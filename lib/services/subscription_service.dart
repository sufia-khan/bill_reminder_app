import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'local_storage_service.dart';
import 'package:async/async.dart';

class SubscriptionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  LocalStorageService? _localStorageService;

  // Sync state management to prevent duplicates
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  Timer? _syncTimer;

  // Initialize local storage
  Future<void> init() async {
    _localStorageService = await LocalStorageService.init();
    final userId = _auth.currentUser?.uid;
    if (userId != null) {
      await _localStorageService?.setUserId(userId);
    }
  }

  // Collection reference
  CollectionReference get _subscriptionsCollection => _firestore
      .collection('users')
      .doc(_auth.currentUser?.uid)
      .collection('subscriptions');

  // Get local storage service for direct access
  LocalStorageService? get localStorageService => _localStorageService;

  // Add a new subscription with BATCHED Firebase sync
  Future<void> addSubscription(Map<String, dynamic> subscription) async {
    // Mark as pending sync and save locally
    subscription['syncPending'] = true;
    subscription['lastModified'] = DateTime.now().toIso8601String();

    await _localStorageService?.saveSubscription(subscription);
    debugPrint('✅ Saved locally and marked for sync');

    // Schedule batch sync instead of immediate sync
    _scheduleBatchSync();
  }

  // Get ONLY Firebase subscriptions (clean data source)
  Future<List<Map<String, dynamic>>> getFirebaseSubscriptionsOnly() async {
    try {
      final online = await isOnline();
      if (!online) {
        debugPrint('Offline: Cannot get Firebase subscriptions');
        return [];
      }

      debugPrint('🌐 Getting Firebase subscriptions only...');
      final querySnapshot = await _subscriptionsCollection
          .orderBy('createdAt', descending: true)
          .get();

      final firebaseSubscriptions = querySnapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        data['firebaseId'] = doc.id;
        data['source'] = 'firebase';
        return data;
      }).toList();

      debugPrint(
        '✅ Got ${firebaseSubscriptions.length} subscriptions from Firebase',
      );
      return firebaseSubscriptions;
    } catch (e) {
      debugPrint('❌ Failed to get Firebase subscriptions: $e');
      return [];
    }
  }

  // Get subscriptions from LOCAL storage only (local-first approach)
  Future<List<Map<String, dynamic>>> getSubscriptions() async {
    try {
      // Get active subscriptions from local storage only
      final localSubscriptions =
          await _localStorageService?.getActiveSubscriptions() ?? [];

      debugPrint(
        '📱 Getting ${localSubscriptions.length} subscriptions from local storage',
      );

      return localSubscriptions.map((sub) {
        sub['source'] = 'local';
        return sub;
      }).toList();
    } catch (e) {
      debugPrint('Failed to get local subscriptions: $e');
      return [];
    }
  }

  // Update a subscription with BATCHED Firebase sync
  Future<void> updateSubscription(
    String? id,
    Map<String, dynamic> subscription,
  ) async {
    if (id == null) {
      throw Exception('Subscription ID is required for update');
    }
    try {
      debugPrint('📱 Updating subscription locally: $id');

      // Mark as pending sync and update locally
      subscription['syncPending'] = true;
      subscription['lastModified'] = DateTime.now().toIso8601String();

      // Try to update in local storage
      try {
        await _localStorageService?.updateSubscription(id, subscription);
        debugPrint(
          '✅ Updated subscription in local storage and marked for sync',
        );
      } catch (e) {
        debugPrint('⚠️ Local storage update failed, trying fallback: $e');

        // If local storage fails, try to update the bill in the list directly
        final subscriptions = await getSubscriptions();
        final index = subscriptions.indexWhere(
          (sub) =>
              sub['id'] == id ||
              sub['localId'] == id ||
              sub['firebaseId'] == id,
        );

        if (index != -1) {
          // Update the subscription in the list
          subscriptions[index] = {...subscriptions[index], ...subscription};
          await _localStorageService?.saveSubscriptions(subscriptions);
          debugPrint('✅ Updated subscription using fallback method');
        } else {
          throw Exception('Subscription not found for update: $id');
        }
      }

      // Schedule batch sync instead of immediate sync
      _scheduleBatchSync();
    } catch (e) {
      debugPrint('❌ Failed to update subscription: $e');
      throw Exception('Failed to update subscription: $e');
    }
  }

  // Delete a subscription with BATCHED Firebase sync
  Future<void> deleteSubscription(String id) async {
    try {
      debugPrint('📱 Deleting subscription locally: $id');

      // Delete locally (which handles marking for sync if needed)
      await _localStorageService?.deleteSubscription(id);
      debugPrint('✅ Deleted subscription in local storage and marked for sync');

      // Schedule batch sync instead of immediate sync
      _scheduleBatchSync();
    } catch (e) {
      debugPrint('❌ Failed to delete subscription: $e');
      throw Exception('Failed to delete subscription: $e');
    }
  }

  // Mark that sync is needed (will be handled by app lifecycle events)
  void _scheduleBatchSync() {
    // Cancel any existing timer-based sync
    _syncTimer?.cancel();

    // Just mark that sync is needed - actual sync will happen on app lifecycle events
    debugPrint(
      '📝 Changes marked for sync (will sync on app background/close)',
    );
  }

  // Perform batch sync (ULTRA-OPTIMIZED for minimal Firestore usage)
  Future<bool> performBatchSync() async {
    try {
      // Prevent multiple syncs running simultaneously
      if (_isSyncing) {
        debugPrint('🔄 Sync already in progress, skipping...');
        return false;
      }

      // Prevent rapid successive syncs (minimum 15 seconds between syncs - reduced from 30)
      if (_lastSyncTime != null) {
        final timeSinceLastSync = DateTime.now().difference(_lastSyncTime!);
        if (timeSinceLastSync.inSeconds < 15) {
          debugPrint(
            '🔄 Sync cooldown active (${timeSinceLastSync.inSeconds}s ago), skipping...',
          );
          return true; // Return true because this isn't an error
        }
      }

      return await syncLocalToFirebase();
    } catch (e) {
      debugPrint('❌ Batch sync scheduling failed: $e');
      return false;
    }
  }

  // Batch sync local subscriptions to Firebase (ULTRA-OPTIMIZED for minimal usage)
  Future<bool> syncLocalToFirebase() async {
    try {
      // Prevent multiple syncs running simultaneously
      if (_isSyncing) {
        debugPrint('🔄 Sync already in progress, skipping...');
        return false;
      }

      // Prevent rapid successive syncs (minimum 15 seconds between syncs)
      if (_lastSyncTime != null) {
        final timeSinceLastSync = DateTime.now().difference(_lastSyncTime!);
        if (timeSinceLastSync.inSeconds < 15) {
          debugPrint(
            '🔄 Sync cooldown active (${timeSinceLastSync.inSeconds}s ago), skipping...',
          );
          return true; // Return true because this isn't an error
        }
      }

      // Check if online first
      if (!await isOnline()) {
        debugPrint('📵 Offline - skipping sync');
        return false;
      }

      final unsyncedSubscriptions =
          await _localStorageService?.getUnsyncedSubscriptions() ?? [];
      final deletedSubscriptions =
          await _localStorageService?.getDeletedSubscriptions() ?? [];

      if (unsyncedSubscriptions.isEmpty && deletedSubscriptions.isEmpty) {
        debugPrint('✅ No changes to sync');
        return true;
      }

      // SMART BATCHING: Only sync if we have enough changes or it's been too long
      final totalChanges = unsyncedSubscriptions.length + deletedSubscriptions.length;
      if (totalChanges < 3) { // Only sync single items if they're old
        final oldestUnsynced = await _localStorageService?.getOldestUnsyncedTime();
        if (oldestUnsynced != null) {
          final age = DateTime.now().difference(oldestUnsynced);
          if (age.inMinutes < 5) {
            debugPrint('⏰ Skipping sync - only $totalChanges recent changes');
            return true;
          }
        }
      }

      // Mark sync as started
      _isSyncing = true;
      debugPrint(
        '🔄 Starting sync: ${unsyncedSubscriptions.length} updates, ${deletedSubscriptions.length} deletions',
      );

      bool hasErrors = false;
      final List<Map<String, dynamic>> successfullySynced = [];

      // Sync updated subscriptions in batch
      final batch = _firestore.batch();

      for (final subscription in unsyncedSubscriptions) {
        try {
          final subscriptionToSync = Map<String, dynamic>.from(subscription);
          final hasFirebaseId =
              subscription.containsKey('firebaseId') &&
              subscription['firebaseId'] != null;

          // Remove local-only fields
          subscriptionToSync.remove('localId');
          subscriptionToSync.remove('source');
          subscriptionToSync.remove('syncPending');
          subscriptionToSync.remove('lastModified');
          subscriptionToSync.remove('lastSynced');

          if (hasFirebaseId) {
            // Update existing document
            final firebaseId = subscription['firebaseId'];
            subscriptionToSync['updatedAt'] = FieldValue.serverTimestamp();
            batch.update(
              _subscriptionsCollection.doc(firebaseId),
              subscriptionToSync,
            );

            successfullySynced.add({
              'localId': subscription['localId'],
              'firebaseId': firebaseId,
            });

            debugPrint('📝 Queued update: ${subscription['name']}');
          } else {
            // DEDUPLICATION CHECK: Look for existing subscription by name and amount
            final existingSubscription = await _findExistingSubscription(
              subscription,
            );
            if (existingSubscription != null) {
              // Found existing subscription, update it instead of creating duplicate
              debugPrint(
                '🔄 Found existing subscription, updating: ${subscription['name']}',
              );
              subscriptionToSync['updatedAt'] = FieldValue.serverTimestamp();
              batch.update(
                _subscriptionsCollection.doc(existingSubscription.id),
                subscriptionToSync,
              );

              successfullySynced.add({
                'localId': subscription['localId'],
                'firebaseId': existingSubscription.id,
              });
            } else {
              // Create new document (no duplicate found)
              subscriptionToSync['createdAt'] = FieldValue.serverTimestamp();
              subscriptionToSync['updatedAt'] = FieldValue.serverTimestamp();
              final docRef = _subscriptionsCollection.doc();
              batch.set(docRef, subscriptionToSync);

              successfullySynced.add({
                'localId': subscription['localId'],
                'firebaseId': docRef.id,
              });

              debugPrint('📝 Queued creation: ${subscription['name']}');
            }
          }
        } catch (e) {
          debugPrint(
            '❌ Failed to prepare subscription ${subscription['name']}: $e',
          );
          hasErrors = true;
        }
      }

      // Handle deletions
      for (final subscription in deletedSubscriptions) {
        try {
          final firebaseId = subscription['firebaseId'];
          batch.delete(_subscriptionsCollection.doc(firebaseId));
          debugPrint('📝 Queued deletion: ${subscription['name']}');
        } catch (e) {
          debugPrint(
            '❌ Failed to prepare deletion ${subscription['name']}: $e',
          );
          hasErrors = true;
        }
      }

      // Commit the batch
      try {
        await batch.commit();
        debugPrint('✅ Batch sync completed successfully');

        // Mark synced items as synced
        if (successfullySynced.isNotEmpty) {
          await _localStorageService?.markBatchAsSynced(successfullySynced);
        }

        // Clean up deleted subscriptions
        final deletedFirebaseIds = deletedSubscriptions
            .map((sub) => sub['firebaseId'] as String)
            .toList();
        if (deletedFirebaseIds.isNotEmpty) {
          await _localStorageService?.cleanupDeletedSubscriptions(
            deletedFirebaseIds,
          );
        }

        // Update last sync time
        await _localStorageService?.setLastSync();

        return !hasErrors;
      } catch (e) {
        debugPrint('❌ Batch commit failed: $e');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Sync failed: $e');
      return false;
    } finally {
      // Always reset sync state
      _isSyncing = false;
      _lastSyncTime = DateTime.now();
      debugPrint('✅ Sync completed, state reset');
    }
  }

  // Find existing subscription to prevent duplicates
  Future<DocumentSnapshot?> _findExistingSubscription(
    Map<String, dynamic> subscription,
  ) async {
    try {
      final name = subscription['name']?.toString().toLowerCase().trim();
      final amount = subscription['amount']?.toString();
      final userId = _auth.currentUser?.uid;

      if (name == null || name.isEmpty || amount == null || userId == null) {
        return null;
      }

      // Look for subscription with same name and amount for this user
      final querySnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('subscriptions')
          .where('name', isEqualTo: subscription['name'])
          .where('amount', isEqualTo: amount)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final existingDoc = querySnapshot.docs.first;
        debugPrint(
          '🔍 Found existing subscription: ${existingDoc.id} - ${existingDoc['name']}',
        );
        return existingDoc;
      }

      return null;
    } catch (e) {
      debugPrint('❌ Error checking for existing subscription: $e');
      return null;
    }
  }

  // Check if user is online with MOBILE-FRIENDLY connectivity detection
  Future<bool> isOnline() async {
    try {
      debugPrint('🌐 [isOnline] Starting connectivity check...');

      // First check basic network connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      debugPrint('🌐 [isOnline] Connectivity result: $connectivityResult');

      if (connectivityResult == ConnectivityResult.none) {
        debugPrint('🌐 [isOnline] No network connectivity detected');
        return false;
      }

      // MOBILE FRIENDLY: Use longer timeout for mobile networks
      final timeout = const Duration(
        seconds: 5,
      ); // Increased timeout for mobile

      // Try 1: Quick auth check (fastest)
      try {
        debugPrint('🌐 [isOnline] Testing auth connectivity...');
        final user = _auth.currentUser;
        if (user != null) {
          await user.getIdToken(true).timeout(timeout);
          debugPrint('✅ [isOnline] Auth connectivity confirmed');
          return true;
        } else {
          debugPrint('🌐 [isOnline] No user logged in, checking Firebase...');
        }
      } catch (e) {
        debugPrint('🌐 [isOnline] Auth connectivity test failed: $e');
      }

      // Try 2: More reliable Firebase operation
      try {
        debugPrint('🌐 [isOnline] Testing Firebase connectivity...');
        await _firestore.collection('users').limit(1).get().timeout(timeout);
        debugPrint('✅ [isOnline] Firebase connectivity confirmed');
        return true;
      } catch (e) {
        debugPrint('🌐 [isOnline] Firebase connectivity test failed: $e');

        // Try alternative connectivity check - but be more conservative
        try {
          debugPrint('🌐 [isOnline] Testing alternative connectivity...');
          // Try a simple ping to a reliable endpoint
          final user = _auth.currentUser;
          if (user != null) {
            // Try to refresh token to confirm actual connectivity
            await user.getIdToken(true).timeout(const Duration(seconds: 3));
            debugPrint('✅ [isOnline] Auth connectivity confirmed - actually online');
            return true;
          } else {
            debugPrint('🌐 [isOnline] No user available for connectivity check');
          }
        } catch (authCheckError) {
          debugPrint(
            '🌐 [isOnline] Alternative connectivity check failed: $authCheckError',
          );
        }

        debugPrint('🌐 [isOnline] All connectivity checks failed, returning false');
        return false;
      }
    } catch (e) {
      debugPrint('🌐 [isOnline] Network check failed with exception: $e');
      return false;
    }
  }

  // Enhanced stream for connectivity changes with immediate updates
  Stream<bool> connectivityStream() async* {
    final connectivity = Connectivity();
    bool lastState = false;

    await for (final result in connectivity.onConnectivityChanged) {
      if (result == ConnectivityResult.none) {
        lastState = false;
        yield false;
      } else {
        // For immediate feedback, yield true quickly first, then verify
        yield true;

        // Then verify actual internet connectivity
        final isActuallyOnline = await isOnline();

        // Only emit if state changed
        if (isActuallyOnline != lastState) {
          lastState = isActuallyOnline;
          yield isActuallyOnline;
        }
      }
    }
  }

  // Get ONLY local subscriptions (no Firebase call)
  Future<List<Map<String, dynamic>>> getLocalSubscriptions() async {
    debugPrint('🗂️ Getting subscriptions from local storage only');
    final localSubscriptions =
        await _localStorageService?.getSubscriptions() ?? [];
    debugPrint('📱 Found ${localSubscriptions.length} local subscriptions');
    return localSubscriptions.map((sub) {
      sub['source'] = 'local';
      return sub;
    }).toList();
  }

  // Get count of unsynced subscriptions (for optimization)
  Future<int> getUnsyncedSubscriptionsCount() async {
    final unsynced =
        await _localStorageService?.getUnsyncedSubscriptions() ?? [];
    return unsynced.length;
  }

  // Check if we should sync with Firebase (ULTRA-OPTIMIZED for minimal usage)
  Future<bool> shouldSyncWithFirebase() async {
    // Don't sync if offline
    if (!await isOnline()) {
      return false;
    }

    final unsyncedCount = await getUnsyncedSubscriptionsCount();
    if (unsyncedCount == 0) {
      return false; // No changes to sync
    }

    final lastSync = _localStorageService?.getLastSync();
    if (lastSync == null) {
      debugPrint('🆕 First sync needed - ${unsyncedCount} items');
      return true;
    }

    final timeSinceLastSync = DateTime.now().difference(lastSync);

    // SMART BATCHING: Only sync based on urgency and batch size
    if (unsyncedCount >= 5) {
      // Large batch - sync immediately (every 30 seconds)
      if (timeSinceLastSync.inSeconds >= 30) {
        debugPrint('📦 Large batch sync (${unsyncedCount} items, ${timeSinceLastSync.inSeconds}s ago)');
        return true;
      }
    } else if (unsyncedCount >= 3) {
      // Medium batch - sync every 2 minutes
      if (timeSinceLastSync.inMinutes >= 2) {
        debugPrint('📦 Medium batch sync (${unsyncedCount} items, ${timeSinceLastSync.inMinutes}m ago)');
        return true;
      }
    } else {
      // Small batch - sync every 10 minutes
      if (timeSinceLastSync.inMinutes >= 10) {
        debugPrint('📦 Small batch sync (${unsyncedCount} items, ${timeSinceLastSync.inMinutes}m ago)');
        return true;
      }
    }

    // Emergency sync if items are too old (older than 1 hour)
    final oldestUnsynced = await _localStorageService?.getOldestUnsyncedTime();
    if (oldestUnsynced != null) {
      final age = DateTime.now().difference(oldestUnsynced);
      if (age.inMinutes >= 60) {
        debugPrint('🚨 Emergency sync - items are ${age.inMinutes}m old');
        return true;
      }
    }

    return false;
  }

  // Get sync status
  String getSyncStatus() {
    final lastSync = _localStorageService?.getLastSync();
    if (lastSync == null) {
      return 'Never synced';
    }

    final now = DateTime.now();
    final difference = now.difference(lastSync);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours} hours ago';
    } else {
      return '${difference.inDays} days ago';
    }
  }

  // Get detailed connectivity status for UI
  Future<Map<String, dynamic>> getDetailedConnectivityStatus() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final hasInternet = await isOnline();

      return {
        'isOnline': hasInternet,
        'connectivityType': connectivityResult.toString().split('.').last,
        'hasInternet': hasInternet,
        'lastSync': getSyncStatus(),
      };
    } catch (e) {
      return {
        'isOnline': false,
        'connectivityType': 'none',
        'hasInternet': false,
        'lastSync': getSyncStatus(),
        'error': e.toString(),
      };
    }
  }

  // Stream for real-time updates
  Stream<List<Map<String, dynamic>>> subscriptionsStream() {
    return _subscriptionsCollection
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            data['id'] = doc.id;
            data['firebaseId'] = doc.id;
            data['source'] = 'firebase';
            return data;
          }).toList(),
        );
  }

  // Clear local data (for logout)
  Future<void> clearLocalData() async {
    await _localStorageService?.clearAll();
  }

  // Import Firestore data into local storage (merge, avoid duplicates)
  Future<void> importFirestoreToLocal(
    List<Map<String, dynamic>> firestoreData,
  ) async {
    try {
      debugPrint('🔄 [importFirestoreToLocal] Starting import of ${firestoreData.length} documents...');

      if (_localStorageService == null) {
        debugPrint('❌ [importFirestoreToLocal] Local storage service is null');
        return;
      }

      // Load current local subscriptions once
      debugPrint('🔄 [importFirestoreToLocal] Loading current local subscriptions...');
      final localSubscriptions = await getLocalSubscriptions();
      debugPrint('🔄 [importFirestoreToLocal] Found ${localSubscriptions.length} existing local subscriptions');

      // Build lookup for existing firebaseIds
      final existingIds = <String>{};
      for (final sub in localSubscriptions) {
        final fid = sub['firebaseId']?.toString();
        if (fid != null && fid.isNotEmpty) {
          existingIds.add(fid);
          debugPrint('🔄 [importFirestoreToLocal] Existing firebaseId: $fid (${sub['name']})');
        }
      }

      // Only add missing firestore docs to local list
      final List<Map<String, dynamic>> toAdd = [];
      for (int i = 0; i < firestoreData.length; i++) {
        final doc = firestoreData[i];
        final fid = doc['firebaseId']?.toString() ?? doc['id']?.toString();

        debugPrint('🔄 [importFirestoreToLocal] Processing doc $i: ${doc['name']} (ID: $fid)');

        if (fid == null || fid.isEmpty) {
          debugPrint('⚠️ [importFirestoreToLocal] Skipping doc $i - no valid ID');
          continue;
        }

        if (existingIds.contains(fid)) {
          debugPrint('✅ [importFirestoreToLocal] Doc $i already exists locally, skipping');
          continue;
        }

        final item = _convertTimestampsForLocalStorage(doc);
        // Use firebaseId as localId to avoid extra local-only ids and to keep dedup stable
        item['localId'] = fid;
        item['firebaseId'] = fid;
        item['syncPending'] = false; // already from server
        item['source'] = 'firebase';
        item['lastSynced'] = DateTime.now().toIso8601String();
        toAdd.add(item);

        debugPrint('📝 [importFirestoreToLocal] Added to import list: ${item['name']} (localId: $fid)');
      }

      debugPrint('🔄 [importFirestoreToLocal] Total items to import: ${toAdd.length}');

      if (toAdd.isNotEmpty) {
        // Append to local subscriptions and save once
        final merged = List<Map<String, dynamic>>.from(localSubscriptions);
        merged.addAll(toAdd);

        debugPrint('💾 [importFirestoreToLocal] saving ${merged.length} subscriptions to local storage...');
        await _localStorageService?.saveSubscriptions(merged);
        debugPrint(
          '✅ [importFirestoreToLocal] Successfully imported ${toAdd.length} Firestore subscriptions into local storage',
        );

        // Log the imported items
        for (int i = 0; i < toAdd.length; i++) {
          final item = toAdd[i];
          debugPrint('📋 [importFirestoreToLocal] Imported item $i: ${item['name']} (ID: ${item['firebaseId']})');
        }
      } else {
        debugPrint('✅ [importFirestoreToLocal] No new Firestore subscriptions to import');
      }
    } catch (e) {
      debugPrint('❌ [importFirestoreToLocal] Failed to import Firestore data to local: $e');
    }
  }

  // Convert Firestore Timestamp objects to ISO strings for local storage
  Map<String, dynamic> _convertTimestampsForLocalStorage(Map<String, dynamic> doc) {
    final convertedDoc = Map<String, dynamic>.from(doc);

    // Convert Timestamp fields to ISO strings
    final timestampFields = ['createdAt', 'updatedAt', 'lastModified', 'dueDate', 'paidDate'];

    for (final field in timestampFields) {
      if (convertedDoc[field] != null) {
        if (convertedDoc[field] is DateTime) {
          convertedDoc[field] = (convertedDoc[field] as DateTime).toIso8601String();
        } else if (convertedDoc[field] is Timestamp) {
          // Handle Firestore Timestamp objects
          try {
            final timestamp = convertedDoc[field] as Timestamp;
            convertedDoc[field] = timestamp.toDate().toIso8601String();
            debugPrint('🔄 [convertTimestamps] Converted $field Timestamp to ISO string');
          } catch (e) {
            debugPrint('⚠️ [convertTimestamps] Failed to convert Timestamp field $field: $e');
            convertedDoc[field] = DateTime.now().toIso8601String();
          }
        }
      }
    }

    return convertedDoc;
  }

  // Periodic sync method - can be called by app lifecycle events
  Future<void> performPeriodicSync() async {
    try {
      if (await shouldSyncWithFirebase()) {
        debugPrint('🔄 Performing periodic sync...');
        await syncLocalToFirebase();
      }
    } catch (e) {
      debugPrint('❌ Periodic sync failed: $e');
    }
  }

  // Clean up duplicate subscriptions in Firestore
  Future<int> cleanupDuplicateSubscriptions() async {
    try {
      if (!await isOnline()) {
        debugPrint('📵 Offline - cannot cleanup duplicates');
        return 0;
      }

      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        debugPrint('❌ No user logged in');
        return 0;
      }

      debugPrint('🧹 Starting duplicate cleanup...');

      // Get all subscriptions from Firestore
      final querySnapshot = await _subscriptionsCollection.get();
      final allSubscriptions = querySnapshot.docs;

      // Group subscriptions by name and amount to find duplicates
      final Map<String, List<DocumentSnapshot>> groupedSubscriptions = {};

      for (final doc in allSubscriptions) {
        final data = doc.data() as Map<String, dynamic>;
        final name = data['name']?.toString().toLowerCase().trim() ?? '';
        final amount = data['amount']?.toString() ?? '';
        final key = '$name|$amount';

        if (key.isNotEmpty && key != '|') {
          if (!groupedSubscriptions.containsKey(key)) {
            groupedSubscriptions[key] = [];
          }
          groupedSubscriptions[key]!.add(doc);
        }
      }

      // Find and remove duplicates (keep the oldest one)
      int duplicatesRemoved = 0;
      final batch = _firestore.batch();

      for (final entry in groupedSubscriptions.entries) {
        if (entry.value.length > 1) {
          // Sort by creation time (oldest first)
          entry.value.sort((a, b) {
            final aTime = a['createdAt'] as Timestamp?;
            final bTime = b['createdAt'] as Timestamp?;
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return aTime.compareTo(bTime);
          });

          // Keep the oldest, delete the rest
          for (int i = 1; i < entry.value.length; i++) {
            final duplicateDoc = entry.value[i];
            batch.delete(duplicateDoc.reference);
            duplicatesRemoved++;
            debugPrint(
              '🗑️ Marked duplicate for deletion: ${duplicateDoc['name']} (ID: ${duplicateDoc.id})',
            );
          }
        }
      }

      if (duplicatesRemoved > 0) {
        await batch.commit();
        debugPrint('✅ Cleaned up $duplicatesRemoved duplicate subscriptions');
      } else {
        debugPrint('✅ No duplicates found');
      }

      return duplicatesRemoved;
    } catch (e) {
      debugPrint('❌ Failed to cleanup duplicates: $e');
      return 0;
    }
  }

  // Trigger sync on app resume/focus
  Future<void> syncOnAppResume() async {
    try {
      // Only sync if we've been offline for a while or have pending changes
      final unsyncedCount = await getUnsyncedSubscriptionsCount();
      if (unsyncedCount > 0) {
        debugPrint('🔄 Syncing on app resume ($unsyncedCount pending changes)');
        await syncLocalToFirebase();
      }
    } catch (e) {
      debugPrint('❌ Resume sync failed: $e');
    }
  }

  // Trigger sync when app goes to background or is closed
  Future<void> syncOnAppBackground() async {
    try {
      final unsyncedCount = await getUnsyncedSubscriptionsCount();
      if (unsyncedCount > 0) {
        debugPrint(
          '🔄 Syncing on app background ($unsyncedCount pending changes)',
        );
        await syncLocalToFirebase();
      }
    } catch (e) {
      debugPrint('❌ Background sync failed: $e');
    }
  }

  // =========================================================================
  // ULTRA-OPTIMIZED LOCAL-FIRST OPERATIONS
  // These methods provide immediate UI feedback with minimal Firestore usage
  // =========================================================================

  // Ultra-optimized add: Local first, immediate UI feedback, smart batching
  Future<void> addSubscriptionOptimized(Map<String, dynamic> subscription) async {
    debugPrint('⚡ OPTIMIZED ADD: Starting local-first operation');

    // Prepare for local storage
    final localSubscription = Map<String, dynamic>.from(subscription);
    localSubscription['localId'] = DateTime.now().millisecondsSinceEpoch.toString();
    localSubscription['firebaseId'] = null; // Will be set on sync
    localSubscription['syncPending'] = true;
    localSubscription['lastModified'] = DateTime.now().toIso8601String();
    localSubscription['source'] = 'local';
    localSubscription['lastSynced'] = null;

    // Save locally first (immediate)
    await _localStorageService?.saveSubscription(localSubscription);
    debugPrint('✅ OPTIMIZED ADD: Saved locally immediately');

    // Smart sync scheduling (ultra-aggressive batching)
    unawaited(_scheduleSmartSync());
  }

  // Ultra-optimized update: Local first, immediate UI feedback, smart batching
  Future<void> updateSubscriptionOptimized(String? id, Map<String, dynamic> subscription) async {
    if (id == null) {
      throw Exception('Subscription ID is required for update');
    }

    debugPrint('⚡ OPTIMIZED UPDATE: Starting local-first operation for $id');

    // Prepare update data
    final updateData = Map<String, dynamic>.from(subscription);
    updateData['syncPending'] = true;
    updateData['lastModified'] = DateTime.now().toIso8601String();

    // Update locally first (immediate)
    try {
      await _localStorageService?.updateSubscription(id, updateData);
      debugPrint('✅ OPTIMIZED UPDATE: Updated locally immediately');
    } catch (e) {
      debugPrint('⚠️ OPTIMIZED UPDATE: Local update failed, trying fallback: $e');

      // Fallback: reload, update, and save
      final subscriptions = await getSubscriptions();
      final index = subscriptions.indexWhere(
        (sub) => sub['localId'] == id || sub['firebaseId'] == id,
      );

      if (index != -1) {
        subscriptions[index] = {...subscriptions[index], ...updateData};
        await _localStorageService?.saveSubscriptions(subscriptions);
        debugPrint('✅ OPTIMIZED UPDATE: Fallback update successful');
      } else {
        throw Exception('Subscription not found for update: $id');
      }
    }

    // Smart sync scheduling (ultra-aggressive batching)
    unawaited(_scheduleSmartSync());
  }

  // Ultra-optimized mark as paid: Local first, immediate UI feedback, smart batching
  Future<void> markAsPaidOptimized(String id) async {
    debugPrint('⚡ OPTIMIZED MARK PAID: Starting local-first operation for $id');

    // Get current subscription
    final subscriptions = await getSubscriptions();
    final index = subscriptions.indexWhere(
      (sub) => sub['localId'] == id || sub['firebaseId'] == id,
    );

    if (index == -1) {
      throw Exception('Subscription not found: $id');
    }

    // Update locally first (immediate)
    final subscription = subscriptions[index];
    subscription['isPaid'] = true;
    subscription['paidDate'] = DateTime.now().toIso8601String();
    subscription['syncPending'] = true;
    subscription['lastModified'] = DateTime.now().toIso8601String();

    await _localStorageService?.saveSubscriptions(subscriptions);
    debugPrint('✅ OPTIMIZED MARK PAID: Updated locally immediately');

    // Smart sync scheduling (ultra-aggressive batching)
    unawaited(_scheduleSmartSync());
  }

  // Ultra-optimized delete: Local first, immediate UI feedback, smart batching
  Future<void> deleteSubscriptionOptimized(String id) async {
    debugPrint('⚡ OPTIMIZED DELETE: Starting local-first operation for $id');

    // Delete locally first (immediate)
    await _localStorageService?.deleteSubscription(id);
    debugPrint('✅ OPTIMIZED DELETE: Deleted locally immediately');

    // Smart sync scheduling (ultra-aggressive batching)
    unawaited(_scheduleSmartSync());
  }

  // Ultra-optimized smart sync scheduling (aggressive batching)
  Future<void> _scheduleSmartSync() async {
    // Cancel any existing timer
    _syncTimer?.cancel();

    final unsyncedCount = await getUnsyncedSubscriptionsCount();

    // Smart scheduling based on batch size
    Duration delay;
    if (unsyncedCount >= 5) {
      delay = const Duration(seconds: 30); // Large batches sync quickly
    } else if (unsyncedCount >= 3) {
      delay = const Duration(minutes: 1); // Medium batches wait 1 minute
    } else {
      delay = const Duration(minutes: 5); // Small batches wait 5 minutes
    }

    debugPrint('⏰ SMART SYNC: Scheduled in ${delay.inSeconds}s (batch size: $unsyncedCount)');

    _syncTimer = Timer(delay, () async {
      debugPrint('⏰ SMART SYNC: Executing scheduled sync');
      await performBatchSync();
    });
  }

  // Ultra-optimized get subscriptions with intelligent caching
  Future<List<Map<String, dynamic>>> getSubscriptionsOptimized() async {
    debugPrint('📊 OPTIMIZED GET: Using intelligent caching');

    // Always try local first (immediate response)
    final localSubscriptions = await getSubscriptions();

    // Check if we need to refresh from Firestore (smart caching)
    final shouldRefresh = await _shouldRefreshFromFirestore();

    if (shouldRefresh) {
      debugPrint('🔄 OPTIMIZED GET: Smart refresh needed');
      unawaited(_refreshFromFirestoreOptimized());
    }

    return localSubscriptions;
  }

  // Smart refresh logic (minimal Firestore reads)
  Future<bool> _shouldRefreshFromFirestore() async {
    final lastRefresh = await _localStorageService?.getLastFirestoreRefresh();

    if (lastRefresh == null) {
      debugPrint('🆕 OPTIMIZED: First time, need refresh');
      return true;
    }

    final timeSinceRefresh = DateTime.now().difference(lastRefresh);

    // Smart refresh intervals based on usage patterns
    if (timeSinceRefresh.inMinutes >= 60) { // 1 hour minimum
      debugPrint('🔄 OPTIMIZED: Refresh needed (${timeSinceRefresh.inMinutes}m old)');
      return true;
    }

    // Check if we have local data
    final localCount = (await getSubscriptions()).length;
    if (localCount == 0 && timeSinceRefresh.inMinutes >= 5) {
      debugPrint('🔄 OPTIMIZED: No local data, refresh needed');
      return true;
    }

    return false;
  }

  // Ultra-optimized Firestore refresh (minimal reads)
  Future<void> _refreshFromFirestoreOptimized() async {
    if (!await isOnline()) {
      debugPrint('📵 OPTIMIZED REFRESH: Offline, skipping');
      return;
    }

    try {
      debugPrint('🔄 OPTIMIZED REFRESH: Starting minimal refresh');

      // Get only the most recent document to check for updates
      final recentDocs = await _subscriptionsCollection
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (recentDocs.docs.isEmpty) {
        debugPrint('📭 OPTIMIZED REFRESH: No documents in Firestore');
        await _localStorageService?.setLastFirestoreRefresh();
        return;
      }

      final mostRecent = recentDocs.docs.first;
      final mostRecentTime = (mostRecent['createdAt'] as Timestamp).toDate();
      final lastRefresh = await _localStorageService?.getLastFirestoreRefresh();

      // Only fetch full data if there are newer documents
      if (lastRefresh == null || mostRecentTime.isAfter(lastRefresh)) {
        debugPrint('🆕 OPTIMIZED REFRESH: New data found, fetching full sync');
        final firestoreData = await getFirebaseSubscriptionsOnly();
        await importFirestoreToLocal(firestoreData);
      } else {
        debugPrint('✅ OPTIMIZED REFRESH: No new data, skipping fetch');
      }

      await _localStorageService?.setLastFirestoreRefresh();
    } catch (e) {
      debugPrint('❌ OPTIMIZED REFRESH failed: $e');
    }
  }
}
