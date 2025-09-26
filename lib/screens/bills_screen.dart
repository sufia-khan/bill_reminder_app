import 'package:flutter/material.dart';
import 'package:projeckt_k/screens/add_bill_screen.dart';
import 'package:projeckt_k/services/date_format_service.dart';
import 'package:projeckt_k/widgets/bill_item_widget.dart';
import 'package:projeckt_k/services/dialog_service.dart';
import 'package:projeckt_k/services/subscription_service.dart';
import 'package:projeckt_k/services/bill_service.dart';
import 'package:projeckt_k/services/bill_operations_service.dart';

class BillsScreen extends StatefulWidget {
  const BillsScreen({Key? key}) : super(key: key);

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  List<Map<String, dynamic>> _bills = [];
  bool _isLoading = true;
  String _selectedFilter = 'all';
  final SubscriptionService _subscriptionService = SubscriptionService();
  BillOperationsService? _billOperationsService;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    await _subscriptionService.init();
    final billService = BillService(_bills);
    setState(() {
      _billOperationsService = BillOperationsService(billService, context);
    });
    _loadBills();
  }

  Future<void> _loadBills() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final subscriptions = await _subscriptionService.getSubscriptions();
      setState(() {
        _bills = subscriptions.map((sub) => {
          'id': sub['id'] ?? sub['firebaseId'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
          'name': sub['name'] ?? 'Unknown Bill',
          'amount': sub['amount']?.toString() ?? '0.00',
          'dueDate': sub['dueDate'] ?? DateTime.now().toIso8601String(),
          'status': sub['status'] ?? 'upcoming',
          'category': sub['category'] ?? 'other',
          'frequency': sub['frequency'] ?? 'monthly',
          'reminder': sub['reminder'] ?? 'same day',
          'index': _bills.length,
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      // Fallback to mock data if Firebase fails
      setState(() {
        _bills = [
          {
            'id': '1',
            'name': 'Electricity Bill',
            'amount': '120.00',
            'dueDate': '2024-01-15',
            'status': 'paid',
            'category': 'utilities',
            'frequency': 'monthly',
            'reminder': '3 days before',
            'index': 0,
          },
          {
            'id': '2',
            'name': 'Internet Bill',
            'amount': '59.99',
            'dueDate': '2024-01-20',
            'status': 'upcoming',
            'category': 'utilities',
            'frequency': 'monthly',
            'reminder': '2 days before',
            'index': 1,
          },
          {
            'id': '3',
            'name': 'Netflix Subscription',
            'amount': '15.99',
            'dueDate': '2024-01-25',
            'status': 'upcoming',
            'category': 'entertainment',
            'frequency': 'monthly',
            'reminder': '1 day before',
            'index': 2,
          },
          {
            'id': '4',
            'name': 'Water Bill',
            'amount': '45.00',
            'dueDate': '2024-01-10',
            'status': 'overdue',
            'category': 'utilities',
            'frequency': 'monthly',
            'reminder': '5 days before',
            'index': 3,
          },
        ];
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredBills {
    if (_selectedFilter == 'all') return _bills;
    return _bills.where((bill) => bill['status'] == _selectedFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadBills,
              child: Column(
                children: [
                  _buildHeader(),
                  _buildFilterChips(),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _buildBillsList(),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddBillScreen(),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade600, Colors.blue.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'My Bills',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_bills.length} total bills',
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddBillScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddBillScreen(),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          spacing: 8,
          children: [
            _buildFilterChip('All', 'all'),
            _buildFilterChip('Upcoming', 'upcoming'),
            _buildFilterChip('Paid', 'paid'),
            _buildFilterChip('Overdue', 'overdue'),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = selected ? value : 'all';
        });
      },
      backgroundColor: Colors.grey.shade200,
      selectedColor: Colors.blue.shade100,
      checkmarkColor: Colors.blue.shade600,
    );
  }

  Widget _buildBillsList() {
    if (_filteredBills.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No bills found',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _filteredBills.length,
      itemBuilder: (context, index) {
        final bill = _filteredBills[index];
        return BillItemWidget(
          bill: bill,
          onMarkAsPaid: (index) => _markAsPaid(bill),
          onDelete: (index) => _deleteBill(bill),
          onEdit: (bill) => _showEditBillDialog(bill),
          onShowDetails: (bill) => _showBillDetails(bill),
        );
      },
    );
  }

  void _showBillDetails(Map<String, dynamic> bill) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(bill['name']),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Amount', '\$${bill['amount']}'),
            _buildDetailRow('Due Date', DateFormatService.formatDate(bill['dueDate'])),
            _buildDetailRow('Status', bill['status'].toString().toUpperCase()),
            _buildDetailRow('Category', bill['category'].toString().toUpperCase()),
            _buildDetailRow('Frequency', bill['frequency'].toString().toUpperCase()),
            _buildDetailRow('Reminder', bill['reminder']),
          ],
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

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label:',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  void _deleteBill(Map<String, dynamic> bill) {
    final billName = bill['name'] ?? 'this bill';
    final String billId = bill['id'] ?? '';

    if (billId.isEmpty) {
      DialogService.showErrorSnackBar(context, 'Bill ID is missing');
      return;
    }

    DialogService.showDeleteConfirmDialog(context, bill).then((confirmed) async {
      if (confirmed == true) {
        // Show loading state
        setState(() {
          bill['_isDeleting'] = true;
        });

        try {
          // Remove from list first for immediate UI feedback
          setState(() {
            _bills.removeWhere((b) => b['id'] == billId);
          });

          // Delete from Firebase/local storage
          await _subscriptionService.deleteSubscription(billId);

          DialogService.showSuccessSnackBar(context, '$billName deleted successfully');

        } catch (e) {
          // Revert on error
          setState(() {
            bill['_isDeleting'] = false;
            _loadBills(); // Reload to restore the bill
          });
          DialogService.showErrorSnackBar(context, 'Failed to delete bill. Please try again.');
        }
      }
    });
  }

  void _markAsPaid(Map<String, dynamic> bill) {
    final billName = bill['name'] ?? 'this bill';
    final String billId = bill['id'] ?? '';

    if (billId.isEmpty) {
      DialogService.showErrorSnackBar(context, 'Bill ID is missing');
      return;
    }

    DialogService.showMarkAsPaidConfirmDialog(context, billName).then((confirmed) async {
      if (confirmed == true) {
        // Show loading state
        setState(() {
          bill['_isUpdating'] = true;
        });

        try {
          // Update locally first for immediate UI feedback
          setState(() {
            bill['status'] = 'paid';
            bill['_isUpdating'] = false;
          });

          // Update in Firebase/local storage
          final updatedBill = Map<String, dynamic>.from(bill);
          updatedBill.remove('_isUpdating');
          updatedBill['status'] = 'paid';

          await _subscriptionService.updateSubscription(billId, updatedBill);

          DialogService.showSuccessSnackBar(context, '$billName marked as paid!');

        } catch (e) {
          // Revert on error
          setState(() {
            bill['status'] = bill['originalStatus'] ?? 'upcoming';
            bill['_isUpdating'] = false;
          });
          DialogService.showErrorSnackBar(context, 'Failed to mark as paid. Please try again.');
        }
      }
    });
  }

  void _showEditBillDialog(Map<String, dynamic> bill) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit ${bill['name']}'),
        content: const Text('Edit functionality would be implemented here.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}