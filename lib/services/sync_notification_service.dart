import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'subscription_service.dart';

class SyncNotificationService {
  static final SyncNotificationService _instance = SyncNotificationService._internal();
  factory SyncNotificationService() => _instance;
  SyncNotificationService._internal();

  final SubscriptionService _subscriptionService = SubscriptionService();
  bool _isListening = false;
  bool _wasOffline = false;
  BuildContext? _currentContext;

  void init() {
    if (!_isListening) {
      _setupConnectivityListener();
      _isListening = true;
    }
  }

  void setContext(BuildContext context) {
    _currentContext = context;
  }

  void _setupConnectivityListener() {
    final connectivity = Connectivity();
    connectivity.onConnectivityChanged.listen((result) async {
      debugPrint('Connectivity changed: $result');

      if (result != ConnectivityResult.none) {
        // Check if we actually have internet connection
        final isOnline = await _subscriptionService.isOnline();
        debugPrint('Is online: $isOnline, Was offline: $_wasOffline');

        if (isOnline && _wasOffline) {
          // We just came back online - IMMEDIATE SYNC
          debugPrint('🔥 NETWORK RESTORED - STARTING IMMEDIATE SYNC');
          await immediateSync();
        }

        _wasOffline = !isOnline;
      } else {
        debugPrint('Going offline');
        _wasOffline = true;
      }
    });
  }

  Future<void> immediateSync() async {
    try {
      // Check if there are unsynced items
      final unsyncedCount = await _subscriptionService.getUnsyncedCount();
      debugPrint('📱 Found $unsyncedCount unsynced items');

      if (unsyncedCount > 0) {
        // Show sync started notification
        _showNotification('Syncing $unsyncedCount item${unsyncedCount > 1 ? 's' : ''}...', Colors.blue);

        // Perform IMMEDIATE sync
        debugPrint('⚡ STARTING SYNC NOW...');
        final success = await _subscriptionService.syncLocalToFirebase();
        debugPrint('✅ Sync completed with success: $success');

        // Show result
        _showNotification(
          success
            ? 'Successfully synced $unsyncedCount item${unsyncedCount > 1 ? 's' : ''}!'
            : 'Sync failed for $unsyncedCount item${unsyncedCount > 1 ? 's' : ''}',
          success ? Colors.green : Colors.red
        );
      } else {
        debugPrint('✅ No unsynced items found');
      }
    } catch (e) {
      debugPrint('❌ Error during immediate sync: $e');
      _showNotification('Sync failed: ${e.toString()}', Colors.red);
    }
  }

  void _showNotification(String message, Color color) {
    debugPrint('📢 Showing notification: $message');
    if (_currentContext != null && _currentContext!.mounted) {
      ScaffoldMessenger.of(_currentContext!).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      debugPrint('❌ Cannot show notification - context is null or not mounted');
    }
  }

  void dispose() {
    _isListening = false;
  }
}

// Extension method to add getUnsyncedCount to SubscriptionService
extension SubscriptionServiceExtensions on SubscriptionService {
  Future<int> getUnsyncedCount() async {
    try {
      // We need to access the private _localStorageService field
      // Since we can't access it directly from the extension, we'll use an alternative approach
      final unsyncedSubscriptions = await this.getUnsyncedSubscriptionsAlternative();
      return unsyncedSubscriptions.length;
    } catch (e) {
      debugPrint('Error getting unsynced count: $e');
      return 0;
    }
  }
}

// Alternative method to get unsynced subscriptions without accessing private fields
extension SubscriptionServiceAlternative on SubscriptionService {
  Future<List<Map<String, dynamic>>> getUnsyncedSubscriptionsAlternative() async {
    try {
      // Try to get subscriptions and filter for unsynced ones
      final allSubscriptions = await getSubscriptions();
      final unsyncedSubscriptions = allSubscriptions.where((sub) =>
        sub['source'] == 'local' && (sub['firebaseId'] == null || sub['firebaseId'].isEmpty)
      ).toList();
      return unsyncedSubscriptions;
    } catch (e) {
      debugPrint('Error getting unsynced subscriptions: $e');
      return [];
    }
  }
}