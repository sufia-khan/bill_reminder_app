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

  // Add a new subscription with offline support
  Future<void> addSubscription(Map<String, dynamic> subscription) async {
    try {
      // Try to add to Firebase first
      subscription['createdAt'] = FieldValue.serverTimestamp();
      subscription['updatedAt'] = FieldValue.serverTimestamp();

      final docRef = await _subscriptionsCollection.add(subscription);
      subscription['id'] = docRef.id;
      subscription['firebaseId'] = docRef.id;

      debugPrint('Successfully added to Firebase with ID: ${docRef.id}');

      // Save locally as well for offline access (don't throw if this fails)
      try {
        await _localStorageService?.saveSubscription(subscription);
        await _localStorageService?.setLastSync();
        debugPrint('Successfully saved locally');
      } catch (localError) {
        debugPrint('Local save failed but Firebase succeeded: $localError');
        // Don't throw here since Firebase was successful
      }

    } on FirebaseException catch (e) {
      // If Firebase fails, save only locally
      debugPrint('Firebase add failed: $e. Saving locally only.');
      await _localStorageService?.saveSubscription(subscription);
      throw Exception('Offline mode: Saved locally. Will sync when online.');
    } catch (e) {
      // For other exceptions, check if it's a network issue
      debugPrint('Add subscription failed: $e');
      if (e.toString().contains('network') || e.toString().contains('connectivity') || e.toString().contains('offline')) {
        await _localStorageService?.saveSubscription(subscription);
        throw Exception('Offline mode: Saved locally. Will sync when online.');
      } else {
        rethrow;
      }
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

  // Update a subscription
  Future<void> updateSubscription(String id, Map<String, dynamic> subscription) async {
    try {
      subscription['updatedAt'] = FieldValue.serverTimestamp();

      // Try Firebase first
      await _subscriptionsCollection.doc(id).update(subscription);

      // Update locally
      await _localStorageService?.updateSubscription(id, subscription);

    } catch (e) {
      // If Firebase fails, update locally only
      debugPrint('Firebase update failed: $e. Updating locally only.');
      await _localStorageService?.updateSubscription(id, subscription);
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
          subscriptionToSync.remove('localId');
          subscriptionToSync.remove('source');
          subscriptionToSync['createdAt'] = FieldValue.serverTimestamp();
          subscriptionToSync['updatedAt'] = FieldValue.serverTimestamp();

          final docRef = await _subscriptionsCollection.add(subscriptionToSync);

          // Mark as synced
          await _localStorageService?.markAsSynced(subscription['localId'], docRef.id);

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

  // Check if user is online with improved connectivity detection
  Future<bool> isOnline() async {
    try {
      // First check network connectivity
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        debugPrint('No network connectivity detected');
        return false;
      }

      // Then check Firebase connectivity with multiple approaches
      final timeout = const Duration(seconds: 3);

      // Try 1: Basic Firebase connection test
      try {
        await _firestore.collection('connectivity_test').doc('test').get().timeout(timeout);
      } catch (e) {
        debugPrint('Firebase connectivity test 1 failed: $e');

        // Try 2: Alternative test with user document
        try {
          await _firestore.collection('users').doc(_auth.currentUser?.uid).get().timeout(timeout);
        } catch (e2) {
          debugPrint('Firebase connectivity test 2 failed: $e2');

          // Try 3: Simple ping to Firebase
          try {
            await _firestore.collection('ping').limit(1).get().timeout(timeout);
          } catch (e3) {
            debugPrint('All Firebase connectivity tests failed: $e3');
            return false;
          }
        }
      }

      debugPrint('Successfully connected to Firebase');
      return true;
    } catch (e) {
      debugPrint('Network check failed: $e');
      return false;
    }
  }

  // Stream for connectivity changes
  Stream<bool> connectivityStream() async* {
    final connectivity = Connectivity();
    await for (final result in connectivity.onConnectivityChanged) {
      if (result == ConnectivityResult.none) {
        yield false;
      } else {
        yield await isOnline();
      }
    }
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