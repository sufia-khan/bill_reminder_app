import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:projeckt_k/screens/profile_screen.dart';
import 'package:projeckt_k/services/subscription_service.dart';
import 'package:projeckt_k/services/notification_service.dart';
import 'package:projeckt_k/models/category_model.dart';
import 'package:projeckt_k/widgets/subtitle_changing.dart';
import 'package:projeckt_k/widgets/bill_summary_cards.dart';
import 'package:projeckt_k/widgets/bill_item_widget.dart';

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
  Timer? _updateTimer;
  String _selectedCategory = 'all'; // 'all' or specific category id
  // shared sizes
  // shared sizes
  double sharedTop = 36;
  double sharedMiddle = 70;
  double sharedBottom = 45;

  // base sizes for "This Month"
  double baseBottomAmountFontSize = 14;
  double baseBottomTextFontSize = 13;

  @override
  void initState() {
    super.initState();
    _initServices();

    _checkConnectivity();
    _loadSubscriptions();
    _setupConnectivityListener();
    _startPeriodicUpdates();
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
    _connectivitySubscription?.cancel();
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
    }
  }

  void _setupConnectivityListener() {
    _connectivitySubscription = _subscriptionService
        .connectivityStream()
        .listen((isOnline) {
          debugPrint('Connectivity stream update: $isOnline');
          if (mounted) {
            setState(() {
              _isOnline = isOnline;
            });

            // Auto-sync when coming online
            if (isOnline) {
              _autoSyncWhenOnline();
            }
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

  // Mark bill as paid from notification action
  void _markBillAsPaidFromNotification(String billId) {
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
        _markAsPaid(billIndex);

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
      final success = await _subscriptionService.syncLocalToFirebase();
      if (mounted) {
        setState(() {});
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Auto-sync completed successfully!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
          await _loadSubscriptions(); // Refresh the list
        }
      }
    } catch (e) {
      debugPrint('Auto-sync failed: $e');
    }
  }

  void _showBillsDetailScreen(BuildContext context, String category) {
    List<Map<String, dynamic>> filteredBills = [];

    final now = DateTime.now();

    for (var bill in _bills) {
      try {
        final dueDate = _parseDueDate(bill);
        if (dueDate != null) {
          bool shouldInclude = false;

          switch (category.toLowerCase()) {
            case 'upcoming':
              final oneMonthFromNow = now.add(const Duration(days: 30));
              shouldInclude =
                  dueDate.isAfter(now) &&
                  dueDate.isBefore(oneMonthFromNow) &&
                  bill['status'] != 'paid';
              break;
            case 'paid':
              // Check if bill is marked as paid and has a paid date
              shouldInclude =
                  bill['status'] == 'paid' && bill['paidDate'] != null;
              break;
            case 'overdue':
              final sixMonthsAgo = now.subtract(const Duration(days: 180));
              shouldInclude =
                  dueDate.isBefore(now) &&
                  dueDate.isAfter(sixMonthsAgo) &&
                  bill['status'] != 'paid';
              break;
          }

          if (shouldInclude) {
            filteredBills.add(
              Map.from(bill)..['originalIndex'] = _bills.indexOf(bill),
            );
          }
        }
      } catch (e) {
        debugPrint('Error filtering bills: $e');
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _getCategoryColor(category).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _getCategoryIcon(category),
                      color: _getCategoryColor(category),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$category Bills',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                        ),
                        Text(
                          '${filteredBills.length} bills',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: filteredBills.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No $category bills',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredBills.length,
                      itemBuilder: (context, index) {
                        final bill = filteredBills[index];
                        return BillItemWidget(
                          bill: {...bill, 'index': index},
                          onMarkAsPaid: (billIndex) async {
                            bool? confirm = await _showMarkAsPaidConfirmDialog(
                              context,
                              bill['name'] ?? 'this bill',
                            );
                            if (confirm == true) {
                              await _markBillAsPaid(billIndex);
                              _loadSubscriptions();
                            }
                          },
                          onDelete: (billIndex) async {
                            bool? confirm = await _showDeleteConfirmDialog(
                              context,
                            );
                            if (confirm == true) {
                              await _deleteSubscription(billIndex);
                              _loadSubscriptions();
                            }
                          },
                          onEdit: (billData) {
                            _editBill(billData['originalIndex']);
                          },
                          onShowDetails: (billData) {
                            // Show bill details if needed
                          },
                          useHomeScreenEdit: true,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
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

  void _editBill(int index) {
    if (index < 0 || index >= _bills.length) return;

    final bill = _bills[index];
    showAddBillBottomSheet(context, bill: bill, editIndex: index);
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

      // Refresh data to update all statistics
      await _loadSubscriptions();
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

  void _showEditBillScreen(
    BuildContext context,
    Map<String, dynamic> bill,
    int index,
  ) {
    final _formKey = GlobalKey<FormState>();
    final _nameController = TextEditingController(text: bill['name'] ?? '');
    final _amountController = TextEditingController(text: bill['amount'] ?? '');
    final _dueDateController = TextEditingController(
      text: bill['dueDate'] ?? '',
    );
    final _dueTimeController = TextEditingController(
      text: bill['dueTime'] ?? '',
    );
    final _notesController = TextEditingController(text: bill['notes'] ?? '');

    DateTime? _selectedDate;
    TimeOfDay? _selectedTime;
    String _selectedFrequency = bill['frequency'] ?? 'Monthly';
    String _selectedReminder = bill['reminder'] ?? 'Same day';
    Category _selectedCategory = Category.defaultCategories[0];

    // Parse the due date and time if they exist
    final parsedDate = _parseDueDate(bill);
    if (parsedDate != null) {
      _selectedDate = parsedDate;
      _selectedTime = TimeOfDay(
        hour: parsedDate.hour,
        minute: parsedDate.minute,
      );
      _dueDateController.text = bill['dueDate'] ?? '';
      _dueTimeController.text = bill['dueTime'] ?? '';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
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
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return Form(
                key: _formKey,
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
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.edit,
                              color: Colors.orange[700],
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Edit Bill',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                  fontSize: 16,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _nameController,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Bill Name',
                          hintText: 'e.g., Netflix, Spotify',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Colors.orange,
                              width: 1,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Colors.orange.withOpacity(0.6),
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Colors.orange,
                              width: 1.5,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                          prefixIcon: Container(
                            margin: const EdgeInsets.all(8),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              Icons.notifications,
                              color: Colors.blue[700],
                              size: 16,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter bill name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _amountController,
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
                              color: Colors.orange,
                              width: 1,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Colors.orange.withOpacity(0.6),
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Colors.orange,
                              width: 1.5,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                          prefixIcon: Container(
                            margin: const EdgeInsets.all(8),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
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
                              controller: _dueDateController,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                              ),
                              readOnly: true,
                              onTap: () async {
                                final DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate:
                                      _selectedDate ??
                                      DateTime.now().add(
                                        const Duration(days: 1),
                                      ),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime(2100),
                                  builder: (context, child) {
                                    return Theme(
                                      data: Theme.of(context).copyWith(
                                        colorScheme: ColorScheme.light(
                                          primary: Colors.orange,
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
                                    _selectedDate = DateTime(
                                      picked.year,
                                      picked.month,
                                      picked.day,
                                      _selectedTime?.hour ?? 0,
                                      _selectedTime?.minute ?? 0,
                                    );
                                    _dueDateController.text =
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
                                    color: Colors.orange,
                                    width: 1,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.orange.withOpacity(0.6),
                                    width: 1,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.orange,
                                    width: 1.5,
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                                prefixIcon: Container(
                                  margin: const EdgeInsets.all(8),
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.withOpacity(0.1),
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
                                  color: Colors.orange,
                                  size: 18,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
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
                              controller: _dueTimeController,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                              ),
                              readOnly: true,
                              onTap: () async {
                                final defaultTime =
                                    await _getDefaultNotificationTime();
                                final TimeOfDay? picked = await showTimePicker(
                                  context: context,
                                  initialTime: _selectedTime ?? defaultTime,
                                  builder: (context, child) {
                                    return Theme(
                                      data: Theme.of(context).copyWith(
                                        colorScheme: ColorScheme.light(
                                          primary: Colors.orange,
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
                                    _selectedTime = picked;
                                    _dueTimeController.text = picked.format(
                                      context,
                                    );

                                    // Update selectedDate with the new time
                                    if (_selectedDate != null) {
                                      _selectedDate = DateTime(
                                        _selectedDate!.year,
                                        _selectedDate!.month,
                                        _selectedDate!.day,
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
                                    color: Colors.orange,
                                    width: 1,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.orange.withOpacity(0.6),
                                    width: 1,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: Colors.orange,
                                    width: 1.5,
                                  ),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                                prefixIcon: Container(
                                  margin: const EdgeInsets.all(8),
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.1),
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
                                  color: Colors.orange,
                                  size: 18,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
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
                      TextFormField(
                        controller: _notesController,
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
                              color: Colors.orange,
                              width: 1,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Colors.orange.withOpacity(0.6),
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Colors.orange,
                              width: 1.5,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                          prefixIcon: Container(
                            margin: const EdgeInsets.all(8),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.teal.withOpacity(0.1),
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
                                if (_formKey.currentState!.validate()) {
                                  final updatedBill = {
                                    'name': _nameController.text,
                                    'amount': _amountController.text,
                                    'dueDate': _dueDateController.text,
                                    'dueTime': _dueTimeController.text,
                                    'dueDateTime': _selectedDate
                                        ?.toIso8601String(),
                                    'frequency': _selectedFrequency,
                                    'reminder': _selectedReminder,
                                    'notes': _notesController.text.isEmpty
                                        ? null
                                        : _notesController.text,
                                  };

                                  await _updateBill(index, updatedBill);
                                  Navigator.pop(context);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text(
                                'Save Changes',
                                style: TextStyle(fontSize: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _updateBill(int index, Map<String, dynamic> updatedBill) async {
    if (index < 0 || index >= _bills.length) return;

    // Check network status first
    await _checkConnectivity();
    debugPrint('Updating bill. Network status: $_isOnline');

    // Get the original bill for reference
    final originalBill = _bills[index];
    final billId = originalBill['id'];

    try {
      if (_isOnline && billId != null) {
        // Try to update in Firebase first
        await _subscriptionService.updateSubscription(billId, updatedBill);

        // If successful, update local list
        if (mounted) {
          setState(() {
            _bills[index] = Map.from(originalBill)..addAll(updatedBill);
            _checkForOverdueBills(); // Immediate check for overdue status
          });

          // Update reminders if needed
          await _updateBillReminders(_bills[index]);

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
      } else {
        // Offline or no ID: Update locally only
        if (mounted) {
          setState(() {
            _bills[index] = Map.from(originalBill)..addAll(updatedBill);
            _checkForOverdueBills(); // Immediate check for overdue status
          });

          // Update reminders locally
          await _updateBillReminders(_bills[index]);

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
        }
      }
    } catch (e) {
      // Re-check connectivity to make sure it's actually offline
      await _checkConnectivity();

      if (!_isOnline) {
        // Only show offline message if actually offline
        if (mounted) {
          setState(() {
            _bills[index] = Map.from(originalBill)..addAll(updatedBill);
            _checkForOverdueBills(); // Immediate check for overdue status
          });

          // Update reminders locally
          await _updateBillReminders(_bills[index]);

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
        }
      } else {
        // If online but Firebase failed, show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update bill. Please try again.'),
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

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'upcoming':
        return Colors.blue[700]!;
      case 'paid':
        return Colors.green[700]!;
      case 'overdue':
        return Colors.red[700]!;
      default:
        return kPrimaryColor;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'upcoming':
        return Icons.calendar_today;
      case 'paid':
        return Icons.check_circle;
      case 'overdue':
        return Icons.warning;
      default:
        return Icons.subscriptions;
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
            final day = int.parse(parts[0]);
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
                      // Top row: icon + title/subtitle + profile
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
                                      .withOpacity(0.15), // light bg
                                  child: Icon(
                                    Icons.person, // 🔄 subscription icon
                                    color: Colors.indigoAccent, // main color
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ),
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
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: _buildCategoryTabsList(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Category Content
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildCategoryContent(),
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

  // Category Tabs and Content Methods
  List<Widget> _buildCategoryTabsList() {
    List<Widget> tabs = [];

    // "All" tab
    tabs.add(
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: _buildCategoryTab(
          title: 'All',
          isSelected: _selectedCategory == 'all',
          onTap: () {
            setState(() {
              _selectedCategory = 'all';
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
            isSelected: _selectedCategory == category.id,
            onTap: () {
              setState(() {
                _selectedCategory = category.id;
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
                    color: Colors.black.withOpacity(0.2),
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
    if (_selectedCategory == 'all') {
      return _buildAllCategoriesContent();
    } else {
      return _buildSingleCategoryContent(_selectedCategory);
    }
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
                  _loadSubscriptions();
                }
              },
              onDelete: (billIndex) async {
                bool? confirm = await _showDeleteConfirmDialog(context);
                if (confirm == true) {
                  await _deleteSubscription(billIndex);
                  _loadSubscriptions();
                }
              },
              onEdit: (billData) {
                _editBill(billData['originalIndex']);
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

  // Mark bill as paid
  void _markAsPaid(int billIndex) {
    if (billIndex >= 0 && billIndex < _bills.length) {
      setState(() {
        _bills[billIndex]['status'] = 'paid';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_bills[billIndex]['name']} marked as paid!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
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

  void showAddBillBottomSheet(BuildContext context, {Map<String, dynamic>? bill, int? editIndex}) {
    final _formKey = GlobalKey<FormState>();
    final _nameController = TextEditingController(text: bill?['name'] ?? '');
    final _amountController = TextEditingController(text: bill?['amount']?.toString() ?? '');
    final _dueDateController = TextEditingController(text: bill?['dueDate'] ?? '');
    final _dueTimeController = TextEditingController(text: bill?['dueTime'] ?? '');
    final _notesController = TextEditingController(text: bill?['notes'] ?? '');
    final _reminderTimeController = TextEditingController();
    DateTime? _selectedDate;
    TimeOfDay? _selectedTime;  // This is the DUE time (when bill expires)
    TimeOfDay? _selectedReminderTime;  // This is the REMINDER time (when notification is sent)
    String _selectedFrequency = bill?['frequency'] ?? 'Monthly';
    String _selectedReminder = bill?['reminder'] ?? 'Same day';
    Category _selectedCategory = Category.defaultCategories[0];

    final bool isEditMode = bill != null && editIndex != null;

    // Parse the due date and time if they exist (for edit mode)
    if (isEditMode) {
      final parsedDate = _parseDueDate(bill!);
      if (parsedDate != null) {
        _selectedDate = parsedDate;
        _selectedTime = TimeOfDay(hour: parsedDate.hour, minute: parsedDate.minute);

        // Format date and time for display
        _dueDateController.text = '${parsedDate.day.toString().padLeft(2, '0')}/${parsedDate.month.toString().padLeft(2, '0')}/${parsedDate.year}';
        _dueTimeController.text = _selectedTime.format(context);
      }

      // Parse the reminder time if it exists (SEPARATE from due time)
      if (bill!['reminderTime'] != null) {
        try {
          final reminderTimeStr = bill['reminderTime'];
          if (reminderTimeStr is String) {
            final parts = reminderTimeStr.split(':');
            if (parts.length == 2) {
              _selectedReminderTime = TimeOfDay(
                hour: int.parse(parts[0]),
                minute: int.parse(parts[1]),
              );
            }
          } else if (reminderTimeStr is Map) {
            _selectedReminderTime = TimeOfDay(
              hour: reminderTimeStr['hour'] ?? 9,
              minute: reminderTimeStr['minute'] ?? 0,
            );
          }
        } catch (e) {
          // If parsing fails, fall back to default
          _selectedReminderTime = await _getDefaultNotificationTime();
        }
      } else {
        // If no specific reminder time, get default from settings
        _selectedReminderTime = await _getDefaultNotificationTime();
      }
    }

    // Set category if exists
    if (bill?['category'] != null) {
        final category = Category.findById(bill['category']);
        if (category != null) {
          _selectedCategory = category;
        }
      }
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
          child: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              // Make these variables accessible inside the builder
              final bool isEditMode = bill != null && editIndex != null;
              final int? currentEditIndex = editIndex;
              return Form(
                key: _formKey,
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
                              color: (isEditMode ? Colors.orange[700]! : kPrimaryColor).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isEditMode ? Icons.edit : Icons.add,
                              color: isEditMode ? Colors.orange[700]! : kPrimaryColor,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            isEditMode ? 'Edit Bill' : 'Add Bill',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isEditMode ? Colors.orange[700]! : kPrimaryColor,
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
                              _selectedCategory = category;
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
                                    color: _selectedCategory.backgroundColor,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    _selectedCategory.icon,
                                    color: _selectedCategory.color,
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
                                        _selectedCategory.name,
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
                        controller: _nameController,
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
                              color: Colors.blue.withOpacity(0.1),
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
                        controller: _amountController,
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
                              color: Colors.green.withOpacity(0.1),
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
                              controller: _dueDateController,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                              ),
                              readOnly: true,
                              onTap: () async {
                                final DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate:
                                      _selectedDate ??
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
                                    _selectedDate = DateTime(
                                      picked.year,
                                      picked.month,
                                      picked.day,
                                      _selectedTime?.hour ?? 0,
                                      _selectedTime?.minute ?? 0,
                                    );
                                    _dueDateController.text =
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
                                    color: Colors.purple.withOpacity(0.1),
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
                              controller: _dueTimeController,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                              ),
                              readOnly: true,
                              onTap: () async {
                                final TimeOfDay? picked = await showTimePicker(
                                  context: context,
                                  initialTime:
                                      _selectedTime ??
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
                                    _selectedTime = picked;
                                    _dueTimeController.text = picked.format(
                                      context,
                                    );

                                    // Update selectedDate with the new time
                                    if (_selectedDate != null) {
                                      _selectedDate = DateTime(
                                        _selectedDate!.year,
                                        _selectedDate!.month,
                                        _selectedDate!.day,
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
                                    color: Colors.orange.withOpacity(0.1),
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
                              _selectedFrequency = frequency;
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
                                    color: Colors.orange.withOpacity(0.1),
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
                                        _selectedFrequency,
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
                              _selectedReminder = reminder;
                            });
                          }, _selectedDate);
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
                                    color: Colors.red.withOpacity(0.1),
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
                                        _selectedReminder,
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
                        onTap: _selectedReminder == 'No reminder'
                            ? null
                            : () async {
                                final defaultTime =
                                    await _getDefaultNotificationTime();
                                final TimeOfDay? picked = await showTimePicker(
                                  context: context,
                                  initialTime: _selectedReminderTime ?? defaultTime,
                                );
                                if (picked != null) {
                                  setState(() {
                                    _selectedReminderTime = picked;
                                    _reminderTimeController.text =
                                        _selectedReminderTime!.format(context);

                                    // Don't update user's default notification preference
                                    // when editing individual bill reminder time
                                  });
                                }
                              },
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: _selectedReminder == 'No reminder'
                                  ? Colors.grey.withValues(alpha: 0.3)
                                  : kPrimaryColor.withValues(alpha: 0.6),
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            color: _selectedReminder == 'No reminder'
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
                                    color: Colors.orange.withOpacity(0.1),
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
                                              _selectedReminder == 'No reminder'
                                              ? Colors.grey[400]
                                              : Colors.grey[600],
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _selectedReminder == 'No reminder'
                                            ? 'No reminder set'
                                            : (_selectedReminderTime?.format(context) ??
                                                  'Select reminder time'),
                                        style: TextStyle(
                                          color:
                                              _selectedReminder == 'No reminder'
                                              ? Colors.grey[400]
                                              : (_selectedReminderTime != null
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
                                  color: _selectedReminder == 'No reminder'
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
                        controller: _notesController,
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
                              color: Colors.teal.withOpacity(0.1),
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
                                if (_formKey.currentState!.validate()) {
                                  // Ensure we have a time set (default to user's preferred time if not selected)
                                  if (_selectedTime == null) {
                                    _selectedTime =
                                        await _getDefaultNotificationTime();
                                    _dueTimeController.text = _selectedTime!
                                        .format(context);

                                    // Update selectedDate with default time
                                    if (_selectedDate != null) {
                                      _selectedDate = DateTime(
                                        _selectedDate!.year,
                                        _selectedDate!.month,
                                        _selectedDate!.day,
                                        _selectedTime!.hour,
                                        _selectedTime!.minute,
                                      );
                                    }
                                  }

                                  // Create full due date string with time
                                  String fullDueDate = _dueDateController.text;
                                  if (_selectedTime != null) {
                                    fullDueDate +=
                                        ' ${_selectedTime!.format(context)}';
                                  }

                                  // Schedule notification if reminder time is selected
                                  if (_selectedReminderTime != null && _selectedReminder != 'No reminder') {
                                    // Calculate the actual reminder date based on the reminder preference
                                    DateTime reminderDate;
                                    if (_selectedDate != null) {
                                      reminderDate = _calculateReminderDate(_selectedDate!, _selectedReminder);
                                    } else {
                                      reminderDate = DateTime.now();
                                    }

                                    // Set the reminder time (separate from due time)
                                    final reminderDateTime = DateTime(
                                      reminderDate.year,
                                      reminderDate.month,
                                      reminderDate.day,
                                      _selectedReminderTime!.hour,
                                      _selectedReminderTime!.minute,
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
                                            'Bill Reminder: ${_nameController.text}',
                                        body:
                                            'Your bill for ${_nameController.text} of ${_amountController.text} is due soon!',
                                        scheduledTime: reminderDateTime,
                                      );
                                    }
                                  }

                                  final subscription = {
                                    'name': _nameController.text,
                                    'amount': _amountController.text,
                                    'dueDate': _dueDateController.text,
                                    'dueTime': _dueTimeController.text,
                                    'dueDateTime': _selectedDate
                                        ?.toIso8601String(),
                                    'reminderTime':
                                        _selectedReminderTime != null
                                        ? '${_selectedReminderTime!.hour.toString().padLeft(2, '0')}:${_selectedReminderTime!.minute.toString().padLeft(2, '0')}'
                                        : null,
                                    'frequency': _selectedFrequency,
                                    'reminder': _selectedReminder,
                                    'category': _selectedCategory.id,
                                    'categoryName': _selectedCategory.name,
                                    'categoryColor': _selectedCategory.color
                                        .toARGB32(),
                                    'categoryBackgroundColor': _selectedCategory
                                        .backgroundColor
                                        .toARGB32(),
                                    'notes': _notesController.text.isEmpty
                                        ? null
                                        : _notesController.text,
                                  };
                                  if (isEditMode && currentEditIndex != null) {
                                    await _updateBill(currentEditIndex, subscription);
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
              );
            },
          ),
        ),
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

        // If successful, add to local list
        if (mounted) {
          setState(() {
            _bills.add(subscription);
            _checkForOverdueBills(); // Immediate check for overdue status
          });

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
    // Filter bills for the selected category
    final categoryBills = _bills
        .where(
          (bill) =>
              bill['category']?.toLowerCase() == category.name.toLowerCase(),
        )
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: category.backgroundColor.withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: category.backgroundColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(category.icon, color: category.color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          '${categoryBills.length} bills',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            // Bills List
            Expanded(
              child: categoryBills.isEmpty
                  ? Center(
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
                            'No bills in ${category.name}',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add a new bill to get started',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: categoryBills.length,
                      itemBuilder: (context, index) {
                        final bill = categoryBills[index];
                        final dueDate = _parseDueDate(bill);
                        final now = DateTime.now();
                        final isOverdue =
                            dueDate != null &&
                            dueDate.isBefore(now) &&
                            bill['status'] != 'paid';
                        final isPaid = bill['status'] == 'paid';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[200]!),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(16),
                            title: Text(
                              bill['name'] ?? 'Unnamed Bill',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.calendar_today_outlined,
                                      size: 14,
                                      color: Colors.grey[600],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      dueDate != null
                                          ? _formatDate(dueDate)
                                          : 'No due date',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '\$${_parseAmount(bill['amount']).toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: isPaid
                                            ? Colors.green
                                            : (isOverdue
                                                  ? Colors.red
                                                  : Colors.black87),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isPaid
                                            ? Colors.green.withOpacity(0.1)
                                            : (isOverdue
                                                  ? Colors.red.withOpacity(0.1)
                                                  : Colors.orange.withOpacity(
                                                      0.1,
                                                    )),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        isPaid
                                            ? 'Paid'
                                            : (isOverdue
                                                  ? 'Overdue'
                                                  : 'Pending'),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: isPaid
                                              ? Colors.green[700]
                                              : (isOverdue
                                                    ? Colors.red[700]
                                                    : Colors.orange[700]),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) async {
                                switch (value) {
                                  case 'edit':
                                    _editBill(_bills.indexOf(bill));
                                    break;
                                  case 'paid':
                                    await _markBillAsPaid(_bills.indexOf(bill));
                                    break;
                                  case 'delete':
                                    bool? confirm =
                                        await _showDeleteConfirmDialog(context);
                                    if (confirm == true) {
                                      await _deleteSubscription(
                                        _bills.indexOf(bill),
                                      );
                                    }
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit, size: 16),
                                      SizedBox(width: 8),
                                      Text('Edit'),
                                    ],
                                  ),
                                ),
                                if (!isPaid)
                                  const PopupMenuItem(
                                    value: 'paid',
                                    child: Row(
                                      children: [
                                        Icon(Icons.check_circle, size: 16),
                                        SizedBox(width: 8),
                                        Text('Mark as Paid'),
                                      ],
                                    ),
                                  ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete, size: 16),
                                      SizedBox(width: 8),
                                      Text('Delete'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Add New Bill Button
            if (categoryBills.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context); // Close bills bottom sheet
                      // Return to add bill flow with this category pre-selected
                      Navigator.pop(context, category);
                    },
                    icon: const Icon(Icons.add),
                    label: Text('Add ${category.name} Bill'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: category.backgroundColor,
                      foregroundColor: category.color,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadSubscriptions() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final subscriptions = await _subscriptionService.getSubscriptions();
      if (mounted) {
        setState(() {
          _bills = subscriptions;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load subscriptions: $e');
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
      await _loadSubscriptions(); // Refresh the list

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

        // Refresh the list
        await _loadSubscriptions();

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
