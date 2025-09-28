import 'dart:async';
import 'subscription_service.dart';

class PeriodicSyncService {
  final SubscriptionService _subscriptionService;
  Timer? _periodicTimer;

  PeriodicSyncService(this._subscriptionService);

  void startPeriodicSync() {
    // Stop any existing timer
    stopPeriodicSync();

    // Start a new timer that triggers sync every 30 minutes
    _periodicTimer = Timer.periodic(
      const Duration(minutes: 30),
      (timer) async {
        try {
          await _subscriptionService.performPeriodicSync();
        } catch (e) {
          print('❌ Periodic sync failed: $e');
        }
      },
    );

    print('🔄 Started periodic sync timer (30 minutes)');
  }

  void stopPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    print('⏹️ Stopped periodic sync timer');
  }

  void dispose() {
    stopPeriodicSync();
  }
}