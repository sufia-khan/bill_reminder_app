import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // Callback for handling mark as paid action
  Function(String? billId)? onMarkAsPaid;

  static const String _defaultNotificationTimeKey = 'default_notification_time';
  static const TimeOfDay _defaultTime = TimeOfDay(hour: 9, minute: 0);

  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;
  late SharedPreferences _prefs;

  // Initialize the notification service
  Future<void> init() async {
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    _prefs = await SharedPreferences.getInstance();

    // Initialize timezone
    tz.initializeTimeZones();

    // Android settings
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS settings
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    // Initialize settings
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: onNotificationResponse,
    );

    // Create notification channel for Android
    await _createNotificationChannel();

    // Request notification permissions
    await _requestPermissions();
  }

  // Check if this is the first time the app is launched
  Future<bool> isFirstTimeLaunch() async {
    final isFirstTime = _prefs.getBool('first_time_launch') ?? true;
    if (isFirstTime) {
      await _prefs.setBool('first_time_launch', false);
    }
    return isFirstTime;
  }

  // Request notification permissions with user-friendly dialog
  Future<bool> requestNotificationPermissions(BuildContext context) async {
    final isFirstTime = await isFirstTimeLaunch();

    if (!isFirstTime) {
      // For returning users, just check current permissions
      return await areNotificationsEnabled();
    }

    // For first-time users, show a dialog explaining the benefits
    return await _showPermissionRequestDialog(context);
  }

  Future<bool> _showPermissionRequestDialog(BuildContext context) async {
    final completer = Completer<bool>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Enable Bill Reminders'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stay on top of your bills with timely reminders!'),
            SizedBox(height: 12),
            Text('• Get notified before bills are due'),
            Text('• Never miss a payment deadline'),
            Text('• Customize reminder times and frequency'),
            SizedBox(height: 12),
            Text('Would you like to enable bill reminder notifications?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              completer.complete(false);
            },
            child: const Text('Not Now'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _requestPermissions();
              final isEnabled = await areNotificationsEnabled();
              completer.complete(isEnabled);
            },
            child: const Text('Enable Notifications'),
          ),
        ],
      ),
    );

    return completer.future;
  }

  // Create notification channel for Android
  Future<void> _createNotificationChannel() async {
    final androidPlugin = flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'bill_reminders',
        'Bill Reminders',
        description: 'Notifications for bill due dates',
        importance: Importance.high,
        enableLights: true,
        enableVibration: true,
        playSound: true,
        showBadge: true,
      );

      await androidPlugin.createNotificationChannel(channel);
      debugPrint('✅ Created Android notification channel: ${channel.id}');
    }
  }

  // Request notification permissions
  Future<void> _requestPermissions() async {
    // Android permissions are requested automatically when showing notifications
    // For iOS, we request permissions
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
  }

  // Handle notification tap and actions
  @pragma('vm:entry-point')
  static void onNotificationResponse(NotificationResponse notificationResponse) {
    debugPrint('Notification response: ${notificationResponse.payload}');
    debugPrint('Action ID: ${notificationResponse.actionId}');

    // Handle mark as paid action
    if (notificationResponse.actionId == 'mark_paid') {
      debugPrint('📝 Mark as Paid action triggered');
      _handleMarkAsPaid(notificationResponse.payload);
    }
  }

  // Handle mark as paid action
  static void _handleMarkAsPaid(String? payload) {
    debugPrint('📝 Handling mark as paid for payload: $payload');

    // Call the callback if it's set
    _instance.onMarkAsPaid?.call(payload);
  }

  // Get default notification time
  Future<TimeOfDay> getDefaultNotificationTime() async {
    final hour = _prefs.getInt(_defaultNotificationTimeKey + '_hour') ?? _defaultTime.hour;
    final minute = _prefs.getInt(_defaultNotificationTimeKey + '_minute') ?? _defaultTime.minute;
    return TimeOfDay(hour: hour, minute: minute);
  }

  // Set default notification time
  Future<void> setDefaultNotificationTime(TimeOfDay time) async {
    await _prefs.setInt(_defaultNotificationTimeKey + '_hour', time.hour);
    await _prefs.setInt(_defaultNotificationTimeKey + '_minute', time.minute);
  }

  // Schedule a bill reminder notification
  Future<void> scheduleBillReminder({
    required int id,
    required String title,
    required String body,
    required DateTime dueDate,
    required String reminderPreference,
    TimeOfDay? customNotificationTime,
    String? payload,
  }) async {
    try {
      // Check if notifications are globally enabled
      final prefs = await SharedPreferences.getInstance();
      final notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;

      if (!notificationsEnabled) {
        debugPrint('🚫 Notifications are disabled globally, skipping notification scheduling');
        return;
      }

      final defaultTime = await getDefaultNotificationTime();
      final now = DateTime.now();

      // Check if bill is overdue and needs immediate notification
      if (dueDate.isBefore(now) && reminderPreference != 'No reminder') {
        debugPrint('🚨 Bill is overdue, sending immediate notification');
        await _sendOverdueNotification(id, title, body, payload: payload);
        return;
      }

      // Use custom notification time if provided, otherwise use default time
      final TimeOfDay notificationTimeOfDay = customNotificationTime ?? defaultTime;

      // Calculate notification time based on reminder preference
      DateTime notificationTime = _calculateNotificationTime(
        dueDate: dueDate,
        reminderPreference: reminderPreference,
        defaultTime: notificationTimeOfDay,
      );

      // Make sure notification time is in the future
      if (notificationTime.isBefore(now)) {
        debugPrint('⚠️ Notification time is in the past, skipping: $notificationTime (now: $now)');
        return;
      }

      // Convert to local timezone with proper UTC handling
      final tz.TZDateTime scheduledTime = tz.TZDateTime.local(
        notificationTime.year,
        notificationTime.month,
        notificationTime.day,
        notificationTime.hour,
        notificationTime.minute,
      );

      debugPrint('📅 Scheduling notification:');
      debugPrint('   Bill: $title');
      debugPrint('   Due Date: $dueDate');
      debugPrint('   Reminder: $reminderPreference');
      debugPrint('   Default Time: ${defaultTime.hour}:${defaultTime.minute}');
      debugPrint('   Custom Time: ${customNotificationTime?.hour}:${customNotificationTime?.minute}');
      debugPrint('   Using Time: ${notificationTimeOfDay.hour}:${notificationTimeOfDay.minute}');
      debugPrint('   Calculated Time: $notificationTime');
      debugPrint('   Scheduled Time (local): $scheduledTime');
      debugPrint('   Current Time: $now');
      debugPrint('   Is Future: ${scheduledTime.isAfter(tz.TZDateTime.now(tz.local))}');

      // Android notification details
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'bill_reminders',
        'Bill Reminders',
        channelDescription: 'Notifications for bill due dates',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        actions: [
          AndroidNotificationAction(
            'mark_paid',
            'Mark as Paid',
            icon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          ),
        ],
      );

      // iOS notification details
      const DarwinNotificationDetails iOSDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      // Combined notification details
      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iOSDetails,
      );

      // Schedule the notification
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledTime,
        notificationDetails,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload ?? 'bill_reminder_$id',
      );

      debugPrint('✅ Successfully scheduled notification for bill $id at $scheduledTime');
    } catch (e) {
      debugPrint('❌ ERROR scheduling notification: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
    }
  }

  // Send immediate notification for overdue bills
  Future<void> _sendOverdueNotification(int id, String title, String body, {String? payload}) async {
    try {
      debugPrint('🚨 Sending immediate overdue notification for: $title');

      // Android notification details for overdue
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'bill_reminders',
        'Bill Reminders',
        channelDescription: 'Notifications for bill due dates',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        category: AndroidNotificationCategory.alarm,
        actions: [
          AndroidNotificationAction(
            'mark_paid',
            'Mark as Paid',
            icon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          ),
        ],
      );

      // iOS notification details
      const DarwinNotificationDetails iOSDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      // Combined notification details
      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iOSDetails,
      );

      // Send immediate notification
      await flutterLocalNotificationsPlugin.show(
        id,
        '🚨 OVERDUE: $title',
        body,
        notificationDetails,
        payload: payload ?? 'overdue_bill_$id',
      );

      debugPrint('✅ Successfully sent overdue notification for bill $id');
    } catch (e) {
      debugPrint('❌ ERROR sending overdue notification: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
    }
  }

  // Calculate notification time based on reminder preference
  DateTime _calculateNotificationTime({
    required DateTime dueDate,
    required String reminderPreference,
    required TimeOfDay defaultTime,
  }) {
    DateTime notificationTime;

    switch (reminderPreference) {
      case 'Same day':
        notificationTime = DateTime(
          dueDate.year,
          dueDate.month,
          dueDate.day,
          defaultTime.hour,
          defaultTime.minute,
        );
        break;
      case '1 day before':
        notificationTime = DateTime(
          dueDate.year,
          dueDate.month,
          dueDate.day - 1,
          defaultTime.hour,
          defaultTime.minute,
        );
        break;
      case '3 days before':
        notificationTime = DateTime(
          dueDate.year,
          dueDate.month,
          dueDate.day - 3,
          defaultTime.hour,
          defaultTime.minute,
        );
        break;
      case '1 week before':
        notificationTime = DateTime(
          dueDate.year,
          dueDate.month,
          dueDate.day - 7,
          defaultTime.hour,
          defaultTime.minute,
        );
        break;
      case '10 days before':
        notificationTime = DateTime(
          dueDate.year,
          dueDate.month,
          dueDate.day - 10,
          defaultTime.hour,
          defaultTime.minute,
        );
        break;
      default:
        notificationTime = DateTime(
          dueDate.year,
          dueDate.month,
          dueDate.day,
          defaultTime.hour,
          defaultTime.minute,
        );
    }

    return notificationTime;
  }

  // Cancel a specific notification
  Future<void> cancelNotification(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
    debugPrint('Cancelled notification for bill $id');
  }

  // Cancel all notifications
  Future<void> cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
    debugPrint('Cancelled all notifications');
  }

  // Show an immediate notification (for testing)
  Future<void> showImmediateNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    // Check if notifications are globally enabled
    final prefs = await SharedPreferences.getInstance();
    final notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;

    if (!notificationsEnabled) {
      debugPrint('Notifications are disabled globally, skipping immediate notification');
      return;
    }

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'bill_reminders',
      'Bill Reminders',
      channelDescription: 'Notifications for bill due dates',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      actions: [
        AndroidNotificationAction(
          'mark_paid',
          'Mark as Paid',
          icon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        ),
      ],
    );

    const DarwinNotificationDetails iOSDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iOSDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      notificationDetails,
      payload: payload ?? 'test_notification',
    );
  }

  // Check if notifications are enabled
  Future<bool> areNotificationsEnabled() async {
    try {
      final androidPlugin = flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        return await androidPlugin.areNotificationsEnabled() ?? true;
      }

      final iosPlugin = flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (iosPlugin != null) {
        // For iOS, we assume enabled if permissions were granted
        return true;
      }

      return true; // Assume enabled if we can't check
    } catch (e) {
      debugPrint('Error checking notification permissions: $e');
      return true; // Assume enabled by default
    }
  }

  // Open notification settings
  Future<void> openNotificationSettings() async {
    // Note: The openNotificationSettings method may not be available in all versions
    // For now, we'll just show a message directing users to settings
    debugPrint('Please enable notifications in device settings');
  }
}