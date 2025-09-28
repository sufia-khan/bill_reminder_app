import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'local_storage_service.dart';

class SubscriptionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  LocalStorageService? _localStorageService;

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

      debugPrint('🔄 Syncing ${unsyncedSubscriptions.length} updates and ${deletedSubscriptions.length} deletions');

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
            // Create new document
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