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

class HomeScreenState extends State<HomeScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  // --- state fields (must be inside the State class) ---
  List<Map<String, dynamic>> _bills = [];
  final SubscriptionService _subscriptionService = SubscriptionService();
  bool _isLoading = false;
  bool _hasError = false;
  bool _isOnline = false;
  bool _isInitialized = false; // Track if initialization is complete
  DateTime? _lastDataLoadTime; // Track when data was last loaded
  bool _isBackgroundRefresh = false; // Track if we're doing background refresh
  bool _isFirstBuild = true; // Track if this is the first build

  // Cached calculations for performance
  int? _cachedUpcoming7DaysCount;
  double? _cachedUpcoming7DaysTotal;
  double? _cachedThisMonthTotal;
  DateTime? _lastCalculationTime;
  StreamSubscription<bool>? _connectivitySubscription;
  final ValueNotifier<bool> _connectivityNotifier = ValueNotifier<bool>(false);
  Timer? _updateTimer;
  String selectedCategory = 'all'; // 'all' or specific category id
  String selectedStatus = 'upcoming'; // 'upcoming', 'overdue', 'paid'
  final ScrollController _categoryScrollController = ScrollController();
  // base sizes for "This Month"
  double baseBottomAmountFontSize = 14;
  double baseBottomTextFontSize = 13;

  // Loading states
  bool _isAddingBill = false;
  String? _markingPaidBillId;

  @override
  void initState() {
    super.initState();

    // If we have data, never show loading or reinitialize
    if (_bills.isNotEmpty && _isInitialized) {
      _isLoading = false;
      return;
    }

    // Only initialize on first run
    if (!_isInitialized) {
      _isLoading = _bills.isEmpty; // Only show loading if no data
      _initializeApp();
    }
  }

  Future<void> _initializeApp() async {
    if (_isInitialized) {
      debugPrint('🔄 App already initialized, skipping...');
      return;
    }

    debugPrint('🚀 Initializing app...');
    await _initServices();
    await _checkConnectivity();
    await _loadDataWithSyncPriority(); // Load with Firebase priority for cross-device sync
    _setupConnectivityListener();
    _startPeriodicUpdates();

    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
    debugPrint('✅ App initialization completed');
  }

  Future<void> _initServices() async {
    await _subscriptionService.init();

    // Clean up any mixed user data from old storage system
    await _subscriptionService.localStorageService?.cleanupMixedUserData();

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

  @override
  void activate() {
    // Called when the widget becomes active again (e.g., when navigating back)
    debugPrint('🔄 Home screen activated');

    // Always ensure loading is false when activating and we have data
    if (_bills.isNotEmpty && mounted) {
      setState(() {
        _isLoading = false;
      });
    }

    // NEVER trigger any loading when activating - just silent background sync if needed
    if (_isInitialized && _bills.isNotEmpty) {
      // Only do silent background sync, never show any loading
      _isBackgroundRefresh = true;
      _silentBackgroundSync();
      // Reset flag after a short delay
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _isBackgroundRefresh = false;
        }
      });
    }

    super.activate();
  }

  // Update cached calculations for better performance
  void _updateCachedCalculations() {
    if (_bills.isEmpty) {
      _cachedUpcoming7DaysCount = 0;
      _cachedUpcoming7DaysTotal = 0.0;
      _cachedThisMonthTotal = 0.0;
      _lastCalculationTime = DateTime.now();
      return;
    }

    _cachedUpcoming7DaysCount = _calculateUpcoming7DaysCount();
    _cachedUpcoming7DaysTotal = _calculateUpcoming7DaysTotal();
    _cachedThisMonthTotal = _calculateThisMonthTotal();
    _lastCalculationTime = DateTime.now();
  }

  // Silent background sync - never shows loading, never affects UI
  Future<void> _silentBackgroundSync() async {
    if (!mounted) return;

    try {
      debugPrint('🔄 Silent background sync started...');

      // Only sync if we have a network connection
      final isOnline = await _subscriptionService.isOnline();
      if (!isOnline) {
        debugPrint('🔄 Offline, skipping background sync');
        return;
      }

      // Perform periodic sync in background
      await _subscriptionService.performPeriodicSync();

      // If new data was synced, update our bills list silently
      final freshData = await _subscriptionService.getSubscriptions();
      if (freshData.length != _bills.length) {
        debugPrint('🔄 Background sync found ${freshData.length} bills (was ${_bills.length})');
        if (mounted) {
          setState(() {
            _bills = freshData;
            _updateCachedCalculations();
          });
        }
      }

      debugPrint('✅ Silent background sync completed');
    } catch (e) {
      debugPrint('⚠️ Background sync failed: $e');
      // Silent failures are okay - don't affect user experience
    }
  }

  // Public method to force refresh data (can be called from parent widget)
  void forceRefresh({bool showLoading = true}) {
    debugPrint('🔄 Force refreshing home screen data');
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
      });
    }
    _lastDataLoadTime = null; // Reset the timestamp to force refresh
    _refreshDataFromFirebase();
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
          debugPrint(
            'Connectivity stream update: $isOnline (was offline: $wasOffline)',
          );
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

        // Every 5 minutes, also refresh data from Firebase for cross-device sync
        if (timer.tick % 5 == 0) {
          _refreshDataFromFirebase();
        }
      }
    });
  }

  // Initialize status for a single bill (upcoming, overdue, paid)
  void _initializeSingleBillStatus(Map<String, dynamic> bill) {
    try {
      final dueDate = _parseDueDate(bill);
      final now = DateTime.now();

      if (bill['status'] == 'paid') {
        // Keep paid status
        bill['status'] = 'paid';
      } else if (dueDate != null && dueDate.isBefore(now)) {
        // Mark as overdue if due date has passed
        bill['status'] = 'overdue';
      } else if (dueDate != null && dueDate.isAfter(now)) {
        // Mark as upcoming if due date is in the future
        bill['status'] = 'upcoming';
      } else {
        // No due date or due date is today, mark as upcoming by default
        bill['status'] = 'upcoming';
      }
    } catch (e) {
      debugPrint('Error initializing single bill status: $e');
      // Default to upcoming if there's an error
      bill['status'] = 'upcoming';
    }
  }

  // Initialize status for all bills (upcoming, overdue, paid)
  void _initializeBillStatuses() {
    bool needsUpdate = false;
    final now = DateTime.now();

    for (var bill in _bills) {
      try {
        final dueDate = _parseDueDate(bill);
        String newStatus = bill['status'] ?? '';

        if (bill['status'] == 'paid') {
          // Keep paid status
          newStatus = 'paid';
        } else if (dueDate != null && dueDate.isBefore(now)) {
          // Mark as overdue if due date has passed
          newStatus = 'overdue';
        } else if (dueDate != null && dueDate.isAfter(now)) {
          // Mark as upcoming if due date is in the future
          newStatus = 'upcoming';
        } else if (dueDate == null) {
          // No due date, mark as upcoming by default
          newStatus = 'upcoming';
        }

        if (bill['status'] != newStatus) {
          bill['status'] = newStatus;
          needsUpdate = true;
        }
      } catch (e) {
        debugPrint('Error initializing bill status: $e');
        // Default to upcoming if there's an error
        if (bill['status'] != 'paid') {
          bill['status'] = 'upcoming';
          needsUpdate = true;
        }
      }
    }

    if (needsUpdate && mounted) {
      setState(() {});
    }
  }

  void _checkForOverdueBills() async {
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

          // Save the updated status to local storage
          final localId = bill['localId'] ?? bill['id'];
          if (localId != null) {
            await _subscriptionService.localStorageService?.updateSubscription(
              localId,
              bill,
            );
            debugPrint(
              '✅ Saved overdue status to local storage for: ${bill['name']}',
            );
          }

          // Try to sync with Firebase if online
          final online = await _subscriptionService.isOnline();
          if (online) {
            final firebaseId = bill['firebaseId'];
            if (firebaseId != null) {
              try {
                await _subscriptionService.updateSubscription(firebaseId, bill);
                debugPrint(
                  '✅ Synced overdue status to Firebase for: ${bill['name']}',
                );
              } catch (e) {
                debugPrint('⚠️ Failed to sync overdue status to Firebase: $e');
              }
            }
          }

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
      final unsyncedCount = await _subscriptionService
          .getUnsyncedSubscriptionsCount();
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

      // After syncing, refresh data from Firebase to get changes from other devices
      debugPrint(
        '🔄 Refreshing data from Firebase to get changes from other devices...',
      );
      await _refreshDataFromFirebase();
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

  // Refresh data from local storage (local-first approach)
  Future<void> _refreshDataFromFirebase() async {
    try {
      debugPrint('🔄 Refreshing data from local storage...');

      // Get data from local storage only
      final freshData = await _subscriptionService.getSubscriptions();
      debugPrint('✅ Refreshed ${freshData.length} bills from local storage');

      if (mounted) {
        setState(() {
          _bills = freshData;
          _lastDataLoadTime = DateTime.now(); // Update load time
        });
        debugPrint('✅ UI updated with ${_bills.length} bills');

        // Update cached calculations for instant display
        _updateCachedCalculations();
      }

      // Trigger sync in background if needed
      unawaited(_subscriptionService.performPeriodicSync());

    } catch (e) {
      debugPrint('❌ Failed to refresh data: $e');
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

    final bill = _bills[index];
    final billId = _getBillId(bill);

    if (_markingPaidBillId == billId) return;

    setState(() {
      _markingPaidBillId = billId;
    });

    try {
      final bill = _bills[index];
      final billName = bill['name']?.toString() ?? 'Bill';
      final now = DateTime.now();

      // Update UI immediately for faster feedback
      final updatedBill = Map<String, dynamic>.from(bill);
      updatedBill['status'] = 'paid';
      updatedBill['paidDate'] = now.toIso8601String();
      updatedBill['lastModified'] = now.toIso8601String();

      if (mounted) {
        setState(() {
          _bills[index] = updatedBill;
        });
      }

      // Save to local storage in parallel
      final localId = bill['localId'] ?? bill['id'];
      if (localId != null) {
        _subscriptionService.localStorageService
            ?.updateSubscription(localId, updatedBill)
            .then((_) {
              debugPrint('✅ Saved paid status to local storage for $billName');
            })
            .catchError((storageError) {
              debugPrint('❌ Failed to save to local storage: $storageError');
            });
      }

      // Check connectivity and sync with Firebase if online
      _subscriptionService.isOnline().then((online) {
        if (online && bill['firebaseId'] != null) {
          _subscriptionService
              .updateSubscription(bill['firebaseId'], updatedBill)
              .then((_) {
                debugPrint('✅ Synced paid status to Firebase for $billName');
              })
              .catchError((firebaseError) {
                debugPrint(
                  '⚠️ Firebase sync failed for $billName: $firebaseError',
                );
              });
        }
      });

      // Show success message immediately
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$billName marked as paid successfully!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('❌ Critical error marking bill as paid: $e');

      // Try to update UI even if storage fails
      try {
        final bill = _bills[index];
        final errorBillName = bill['name']?.toString() ?? 'Bill';
        final updatedBill = Map<String, dynamic>.from(bill);
        updatedBill['status'] = 'paid';
        updatedBill['paidDate'] = DateTime.now().toIso8601String();

        if (mounted) {
          setState(() {
            _bills[index] = updatedBill;
          });
          debugPrint('✅ UI updated despite error for $errorBillName');
        }
      } catch (uiError) {
        debugPrint('❌ Even UI update failed: $uiError');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error marking bill as paid: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _markingPaidBillId = null;
        });
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
      // Note: UI is already updated by the calling method for immediate feedback

      // Save to local storage in parallel (optimized like paid functionality)
      final localId = originalBill['localId'] ?? originalBill['id'];
      if (localId != null) {
        final billToSave = Map<String, dynamic>.from(_bills[index]);
        // Ensure status is properly set before saving
        if (billToSave['status'] == null ||
            billToSave['status'].toString().isEmpty) {
          _initializeSingleBillStatus(billToSave);
        }

        // Save to local storage in parallel
        unawaited(_subscriptionService.localStorageService?.updateSubscription(
          localId,
          billToSave,
        ).then((_) {
          debugPrint('✅ Updated bill in local storage');
        }).catchError((error) {
          debugPrint('❌ Failed to update local storage: $error');
        }));
      }

      // Update reminders in parallel
      unawaited(_updateBillReminders(_bills[index]).then((_) {
        debugPrint('✅ Updated bill reminders');
      }).catchError((error) {
        debugPrint('❌ Failed to update reminders: $error');
      }));

      // Check connectivity in parallel
      unawaited(_checkConnectivity());

      if (_isOnline && billId != null) {
        // Update in Firebase with proper status
        final firebaseBill = Map<String, dynamic>.from(updatedBill);
        // Ensure status is properly set before saving to Firebase
        if (firebaseBill['status'] == null ||
            firebaseBill['status'].toString().isEmpty) {
          _initializeSingleBillStatus(firebaseBill);
        }
        await _subscriptionService.updateSubscription(billId, firebaseBill);

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
              content: Text(
                '${updatedBill['name']} saved locally. Will sync when online.',
              ),
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
          _updateCachedCalculations(); // Update cached calculations
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
    } finally {
      // Note: This is for the _updateBill method, not _markBillAsPaid
      // We don't need to reset _markingPaidBillId here as it's for editing, not marking as paid
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

  // Helper method to get bill ID consistently
  String? _getBillId(Map<String, dynamic> bill) {
    return bill['id']?.toString() ??
        bill['localId']?.toString() ??
        bill['firebaseId']?.toString();
  }

  // Helper method for smart due date display
  String _getSmartDueDateText(DateTime? dueDate) {
    if (dueDate == null) return 'No due date';

    final now = DateTime.now();
    final difference = dueDate.difference(now);
    final days = difference.inDays;

    if (days < 0) {
      return 'Overdue';
    } else if (days == 0) {
      return 'Today';
    } else if (days == 1) {
      return 'Tomorrow';
    } else if (days <= 7) {
      return 'In $days days';
    } else if (days <= 14) {
      return 'In 1 week';
    } else if (days <= 21) {
      return 'In 2 weeks';
    } else if (days <= 30) {
      return 'In 3 weeks';
    } else {
      return '${dueDate.day}/${dueDate.month}/${dueDate.year}';
    }
  }

  // Helper method to get vibrant colors for category icons
  Color _getCategoryColor(String? categoryId) {
    // Map of category IDs to vibrant colors
    const categoryColors = {
      'subscription': Colors.red,
      'utilities': Colors.blue,
      'entertainment': Colors.purple,
      'food': Colors.orange,
      'transport': Colors.green,
      'health': Colors.pink,
      'education': Colors.indigo,
      'shopping': Colors.teal,
      'insurance': Colors.amber,
      'other': Colors.brown,
    };

    // If category ID exists in our map, return the corresponding color
    if (categoryId != null && categoryColors.containsKey(categoryId)) {
      return categoryColors[categoryId]!;
    }

    // If no specific color, generate one based on hash of category ID
    if (categoryId != null) {
      final hash = categoryId.hashCode;
      final colors = [
        Colors.red, Colors.blue, Colors.green, Colors.orange, Colors.purple,
        Colors.pink, Colors.indigo, Colors.teal, Colors.amber, Colors.cyan,
        Colors.deepOrange, Colors.lime, Colors.brown, Colors.grey
      ];
      return colors[hash.abs() % colors.length];
    }

    // Default color for uncategorized
    return Colors.grey;
  }

  // Helper method to format frequency text
  String _getFrequencyText(String? frequency) {
    if (frequency == null || frequency.isEmpty) {
      return 'One-time';
    }

    switch (frequency.toLowerCase()) {
      case 'weekly':
        return 'Weekly';
      case 'bi-weekly':
      case 'biweekly':
        return 'Bi-weekly';
      case 'monthly':
        return 'Monthly';
      case 'quarterly':
        return 'Quarterly';
      case 'semi-annual':
      case 'semiannual':
        return 'Semi-annual';
      case 'annual':
      case 'yearly':
        return 'Annual';
      default:
        return frequency;
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

  // Calculate upcoming bills count (next 7 days) - raw calculation
  int _calculateUpcoming7DaysCount() {
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

  // Calculate total amount for upcoming bills (next 7 days) - raw calculation
  double _calculateUpcoming7DaysTotal() {
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

  // Calculate this month total - raw calculation
  double _calculateThisMonthTotal() {
    double total = 0.0;
    final now = DateTime.now();
    final currentMonth = now.month;
    final currentYear = now.year;

    for (var bill in _bills) {
      try {
        final dueDate = _parseDueDate(bill);
        if (dueDate != null &&
            dueDate.month == currentMonth &&
            dueDate.year == currentYear &&
            bill['status'] != 'paid') {
          final amount = double.tryParse(bill['amount']?.toString() ?? '0') ?? 0.0;
          total += amount;
        }
      } catch (e) {
        debugPrint('Error calculating this month total: $e');
      }
    }
    return total;
  }

  // Cached getter methods for instant access
  int _getUpcoming7DaysCount() {
    if (_cachedUpcoming7DaysCount == null || _shouldRecalculate()) {
      _updateCachedCalculations();
    }
    return _cachedUpcoming7DaysCount ?? 0;
  }

  double _getUpcoming7DaysTotal() {
    if (_cachedUpcoming7DaysTotal == null || _shouldRecalculate()) {
      _updateCachedCalculations();
    }
    return _cachedUpcoming7DaysTotal ?? 0.0;
  }

  double _getThisMonthTotal() {
    if (_cachedThisMonthTotal == null || _shouldRecalculate()) {
      _updateCachedCalculations();
    }
    return _cachedThisMonthTotal ?? 0.0;
  }

  bool _shouldRecalculate() {
    if (_lastCalculationTime == null) return true;

    // Only recalculate if bills have changed or it's been more than 1 minute
    final now = DateTime.now();
    return now.difference(_lastCalculationTime!) > const Duration(minutes: 1);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Reset first build flag after first build
    if (_isFirstBuild) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _isFirstBuild = false;
          });
        }
      });
    }

    // shared heights you used earlier
    final int upcomingCount = _getUpcoming7DaysCount();
    final String upcomingText = upcomingCount == 1
        ? '1 bill'
        : '$upcomingCount bills';

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
                              const SizedBox(width: 12),
                              // Refresh button for manual sync
                              GestureDetector(
                                onTap: () async {
                                  if (_isOnline) {
                                    debugPrint(
                                      '🔄 Manual refresh triggered...',
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Refreshing data...'),
                                        backgroundColor: Colors.blue,
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                    await _refreshDataFromFirebase();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Data refreshed!'),
                                        backgroundColor: Colors.green,
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Cannot refresh while offline',
                                        ),
                                        backgroundColor: Colors.orange,
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                },
                                child: Column(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: Colors.blue.withValues(
                                        alpha: 0.15,
                                      ),
                                      child: Icon(
                                        Icons.refresh,
                                        color: Colors.blue,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                ),
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
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 6),
                  children: [
                    // Category Tabs Section
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Categories',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 40,
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
                                child: Row(children: _buildCategoryTabsList()),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Status Tabs Bar
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(children: _buildStatusTabsList()),
                    ),

                    const SizedBox(height: 8),

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
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                gradient: selectedStatus == status['id']
                    ? LinearGradient(
                        colors: [
                          HSLColor.fromAHSL(1.0, 250, 0.84, 0.60).toColor(),
                          HSLColor.fromAHSL(1.0, 280, 0.75, 0.65).toColor(),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: selectedStatus == status['id'] ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    status['icon'] as IconData,
                    color: selectedStatus == status['id']
                        ? Colors.white
                        : Colors.grey[600],
                    size: 16,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    status['title'] as String,
                    style: TextStyle(
                      color: selectedStatus == status['id']
                          ? Colors.white
                          : Colors.grey[600],
                      fontWeight: selectedStatus == status['id']
                          ? FontWeight.w600
                          : FontWeight.w500,
                      fontSize: 11,
                      fontFamily: GoogleFonts.poppins().fontFamily,
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    HSLColor.fromAHSL(1.0, 250, 0.84, 0.60).toColor(),
                    HSLColor.fromAHSL(1.0, 280, 0.75, 0.65).toColor(),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? null
              : Border.all(color: Colors.grey[300]!, width: 1),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: HSLColor.fromAHSL(1.0, 250, 0.84, 0.60).toColor().withValues(alpha: 0.25),
                    blurRadius: 8,
                    spreadRadius: 1,
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
            fontSize: 12,
            fontFamily: GoogleFonts.poppins().fontFamily,
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
    // Show loading indicator ONLY on first app start with no data, NEVER when navigating back
    if (_isLoading && !_isBackgroundRefresh && _bills.isEmpty && !_isInitialized) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
            ),
            SizedBox(height: 16),
            Text(
              'Loading your bills...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Show error message if there's an error
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 48),
            SizedBox(height: 16),
            Text(
              'Failed to load bills',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() {
                  _hasError = false;
                  _isLoading = true;
                });
                _loadFromLocalStorageOnly();
              },
              child: Text('Retry'),
            ),
          ],
        ),
      );
    }

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
    // Cache frequently accessed values for better performance
    final dueDate = _parseDueDate(bill);
    final now = DateTime.now();
    final isOverdue =
        dueDate != null && dueDate.isBefore(now) && bill['status'] != 'paid';
    final isPaid = bill['status'] == 'paid';
    final category = bill['category'] != null
        ? Category.findById(bill['category'].toString())
        : null;
    final billId = _getBillId(bill);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.15),
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isOverdue
                ? Colors.red.withValues(alpha: 0.3)
                : Colors.transparent,
            width: isOverdue ? 1.5 : 0,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showBillManagementBottomSheet(context, bill, index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Main content row
                Row(
                  children: [
                    // Category icon
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _getCategoryColor(category?.id),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        category?.icon ?? Icons.receipt,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Bill details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Bill name
                          Text(
                            bill['name']?.toString() ?? 'Unnamed Bill',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                              fontFamily: GoogleFonts.poppins().fontFamily,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),

                          // Category name
                          Text(
                            category?.name ?? 'Uncategorized',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[600],
                              fontFamily: GoogleFonts.poppins().fontFamily,
                            ),
                          ),
                          const SizedBox(height: 2),

                          // Frequency
                          Text(
                            _getFrequencyText(bill['frequency']?.toString()),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              color: Colors.grey[500],
                              fontFamily: GoogleFonts.poppins().fontFamily,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Amount and status
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '\$${bill['amount']?.toString() ?? '0.00'}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: isOverdue ? Colors.red : Colors.black87,
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Status text below amount
                        Text(
                          isPaid ? 'Paid' :
                                 isOverdue ? 'Overdue' :
                                 _getSmartDueDateText(dueDate),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isPaid ? Colors.green :
                                   isOverdue ? Colors.red :
                                   Colors.blue[700],
                            fontFamily: GoogleFonts.poppins().fontFamily,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Manage text button
                        GestureDetector(
                          onTap: () => _showBillManagementBottomSheet(context, bill, index),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Manage',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue[700],
                                fontFamily: GoogleFonts.poppins().fontFamily,
                              ),
                            ),
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
      ),
    );
  }

  // Modern bottom sheet for bill management actions
  void _showBillManagementBottomSheet(BuildContext context, Map<String, dynamic> bill, int index) {
    final isPaid = bill['status'] == 'paid';
    final isOverdue = _parseDueDate(bill)?.isBefore(DateTime.now()) == true && !isPaid;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            // Bill info header
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        isOverdue ? Colors.red : Colors.blue,
                        isOverdue ? Colors.red.withValues(alpha: 0.7) : Colors.blue.withValues(alpha: 0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.receipt,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bill['name']?.toString() ?? 'Unknown Bill',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      Text(
                        '\$${bill['amount']?.toString() ?? '0.0'}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isOverdue ? Colors.red : const Color(0xFF1F2937),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Action buttons
            if (!isPaid) ...[
              // Mark as Paid button
              Container(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    bool? confirm = await _showMarkAsPaidConfirmDialog(
                      context,
                      bill['name']?.toString() ?? 'this bill',
                    );
                    if (confirm == true) {
                      await _markBillAsPaid(index);
                    }
                  },
                  icon: const Icon(Icons.check_circle, size: 20),
                  label: const Text('Mark as Paid'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Edit button
            Container(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await _editBill(index);
                },
                icon: const Icon(Icons.edit, size: 20),
                label: const Text('Edit Bill'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Delete button
            Container(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  bool? confirm = await _showDeleteConfirmDialog(context);
                  if (confirm == true) {
                    _deleteBill(index);
                  }
                },
                icon: const Icon(Icons.delete, size: 20),
                label: const Text('Delete Bill'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Cancel button
            Container(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey[300]!),
                  ),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
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
                    _updateCachedCalculations(); // Update cached calculations
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
                    _updateCachedCalculations(); // Update cached calculations
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

    // Reset loading state before showing bottom sheet
    if (mounted) {
      setState(() {
        _isAddingBill = false;
      });
    }

    final result = await showModalBottomSheet(
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
                child: WillPopScope(
                  onWillPop: () async {
                    // Reset loading state when bottom sheet is dismissed
                    if (mounted) {
                      this.setState(() {
                        _isAddingBill = false;
                      });
                    }
                    return true;
                  },
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
                                if (_isAddingBill) return;

                                // Set loading state immediately
                                setState(() {
                                  _isAddingBill = true;
                                });

                                // Also update the main screen state
                                if (mounted) {
                                  this.setState(() {
                                    _isAddingBill = true;
                                  });
                                }

                                try {
                                  if (formKey.currentState!.validate()) {
                                    // Quick validation first
                                    if (nameController.text.trim().isEmpty) {
                                      throw Exception('Bill name is required');
                                    }
                                    if (amountController.text.trim().isEmpty) {
                                      throw Exception('Amount is required');
                                    }
                                    if (dueDateController.text.trim().isEmpty) {
                                      throw Exception('Due date is required');
                                    }

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

                                    // Create subscription data object
                                    final subscription = {
                                      'name': nameController.text.trim(),
                                      'amount': amountController.text.trim(),
                                      'dueDate': dueDateController.text.trim(),
                                      'dueTime': dueTimeController.text.trim(),
                                      'dueDateTime': selectedDate
                                          ?.toIso8601String(),
                                      'reminderTime':
                                          selectedReminderTime != null
                                          ? '${selectedReminderTime!.hour.toString().padLeft(2, '0')}:${selectedReminderTime!.minute.toString().padLeft(2, '0')}'
                                          : null,
                                      'frequency': selectedFrequency,
                                      'reminder': selectedReminder,
                                      'category': selectedCategory.id,
                                      'categoryName': selectedCategory.name,
                                      'categoryColor': selectedCategory.color
                                          .toARGB32(),
                                      'categoryBackgroundColor':
                                          selectedCategory.backgroundColor
                                              .toARGB32(),
                                      'notes': notesController.text.trim().isEmpty
                                          ? null
                                          : notesController.text.trim(),
                                      'status': 'upcoming', // Set initial status
                                      'createdAt': DateTime.now().toIso8601String(),
                                      'lastModified': DateTime.now().toIso8601String(),
                                    };

                                    // Close bottom sheet first for better UX
                                    if (mounted) {
                                      Navigator.pop(context);
                                    }

                                    // Then process the save operation in background
                                    unawaited(_processBillSave(isEditMode, currentEditIndex, subscription, selectedReminderTime, selectedReminder, selectedDate, nameController.text, amountController.text));
                                  }
                                } catch (e) {
                                  debugPrint('Error adding bill: $e');
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Error adding bill: ${e.toString()}',
                                        ),
                                        backgroundColor: Colors.red,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                } finally {
                                  // Reset loading state
                                  if (mounted) {
                                    setState(() {
                                      _isAddingBill = false;
                                    });
                                    this.setState(() {
                                      _isAddingBill = false;
                                    });
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
                              child: _isAddingBill
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    )
                                  : Text(
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
          ));
        },
      ),
    );

    // Handle bottom sheet dismissal - always reset loading state
    if (mounted) {
      setState(() {
        _isAddingBill = false;
      });
    }
  }

  // Process bill save operation in background for better UX
  Future<void> _processBillSave(
    bool isEditMode,
    int? currentEditIndex,
    Map<String, dynamic> subscription,
    TimeOfDay? selectedReminderTime,
    String selectedReminder,
    DateTime? selectedDate,
    String billName,
    String billAmount,
  ) async {
    try {
      debugPrint('🚀 Processing bill save in background...');

      // Schedule notification if reminder time is selected
      if (selectedReminderTime != null &&
          selectedReminder != 'No reminder') {
        // Calculate the actual reminder date based on the reminder preference
        DateTime reminderDate;
        if (selectedDate != null) {
          reminderDate = _calculateReminderDate(
            selectedDate,
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
          selectedReminderTime.hour,
          selectedReminderTime.minute,
        );

        // Only schedule if the reminder time is in the future
        if (reminderDateTime.isAfter(
          DateTime.now(),
        )) {
          await NotificationService()
              .scheduleNotification(
                id:
                    DateTime.now()
                        .millisecondsSinceEpoch ~/
                    1000,
                title:
                    'Bill Reminder: $billName',
                body:
                    'Your bill for $billName of $billAmount is due soon!',
                scheduledTime: reminderDateTime,
              );
        }
      }

      // Save to storage using optimized approach similar to paid functionality
      if (isEditMode && currentEditIndex != null) {
        // Update UI immediately for faster feedback
        if (mounted && currentEditIndex < _bills.length) {
          setState(() {
            _bills[currentEditIndex] = subscription;
          });
        }

        // Save to local storage in parallel
        unawaited(_updateBill(currentEditIndex, subscription).then((_) {
          debugPrint('✅ Updated bill in storage for $billName');
        }).catchError((error) {
          debugPrint('❌ Failed to update bill: $error');
        }));
      } else {
        // Add to UI immediately for faster feedback
        if (mounted) {
          setState(() {
            _bills.add(subscription);
            _updateCachedCalculations(); // Update cached calculations
          });
        }

        // Save to storage in parallel
        unawaited(_addSubscription(subscription).then((_) {
          debugPrint('✅ Added bill to storage for $billName');
        }).catchError((error) {
          debugPrint('❌ Failed to add bill: $error');
        }));
      }

      debugPrint('✅ Bill save completed successfully');
    } catch (e) {
      debugPrint('❌ Error in background bill save: $e');
      // Show error message if still on screen
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error saving bill: ${e.toString()}',
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } finally {
      // Ensure loading state is reset
      if (mounted) {
        setState(() {
          _isAddingBill = false;
        });
      }
    }
  }

  Future<void> _addSubscription(Map<String, dynamic> subscription) async {
    // Ensure status is properly set before saving
    _initializeSingleBillStatus(subscription);

    // Note: UI is already updated by the calling method for immediate feedback

    // Check network status and save in parallel (optimized like paid functionality)
    unawaited(_checkConnectivity().then((_) async {
      debugPrint('Adding subscription. Network status: $_isOnline');

      if (_isOnline) {
        try {
          // Try to add to Firebase first
          await _subscriptionService.addSubscription(subscription);

          // If successful, show success message
          if (mounted) {
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
        // Offline: Show offline message
        if (mounted) {
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
    }));
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

        // Initialize bill statuses after refresh
        _initializeBillStatuses();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to refresh bills for category: $e');
    }
  }

  // Load data with local-first approach
  Future<void> _loadDataWithSyncPriority() async {
    if (!mounted) return;

    // NEVER reload if we already have data and are initialized
    if (_isInitialized && _bills.isNotEmpty) {
      debugPrint('🔄 Skipping data load - already have ${_bills.length} bills loaded');
      return;
    }

    // Check if we should skip data loading (e.g., when navigating back)
    final now = DateTime.now();
    if (_lastDataLoadTime != null &&
        now.difference(_lastDataLoadTime!) < const Duration(seconds: 30)) {
      debugPrint('🔄 Skipping data load - last load was ${now.difference(_lastDataLoadTime!).inSeconds} seconds ago');
      return;
    }

    // Only show loading indicator if we have no data at all
    final shouldShowLoading = _bills.isEmpty && !_isBackgroundRefresh;
    if (shouldShowLoading && mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    debugPrint(
      '🔄 Loading data with local-first approach...',
    );

    try {
      // Always load from local storage first (fastest)
      debugPrint('📱 Loading from local storage...');
      final subscriptions = await _subscriptionService.getSubscriptions();
      debugPrint('✅ Loaded ${subscriptions.length} bills from local storage');

      // Filter out invalid/ghost bills - only show bills that have proper IDs
      final filteredSubscriptions = subscriptions.where((bill) {
        final hasValidId =
            bill['id'] != null && bill['id'].toString().isNotEmpty;
        final hasFirebaseId =
            bill['firebaseId'] != null &&
            bill['firebaseId'].toString().isNotEmpty;
        final hasLocalId =
            bill['localId'] != null && bill['localId'].toString().isNotEmpty;
        final hasName =
            bill['name'] != null && bill['name'].toString().isNotEmpty;

        // Keep if it has valid Firebase ID OR valid local ID with name
        final isValid = hasFirebaseId || (hasLocalId && hasName);

        if (!isValid) {
          debugPrint(
            '🗑️ Filtering out invalid bill: ${bill['name']} (ID: ${bill['id']}, FirebaseID: ${bill['firebaseId']}, LocalID: ${bill['localId']})',
          );
        }

        return isValid;
      }).toList();

      if (mounted) {
        setState(() {
          _bills = filteredSubscriptions;
          _isLoading = false;
          _lastDataLoadTime = DateTime.now(); // Update last load time
        });
        debugPrint(
          '✅ Final loaded ${_bills.length} valid bills (filtered from ${subscriptions.length} total)',
        );

        // Update cached calculations for instant display
        _updateCachedCalculations();

        // Initialize bill statuses
        _initializeBillStatuses();

        // Trigger background sync if needed
        unawaited(_subscriptionService.performPeriodicSync());
      }
    } catch (e) {
      debugPrint('❌ Data load failed: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  // Sync local storage with Firebase (background operation)
  Future<void> _syncLocalWithFirebase() async {
    try {
      debugPrint('🔄 Starting background sync with Firebase...');

      // Get unsynced count
      final unsyncedCount = await _subscriptionService
          .getUnsyncedSubscriptionsCount();

      if (unsyncedCount > 0) {
        debugPrint('🔄 Found $unsyncedCount unsynced items, syncing now...');
        final success = await _subscriptionService.syncLocalToFirebase();

        if (success) {
          debugPrint('✅ Background sync completed successfully');

          // Refresh data after sync to get any changes from other devices
          final updatedSubscriptions = await _subscriptionService
              .getSubscriptions();
          if (mounted) {
            setState(() {
              _bills = updatedSubscriptions;
            });
            debugPrint(
              '✅ Refreshed data after sync - now have ${_bills.length} bills',
            );
          }
        } else {
          debugPrint('⚠️ Background sync had some issues');
        }
      } else {
        debugPrint('✅ No unsynced items, local storage is up to date');
      }
    } catch (e) {
      debugPrint('❌ Background sync failed: $e');
    }
  }

  // Load ONLY from local storage - fast and minimal Firebase usage (fallback)
  Future<void> _loadFromLocalStorageOnly() async {
    if (!mounted) return;

    debugPrint('📱 Loading from local storage only...');

    try {
      final localSubscriptions = await _subscriptionService
          .getLocalSubscriptions();

      if (mounted) {
        setState(() {
          _bills = localSubscriptions;
          _isLoading = false; // Turn off loading indicator
        });
        debugPrint('✅ Loaded ${_bills.length} bills from local storage');

        // Initialize bill statuses
        _initializeBillStatuses();
      }
    } catch (e) {
      debugPrint('❌ Local storage load failed: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  // Load subscriptions with Firebase sync (only called when needed)
  Future<void> _loadSubscriptions() async {
    if (!mounted) return;

    debugPrint('📱 Loading subscriptions with Firebase sync...');

    try {
      // Load from local storage first
      final localSubscriptions = await _subscriptionService
          .getLocalSubscriptions();

      if (mounted) {
        setState(() {
          _bills = localSubscriptions;
          _isLoading = false;
        });
        debugPrint('✅ Loaded ${_bills.length} bills from local storage');

        // Initialize bill statuses
        _initializeBillStatuses();
      }

      // Only sync with Firebase if online and needed
      final isOnline = await _subscriptionService.isOnline();
      if (isOnline) {
        _startFirebaseSync();
      }
    } catch (e) {
      debugPrint('❌ Load failed: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  // Minimal Firebase sync - only when absolutely necessary
  void _startFirebaseSync() {
    Future.microtask(() async {
      debugPrint('🌐 Starting minimal Firebase sync...');

      try {
        final isOnline = await _subscriptionService.isOnline();
        if (!isOnline) {
          debugPrint('⏭️ Offline - skipping Firebase sync');
          return;
        }

        // Only sync if we haven't synced recently or if there are unsynced changes
        final shouldSync = await _subscriptionService.shouldSyncWithFirebase();
        if (!shouldSync) {
          debugPrint('⏭️ No sync needed - using local data');
          return;
        }

        // Get fresh data from Firebase (minimal usage)
        final firebaseSubscriptions = await _subscriptionService
            .getSubscriptions();

        if (mounted) {
          setState(() {
            _bills = firebaseSubscriptions;
          });
          debugPrint('🔄 UI updated with ${_bills.length} bills from Firebase');

          // Re-initialize bill statuses
          _initializeBillStatuses();

          // Update local storage (only when Firebase data changes)
          for (var subscription in firebaseSubscriptions) {
            await _subscriptionService.localStorageService?.saveSubscription(
              subscription,
            );
          }
          debugPrint('💾 Local storage synced with Firebase');
        }
      } catch (e) {
        debugPrint('❌ Firebase sync failed, keeping local data: $e');
      }
    });
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
    if (index < 0 || index >= _bills.length) return;

    final subscription = _bills[index];
    final subscriptionName = subscription['name'] ?? 'Unknown Bill';

    // Show loading indicator
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deleting bill...'),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 1),
        ),
      );
    }

    try {
      // CRITICAL: Delete from local storage FIRST for immediate response
      final localId = subscription['localId'] ?? subscription['id'];
      if (localId != null) {
        try {
          await _subscriptionService.localStorageService?.deleteSubscription(
            localId,
          );
          debugPrint(
            '✅ Deleted from local storage for $subscriptionName (ID: $localId)',
          );
        } catch (storageError) {
          debugPrint('❌ Failed to delete from local storage: $storageError');
          throw Exception('Failed to delete bill locally: $storageError');
        }
      }

      // Check network status for Firebase deletion
      await _checkConnectivity();

      if (_isOnline) {
        try {
          // Try to delete from Firebase
          final firebaseId = subscription['firebaseId'] ?? subscription['id'];
          if (firebaseId != null &&
              (firebaseId.startsWith('sub_') || firebaseId.length > 20)) {
            debugPrint(
              '🌐 Online, deleting from Firebase: $subscriptionName (ID: $firebaseId)',
            );
            await _subscriptionService.deleteSubscription(firebaseId);
            debugPrint('✅ Deleted from Firebase for $subscriptionName');
          }

          // Show success message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$subscriptionName deleted successfully!'),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
          }
        } catch (firebaseError) {
          debugPrint(
            '⚠️ Firebase delete failed for $subscriptionName: $firebaseError',
          );

          // Still show success since local deletion worked
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '$subscriptionName deleted locally. Will sync when online.',
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
      } else {
        debugPrint('📵 Offline - deleted locally only for $subscriptionName');

        // Show offline message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$subscriptionName deleted locally. Will sync when online.',
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

      // Remove from UI list after successful operations
      if (mounted) {
        setState(() {
          _bills.removeAt(index);
          _updateCachedCalculations(); // Update cached calculations
        });
      }

      // Cancel any existing notifications for this bill
      try {
        final notificationService = NotificationService();
        if (subscription['id'] != null) {
          await notificationService.cancelNotification(
            int.tryParse(subscription['id'].toString()) ?? 0,
          );
        }
      } catch (e) {
        debugPrint('Error canceling notification: $e');
      }
    } catch (e) {
      debugPrint('❌ Error deleting bill $subscriptionName: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to delete $subscriptionName: ${e.toString()}',
            ),
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

  /// Clean up duplicate subscriptions in Firestore
  Future<void> _cleanupDuplicates() async {
    if (!_isOnline) {
      _showErrorSnackBar('Cleanup requires internet connection');
      return;
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final result = await _subscriptionService.cleanupDuplicateSubscriptions();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message']),
            backgroundColor: result['success'] ? Colors.green : Colors.orange,
          ),
        );

        // Reload data to show cleaned-up results
        await _loadDataWithSyncPriority();
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Failed to cleanup duplicates: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Show error snack bar
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}
