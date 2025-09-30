import 'package:flutter/material.dart';
import 'subscription_service.dart';
import 'notification_service.dart';

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
        _handleAppInactive();
        break;
      case AppLifecycleState.paused:
        _handleAppPaused();
        break;
      case AppLifecycleState.detached:
        _handleAppDetached();
        break;
      case AppLifecycleState.hidden:
        // Handle hidden state if needed
        break;
    }
  }

  Future<void> _handleAppResumed() async {
    try {
      // Trigger sync when app is resumed (in case sync failed on pause)
      await _subscriptionService.syncOnAppResume();

      // Check for pending notification actions when app resumes
      final notificationService = NotificationService();
      await notificationService.checkAndProcessPendingActions();
    } catch (e) {
      print('❌ Failed to sync on app resume: $e');
    }
  }

  Future<void> _handleAppInactive() async {
    try {
      // Trigger sync when app becomes inactive (about to go to background)
      await _subscriptionService.syncOnAppBackground();
    } catch (e) {
      print('❌ Failed to sync on app inactive: $e');
    }
  }

  Future<void> _handleAppPaused() async {
    try {
      // Trigger sync when app is paused (in background)
      await _subscriptionService.syncOnAppBackground();
    } catch (e) {
      print('❌ Failed to sync on app paused: $e');
    }
  }

  Future<void> _handleAppDetached() async {
    try {
      // Trigger sync when app is detached (being closed)
      await _subscriptionService.syncOnAppBackground();
    } catch (e) {
      print('❌ Failed to sync on app detached: $e');
    }
  }

  void dispose() {
    // Clean up if needed
  }
}