import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'local_storage_service.dart';

class SubscriptionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  LocalStorageService? _localStorageService;

  // Sync state management to prevent duplicates
  bool _isSyncing = false;
  DateTime? _lastSyncTime;

  // Initialize local storage
  Future<void> init() async {
    _localStorageService = await LocalStorageService.init();
    final userId = _auth.currentUser?.uid;
    if (userId != null) {
      await _localStorageService?.setUserId(userId);
    }
  }

  // Collection reference
  CollectionReference get _subscriptionsCollection =>
      _firestore.collection('users').doc(_auth.currentUser?.uid).collection('subscriptions');

  // Get local storage service for direct access
  LocalStorageService? get localStorageService => _localStorageService;

  // Add a new subscription with LOCAL-FIRST approach
  Future<void> addSubscription(Map<String, dynamic> subscription) async {
    // Save locally first (immediate UI response)
    await _localStorageService?.saveSubscription(subscription);
    debugPrint('✅ Saved locally - operation complete for UI');

    // No immediate Firebase sync - will be handled by batch sync
    debugPrint('📝 Queued for sync - will sync in batch when online');
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

      debugPrint('✅ Got ${firebaseSubscriptions.length} subscriptions from Firebase');
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
      final localSubscriptions = await _localStorageService?.getActiveSubscriptions() ?? [];

      debugPrint('📱 Getting ${localSubscriptions.length} subscriptions from local storage');

      return localSubscriptions.map((sub) {
        sub['source'] = 'local';
        return sub;
      }).toList();
    } catch (e) {
      debugPrint('Failed to get local subscriptions: $e');
      return [];
    }
  }

  // Update a subscription with LOCAL-FIRST approach
  Future<void> updateSubscription(String id, Map<String, dynamic> subscription) async {
    try {
      debugPrint('📱 Updating subscription locally: $id');

      // Always update locally first
      await _localStorageService?.updateSubscription(id, subscription);
      debugPrint('✅ Updated subscription in local storage');

      // No immediate Firebase sync - will be handled by batch sync
      debugPrint('📝 Update queued for sync');

    } catch (e) {
      debugPrint('❌ Failed to update subscription: $e');
      throw Exception('Failed to update subscription: $e');
    }
  }

  // Delete a subscription with LOCAL-FIRST approach
  Future<void> deleteSubscription(String id) async {
    try {
      debugPrint('📱 Deleting subscription locally: $id');

      // Delete locally first
      await _localStorageService?.deleteSubscription(id);
      debugPrint('✅ Deleted subscription in local storage');

      // No immediate Firebase sync - will be handled by batch sync
      debugPrint('📝 Deletion queued for sync');

    } catch (e) {
      debugPrint('❌ Failed to delete subscription: $e');
      throw Exception('Failed to delete subscription: $e');
    }
  }

  // Batch sync local subscriptions to Firebase (optimized for reduced usage)
  Future<bool> syncLocalToFirebase() async {
    try {
      // Prevent multiple syncs running simultaneously
      if (_isSyncing) {
        debugPrint('🔄 Sync already in progress, skipping...');
        return false;
      }

      // Prevent rapid successive syncs (minimum 30 seconds between syncs)
      if (_lastSyncTime != null) {
        final timeSinceLastSync = DateTime.now().difference(_lastSyncTime!);
        if (timeSinceLastSync.inSeconds < 30) {
          debugPrint('🔄 Sync cooldown active (${timeSinceLastSync.inSeconds}s ago), skipping...');
          return true; // Return true because this isn't an error
        }
      }

      // Check if online first
      if (!await isOnline()) {
        debugPrint('📵 Offline - skipping sync');
        return false;
      }

      final unsyncedSubscriptions = await _localStorageService?.getUnsyncedSubscriptions() ?? [];
      final deletedSubscriptions = await _localStorageService?.getDeletedSubscriptions() ?? [];

      if (unsyncedSubscriptions.isEmpty && deletedSubscriptions.isEmpty) {
        debugPrint('✅ No changes to sync');
        return true;
      }

      // Mark sync as started
      _isSyncing = true;
      debugPrint('🔄 Starting sync: ${unsyncedSubscriptions.length} updates, ${deletedSubscriptions.length} deletions');

      bool hasErrors = false;
      final List<Map<String, dynamic>> successfullySynced = [];

      // Sync updated subscriptions in batch
      final batch = _firestore.batch();

      for (final subscription in unsyncedSubscriptions) {
        try {
          final subscriptionToSync = Map<String, dynamic>.from(subscription);
          final hasFirebaseId = subscription.containsKey('firebaseId') && subscription['firebaseId'] != null;

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
            batch.update(_subscriptionsCollection.doc(firebaseId), subscriptionToSync);

            successfullySynced.add({
              'localId': subscription['localId'],
              'firebaseId': firebaseId,
            });

            debugPrint('📝 Queued update: ${subscription['name']}');
          } else {
            // DEDUPLICATION CHECK: Look for existing subscription by name and amount
            final existingSubscription = await _findExistingSubscription(subscription);
            if (existingSubscription != null) {
              // Found existing subscription, update it instead of creating duplicate
              debugPrint('🔄 Found existing subscription, updating: ${subscription['name']}');
              subscriptionToSync['updatedAt'] = FieldValue.serverTimestamp();
              batch.update(_subscriptionsCollection.doc(existingSubscription.id), subscriptionToSync);

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
          debugPrint('❌ Failed to prepare subscription ${subscription['name']}: $e');
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
          debugPrint('❌ Failed to prepare deletion ${subscription['name']}: $e');
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
          await _localStorageService?.cleanupDeletedSubscriptions(deletedFirebaseIds);
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
  Future<DocumentSnapshot?> _findExistingSubscription(Map<String, dynamic> subscription) async {
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
        debugPrint('🔍 Found existing subscription: ${existingDoc.id} - ${existingDoc['name']}');
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
      // First check basic network connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      debugPrint('📱 MOBILE DEBUG: Connectivity result: $connectivityResult');

      if (connectivityResult == ConnectivityResult.none) {
        debugPrint('📱 MOBILE DEBUG: No network connectivity detected');
        return false;
      }

      // MOBILE FRIENDLY: Use longer timeout for mobile networks
      final timeout = const Duration(seconds: 5); // Increased timeout for mobile

      // Try 1: Quick auth check (fastest)
      try {
        final user = _auth.currentUser;
        if (user != null) {
          await user.getIdToken(true).timeout(timeout);
          debugPrint('✅ Auth connectivity confirmed');
          return true;
        }
      } catch (e) {
        debugPrint('📱 MOBILE DEBUG: Auth connectivity test failed: $e');
      }

      // Try 2: Lightweight Firebase operation
      try {
        await _firestore.collection('users').limit(1).get().timeout(timeout);
        debugPrint('✅ Firebase connectivity confirmed');
        return true;
      } catch (e) {
        debugPrint('📱 MOBILE DEBUG: Firebase connectivity test failed: $e');

        // MOBILE FRIENDLY: Try alternative connectivity check
        try {
          // Try a different approach - check if we can reach Firebase auth
          final user = _auth.currentUser;
          if (user != null) {
            // Just check if user exists (no network call)
            debugPrint('✅ Basic auth check passed - assuming online');
            return true;
          }
        } catch (authCheckError) {
          debugPrint('📱 MOBILE DEBUG: Basic auth check failed: $authCheckError');
        }

        return false;
      }
    } catch (e) {
      debugPrint('📱 MOBILE DEBUG: Network check failed: $e');
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
    final localSubscriptions = await _localStorageService?.getSubscriptions() ?? [];
    debugPrint('📱 Found ${localSubscriptions.length} local subscriptions');
    return localSubscriptions.map((sub) {
      sub['source'] = 'local';
      return sub;
    }).toList();
  }

  // Get count of unsynced subscriptions (for optimization)
  Future<int> getUnsyncedSubscriptionsCount() async {
    final unsynced = await _localStorageService?.getUnsyncedSubscriptions() ?? [];
    return unsynced.length;
  }

  // Check if we should sync with Firebase (smart sync) - OPTIMIZED for reduced usage
  Future<bool> shouldSyncWithFirebase() async {
    // Don't sync if offline
    if (!await isOnline()) {
      return false;
    }

    // Sync if there are unsynced items (but less frequently)
    if (await getUnsyncedSubscriptionsCount() > 0) {
      final lastSync = _localStorageService?.getLastSync();
      if (lastSync == null) {
        debugPrint('🆕 First sync needed');
        return true;
      }

      final timeSinceLastSync = DateTime.now().difference(lastSync);
      // Sync every 5 minutes instead of immediately
      if (timeSinceLastSync.inMinutes >= 5) {
        debugPrint('🔄 Unsynced items and time to sync (${timeSinceLastSync.inMinutes} minutes)');
        return true;
      }
    }

    // Periodic sync every 30 minutes (reduced from 15 for less usage)
    final lastSync = _localStorageService?.getLastSync();
    if (lastSync != null) {
      final timeSinceLastSync = DateTime.now().difference(lastSync);
      if (timeSinceLastSync.inMinutes >= 30) {
        debugPrint('⏰ Periodic sync needed (${timeSinceLastSync.inMinutes} minutes)');
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
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              data['id'] = doc.id;
              data['firebaseId'] = doc.id;
              data['source'] = 'firebase';
              return data;
            }).toList());
  }

  // Clear local data (for logout)
  Future<void> clearLocalData() async {
    await _localStorageService?.clearAll();
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
            debugPrint('🗑️ Marked duplicate for deletion: ${duplicateDoc['name']} (ID: ${duplicateDoc.id})');
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
}