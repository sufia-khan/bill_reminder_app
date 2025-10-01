import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:projeckt_k/screens/settings_screen.dart';
import 'package:projeckt_k/services/subscription_service.dart';
import 'package:projeckt_k/services/notification_service.dart';
import 'package:projeckt_k/services/app_lifecycle_manager.dart';
import 'package:projeckt_k/models/category_model.dart';
import 'package:projeckt_k/widgets/subtitle_changing.dart';
import 'package:projeckt_k/widgets/bill_summary_cards.dart';
import 'package:projeckt_k/widgets/bill_item_widget.dart';
import 'package:projeckt_k/widgets/category_bills_bottom_sheet.dart';
import 'package:projeckt_k/widgets/horizontal_category_selector.dart';
import 'package:projeckt_k/widgets/collapsible_bill_card.dart';
import 'package:projeckt_k/widgets/summary_information_bar.dart';
import 'package:projeckt_k/screens/add_edit_bill_screen.dart';

// NOTE: this file contains some legacy code paths and conditional branches
// that are intentionally permissive while we iterate on sync logic.
// Suppress some non-critical analyzer warnings here so runtime testing
// can proceed. We'll remove these ignores after targeted cleanup.
// ignore_for_file: dead_code, unnecessary_cast, unnecessary_null_comparison, unused_local_variable, unused_element, prefer_final_locals

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

class HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
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
  // base sizes for "This Month"
  double baseBottomAmountFontSize = 14;
  double baseBottomTextFontSize = 13;

  // Loading states
  bool _isAddingBill = false;
  String? _markingPaidBillId;
  AppLifecycleManager? _appLifecycleManager;
  @override
  void initState() {
    super.initState();

    // Initialize app lifecycle manager for sync on background/close
    _appLifecycleManager = AppLifecycleManager(_subscriptionService);
    WidgetsBinding.instance.addObserver(_appLifecycleManager!);

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

  // Centralized initialization sequence called from initState
  Future<void> _initializeApp() async {
    if (!mounted) return;
    try {
      // Initialize dependent services
      await _initServices();

      // Sync any pending local changes from previous sessions
      await _syncPendingBillsOnStartup();

      // Load local data quickly for immediate UI responsiveness
      await _loadFromLocalStorageOnly();

      // Set up connectivity and periodic background updates
      _setupConnectivityListener();
      _startPeriodicUpdates();

      // Mark initialization finished
      _isInitialized = true;
    } catch (e) {
      debugPrint('❌ Error during _initializeApp(): $e');
      _hasError = true;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isInitialized = true;
        });
      }
    }
  }

  // Sync pending bills on app startup if they exist from previous session
  Future<void> _syncPendingBillsOnStartup() async {
    try {
      final unsyncedCount = await _subscriptionService
          .getUnsyncedSubscriptionsCount();
      if (unsyncedCount > 0) {
        debugPrint(
          '🔄 Found $unsyncedCount pending bills from previous session, syncing...',
        );
        await _subscriptionService.syncLocalToFirebase();
      }
    } catch (e) {
      debugPrint('❌ Failed to sync pending bills on startup: $e');
    }
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

    // Set up notification callback for undo payment action
    notificationService.onUndoPayment = (String? billId) {
      debugPrint('↩️ Undo payment callback received for bill ID: $billId');
      if (billId != null) {
        _undoBillPayment(billId);
      }
    };

    // Check for any pending notification actions (for when app is launched from notification)
    await notificationService.checkAndProcessPendingActions();

    // Verify notification setup for debugging
    await notificationService.verifyNotificationSetup();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _connectivityNotifier.dispose();
    _updateTimer?.cancel();

    // Clean up app lifecycle manager
    if (_appLifecycleManager != null) {
      WidgetsBinding.instance.removeObserver(_appLifecycleManager!);
      _appLifecycleManager?.dispose();
    }

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

      // Perform periodic sync in background (upload local changes to Firebase)
      await _subscriptionService.performPeriodicSync();

      // Then fetch latest data from Firestore for cross-device sync
      await _fetchLatestFromFirestore();

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
    // Use Firestore fetch instead of local-only refresh
    unawaited(_fetchLatestFromFirestore());
  }

  Future<void> _checkConnectivity() async {
    debugPrint('🌐 _checkConnectivity() called...');
    final isOnline = await _subscriptionService.isOnline();
    debugPrint('🌐 Network status check result: $isOnline');
    debugPrint('🌐 Mounted status: $mounted');
    if (mounted) {
      debugPrint('🌐 Setting state _isOnline to: $isOnline');
      setState(() {
        _isOnline = isOnline;
      });
      _connectivityNotifier.value = isOnline;
    } else {
      debugPrint('🌐 Not mounted, skipping state update');
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

        // Every 5 minutes, also fetch data from Firestore for cross-device sync
        if (timer.tick % 5 == 0) {
          unawaited(_fetchLatestFromFirestore());
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
        // Skip invalid bills with no name
        if (bill['name'] == null) {
          continue;
        }

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
        final billName = bill['name'] ?? 'Unknown';
        debugPrint('Error initializing bill status for bill "$billName": $e');
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
        // Skip invalid bills with no name
        if (bill['name'] == null) {
          continue;
        }

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
            try {
              await _subscriptionService.localStorageService
                  ?.updateSubscription(localId, bill);
              debugPrint(
                '✅ Saved overdue status to local storage for: ${bill['name']}',
              );
            } catch (e) {
              debugPrint(
                '⚠️ Failed to save overdue status to local storage for ${bill['name']}: $e',
              );
            }
          }

          // Try to sync with Firebase if online
          try {
            final online = await _subscriptionService.isOnline();
            if (online) {
              final firebaseId = bill['firebaseId'];
              if (firebaseId != null) {
                try {
                  await _subscriptionService.updateSubscription(
                    firebaseId,
                    bill,
                  );
                  debugPrint(
                    '✅ Synced overdue status to Firebase for: ${bill['name']}',
                  );
                } catch (e) {
                  debugPrint(
                    '⚠️ Failed to sync overdue status to Firebase for ${bill['name']}: $e',
                  );
                }
              }
            }
          } catch (e) {
            debugPrint(
              '⚠️ Failed to check online status for ${bill['name']}: $e',
            );
          }

          // Send immediate overdue notification
          try {
            _sendOverdueBillNotification(bill, notificationService);
          } catch (e) {
            debugPrint(
              '⚠️ Failed to send overdue notification for ${bill['name']}: $e',
            );
          }
        }
      } catch (e) {
        final billName = bill['name'] ?? 'Unknown';
        debugPrint('Error checking overdue bill for "$billName": $e');
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
        final billName = bill['name']?.toString() ?? 'Bill';

        // Check if app is in foreground
        final notificationService = NotificationService();
        final isAppInForeground = await notificationService.isAppInForeground();

        debugPrint('📱 App in foreground: $isAppInForeground');

        // Mark bill as paid immediately (no confirmation dialog)
        await _markBillAsPaidImmediate(billIndex, isFromNotification: true);

        if (isAppInForeground) {
          // Show snackbar with undo option for foreground app
          _showPaymentUndoSnackbar(billName, billId);
        } else {
          // Update notification to show undo option
          final notificationId =
              bill['notificationId'] ??
              int.tryParse(billId) ??
              DateTime.now().millisecondsSinceEpoch;

          await notificationService.updatePaymentConfirmationNotification(
            id: notificationId,
            billName: billName,
            payload: billId,
          );
        }

        debugPrint('✅ Bill marked as paid from notification with undo option');
      } else {
        debugPrint('❌ Bill not found with ID: $billId');
      }
    } catch (e) {
      debugPrint('Error marking bill as paid from notification: $e');
    }
  }

  // Mark bill as paid immediately (without confirmation dialog)
  Future<void> _markBillAsPaidImmediate(
    int index, {
    bool isFromNotification = false,
  }) async {
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

      // Store original status for potential undo
      final originalStatus = bill['status'] ?? 'unpaid';
      final originalPaidDate = bill['paidDate'];

      // Update UI immediately for faster feedback
      final updatedBill = Map<String, dynamic>.from(bill);
      updatedBill['status'] = 'paid';
      updatedBill['paidDate'] = now.toIso8601String();
      updatedBill['lastModified'] = now.toIso8601String();
      updatedBill['_originalStatus'] = originalStatus; // Store for undo
      updatedBill['_originalPaidDate'] = originalPaidDate; // Store for undo

      if (mounted) {
        setState(() {
          _bills[index] = updatedBill;
        });
      }

      // Save to local storage first and wait for completion
      try {
        // Use the subscription service to update (which handles local storage properly)
        await _subscriptionService.updateSubscription(billId, updatedBill);
        debugPrint('✅ Saved paid status to local storage for $billName');
      } catch (storageError) {
        debugPrint('❌ Failed to save to local storage: $storageError');
        // Revert UI change if local storage fails
        if (mounted) {
          setState(() {
            _bills[index] = bill; // Revert to original bill
          });
        }
        throw Exception('Failed to save to local storage: $storageError');
      }

      // Check connectivity and sync with Firebase if online
      final isOnline = await _subscriptionService.isOnline();
      if (isOnline && bill['firebaseId'] != null) {
        try {
          await _subscriptionService.updateSubscription(
            bill['firebaseId'],
            updatedBill,
          );
          debugPrint('✅ Synced paid status to Firebase for $billName');
        } catch (firebaseError) {
          debugPrint('⚠️ Firebase sync failed for $billName: $firebaseError');
          // Don't throw here - local save succeeded, so we can continue
          // Firebase sync can happen later
        }
      }

      // Refresh the data to ensure consistency across the app
      _loadDataWithSyncPriority();

      // Don't show success message here - it will be handled by the caller
      debugPrint('✅ Bill $billName marked as paid immediately');
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
    } finally {
      if (mounted) {
        setState(() {
          _markingPaidBillId = null;
        });
      }
    }
  }

  // Show snackbar with undo option
  void _showPaymentUndoSnackbar(String billName, String billId) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$billName marked as paid'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 10), // Show for 10 seconds
        action: SnackBarAction(
          label: 'Undo',
          textColor: Colors.white,
          onPressed: () {
            _undoBillPayment(billId);
          },
        ),
      ),
    );
  }

  // Undo bill payment
  Future<void> _undoBillPayment(String billId) async {
    debugPrint('↩️ Undoing payment for bill ID: $billId');

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
        final billName = bill['name']?.toString() ?? 'Bill';

        // Restore original status
        final originalStatus = bill['_originalStatus'] ?? 'unpaid';
        final originalPaidDate = bill['_originalPaidDate'];

        // Update UI immediately
        final updatedBill = Map<String, dynamic>.from(bill);
        updatedBill['status'] = originalStatus;
        updatedBill['paidDate'] = originalPaidDate;
        updatedBill['lastModified'] = DateTime.now().toIso8601String();
        updatedBill.remove('_originalStatus'); // Clean up undo data
        updatedBill.remove('_originalPaidDate'); // Clean up undo data

        if (mounted) {
          setState(() {
            _bills[billIndex] = updatedBill;
          });
        }

        // Save to local storage
        final localId = bill['localId'] ?? bill['id'];
        if (localId != null) {
          _subscriptionService.localStorageService
              ?.updateSubscription(localId, updatedBill)
              .then((_) {
                debugPrint(
                  '✅ Restored original status to local storage for $billName',
                );
              })
              .catchError((storageError) {
                debugPrint(
                  '❌ Failed to restore to local storage: $storageError',
                );
              });
        }

        // Sync with Firebase if online
        _subscriptionService.isOnline().then((online) {
          if (online && bill['firebaseId'] != null) {
            _subscriptionService
                .updateSubscription(bill['firebaseId'], updatedBill)
                .then((_) {
                  debugPrint(
                    '✅ Synced restored status to Firebase for $billName',
                  );
                })
                .catchError((firebaseError) {
                  debugPrint(
                    '⚠️ Firebase sync failed for $billName: $firebaseError',
                  );
                });
          }
        });

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment for $billName has been undone'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            duration: const Duration(seconds: 3),
          ),
        );

        debugPrint('✅ Payment undone for bill $billName');
      } else {
        debugPrint('❌ Bill not found with ID: $billId');
      }
    } catch (e) {
      debugPrint('Error undoing payment: $e');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error undoing payment: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
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

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddEditBillScreen(
          bill: cleanBill,
          editIndex: index,
          onBillSaved: (updatedBill, editIndex) async {
            await _handleBillSaved(updatedBill, editIndex);
          },
        ),
      ),
    );
  }

  Future<void> _handleBillSaved(
    Map<String, dynamic> billData,
    int? editIndex,
  ) async {
    try {
      if (editIndex != null) {
        // Update existing bill
        debugPrint('💾 Updating existing bill at index $editIndex');
        await _updateBillInStorage(billData, editIndex);
      } else {
        // Add new bill
        debugPrint('➕ Adding new bill');
        await _addBillToStorage(billData);
      }
    } catch (e) {
      debugPrint('❌ Error saving bill: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving bill: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _updateBillInStorage(
    Map<String, dynamic> billData,
    int index,
  ) async {
    // Update the bill in the list
    setState(() {
      _bills[index] = billData;
      _updateCachedCalculations();
    });

    // Save to local storage
    await _subscriptionService.updateSubscription(billData['id'], billData);

    // Update reminders
    await _updateBillReminders(billData);

    debugPrint('✅ Bill updated successfully');
  }

  Future<void> _addBillToStorage(Map<String, dynamic> billData) async {
    // Add to the list
    setState(() {
      _bills.add(billData);
      _updateCachedCalculations();
    });

    // Save to local storage
    await _subscriptionService.addSubscription(billData);

    // Schedule reminders
    await _updateBillReminders(billData);

    debugPrint('✅ Bill added successfully');
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

      // Save to local storage first and wait for completion
      bool localSaveSuccess = false;

      try {
        // Use the subscription service to update (which handles local storage properly)
        await _subscriptionService.updateSubscription(billId, updatedBill);
        debugPrint('✅ Saved paid status to local storage for $billName');
        localSaveSuccess = true;
      } catch (storageError) {
        debugPrint('❌ Failed to save to local storage: $storageError');
        // Revert UI change if local storage fails
        if (mounted) {
          setState(() {
            _bills[index] = bill; // Revert to original bill
          });
        }
        throw Exception('Failed to save to local storage: $storageError');
      }

      // Check connectivity and sync with Firebase if online
      final isOnline = await _subscriptionService.isOnline();
      if (isOnline && bill['firebaseId'] != null) {
        try {
          await _subscriptionService.updateSubscription(
            bill['firebaseId'],
            updatedBill,
          );
          debugPrint('✅ Synced paid status to Firebase for $billName');
        } catch (firebaseError) {
          debugPrint('⚠️ Firebase sync failed for $billName: $firebaseError');
          // Don't throw here - local save succeeded, so we can continue
          // Firebase sync can happen later
        }
      }

      // Only show success if local storage succeeded
      if (localSaveSuccess) {
        // Refresh the data to ensure consistency across the app
        _loadDataWithSyncPriority();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$billName marked as paid successfully!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
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
        unawaited(
          _subscriptionService.localStorageService
              ?.updateSubscription(localId, billToSave)
              .then((_) {
                debugPrint('✅ Updated bill in local storage');
              })
              .catchError((error) {
                debugPrint('❌ Failed to update local storage: $error');
              }),
        );
      }

      // Update reminders in parallel
      unawaited(
        _updateBillReminders(_bills[index])
            .then((_) {
              debugPrint('✅ Updated bill reminders');
            })
            .catchError((error) {
              debugPrint('❌ Failed to update reminders: $error');
            }),
      );

      // Check connectivity in parallel
      debugPrint('🌐 Checking connectivity during initialization...');
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
          final billName = _bills[index]['name']?.toString() ?? 'Bill';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$billName updated successfully!'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        if (mounted) {
          final billName = _bills[index]['name']?.toString() ?? 'Bill';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$billName saved locally. Will sync when online.'),
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
          final billName = _bills[index]['name']?.toString() ?? 'Bill';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$billName updated locally. Will sync when online.',
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
          final billName = _bills[index]['name']?.toString() ?? 'Bill';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$billName updated successfully!'),
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
        try {
          // Handle time format like "8:30 AM" or "14:30"
          if (timeStr.contains('AM') || timeStr.contains('PM')) {
            // 12-hour format - extract numbers first
            final numbers = timeStr
                .split(RegExp(r'[^\d]'))
                .where((s) => s.isNotEmpty)
                .toList();
            if (numbers.length >= 2) {
              hour = int.parse(numbers[0]);
              minute = int.parse(numbers[1]);

              if (timeStr.contains('PM') && hour != 12) {
                hour += 12;
              }
              if (timeStr.contains('AM') && hour == 12) {
                hour = 0;
              }
            }
          } else {
            // 24-hour format
            final timeParts = timeStr.split(':');
            if (timeParts.length >= 2) {
              hour = int.parse(timeParts[0]);
              minute = timeParts.length > 1 ? int.parse(timeParts[1]) : 0;
            }
          }
        } catch (timeError) {
          debugPrint(
            '⚠️ Invalid time format "$timeStr", using default time: $timeError',
          );
          // Use default time if parsing fails
          hour = 9;
          minute = 0;
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
        Colors.red,
        Colors.blue,
        Colors.green,
        Colors.orange,
        Colors.purple,
        Colors.pink,
        Colors.indigo,
        Colors.teal,
        Colors.amber,
        Colors.cyan,
        Colors.deepOrange,
        Colors.lime,
        Colors.brown,
        Colors.grey,
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
            // day value parsed but not used directly (kept for clarity)
            final _ = int.parse(parts[0]);
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
          final amount =
              double.tryParse(bill['amount']?.toString() ?? '0') ?? 0.0;
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

    // Make status bar transparent so our gradient shows behind it
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

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

    // ------------ tuning values (adjust these to change overlap) ------------
    const double cardHeight = 140.0;
    final double cardOverlap = cardHeight / 2.2; // less overlap (was /2)
    const double headerInnerHeight = 130.0; // a little taller (was 110)
    const double headerBottomPadding = 25.0; // more padding (was 24)
    // -----------------------------------------------------------------------

    final double topPadding = MediaQuery.of(context).padding.top;
    final double headerTotalHeight =
        topPadding + headerInnerHeight + headerBottomPadding;
    final double contentPaddingTop = headerTotalHeight - cardOverlap;

    // shared helpers (unchanged)
    final int upcomingCount = _getUpcoming7DaysCount();
    final String upcomingText = upcomingCount == 1
        ? '1 bill'
        : '$upcomingCount bills';
    const double sharedTop = 36;
    const double sharedMiddle = 72;
    const double sharedBottom = 48;

    return Scaffold(
      // draw body behind the status bar so gradient can extend into that area
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Gradient header covering the very top (including status bar area)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: headerTotalHeight,
              padding: EdgeInsets.only(
                top: topPadding + 16,
                left: 16,
                right: 16,
                bottom: headerBottomPadding,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF2563EB), // blue-600
                    Color(0xFF7C3AED), // purple-600
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SubManager',
                    style: GoogleFonts.montserrat(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Never miss a due date again',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),

          // Main scrollable content pushed down so cards overlap the headerTotalHeight by cardOverlap
          Positioned.fill(
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(top: contentPaddingTop, bottom: 48),
              children: [
                // Summary Cards Row (white elevated cards)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              // ---------- This Month Card ----------
                              Expanded(
                                child: Container(
                                  height: 120,
                                  margin: const EdgeInsets.only(
                                    left: 5,
                                    right: 5,
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 8,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment
                                        .start, // no spaceBetween
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.calendar_month,
                                            color: Colors.blue,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            "This Month",
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        "\$${_calculateMonthlyTotal().toStringAsFixed(2)}",
                                        style: TextStyle(
                                          fontSize: 20,
                                          color: Colors.black,

                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Flexible(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              "${_calculateMonthlyDifference().abs().toStringAsFixed(2)}",
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.grey[800],
                                              ),
                                            ),
                                            Text(
                                              _calculateMonthlyDifference() > 0
                                                  ? "more than last month"
                                                  : "less than last month",
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // ---------- Next 7 Days Card ----------
                              Expanded(
                                child: Container(
                                  height: 120, // fixed equal height
                                  margin: const EdgeInsets.only(
                                    right: 5,
                                    left: 5,
                                  ),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 8,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment
                                        .start, // no spaceBetween
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.schedule,
                                            color: Colors.purple,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            "Next 7 Days",
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        "\$${_calculateThisMonthTotal().toStringAsFixed(2)}",
                                        style: TextStyle(
                                          fontSize: 20,
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Flexible(
                                        child: Text(
                                          "${_calculateUpcoming7DaysCount()} bills",
                                          style: TextStyle(
                                            fontSize: 20,
                                            color: Colors.grey[600],
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // spacing so next content isn't jammed under cards
                SizedBox(height: cardOverlap - 12),

                // Categories + summary bar (unchanged)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: HorizontalCategorySelector(
                    categories: Category.defaultCategories,
                    selectedCategory: selectedCategory,
                    onCategorySelected: (category) {
                      setState(() {
                        selectedCategory = category;
                      });
                    },
                    totalBills: _bills.length,
                    getCategoryBillCount: _getCategoryBillCount,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SummaryInformationBar(
                    billCount: _getFilteredBillCount(),
                    totalAmount: _getFilteredTotalAmount(),
                  ),
                ),

                const SizedBox(height: 8),

                Container(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.of(context).size.height * 0.4,
                  ),
                  child: _buildFilteredBillsContent(),
                ),

                const SizedBox(height: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods for the category-only filter design
  double _getFilteredTotalAmount() {
    double total = 0.0;

    for (var bill in _bills) {
      // Category filtering logic only
      final billCategory = bill['category']?.toString();
      bool matchesCategory =
          selectedCategory == 'all' ||
          (billCategory != null && billCategory == selectedCategory);

      if (matchesCategory) {
        final amount =
            double.tryParse(bill['amount']?.toString() ?? '0') ?? 0.0;
        total += amount;
      }
    }

    return total;
  }

  int _getFilteredBillCount() {
    int count = 0;

    for (var bill in _bills) {
      // Category filtering logic only
      final billCategory = bill['category']?.toString();
      bool matchesCategory =
          selectedCategory == 'all' ||
          (billCategory != null && billCategory == selectedCategory);

      if (matchesCategory) {
        count++;
      }
    }

    return count;
  }

  // Calculate bill count for a specific category
  int _getCategoryBillCount(String categoryId) {
    if (categoryId == 'all') {
      return _bills.length;
    }

    int count = 0;
    for (var bill in _bills) {
      final billCategory = bill['category']?.toString();
      if (billCategory != null && billCategory == categoryId) {
        count++;
      }
    }
    return count;
  }

  Widget _buildFilteredBillsContent() {
    // Show loading indicator ONLY on first app start with no data, NEVER when navigating back
    if (_isLoading &&
        !_isBackgroundRefresh &&
        _bills.isEmpty &&
        !_isInitialized) {
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

    // Filter bills based on selected category only
    List<Map<String, dynamic>> filteredBills = [];

    debugPrint(
      '🔍 Filtering bills - Category: $selectedCategory, Total bills: ${_bills.length}',
    );

    for (var bill in _bills) {
      try {
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
        }

        // Only add bill if category matches
        if (matchesCategory) {
          filteredBills.add(bill);
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
                  ? 'No bills in ${selectedCategory != 'all' ? Category.findById(selectedCategory)?.name ?? selectedCategory : 'any category'}'
                  : 'No bills in ${selectedCategory != 'all' ? Category.findById(selectedCategory)?.name ?? selectedCategory : 'any category'}',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a new bill to get started',
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
    final category = bill['category'] != null
        ? Category.findById(bill['category'].toString())
        : null;

    return CollapsibleBillCard(
      bill: bill,
      index: index,
      category: category,
      onMarkAsPaid: (billIndex) async {
        bool? confirm = await _showMarkAsPaidConfirmDialog(
          context,
          bill['name']?.toString() ?? 'this bill',
        );
        if (confirm == true) {
          await _markBillAsPaid(billIndex);
        }
      },
      onEdit: (billIndex) async {
        await _editBill(billIndex);
      },
      onDelete: (billIndex) async {
        bool? confirm = await _showDeleteConfirmDialog(context);
        if (confirm == true) {
          await _deleteSubscription(billIndex);
        }
      },
    );
  }

  // Modern bottom sheet for bill management actions
  void _showBillManagementBottomSheet(
    BuildContext context,
    Map<String, dynamic> bill,
    int index,
  ) {
    final isPaid = bill['status'] == 'paid';
    final isOverdue =
        _parseDueDate(bill)?.isBefore(DateTime.now()) == true && !isPaid;

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
                        isOverdue
                            ? Colors.red.withValues(alpha: 0.7)
                            : Colors.blue.withValues(alpha: 0.7),
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
                          color: isOverdue
                              ? Colors.red
                              : const Color(0xFF1F2937),
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
                      // Use the passed index which is already the correct original index
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
                  // Verify the index is valid before editing
                  if (index >= 0 && index < _bills.length) {
                    await _editBill(index);
                  }
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
                  // Verify the index is valid before deleting
                  if (index >= 0 && index < _bills.length) {
                    bool? confirm = await _showDeleteConfirmDialog(context);
                    if (confirm == true) {
                      _deleteBill(index);
                    }
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
                onPressed: () {
                  // Close the bottom sheet synchronously and reset the adding state.
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                  if (mounted) {
                    this.setState(() {
                      _isAddingBill = false;
                    });
                  }
                },
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
                  // Find the original index of this bill in the _bills list
                  final bill = bills[billIndex];
                  final originalIndex = _bills.indexOf(bill);
                  if (originalIndex != -1) {
                    await _markBillAsPaid(originalIndex);
                  }
                }
              },
              onDelete: (billIndex) async {
                bool? confirm = await _showDeleteConfirmDialog(context);
                if (confirm == true) {
                  // Find the original index of this bill in the _bills list
                  final bill = bills[billIndex];
                  final originalIndex = _bills.indexOf(bill);
                  if (originalIndex != -1) {
                    await _deleteSubscription(originalIndex);
                  }
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
      final editBill = bill;

      final parsedDate = _parseDueDate(editBill);
      if (parsedDate != null) {
        selectedDate = parsedDate;
        selectedTime = TimeOfDay(
          hour: parsedDate.hour,
          minute: parsedDate.minute,
        );

        // Format date and time for display
        dueDateController.text =
            '${parsedDate.day.toString().padLeft(2, '0')}/${parsedDate.month.toString().padLeft(2, '0')}/${parsedDate.year}';
        dueTimeController.text = TimeOfDay(
          hour: parsedDate.hour,
          minute: parsedDate.minute,
        ).format(context);
      }

      // Parse the reminder time if it exists (SEPARATE from due time)
      if (editBill['reminderTime'] != null) {
        try {
          final reminderTimeStr = editBill['reminderTime'];
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
      if (editBill['category'] != null) {
        debugPrint('📝 Setting category from bill: ${editBill['category']}');
        final category = Category.findById(editBill['category']);
        if (category != null) {
          selectedCategory = category;
          debugPrint('✅ Category set to: ${category.name}');
        } else {
          debugPrint('⚠️ Category not found: ${editBill['category']}');
        }
      }

      // Set frequency and reminder preferences from bill
      selectedFrequency = editBill['frequency'] ?? 'Monthly';
      selectedReminder = editBill['reminder'] ?? 'Same day';
    }

    // Reset loading state before showing bottom sheet
    if (mounted) {
      setState(() {
        _isAddingBill = false;
      });
    }

    // Create a short-lived animation controller to make the bottom sheet
    // transition appear smoother and snappier than the default.
    final AnimationController _sheetAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      reverseDuration: const Duration(milliseconds: 900),
    );

    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        transitionAnimationController: _sheetAnimController,
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
                  child: PopScope(
                    canPop: true,
                    onPopInvoked: (didPop) {
                      // Reset loading state when bottom sheet is dismissed
                      if (mounted) {
                        this.setState(() {
                          _isAddingBill = false;
                        });
                      }
                    },
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                              GestureDetector(
                                onTap: () {
                                  Navigator.of(context).pop();
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.grey,
                                    size: 20,
                                  ),
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
                                    final DateTime? picked =
                                        await showDatePicker(
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
                                        color: kPrimaryColor.withValues(
                                          alpha: 0.6,
                                        ),
                                        width: 1,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: kPrimaryColor.withValues(
                                          alpha: 0.6,
                                        ),
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
                                        color: Colors.purple.withValues(
                                          alpha: 0.1,
                                        ),
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
                                    final TimeOfDay? picked =
                                        await showTimePicker(
                                          context: context,
                                          initialTime:
                                              selectedTime ??
                                              const TimeOfDay(
                                                hour: 9,
                                                minute: 0,
                                              ),
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
                                        color: kPrimaryColor.withValues(
                                          alpha: 0.6,
                                        ),
                                        width: 1,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: kPrimaryColor.withValues(
                                          alpha: 0.6,
                                        ),
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
                                        color: Colors.orange.withValues(
                                          alpha: 0.1,
                                        ),
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
                                        color: Colors.orange.withValues(
                                          alpha: 0.1,
                                        ),
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
                                        color: Colors.red.withValues(
                                          alpha: 0.1,
                                        ),
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
                                    final TimeOfDay? picked =
                                        await showTimePicker(
                                          context: context,
                                          initialTime:
                                              selectedReminderTime ??
                                              defaultTime,
                                        );
                                    if (picked != null) {
                                      setState(() {
                                        selectedReminderTime = picked;
                                        reminderTimeController.text =
                                            selectedReminderTime!.format(
                                              context,
                                            );

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
                                        color: Colors.orange.withValues(
                                          alpha: 0.1,
                                        ),
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
                                                  selectedReminder ==
                                                      'No reminder'
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
                                                  selectedReminder ==
                                                      'No reminder'
                                                  ? Colors.grey[400]
                                                  : (selectedReminderTime !=
                                                            null
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
                                    // Immediately stop any running sheet transition and jump to hidden
                                    try {
                                      _sheetAnimController.stop();
                                      _sheetAnimController.value = 0.0;
                                    } catch (_) {
                                      // ignore - controller may be disposed or not running
                                    }
                                    // Pop the bottom sheet synchronously
                                    if (Navigator.of(context).canPop()) {
                                      Navigator.of(context).pop();
                                    }
                                    // Reset the parent loading flag to ensure UI returns to normal
                                    if (mounted) {
                                      this.setState(() {
                                        _isAddingBill = false;
                                      });
                                    }
                                  },
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    side: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
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
                                        if (nameController.text
                                            .trim()
                                            .isEmpty) {
                                          throw Exception(
                                            'Bill name is required',
                                          );
                                        }
                                        if (amountController.text
                                            .trim()
                                            .isEmpty) {
                                          throw Exception('Amount is required');
                                        }
                                        if (dueDateController.text
                                            .trim()
                                            .isEmpty) {
                                          throw Exception(
                                            'Due date is required',
                                          );
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
                                        String fullDueDate =
                                            dueDateController.text;
                                        if (selectedTime != null) {
                                          fullDueDate +=
                                              ' ${selectedTime!.format(context)}';
                                        }

                                        // Create subscription data object
                                        final subscription = {
                                          'name': nameController.text.trim(),
                                          'amount': amountController.text
                                              .trim(),
                                          'dueDate': dueDateController.text
                                              .trim(),
                                          'dueTime': dueTimeController.text
                                              .trim(),
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
                                          'categoryColor': selectedCategory
                                              .color
                                              .toARGB32(),
                                          'categoryBackgroundColor':
                                              selectedCategory.backgroundColor
                                                  .toARGB32(),
                                          'notes':
                                              notesController.text
                                                  .trim()
                                                  .isEmpty
                                              ? null
                                              : notesController.text.trim(),
                                          'status':
                                              'upcoming', // Set initial status
                                          'createdAt': DateTime.now()
                                              .toIso8601String(),
                                          'lastModified': DateTime.now()
                                              .toIso8601String(),
                                        };

                                        // Close bottom sheet first for better UX
                                        if (mounted) {
                                          Navigator.pop(context);
                                        }

                                        // Then process the save operation in background
                                        unawaited(
                                          _processBillSave(
                                            isEditMode,
                                            currentEditIndex,
                                            subscription,
                                            selectedReminderTime,
                                            selectedReminder,
                                            selectedDate,
                                            nameController.text,
                                            amountController.text,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      debugPrint('Error adding bill: $e');
                                      if (mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Error adding bill: ${e.toString()}',
                                            ),
                                            backgroundColor: Colors.red,
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
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
              ),
            );
          },
        ),
      );
    } finally {
      // Dispose the transient animation controller used for the sheet transition
      _sheetAnimController.dispose();
    }

    // Handle bottom sheet dismissal - always reset loading state
    if (mounted) {
      setState(() {
        _isAddingBill = false;
      });
    }
  }

  // Show full-screen add bill screen
  Future<void> showAddBillFullScreen(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddEditBillScreen(
          onBillSaved: (billData, editIndex) async {
            Navigator.pop(context, billData);
          },
        ),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      await _handleBillSaved(result, null);
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
      if (selectedReminderTime != null && selectedReminder != 'No reminder') {
        // Calculate the actual reminder date based on the reminder preference
        DateTime reminderDate;
        if (selectedDate != null) {
          reminderDate = _calculateReminderDate(selectedDate, selectedReminder);
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
        if (reminderDateTime.isAfter(DateTime.now())) {
          await NotificationService().scheduleNotification(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            title: 'Bill Reminder: $billName',
            body: 'Your bill for $billName of $billAmount is due soon!',
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
        unawaited(
          _updateBill(currentEditIndex, subscription)
              .then((_) {
                debugPrint('✅ Updated bill in storage for $billName');
              })
              .catchError((error) {
                debugPrint('❌ Failed to update bill: $error');
              }),
        );
      } else {
        // Add to UI immediately for faster feedback
        if (mounted) {
          setState(() {
            _bills.add(subscription);
            _updateCachedCalculations(); // Update cached calculations
          });
        }

        // Save to storage in parallel
        unawaited(
          _addSubscription(subscription)
              .then((_) {
                debugPrint('✅ Added bill to storage for $billName');
              })
              .catchError((error) {
                debugPrint('❌ Failed to add bill: $error');
              }),
        );
      }

      debugPrint('✅ Bill save completed successfully');
    } catch (e) {
      debugPrint('❌ Error in background bill save: $e');
      // Show error message if still on screen
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving bill: ${e.toString()}'),
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
    unawaited(
      _checkConnectivity().then((_) async {
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
                    content: Text(
                      'Failed to save to server. Please try again.',
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
      }),
    );
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
      debugPrint(
        '🔄 Skipping data load - already have ${_bills.length} bills loaded',
      );
      return;
    }

    // Check if we should skip data loading (e.g., when navigating back)
    final now = DateTime.now();
    if (_lastDataLoadTime != null &&
        now.difference(_lastDataLoadTime!) < const Duration(seconds: 30)) {
      debugPrint(
        '🔄 Skipping data load - last load was ${now.difference(_lastDataLoadTime!).inSeconds} seconds ago',
      );
      return;
    }

    // Only show loading indicator if we have no data at all
    final shouldShowLoading = _bills.isEmpty && !_isBackgroundRefresh;
    if (shouldShowLoading && mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    debugPrint('🔄 Loading data with local-first approach...');

    try {
      // Always load from local storage first (fastest)
      debugPrint('📱 Loading from local storage...');
      final subscriptions = await _subscriptionService.getSubscriptions();
      debugPrint('✅ Loaded ${subscriptions.length} bills from local storage');

      // Filter out invalid/ghost bills - only show bills that have proper IDs and valid data
      final filteredSubscriptions = subscriptions.where((bill) {
        try {
          // Skip bills without a name
          if (bill['name'] == null) {
            debugPrint('🗑️ Filtering out bill with no name');
            return false;
          }

          // Check for valid ID structure
          final hasValidId =
              bill['id'] != null && bill['id'].toString().isNotEmpty;
          final hasFirebaseId =
              bill['firebaseId'] != null &&
              bill['firebaseId'].toString().isNotEmpty;
          final hasLocalId =
              bill['localId'] != null && bill['localId'].toString().isNotEmpty;

          // Validate name exists and is meaningful
          final hasName =
              bill['name'] != null &&
              bill['name'].toString().trim().isNotEmpty &&
              bill['name'].toString().length > 1; // More than just a character

          // Validate amount (should be a positive number if present)
          final hasValidAmount =
              bill['amount'] == null ||
              (bill['amount'] is num && bill['amount'] >= 0) ||
              (double.tryParse(bill['amount'].toString()) != null &&
                  double.parse(bill['amount'].toString()) >= 0);

          // Validate due date format if present
          final hasValidDueDate =
              bill['dueDate'] == null ||
              (bill['dueDate'] is String &&
                  bill['dueDate'].toString().isNotEmpty);

          // Keep if it has valid Firebase ID OR valid local ID with name and valid data
          final isValid =
              hasFirebaseId ||
              (hasLocalId && hasName && hasValidAmount && hasValidDueDate);

          if (!isValid) {
            debugPrint(
              '🗑️ Filtering out invalid bill: ${bill['name']} (ID: ${bill['id']}, FirebaseID: ${bill['firebaseId']}, LocalID: ${bill['localId']}, Amount: ${bill['amount']})',
            );
          }

          return isValid;
        } catch (e) {
          debugPrint('🗑️ Error validating bill, filtering out: $e');
          return false; // Filter out any bill that causes validation errors
        }
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

        // Fetch latest data from Firestore on app startup for cross-device sync
        await _fetchLatestFromFirestore();
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

  // Fetch latest data from Firestore on app startup
  Future<void> _fetchLatestFromFirestore() async {
    if (!mounted) return;

    // Declare here so it's available after the try/catch for emergency checks
    List<Map<String, dynamic>> firestoreData = [];

    try {
      debugPrint('🔥 [_fetchLatestFromFirestore] Starting fetch process...');
      debugPrint(
        '🔥 [_fetchLatestFromFirestore] Current _bills count: ${_bills.length}',
      );

      // Check if online first
      debugPrint('🔥 [_fetchLatestFromFirestore] Checking online status...');
      final isOnline = await _subscriptionService.isOnline();
      debugPrint(
        '🔥 [_fetchLatestFromFirestore] Online status result: $isOnline',
      );

      if (!isOnline) {
        debugPrint(
          '📵 [_fetchLatestFromFirestore] Offline, skipping Firestore fetch',
        );
        return;
      }

      // Debug: Check current user
      final currentUser = FirebaseAuth.instance.currentUser;
      debugPrint(
        '👤 [_fetchLatestFromFirestore] Current user: ${currentUser?.uid ?? "NOT LOGGED IN"}',
      );
      debugPrint(
        '📧 [_fetchLatestFromFirestore] User email: ${currentUser?.email ?? "UNKNOWN"}',
      );

      // Fetch fresh data from Firestore
      debugPrint('🔥 [_fetchLatestFromFirestore] Fetching from Firestore...');
      firestoreData = await _subscriptionService.getFirebaseSubscriptionsOnly();
      debugPrint(
        '✅ [_fetchLatestFromFirestore] Fetched ${firestoreData.length} bills from Firestore',
      );

      // Debug: Log the fetched bills
      for (int i = 0; i < firestoreData.length; i++) {
        final bill = firestoreData[i];
        debugPrint(
          '📋 [_fetchLatestFromFirestore] Firestore bill $i: ${bill['name']} (ID: ${bill['firebaseId']})',
        );
      }

      // Get local data for comparison
      debugPrint(
        '🔥 [_fetchLatestFromFirestore] Getting local data for comparison...',
      );
      final localData = await _subscriptionService.getSubscriptions();
      debugPrint(
        '📱 [_fetchLatestFromFirestore] Local data has ${localData.length} bills',
      );

      // Debug: Log the local bills
      for (int i = 0; i < localData.length; i++) {
        final bill = localData[i];
        debugPrint(
          '📱 [_fetchLatestFromFirestore] Local bill $i: ${bill['name']} (FirebaseID: ${bill['firebaseId']}, LocalID: ${bill['localId']})',
        );
      }

      // Check if there are differences that warrant an update
      bool needsUpdate = false;

      // Simple comparison: if counts differ, we need update
      if (firestoreData.length != localData.length) {
        needsUpdate = true;
        debugPrint(
          '📊 Data count mismatch - Firestore: ${firestoreData.length}, Local: ${localData.length}',
        );
      }

      // Check for newer updates in Firestore
      if (!needsUpdate) {
        for (final firestoreBill in firestoreData) {
          final firestoreId = firestoreBill['firebaseId']?.toString();
          if (firestoreId == null) continue;

          final localBill = localData.firstWhere(
            (bill) => bill['firebaseId']?.toString() == firestoreId,
            orElse: () => <String, dynamic>{},
          );

          if (localBill.isEmpty) {
            needsUpdate = true;
            debugPrint(
              '🆕 New bill found in Firestore: ${firestoreBill['name']}',
            );
            break;
          }

          // Compare last modified timestamps
          final firestoreModified = firestoreBill['lastModified']?.toString();
          final localModified = localBill['lastModified']?.toString();

          if (firestoreModified != null && localModified != null) {
            try {
              final firestoreTime = DateTime.parse(firestoreModified);
              final localTime = DateTime.parse(localModified);

              if (firestoreTime.isAfter(localTime)) {
                needsUpdate = true;
                debugPrint(
                  '🔄 Newer version found in Firestore for: ${firestoreBill['name']}',
                );
                break;
              }
            } catch (e) {
              debugPrint('⚠️ Error parsing timestamps for comparison: $e');
            }
          }
        }
      }

      // If update is needed, sync the data
      if (needsUpdate) {
        debugPrint(
          '🔄 [_fetchLatestFromFirestore] UPDATE NEEDED - Updating local data with latest from Firestore...',
        );

        // Import Firestore data into local storage
        debugPrint(
          '🔄 [_fetchLatestFromFirestore] Importing Firestore data to local storage...',
        );
        await _subscriptionService.importFirestoreToLocal(firestoreData);

        // Perform a full sync to merge Firestore data with local data
        debugPrint(
          '🔄 [_fetchLatestFromFirestore] Performing periodic sync...',
        );
        await _subscriptionService.performPeriodicSync();

        // Reload the updated data
        debugPrint('🔄 [_fetchLatestFromFirestore] Reloading updated data...');
        final updatedData = await _subscriptionService.getSubscriptions();
        debugPrint(
          '🔄 [_fetchLatestFromFirestore] Updated data count: ${updatedData.length}',
        );

        if (mounted) {
          setState(() {
            _bills = updatedData;
            _updateCachedCalculations();
            _initializeBillStatuses();
          });

          debugPrint(
            '✅ [_fetchLatestFromFirestore] Successfully updated with latest Firestore data',
          );

          // Show a subtle notification about the update
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Data synchronized with cloud'),
                backgroundColor: Colors.blue,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      } else {
        debugPrint(
          '✅ NO UPDATE NEEDED - Local data is already up to date with Firestore',
        );
      }
    } catch (e) {
      debugPrint('❌ Failed to fetch from Firestore on startup: $e');
      // Don't show error to user - this is a background operation
    }

    // After regular sync, if we still have no bills but Firestore showed data, trigger emergency sync
    if (mounted && firestoreData.length > 0 && _bills.length == 0) {
      debugPrint(
        '🚨 EMERGENCY SYNC TRIGGERED - Firestore has ${firestoreData.length} bills but local is empty',
      );
      debugPrint('🚨 Current _bills length: ${_bills.length}');
      debugPrint('🚨 Firestore data length: ${firestoreData.length}');
      unawaited(_emergencyFirestoreSync());
    } else {
      debugPrint(
        '✅ No emergency sync needed - Firestore: ${firestoreData.length}, Local: ${_bills.length}',
      );
    }
  }

  // Emergency sync method - directly import all Firestore bills
  Future<void> _emergencyFirestoreSync() async {
    if (!mounted) return;

    try {
      debugPrint('🚨 EMERGENCY FIRESTORE SYNC STARTED...');
      debugPrint(
        '🚨 Emergency sync - _bills length before sync: ${_bills.length}',
      );

      // Check if online first
      final isOnline = await _subscriptionService.isOnline();
      if (!isOnline) {
        debugPrint('📵 Offline, skipping emergency sync');
        return;
      }

      // Debug: Check current user
      final currentUser = FirebaseAuth.instance.currentUser;
      debugPrint(
        '👤 Emergency sync - Current user: ${currentUser?.uid ?? "NOT LOGGED IN"}',
      );

      // Fetch ALL data from Firestore
      final firestoreData = await _subscriptionService
          .getFirebaseSubscriptionsOnly();
      debugPrint(
        '🚨 Emergency sync - Fetched ${firestoreData.length} bills from Firestore',
      );

      // Get current local data
      final localData = await _subscriptionService.getSubscriptions();
      debugPrint(
        '🚨 Emergency sync - Current local data has ${localData.length} bills',
      );

      // Create a map of existing local bills by firebaseId for quick lookup
      final Map<String, Map<String, dynamic>> localBillsByFirebaseId = {};
      for (final localBill in localData) {
        final firebaseId = localBill['firebaseId']?.toString();
        if (firebaseId != null && firebaseId.isNotEmpty) {
          localBillsByFirebaseId[firebaseId] = localBill;
        }
      }

      // Track new bills from Firestore
      final List<Map<String, dynamic>> newBills = [];

      // Import any bills from Firestore that don't exist locally
      for (final firestoreBill in firestoreData) {
        final firebaseId = firestoreBill['firebaseId']?.toString();
        if (firebaseId == null || firebaseId.isEmpty) {
          debugPrint(
            '⚠️ Skipping Firestore bill with no firebaseId: ${firestoreBill['name']}',
          );
          continue;
        }

        if (!localBillsByFirebaseId.containsKey(firebaseId)) {
          debugPrint(
            '🆕 EMERGENCY SYNC - Found new bill from Firestore: ${firestoreBill['name']} (ID: $firebaseId)',
          );

          // Create a copy for local storage with Timestamp conversion
          final localBillCopy = _convertFirestoreTimestamps(firestoreBill);
          localBillCopy['localId'] =
              firestoreBill['firebaseId']; // Use firebaseId as localId
          localBillCopy['syncPending'] = false; // Already synced
          localBillCopy['source'] = 'firestore_emergency_sync';

          newBills.add(localBillCopy);
        }
      }

      // Save new bills to local storage
      if (newBills.isNotEmpty) {
        debugPrint(
          '💾 EMERGENCY SYNC - Saving ${newBills.length} new bills to local storage',
        );

        for (final newBill in newBills) {
          try {
            await _subscriptionService.addSubscription(newBill);
            debugPrint('✅ EMERGENCY SYNC - Saved bill: ${newBill['name']}');
          } catch (e) {
            debugPrint(
              '❌ EMERGENCY SYNC - Failed to save bill ${newBill['name']}: $e',
            );
          }
        }

        // Reload all data to show the new bills
        final updatedData = await _subscriptionService.getSubscriptions();

        if (mounted) {
          setState(() {
            _bills = updatedData;
            _updateCachedCalculations();
            _initializeBillStatuses();
          });

          debugPrint(
            '🎉 EMERGENCY SYNC COMPLETED - Added ${newBills.length} bills from Firestore',
          );

          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Emergency sync completed! Added ${newBills.length} bills from cloud.',
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        debugPrint('✅ EMERGENCY SYNC - No new bills found in Firestore');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No new bills found in cloud'),
              backgroundColor: Colors.blue,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ EMERGENCY SYNC FAILED: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Emergency sync failed: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // Convert Firestore Timestamp objects to ISO strings for local storage
  Map<String, dynamic> _convertFirestoreTimestamps(Map<String, dynamic> bill) {
    final convertedBill = Map<String, dynamic>.from(bill);

    // Convert Timestamp fields to ISO strings
    final timestampFields = [
      'createdAt',
      'updatedAt',
      'lastModified',
      'dueDate',
      'paidDate',
    ];

    for (final field in timestampFields) {
      if (convertedBill[field] != null) {
        if (convertedBill[field] is DateTime) {
          convertedBill[field] = (convertedBill[field] as DateTime)
              .toIso8601String();
        } else if (convertedBill[field] is Timestamp) {
          // Handle Firestore Timestamp objects
          try {
            final timestamp = convertedBill[field] as Timestamp;
            convertedBill[field] = timestamp.toDate().toIso8601String();
            debugPrint('🔄 Converted $field Timestamp to ISO string');
          } catch (e) {
            debugPrint('⚠️ Failed to convert Timestamp field $field: $e');
            convertedBill[field] = DateTime.now().toIso8601String();
          }
        }
      }
    }

    return convertedBill;
  }

  // Forced sync method - bypasses online check for manual refresh
  Future<void> _forcedSyncFromFirestore() async {
    if (!mounted) return;

    try {
      debugPrint('🔄 FORCED SYNC STARTED (bypassing online check)...');
      debugPrint(
        '🔄 Forced sync - _bills length before sync: ${_bills.length}',
      );

      // Check current user first
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        debugPrint('🔄 Forced sync - No user logged in');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No user logged in'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      debugPrint(
        '🔄 Forced sync - User: ${currentUser.uid} (${currentUser.email})',
      );

      // Try to fetch from Firestore directly (bypassing isOnline check)
      List<Map<String, dynamic>> firestoreData = [];
      try {
        debugPrint('🔄 Forced sync - Attempting direct Firestore fetch...');
        firestoreData = await _subscriptionService
            .getFirebaseSubscriptionsOnly();
        debugPrint(
          '🔄 Forced sync - Fetched ${firestoreData.length} bills from Firestore',
        );
      } catch (e) {
        debugPrint('🔄 Forced sync - Firestore fetch failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Forced sync failed: ${e.toString()}'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      if (firestoreData.isEmpty) {
        debugPrint('🔄 Forced sync - No bills found in Firestore');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No bills found in cloud'),
              backgroundColor: Colors.blue,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Import Firestore data into local storage
      debugPrint(
        '🔄 Forced sync - Importing ${firestoreData.length} bills to local storage...',
      );
      await _subscriptionService.importFirestoreToLocal(firestoreData);

      // Reload the updated data
      debugPrint('🔄 Forced sync - Reloading data...');
      final updatedData = await _subscriptionService.getSubscriptions();
      debugPrint('🔄 Forced sync - Updated data count: ${updatedData.length}');

      if (mounted) {
        setState(() {
          _bills = updatedData;
          _updateCachedCalculations();
          _initializeBillStatuses();
        });

        debugPrint(
          '✅ Forced sync completed! Updated with ${updatedData.length} bills from cloud.',
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Forced sync completed! Added ${updatedData.length} bills from cloud.',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ FORCED SYNC FAILED: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Forced sync failed: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
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
      await _subscriptionService.cleanupDuplicateSubscriptions();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cleanup completed successfully'),
            backgroundColor: Colors.green,
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
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}
