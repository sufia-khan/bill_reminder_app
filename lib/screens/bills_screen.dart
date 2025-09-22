import 'package:flutter/material.dart';
import 'package:projeckt_k/services/date_format_service.dart';
import 'package:projeckt_k/widgets/bill_item_widget.dart';
import 'package:projeckt_k/services/dialog_service.dart';

class BillsScreen extends StatefulWidget {
  const BillsScreen({Key? key}) : super(key: key);

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  List<Map<String, dynamic>> _bills = [];
  bool _isLoading = true;
  String _selectedFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadBills();
  }

  Future<void> _loadBills() async {
    setState(() {
      _isLoading = true;
    });

    // Simulate loading bills
    await Future.delayed(const Duration(seconds: 1));

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
          'reminder': '3 days before'
        },
        {
          'id': '2',
          'name': 'Internet Bill',
          'amount': '59.99',
          'dueDate': '2024-01-20',
          'status': 'upcoming',
          'category': 'utilities',
          'frequency': 'monthly',
          'reminder': '2 days before'
        },
        {
          'id': '3',
          'name': 'Netflix Subscription',
          'amount': '15.99',
          'dueDate': '2024-01-25',
          'status': 'upcoming',
          'category': 'entertainment',
          'frequency': 'monthly',
          'reminder': '1 day before'
        },
        {
          'id': '4',
          'name': 'Water Bill',
          'amount': '45.00',
          'dueDate': '2024-01-10',
          'status': 'overdue',
          'category': 'utilities',
          'frequency': 'monthly',
          'reminder': '5 days before'
        },
      ];
      _isLoading = false;
    });
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
    DialogService.showDeleteConfirmDialog(context, bill).then((confirmed) {
      if (confirmed == true) {
        setState(() {
          _bills.removeWhere((b) => b['id'] == bill['id']);
        });
        DialogService.showSnackBar(context, 'Bill deleted successfully');
      }
    });
  }

  void _markAsPaid(Map<String, dynamic> bill) {
    final billName = bill['name'] ?? 'this bill';
    DialogService.showMarkAsPaidConfirmDialog(context, billName).then((confirmed) {
      if (confirmed == true) {
        setState(() {
          bill['status'] = 'paid';
        });
        DialogService.showSnackBar(context, 'Bill marked as paid');
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