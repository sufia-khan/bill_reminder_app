import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:projeckt_k/screens/profile_screen.dart';
import 'package:projeckt_k/services/subscription_service.dart';
import 'package:projeckt_k/services/notification_service.dart';
import 'package:projeckt_k/models/category_model.dart';
import 'package:projeckt_k/widgets/subtitle_changing.dart';
import 'package:projeckt_k/widgets/bill_summary_cards.dart';
import 'package:projeckt_k/widgets/bill_item_widget.dart';
import 'package:projeckt_k/widgets/category_bills_bottom_sheet.dart';

final Color kPrimaryColor = HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor();
final Color bgUpcomingMuted = HSLColor.fromAHSL(
  1.0,
  45.0,
  0.93,
  0.95,
).toColor();

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  // --- state fields (must be inside the State class) ---
  List<Map<String, dynamic>> _bills = [];
  final SubscriptionService _subscriptionService = SubscriptionService();
  bool _isLoading = false;
  bool _hasError = false;
  bool _isOnline = false;
  StreamSubscription<bool>? _connectivitySubscription;
  final ValueNotifier<bool> _connectivityNotifier = ValueNotifier<bool>(false);
  Timer? _updateTimer;
  String selectedCategory = 'all'; // 'all' or specific category id
  String selectedStatus = 'upcoming'; // 'upcoming', 'overdue', 'paid'
  final ScrollController _categoryScrollController = ScrollController();
  // base sizes for "This Month"
  double baseBottomAmountFontSize = 14;
  double baseBottomTextFontSize = 13;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    debugPrint('🚀 Initializing app...');
    await _initServices();
    await _checkConnectivity();
    await _loadSubscriptions();
    _setupConnectivityListener();
    _startPeriodicUpdates();
    debugPrint('✅ App initialization completed');
  }

  Future<void> _initServices() async {
    await _subscriptionService.init();

    // Set up notification callback for mark as paid action
    final notificationService = NotificationService();
    notificationService.onMarkAsPaid = (String? billId) {
      debugPrint('📝 Mark as paid callback received for bill ID: $billId');
      if (billId != null) {
        _markBillAsPaidFromNotification(billId);
      }
    };
  }

  @override
  void dispose() {
    _categoryScrollController.dispose();
    _connectivitySubscription?.cancel();
    _connectivityNotifier.dispose();
    _updateTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    final isOnline = await _subscriptionService.isOnline();
    debugPrint('Network status check: $isOnline');
    if (mounted) {
      setState(() {
        _isOnline = isOnline;
      });
      _connectivityNotifier.value = isOnline;
    }
  }

  void _setupConnectivityListener() {
    bool wasOffline = false;

    _connectivitySubscription = _subscriptionService
        .connectivityStream()
        .listen((isOnline) {
          debugPrint('Connectivity stream update: $isOnline (was offline: $wasOffline)');
          if (mounted) {
            setState(() {
              _isOnline = isOnline;
            });
            _connectivityNotifier.value = isOnline;

            // Auto-sync only when transitioning from offline to online
            if (isOnline && wasOffline) {
              debugPrint('🔄 Back online! Triggering auto-sync...');
              _autoSyncWhenOnline();
            }

            wasOffline = !isOnline;
          }
        });
  }

  void _startPeriodicUpdates() {
    // Update every minute to check for overdue bills
    _updateTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        _checkForOverdueBills();
      }
    });
  }

  void _checkForOverdueBills() {
    bool needsUpdate = false;
    final now = DateTime.now();
    final notificationService = NotificationService();

    for (var bill in _bills) {
      try {
        final dueDate = _parseDueDate(bill);
        if (dueDate != null &&
            bill['status'] != 'paid' &&
            dueDate.isBefore(now) &&
            bill['status'] != 'overdue') {
          // Mark bill as overdue
          bill['status'] = 'overdue';
          needsUpdate = true;

          // Send immediate overdue notification
          _sendOverdueBillNotification(bill, notificationService);
        }
      } catch (e) {
        debugPrint('Error checking overdue bill: $e');
      }
    }

    if (needsUpdate && mounted) {
      setState(() {});
    }
  }

  Future<void> _sendOverdueBillNotification(
    Map<String, dynamic> bill,
    NotificationService notificationService,
  ) async {
    try {
      final billName = bill['name'] ?? 'Unknown Bill';
      final billAmount = bill['amount'] ?? '0';
      final id = bill['id'] ?? DateTime.now().millisecondsSinceEpoch;

      debugPrint('🚨 Sending overdue notification for bill: $billName');

      await notificationService.showImmediateNotification(
        title: '🚨 OVERDUE: $billName',
        body:
            'Your bill for $billAmount is overdue. Please pay as soon as possible.',
        payload: id.toString(),
      );
    } catch (e) {
      debugPrint('Error sending overdue notification: $e');
    }
  }

  // Mark bill as paid (for notification action)
  Future<void> _markBillAsPaidFromNotification(String billId) async {
    debugPrint('📝 Marking bill as paid from notification: $billId');

    try {
      // Find the bill by ID
      final billIndex = _bills.indexWhere(
        (bill) =>
            bill['id']?.toString() == billId ||
            bill['firebaseId']?.toString() == billId ||
            bill['localId']?.toString() == billId,
      );

      if (billIndex != -1) {
        final bill = _bills[billIndex];
        await _markBillAsPaid(billIndex);

        // Cancel the notification for this bill
        final notificationService = NotificationService();
        final notificationId =
            bill['notificationId'] ??
            int.tryParse(billId) ??
            DateTime.now().millisecondsSinceEpoch;
        notificationService.cancelNotification(notificationId);

        debugPrint('✅ Bill marked as paid and notification cancelled');
      } else {
        debugPrint('❌ Bill not found with ID: $billId');
      }
    } catch (e) {
      debugPrint('Error marking bill as paid from notification: $e');
    }
  }

  Future<void> _autoSyncWhenOnline() async {
    try {
      debugPrint('🔄 Auto-sync triggered!');
      final unsyncedCount = await _subscriptionService.getUnsyncedSubscriptionsCount();
      debugPrint('🔄 Found $unsyncedCount unsynced items');

      if (unsyncedCount > 0) {
        // Show syncing indicator
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Syncing your changes...'),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 2),
            ),
          );
        }

        final success = await _subscriptionService.syncLocalToFirebase();

        if (mounted) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ Synced $unsyncedCount items to cloud!'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('❌ Some items failed to sync'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        debugPrint('✅ No items to sync');
      }
    } catch (e) {
      debugPrint('❌ Auto-sync failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool?> _showDeleteConfirmDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Bill'),
        content: const Text(
          'Are you sure you want to delete this bill? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _editBill(int index) async {
    if (index < 0 || index >= _bills.length) return;

    final bill = _bills[index];

    // Create a clean copy of the bill data for editing
    final cleanBill = Map<String, dynamic>.from(bill);

    await showAddBillBottomSheet(context, bill: cleanBill, editIndex: index);
  }

  Future<bool?> _showMarkAsPaidConfirmDialog(
    BuildContext context,
    String billName,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as Paid'),
        content: Text(
          'Have you paid "$billName"? This will move it to the Paid category.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('Yes, Mark as Paid'),
          ),
        ],
      ),
    );
  }

  Future<void> _markBillAsPaid(int index) async {
    if (index < 0 || index >= _bills.length) return;

    try {
      final bill = _bills[index];

      // Update the bill with paid status and paid date
      final updatedBill = Map<String, dynamic>.from(bill);
      updatedBill['status'] = 'paid';
      updatedBill['paidDate'] = DateTime.now().toIso8601String();
      updatedBill['lastModified'] = DateTime.now().toIso8601String();

      // Try to update in Firestore first
      if (bill['firebaseId'] != null) {
        await _subscriptionService.updateSubscription(
          bill['firebaseId'],
          updatedBill,
        );
      } else if (bill['localId'] != null) {
        await _subscriptionService.updateSubscription(
          bill['localId'],
          updatedBill,
        );
      }

      // Update local state immediately
      if (mounted) {
        setState(() {
          _bills[index] = updatedBill;
        });
      }

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bill marked as paid successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Note: Removed _loadSubscriptions() call as it was overriding the paid status
      // Local state is already updated and other sync mechanisms handle data consistency
    } catch (e) {
      debugPrint('Error marking bill as paid: $e');

      // If Firestore fails, update locally only
      try {
        final bill = _bills[index];
        final updatedBill = Map<String, dynamic>.from(bill);
        updatedBill['status'] = 'paid';
        updatedBill['paidDate'] = DateTime.now().toIso8601String();

        if (mounted) {
          setState(() {
            _bills[index] = updatedBill;
          });
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Bill marked as paid locally. Will sync when online.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      } catch (localError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to mark bill as paid: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  Future<void> _updateBill(int index, Map<String, dynamic> updatedBill) async {
    if (index < 0 || index >= _bills.length) return;

    // Get the original bill for reference
    final originalBill = _bills[index];
    final billId = originalBill['id'];

    // Add timestamp for tracking
    updatedBill['lastModified'] = DateTime.now().toIso8601String();

    // Show loading indicator
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Updating bill...'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 1),
        ),
      );
    }

    try {
      // Update UI immediately
      if (mounted) {
        setState(() {
          _bills[index] = Map.from(originalBill)..addAll(updatedBill);
          _checkForOverdueBills();
        });
      }

      // Save to local storage
      if (originalBill['localId'] != null) {
        await _subscriptionService.localStorageService?.updateSubscription(
          originalBill['localId'],
          _bills[index],
        );
      } else {
        // Create new local ID if needed
        _bills[index]['localId'] = DateTime.now().millisecondsSinceEpoch.toString();
        await _subscriptionService.localStorageService?.saveSubscription(_bills[index]);
      }

      // Update reminders
      await _updateBillReminders(_bills[index]);

      // Check connectivity
      await _checkConnectivity();

      if (_isOnline && billId != null) {
        // Update in Firebase
        await _subscriptionService.updateSubscription(billId, updatedBill);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${updatedBill['name']} updated successfully!'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${updatedBill['name']} saved locally. Will sync when online.'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error updating bill: $e');
      // Re-check connectivity to make sure it's actually offline
      await _checkConnectivity();

      // Even if Firebase fails, update locally
      if (mounted) {
        setState(() {
          _bills[index] = Map.from(originalBill)..addAll(updatedBill);
          _checkForOverdueBills(); // Immediate check for overdue status
        });

        // Update reminders locally
        await _updateBillReminders(_bills[index]);

        if (!_isOnline) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${updatedBill['name']} updated locally. Will sync when online.',
              ),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        } else {
          // If online but Firebase failed, still show success for local update
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${updatedBill['name']} updated successfully!'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }
      }
    }
  }

  /// Update reminders for a bill when it's edited
  Future<void> _updateBillReminders(Map<String, dynamic> bill) async {
    try {
      final notificationService = NotificationService();

      // Cancel existing reminders for this bill
      if (bill['id'] != null) {
        await notificationService.cancelNotification(
          int.tryParse(bill['id'].toString()) ?? 0,
        );
      }

      // Schedule new reminder if needed
      if (bill['reminder'] != null &&
          bill['reminder'] != 'No reminder' &&
          bill['status'] != 'paid') {
        final dueDateTime = _parseDueDate(bill);
        if (dueDateTime != null) {
          final billId = bill['id'] != null
              ? int.tryParse(bill['id'].toString()) ??
                    DateTime.now().millisecondsSinceEpoch
              : DateTime.now().millisecondsSinceEpoch;

          await notificationService.scheduleBillReminder(
            id: billId,
            title: bill['name'] ?? 'Unknown Bill',
            body: 'Payment of \$${bill['amount'] ?? '0.0'} is due',
            dueDate: dueDateTime,
            reminderPreference: bill['reminder'] ?? 'Same day',
            payload: bill['id']?.toString(),
          );
        }
      }
    } catch (e) {
      debugPrint('Error updating bill reminders: $e');
      // Don't show error to user for reminder issues, as the main update was successful
    }
  }


  // Helper method to parse due date with time
  DateTime? _parseDueDate(Map<String, dynamic> bill) {
    try {
      // If we have the full ISO date time string, use that
      if (bill['dueDateTime'] != null) {
        return DateTime.parse(bill['dueDateTime']);
      }

      // Otherwise parse from date and time strings
      final dueDateStr = bill['dueDate']?.toString() ?? '';
      if (dueDateStr.isEmpty) return null;

      final parts = dueDateStr.split('/');
      if (parts.length != 3) return null;

      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);

      // Parse time if available, otherwise use default time
      int hour = 0;
      int minute = 0;

      if (bill['dueTime'] != null) {
        final timeStr = bill['dueTime'].toString();
        final timeParts = timeStr.split(RegExp(r'[:\s]'));
        if (timeParts.isNotEmpty) {
          // Handle time format like "8:30 AM" or "14:30"
          if (timeStr.contains('AM') || timeStr.contains('PM')) {
            // 12-hour format
            hour = int.parse(timeParts[0]);
            minute = int.parse(timeParts[1]);
            if (timeStr.contains('PM') && hour != 12) {
              hour += 12;
            }
            if (timeStr.contains('AM') && hour == 12) {
              hour = 0;
            }
          } else {
            // 24-hour format
            hour = int.parse(timeParts[0]);
            minute = int.parse(timeParts[1]);
          }
        }
      } 

      return DateTime(year, month, day, hour, minute);
    } catch (e) {
      debugPrint('Error parsing due date: $e');
      return null;
    }
  }

  // Helper method to calculate reminder date based on reminder preference
  DateTime _calculateReminderDate(DateTime dueDate, String reminderPreference) {
    switch (reminderPreference) {
      case 'Same day':
        return dueDate;
      case '1 day before':
        return dueDate.subtract(const Duration(days: 1));
      case '3 days before':
        return dueDate.subtract(const Duration(days: 3));
      case '1 week before':
        return dueDate.subtract(const Duration(days: 7));
      default:
        return dueDate;
    }
  }

  double _parseAmount(dynamic amount) {
    if (amount == null) return 0.0;
    if (amount is num) return amount.toDouble();
    if (amount is String) return double.tryParse(amount) ?? 0.0;
    return 0.0;
  }

  double _calculateMonthlyTotal() {
    double total = 0;
    final now = DateTime.now();
    final currentMonth = now.month;
    final currentYear = now.year;

    for (var bill in _bills) {
      try {
        final amount = _parseAmount(bill['amount']);
        final dueDateStr = bill['dueDate']?.toString() ?? '';

        if (dueDateStr.isNotEmpty) {
          final parts = dueDateStr.split('/');
          if (parts.length == 3) {
            final day = int.parse(parts[0]);
            final month = int.parse(parts[1]);
            final year = int.parse(parts[2]);

            if (month == currentMonth && year == currentYear) {
              total += amount;
            }
          }
        }
      } catch (e) {
        debugPrint('Error calculating monthly total: $e');
      }
    }
    return total;
  }

  double _calculateMonthlyDifference() {
    // Calculate actual difference based on last month's data
    final now = DateTime.now();
    final lastMonth = now.month == 1 ? 12 : now.month - 1;
    final lastMonthYear = now.month == 1 ? now.year - 1 : now.year;

    double thisMonthTotal = _calculateMonthlyTotal();
    double lastMonthTotal = 0;

    for (var bill in _bills) {
      try {
        final amount = _parseAmount(bill['amount']);
        final dueDateStr = bill['dueDate']?.toString() ?? '';

        if (dueDateStr.isNotEmpty) {
          final parts = dueDateStr.split('/');
          if (parts.length == 3) {
            final month = int.parse(parts[1]);
            final year = int.parse(parts[2]);

            if (month == lastMonth && year == lastMonthYear) {
              lastMonthTotal += amount;
            }
          }
        }
      } catch (e) {
        debugPrint('Error calculating last month total: $e');
      }
    }

    return thisMonthTotal - lastMonthTotal;
  }

  // Helper method for upcoming bills count (next 7 days)
  int _getUpcoming7DaysCount() {
    int count = 0;
    final now = DateTime.now();
    final sevenDaysFromNow = now.add(const Duration(days: 7));

    for (var bill in _bills) {
      try {
        final dueDate = _parseDueDate(bill);
        if (dueDate != null) {
          // Count bills that are due within the next 7 days (inclusive) and not yet paid
          if ((dueDate.isAtSameMomentAs(now) || dueDate.isAfter(now)) &&
              (dueDate.isAtSameMomentAs(sevenDaysFromNow) ||
                  dueDate.isBefore(sevenDaysFromNow)) &&
              bill['status'] != 'paid') {
            count++;
          }
        }
      } catch (e) {
        debugPrint('Error getting upcoming 7 days count: $e');
      }
    }
    return count;
  }

  // Helper method to get total amount for upcoming bills (next 7 days)
  double _getUpcoming7DaysTotal() {
    double total = 0.0;
    final now = DateTime.now();
    final sevenDaysFromNow = now.add(const Duration(days: 7));

    for (var bill in _bills) {
      try {
        final dueDate = _parseDueDate(bill);
        if (dueDate != null) {
          // Sum bills that are due within the next 7 days (inclusive) and not yet paid
          if ((dueDate.isAtSameMomentAs(now) || dueDate.isAfter(now)) &&
              (dueDate.isAtSameMomentAs(sevenDaysFromNow) ||
                  dueDate.isBefore(sevenDaysFromNow)) &&
              bill['status'] != 'paid') {
            final amount =
                double.tryParse(bill['amount']?.toString() ?? '0') ?? 0.0;
            total += amount;
          }
        }
      } catch (e) {
        debugPrint('Error calculating upcoming 7 days total: $e');
      }
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    // shared heights you used earlier
    const double sharedTop = 36;
    const double sharedMiddle = 72;
    const double sharedBottom = 45;

    return Scaffold(
      appBar: null,
      // ensure scaffold background is white
      backgroundColor: Colors.white,
      // don't draw body behind status bar (we already use SafeArea in the header)
      extendBodyBehindAppBar: false,
      body: Container(
        color: Colors.white, // make the entire page white explicitly
        child: Column(
          children: [
            // Custom header container
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Top row: icon + title/subtitle + profile + sync status
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.notifications_active_rounded,
                                color: Colors.orange,
                                size: 25,
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'SubManager',
                                    style: GoogleFonts.montserrat(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 23,
                                    ),
                                  ),

                                  const SizedBox(height: 2),
                                  const ChangingSubtitle(),
                                ],
                              ),
                            ],
                          ),

                          // Sync status and profile row
                          Row(
                            children: [
                              // Enhanced network status indicator
                              ValueListenableBuilder<bool>(
                                valueListenable: _connectivityNotifier,
                                builder: (context, isOnline, child) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isOnline
                                          ? Colors.green.withValues(alpha: 0.1)
                                          : Colors.grey.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isOnline
                                            ? Colors.green.withValues(
                                                alpha: 0.3,
                                              )
                                            : Colors.grey.withValues(
                                                alpha: 0.3,
                                              ),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          child: Icon(
                                            isOnline
                                                ? Icons.wifi
                                                : Icons.wifi_off,
                                            color: isOnline
                                                ? Colors.green
                                                : Colors.grey,
                                            size: 14,
                                            key: ValueKey(isOnline),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          isOnline ? 'Online' : 'Offline',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                            color: isOnline
                                                ? Colors.green[700]
                                                : Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 16),
                              // Profile (kept inside the same top row)
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const ProfileScreen(),
                                    ),
                                  );
                                },
                                child: Column(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: Colors.indigoAccent
                                          .withValues(alpha: 0.15), // light bg
                                      child: Icon(
                                        Icons.person, // 🔄 subscription icon
                                        color:
                                            Colors.indigoAccent, // main color
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: BillSummaryCard(
                              title: "This Month",
                              icon: Icons.trending_up_rounded,
                              gradientColors: [
                                HSLColor.fromAHSL(
                                  1.0,
                                  250,
                                  0.84,
                                  0.60,
                                ).toColor(),
                                HSLColor.fromAHSL(
                                  1.0,
                                  280,
                                  0.75,
                                  0.65,
                                ).toColor(),
                              ],
                              primaryValue:
                                  "\$${_calculateMonthlyTotal().toStringAsFixed(2)}",
                              secondaryAmount:
                                  "\$${_calculateMonthlyDifference().abs().toStringAsFixed(2)}",
                              secondaryText: _calculateMonthlyDifference() > 0
                                  ? "more than last month"
                                  : "less than last month",
                              topBoxHeight: sharedTop,
                              middleBoxHeight: sharedMiddle,
                              bottomBoxHeight: sharedBottom,
                              // keep This Month bottom sizes as before
                              bottomAmountFontSize: 14,
                              bottomTextFontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: BillSummaryCard(
                              title: "Next 7 Days",
                              icon: Icons.calendar_today_rounded,
                              gradientColors: [
                                HSLColor.fromAHSL(
                                  1.0,
                                  30,
                                  0.85,
                                  0.60,
                                ).toColor(),
                                HSLColor.fromAHSL(
                                  1.0,
                                  15,
                                  0.85,
                                  0.55,
                                ).toColor(),
                              ],
                              primaryValue:
                                  "\$${_getUpcoming7DaysTotal().toStringAsFixed(2)}",

                              // increase the bottom (count) size here:
                              secondaryText:
                                  "${_getUpcoming7DaysCount()} bills",
                              topBoxHeight: sharedTop,
                              middleBoxHeight: sharedMiddle,
                              bottomBoxHeight: sharedBottom,
                              // larger bottom fonts for emphasis
                              bottomAmountFontSize:
                                  20, // if you show an amount here, it'll be bigger
                              bottomTextFontSize:
                                  22, // <-- increased size for the "X bills" text
                              minBottomFontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Main content
            Expanded(
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.all(6),
                child: RefreshIndicator(
                  onRefresh: _loadSubscriptions,
                  color: Colors.white,
                  backgroundColor: Colors.transparent,
                  displacement: 40,
                  strokeWidth: 3,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(top: 6),
                    children: [
                      // Category Tabs Section
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Categories',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              height: 60,
                              child: RawScrollbar(
                                thumbColor: HSLColor.fromAHSL(
                                  1.0,
                                  236,
                                  0.89,
                                  0.75,
                                ).toColor(),
                                radius: const Radius.circular(20),
                                thickness: 4,
                                thumbVisibility: true,
                                controller: _categoryScrollController,
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  controller: _categoryScrollController,
                                  child: Row(
                                    children: _buildCategoryTabsList(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Status Tabs Bar
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(children: _buildStatusTabsList()),
                      ),

                      const SizedBox(height: 16),

                      // Filtered Bills Content
                      Container(
                        constraints: BoxConstraints(
                          minHeight: MediaQuery.of(context).size.height * 0.4,
                        ),
                        child: _buildFilteredBillsContent(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Status Tabs and Content Methods
  List<Widget> _buildStatusTabsList() {
    List<Widget> tabs = [];

    final statusOptions = [
      {'id': 'upcoming', 'title': 'Upcoming', 'icon': Icons.calendar_today},
      {'id': 'overdue', 'title': 'Overdue', 'icon': Icons.warning},
      {'id': 'paid', 'title': 'Paid', 'icon': Icons.check_circle},
    ];

    for (var status in statusOptions) {
      tabs.add(
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                selectedStatus = status['id'] as String;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: selectedStatus == status['id']
                    ? HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor()
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    status['icon'] as IconData,
                    color: selectedStatus == status['id']
                        ? Colors.white
                        : Colors.grey[600],
                    size: 20,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    status['title'] as String,
                    style: TextStyle(
                      color: selectedStatus == status['id']
                          ? Colors.white
                          : Colors.grey[600],
                      fontWeight: selectedStatus == status['id']
                          ? FontWeight.w600
                          : FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return tabs;
  }

  // Category Tabs and Content Methods
  List<Widget> _buildCategoryTabsList() {
    List<Widget> tabs = [];

    // "All" tab
    tabs.add(
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: _buildCategoryTab(
          title: 'All',
          isSelected: selectedCategory == 'all',
          onTap: () {
            setState(() {
              selectedCategory = 'all';
            });
          },
        ),
      ),
    );

    // Category tabs
    for (var category in Category.defaultCategories) {
      tabs.add(
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _buildCategoryTab(
            title: category.name,
            isSelected: selectedCategory == category.id,
            onTap: () {
              setState(() {
                selectedCategory = category.id;
              });
            },
          ),
        ),
      );
    }

    return tabs;
  }

  Widget _buildCategoryTab({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? HSLColor.fromAHSL(1.0, 236, 0.89, 0.75)
                    .toColor() // 🔹 same as bottom nav
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? null
              : Border.all(color: Colors.grey[300]!, width: 1),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryContent() {
    return Column(
      children: [
        // Category Selector
        Container(
          height: 40,
          margin: const EdgeInsets.only(bottom: 16),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _buildCategoryTabsList().length,
            itemBuilder: (context, index) {
              return _buildCategoryTabsList()[index];
            },
          ),
        ),

        // Filtered Bills Content
        Expanded(child: _buildFilteredBillsContent()),
      ],
    );
  }

  Widget _buildFilteredBillsContent() {
    // Filter bills based on selected status and category
    List<Map<String, dynamic>> filteredBills = [];

    final now = DateTime.now();

    debugPrint(
      '🔍 Filtering bills - Status: $selectedStatus, Category: $selectedCategory, Total bills: ${_bills.length}',
    );

    // Debug: Print available categories and selected category
    debugPrint('🔍 Selected category: "$selectedCategory"');
    debugPrint('🔍 Available categories in bills:');
    final availableCategories = _bills
        .map((bill) => bill['category']?.toString())
        .where((cat) => cat != null)
        .toSet();
    debugPrint('  - Categories found: $availableCategories');

    for (var bill in _bills) {
      try {
        final dueDate = _parseDueDate(bill);

        // Quick status check first (more efficient)
        final billStatus = bill['status']?.toString() ?? '';
        bool matchesStatus = false;

        // Debug status for specific bill that matches category
        if (bill['name'] == 'health health ') {
          debugPrint(
            '🔍 Status debug - Bill: "${bill['name']}", Status: "$billStatus", DueDate: $dueDate, SelectedStatus: "$selectedStatus"',
          );
        }

        switch (selectedStatus) {
          case 'all':
            // Show reminders for upcoming bills (unpaid bills with due dates)
            matchesStatus = billStatus != 'paid' && dueDate != null;
            break;
          case 'upcoming':
            matchesStatus =
                billStatus != 'paid' &&
                dueDate != null &&
                dueDate.isAfter(now) &&
                dueDate.isBefore(now.add(const Duration(days: 30)));
            break;
          case 'overdue':
            matchesStatus =
                billStatus != 'paid' &&
                dueDate != null &&
                dueDate.isBefore(now);
            break;
          case 'paid':
            matchesStatus = billStatus == 'paid';
            break;
        }

        // Quick category check (more efficient)
        final billCategory = bill['category']?.toString();
        bool matchesCategory = false;

        if (selectedCategory == 'all') {
          matchesCategory = true;
        } else {
          // Try multiple matching strategies for category
          if (billCategory == null) {
            // Skip bills with no category when specific category is selected
            matchesCategory = false;
          } else {
            final exactMatch = billCategory == selectedCategory;
            final containsMatch = billCategory.contains(selectedCategory);
            final caseInsensitiveMatch =
                billCategory.toLowerCase() == selectedCategory.toLowerCase();

            matchesCategory =
                exactMatch || containsMatch || caseInsensitiveMatch;
          }

          // Debug: Print first few matching attempts
          if (filteredBills.length < 2) {
            debugPrint(
              '🔍 Category check - Bill: "${bill['name']}", Category: "$billCategory", Selected: "$selectedCategory", Match: $matchesCategory',
            );
          }
        }

        // Only add bill if both filters match
        if (matchesStatus && matchesCategory) {
          filteredBills.add(bill);
          if (bill['name'] == 'health health ') {
            debugPrint(
              '🔍 Bill "${bill['name']}" ADDED - Status: $matchesStatus, Category: $matchesCategory',
            );
          }
        } else if (matchesCategory) {
          if (bill['name'] == 'health health ') {
            debugPrint(
              '🔍 Bill "${bill['name']}" FILTERED OUT - Status: $matchesStatus, Category: $matchesCategory',
            );
          }
        }
      } catch (e) {
        debugPrint('Error filtering bill: $e');
      }
    }

    // Sort by due date
    filteredBills.sort((a, b) {
      final aDate = _parseDueDate(a);
      final bDate = _parseDueDate(b);
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return aDate.compareTo(bDate);
    });

    debugPrint('🔍 Final filtered bills count: ${filteredBills.length}');

    if (filteredBills.isEmpty) {
      // Check if there are any bills in this category at all (regardless of status)
      final hasBillsInCategory = selectedCategory == 'all'
          ? _bills.isNotEmpty
          : _bills.any(
              (bill) => bill['category']?.toString() == selectedCategory,
            );

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              hasBillsInCategory
                  ? 'No ${selectedStatus} bills${selectedCategory != 'all' ? ' in ${Category.findById(selectedCategory)?.name ?? selectedCategory}' : ''}'
                  : 'No bills in ${selectedCategory != 'all' ? Category.findById(selectedCategory)?.name ?? selectedCategory : 'any category'}',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasBillsInCategory
                  ? 'Try selecting a different status (Upcoming, Paid, Overdue)'
                  : 'Add a new bill to get started',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: filteredBills.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        final bill = filteredBills[index];
        // Find the original index in _bills for proper editing/deletion
        final originalIndex = _bills.indexWhere(
          (b) =>
              b['id'] == bill['id'] ||
              b['firebaseId'] == bill['firebaseId'] ||
              b['localId'] == bill['localId'],
        );
        return _buildBillCard(bill, originalIndex);
      },
    );
  }

  Widget _buildBillCard(Map<String, dynamic> bill, int index) {
    final dueDate = _parseDueDate(bill);
    final now = DateTime.now();
    final isOverdue =
        dueDate != null && dueDate.isBefore(now) && bill['status'] != 'paid';
    final isPaid = bill['status'] == 'paid';
    final category = bill['category'] != null
        ? Category.findById(bill['category'].toString())
        : null;

    // Determine status color and text
    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (isPaid) {
      statusColor = Colors.green;
      statusText = 'Paid';
      statusIcon = Icons.check_circle;
    } else if (isOverdue) {
      statusColor = Colors.red;
      statusText = 'Overdue';
      statusIcon = Icons.warning;
    } else {
      statusColor = Colors.orange;
      statusText = 'Upcoming';
      statusIcon = Icons.calendar_today;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isOverdue
                ? Colors.red.withValues(alpha: 0.3)
                : Colors.transparent,
            width: isOverdue ? 1 : 0,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row with title and status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        // Category icon
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color:
                                category?.backgroundColor ?? Colors.grey[200],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            category?.icon ?? Icons.receipt,
                            color: category?.color ?? Colors.grey[700],
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Bill name and amount
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                bill['name']?.toString() ?? 'Unnamed Bill',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '\$${bill['amount']?.toString() ?? '0.00'}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Status indicator
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, color: statusColor, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Divider
              const SizedBox(height: 12),
              const Divider(height: 1),

              // Due date and actions row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Due date
                  Row(
                    children: [
                      Icon(Icons.event, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Text(
                        dueDate != null
                            ? '${dueDate.day.toString().padLeft(2, '0')}/${dueDate.month.toString().padLeft(2, '0')}/${dueDate.year}'
                            : 'No due date',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),

                  // Action buttons
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isPaid)
                        TextButton.icon(
                          onPressed: () async {
                            bool? confirm = await _showMarkAsPaidConfirmDialog(
                              context,
                              bill['name']?.toString() ?? 'this bill',
                            );
                            if (confirm == true) {
                              await _markBillAsPaid(index);
                            }
                          },
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('Pay'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () async {
                          await _editBill(index);
                        },
                        icon: const Icon(Icons.edit, size: 16),
                        style: IconButton.styleFrom(
                          foregroundColor: Colors.blue,
                          padding: const EdgeInsets.all(4),
                        ),
                      ),
                      IconButton(
                        onPressed: () async {
                          bool? confirm = await _showDeleteConfirmDialog(
                            context,
                          );
                          if (confirm == true) {
                            await _deleteSubscription(index);
                          }
                        },
                        icon: const Icon(Icons.delete, size: 16),
                        style: IconButton.styleFrom(
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.all(4),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllCategoriesContent() {
    // Get all categories that have bills
    final categoriesWithBills = <String, List<Map<String, dynamic>>>{};

    for (var bill in _bills) {
      final categoryId = bill['category'] ?? 'other';
      if (!categoriesWithBills.containsKey(categoryId)) {
        categoriesWithBills[categoryId] = [];
      }
      categoriesWithBills[categoryId]!.add(bill);
    }

    // Sort categories by their most upcoming bill
    final sortedCategories = categoriesWithBills.entries.toList()
      ..sort((a, b) {
        final aEarliest = a.value.isEmpty ? null : _parseDueDate(a.value.first);
        final bEarliest = b.value.isEmpty ? null : _parseDueDate(b.value.first);

        if (aEarliest == null && bEarliest == null) return 0;
        if (aEarliest == null) return 1;
        if (bEarliest == null) return -1;

        return aEarliest.compareTo(bEarliest);
      });

    if (sortedCategories.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            'No bills found in any category',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }

    return Column(
      children: sortedCategories.map((entry) {
        final categoryId = entry.key;
        final categoryBills = entry.value;
        final category = Category.findById(categoryId);

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildCategorySection(
            category: category,
            bills: categoryBills,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSingleCategoryContent(String categoryId) {
    final categoryBills = _bills
        .where((bill) => bill['category'] == categoryId)
        .toList();
    final category = Category.findById(categoryId);

    if (categoryBills.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            'No bills found in ${category?.name ?? categoryId}',
            style: const TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }

    return _buildCategorySection(category: category, bills: categoryBills);
  }

  Widget _buildCategorySection({
    required Category? category,
    required List<Map<String, dynamic>> bills,
  }) {
    // Sort bills by due date
    bills.sort((a, b) {
      final aDate = _parseDueDate(a);
      final bDate = _parseDueDate(b);
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return aDate.compareTo(bDate);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category name header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            category?.name ?? 'Unknown Category',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor(),
            ),
          ),
        ),
        // Bills card
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: bills.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: Colors.grey[200]),
            itemBuilder: (_, index) => BillItemWidget(
              bill: {...bills[index], 'index': index},
              onMarkAsPaid: (billIndex) async {
                bool? confirm = await _showMarkAsPaidConfirmDialog(
                  context,
                  bills[billIndex]['name'] ?? 'this bill',
                );
                if (confirm == true) {
                  await _markBillAsPaid(billIndex);
                }
              },
              onDelete: (billIndex) async {
                bool? confirm = await _showDeleteConfirmDialog(context);
                if (confirm == true) {
                  await _deleteSubscription(billIndex);
                }
              },
              onEdit: (billData) async {
                await _editBill(billData['originalIndex']);
              },
              onShowDetails: (billData) {
                // Show bill details if needed
              },
              useHomeScreenEdit: true,
            ),
          ),
        ),
      ],
    );
  }

  // Helper method to format date
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = date.difference(now);

    if (difference.inDays == 0) return 'Today';
    if (difference.inDays == 1) return 'Tomorrow';
    if (difference.inDays == -1) return 'Yesterday';
    if (difference.inDays > 0 && difference.inDays <= 7) {
      return '${difference.inDays} days from now';
    }
    if (difference.inDays < 0 && difference.inDays >= -7) {
      return '${difference.inDays.abs()} days ago';
    }

    return '${date.day}/${date.month}/${date.year}';
  }

  
  // Delete bill
  void _deleteBill(int billIndex) {
    if (billIndex >= 0 && billIndex < _bills.length) {
      final billName = _bills[billIndex]['name'] ?? 'Unknown Bill';

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Bill'),
          content: Text('Are you sure you want to delete "$billName"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  final bill = _bills[billIndex];
                  final billId = bill['id'] ?? bill['firebaseId'];

                  if (billId != null) {
                    // Delete from Firebase and local storage
                    await _subscriptionService.deleteSubscription(billId);
                  }

                  setState(() {
                    _bills.removeAt(billIndex);
                  });
                  Navigator.pop(context);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$billName deleted permanently!'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                } catch (e) {
                  setState(() {
                    _bills.removeAt(billIndex);
                  });
                  Navigator.pop(context);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '$billName deleted. Changes will sync when online.',
                      ),
                      backgroundColor: Colors.orange,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
    }
  }

  // Show quick edit bottom sheet
  void _showQuickEditSheet(BuildContext context, Map<String, dynamic> bill) {
    final nameController = TextEditingController(text: bill['name'] ?? '');
    final amountController = TextEditingController(text: bill['amount'] ?? '');
    final dueDateController = TextEditingController(
      text: bill['dueDate'] ?? '',
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Quick Edit',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Name field
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Bill Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
            ),
            const SizedBox(height: 16),

            // Amount field
            TextField(
              controller: amountController,
              decoration: const InputDecoration(
                labelText: 'Amount',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.attach_money),
                prefixText: '\$',
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),

            // Due date field
            TextField(
              controller: dueDateController,
              decoration: const InputDecoration(
                labelText: 'Due Date',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.calendar_today),
                hintText: 'DD/MM/YYYY',
              ),
            ),
            const SizedBox(height: 24),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final billIndex = _bills.indexOf(bill);
                      if (billIndex != -1) {
                        setState(() {
                          _bills[billIndex]['name'] = nameController.text;
                          _bills[billIndex]['amount'] = amountController.text;
                          _bills[billIndex]['dueDate'] = dueDateController.text;
                        });

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${nameController.text} updated successfully!',
                            ),
                            backgroundColor: Colors.green,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Save Changes'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showFrequencyBottomSheet(
    BuildContext context,
    Function(String) onSelected,
  ) {
    final List<String> frequencies = ['Daily', 'Weekly', 'Monthly', 'Yearly'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,

                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select Frequency',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: kPrimaryColor,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: frequencies
                  .map(
                    (frequency) => ListTile(
                      title: Text(
                        frequency,
                        style: const TextStyle(color: Colors.black),
                      ),
                      onTap: () {
                        onSelected(frequency);
                        Navigator.pop(context);
                      },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // Helper method to check if reminder option is valid based on selected date
  bool _isReminderOptionValid(String reminder, DateTime? selectedDate) {
    if (selectedDate == null) return true;
    if (reminder == 'No reminder' || reminder == 'Same day') return true;

    final now = DateTime.now();
    final difference = selectedDate.difference(now).inDays;

    switch (reminder) {
      case '1 day before':
        return difference >= 1;
      case '3 days before':
        return difference >= 3;
      case '1 week before':
        return difference >= 7;
      case '10 days before':
        return difference >= 10;
      default:
        return true;
    }
  }

  void _showReminderBottomSheet(
    BuildContext context,
    Function(String) onSelected,
    DateTime? selectedDate,
  ) {
    final List<String> reminders = [
      'No reminder',
      'Same day',
      '1 day before',
      '3 days before',
      '1 week before',
      '10 days before',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select Reminder',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: kPrimaryColor,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: reminders.length,
                itemBuilder: (context, index) {
                  final reminder = reminders[index];
                  final isValid = _isReminderOptionValid(
                    reminder,
                    selectedDate,
                  );

                  return ListTile(
                    title: Text(
                      reminder,
                      style: TextStyle(
                        color: isValid ? Colors.black : Colors.grey.shade400,
                      ),
                    ),
                    onTap: isValid
                        ? () {
                            onSelected(reminder);
                            Navigator.pop(context);
                          }
                        : null,
                    tileColor: isValid ? null : Colors.grey.shade100,
                    enabled: isValid,
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showCategoryBottomSheet(
    BuildContext context,
    Function(Category) onSelected,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select Category',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: kPrimaryColor,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: Category.defaultCategories.length,
                itemBuilder: (context, index) {
                  final category = Category.defaultCategories[index];
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: category.backgroundColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        category.icon,
                        color: category.color,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      category.name,
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onTap: () {
                      onSelected(category);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> showAddBillBottomSheet(
    BuildContext context, {
    Map<String, dynamic>? bill,
    int? editIndex,
  }) async {
    final bool isEditMode = bill != null && editIndex != null;
    debugPrint(
      '📝 Edit mode: $isEditMode, bill: ${bill?['name']}, editIndex: $editIndex',
    );

    // Declare variables outside StatefulBuilder to maintain state
    final formKey = GlobalKey<FormState>();
    late final TextEditingController nameController;
    late final TextEditingController amountController;
    late final TextEditingController dueDateController;
    late final TextEditingController dueTimeController;
    late final TextEditingController notesController;
    late final TextEditingController reminderTimeController;
    late DateTime? selectedDate;
    late TimeOfDay? selectedTime;
    late TimeOfDay? selectedReminderTime;
    late String selectedFrequency;
    late String selectedReminder;
    late Category selectedCategory;
    final int? currentEditIndex = editIndex;

    // Initialize variables
    nameController = TextEditingController(
      text: bill?['name']?.toString() ?? '',
    );
    amountController = TextEditingController(
      text: bill?['amount']?.toString() ?? '',
    );
    dueDateController = TextEditingController(
      text: bill?['dueDate']?.toString() ?? '',
    );
    dueTimeController = TextEditingController(
      text: bill?['dueTime']?.toString() ?? '',
    );
    notesController = TextEditingController(
      text: bill?['notes']?.toString() ?? '',
    );
    reminderTimeController = TextEditingController();
    selectedDate = null;
    selectedTime = null;
    selectedReminderTime = null;
    selectedFrequency = bill?['frequency']?.toString() ?? 'Monthly';
    selectedReminder = bill?['reminder']?.toString() ?? 'Same day';
    selectedCategory = Category.defaultCategories[0];

    // Parse the due date and time if they exist (for edit mode)
    if (isEditMode) {
      debugPrint('📝 Parsing bill data for editing...');
      final parsedDate = _parseDueDate(bill!);
      if (parsedDate != null) {
        selectedDate = parsedDate;
        selectedTime = TimeOfDay(
          hour: parsedDate.hour,
          minute: parsedDate.minute,
        );

        // Format date and time for display
        dueDateController.text =
            '${parsedDate.day.toString().padLeft(2, '0')}/${parsedDate.month.toString().padLeft(2, '0')}/${parsedDate.year}';
        dueTimeController.text = selectedTime?.format(context) ?? '';
      }

      // Parse the reminder time if it exists (SEPARATE from due time)
      if (bill!['reminderTime'] != null) {
        try {
          final reminderTimeStr = bill['reminderTime'];
          if (reminderTimeStr is String) {
            final parts = reminderTimeStr.split(':');
            if (parts.length == 2) {
              selectedReminderTime = TimeOfDay(
                hour: int.parse(parts[0]),
                minute: int.parse(parts[1]),
              );
            }
          } else if (reminderTimeStr is Map) {
            selectedReminderTime = TimeOfDay(
              hour: reminderTimeStr['hour'] ?? 9,
              minute: reminderTimeStr['minute'] ?? 0,
            );
          }
        } catch (e) {
          // If parsing fails, fall back to default
          selectedReminderTime = const TimeOfDay(hour: 9, minute: 0);
        }
      } else {
        // If no specific reminder time, get default from settings
        selectedReminderTime = const TimeOfDay(hour: 9, minute: 0);
      }

      // Set category if exists
      if (bill?['category'] != null) {
        debugPrint('📝 Setting category from bill: ${bill!['category']}');
        final category = Category.findById(bill!['category']);
        if (category != null) {
          selectedCategory = category;
          debugPrint('✅ Category set to: ${category.name}');
        } else {
          debugPrint('⚠️ Category not found: ${bill!['category']}');
        }
      }

      // Set frequency and reminder preferences from bill
      selectedFrequency = bill?['frequency'] ?? 'Monthly';
      selectedReminder = bill?['reminder'] ?? 'Same day';
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.5,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Padding(
              padding: EdgeInsets.only(
                left: 20.0,
                right: 20.0,
                top: 20.0,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20.0,
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color:
                                  (isEditMode
                                          ? Colors.orange[700]!
                                          : kPrimaryColor)
                                      .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isEditMode ? Icons.edit : Icons.add,
                              color: isEditMode
                                  ? Colors.orange[700]!
                                  : kPrimaryColor,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            isEditMode ? 'Edit Bill' : 'Add Bill',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isEditMode
                                      ? Colors.orange[700]!
                                      : kPrimaryColor,
                                  fontSize: 16,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      // Category Field
                      GestureDetector(
                        onTap: () {
                          _showCategoryBottomSheet(context, (category) {
                            setState(() {
                              selectedCategory = category;
                            });
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: kPrimaryColor.withAlpha(77),
                            ),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey[50],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: selectedCategory.backgroundColor,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    selectedCategory.icon,
                                    color: selectedCategory.color,
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Category',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        selectedCategory.name,
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_drop_down,
                                  color: kPrimaryColor,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: nameController,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          labelText: 'bill Name',
                          hintText: '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: kPrimaryColor.withValues(alpha: 0.6),
                              width: 1,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: kPrimaryColor.withValues(alpha: 0.6),
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: kPrimaryColor,
                              width: 1.5,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                          prefixIcon: Container(
                            margin: const EdgeInsets.all(8),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              Icons.description,
                              color: Colors.blue[700],
                              size: 16,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[400],
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter subscription name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: amountController,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Amount',
                          hintText: 'e.g., 15.99',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: kPrimaryColor.withValues(alpha: 0.6),
                              width: 1,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: kPrimaryColor.withValues(alpha: 0.6),
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: kPrimaryColor,
                              width: 1.5,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                          prefixIcon: Container(
                            margin: const EdgeInsets.all(8),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              Icons.attach_money,
                              color: Colors.green[700],
                              size: 16,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[400],
                          ),
                        ),
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter amount';
                          }
                          if (double.tryParse(value) == null) {
                            return 'Please enter a valid amount';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: dueDateController,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                              ),
                              readOnly: true,
                              onTap: () async {
                                final DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate:
                                      selectedDate ??
                                      DateTime.now().add(
                                        const Duration(days: 1),
                                      ),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime(2100),
                                  builder: (context, child) {
                                    return Theme(
                                      data: Theme.of(context).copyWith(
                                        colorScheme: ColorScheme.light(
                                          primary: kPrimaryColor,
                                          onPrimary: Colors.white,
                                          surface: Colors.white,
                                          onSurface: Colors.black,
                                        ),
                                      ),
                                      child: child!,
                                    );
                                  },
                                );
                                if (picked != null) {
                                  setState(() {
                                    selectedDate = DateTime(
                                      picked.year,
                                      picked.month,
                                      picked.day,
                                      selectedTime?.hour ?? 0,
                                      selectedTime?.minute ?? 0,
                                    );
                                    dueDateController.text =
                                        '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
                                  });
                                }
                              },
                              decoration: InputDecoration(
                                labelText: 'Due Date',
                                hintText: 'Select date',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: kPrimaryColor.withValues(alpha: 0.6),
                                    width: 1,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: kPrimaryColor.withValues(alpha: 0.6),
                                    width: 1,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: kPrimaryColor,
                                    width: 1.5,
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                                prefixIcon: Container(
                                  margin: const EdgeInsets.all(8),
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    Icons.calendar_today,
                                    color: Colors.purple[700],
                                    size: 16,
                                  ),
                                ),
                                suffixIcon: Icon(
                                  Icons.arrow_drop_down,
                                  color: kPrimaryColor,
                                  size: 18,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                labelStyle: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                                hintStyle: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[400],
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please select due date';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: dueTimeController,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                              ),
                              readOnly: true,
                              onTap: () async {
                                final TimeOfDay? picked = await showTimePicker(
                                  context: context,
                                  initialTime:
                                      selectedTime ??
                                      const TimeOfDay(hour: 9, minute: 0),
                                  builder: (context, child) {
                                    return Theme(
                                      data: Theme.of(context).copyWith(
                                        colorScheme: ColorScheme.light(
                                          primary: kPrimaryColor,
                                          onPrimary: Colors.white,
                                          surface: Colors.white,
                                          onSurface: Colors.black,
                                        ),
                                      ),
                                      child: child!,
                                    );
                                  },
                                );
                                if (picked != null) {
                                  setState(() {
                                    selectedTime = picked;
                                    dueTimeController.text = picked.format(
                                      context,
                                    );

                                    // Update selectedDate with the new time
                                    if (selectedDate != null) {
                                      selectedDate = DateTime(
                                        selectedDate!.year,
                                        selectedDate!.month,
                                        selectedDate!.day,
                                        picked.hour,
                                        picked.minute,
                                      );
                                    }
                                  });
                                }
                              },
                              decoration: InputDecoration(
                                labelText: 'Due Time',
                                hintText: 'Select time',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: kPrimaryColor.withValues(alpha: 0.6),
                                    width: 1,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: kPrimaryColor.withValues(alpha: 0.6),
                                    width: 1,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: kPrimaryColor,
                                    width: 1.5,
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                                prefixIcon: Container(
                                  margin: const EdgeInsets.all(8),
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    Icons.access_time,
                                    color: Colors.orange[700],
                                    size: 16,
                                  ),
                                ),
                                suffixIcon: Icon(
                                  Icons.arrow_drop_down,
                                  color: kPrimaryColor,
                                  size: 18,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                labelStyle: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                                hintStyle: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[400],
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please select due time';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: () {
                          _showFrequencyBottomSheet(context, (frequency) {
                            setState(() {
                              selectedFrequency = frequency;
                            });
                          });
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: kPrimaryColor.withAlpha(77),
                            ),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey[50],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    Icons.repeat,
                                    color: Colors.orange[700],
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Frequency',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        selectedFrequency,
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_drop_down,
                                  color: kPrimaryColor,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: () {
                          _showReminderBottomSheet(context, (reminder) {
                            setState(() {
                              selectedReminder = reminder;
                            });
                          }, selectedDate);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: kPrimaryColor.withAlpha(77),
                            ),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey[50],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    Icons.notifications,
                                    color: Colors.red[700],
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Reminder',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        selectedReminder,
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_drop_down,
                                  color: kPrimaryColor,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Reminder Time Field
                      GestureDetector(
                        onTap: selectedReminder == 'No reminder'
                            ? null
                            : () async {
                                final defaultTime =
                                    await _getDefaultNotificationTime();
                                final TimeOfDay? picked = await showTimePicker(
                                  context: context,
                                  initialTime:
                                      selectedReminderTime ?? defaultTime,
                                );
                                if (picked != null) {
                                  setState(() {
                                    selectedReminderTime = picked;
                                    reminderTimeController.text =
                                        selectedReminderTime!.format(context);

                                    // Don't update user's default notification preference
                                    // when editing individual bill reminder time
                                  });
                                }
                              },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: selectedReminder == 'No reminder'
                                  ? Colors.grey.withValues(alpha: 0.3)
                                  : kPrimaryColor.withValues(alpha: 0.6),
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            color: selectedReminder == 'No reminder'
                                ? Colors.grey[100]
                                : Colors.grey[50],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    Icons.notifications_active,
                                    color: Colors.orange[700],
                                    size: 16,
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Reminder Time',
                                        style: TextStyle(
                                          color:
                                              selectedReminder == 'No reminder'
                                              ? Colors.grey[400]
                                              : Colors.grey[600],
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        selectedReminder == 'No reminder'
                                            ? 'No reminder set'
                                            : (selectedReminderTime?.format(
                                                    context,
                                                  ) ??
                                                  'Select reminder time'),
                                        style: TextStyle(
                                          color:
                                              selectedReminder == 'No reminder'
                                              ? Colors.grey[400]
                                              : (selectedReminderTime != null
                                                    ? Colors.black
                                                    : Colors.grey[400]),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.access_time,
                                  color: selectedReminder == 'No reminder'
                                      ? Colors.grey[400]
                                      : kPrimaryColor,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: notesController,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Notes (Optional)',
                          hintText: 'Add any additional notes...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: kPrimaryColor.withValues(alpha: 0.6),
                              width: 1,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: kPrimaryColor.withValues(alpha: 0.6),
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: kPrimaryColor,
                              width: 1.5,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                          prefixIcon: Container(
                            margin: const EdgeInsets.all(8),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              Icons.note,
                              color: Colors.teal[700],
                              size: 16,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          labelStyle: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[400],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                side: BorderSide(color: Colors.grey.shade300),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(fontSize: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                if (formKey.currentState!.validate()) {
                                  // Ensure we have a time set (default to user's preferred time if not selected)
                                  if (selectedTime == null) {
                                    selectedTime =
                                        await _getDefaultNotificationTime();
                                    dueTimeController.text = selectedTime!
                                        .format(context);

                                    // Update selectedDate with default time
                                    if (selectedDate != null) {
                                      selectedDate = DateTime(
                                        selectedDate!.year,
                                        selectedDate!.month,
                                        selectedDate!.day,
                                        selectedTime!.hour,
                                        selectedTime!.minute,
                                      );
                                    }
                                  }

                                  // Create full due date string with time
                                  String fullDueDate = dueDateController.text;
                                  if (selectedTime != null) {
                                    fullDueDate +=
                                        ' ${selectedTime!.format(context)}';
                                  }

                                  // Schedule notification if reminder time is selected
                                  if (selectedReminderTime != null &&
                                      selectedReminder != 'No reminder') {
                                    // Calculate the actual reminder date based on the reminder preference
                                    DateTime reminderDate;
                                    if (selectedDate != null) {
                                      reminderDate = _calculateReminderDate(
                                        selectedDate!,
                                        selectedReminder,
                                      );
                                    } else {
                                      reminderDate = DateTime.now();
                                    }

                                    // Set the reminder time (separate from due time)
                                    final reminderDateTime = DateTime(
                                      reminderDate.year,
                                      reminderDate.month,
                                      reminderDate.day,
                                      selectedReminderTime!.hour,
                                      selectedReminderTime!.minute,
                                    );

                                    // Only schedule if the reminder time is in the future
                                    if (reminderDateTime.isAfter(
                                      DateTime.now(),
                                    )) {
                                      await NotificationService().scheduleNotification(
                                        id:
                                            DateTime.now()
                                                .millisecondsSinceEpoch ~/
                                            1000,
                                        title:
                                            'Bill Reminder: ${nameController.text}',
                                        body:
                                            'Your bill for ${nameController.text} of ${amountController.text} is due soon!',
                                        scheduledTime: reminderDateTime,
                                      );
                                    }
                                  }

                                  final subscription = {
                                    'name': nameController.text,
                                    'amount': amountController.text,
                                    'dueDate': dueDateController.text,
                                    'dueTime': dueTimeController.text,
                                    'dueDateTime': selectedDate
                                        ?.toIso8601String(),
                                    'reminderTime': selectedReminderTime != null
                                        ? '${selectedReminderTime!.hour.toString().padLeft(2, '0')}:${selectedReminderTime!.minute.toString().padLeft(2, '0')}'
                                        : null,
                                    'frequency': selectedFrequency,
                                    'reminder': selectedReminder,
                                    'category': selectedCategory.id,
                                    'categoryName': selectedCategory.name,
                                    'categoryColor': selectedCategory.color
                                        .toARGB32(),
                                    'categoryBackgroundColor': selectedCategory
                                        .backgroundColor
                                        .toARGB32(),
                                    'notes': notesController.text.isEmpty
                                        ? null
                                        : notesController.text,
                                  };
                                  if (isEditMode && currentEditIndex != null) {
                                    await _updateBill(
                                      currentEditIndex,
                                      subscription,
                                    );
                                  } else {
                                    await _addSubscription(subscription);
                                  }
                                  if (mounted) {
                                    Navigator.pop(context);
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kPrimaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                isEditMode ? 'Edit Bill' : 'Add Bill',
                                style: TextStyle(fontSize: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _addSubscription(Map<String, dynamic> subscription) async {
    // Check network status first
    await _checkConnectivity();
    debugPrint('Adding subscription. Network status: $_isOnline');

    if (_isOnline) {
      try {
        // Try to add to Firebase first
        await _subscriptionService.addSubscription(subscription);

        // If successful, refresh from local to ensure consistency
        if (mounted) {
          await _refreshBillsForCategory(); // Refresh from local storage
          _checkForOverdueBills(); // Immediate check for overdue status

          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${subscription['name']} added successfully!'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }
      } catch (e) {
        // Re-check connectivity to make sure it's actually offline
        await _checkConnectivity();

        if (!_isOnline) {
          // Only show offline message if actually offline
          if (mounted) {
            await _refreshBillsForCategory(); // Refresh from local storage
            _checkForOverdueBills(); // Immediate check for overdue status
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${subscription['name']} saved locally. Will sync when online.',
                ),
                backgroundColor: Colors.orange,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
          }
        } else {
          // If online but Firebase failed, show error message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to save to server. Please try again.'),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
          }
        }
      }
    } else {
      // Offline: Add to local list only
      if (mounted) {
        setState(() {
          _bills.add(subscription);
          _checkForOverdueBills(); // Immediate check for overdue status
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${subscription['name']} saved locally. Will sync when online.',
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }

  void showCategoryBillsBottomSheet(BuildContext context, Category category) {
    // First ensure we have the latest data
    _refreshBillsForCategory();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CategoryBillsBottomSheet(
        category: category,
        subscriptionService: _subscriptionService,
        onBillAdded: () {
          // Refresh the main bills list when a new bill is added
          _loadSubscriptions();
        },
      ),
    );
  }

  // Refresh bills specifically for category display
  Future<void> _refreshBillsForCategory() async {
    try {
      // Always get latest local data first
      final localSubscriptions = await _subscriptionService
          .getLocalSubscriptions();

      if (mounted) {
        setState(() {
          _bills = localSubscriptions;
        });
        debugPrint(
          '🔄 Refreshed bills for category: ${_bills.length} bills loaded',
        );
      }
    } catch (e) {
      debugPrint('⚠️ Failed to refresh bills for category: $e');
    }
  }

  Future<void> _loadSubscriptions() async {
    if (!mounted) return;

    debugPrint('📱 Loading subscriptions (SMART LOCAL-FIRST)...');
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      // ALWAYS load from local first (fast, no Firebase needed)
      debugPrint('🗂️ Loading from local storage...');
      final localSubscriptions = await _subscriptionService
          .getLocalSubscriptions();

      if (mounted) {
        setState(() {
          _bills = localSubscriptions;
          _isLoading = false;
        });
        debugPrint(
          '✅ UI updated with ${_bills.length} bills from local storage',
        );
      }

      // THEN check if we should sync with Firebase (smart sync)
      final shouldSync = await _subscriptionService.shouldSyncWithFirebase();
      if (shouldSync) {
        debugPrint('🌐 Smart sync triggered, attempting background sync...');
        try {
          final syncedSubscriptions = await _subscriptionService
              .getSubscriptions();

          // Smart merge: preserve local paid status changes while syncing other data
          if (mounted) {
            bool needsUpdate = false;
            final List<Map<String, dynamic>> mergedBills = [];

            for (var syncedBill in syncedSubscriptions) {
              final localBill = _bills.firstWhere(
                (b) =>
                    b['id'] == syncedBill['id'] ||
                    b['firebaseId'] == syncedBill['firebaseId'] ||
                    b['localId'] == syncedBill['localId'],
                orElse: () => syncedBill,
              );

              // Check if local bill has important changes to preserve
              bool localHasPaidStatus = localBill['status'] == 'paid';
              bool syncedHasPaidStatus = syncedBill['status'] == 'paid';

              // Create merged bill
              Map<String, dynamic> mergedBill = Map.from(syncedBill);

              if (localHasPaidStatus) {
                // Always preserve local paid status and paid date
                mergedBill['status'] = 'paid';
                mergedBill['paidDate'] = localBill['paidDate'];
                needsUpdate = true;
                debugPrint('🔄 Preserving paid status for: ${syncedBill['name']}');
              }

              // Check for other local changes that should be preserved
              // (like recent edits that haven't synced yet)
              if (localBill.containsKey('lastModified') && syncedBill.containsKey('lastModified')) {
                final localModified = DateTime.tryParse(localBill['lastModified'].toString());
                final syncedModified = DateTime.tryParse(syncedBill['lastModified'].toString());

                if (localModified != null && syncedModified != null && localModified.isAfter(syncedModified)) {
                  // Local version is newer, preserve more fields
                  for (var key in localBill.keys) {
                    if (!['id', 'firebaseId', 'localId'].contains(key)) {
                      mergedBill[key] = localBill[key];
                    }
                  }
                  needsUpdate = true;
                  debugPrint('🔄 Preserving newer local version for: ${syncedBill['name']}');
                }
              }

              mergedBills.add(mergedBill);
            }

            // Only update if there are actual changes
            if (needsUpdate || mergedBills.length != _bills.length) {
              setState(() {
                _bills = mergedBills;
              });
              debugPrint(
                '🔄 UI updated with merged data: ${_bills.length} bills (preserved local paid status)',
              );
            } else {
              debugPrint('✅ No changes needed from sync');
            }
          }
        } catch (e) {
          debugPrint(
            '⚠️ Background sync failed, but local data is available: $e',
          );
        }
      } else {
        debugPrint('⏭️ Skipping sync - not needed or offline');
      }
    } catch (e) {
      debugPrint('❌ Failed to load from local storage: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<void> addSubscription(Map<dynamic, dynamic> subscription) async {
    try {
      // Convert Map<dynamic, dynamic> to Map<String, dynamic> for the service
      final Map<String, dynamic> convertedSubscription = subscription.map(
        (key, value) => MapEntry(key.toString(), value),
      );

      await _subscriptionService.addSubscription(convertedSubscription);
      // Note: Removed _loadSubscriptions() call to prevent overriding paid status changes
      // The add operation should automatically update the local state

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Subscription added successfully!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add subscription: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }

  Future<void> _deleteSubscription(int index) async {
    final subscription = _bills[index];

    // Check network status first
    await _checkConnectivity();

    if (_isOnline) {
      try {
        // Try to delete from Firebase
        if (subscription['firebaseId'] != null) {
          await _subscriptionService.deleteSubscription(
            subscription['firebaseId'],
          );
        } else if (subscription['localId'] != null) {
          await _subscriptionService.deleteSubscription(
            subscription['localId'],
          );
        }

        // Remove from local list immediately instead of full reload
        if (mounted) {
          setState(() {
            _bills.removeAt(index);
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${subscription['name']} deleted successfully!'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }
      } catch (e) {
        // If Firebase fails, just remove from local list
        if (mounted) {
          setState(() {
            _bills.removeAt(index);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${subscription['name']} deleted locally.'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }
      }
    } else {
      // Offline: Just remove from local list
      if (mounted) {
        setState(() {
          _bills.removeAt(index);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${subscription['name']} deleted locally.'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }

  /// Get the user's default notification time preference
  Future<TimeOfDay> _getDefaultNotificationTime() async {
    try {
      final notificationService = NotificationService();
      return await notificationService.getDefaultNotificationTime();
    } catch (e) {
      // Fallback to 9:00 AM if there's an error
      return const TimeOfDay(hour: 9, minute: 0);
    }
  }
}
