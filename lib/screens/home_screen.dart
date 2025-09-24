import 'dart:async';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:projeckt_k/screens/all_bills_screen.dart';
import 'package:projeckt_k/screens/profile_screen.dart';
import 'package:projeckt_k/services/auth_service.dart';
import 'package:projeckt_k/services/subscription_service.dart';
import 'package:projeckt_k/services/notification_service.dart';
import 'package:projeckt_k/models/category_model.dart';
import 'package:projeckt_k/widgets/subtitle_changing.dart';
import 'package:projeckt_k/widgets/bill_summary_cards.dart';

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
  // set the fixed box heights once
  double topBox = 40;
  double midBox = 100;
  double bottomBox = 40;
  double bottomSingleLineSize = 18;
  double primarySize = 44;

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
                        return _buildBillCard(context, bill, category);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBillCard(
    BuildContext context,
    Map<String, dynamic> bill,
    String category,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bill['name'] ?? '',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Due: ${bill['dueDate'] ?? ''}${bill['dueTime'] != null ? ' ${bill['dueTime']}' : ''}',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Text(
                  '\$${bill['amount'] ?? ''}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _editBill(bill['originalIndex']);
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          side: BorderSide(color: Colors.grey[400]!),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.edit, size: 16, color: Colors.grey[700]),
                            const SizedBox(width: 6),
                            const Text('Edit', style: TextStyle(fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          bool? confirm = await _showDeleteConfirmDialog(
                            context,
                          );
                          if (confirm == true) {
                            await _deleteSubscription(bill['originalIndex']);
                            Navigator.pop(context);
                            _loadSubscriptions(); // Refresh data
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[50],
                          foregroundColor: Colors.red[700],
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delete, size: 16),
                            const SizedBox(width: 6),
                            const Text(
                              'Delete',
                              style: TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (category.toLowerCase() != 'paid') ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        bool? confirm = await _showMarkAsPaidConfirmDialog(
                          context,
                          bill['name'] ?? 'this bill',
                        );
                        if (confirm == true) {
                          await _markBillAsPaid(bill['originalIndex']);
                          Navigator.pop(context);
                          _loadSubscriptions(); // Refresh data
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[50],
                        foregroundColor: Colors.green[700],
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle, size: 16),
                          const SizedBox(width: 6),
                          const Text(
                            'Mark as Paid',
                            style: TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
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
    _showEditBillScreen(context, bill, index);
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
                                final TimeOfDay? picked = await showTimePicker(
                                  context: context,
                                  initialTime:
                                      _selectedTime ??
                                      const TimeOfDay(hour: 9, minute: 0),
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

    try {
      // In a real app, you would update the bill in the database
      // For now, we'll just update the local list and show a success message
      setState(() {
        _bills[index] = Map.from(_bills[index])..addAll(updatedBill);
        _checkForOverdueBills(); // Immediate check for overdue status
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bill updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update bill: $e'),
          backgroundColor: Colors.red,
        ),
      );
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

  // Helper methods for statistics
  Widget _buildAnimatedStatCard(
    String title,
    String count,
    String amount,
    Color backgroundColor,
    IconData icon,
    Color iconColor,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _showBillsDetailScreen(context, title);
          },
          borderRadius: BorderRadius.circular(12),
          splashColor: iconColor.withOpacity(0.1),
          highlightColor: iconColor.withOpacity(0.05),
          child: Container(
            width: double.infinity,
            height: 90, // 🔹 Reduced height
            padding: const EdgeInsets.all(8), // tighter padding
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: iconColor.withOpacity(0.25),
                width: 1.5,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [backgroundColor, backgroundColor.withOpacity(0.7)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment:
                  MainAxisAlignment.spaceEvenly, // 🔹 Distributes evenly
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: iconColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        icon,
                        color: iconColor,
                        size: 18,
                      ), // smaller icon
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 13, // smaller text
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      count,
                      style: TextStyle(
                        fontSize: 20, // smaller than before
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        shadows: [
                          Shadow(
                            color: iconColor.withOpacity(0.12),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        amount,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                          overflow: TextOverflow.ellipsis,
                          shadows: [
                            Shadow(
                              color: iconColor.withOpacity(0.08),
                              blurRadius: 1,
                              offset: const Offset(0, 1),
                            ),
                          ],
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

  double _calculateLastMonthTotal() {
    double total = 0;
    final now = DateTime.now();
    final lastMonth = now.month == 1 ? 12 : now.month - 1;
    final lastMonthYear = now.month == 1 ? now.year - 1 : now.year;

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
              total += amount;
            }
          }
        }
      } catch (e) {
        debugPrint('Error calculating last month total: $e');
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

  double _calculateMonthlyPercentageChange() {
    double thisMonthTotal = _calculateMonthlyTotal();
    double difference = _calculateMonthlyDifference();

    if (thisMonthTotal == 0) return 0;

    return (difference / thisMonthTotal) * 100;
  }

  bool _isMonthlyIncrease() {
    return _calculateMonthlyDifference() > 0;
  }

  int _getUpcomingCount() {
    int count = 0;
    final now = DateTime.now();
    final oneMonthFromNow = now.add(const Duration(days: 30));

    for (var bill in _bills) {
      try {
        final dueDate = _parseDueDate(bill);
        if (dueDate != null) {
          // Show bills that are due within the next month and not yet paid
          if (dueDate.isAfter(now) &&
              dueDate.isBefore(oneMonthFromNow) &&
              bill['status'] != 'paid') {
            count++;
          }
        }
      } catch (e) {
        debugPrint('Error getting upcoming count: $e');
      }
    }
    return count;
  }

  double _getUpcomingAmount() {
    double total = 0;
    final now = DateTime.now();
    final oneMonthFromNow = now.add(const Duration(days: 30));

    for (var bill in _bills) {
      try {
        final amount = _parseAmount(bill['amount']);
        final dueDate = _parseDueDate(bill);

        if (dueDate != null) {
          // Show bills that are due within the next month and not yet paid
          if (dueDate.isAfter(now) &&
              dueDate.isBefore(oneMonthFromNow) &&
              bill['status'] != 'paid') {
            total += amount;
          }
        }
      } catch (e) {
        debugPrint('Error getting upcoming amount: $e');
      }
    }
    return total;
  }

  int _getPaidCount() {
    int count = 0;
    final now = DateTime.now();

    for (var bill in _bills) {
      try {
        // Check if bill is marked as paid and has a paid date
        if (bill['status'] == 'paid' && bill['paidDate'] != null) {
          count++;
        }
      } catch (e) {
        debugPrint('Error getting paid count: $e');
      }
    }
    return count;
  }

  double _getPaidAmount() {
    double total = 0;
    final now = DateTime.now();

    for (var bill in _bills) {
      try {
        final amount = _parseAmount(bill['amount']);

        // Check if bill is marked as paid and has a paid date
        if (bill['status'] == 'paid' && bill['paidDate'] != null) {
          total += amount;
        }
      } catch (e) {
        debugPrint('Error getting paid amount: $e');
      }
    }
    return total;
  }

  int _getOverdueCount() {
    int count = 0;
    final now = DateTime.now();
    final sixMonthsAgo = now.subtract(
      const Duration(days: 180),
    ); // 6 months ago

    for (var bill in _bills) {
      try {
        final dueDate = _parseDueDate(bill);
        if (dueDate != null) {
          // Show bills that are overdue (before now) and within the last 6 months, and not yet paid
          if (dueDate.isBefore(now) &&
              dueDate.isAfter(sixMonthsAgo) &&
              bill['status'] != 'paid') {
            count++;
          }
        }
      } catch (e) {
        debugPrint('Error getting overdue count: $e');
      }
    }
    return count;
  }

  double _getOverdueAmount() {
    double total = 0;
    final now = DateTime.now();
    final sixMonthsAgo = now.subtract(
      const Duration(days: 180),
    ); // 6 months ago

    for (var bill in _bills) {
      try {
        final amount = _parseAmount(bill['amount']);
        final dueDate = _parseDueDate(bill);

        if (dueDate != null) {
          // Show bills that are overdue (before now) and within the last 6 months, and not yet paid
          if (dueDate.isBefore(now) &&
              dueDate.isAfter(sixMonthsAgo) &&
              bill['status'] != 'paid') {
            total += amount;
          }
        }
      } catch (e) {
        debugPrint('Error getting overdue amount: $e');
      }
    }
    return total;
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
    final authService = AuthService();

    return Scaffold(
      // AppBar now *is* the gradient card (single container)
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(
          290.0,
        ), // height includes title + stats
        child: AppBar(
          elevation: 0,
          backgroundColor:
              Colors.transparent, // let flexibleSpace draw the gradient
          automaticallyImplyLeading: false,
          flexibleSpace: ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(30),
              bottomRight: Radius.circular(30),
            ),
            child: Container(
              // White container for app bar
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),

              // Use Column to stack top row (title) and stats below
              child: SafeArea(
                bottom: false, // we only need SafeArea for top here
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
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.bold,
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
                                  backgroundColor: Colors.white.withOpacity(
                                    0.9,
                                  ),
                                  child: Icon(
                                    Icons.person,
                                    color: Colors.blueAccent,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // Text(
                                //   authService.currentUser?.displayName ??
                                //       'User',
                                //   style: TextStyle(
                                //     color: Colors.white,
                                //     fontWeight: FontWeight.w500,
                                //     fontSize: 14,
                                //   ),
                                // ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // Stats row (inside same gradient container)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: // Inside your Padding -> Row
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
                                topBoxHeight: topBox,
                                bottomBoxHeight: bottomBox,
                                bottomSingleLineFontSize: bottomSingleLineSize,
                                primaryFontSize: primarySize,
                                iconOnRight: true,
                                iconSize: 44,
                                textIconGap: 8,
                                padding: 10,
                              ),
                            ),

                            const SizedBox(width: 12),

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
                                secondaryText:
                                    "${_getUpcoming7DaysCount()} bills",
                                topBoxHeight: topBox,
                                bottomBoxHeight: bottomBox,
                                bottomSingleLineFontSize: bottomSingleLineSize,
                                primaryFontSize: primarySize,
                                iconOnRight: true,
                                iconSize: 44,
                                textIconGap: 8,
                                padding: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),

      // No need to extend body behind appBar now
      extendBodyBehindAppBar: false,
      extendBody: true,
      backgroundColor: Colors.white,
      body: SafeArea(
        minimum: const EdgeInsets.all(6),
        child: RefreshIndicator(
          onRefresh: _loadSubscriptions,
          color: Colors.white,
          backgroundColor: Colors.transparent,
          displacement: 40,
          strokeWidth: 3,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(
              top: 12,
            ), // small spacing under the card
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
                        radius: const Radius.circular(20), // rounded corners
                        thickness: 4, // thickness of the scrollbar
                        thumbVisibility: true, // always show thumb
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: _buildCategoryTabsList()),
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
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color bgColor,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: iconColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
          minimumSize: const Size(80, 70),
          padding: EdgeInsets.zero,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: iconColor),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 11,
                color: iconColor,
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

  Widget _buildCategoryTabs() {
    return SizedBox(
      height: 40,
      child: Stack(
        children: [
          // 1️⃣ Horizontal scrollable tabs
          ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: Category.defaultCategories.length + 1, // +1 for "All"
            itemBuilder: (context, index) {
              if (index == 0) {
                // "All" tab
                return Padding(
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
                );
              } else {
                final category = Category.defaultCategories[index - 1];
                return Padding(
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
                );
              }
            },
          ),

          // 2️⃣ Right scroll indicator
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 20,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.transparent,
                    Colors.grey.shade300.withOpacity(0.6),
                  ],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
            itemBuilder: (_, index) => _buildBillItem(bills[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildBillItem(Map<String, dynamic> bill) {
    final dueDate = _parseDueDate(bill);
    final now = DateTime.now();
    final isOverdue =
        dueDate != null && dueDate.isBefore(now) && bill['status'] != 'paid';
    final isPaid = bill['status'] == 'paid';
    final billIndex = _bills.indexOf(bill);

    return Dismissible(
      key: Key(bill['id'] ?? billIndex.toString()),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: HSLColor.fromAHSL(1.0, 0, 0.8, 0.8).toColor(),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _deleteBill(billIndex),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: HSLColor.fromAHSL(1.0, 236, 0.89, 0.85).toColor(),
              blurRadius: 6,
              spreadRadius: 1,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Bill header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isPaid
                          ? HSLColor.fromAHSL(1.0, 236, 0.89, 0.7).toColor()
                          : (isOverdue
                                ? HSLColor.fromAHSL(1.0, 0, 0.8, 0.85).toColor()
                                : HSLColor.fromAHSL(
                                    1.0,
                                    36,
                                    0.9,
                                    0.85,
                                  ).toColor()),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isPaid
                          ? Icons.check_circle
                          : (isOverdue ? Icons.error : Icons.access_time),
                      color: isPaid
                          ? HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor()
                          : Colors.orange,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bill['name'] ?? 'Unknown Bill',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 14,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              dueDate != null
                                  ? _formatDate(dueDate)
                                  : 'No due date',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '\$${_parseAmount(bill['amount']).toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isPaid
                          ? HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor()
                          : Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Compact actions
              Row(
                children: [
                  if (!isPaid)
                    SizedBox(
                      height: 30,
                      child: OutlinedButton.icon(
                        onPressed: () => _markAsPaid(billIndex),
                        icon: const Icon(Icons.check, size: 16),
                        label: const Text(
                          'Paid',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.green,
                          side: const BorderSide(color: Colors.green),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  if (!isPaid) const SizedBox(width: 8),
                  SizedBox(
                    height: 30,
                    child: OutlinedButton.icon(
                      onPressed: () => _showQuickEditSheet(context, bill),
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Edit', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: HSLColor.fromAHSL(
                          1.0,
                          236,
                          0.89,
                          0.65,
                        ).toColor(),
                        side: BorderSide(
                          color: HSLColor.fromAHSL(
                            1.0,
                            236,
                            0.89,
                            0.65,
                          ).toColor(),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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

  // Show bill details modal
  void _showBillDetails(BuildContext context, Map<String, dynamic> bill) {
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
                  'Bill Details',
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
            const SizedBox(height: 16),
            Text(
              bill['name'] ?? 'Unknown Bill',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Amount: \$${_parseAmount(bill['amount']).toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 16, color: Colors.black87),
            ),
            if (bill['dueDate'] != null) ...[
              const SizedBox(height: 8),
              Text(
                'Due Date: ${bill['dueDate']}',
                style: const TextStyle(fontSize: 16, color: Colors.black87),
              ),
            ],
            if (bill['category'] != null) ...[
              const SizedBox(height: 8),
              Text(
                'Category: ${bill['category']}',
                style: const TextStyle(fontSize: 16, color: Colors.black87),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      // TODO: Implement edit functionality
                    },
                    child: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      // TODO: Implement delete functionality
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewAllCard(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AllBillsScreen()), // your screen
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blueGrey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.blueGrey.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.list_alt, size: 28, color: Colors.blueGrey),
            SizedBox(height: 8),
            Text(
              "View All",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
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
            Expanded(
              child: ListView.builder(
                itemCount: frequencies.length,
                itemBuilder: (context, index) {
                  final frequency = frequencies[index];
                  return ListTile(
                    title: Text(
                      frequency,
                      style: const TextStyle(color: Colors.black),
                    ),
                    onTap: () {
                      onSelected(frequency);
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

  void _showReminderBottomSheet(
    BuildContext context,
    Function(String) onSelected,
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
                  return ListTile(
                    title: Text(
                      reminder,
                      style: const TextStyle(color: Colors.black),
                    ),
                    onTap: () {
                      onSelected(reminder);
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

  void showAddBillBottomSheet(
    BuildContext context,
    Future<void> Function(Map) _addSubscription,
  ) {
    final _formKey = GlobalKey<FormState>();
    final _nameController = TextEditingController();
    final _amountController = TextEditingController();
    final _dueDateController = TextEditingController();
    final _dueTimeController = TextEditingController();
    final _notesController = TextEditingController();

    DateTime? _selectedDate;
    TimeOfDay? _selectedTime;
    String _selectedFrequency = 'Monthly';
    String _selectedReminder = 'Same day';
    TimeOfDay _selectedNotificationTime;
    Category _selectedCategory = Category.defaultCategories[0];

    // Initialize notification time from service
    final notificationService = NotificationService();
    _selectedNotificationTime = const TimeOfDay(
      hour: 9,
      minute: 0,
    ); // Fallback default
    notificationService.getDefaultNotificationTime().then((time) {
      _selectedNotificationTime = time;
    });

    // Comprehensive mapping of category name -> common bill types and sub-categories
    final Map<String, List<String>> predefinedBills = {
      'Subscription': [
        'Netflix',
        'Spotify',
        'YouTube Premium',
        'Amazon Prime',
        'Disney+',
        'Apple Music',
        'Hulu',
        'HBO Max',
        'Other',
      ],
      'Rent': [
        'House Rent',
        'Apartment Rent',
        'Office Rent',
        'Shop Rent',
        'Warehouse Rent',
        'Storage Rent',
        'Parking Rent',
        'Other',
      ],
      'Internet': [
        'Home Internet',
        'Mobile Internet',
        'Office Internet',
        'WiFi Hotspot',
        'Broadband',
        'Fiber Optic',
        'Other',
      ],
      'Education': [
        'School Fees',
        'College Tuition',
        'Online Courses',
        'Books & Supplies',
        'Student Loans',
        'Certification Programs',
        'Tutoring',
        'Other',
      ],
      'Utilities': [
        'Water Bill',
        'Electricity Bill',
        'Gas Bill',
        'Trash Collection',
        'Sewage Bill',
        'Property Tax',
        'Maintenance Fees',
        'Other',
      ],
      'Insurance': [
        'Health Insurance',
        'Car Insurance',
        'Home Insurance',
        'Life Insurance',
        'Travel Insurance',
        'Phone Insurance',
        'Pet Insurance',
        'Other',
      ],
      'Transport': [
        'Car Payment',
        'Fuel',
        'Public Transport',
        'Ride Sharing',
        'Parking Fees',
        'Toll Fees',
        'Vehicle Maintenance',
        'Other',
      ],
      'Entertainment': [
        'Movie Tickets',
        'Concerts',
        'Theater',
        'Gaming Subscriptions',
        'Streaming Services',
        'Books & Magazines',
        'Hobbies',
        'Other',
      ],
      'Food & Dining': [
        'Groceries',
        'Restaurants',
        'Food Delivery',
        'Coffee Shops',
        'Fast Food',
        'Meal Kits',
        'Office Lunch',
        'Other',
      ],
      'Shopping': [
        'Clothing',
        'Electronics',
        'Home Goods',
        'Beauty Products',
        'Sports Equipment',
        'Furniture',
        'Online Shopping',
        'Other',
      ],
      'Health': [
        'Doctor Visits',
        'Medication',
        'Dental Care',
        'Eye Care',
        'Gym Membership',
        'Therapy',
        'Medical Tests',
        'Other',
      ],
      'Fitness': [
        'Gym Membership',
        'Personal Trainer',
        'Yoga Classes',
        'Pilates',
        'Sports Club',
        'Fitness App',
        'Equipment',
        'Other',
      ],
    };

    // Helper to show a simple choice sheet and return the selected value.
    Future<T?> _showChoiceSheet<T>(
      BuildContext ctx, {
      required String title,
      required List<T> options,
      required String Function(T) label,
    }) {
      return showModalBottomSheet<T>(
        context: ctx,
        backgroundColor: Colors.transparent,
        builder: (c) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                ...options.map((opt) {
                  final idx = options.indexOf(opt);
                  return ListTile(
                    title: Text(label(opt)),
                    onTap: () => Navigator.of(c).pop(opt),
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    }

    // Show category picker. If category has predefined bills, show bills list next.
    Future<void> _showCategoryThenBillsPicker(
      BuildContext ctx,
      StateSetter setState,
    ) async {
      final Category? pickedCategory = await showModalBottomSheet<Category>(
        context: ctx,
        backgroundColor: Colors.transparent,
        builder: (c) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6.0),
                  child: Text(
                    'Choose Category',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 1.1,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount:
                        Category.defaultCategories.length + 1, // +1 for Other
                    itemBuilder: (context, index) {
                      if (index == Category.defaultCategories.length) {
                        return GestureDetector(
                          onTap: () {
                            Navigator.of(c).pop(null);
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Center(child: Text('Other')),
                          ),
                        );
                      }
                      final cat = Category.defaultCategories[index];
                      return GestureDetector(
                        onTap: () {
                          Navigator.of(c).pop(cat);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey.shade50,
                          ),
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: cat.backgroundColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  cat.icon,
                                  color: cat.color,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                cat.name,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // If user chose Other (pickedCategory == null), show custom category input
      if (pickedCategory == null) {
        final Map<String, dynamic>? customBillData =
            await showModalBottomSheet<Map<String, dynamic>>(
              context: ctx,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              builder: (c) {
                final _nameController = TextEditingController();
                final _customCategoryController = TextEditingController();
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(c).viewInsets.bottom,
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(18),
                      ),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const Text(
                          'Add Custom Bill',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Bill Name',
                            hintText: 'e.g., My Custom Bill',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter bill name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _customCategoryController,
                          decoration: const InputDecoration(
                            labelText: 'Category Name',
                            hintText: 'e.g., Other',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter category name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(c).pop(null),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  if (_nameController.text.trim().isNotEmpty &&
                                      _customCategoryController.text
                                          .trim()
                                          .isNotEmpty) {
                                    Navigator.of(c).pop({
                                      'name': _nameController.text.trim(),
                                      'category': _customCategoryController.text
                                          .trim(),
                                    });
                                  }
                                },
                                child: const Text('Next'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );

        if (customBillData != null) {
          setState(() {
            _nameController.text = customBillData['name'];
            _selectedCategory = Category.defaultCategories.firstWhere(
              (cat) => cat.id == 'other',
              orElse: () => Category.defaultCategories[0],
            );
          });
        }

        return;
      }

      // If a category was picked, check for predefined bills for that category
      final bills = predefinedBills[pickedCategory.name];

      if (bills != null && bills.isNotEmpty) {
        final String? pickedBill = await showModalBottomSheet<String>(
          context: ctx,
          backgroundColor: Colors.transparent,
          builder: (c) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
            ),
            padding: const EdgeInsets.all(12),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Text(
                      'Select ${pickedCategory.name} Type',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...bills
                      .map(
                        (b) => ListTile(
                          title: Text(b),
                          onTap: () => Navigator.of(c).pop(b),
                        ),
                      )
                      .toList(),
                ],
              ),
            ),
          ),
        );

        if (pickedBill != null) {
          if (pickedBill == 'Other') {
            // Quick-add for custom bill name under the chosen category
            final String? manualName = await showModalBottomSheet<String>(
              context: ctx,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              builder: (c) {
                final _quickController = TextEditingController();
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(c).viewInsets.bottom,
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(18),
                      ),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        Text(
                          'Add custom bill under ${pickedCategory.name}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _quickController,
                          decoration: const InputDecoration(
                            hintText: 'e.g., Local Water Board',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(c).pop(null),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => Navigator.of(c).pop(
                                  _quickController.text.trim().isEmpty
                                      ? null
                                      : _quickController.text.trim(),
                                ),
                                child: const Text('Add'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );

            if (manualName != null && manualName.isNotEmpty) {
              setState(() {
                _selectedCategory = pickedCategory;
                _nameController.text = manualName;
              });
            }
          } else {
            // User picked a predefined bill name
            setState(() {
              _selectedCategory = pickedCategory;
              _nameController.text = pickedBill;
            });
          }
        }
      } else {
        // Category has no predefined bills — just set category and let user type name if needed
        setState(() {
          _selectedCategory = pickedCategory;
        });
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 20.0,
                    right: 20.0,
                    top: 12.0,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 12.0,
                  ),
                  child: StatefulBuilder(
                    builder: (BuildContext context, StateSetter setState) {
                      return Column(
                        children: [
                          // Grab handle
                          Container(
                            width: 44,
                            height: 5,
                            margin: const EdgeInsets.only(top: 6, bottom: 14),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),

                          // Title
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: kPrimaryColor.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.add,
                                  color: kPrimaryColor,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Add bill',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Quickly add a subscription',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          // Form area
                          Expanded(
                            child: SingleChildScrollView(
                              controller: scrollController,
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Bill Details Card (name now opens category-first picker)
                                    Card(
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      color: Colors.grey.shade50,
                                      child: Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Column(
                                          children: [
                                            // Name field (readOnly) — tapping opens category/bill picker
                                            TextFormField(
                                              controller: _nameController,
                                              readOnly: true,
                                              onTap: () async {
                                                await _showCategoryThenBillsPicker(
                                                  context,
                                                  setState,
                                                );
                                              },
                                              decoration: InputDecoration(
                                                hintText:
                                                    'Tap to choose category & bill (or add custom)',
                                                prefixIcon: const Icon(
                                                  Icons.subscriptions,
                                                ),
                                                suffixIcon:
                                                    _selectedCategory != null
                                                    ? Container(
                                                        margin:
                                                            const EdgeInsets.only(
                                                              right: 8,
                                                            ),
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 4,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: _selectedCategory
                                                              .backgroundColor,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Icon(
                                                              _selectedCategory
                                                                  .icon,
                                                              size: 14,
                                                              color:
                                                                  _selectedCategory
                                                                      .color,
                                                            ),
                                                            const SizedBox(
                                                              width: 6,
                                                            ),
                                                            Text(
                                                              _selectedCategory
                                                                  .name,
                                                              style:
                                                                  const TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                  ),
                                                            ),
                                                          ],
                                                        ),
                                                      )
                                                    : null,
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  borderSide: BorderSide.none,
                                                ),
                                                filled: true,
                                                fillColor: Colors.white,
                                              ),
                                              validator: (v) =>
                                                  (v == null || v.isEmpty)
                                                  ? 'Please choose or enter a bill name'
                                                  : null,
                                            ),

                                            const SizedBox(height: 10),

                                            // Amount
                                            TextFormField(
                                              controller: _amountController,
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                              decoration: InputDecoration(
                                                hintText:
                                                    'Amount (e.g., 15.99)',
                                                prefixIcon: const Icon(
                                                  Icons.attach_money,
                                                ),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  borderSide: BorderSide.none,
                                                ),
                                                filled: true,
                                                fillColor: Colors.white,
                                              ),
                                              validator: (v) {
                                                if (v == null || v.isEmpty)
                                                  return 'Please enter amount';
                                                if (double.tryParse(v) == null)
                                                  return 'Please enter a valid amount';
                                                return null;
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 12),

                                    // Schedule row
                                    Row(
                                      children: [
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () async {
                                              final DateTime? picked =
                                                  await showDatePicker(
                                                    context: context,
                                                    initialDate:
                                                        _selectedDate ??
                                                        DateTime.now().add(
                                                          const Duration(
                                                            days: 1,
                                                          ),
                                                        ),
                                                    firstDate: DateTime.now(),
                                                    lastDate: DateTime(2100),
                                                  );
                                              if (picked != null) {
                                                setState(() {
                                                  _selectedDate = DateTime(
                                                    picked.year,
                                                    picked.month,
                                                    picked.day,
                                                    _selectedTime?.hour ?? 9,
                                                    _selectedTime?.minute ?? 0,
                                                  );
                                                  _dueDateController.text =
                                                      '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
                                                });
                                              }
                                            },
                                            child: AbsorbPointer(
                                              child: TextFormField(
                                                controller: _dueDateController,
                                                decoration: InputDecoration(
                                                  labelText: 'Due Date',
                                                  prefixIcon: const Icon(
                                                    Icons.calendar_today,
                                                  ),
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                  filled: true,
                                                  fillColor: Colors.white,
                                                ),
                                                validator: (v) =>
                                                    (v == null || v.isEmpty)
                                                    ? 'Please select due date'
                                                    : null,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: GestureDetector(
                                            onTap: () async {
                                              final TimeOfDay? picked =
                                                  await showTimePicker(
                                                    context: context,
                                                    initialTime:
                                                        _selectedTime ??
                                                        const TimeOfDay(
                                                          hour: 9,
                                                          minute: 0,
                                                        ),
                                                  );
                                              if (picked != null) {
                                                setState(() {
                                                  _selectedTime = picked;
                                                  _dueTimeController.text =
                                                      picked.format(context);
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
                                            child: AbsorbPointer(
                                              child: TextFormField(
                                                controller: _dueTimeController,
                                                decoration: InputDecoration(
                                                  labelText: 'Due Time',
                                                  prefixIcon: const Icon(
                                                    Icons.access_time,
                                                  ),
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                  filled: true,
                                                  fillColor: Colors.white,
                                                ),
                                                validator: (v) =>
                                                    (v == null || v.isEmpty)
                                                    ? 'Please select due time'
                                                    : null,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 12),

                                    // Frequency / Reminder
                                    Row(
                                      children: [
                                        Expanded(
                                          child: InkWell(
                                            onTap: () async {
                                              final choice =
                                                  await _showChoiceSheet<
                                                    String
                                                  >(
                                                    context,
                                                    title: 'Frequency',
                                                    options: [
                                                      'Daily',
                                                      'Weekly',
                                                      'Monthly',
                                                      'Yearly',
                                                    ],
                                                    label: (s) => s,
                                                  );
                                              if (choice != null)
                                                setState(
                                                  () => _selectedFrequency =
                                                      choice,
                                                );
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                color: Colors.grey.shade50,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Frequency',
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.bodySmall,
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Text(
                                                        _selectedFrequency,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                      const Icon(
                                                        Icons
                                                            .keyboard_arrow_down,
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: InkWell(
                                            onTap: () async {
                                              final choice =
                                                  await _showChoiceSheet<
                                                    String
                                                  >(
                                                    context,
                                                    title: 'Reminder',
                                                    options: [
                                                      'Same day',
                                                      '1 day before',
                                                      '3 days before',
                                                      '1 week before',
                                                    ],
                                                    label: (s) => s,
                                                  );
                                              if (choice != null)
                                                setState(
                                                  () => _selectedReminder =
                                                      choice,
                                                );
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                color: Colors.grey.shade50,
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Reminder',
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.bodySmall,
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Text(
                                                        _selectedReminder,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                      const Icon(
                                                        Icons
                                                            .keyboard_arrow_down,
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 12),

                                    // Notification Time
                                    InkWell(
                                      onTap: () async {
                                        final TimeOfDay?
                                        pickedTime = await showTimePicker(
                                          context: context,
                                          initialTime:
                                              _selectedNotificationTime,
                                          builder:
                                              (
                                                BuildContext context,
                                                Widget? child,
                                              ) {
                                                return Theme(
                                                  data: ThemeData.light().copyWith(
                                                    timePickerTheme:
                                                        TimePickerThemeData(
                                                          backgroundColor:
                                                              Colors.white,
                                                          hourMinuteColor:
                                                              kPrimaryColor
                                                                  .withOpacity(
                                                                    0.1,
                                                                  ),
                                                          hourMinuteTextColor:
                                                              kPrimaryColor,
                                                          dialHandColor:
                                                              kPrimaryColor,
                                                          dialTextColor:
                                                              Colors.black87,
                                                        ),
                                                  ),
                                                  child: child!,
                                                );
                                              },
                                        );
                                        if (pickedTime != null) {
                                          setState(() {
                                            _selectedNotificationTime =
                                                pickedTime;
                                          });
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          color: Colors.grey.shade50,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Notification Time',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  _selectedNotificationTime
                                                      .format(context),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const Icon(
                                                  Icons.access_time,
                                                  size: 18,
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 12),

                                    // Notes
                                    TextFormField(
                                      controller: _notesController,
                                      maxLines: 3,
                                      decoration: InputDecoration(
                                        hintText: 'Notes (optional)',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                        filled: true,
                                        fillColor: Colors.white,
                                      ),
                                    ),

                                    const SizedBox(height: 18),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Sticky actions
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            color: Colors.white,
                            child: Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => Navigator.pop(context),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text('Cancel'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () async {
                                      if (_formKey.currentState!.validate()) {
                                        if (_selectedTime == null) {
                                          _selectedTime = const TimeOfDay(
                                            hour: 9,
                                            minute: 0,
                                          );
                                          _dueTimeController.text =
                                              _selectedTime!.format(context);
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

                                        // Generate a unique ID for this bill
                                        final billId = DateTime.now()
                                            .millisecondsSinceEpoch
                                            .toString();

                                        final subscription = {
                                          'id': billId,
                                          'name': _nameController.text,
                                          'amount': _amountController.text,
                                          'dueDate': _dueDateController.text,
                                          'dueTime': _dueTimeController.text,
                                          'dueDateTime': _selectedDate
                                              ?.toIso8601String(),
                                          'frequency': _selectedFrequency,
                                          'reminder': _selectedReminder,
                                          'notificationTime':
                                              '${_selectedNotificationTime.hour}:${_selectedNotificationTime.minute}',
                                          'category': _selectedCategory.id,
                                          'categoryName':
                                              _selectedCategory.name,
                                          'categoryColor': _selectedCategory
                                              .color
                                              .toARGB32(),
                                          'categoryBackgroundColor':
                                              _selectedCategory.backgroundColor
                                                  .toARGB32(),
                                          'notes': _notesController.text.isEmpty
                                              ? null
                                              : _notesController.text,
                                        };

                                        await _addSubscription(subscription);

                                        // Schedule notification
                                        if (_selectedDate != null) {
                                          final notificationService =
                                              NotificationService();
                                          await notificationService
                                              .scheduleBillReminder(
                                                id: DateTime.now()
                                                    .millisecondsSinceEpoch,
                                                title:
                                                    'Bill Due: ${_nameController.text}',
                                                body:
                                                    'Your bill for ${_amountController.text} is due ${_selectedReminder.toLowerCase()}',
                                                dueDate: _selectedDate!,
                                                reminderPreference:
                                                    _selectedReminder,
                                                customNotificationTime:
                                                    _selectedTime,
                                                payload: billId,
                                              );

                                          // Store notification ID with the bill for later cancellation
                                          subscription['notificationId'] =
                                              DateTime.now()
                                                  .millisecondsSinceEpoch;
                                        }
                                        if (Navigator.canPop(context))
                                          Navigator.pop(context);
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text('Add Subscription'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
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

  Future<void> _syncWithFirebase() async {
    if (!mounted) return;

    await _checkConnectivity();

    if (_isOnline) {
      try {
        final success = await _subscriptionService.syncLocalToFirebase();
        await _loadSubscriptions();

        if (mounted) {
          setState(() {});

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success ? 'Synced successfully!' : 'Some items failed to sync',
              ),
              backgroundColor: success ? Colors.green : Colors.orange,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sync failed: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No internet connection. Please try again when online.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }
}
