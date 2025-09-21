import 'package:flutter/material.dart';
import 'package:projeckt_k/services/subscription_service.dart';
import 'package:projeckt_k/models/category_model.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

class AllBillsScreen extends StatefulWidget {
  const AllBillsScreen({super.key});

  @override
  State<AllBillsScreen> createState() => _AllBillsScreenState();
}

class _AllBillsScreenState extends State<AllBillsScreen> {
  final SubscriptionService _subscriptionService = SubscriptionService();

  List<Map<String, dynamic>> _bills = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _selectedFilter = 'All';
  bool _isCalendarView = true;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadBills();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadBills() async {
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
      debugPrint('Failed to load bills: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredBills {
    if (_selectedFilter == 'All') return _bills;

    return _bills.where((bill) {
      final status = _getBillStatus(bill);
      return status == _selectedFilter;
    }).toList();
  }

  String _getBillStatus(Map<String, dynamic> bill) {
    if (bill['status'] == 'paid') return 'Paid';

    try {
      final dueDate = DateTime.parse(bill['dueDate']);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final due = DateTime(dueDate.year, dueDate.month, dueDate.day);

      if (due.isBefore(today)) {
        return 'Overdue';
      } else {
        return 'Upcoming';
      }
    } catch (e) {
      return 'Upcoming';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case "Paid":
        return const Color(0xFF2E7D32);
      case "Overdue":
        return const Color(0xFFC62828);
      case "Upcoming":
        return const Color(0xFFD4A017);
      default:
        return Colors.grey[600]!;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case "Paid":
        return Icons.payments_rounded;
      case "Overdue":
        return Icons.hourglass_top_rounded;
      case "Upcoming":
        return Icons.calendar_month;
      default:
        return Icons.receipt_long;
    }
  }

  Color _getStatusBackgroundColor(String status) {
    switch (status) {
      case "Paid":
        return const Color(0xFFE8F5E9);
      case "Overdue":
        return const Color(0xFFFFEBEE);
      case "Upcoming":
        return const Color(0xFFFDF4E3);
      default:
        return Colors.grey[100]!;
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('MMM dd, yyyy').format(date);
  }

  String _formatSafeDate(dynamic dateValue) {
    if (dateValue == null) return 'No date';

    try {
      if (dateValue is DateTime) {
        return DateFormat('MMM dd, yyyy').format(dateValue);
      }

      if (dateValue is String) {
        final dateStr = dateValue.trim();
        final formats = [
          'dd/MM/yyyy',
          'MM/dd/yyyy',
          'yyyy-MM-dd',
          'MMM dd, yyyy',
        ];

        for (final format in formats) {
          try {
            final date = DateFormat(format).parse(dateStr);
            return DateFormat('MMM dd, yyyy').format(date);
          } catch (e) {
            // Try next format
          }
        }

        return dateStr;
      }

      return 'Invalid date';
    } catch (e) {
      debugPrint('Error formatting date: $e');
      return 'Invalid date';
    }
  }

  double _parseAmount(dynamic amount) {
    if (amount == null) return 0.0;
    if (amount is num) return amount.toDouble();
    if (amount is String) return double.tryParse(amount) ?? 0.0;
    return 0.0;
  }

  double _getTotalAmount() {
    return _filteredBills.fold(0.0, (sum, bill) {
      final amount = bill['amount'];
      if (amount == null) return sum;
      if (amount is num) return sum + amount.toDouble();
      if (amount is String) return sum + (double.tryParse(amount) ?? 0.0);
      return sum;
    });
  }

  int _getBillCount(String status) {
    return _filteredBills
        .where((bill) => _getBillStatus(bill) == status)
        .length;
  }

  List<Map<String, dynamic>> _getBillsForDay(DateTime day) {
    return _bills.where((bill) {
      try {
        final dueDate = _parseDueDate(bill);
        if (dueDate == null) return false;

        final billDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
        final selectedDay = DateTime(day.year, day.month, day.day);

        return billDay.isAtSameMomentAs(selectedDay);
      } catch (e) {
        return false;
      }
    }).toList();
  }

  DateTime? _parseDueDate(Map<String, dynamic> bill) {
    try {
      if (bill['dueDate'] is DateTime) {
        return bill['dueDate'];
      }

      if (bill['dueDate'] is String) {
        final dateStr = bill['dueDate'].toString().trim();
        final formats = [
          'dd/MM/yyyy',
          'MM/dd/yyyy',
          'yyyy-MM-dd',
          'MMM dd, yyyy',
        ];

        for (final format in formats) {
          try {
            return DateFormat(format).parse(dateStr);
          } catch (e) {
            // Try next format
          }
        }
      }

      return null;
    } catch (e) {
      debugPrint('Error parsing due date: $e');
      return null;
    }
  }

  Future<void> _markBillAsPaid(int index) async {
    try {
      final bill = _bills[index];
      final billId = bill['id'] ?? bill['firebaseId']?.toString() ?? index.toString();

      await _subscriptionService.updateSubscription(billId, {
        'status': 'paid',
        'updatedAt': DateTime.now().toIso8601String(),
      });
      await _loadBills();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bill marked as paid!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to mark bill as paid: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteBill(int index) async {
    final bill = _bills[index];
    final billId = bill['id'] ?? bill['firebaseId']?.toString() ?? index.toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Bill'),
        content: Text('Are you sure you want to delete "${bill['name'] ?? 'this bill'}"?'),
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

    if (confirmed == true) {
      try {
        await _subscriptionService.deleteSubscription(billId);
        await _loadBills();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bill deleted successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete bill: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _editBill(Map<String, dynamic> bill) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => EditBillDialog(bill: bill),
    );

    if (result != null) {
      try {
        final billId = bill['id'] ?? bill['firebaseId']?.toString() ?? bill['localId']?.toString() ?? '';
        await _subscriptionService.updateSubscription(billId, result);
        await _loadBills();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bill updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update bill: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          "All Bills",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: () {
              setState(() {
                _isCalendarView = !_isCalendarView;
              });
            },
            icon: Icon(_isCalendarView ? Icons.list : Icons.calendar_month),
            tooltip: _isCalendarView ? 'List View' : 'Calendar View',
          ),
          IconButton(
            onPressed: _loadBills,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadBills,
        color: const Color(0xFF1976D2),
        backgroundColor: Colors.white,
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading bills...'),
                  ],
                ),
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
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: _loadBills,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _isCalendarView
                    ? _buildCalendarView()
                    : _buildListView(),
      ),
    );
  }

  Widget _buildCalendarView() {
    return Column(
      children: [
        // Filter Chips
        Container(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All', _getBillCount('All')),
                const SizedBox(width: 8),
                _buildFilterChip('Upcoming', _getBillCount('Upcoming'), const Color(0xFFD4A017)),
                const SizedBox(width: 8),
                _buildFilterChip('Paid', _getBillCount('Paid'), const Color(0xFF2E7D32)),
                const SizedBox(width: 8),
                _buildFilterChip('Overdue', _getBillCount('Overdue'), const Color(0xFFC62828)),
              ],
            ),
          ),
        ),

        // Calendar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) {
              return isSameDay(_selectedDay, day);
            },
            calendarFormat: _calendarFormat,
            eventLoader: _getBillsForDay,
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            onFormatChanged: (format) {
              setState(() {
                _calendarFormat = format;
              });
            },
            onPageChanged: (focusedDay) {
              setState(() {
                _focusedDay = focusedDay;
              });
            },
            calendarStyle: CalendarStyle(
              markersMaxCount: 6,
              markerDecoration: BoxDecoration(
                color: _getStatusColor('Upcoming'),
                shape: BoxShape.circle,
              ),
              markersAnchor: 0.7,
              markerSizeScale: 0.3,
              markerMargin: EdgeInsets.symmetric(horizontal: 1.5),
              todayDecoration: BoxDecoration(
                color: const Color(0xFF1976D2).withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF1976D2), width: 1),
              ),
              selectedDecoration: BoxDecoration(
                color: const Color(0xFF1976D2),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              weekendTextStyle: TextStyle(color: Colors.red[400]),
              holidayTextStyle: TextStyle(color: Colors.red[600]),
              defaultTextStyle: const TextStyle(color: Colors.black87, fontSize: 14),
              weekNumberTextStyle: TextStyle(color: Colors.grey[500], fontSize: 12),
              outsideDaysVisible: true,
              outsideTextStyle: TextStyle(color: Colors.grey[400]),
              disabledTextStyle: TextStyle(color: Colors.grey[300]),
              cellMargin: const EdgeInsets.all(4),
              cellPadding: const EdgeInsets.all(8),
              rangeHighlightColor: const Color(0xFF1976D2).withOpacity(0.2),
              rangeStartDecoration: BoxDecoration(
                color: const Color(0xFF1976D2),
                shape: BoxShape.circle,
              ),
              rangeEndDecoration: BoxDecoration(
                color: const Color(0xFF1976D2),
                shape: BoxShape.circle,
              ),
              withinRangeTextStyle: const TextStyle(color: Colors.black87),
              withinRangeDecoration: BoxDecoration(
                color: const Color(0xFF1976D2).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
            ),
            headerStyle: HeaderStyle(
              formatButtonVisible: true,
              formatButtonShowsNext: false,
              formatButtonDecoration: BoxDecoration(
                color: const Color(0xFF1976D2),
                borderRadius: BorderRadius.circular(12),
              ),
              formatButtonTextStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              titleTextStyle: const TextStyle(
                color: Colors.black87,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              headerPadding: const EdgeInsets.symmetric(vertical: 16),
              headerMargin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              leftChevronIcon: Icon(
                Icons.chevron_left,
                color: Colors.grey[700],
                size: 24,
              ),
              rightChevronIcon: Icon(
                Icons.chevron_right,
                color: Colors.grey[700],
                size: 24,
              ),
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: TextStyle(
                color: Colors.grey[700],
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              weekendStyle: TextStyle(
                color: Colors.red[500],
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
              ),
            ),
            calendarStyle: CalendarStyle(
              markersMaxCount: 3,
              markerDecoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
              markersAnchor: 0.7,
              markerSizeScale: 0.2,
              markerMargin: const EdgeInsets.symmetric(horizontal: 1.5),
              todayDecoration: BoxDecoration(
                color: const Color(0xFF1976D2).withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF1976D2), width: 1),
              ),
              selectedDecoration: BoxDecoration(
                color: const Color(0xFF1976D2),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              weekendTextStyle: TextStyle(color: Colors.red[400]),
              holidayTextStyle: TextStyle(color: Colors.red[600]),
              defaultTextStyle: const TextStyle(color: Colors.black87, fontSize: 14),
              weekNumberTextStyle: TextStyle(color: Colors.grey[500], fontSize: 12),
              outsideDaysVisible: true,
              outsideTextStyle: TextStyle(color: Colors.grey[400]),
              disabledTextStyle: TextStyle(color: Colors.grey[300]),
              cellMargin: const EdgeInsets.all(4),
              cellPadding: const EdgeInsets.all(8),
              rangeHighlightColor: const Color(0xFF1976D2).withOpacity(0.2),
              rangeStartDecoration: BoxDecoration(
                color: const Color(0xFF1976D2),
                shape: BoxShape.circle,
              ),
              rangeEndDecoration: BoxDecoration(
                color: const Color(0xFF1976D2),
                shape: BoxShape.circle,
              ),
              withinRangeTextStyle: const TextStyle(color: Colors.black87),
              withinRangeDecoration: BoxDecoration(
                color: const Color(0xFF1976D2).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Legend
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildLegendItem('Overdue', const Color(0xFFC62828)),
              _buildLegendItem('Upcoming', const Color(0xFFD4A017)),
              _buildLegendItem('Paid', const Color(0xFF2E7D32)),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Bills for selected day
        Expanded(
          child: _buildBillsForSelectedDay(),
        ),
      ],
    );
  }

  Widget _buildListView() {
    return Column(
      children: [
        // Summary Card
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1976D2), Color(0xFF1565C0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1976D2).withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Amount',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '\$${_getTotalAmount().toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_filteredBills.length} bills',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Filter Chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All', _getBillCount('All')),
                const SizedBox(width: 8),
                _buildFilterChip('Upcoming', _getBillCount('Upcoming'), const Color(0xFFD4A017)),
                const SizedBox(width: 8),
                _buildFilterChip('Paid', _getBillCount('Paid'), const Color(0xFF2E7D32)),
                const SizedBox(width: 8),
                _buildFilterChip('Overdue', _getBillCount('Overdue'), const Color(0xFFC62828)),
              ],
            ),
          ),
        ),

        // Bills List
        Expanded(
          child: _filteredBills.isEmpty
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
                        'No bills found',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _filteredBills.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final bill = _filteredBills[index];
                    final status = _getBillStatus(bill);
                    return _buildBillCard(bill, status, index);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildBillsForSelectedDay() {
    final dayBills = _getBillsForDay(_selectedDay);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Bills for ${_formatDate(_selectedDay)}',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: dayBills.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No bills for this day',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: dayBills.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final bill = dayBills[index];
                      final status = _getBillStatus(bill);
                      final originalIndex = _bills.indexOf(bill);
                      return _buildBillCard(bill, status, originalIndex);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, int count, [Color? color]) {
    final isSelected = _selectedFilter == label;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          const SizedBox(width: 4),
          Text(
            '($count)',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : Colors.grey[600],
            ),
          ),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = selected ? label : 'All';
        });
      },
      backgroundColor: Colors.white,
      selectedColor: color ?? const Color(0xFF1976D2),
      checkmarkColor: Colors.white,
      side: BorderSide(color: Colors.grey[300]!, width: 1),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }

  Widget _buildBillCard(Map<String, dynamic> bill, String status, int index) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: _getStatusColor(status).withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: _getStatusColor(status).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _getStatusBackgroundColor(status),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: _getStatusColor(status).withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    _getStatusIcon(status),
                    color: _getStatusColor(status),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bill['name'] ?? 'Unnamed Bill',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 14,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatSafeDate(bill['dueDate']),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      if (bill['category'] != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.category_outlined,
                              size: 14,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              bill['category'],
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      "\$${_parseAmount(bill['amount']).toStringAsFixed(2)}",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusBackgroundColor(status),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getStatusColor(status).withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _getStatusColor(status),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (bill['description'] != null && bill['description'].toString().isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Text(
                bill['description'],
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (status.toLowerCase() != 'paid') ...[
                    OutlinedButton.icon(
                      onPressed: () => _markBillAsPaid(index),
                      icon: const Icon(Icons.check_circle, size: 16),
                      label: const Text('Mark Paid'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                        side: const BorderSide(color: Colors.green),
                        minimumSize: const Size(80, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  OutlinedButton.icon(
                    onPressed: () => _editBill(bill),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Edit'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      minimumSize: const Size(60, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _deleteBill(index),
                    icon: const Icon(Icons.delete, size: 16),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      minimumSize: const Size(60, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EditBillDialog extends StatefulWidget {
  final Map<String, dynamic> bill;

  const EditBillDialog({super.key, required this.bill});

  @override
  State<EditBillDialog> createState() => _EditBillDialogState();
}

class _EditBillDialogState extends State<EditBillDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _amountController;
  late TextEditingController _dueDateController;
  late TextEditingController _descriptionController;

  String _selectedCategory = 'Other';
  String _selectedFrequency = 'Monthly';
  String _selectedReminder = 'Same day';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.bill['name'] ?? '');
    _amountController = TextEditingController(text: widget.bill['amount']?.toString() ?? '');
    _dueDateController = TextEditingController(text: widget.bill['dueDate'] ?? '');
    _descriptionController = TextEditingController(text: widget.bill['description'] ?? '');
    _selectedCategory = widget.bill['category'] ?? 'Other';
    _selectedFrequency = widget.bill['frequency'] ?? 'Monthly';
    _selectedReminder = widget.bill['reminder'] ?? 'Same day';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _dueDateController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(DateTime.now().year + 10),
    );

    if (picked != null) {
      setState(() {
        _dueDateController.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Bill'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Bill Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter bill name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  border: OutlineInputBorder(),
                  prefixText: '\$',
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter amount';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Please enter valid amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _dueDateController,
                decoration: const InputDecoration(
                  labelText: 'Due Date',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                readOnly: true,
                onTap: _selectDueDate,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please select due date';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: Category.defaultCategories.map((category) {
                  return DropdownMenuItem(
                    value: category.name,
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: category.backgroundColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Icon(
                            category.icon,
                            color: category.color,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(category.name),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCategory = value!;
                  });
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedFrequency,
                decoration: const InputDecoration(
                  labelText: 'Frequency',
                  border: OutlineInputBorder(),
                ),
                items: ['Daily', 'Weekly', 'Monthly', 'Yearly']
                    .map((frequency) => DropdownMenuItem(
                          value: frequency,
                          child: Text(frequency),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedFrequency = value!;
                  });
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedReminder,
                decoration: const InputDecoration(
                  labelText: 'Reminder',
                  border: OutlineInputBorder(),
                ),
                items: [
                  'No reminder',
                  'Same day',
                  '1 day before',
                  '3 days before',
                  '1 week before',
                  '10 days before',
                ]
                    .map((reminder) => DropdownMenuItem(
                          value: reminder,
                          child: Text(reminder),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedReminder = value!;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (Optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final updatedBill = {
                'name': _nameController.text.trim(),
                'amount': double.parse(_amountController.text),
                'dueDate': _dueDateController.text,
                'category': _selectedCategory,
                'frequency': _selectedFrequency,
                'reminder': _selectedReminder,
                'description': _descriptionController.text.trim(),
                'status': widget.bill['status'],
              };
              Navigator.pop(context, updatedBill);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}