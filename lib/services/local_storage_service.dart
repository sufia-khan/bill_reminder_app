import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class LocalStorageService {
  static const String _subscriptionsKey = 'subscriptions';
  static const String _lastSyncKey = 'last_sync';
  static const String _userIdKey = 'user_id';

  final SharedPreferences _prefs;

  LocalStorageService(this._prefs);

  // Save subscription locally
  Future<void> saveSubscription(Map<String, dynamic> subscription) async {
    final subscriptions = await getSubscriptions();
    subscription['localId'] = DateTime.now().millisecondsSinceEpoch.toString();
    subscriptions.add(subscription);
    await _saveSubscriptions(subscriptions);
  }

  // Get all local subscriptions
  Future<List<Map<String, dynamic>>> getSubscriptions() async {
    final subscriptionsJson = _prefs.getString(_subscriptionsKey);
    if (subscriptionsJson == null) return [];

    final List<dynamic> decoded = json.decode(subscriptionsJson);
    return decoded.cast<Map<String, dynamic>>();
  }

  // Update subscription locally
  Future<void> updateSubscription(String localId, Map<String, dynamic> subscription) async {
    final subscriptions = await getSubscriptions();
    final index = subscriptions.indexWhere((sub) => sub['localId'] == localId);
    if (index != -1) {
      subscriptions[index] = {...subscriptions[index], ...subscription};
      await _saveSubscriptions(subscriptions);
    }
  }

  // Delete subscription locally
  Future<void> deleteSubscription(String localId) async {
    final subscriptions = await getSubscriptions();
    subscriptions.removeWhere((sub) => sub['localId'] == localId);
    await _saveSubscriptions(subscriptions);
  }

  // Save subscriptions list
  Future<void> _saveSubscriptions(List<Map<String, dynamic>> subscriptions) async {
    final subscriptionsJson = json.encode(subscriptions);
    await _prefs.setString(_subscriptionsKey, subscriptionsJson);
  }

  // Clear local subscriptions (after successful sync)
  Future<void> clearLocalSubscriptions() async {
    await _prefs.remove(_subscriptionsKey);
  }

  // Get local subscriptions that need to be synced
  Future<List<Map<String, dynamic>>> getUnsyncedSubscriptions() async {
    final subscriptions = await getSubscriptions();
    return subscriptions.where((sub) => !sub.containsKey('firebaseId')).toList();
  }

  // Mark subscription as synced
  Future<void> markAsSynced(String localId, String firebaseId) async {
    final subscriptions = await getSubscriptions();
    final index = subscriptions.indexWhere((sub) => sub['localId'] == localId);
    if (index != -1) {
      subscriptions[index]['firebaseId'] = firebaseId;
      await _saveSubscriptions(subscriptions);
    }
  }

  // Save last sync timestamp
  Future<void> setLastSync() async {
    await _prefs.setInt(_lastSyncKey, DateTime.now().millisecondsSinceEpoch);
  }

  // Get last sync timestamp
  DateTime? getLastSync() {
    final timestamp = _prefs.getInt(_lastSyncKey);
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

  // Clear all data (for logout)
  Future<void> clearAll() async {
    await _prefs.remove(_subscriptionsKey);
    await _prefs.remove(_lastSyncKey);
    await _prefs.remove(_userIdKey);
  }

  // Factory constructor for initialization
  static Future<LocalStorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalStorageService(prefs);
  }
}