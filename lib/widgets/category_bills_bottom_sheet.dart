import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:projeckt_k/models/category_model.dart';
import 'package:projeckt_k/services/subscription_service.dart';

class CategoryBillsBottomSheet extends StatefulWidget {
  final Category category;
  final SubscriptionService subscriptionService;
  final VoidCallback onBillAdded;

  const CategoryBillsBottomSheet({
    Key? key,
    required this.category,
    required this.subscriptionService,
    required this.onBillAdded,
  }) : super(key: key);

  @override
  State<CategoryBillsBottomSheet> createState() => _CategoryBillsBottomSheetState();
}

class _CategoryBillsBottomSheetState extends State<CategoryBillsBottomSheet> {
  List<Map<String, dynamic>> _bills = [];
  List<Map<String, dynamic>> _filteredBills = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _selectedStatus = 'all';

  @override
  void initState() {
    super.initState();
    debugPrint('🚀 CategoryBillsBottomSheet initialized for category: ${widget.category.name} (ID: ${widget.category.id})');
    _loadBills();
  }

  Future<void> _loadBills() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      // Load from local storage first for immediate display
      final localBills = await widget.subscriptionService.getLocalSubscriptions();

      debugPrint('🔍 Debug: Category ID: ${widget.category.id}');
      debugPrint('🔍 Debug: Local bills count: ${localBills.length}');
      for (var bill in localBills) {
        debugPrint('🔍 Debug: Bill category: ${bill['category']} - Bill name: ${bill['name']}');
      }

      final categoryBills = localBills
          .where((bill) {
            final billCategory = bill['category']?.toString();
            // Try multiple matching strategies
            final exactMatch = billCategory == widget.category.id;
            final containsMatch = billCategory?.contains(widget.category.id) ?? false;
            final caseInsensitiveMatch = billCategory?.toLowerCase() == widget.category.id.toLowerCase();
            final matches = exactMatch || containsMatch || caseInsensitiveMatch;

            debugPrint('🔍 Debug: Checking bill "${bill['name']}" - category: $billCategory vs ${widget.category.id} - matches: $matches');
            return matches;
          })
          .toList();

      setState(() {
        _bills = categoryBills;
        _filterBills(); // Apply status filtering
        _isLoading = false;
      });

