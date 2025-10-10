import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:projeckt_k/services/notification_service.dart';
import 'package:projeckt_k/services/local_storage_service.dart';
import 'package:projeckt_k/services/subscription_service.dart';
import 'package:projeckt_k/services/auth_service.dart';

class SettingsScreen extends StatefulWidget {
  final Function()? onDataCleared;

  const SettingsScreen({
    super.key,
    this.onDataCleared,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _darkMode = false;
  String _currency = 'USD';
  String _reminderTime = '09:00';

  // Profile related variables
  final AuthService _authService = AuthService();
  bool _isLoadingProfile = true;
  bool _hasError = false;
  bool _isEditing = false;
  String _displayName = '';
  String _email = '';
  String _photoURL = '';
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _loadUserData();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final notificationService = NotificationService();
    final defaultTime = await notificationService.getDefaultNotificationTime();

    if (mounted) {
      setState(() {
        _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
        _darkMode = prefs.getBool('dark_mode') ?? false;
        _currency = prefs.getString('currency') ?? 'USD';
        _reminderTime = '${defaultTime.hour.toString().padLeft(2, '0')}:${defaultTime.minute.toString().padLeft(2, '0')}';
      });
    }
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
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _showSettingFeedback(String message, {Color backgroundColor = Colors.green}) {
    if (mounted) {
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
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoadingProfile = true;
      _hasError = false;
    });

    try {
      final user = _authService.currentUser;
      if (user != null) {
        setState(() {
          _displayName = user.displayName ?? 'User';
          _email = user.email ?? '';
          _photoURL = user.photoURL ?? '';
          _nameController = TextEditingController(text: _displayName);
          _isLoadingProfile = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load user data: $e');
      setState(() {
        _hasError = true;
        _isLoadingProfile = false;
      });
    }
  }

  Future<void> _updateUserProfile() async {
    try {
      await _authService.updateDisplayName(_nameController.text.trim());

      setState(() {
        _displayName = _nameController.text.trim();
        _isEditing = false;
      });

      _showSettingFeedback('Profile updated successfully!');
    } catch (e) {
      debugPrint('Failed to update profile: $e');
      _showSettingFeedback('Failed to update profile: ${e.toString()}', backgroundColor: Colors.red);
    }
  }

  Future<void> _signOut() async {
    try {
      await _authService.signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } catch (e) {
      _showSettingFeedback('Failed to sign out: ${e.toString()}', backgroundColor: Colors.red);
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
                if (mounted) {
                  setState(() {
                    _darkMode = value;
                  });
                  _savePreference('dark_mode', value);
                  _showSettingFeedback('Dark mode ${value ? 'enabled' : 'disabled'}');
                }
              },
              Icons.dark_mode_outlined,
              Colors.purple,
            ),
            _buildSwitchTile(
              'Notifications',
              'Enable bill reminders',
              _notificationsEnabled,
              (value) async {
                if (mounted) {
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
                }
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
              'Clean Up Duplicates',
              'Remove duplicate bills from cloud storage',
              Icons.cleaning_services,
              Colors.orange,
              () => _cleanupDuplicates(),
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
            _buildListTile(
              'Network Connection',
              'Check network status',
              Icons.wifi,
              Colors.blue,
              () => _checkNetworkConnection(),
            ),
          ]),
          const SizedBox(height: 24),
          _buildProfileSection(),
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

  Widget _buildProfileSection() {
    if (_isLoadingProfile) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading profile...'),
              ],
            ),
          ),
        ),
      );
    }

    if (_hasError) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'Failed to load profile',
                  style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _loadUserData,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Profile Header
          ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: Colors.blue.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: _photoURL.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Image.network(
                        _photoURL,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.person,
                            size: 30,
                            color: Colors.blue.withOpacity(0.8),
                          );
                        },
                      ),
                    )
                  : Icon(
                      Icons.person,
                      size: 30,
                      color: Colors.blue.withOpacity(0.8),
                    ),
            ),
            title: _isEditing
                ? TextField(
                    controller: _nameController,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Display Name',
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  )
                : Text(
                    _displayName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
            subtitle: Text(
              _email,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            trailing: _isEditing
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _isEditing = false;
                            _nameController.text = _displayName;
                          });
                        },
                        icon: const Icon(Icons.close),
                        color: Colors.grey,
                      ),
                      IconButton(
                        onPressed: _updateUserProfile,
                        icon: const Icon(Icons.check),
                        color: Colors.green,
                      ),
                    ],
                  )
                : IconButton(
                    onPressed: () {
                      setState(() {
                        _isEditing = true;
                      });
                    },
                    icon: const Icon(Icons.edit),
                    color: Colors.blue,
                  ),
          ),
          const Divider(height: 1),
          // Profile Information
          _buildListTile(
            'Account Status',
            'Active',
            Icons.account_circle_outlined,
            Colors.blue,
            null,
          ),
          _buildListTile(
            'Member Since',
            'January 2024',
            Icons.calendar_today_outlined,
            Colors.green,
            null,
          ),
          _buildListTile(
            'Change Password',
            'Update your password',
            Icons.lock_outlined,
            Colors.purple,
            () {
              _showSettingFeedback('Password change functionality coming soon!', backgroundColor: Colors.blue);
            },
          ),
          const SizedBox(height: 8),
          // Sign Out Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _signOut,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Sign Out',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
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
            color: Colors.black.withValues(alpha: 0.1),
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
            color: iconColor.withValues(alpha: 0.1),
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
          activeThumbColor: HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor(),
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
            color: iconColor.withValues(alpha: 0.1),
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
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      transitionAnimationController: AnimationController(
        vsync: Navigator.of(context),
        duration: const Duration(milliseconds: 350),
      ),
      builder: (context) => CurrencySelector(
        currentCurrency: _currency,
        onCurrencySelected: (currency) {
          if (mounted) {
            setState(() {
              _currency = currency;
            });
            _savePreference('currency', currency);
            Navigator.pop(context);
            _showSettingFeedback('Currency changed to $currency');
          }
        },
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
      if (time != null && mounted) {
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

  Future<void> _showClearDataConfirm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data?'),
        content: const Text('This action cannot be undone. All your bills and settings will be permanently deleted from both your device and the cloud.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear Data'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _clearAllData();
    }
  }

  Future<void> _clearAllData() async {
    try {
      // Show loading indicator with blur background
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.3),
        builder: (context) => BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: AlertDialog(
            backgroundColor: Colors.white.withValues(alpha: 0.9),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Clearing all data...',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Cancel all notifications first
      final notificationService = NotificationService();
      await notificationService.cancelAllNotifications();

      // Clear local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Clear Firebase data
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          // Delete all subscriptions from Firestore with batch write for better performance
          final subscriptionsRef = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('subscriptions');

          final snapshot = await subscriptionsRef.get();

          // Use batch write for better performance
          final batch = FirebaseFirestore.instance.batch();
          for (final doc in snapshot.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();

          // Also clear any user-specific settings from Firestore
          final userSettingsRef = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid);
          await userSettingsRef.delete();

        } catch (e) {
          debugPrint('Error clearing Firebase data: $e');
        }
      }

      // Clear any cached data in local storage service
      final localStorageService = await LocalStorageService.init();
      await localStorageService.clearAll();

      // Hide loading indicator
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All data cleared successfully'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        );
      }

      // Reset app state
      if (mounted) {
        setState(() {
          _notificationsEnabled = true;
          _darkMode = false;
          _currency = 'USD';
          _reminderTime = '09:00';
        });
      }

      // Navigate back to home screen and force refresh
      if (mounted) {
        // Call the callback to notify home screen
        widget.onDataCleared?.call();

        // Pop all screens until we reach the home screen
        Navigator.popUntil(context, (route) => route.isFirst);

        // Force refresh the home screen by showing a message
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Data cleared successfully! Add some bills to get started.'),
                backgroundColor: Colors.blue,
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 3),
              ),
            );
          }
        });
      }

    } catch (e) {
      // Hide loading indicator if showing
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing data: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),
        );
      }
    }
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

  Future<void> _checkNetworkConnection() async {
    try {
      // Show checking dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Checking network connection...'),
              ],
            ),
          ),
        );
      }

      // Check network connectivity
      final subscriptionService = SubscriptionService();
      final isOnline = await subscriptionService.isOnline();

      // Hide checking dialog
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Show result with detailed information
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  isOnline ? Icons.wifi : Icons.wifi_off,
                  color: isOnline ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text('Network Status'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Status: ${isOnline ? 'Connected' : 'Disconnected'}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isOnline ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isOnline
                    ? 'Your device is connected to the internet. You can sync your bills with the cloud.'
                    : 'Your device is not connected to the internet. Bills will be saved locally and synced when you\'re back online.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isOnline ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isOnline ? Colors.green.withValues(alpha: 0.3) : Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isOnline ? Icons.check_circle : Icons.error,
                        color: isOnline ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isOnline ? 'Cloud sync is available' : 'Only local storage available',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: isOnline ? Colors.green[700] : Colors.red[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
              if (!isOnline)
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _openNetworkSettings();
                  },
                  child: const Text('Open Settings'),
                ),
            ],
          ),
        );
      }
    } catch (e) {
      // Hide checking dialog if showing
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (mounted) {
        _showSettingFeedback(
          'Failed to check network connection: ${e.toString()}',
          backgroundColor: Colors.red,
        );
      }
    }
  }

  void _openNetworkSettings() {
    // This would open device network settings
    // For now, show a message directing user to device settings
    _showSettingFeedback(
      'Please check your network connection in device settings',
      backgroundColor: Colors.orange,
    );
  }

  Future<void> _cleanupDuplicates() async {
    // Check internet connection
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSettingFeedback('You must be logged in to clean up duplicates', backgroundColor: Colors.red);
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clean Up Duplicates?'),
        content: const Text('This will scan your cloud storage and remove duplicate bills. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Clean Up'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show loading indicator
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Scanning for duplicates...'),
          ],
        ),
      ),
      );
    }

    try {
      final subscriptionService = SubscriptionService();
      final result = await subscriptionService.cleanupDuplicateSubscriptions();

      // Hide loading indicator
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Show result
      if (mounted) {
        _showSettingFeedback(
          'Cleaned up $result duplicate subscriptions',
          backgroundColor: result > 0 ? Colors.green : Colors.orange,
        );
      }
    } catch (e) {
      // Hide loading indicator
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (mounted) {
        _showSettingFeedback(
          'Failed to clean up duplicates: ${e.toString()}',
          backgroundColor: Colors.red,
        );
      }
    }
  }
}

