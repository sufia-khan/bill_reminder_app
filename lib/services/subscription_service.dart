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

  // Add a new subscription with offline support - OPTIMIZED for cross-device access
  Future<void> addSubscription(Map<String, dynamic> subscription) async {
    // ALWAYS save locally first (immediate UI response)
    await _localStorageService?.saveSubscription(subscription);
    debugPrint('✅ Saved locally first');

    // THEN try to sync with Firebase if online (for cross-device access)
    final online = await isOnline();
    if (online) {
      try {
        debugPrint('🌐 Online, attempting Firebase sync for cross-device access...');

        final subscriptionForFirebase = Map<String, dynamic>.from(subscription);
        subscriptionForFirebase['createdAt'] = FieldValue.serverTimestamp();
        subscriptionForFirebase['updatedAt'] = FieldValue.serverTimestamp();
        subscriptionForFirebase.remove('localId'); // Don't store local ID in Firebase
        subscriptionForFirebase.remove('source'); // Don't store source in Firebase

        final docRef = await _subscriptionsCollection.add(subscriptionForFirebase);

        // Update local copy with Firebase ID for future sync
        subscription['firebaseId'] = docRef.id;
        subscription['id'] = docRef.id;
        await _localStorageService?.updateSubscription(subscription['localId'], subscription);

        await _localStorageService?.setLastSync();
        debugPrint('✅ Successfully synced to Firebase - available on other devices!');

      } catch (e) {
        debugPrint('⚠️ Firebase sync failed, but saved locally: $e');
        // Data is safe locally, just not available on other devices yet
        throw Exception('Saved locally. Will sync to cloud when online.');
      }
    } else {
      debugPrint('📵 Offline - saved locally only. Will sync when online for cross-device access.');
      throw Exception('Offline mode: Saved locally. Will sync when online for other devices.');
    }
  }

  // Get subscriptions from Firebase and merge with local
  Future<List<Map<String, dynamic>>> getSubscriptions() async {
    try {
      List<Map<String, dynamic>> allSubscriptions = [];

      // Check connectivity to avoid unnecessary Firebase reads
      final online = await isOnline();

      if (online) {
        // Try to get from Firebase
        try {
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

          allSubscriptions.addAll(firebaseSubscriptions);
        } catch (e) {
          debugPrint('Failed to get Firebase subscriptions: $e');
        }
      } else {
        debugPrint('Offline detected: skipping Firebase read in getSubscriptions');
      }

      // Get local subscriptions that aren't synced
      final localSubscriptions = await _localStorageService?.getSubscriptions() ?? [];
      final unsyncedSubscriptions = localSubscriptions.where((local) =>
        !allSubscriptions.any((firebase) =>
          firebase['name'] == local['name'] &&
          firebase['dueDate'] == local['dueDate']
        )
      ).map((sub) {
        sub['source'] = 'local';
        return sub;
      }).toList();

      allSubscriptions.addAll(unsyncedSubscriptions);

      // Sort by creation date
      allSubscriptions.sort((a, b) {
        final aDate = a['createdAt'] is Timestamp ? (a['createdAt'] as Timestamp).toDate() : DateTime.now();
        final bDate = b['createdAt'] is Timestamp ? (b['createdAt'] as Timestamp).toDate() : DateTime.now();
        return bDate.compareTo(aDate);
      });

      return allSubscriptions;
    } catch (e) {
      // If everything fails, return only local subscriptions
      debugPrint('All sources failed, returning local only: $e');
      final localSubscriptions = await _localStorageService?.getSubscriptions() ?? [];
      return localSubscriptions.map((sub) {
        sub['source'] = 'local';
        return sub;
      }).toList();
    }
  }

  // Update a subscription with MOBILE debugging
  Future<void> updateSubscription(String id, Map<String, dynamic> subscription) async {
    try {
      subscription['updatedAt'] = FieldValue.serverTimestamp();

      // MOBILE DEBUG: Print detailed information
      debugPrint('📱 MOBILE DEBUG: Updating subscription');
      debugPrint('📱 MOBILE DEBUG: Input ID: $id');
      debugPrint('📱 MOBILE DEBUG: ID type: ${id.startsWith('sub_') || id.length > 20 ? 'Firebase ID' : 'Local ID'}');
      debugPrint('📱 MOBILE DEBUG: Subscription keys: ${subscription.keys.toList()}');

      // Determine if this is a Firebase ID or local ID
      String? firebaseId;
      String? localId;

      if (id.startsWith('sub_') || id.length > 20) {
        // Likely a Firebase ID
        firebaseId = id;
        debugPrint('📱 MOBILE DEBUG: Identified as Firebase ID: $firebaseId');
      } else {
        // Likely a local ID, need to find the corresponding Firebase ID
        debugPrint('📱 MOBILE DEBUG: Looking up Firebase ID for local ID: $id');
        final subscriptions = await _localStorageService?.getSubscriptions();
        final localSub = subscriptions?.firstWhere(
          (sub) => sub['localId'] == id || sub['id'] == id,
          orElse: () => {},
        );
        firebaseId = localSub?['firebaseId'];
        localId = localSub?['localId'] ?? id;
        debugPrint('📱 MOBILE DEBUG: Found Firebase ID: $firebaseId, Local ID: $localId');
      }

      // Try Firebase first if we have a Firebase ID
      if (firebaseId != null) {
        try {
          debugPrint('📱 MOBILE DEBUG: Attempting Firebase update with ID: $firebaseId');
          await _subscriptionsCollection.doc(firebaseId).update(subscription);
          debugPrint('✅ Updated subscription in Firebase with ID: $firebaseId');
        } catch (firebaseError) {
          debugPrint('📱 MOBILE DEBUG: Firebase update failed: $firebaseError');
          throw firebaseError;
        }
      }

      // Always update locally with the correct local ID
      if (localId != null) {
        try {
          debugPrint('📱 MOBILE DEBUG: Updating local storage with ID: $localId');
          await _localStorageService?.updateSubscription(localId, subscription);
          debugPrint('✅ Updated subscription in local storage with ID: $localId');
        } catch (localError) {
          debugPrint('📱 MOBILE DEBUG: Local storage update failed: $localError');
        }
      } else if (firebaseId == null) {
        // If no Firebase ID, use the original ID for local storage
        try {
          debugPrint('📱 MOBILE DEBUG: Updating local storage with original ID: $id');
          await _localStorageService?.updateSubscription(id, subscription);
          debugPrint('✅ Updated subscription in local storage with original ID: $id');
        } catch (localError) {
          debugPrint('📱 MOBILE DEBUG: Local storage update failed: $localError');
        }
      }

    } catch (e) {
      // If Firebase fails, update locally only
      debugPrint('📱 MOBILE DEBUG: Firebase update failed: $e. Updating locally only.');
      try {
        await _localStorageService?.updateSubscription(id, subscription);
        debugPrint('📱 MOBILE DEBUG: Successfully updated locally after Firebase failure');
      } catch (localError) {
        debugPrint('📱 MOBILE DEBUG: Local update also failed: $localError');
      }
      throw Exception('Offline mode: Updated locally. Will sync when online.');
    }
  }

  // Delete a subscription
  Future<void> deleteSubscription(String id) async {
    try {
      // Try Firebase first
      await _subscriptionsCollection.doc(id).delete();

      // Delete locally
      await _localStorageService?.deleteSubscription(id);

    } catch (e) {
      // If Firebase fails, delete locally only
      debugPrint('Firebase delete failed: $e. Deleting locally only.');
      await _localStorageService?.deleteSubscription(id);
      throw Exception('Offline mode: Deleted locally. Will sync when online.');
    }
  }

  // Sync local subscriptions to Firebase
  Future<bool> syncLocalToFirebase() async {
    try {
      final unsyncedSubscriptions = await _localStorageService?.getUnsyncedSubscriptions() ?? [];

      if (unsyncedSubscriptions.isEmpty) {
        return true; // Nothing to sync
      }

      bool hasErrors = false;

      for (final subscription in unsyncedSubscriptions) {
        try {
          final subscriptionToSync = Map<String, dynamic>.from(subscription);

          // Check if this is a new subscription or an edited one
          final hasFirebaseId = subscription.containsKey('firebaseId') && subscription['firebaseId'] != null;

          if (hasFirebaseId) {
            // This is an edited subscription - update the existing document
            final firebaseId = subscription['firebaseId'];
            subscriptionToSync.remove('localId');
            subscriptionToSync.remove('source');
            subscriptionToSync.remove('needsSync');
            subscriptionToSync['updatedAt'] = FieldValue.serverTimestamp();

            await _subscriptionsCollection.doc(firebaseId).update(subscriptionToSync);
            debugPrint('✅ Updated existing subscription: ${subscription['name']} (ID: $firebaseId)');

            // Mark as synced
            await _localStorageService?.markAsSynced(subscription['localId'], firebaseId);
          } else {
            // This is a new subscription - create a new document
            subscriptionToSync.remove('localId');
            subscriptionToSync.remove('source');
            subscriptionToSync.remove('needsSync');
            subscriptionToSync['createdAt'] = FieldValue.serverTimestamp();
            subscriptionToSync['updatedAt'] = FieldValue.serverTimestamp();

            final docRef = await _subscriptionsCollection.add(subscriptionToSync);
            debugPrint('✅ Created new subscription: ${subscription['name']} (ID: ${docRef.id})');

            // Mark as synced
            await _localStorageService?.markAsSynced(subscription['localId'], docRef.id);
          }

        } catch (e) {
          debugPrint('Failed to sync subscription ${subscription['name']}: $e');
          hasErrors = true;
        }
      }

      if (!hasErrors) {
        await _localStorageService?.setLastSync();
      }

      return !hasErrors;
    } catch (e) {
      debugPrint('Sync failed: $e');
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

  // Check if we should sync with Firebase (smart sync) - OPTIMIZED for cross-device access
  Future<bool> shouldSyncWithFirebase() async {
    // Don't sync if offline
    if (!await isOnline()) {
      return false;
    }

    // Always sync if there are unsynced items (critical for cross-device access)
    if (await getUnsyncedSubscriptionsCount() > 0) {
      debugPrint('🔄 Unsynced items detected - sync needed for cross-device access');
      return true;
    }

    // Check if we haven't synced recently (sync every 15 minutes max - reduced from 30)
    final lastSync = _localStorageService?.getLastSync();
    if (lastSync == null) {
      debugPrint('🆕 Never synced before - sync needed');
      return true;
    }

    final timeSinceLastSync = DateTime.now().difference(lastSync);
    final shouldSync = timeSinceLastSync.inMinutes >= 15; // Reduced to 15 minutes for better cross-device sync

    if (shouldSync) {
      debugPrint('⏰ Last sync was ${timeSinceLastSync.inMinutes} minutes ago - sync needed');
    }

    return shouldSync;
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
}