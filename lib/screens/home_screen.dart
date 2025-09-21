import 'dart:async';
import 'package:flutter/material.dart';
import 'package:projeckt_k/screens/all_bills_screen.dart';
import 'package:projeckt_k/screens/profile_screen.dart';
import 'package:projeckt_k/services/auth_service.dart';
import 'package:projeckt_k/services/subscription_service.dart';
import 'package:projeckt_k/models/category_model.dart';
import 'package:projeckt_k/widgets/subtitle_changing.dart';

final Color kPrimaryColor = HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor();
final Color bgUpcomingMuted = HSLColor.fromAHSL(
  1.0, // alpha (100%)
  45.0, // hue
  0.93, // saturation (93%)
  0.95, // lightness (95%)
).toColor();

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _bills = [];
  final SubscriptionService _subscriptionService = SubscriptionService();
  bool _isLoading = false;
  bool _hasError = false;
  bool _isOnline = false;
  StreamSubscription<bool>? _connectivitySubscription;
  Timer? _updateTimer;

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
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _updateTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    final isOnline = await _subscriptionService.isOnline();
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
        }
      } catch (e) {
        debugPrint('Error checking overdue bill: $e');
      }
    }

    if (needsUpdate && mounted) {
      setState(() {});
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
                              Icons.subscriptions,
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

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(75.0), // ⬅️ taller AppBar
        child: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: kPrimaryColor,
          titleSpacing: 16,
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: Colors.deepOrange,
                  size: 25,
                ),
              ),
              const SizedBox(width: 10),

              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SubManager',
                    style: TextStyle(
                      color: kPrimaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                    ),
                  ),
                  ChangingSubtitle(), // 👈 rotating subtitle
                ],
              ),
            ],
          ),
          actions: [
            Builder(
              builder: (context) {
                final user = authService.currentUser;
                final userName = user?.displayName ?? 'User';
                return Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProfileScreen(),
                        ),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            userName,
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 8),
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: kPrimaryColor.withOpacity(0.1),
                          child: Icon(
                            Icons.person,
                            color: kPrimaryColor,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),

      body: RefreshIndicator(
        onRefresh: _loadSubscriptions,
        color: kPrimaryColor,
        backgroundColor: Colors.white,
        displacement: 40,
        strokeWidth: 3,
        child: Container(
          color: Colors.white,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(), // 👈 important
            children: [
              // Total Bills Card
              Padding(
                padding: const EdgeInsets.only(
                  top: 4.0,
                  right: 16.0,
                  left: 16.0,
                  bottom: 12.0,
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      // 👈 fixed spelling here
                      BoxShadow(
                        color: kPrimaryColor.withOpacity(0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),

                  child: SizedBox(
                    height: 135,
                    child: Center(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Bills This Month',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '\$${_calculateMonthlyTotal().toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                _calculateMonthlyDifference() > 0
                                    ? Icons.arrow_upward
                                    : Icons.arrow_downward,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '\$${_calculateMonthlyDifference().abs().toStringAsFixed(2)} ${_calculateMonthlyDifference() > 0 ? 'more' : 'less'} than last month',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
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

              // Four Cards Grid
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: GridView.count(
                  physics:
                      const NeverScrollableScrollPhysics(), // 👈 grid won't scroll separately
                  shrinkWrap: true, // 👈 so it fits inside ListView
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.2,
                  children: [
                    _buildAnimatedStatCard(
                      'Upcoming',
                      '${_getUpcomingCount()}',
                      '\$${_getUpcomingAmount().toStringAsFixed(2)}',
                      bgUpcomingMuted,
                      Icons.calendar_month,
                      const Color(0xFFD4A017),
                    ),
                    _buildAnimatedStatCard(
                      'Paid',
                      '${_getPaidCount()}',
                      '\$${_getPaidAmount().toStringAsFixed(2)}',
                      const Color(0xFFE8F5E9),
                      Icons.payments_rounded,
                      const Color(0xFF2E7D32),
                    ),
                    _buildAnimatedStatCard(
                      'Overdue',
                      '${_getOverdueCount()}',
                      '\$${_getOverdueAmount().toStringAsFixed(2)}',
                      const Color(0xFFFFEBEE),
                      Icons.hourglass_top_rounded,
                      const Color(0xFFC62828),
                    ),
                    _buildViewAllCard(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showAddBillBottomSheet(context);
        },
        backgroundColor: kPrimaryColor,
        elevation: 4,
        child: const Icon(Icons.add, color: Colors.white, size: 18),
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

  void _showAddBillBottomSheet(BuildContext context) {
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
    Category _selectedCategory = Category.defaultCategories[0];

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
                              color: kPrimaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.add,
                              color: kPrimaryColor,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Add bill',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: kPrimaryColor,
                                  fontSize: 16,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: _nameController,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          labelText: 'bill Name',
                          hintText: 'e.g., Netflix, Spotify',
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
                              Icons.subscriptions,
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
                                  // Ensure we have a time set (default to 9:00 AM if not selected)
                                  if (_selectedTime == null) {
                                    _selectedTime = const TimeOfDay(
                                      hour: 9,
                                      minute: 0,
                                    );
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

                                  final subscription = {
                                    'name': _nameController.text,
                                    'amount': _amountController.text,
                                    'dueDate': _dueDateController.text,
                                    'dueTime': _dueTimeController.text,
                                    'dueDateTime': _selectedDate
                                        ?.toIso8601String(),
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
                                  await _addSubscription(subscription);
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
                              child: const Text(
                                'Add Subscription',
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

  Future<void> _addSubscription(Map<String, dynamic> subscription) async {
    try {
      // Try to add to Firebase first
      await _subscriptionService.addSubscription(subscription);

      // If successful, add to local list
      if (mounted) {
        setState(() {
          _bills.add(subscription);
          _checkForOverdueBills(); // Immediate check for overdue status
        });
      }
    } catch (e) {
      // If Firebase fails, add to local list only (will sync later)
      if (mounted) {
        setState(() {
          _bills.add(subscription);
          _checkForOverdueBills(); // Immediate check for overdue status
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved locally. Will sync when online.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _deleteSubscription(int index) async {
    final subscription = _bills[index];

    try {
      // Try to delete from Firebase
      if (subscription['firebaseId'] != null) {
        await _subscriptionService.deleteSubscription(
          subscription['firebaseId'],
        );
      } else if (subscription['localId'] != null) {
        await _subscriptionService.deleteSubscription(subscription['localId']);
      }

      // Refresh the list
      await _loadSubscriptions();
    } catch (e) {
      // If Firebase fails, just remove from local list
      if (mounted) {
        setState(() {
          _bills.removeAt(index);
        });
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
