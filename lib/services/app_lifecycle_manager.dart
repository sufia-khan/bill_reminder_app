import 'package:flutter/material.dart';
import 'subscription_service.dart';

class AppLifecycleManager extends WidgetsBindingObserver {
  final SubscriptionService _subscriptionService;

  AppLifecycleManager(this._subscriptionService);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        _handleAppResumed();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // Handle other states if needed
        break;
    }
  }

  Future<void> _handleAppResumed() async {
    try {
      // Trigger sync when app is resumed
      await _subscriptionService.syncOnAppResume();
    } catch (e) {
      print('❌ Failed to sync on app resume: $e');
    }
  }

  void dispose() {
    // Clean up if needed
  }
}