class CurrencySelector extends StatefulWidget {
  final String currentCurrency;
  final Function(String) onCurrencySelected;

  const CurrencySelector({
    super.key,
    required this.currentCurrency,
    required this.onCurrencySelected,
  });

  @override
  State<CurrencySelector> createState() => _CurrencySelectorState();
}

class _CurrencySelectorState extends State<CurrencySelector> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Map<String, String>> _filteredCurrencies = [];
  Timer? _debounceTimer;

  // Color mapping for currency codes
  final Map<String, Color> _currencyColors = {
    'USD': Colors.green,
    'EUR': Colors.blue,
    'GBP': Colors.purple,
    'JPY': Colors.red,
    'CAD': Colors.red.shade700,
    'AUD': Colors.yellow.shade700,
    'CHF': Colors.teal,
    'CNY': Colors.red.shade800,
    'INR': Colors.orange.shade700,
    'MXN': Colors.green.shade700,
    'BRL': Colors.green.shade800,
    'RUB': Colors.blue.shade800,
    'KRW': Colors.red.shade700,
    'SGD': Colors.red.shade600,
    'HKD': Colors.pink.shade700,
    'SEK': Colors.yellow.shade600,
    'NOK': Colors.red.shade600,
    'DKK': Colors.red.shade700,
    'PLN': Colors.purple.shade700,
    'THB': Colors.blue.shade700,
    'MYR': Colors.orange.shade600,
    'IDR': Colors.red.shade600,
    'PHP': Colors.blue.shade600,
    'VND': Colors.yellow.shade600,
    'ZAR': Colors.green.shade600,
    'EGP': Colors.amber.shade700,
    'NGN': Colors.green.shade800,
    'KES': Colors.green.shade700,
    'GHS': Colors.brown.shade600,
    'TZS': Colors.blue.shade700,
    'UGX': Colors.yellow.shade700,
    'AED': Colors.green.shade600,
    'SAR': Colors.green.shade700,
    'QAR': Colors.purple.shade600,
    'KWD': Colors.red.shade700,
    'BHD': Colors.red.shade800,
    'OMR': Colors.red.shade600,
    'JOD': Colors.amber.shade600,
    'LBP': Colors.red.shade600,
    'ILS': Colors.blue.shade600,
    'TRY': Colors.red.shade600,
    'ARS': Colors.blue.shade700,
    'CLP': Colors.blue.shade600,
    'COP': Colors.yellow.shade600,
    'PEN': Colors.red.shade600,
    'UYU': Colors.blue.shade800,
    'PYG': Colors.blue.shade700,
    'BOB': Colors.red.shade700,
    'CRC': Colors.blue.shade700,
    'GTQ': Colors.blue.shade600,
    'HNL': Colors.blue.shade500,
    'NIO': Colors.blue.shade800,
    'SVN': Colors.blue.shade600,
    'DOP': Colors.blue.shade700,
    'JMD': Colors.green.shade600,
    'TTD': Colors.red.shade600,
    'BBD': Colors.blue.shade600,
    'BZD': Colors.red.shade600,
    'GYD': Colors.green.shade600,
    'FJD': Colors.blue.shade600,
    'PGK': Colors.red.shade600,
    'VUV': Colors.green.shade600,
    'WST': Colors.blue.shade600,
    'TOP': Colors.red.shade600,
    'SBD': Colors.blue.shade600,
    'KID': Colors.green.shade600,
    'TVD': Colors.blue.shade600,
    'NPR': Colors.red.shade600,
    'LKR': Colors.blue.shade600,
    'PKR': Colors.green.shade600,
    'BDT': Colors.red.shade600,
    'MMK': Colors.green.shade600,
    'KHR': Colors.blue.shade600,
    'LAK': Colors.red.shade600,
    'MOP': Colors.green.shade600,
    'TWD': Colors.blue.shade600,
    'MNT': Colors.red.shade600,
    'KZT': Colors.blue.shade600,
    'UZS': Colors.green.shade600,
    'GEL': Colors.red.shade600,
    'AMD': Colors.purple.shade600,
    'AZN': Colors.green.shade600,
    'BGN': Colors.green.shade600,
    'HRK': Colors.red.shade600,
    'CZK': Colors.red.shade600,
    'HUF': Colors.red.shade700,
    'RON': Colors.blue.shade600,
    'RSD': Colors.red.shade600,
    'UAH': Colors.yellow.shade600,
    'BYN': Colors.red.shade600,
    'MDL': Colors.blue.shade600,
    'ISK': Colors.blue.shade600,
    'ALL': Colors.red.shade600,
    'MKD': Colors.red.shade700,
    'BAM': Colors.green.shade600,
    'XCD': Colors.green.shade600,
    'XOF': Colors.orange.shade600,
    'XAF': Colors.green.shade600,
    'XPF': Colors.blue.shade600,
    // Additional currency colors
    'NZD': Colors.blue.shade700,
    'ZMW': Colors.green.shade800,
    'BWP': Colors.blue.shade800,
    'NAD': Colors.blue.shade600,
    'AOA': Colors.red.shade600,
    'MZN': Colors.green.shade600,
    'ERN': Colors.red.shade700,
    'ETB': Colors.yellow.shade700,
    'SSP': Colors.blue.shade800,
    'SOS': Colors.blue.shade600,
    'DJF': Colors.green.shade600,
    'CDF': Colors.blue.shade700,
    'SCR': Colors.red.shade600,
    'MUR': Colors.green.shade700,
    'MGA': Colors.green.shade600,
    'MWK': Colors.red.shade600,
    'LSL': Colors.blue.shade600,
    'SZL': Colors.blue.shade700,
    'BIF': Colors.green.shade600,
    'RWF': Colors.yellow.shade600,
    'GMD': Colors.red.shade600,
    'CVE': Colors.blue.shade600,
    'STN': Colors.green.shade600,
    'GNF': Colors.red.shade600,
    'LRD': Colors.blue.shade600,
    'SLL': Colors.green.shade600,
    'BND': Colors.yellow.shade600,
    'TMT': Colors.green.shade600,
    'TJS': Colors.red.shade600,
    'BTN': Colors.green.shade600,
    'MVR': Colors.red.shade600,
    'XDR': Colors.purple.shade600,
  };

  Color _getCurrencyColor(String currencyCode) {
    return _currencyColors[currencyCode] ?? Colors.grey.shade600;
  }

  // Comprehensive currency data with country names
  final List<Map<String, String>> _allCurrencies = [
    {'code': 'USD', 'name': 'United States Dollar', 'country': 'United States'},
    {'code': 'EUR', 'name': 'Euro', 'country': 'European Union'},
    {'code': 'GBP', 'name': 'British Pound Sterling', 'country': 'United Kingdom'},
    {'code': 'JPY', 'name': 'Japanese Yen', 'country': 'Japan'},
    {'code': 'CAD', 'name': 'Canadian Dollar', 'country': 'Canada'},
    {'code': 'AUD', 'name': 'Australian Dollar', 'country': 'Australia'},
    {'code': 'CHF', 'name': 'Swiss Franc', 'country': 'Switzerland'},
    {'code': 'CNY', 'name': 'Chinese Yuan', 'country': 'China'},
    {'code': 'INR', 'name': 'Indian Rupee', 'country': 'India'},
    {'code': 'MXN', 'name': 'Mexican Peso', 'country': 'Mexico'},
    {'code': 'BRL', 'name': 'Brazilian Real', 'country': 'Brazil'},
    {'code': 'RUB', 'name': 'Russian Ruble', 'country': 'Russia'},
    {'code': 'KRW', 'name': 'South Korean Won', 'country': 'South Korea'},
    {'code': 'SGD', 'name': 'Singapore Dollar', 'country': 'Singapore'},
    {'code': 'HKD', 'name': 'Hong Kong Dollar', 'country': 'Hong Kong'},
    {'code': 'SEK', 'name': 'Swedish Krona', 'country': 'Sweden'},
    {'code': 'NOK', 'name': 'Norwegian Krone', 'country': 'Norway'},
    {'code': 'DKK', 'name': 'Danish Krone', 'country': 'Denmark'},
    {'code': 'PLN', 'name': 'Polish Złoty', 'country': 'Poland'},
    {'code': 'THB', 'name': 'Thai Baht', 'country': 'Thailand'},
    {'code': 'MYR', 'name': 'Malaysian Ringgit', 'country': 'Malaysia'},
    {'code': 'IDR', 'name': 'Indonesian Rupiah', 'country': 'Indonesia'},
    {'code': 'PHP', 'name': 'Philippine Peso', 'country': 'Philippines'},
    {'code': 'VND', 'name': 'Vietnamese Dong', 'country': 'Vietnam'},
    {'code': 'ZAR', 'name': 'South African Rand', 'country': 'South Africa'},
    {'code': 'EGP', 'name': 'Egyptian Pound', 'country': 'Egypt'},
    {'code': 'NGN', 'name': 'Nigerian Naira', 'country': 'Nigeria'},
    {'code': 'KES', 'name': 'Kenyan Shilling', 'country': 'Kenya'},
    {'code': 'GHS', 'name': 'Ghanaian Cedi', 'country': 'Ghana'},
    {'code': 'TZS', 'name': 'Tanzanian Shilling', 'country': 'Tanzania'},
    {'code': 'UGX', 'name': 'Ugandan Shilling', 'country': 'Uganda'},
    {'code': 'AED', 'name': 'UAE Dirham', 'country': 'United Arab Emirates'},
    {'code': 'SAR', 'name': 'Saudi Riyal', 'country': 'Saudi Arabia'},
    {'code': 'QAR', 'name': 'Qatari Riyal', 'country': 'Qatar'},
    {'code': 'KWD', 'name': 'Kuwaiti Dinar', 'country': 'Kuwait'},
    {'code': 'BHD', 'name': 'Bahraini Dinar', 'country': 'Bahrain'},
    {'code': 'OMR', 'name': 'Omani Rial', 'country': 'Oman'},
    {'code': 'JOD', 'name': 'Jordanian Dinar', 'country': 'Jordan'},
    {'code': 'LBP', 'name': 'Lebanese Pound', 'country': 'Lebanon'},
    {'code': 'ILS', 'name': 'Israeli Shekel', 'country': 'Israel'},
    {'code': 'TRY', 'name': 'Turkish Lira', 'country': 'Turkey'},
    {'code': 'ARS', 'name': 'Argentine Peso', 'country': 'Argentina'},
    {'code': 'CLP', 'name': 'Chilean Peso', 'country': 'Chile'},
    {'code': 'COP', 'name': 'Colombian Peso', 'country': 'Colombia'},
    {'code': 'PEN', 'name': 'Peruvian Sol', 'country': 'Peru'},
    {'code': 'UYU', 'name': 'Uruguayan Peso', 'country': 'Uruguay'},
    {'code': 'PYG', 'name': 'Paraguayan Guaraní', 'country': 'Paraguay'},
    {'code': 'BOB', 'name': 'Bolivian Boliviano', 'country': 'Bolivia'},
    {'code': 'CRC', 'name': 'Costa Rican Colón', 'country': 'Costa Rica'},
    {'code': 'GTQ', 'name': 'Guatemalan Quetzal', 'country': 'Guatemala'},
    {'code': 'HNL', 'name': 'Honduran Lempira', 'country': 'Honduras'},
    {'code': 'NIO', 'name': 'Nicaraguan Córdoba', 'country': 'Nicaragua'},
    {'code': 'SVN', 'name': 'Salvadoran Colon', 'country': 'El Salvador'},
    {'code': 'DOP', 'name': 'Dominican Peso', 'country': 'Dominican Republic'},
    {'code': 'JMD', 'name': 'Jamaican Dollar', 'country': 'Jamaica'},
    {'code': 'TTD', 'name': 'Trinidad and Tobago Dollar', 'country': 'Trinidad and Tobago'},
    {'code': 'BBD', 'name': 'Barbados Dollar', 'country': 'Barbados'},
    {'code': 'BZD', 'name': 'Belize Dollar', 'country': 'Belize'},
    {'code': 'GYD', 'name': 'Guyanese Dollar', 'country': 'Guyana'},
    {'code': 'FJD', 'name': 'Fijian Dollar', 'country': 'Fiji'},
    {'code': 'PGK', 'name': 'Papua New Guinea Kina', 'country': 'Papua New Guinea'},
    {'code': 'VUV', 'name': 'Vanuatu Vatu', 'country': 'Vanuatu'},
    {'code': 'WST', 'name': 'Samoan Tala', 'country': 'Samoa'},
    {'code': 'TOP', 'name': 'Tongan Paʻanga', 'country': 'Tonga'},
    {'code': 'SBD', 'name': 'Solomon Islands Dollar', 'country': 'Solomon Islands'},
    {'code': 'KID', 'name': 'Kiribati Dollar', 'country': 'Kiribati'},
    {'code': 'TVD', 'name': 'Tuvalu Dollar', 'country': 'Tuvalu'},
    {'code': 'NPR', 'name': 'Nepalese Rupee', 'country': 'Nepal'},
    {'code': 'LKR', 'name': 'Sri Lankan Rupee', 'country': 'Sri Lanka'},
    {'code': 'PKR', 'name': 'Pakistani Rupee', 'country': 'Pakistan'},
    {'code': 'BDT', 'name': 'Bangladeshi Taka', 'country': 'Bangladesh'},
    {'code': 'MMK', 'name': 'Myanmar Kyat', 'country': 'Myanmar'},
    {'code': 'KHR', 'name': 'Cambodian Riel', 'country': 'Cambodia'},
    {'code': 'LAK', 'name': 'Lao Kip', 'country': 'Laos'},
    {'code': 'MOP', 'name': 'Macanese Pataca', 'country': 'Macau'},
    {'code': 'TWD', 'name': 'New Taiwan Dollar', 'country': 'Taiwan'},
    {'code': 'MNT', 'name': 'Mongolian Tugrik', 'country': 'Mongolia'},
    {'code': 'KZT', 'name': 'Kazakhstani Tenge', 'country': 'Kazakhstan'},
    {'code': 'UZS', 'name': 'Uzbekistani Som', 'country': 'Uzbekistan'},
    {'code': 'GEL', 'name': 'Georgian Lari', 'country': 'Georgia'},
    {'code': 'AMD', 'name': 'Armenian Dram', 'country': 'Armenia'},
    {'code': 'AZN', 'name': 'Azerbaijani Manat', 'country': 'Azerbaijan'},
    {'code': 'BGN', 'name': 'Bulgarian Lev', 'country': 'Bulgaria'},
    {'code': 'HRK', 'name': 'Croatian Kuna', 'country': 'Croatia'},
    {'code': 'CZK', 'name': 'Czech Koruna', 'country': 'Czech Republic'},
    {'code': 'HUF', 'name': 'Hungarian Forint', 'country': 'Hungary'},
    {'code': 'RON', 'name': 'Romanian Leu', 'country': 'Romania'},
    {'code': 'RSD', 'name': 'Serbian Dinar', 'country': 'Serbia'},
    {'code': 'UAH', 'name': 'Ukrainian Hryvnia', 'country': 'Ukraine'},
    {'code': 'BYN', 'name': 'Belarusian Ruble', 'country': 'Belarus'},
    {'code': 'MDL', 'name': 'Moldovan Leu', 'country': 'Moldova'},
    {'code': 'ISK', 'name': 'Icelandic Króna', 'country': 'Iceland'},
    {'code': 'ALL', 'name': 'Albanian Lek', 'country': 'Albania'},
    {'code': 'MKD', 'name': 'Macedonian Denar', 'country': 'North Macedonia'},
    {'code': 'BAM', 'name': 'Bosnia and Herzegovina Convertible Mark', 'country': 'Bosnia and Herzegovina'},
    {'code': 'RSD', 'name': 'Montenegrin Euro', 'country': 'Montenegro'},
    {'code': 'XCD', 'name': 'East Caribbean Dollar', 'country': 'East Caribbean States'},
    {'code': 'XOF', 'name': 'West African CFA Franc', 'country': 'West African States'},
    {'code': 'XAF', 'name': 'Central African CFA Franc', 'country': 'Central African States'},
    {'code': 'XPF', 'name': 'CFP Franc', 'country': 'French Polynesia'},
    // Additional currencies
    {'code': 'NZD', 'name': 'New Zealand Dollar', 'country': 'New Zealand'},
    {'code': 'ZMW', 'name': 'Zambian Kwacha', 'country': 'Zambia'},
    {'code': 'BWP', 'name': 'Botswana Pula', 'country': 'Botswana'},
    {'code': 'NAD', 'name': 'Namibian Dollar', 'country': 'Namibia'},
    {'code': 'AOA', 'name': 'Angolan Kwanza', 'country': 'Angola'},
    {'code': 'MZN', 'name': 'Mozambican Metical', 'country': 'Mozambique'},
    {'code': 'ERN', 'name': 'Eritrean Nakfa', 'country': 'Eritrea'},
    {'code': 'ETB', 'name': 'Ethiopian Birr', 'country': 'Ethiopia'},
    {'code': 'SSP', 'name': 'South Sudanese Pound', 'country': 'South Sudan'},
    {'code': 'SOS', 'name': 'Somali Shilling', 'country': 'Somalia'},
    {'code': 'DJF', 'name': 'Djiboutian Franc', 'country': 'Djibouti'},
    {'code': 'CDF', 'name': 'Congolese Franc', 'country': 'Democratic Republic of Congo'},
    {'code': 'SCR', 'name': 'Seychellois Rupee', 'country': 'Seychelles'},
    {'code': 'MUR', 'name': 'Mauritian Rupee', 'country': 'Mauritius'},
    {'code': 'MGA', 'name': 'Malagasy Ariary', 'country': 'Madagascar'},
    {'code': 'MWK', 'name': 'Malawian Kwacha', 'country': 'Malawi'},
    {'code': 'LSL', 'name': 'Lesotho Loti', 'country': 'Lesotho'},
    {'code': 'SZL', 'name': 'Swazi Lilangeni', 'country': 'Eswatini'},
    {'code': 'BIF', 'name': 'Burundian Franc', 'country': 'Burundi'},
    {'code': 'RWF', 'name': 'Rwandan Franc', 'country': 'Rwanda'},
    {'code': 'GMD', 'name': 'Gambian Dalasi', 'country': 'Gambia'},
    {'code': 'CVE', 'name': 'Cape Verdean Escudo', 'country': 'Cape Verde'},
    {'code': 'STN', 'name': 'São Tomé and Príncipe Dobra', 'country': 'São Tomé and Príncipe'},
    {'code': 'GNF', 'name': 'Guinean Franc', 'country': 'Guinea'},
    {'code': 'LRD', 'name': 'Liberian Dollar', 'country': 'Liberia'},
    {'code': 'SLL', 'name': 'Sierra Leonean Leone', 'country': 'Sierra Leone'},
    {'code': 'BND', 'name': 'Brunei Dollar', 'country': 'Brunei'},
    {'code': 'KHR', 'name': 'Cambodian Riel', 'country': 'Cambodia'},
    {'code': 'FJD', 'name': 'Fijian Dollar', 'country': 'Fiji'},
    {'code': 'PGK', 'name': 'Papua New Guinea Kina', 'country': 'Papua New Guinea'},
    {'code': 'SBD', 'name': 'Solomon Islands Dollar', 'country': 'Solomon Islands'},
    {'code': 'VUV', 'name': 'Vanuatu Vatu', 'country': 'Vanuatu'},
    {'code': 'WST', 'name': 'Samoan Tala', 'country': 'Samoa'},
    {'code': 'TOP', 'name': 'Tongan Paʻanga', 'country': 'Tonga'},
    {'code': 'KID', 'name': 'Kiribati Dollar', 'country': 'Kiribati'},
    {'code': 'TVD', 'name': 'Tuvalu Dollar', 'country': 'Tuvalu'},
    {'code': 'MOP', 'name': 'Macanese Pataca', 'country': 'Macau'},
    {'code': 'TMT', 'name': 'Turkmenistan Manat', 'country': 'Turkmenistan'},
    {'code': 'TJS', 'name': 'Tajikistani Somoni', 'country': 'Tajikistan'},
    {'code': 'BTN', 'name': 'Bhutanese Ngultrum', 'country': 'Bhutan'},
    {'code': 'MVR', 'name': 'Maldivian Rufiyaa', 'country': 'Maldives'},
    {'code': 'LAK', 'name': 'Lao Kip', 'country': 'Laos'},
    {'code': 'MMK', 'name': 'Myanmar Kyat', 'country': 'Myanmar'},
    {'code': 'XDR', 'name': 'Special Drawing Rights', 'country': 'International Monetary Fund'},
  ];

  @override
  void initState() {
    super.initState();
    _filteredCurrencies = _allCurrencies;
    _searchController.addListener(_filterCurrencies);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterCurrencies);
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _filterCurrencies() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
        if (_searchQuery.isEmpty) {
          _filteredCurrencies = _allCurrencies;
        } else {
          _filteredCurrencies = _allCurrencies.where((currency) {
            return currency['code']!.toLowerCase().contains(_searchQuery) ||
                   currency['country']!.toLowerCase().contains(_searchQuery) ||
                   currency['name']!.toLowerCase().contains(_searchQuery);
          }).toList();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header with handle
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select Currency',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                // Search bar
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by country or currency code...',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
          // Currency list
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _filteredCurrencies.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No currencies found',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 20),
                      itemCount: _filteredCurrencies.length,
                      itemBuilder: (context, index) {
                        final currency = _filteredCurrencies[index];
                        final isSelected = currency['code'] == widget.currentCurrency;

                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          child: ListTile(
                            leading: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _getCurrencyColor(currency['code']!).withOpacity(0.2)
                                    : _getCurrencyColor(currency['code']!).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: isSelected
                                      ? _getCurrencyColor(currency['code']!).withOpacity(0.5)
                                      : _getCurrencyColor(currency['code']!).withOpacity(0.3),
                                  width: 2,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  currency['code']!,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: isSelected
                                        ? _getCurrencyColor(currency['code']!)
                                        : _getCurrencyColor(currency['code']!),
                                  ),
                                ),
                              ),
                            ),
                            title: Text(
                              currency['country']!,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Text(
                              currency['name']!,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            trailing: isSelected
                                ? Icon(Icons.check_circle, color: Colors.blue.shade600)
                                : null,
                            onTap: () {
                              widget.onCurrencySelected(currency['code']!);
                            },
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}