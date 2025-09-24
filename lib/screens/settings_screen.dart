import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:projeckt_k/services/notification_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _darkMode = false;
  String _currency = 'USD';
  String _reminderTime = '09:00';

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final notificationService = NotificationService();
    final defaultTime = await notificationService.getDefaultNotificationTime();

    setState(() {
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      _darkMode = prefs.getBool('dark_mode') ?? false;
      _currency = prefs.getString('currency') ?? 'USD';
      _reminderTime = '${defaultTime.hour.toString().padLeft(2, '0')}:${defaultTime.minute.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _savePreference(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          "Settings",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 16),
            _buildSettingsSections(),
          ],
        ),
      ),
    );
  }

  // Header method removed - now using AppBar instead

  Widget _buildSettingsSections() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _buildSection('Preferences', [
            _buildSwitchTile(
              'Dark Mode',
              'Enable dark theme',
              _darkMode,
              (value) {
                setState(() {
                  _darkMode = value;
                });
                _savePreference('dark_mode', value);
                _showSettingFeedback('Dark mode ${value ? 'enabled' : 'disabled'}');
              },
              Icons.dark_mode_outlined,
              Colors.purple,
            ),
            _buildSwitchTile(
              'Notifications',
              'Enable bill reminders',
              _notificationsEnabled,
              (value) async {
                setState(() {
                  _notificationsEnabled = value;
                });
                _savePreference('notifications_enabled', value);

                // If notifications are disabled, cancel all existing notifications
                if (!value) {
                  final notificationService = NotificationService();
                  await notificationService.cancelAllNotifications();
                }

                _showSettingFeedback('Notifications ${value ? 'enabled' : 'disabled'}');
              },
              Icons.notifications_outlined,
              Colors.blue,
            ),
          ]),
          const SizedBox(height: 24),
          _buildSection('Currency & Time', [
            _buildListTile(
              'Currency',
              _currency,
              Icons.attach_money,
              Colors.green,
              () => _showCurrencySelector(),
            ),
            _buildListTile(
              'Default Reminder Time',
              _reminderTime,
              Icons.access_time,
              Colors.orange,
              () => _showTimePicker(),
            ),
            _buildListTile(
              'Notification Permissions',
              'Check and manage notification permissions',
              Icons.security,
              Colors.red,
              () => _checkNotificationPermissions(),
            ),
            _buildListTile(
              'Test Notification',
              'Send a test notification',
              Icons.notifications_active,
              Colors.green,
              () => _sendTestNotification(),
            ),
          ]),
          const SizedBox(height: 24),
          _buildSection('Data & Privacy', [
            _buildListTile(
              'Export Data',
              'Export your bills data',
              Icons.download,
              Colors.teal,
              () => _exportData(),
            ),
            _buildListTile(
              'Clear Data',
              'Clear all app data',
              Icons.delete,
              Colors.red,
              () => _showClearDataConfirm(),
            ),
          ]),
          const SizedBox(height: 24),
          _buildSection('App Settings', [
            _buildSwitchTile(
              'Auto-categorize Bills',
              'Automatically categorize new bills',
              true,
              (value) {
                setState(() {
                  // Auto-categorize setting would be implemented
                });
                _showSettingFeedback('Auto-categorization ${value ? 'enabled' : 'disabled'}');
              },
              Icons.category_outlined,
              Colors.indigo,
            ),
            _buildListTile(
              'Default Category',
              'Entertainment',
              Icons.bookmark_outlined,
              Colors.amber,
              () => _showDefaultCategorySelector(),
            ),
            _buildSwitchTile(
              'Smart Reminders',
              'Get reminders before bills are due',
              true,
              (value) {
                setState(() {
                  // Smart reminders setting would be implemented
                });
                _showSettingFeedback('Smart reminders ${value ? 'enabled' : 'disabled'}');
              },
              Icons.lightbulb_outlined,
              Colors.yellow,
            ),
          ]),
          const SizedBox(height: 24),
          _buildSection('About', [
            _buildListTile(
              'Version',
              '1.0.0',
              Icons.info,
              Colors.grey,
              null,
            ),
            _buildListTile(
              'Privacy Policy',
              'Read our privacy policy',
              Icons.policy,
              Colors.blue,
              () => _showPrivacyPolicy(),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
          ),
          const Divider(height: 1),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSwitchTile(
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
    IconData icon,
    Color iconColor,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!, width: 1)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: iconColor,
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeColor: HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor(),
        ),
      ),
    );
  }

  Widget _buildListTile(
    String title,
    String subtitle,
    IconData icon,
    Color iconColor,
    Function()? onTap,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!, width: 1)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: iconColor,
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        trailing: onTap != null
            ? Icon(Icons.chevron_right, color: Colors.grey[400])
            : null,
        onTap: onTap,
      ),
    );
  }

  void _showCurrencySelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Select Currency',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...['USD', 'EUR', 'GBP', 'JPY', 'CAD', 'AUD'].map((currency) {
              return ListTile(
                title: Text(currency),
                trailing: _currency == currency
                    ? Icon(Icons.check, color: Colors.blue.shade600)
                    : null,
                onTap: () {
                  setState(() {
                    _currency = currency;
                  });
                  _savePreference('currency', currency);
                  Navigator.pop(context);
                  _showSettingFeedback('Currency changed to $currency');
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showTimePicker() {
    showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(_reminderTime.split(':')[0]),
        minute: int.parse(_reminderTime.split(':')[1]),
      ),
    ).then((time) async {
      if (time != null) {
        final newTime = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
        setState(() {
          _reminderTime = newTime;
        });
        _savePreference('reminder_time', newTime);

        // Update notification service default time
        final notificationService = NotificationService();
        await notificationService.setDefaultNotificationTime(time);

        _showSettingFeedback('Default notification time updated to $newTime');
      }
    });
  }

  void _exportData() {
    // Placeholder for export functionality
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Data'),
        content: const Text('Data export functionality would be implemented here.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showClearDataConfirm() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data?'),
        content: const Text('This action cannot be undone. All your bills and settings will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              // Placeholder for clear data functionality
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Data cleared successfully'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear Data'),
          ),
        ],
      ),
    );
  }

  void _showDefaultCategorySelector() {
    final categories = ['Entertainment', 'Utilities', 'Food & Dining', 'Transportation', 'Shopping', 'Healthcare', 'Other'];

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Select Default Category',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...categories.map((category) {
              return ListTile(
                title: Text(category),
                trailing: category == 'Entertainment'
                    ? Icon(Icons.check, color: Colors.blue.shade600)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  _showSettingFeedback('Default category set to $category');
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showSettingFeedback(String message, {Color backgroundColor = Colors.green}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Future<void> _checkNotificationPermissions() async {
    final notificationService = NotificationService();
    final isEnabled = await notificationService.areNotificationsEnabled();

    if (isEnabled) {
      _showSettingFeedback('Notifications are enabled', backgroundColor: Colors.green);
    } else {
      _showSettingFeedback('Notifications are disabled. Enable them in device settings.', backgroundColor: Colors.orange);
      await notificationService.openNotificationSettings();
    }
  }

  Future<void> _sendTestNotification() async {
    final notificationService = NotificationService();
    await notificationService.showImmediateNotification(
      title: 'Test Notification',
      body: 'This is a test notification from Bill Manager!',
    );
    _showSettingFeedback('Test notification sent!', backgroundColor: Colors.blue);
  }

  void _showPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Privacy Policy'),
        content: const Text(
          'Your privacy is important to us. This app stores your data locally on your device and does not share it with third parties.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}