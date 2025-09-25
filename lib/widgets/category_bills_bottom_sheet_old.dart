import 'package:flutter/material.dart';
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
  bool _isLoadingMore = false;
  bool _hasError = false;
  bool _hasReachedMax = false;
  int _currentLimit = 10;
  final ScrollController _scrollController = ScrollController();
  String _selectedStatus = 'all'; // 'all', 'upcoming', 'overdue', 'paid'

  @override
  void initState() {
    super.initState();
    debugPrint('🚀 CategoryBillsBottomSheet initialized for category: ${widget.category.name} (ID: ${widget.category.id})');
    _loadBills();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100) {
      _loadMoreBills();
    }
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

            debugPrint('🔍 Debug: Category ID: ${widget.category.id}');
            debugPrint('🔍 Debug: Checking bill "${bill['name']}" - category: $billCategory');
            debugPrint('🔍 Debug: exactMatch: $exactMatch, containsMatch: $containsMatch, caseInsensitiveMatch: $caseInsensitiveMatch');
            debugPrint('🔍 Debug: Final matches: $matches');

            return matches;
          })
          .toList();

      setState(() {
        _bills = categoryBills;
        _filterBills(); // Apply status filtering
        _isLoading = false;
      });

      // Try to get more bills from Firebase if online
      if (await widget.subscriptionService.isOnline()) {
        await _loadFromFirebase();
      }

      debugPrint('📱 Loaded ${_bills.length} bills for category: ${widget.category.name}');
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
      debugPrint('❌ Failed to load bills: $e');
    }
  }

  Future<void> _loadFromFirebase() async {
    try {
      final allBills = await widget.subscriptionService.getSubscriptions();
      final categoryBills = allBills
          .where((bill) => bill['category']?.toString() == widget.category.id)
          .toList();

      if (categoryBills.length > _bills.length) {
        setState(() {
          _bills = categoryBills;
          _filterBills(); // Apply status filtering
        });
        debugPrint('🌐 Updated with Firebase data: ${_bills.length} bills');
      }
    } catch (e) {
      debugPrint('⚠️ Firebase sync failed: $e');
    }
  }

  // Filter bills based on selected status
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

  Future<void> _loadMoreBills() async {
    if (_isLoadingMore || _hasReachedMax) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      // Simulate loading more bills (in real implementation, you'd use pagination)
      await Future.delayed(const Duration(milliseconds: 500));

      setState(() {
        _isLoadingMore = false;
        _hasReachedMax = true; // Assume we've reached max for demo
      });
    } catch (e) {
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _refreshBills() async {
    _currentLimit = 10;
    _hasReachedMax = false;
    await _loadBills();
  }

  // Build status filter tabs
  List<Widget> _buildStatusTabs() {
    final statuses = [
      {'id': 'all', 'name': 'All', 'icon': Icons.receipt_long},
      {'id': 'upcoming', 'name': 'Upcoming', 'icon': Icons.upcoming},
      {'id': 'overdue', 'name': 'Overdue', 'icon': Icons.warning},
      {'id': 'paid', 'name': 'Paid', 'icon': Icons.check_circle},
    ];

    return statuses.map((status) {
      final isSelected = _selectedStatus == status['id'];
      final count = _getBillCountForStatus(status['id'] as String);

      return Container(
        margin: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                status['icon'] as IconData,
                size: 16,
                color: isSelected ? Colors.white : Colors.grey[600],
              ),
              const SizedBox(width: 4),
              Text(
                '${status['name']} ($count)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? Colors.white : Colors.grey[600],
                ),
              ),
            ],
          ),
          selected: isSelected,
          onSelected: (selected) {
            if (selected) {
              setState(() {
                _selectedStatus = status['id'] as String;
                _filterBills();
              });
            }
          },
          backgroundColor: Colors.grey[200],
          selectedColor: widget.category.backgroundColor,
          checkmarkColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        ),
      );
    }).toList();
  }

  // Get bill count for a specific status
  int _getBillCountForStatus(String status) {
    if (status == 'all') return _bills.length;

    final now = DateTime.now();
    int count = 0;

    for (var bill in _bills) {
      try {
        final dueDate = _parseDueDate(bill);
        final billStatus = bill['status']?.toString() ?? '';
        bool matches = false;

        switch (status) {
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

  // Get icon for status
  IconData _getIconForStatus(String status) {
    switch (status) {
      case 'upcoming':
        return Icons.upcoming;
      case 'overdue':
        return Icons.warning;
      case 'paid':
        return Icons.check_circle;
      default:
        return Icons.receipt_long_outlined;
    }
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
                          color: Colors.black87,
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
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _buildStatusTabs(),
              ),
            ),
          ),

          // Bills List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : _hasError
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Failed to load bills',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _refreshBills,
                              child: const Text('Try Again'),
                            ),
                          ],
                        ),
                      )
                    : _filteredBills.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _selectedStatus == 'all'
                                    ? Icons.receipt_long_outlined
                                    : _getIconForStatus(_selectedStatus),
                                  size: 64,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _selectedStatus == 'all'
                                    ? 'No bills in ${widget.category.name}'
                                    : 'No ${_selectedStatus} bills in ${widget.category.name}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _selectedStatus == 'all'
                                    ? 'Add a new bill to get started'
                                    : 'Try selecting a different status',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : PrimaryScrollController(
                            controller: _scrollController,
                            child: RefreshIndicator(
                              onRefresh: _refreshBills,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(16),
                              itemCount: _filteredBills.length + (_isLoadingMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index >= _filteredBills.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }

                                final bill = _filteredBills[index];
                                return _buildBillItem(bill, context);
                              },
                            ),
                          ),
                          ),
          ),

          // Add Bill Button
          if (!_isLoading && !_hasError)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AddBillScreen(
                          category: widget.category,
                          onBillAdded: widget.onBillAdded,
                        ),
                      ),
                    );
                  },
                  icon: Icon(Icons.add),
                  label: Text('Add ${widget.category.name} Bill'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.category.backgroundColor,
                    foregroundColor: widget.category.color,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBillItem(Map<String, dynamic> bill, BuildContext context) {
    final dueDate = _parseDueDate(bill);
    final now = DateTime.now();
    final isOverdue = dueDate != null && dueDate.isBefore(now) && bill['status'] != 'paid';
    final isPaid = bill['status'] == 'paid';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            if (bill['source'] == 'local')
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Local',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
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
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
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
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Upcoming',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
        onTap: () {
          // TODO: Navigate to bill details
        },
      ),
    );
  }

  DateTime? _parseDueDate(Map<String, dynamic> bill) {
    try {
      final dueDateStr = bill['dueDate']?.toString();
      if (dueDateStr == null || dueDateStr.isEmpty) return null;

      // Try different date formats
      final formats = [
        'dd/MM/yyyy',
        'MM/dd/yyyy',
        'yyyy-MM-dd',
        'dd-MM-yyyy',
      ];

      for (final format in formats) {
        try {
          final intl = DateFormat(format);
          return intl.parse(dueDateStr);
        } catch (_) {
          continue;
        }
      }

      // Try parsing as timestamp
      if (dueDateStr.contains('-')) {
        return DateTime.parse(dueDateStr);
      }

      return null;
    } catch (e) {
      debugPrint('Error parsing due date: $e');
      return null;
    }
  }
}

// Placeholder for AddBillScreen - you should replace this with your actual implementation
class AddBillScreen extends StatelessWidget {
  final Category category;
  final VoidCallback onBillAdded;

  const AddBillScreen({
    Key? key,
    required this.category,
    required this.onBillAdded,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Add ${category.name} Bill'),
        backgroundColor: category.backgroundColor,
      ),
      body: Center(
        child: Text('Add Bill Screen for ${category.name}'),
      ),
    );
  }
}