      debugPrint('📱 Loaded ${_bills.length} bills for category: ${widget.category.name}');
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
      debugPrint('❌ Failed to load bills: $e');
    }
  }

  void _filterBills() {
    final now = DateTime.now();
    final filtered = <Map<String, dynamic>>[];

    for (var bill in _bills) {
      try {
        final dueDate = _parseDueDate(bill);
        final billStatus = bill['status']?.toString() ?? '';
        bool matchesStatus = false;

        switch (_selectedStatus) {
          case 'all':
            matchesStatus = true;
            break;
          case 'upcoming':
            matchesStatus = billStatus != 'paid' &&
                           dueDate != null &&
                           dueDate.isAfter(now) &&
                           dueDate.isBefore(now.add(const Duration(days: 30)));
            break;
          case 'overdue':
            matchesStatus = billStatus != 'paid' &&
                           dueDate != null &&
                           dueDate.isBefore(now);
            break;
          case 'paid':
            matchesStatus = billStatus == 'paid';
            break;
        }

        if (matchesStatus) {
          filtered.add(bill);
        }
      } catch (e) {
        debugPrint('Error filtering bill: $e');
      }
    }

    setState(() {
      _filteredBills = filtered;
    });
  }

  DateTime? _parseDueDate(Map<String, dynamic> bill) {
    try {
      if (bill['dueDate'] != null) {
        if (bill['dueDate'] is DateTime) {
          return bill['dueDate'] as DateTime;
        } else if (bill['dueDate'] is Timestamp) {
          return (bill['dueDate'] as Timestamp).toDate();
        } else if (bill['dueDate'] is String) {
          return DateTime.parse(bill['dueDate']);
        }
      }
    } catch (e) {
      debugPrint('Error parsing due date: $e');
    }
    return null;
  }

  Widget _buildBillItem(Map<String, dynamic> bill, BuildContext context) {
    final dueDate = _parseDueDate(bill);
    final now = DateTime.now();
    final isOverdue = dueDate != null && dueDate.isBefore(now) && bill['status'] != 'paid';
    final isPaid = bill['status'] == 'paid';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(
          bill['name'] ?? 'Unnamed Bill',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 14,
                  color: isOverdue ? Colors.red : Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Text(
                  dueDate != null
                      ? '${dueDate.day}/${dueDate.month}/${dueDate.year}'
                      : 'No due date',
                  style: TextStyle(
                    fontSize: 14,
                    color: isOverdue ? Colors.red : Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.attach_money,
                  size: 14,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Text(
                  bill['amount'] ?? '0.00',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isPaid)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Paid',
                  style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w500),
                ),
              )
            else if (isOverdue)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Overdue',
                  style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w500),
                ),
              ),
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'edit') {
                  // TODO: Implement edit functionality
                  debugPrint('Edit bill: ${bill['name']}');
                } else if (value == 'paid') {
                  await _markAsPaid(bill);
                } else if (value == 'delete') {
                  await _deleteBill(bill);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (!isPaid)
                  const PopupMenuItem(value: 'paid', child: Text('Mark as Paid')),
                const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markAsPaid(Map<String, dynamic> bill) async {
    try {
      final updatedBill = Map<String, dynamic>.from(bill);
      updatedBill['status'] = 'paid';
      updatedBill['paidAt'] = DateTime.now().toIso8601String();

      await widget.subscriptionService.updateSubscription(bill['id'], updatedBill);

      setState(() {
        final index = _bills.indexWhere((b) => b['id'] == bill['id']);
        if (index != -1) {
          _bills[index] = updatedBill;
          _filterBills();
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill marked as paid'), backgroundColor: Colors.green),
      );

      widget.onBillAdded();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to mark as paid: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteBill(Map<String, dynamic> bill) async {
    try {
      await widget.subscriptionService.deleteSubscription(bill['id']);

      setState(() {
        _bills.removeWhere((b) => b['id'] == bill['id']);
        _filterBills();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill deleted'), backgroundColor: Colors.green),
      );

      widget.onBillAdded();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete bill: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildStatusTab(String status, String label, IconData icon) {
    final isSelected = _selectedStatus == status;
    final count = _getBillCountForStatus(status);

    return ChoiceChip(
      label: Text('$label ($count)'),
      avatar: Icon(icon, size: 16),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _selectedStatus = status;
            _filterBills();
          });
        }
      },
      selectedColor: widget.category.backgroundColor,
      labelStyle: TextStyle(
        color: isSelected ? widget.category.color : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  int _getBillCountForStatus(String status) {
    final now = DateTime.now();
    int count = 0;

    for (var bill in _bills) {
      try {
        final dueDate = _parseDueDate(bill);
        final billStatus = bill['status']?.toString() ?? '';

        bool matches = false;
        switch (status) {
          case 'all':
            matches = true;
            break;
          case 'upcoming':
            matches = billStatus != 'paid' &&
                      dueDate != null &&
                      dueDate.isAfter(now) &&
                      dueDate.isBefore(now.add(const Duration(days: 30)));
            break;
          case 'overdue':
            matches = billStatus != 'paid' &&
                      dueDate != null &&
                      dueDate.isBefore(now);
            break;
          case 'paid':
            matches = billStatus == 'paid';
            break;
        }

        if (matches) count++;
      } catch (e) {
        debugPrint('Error counting bill for status $status: $e');
      }
    }

    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
              color: widget.category.backgroundColor.withValues(alpha: 0.1),
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
                    color: widget.category.backgroundColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.category.icon, color: widget.category.color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.category.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_filteredBills.length} of ${_bills.length} bills',
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

          // Status Filter Tabs
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildStatusTab('all', 'All', Icons.receipt_long),
                  const SizedBox(width: 8),
                  _buildStatusTab('upcoming', 'Upcoming', Icons.upcoming),
                  const SizedBox(width: 8),
                  _buildStatusTab('overdue', 'Overdue', Icons.warning),
                  const SizedBox(width: 8),
                  _buildStatusTab('paid', 'Paid', Icons.check_circle),
                ],
              ),
            ),
          ),

          // Bills List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _hasError
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text('Failed to load bills', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                            const SizedBox(height: 8),
                            ElevatedButton(onPressed: _loadBills, child: const Text('Try Again')),
                          ],
                        ),
                      )
                    : _filteredBills.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey[400]),
                                const SizedBox(height: 16),
                                Text(
                                  _selectedStatus == 'all'
                                    ? 'No bills in ${widget.category.name}'
                                    : 'No ${_selectedStatus} bills in ${widget.category.name}',
                                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _selectedStatus == 'all'
                                    ? 'Add a new bill to get started'
                                    : 'Try selecting a different status',
                                  style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadBills,
                            child: ListView(
                              padding: const EdgeInsets.all(16),
                              children: _filteredBills.map((bill) => _buildBillItem(bill, context)).toList(),
                            ),
                          ),
          ),

          // Add Bill Button
          if (!_isLoading && !_hasError)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // TODO: Navigate to add bill screen with this category pre-selected
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.category.backgroundColor,
                    foregroundColor: widget.category.color,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text('Add ${widget.category.name} Bill'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}