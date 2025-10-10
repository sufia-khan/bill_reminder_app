import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class LocalStorageService {
  static const String _userIdKey = 'user_id';
  static const String _syncStatusKey = 'sync_status';

  final SharedPreferences _prefs;

  LocalStorageService(this._prefs);

  // Get user-specific storage keys to isolate data per user
  String _getSubscriptionsKey(String userId) => 'subscriptions_$userId';
  String _getLastSyncKey(String userId) => 'last_sync_$userId';

  // Get current user ID (required for all operations)
  String? _getCurrentUserId() {
    return _prefs.getString(_userIdKey);
  }

  // Save subscription locally
  Future<void> saveSubscription(Map<String, dynamic> subscription) async {
    // 🔍 DEBUG: Print incoming subscription data
    debugPrint('🔍 [LOCAL_STORAGE] Starting saveSubscription...');
    debugPrint('🔍 [LOCAL_STORAGE] Incoming bill: ${subscription['name']} (Amount: ${subscription['amount']})');

    final userId = _getCurrentUserId();
    if (userId == null) {
      throw Exception('User not logged in - cannot save subscription');
    }

    debugPrint('🔍 [LOCAL_STORAGE] User ID: $userId');
    final subscriptions = await getSubscriptions();
    debugPrint('🔍 [LOCAL_STORAGE] Current subscriptions count: ${subscriptions.length}');

    // 🔍 DEBUG: Print existing subscriptions
    for (int i = 0; i < subscriptions.length; i++) {
      final sub = subscriptions[i];
      debugPrint('🔍 [LOCAL_STORAGE] Existing $i: ${sub['name']} (Amount: ${sub['amount']}, Due: ${sub['dueDate']})');
    }

    subscription['localId'] = DateTime.now().millisecondsSinceEpoch.toString();
    debugPrint('🔍 [LOCAL_STORAGE] Generated localId: ${subscription['localId']}');

    subscription['syncPending'] = true; // Mark as needing sync
    subscription['lastModified'] = DateTime.now().toIso8601String();

    debugPrint('🔍 [LOCAL_STORAGE] Adding subscription to list...');
    subscriptions.add(subscription);
    debugPrint('🔍 [LOCAL_STORAGE] New subscriptions count: ${subscriptions.length}');

    debugPrint('🔍 [LOCAL_STORAGE] Saving to shared preferences...');
    await _saveSubscriptions(subscriptions, userId);
    debugPrint('🔍 [LOCAL_STORAGE] saveSubscription completed successfully');
  }

  // Get all local subscriptions for current user
  Future<List<Map<String, dynamic>>> getSubscriptions() async {
    final userId = _getCurrentUserId();
    if (userId == null) {
      debugPrint('⚠️ User not logged in - returning empty subscriptions');
      return [];
    }

    final subscriptionsKey = _getSubscriptionsKey(userId);
    final subscriptionsJson = _prefs.getString(subscriptionsKey);

    debugPrint('🔍 [LOCAL_STORAGE] getSubscriptions called for user $userId');
    debugPrint('🔍 [LOCAL_STORAGE] Subscriptions key: $subscriptionsKey');

    if (subscriptionsJson == null) {
      debugPrint('🔍 [LOCAL_STORAGE] No subscriptions found in storage');
      return [];
    }

    debugPrint('🔍 [LOCAL_STORAGE] Found subscriptions JSON with length: ${subscriptionsJson.length}');
    final List<dynamic> decoded = json.decode(subscriptionsJson);
    debugPrint('🔍 [LOCAL_STORAGE] Decoded ${decoded.length} subscriptions');

    // Print all retrieved subscriptions
    for (int i = 0; i < decoded.length; i++) {
      final sub = decoded[i] as Map<String, dynamic>;
      debugPrint('🔍 [LOCAL_STORAGE] Retrieved subscription $i: ${sub['name']} (ID: ${sub['localId']}, Amount: ${sub['amount']})');
    }

    return decoded.cast<Map<String, dynamic>>();
  }

  // Update subscription locally
  Future<void> updateSubscription(String localId, Map<String, dynamic> subscription) async {
    final userId = _getCurrentUserId();
    if (userId == null) {
      throw Exception('User not logged in - cannot update subscription');
    }

    final subscriptions = await getSubscriptions();
    final index = subscriptions.indexWhere((sub) => sub['localId'] == localId);
    if (index != -1) {
      // Always mark as needing sync for any update
      subscription['syncPending'] = true;
      subscription['lastModified'] = DateTime.now().toIso8601String();
      subscriptions[index] = {...subscriptions[index], ...subscription};
      await _saveSubscriptions(subscriptions, userId);
    }
  }

  // Delete subscription locally
  Future<void> deleteSubscription(String localId) async {
    final userId = _getCurrentUserId();
    if (userId == null) {
      throw Exception('User not logged in - cannot delete subscription');
    }

    final subscriptions = await getSubscriptions();
    final index = subscriptions.indexWhere((sub) => sub['localId'] == localId);
    if (index != -1) {
      // Mark as deleted but keep for sync, or remove immediately
      final subscription = subscriptions[index];
      if (subscription.containsKey('firebaseId')) {
        // Has Firebase ID - mark for sync deletion
        subscription['syncPending'] = true;
        subscription['deleted'] = true;
        subscription['lastModified'] = DateTime.now().toIso8601String();
        await _saveSubscriptions(subscriptions, userId);
      } else {
        // No Firebase ID - remove immediately
        subscriptions.removeAt(index);
        await _saveSubscriptions(subscriptions, userId);
      }
    }
  }

  // Save subscriptions list for specific user
  Future<void> _saveSubscriptions(List<Map<String, dynamic>> subscriptions, String userId) async {
    final subscriptionsKey = _getSubscriptionsKey(userId);

    debugPrint('🔍 [LOCAL_STORAGE] _saveSubscriptions called for user $userId');
    debugPrint('🔍 [LOCAL_STORAGE] Saving ${subscriptions.length} subscriptions');

    // Print all subscriptions being saved
    for (int i = 0; i < subscriptions.length; i++) {
      final sub = subscriptions[i];
      debugPrint('🔍 [LOCAL_STORAGE] Saving subscription $i: ${sub['name']} (ID: ${sub['localId']}, Amount: ${sub['amount']})');
    }

    final subscriptionsJson = json.encode(subscriptions);
    debugPrint('🔍 [LOCAL_STORAGE] JSON length: ${subscriptionsJson.length}');

    await _prefs.setString(subscriptionsKey, subscriptionsJson);
    debugPrint('✅ [LOCAL_STORAGE] Successfully saved to shared preferences');
  }

  // Public method to save subscriptions (used for fallback updates)
  Future<void> saveSubscriptions(List<Map<String, dynamic>> subscriptions) async {
    final userId = _getCurrentUserId();
    if (userId == null) {
      throw Exception('User not logged in - cannot save subscriptions');
    }
    await _saveSubscriptions(subscriptions, userId);
  }

  // Clear local subscriptions for current user (after successful sync)
  Future<void> clearLocalSubscriptions() async {
    final userId = _getCurrentUserId();
    if (userId == null) return;

    final subscriptionsKey = _getSubscriptionsKey(userId);
    await _prefs.remove(subscriptionsKey);
  }

  // Get local subscriptions that need to be synced
  Future<List<Map<String, dynamic>>> getUnsyncedSubscriptions() async {
    final subscriptions = await getSubscriptions();
    return subscriptions.where((sub) =>
      sub['syncPending'] == true || !sub.containsKey('firebaseId')
    ).toList();
  }

  // Get subscriptions marked for deletion
  Future<List<Map<String, dynamic>>> getDeletedSubscriptions() async {
    final subscriptions = await getSubscriptions();
    return subscriptions.where((sub) =>
      sub['deleted'] == true && sub.containsKey('firebaseId')
    ).toList();
  }

  // Remove successfully synced deleted subscriptions
  Future<void> cleanupDeletedSubscriptions(List<String> firebaseIds) async {
    final userId = _getCurrentUserId();
    if (userId == null) return;

    final subscriptions = await getSubscriptions();
    subscriptions.removeWhere((sub) =>
      firebaseIds.contains(sub['firebaseId'])
    );
    await _saveSubscriptions(subscriptions, userId);
  }

  // Get subscriptions that are active (not deleted)
  Future<List<Map<String, dynamic>>> getActiveSubscriptions() async {
    final subscriptions = await getSubscriptions();
    return subscriptions.where((sub) =>
      sub['deleted'] != true
    ).toList();
  }

  // Mark subscription as synced
  Future<void> markAsSynced(String localId, String firebaseId) async {
    final userId = _getCurrentUserId();
    if (userId == null) {
      throw Exception('User not logged in - cannot mark as synced');
    }

    final subscriptions = await getSubscriptions();
    final index = subscriptions.indexWhere((sub) => sub['localId'] == localId);
    if (index != -1) {
      subscriptions[index]['firebaseId'] = firebaseId;
      subscriptions[index]['syncPending'] = false; // Clear sync flag
      subscriptions[index]['lastSynced'] = DateTime.now().toIso8601String();
      await _saveSubscriptions(subscriptions, userId);
    }
  }

  // Mark multiple subscriptions as synced (batch operation)
  Future<void> markBatchAsSynced(List<Map<String, dynamic>> syncedSubscriptions) async {
    final userId = _getCurrentUserId();
    if (userId == null) return;

    final subscriptions = await getSubscriptions();
    final now = DateTime.now().toIso8601String();

    for (final syncedSub in syncedSubscriptions) {
      final localId = syncedSub['localId'];
      final firebaseId = syncedSub['firebaseId'];
      final index = subscriptions.indexWhere((sub) => sub['localId'] == localId);
      if (index != -1) {
        subscriptions[index]['firebaseId'] = firebaseId;
        subscriptions[index]['syncPending'] = false;
        subscriptions[index]['lastSynced'] = now;
      }
    }

    await _saveSubscriptions(subscriptions, userId);
  }

  // Save last sync timestamp
  Future<void> setLastSync() async {
    final userId = _getCurrentUserId();
    if (userId == null) return;

    final lastSyncKey = _getLastSyncKey(userId);
    await _prefs.setInt(lastSyncKey, DateTime.now().millisecondsSinceEpoch);
  }

  // Get last sync timestamp
  DateTime? getLastSync() {
    final userId = _getCurrentUserId();
    if (userId == null) return null;

    final lastSyncKey = _getLastSyncKey(userId);
    final timestamp = _prefs.getInt(lastSyncKey);
    return timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp) : null;
  }

  // Save user ID
  Future<void> setUserId(String userId) async {
    await _prefs.setString(_userIdKey, userId);
  }

  // Get user ID
  String? getUserId() {
    return _prefs.getString(_userIdKey);
  }

  // Clear all data for current user (for logout)
  Future<void> clearAll() async {
    final userId = _getCurrentUserId();
    if (userId != null) {
      // Clear user-specific data
      await _prefs.remove(_getSubscriptionsKey(userId));
      await _prefs.remove(_getLastSyncKey(userId));
    }
    // Clear user ID last
    await _prefs.remove(_userIdKey);
  }

  // Clean up mixed user data (call this when user logs in to fix data isolation)
  Future<void> cleanupMixedUserData() async {
    final userId = _getCurrentUserId();
    if (userId == null) return;

    debugPrint('🧹 Cleaning up mixed user data for user: $userId');

    // Remove old subscriptions key that mixed all users
    await _prefs.remove('subscriptions'); // Old mixed key

    // Remove old last sync key that mixed all users
    await _prefs.remove('last_sync'); // Old mixed key

    debugPrint('✅ Cleaned up mixed user data');
  }

  // Get oldest unsynced item time for smart batching
  Future<DateTime?> getOldestUnsyncedTime() async {
    final userId = _getCurrentUserId();
    if (userId == null) return null;

    final unsynced = await getUnsyncedSubscriptions();
    if (unsynced.isEmpty) return null;

    DateTime? oldest;
    for (final item in unsynced) {
      final modifiedStr = item['lastModified'] as String?;
      if (modifiedStr != null) {
        final modified = DateTime.tryParse(modifiedStr);
        if (modified != null && (oldest == null || modified.isBefore(oldest))) {
          oldest = modified;
        }
      }
    }

    return oldest;
  }

  // Get last Firestore refresh time for smart caching
  Future<DateTime?> getLastFirestoreRefresh() async {
    final userId = _getCurrentUserId();
    if (userId == null) return null;

    final key = 'last_firestore_refresh_$userId';
    final refreshStr = _prefs.getString(key);
    if (refreshStr == null) return null;

    return DateTime.tryParse(refreshStr);
  }

  // Set last Firestore refresh time
  Future<void> setLastFirestoreRefresh() async {
    final userId = _getCurrentUserId();
    if (userId == null) return;

    final key = 'last_firestore_refresh_$userId';
    await _prefs.setString(key, DateTime.now().toIso8601String());
  }

  // Factory constructor for initialization
  static Future<LocalStorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalStorageService(prefs);
  }
}