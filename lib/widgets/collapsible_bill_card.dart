import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:projeckt_k/models/category_model.dart';

class CollapsibleBillCard extends StatefulWidget {
  final Map<String, dynamic> bill;
  final Function(int) onMarkAsPaid;
  final Function(int) onDelete;
  final Function(int) onEdit;
  final int index;
  final Category? category;

  const CollapsibleBillCard({
    super.key,
    required this.bill,
    required this.onMarkAsPaid,
    required this.onDelete,
    required this.onEdit,
    required this.index,
    this.category,
  });

  @override
  State<CollapsibleBillCard> createState() => _CollapsibleBillCardState();
}

class _CollapsibleBillCardState extends State<CollapsibleBillCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _expandAnimation;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _expandAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dueDate = _parseDueDate(widget.bill);
    final now = DateTime.now();
    final isOverdue =
        dueDate != null && dueDate.isBefore(now) && widget.bill['status'] != 'paid';
    final isPaid = widget.bill['status'] == 'paid';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
        child: Column(
          children: [
            // Main content (always visible)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Header row with icon, name, amount, and dropdown
                  Row(
                    children: [
                      // Category icon
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _getCategoryColor(widget.category?.id),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          widget.category?.icon ?? Icons.receipt,
                          color: Colors.white,
                          size: 24,
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
                              widget.bill['name']?.toString() ?? 'Unnamed Bill',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),

                            // Category and due date
                            Row(
                              children: [
                                // Category
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    widget.category?.name ?? 'Uncategorized',
                                    style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Due date
                                Icon(
                                  Icons.calendar_today,
                                  size: 12,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  dueDate != null
                                      ? _formatDate(dueDate)
                                      : 'No due date',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w400,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Amount and dropdown
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Amount
                          Text(
                            '\$${_parseAmount(widget.bill['amount']).toStringAsFixed(2)}',
                            style: GoogleFonts.poppins(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: isOverdue ? Colors.red : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Dropdown button
                          GestureDetector(
                            onTap: _toggleExpand,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                _isExpanded
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                color: Colors.grey[700],
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Status and action buttons row
                  Row(
                    children: [
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isPaid
                              ? Colors.green
                              : (isOverdue ? Colors.red : Colors.orange),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isPaid
                              ? 'Paid'
                              : (isOverdue ? 'Overdue' : 'Upcoming'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // Action buttons
                      if (!isPaid) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: widget.bill['_isUpdating'] == true
                                ? null
                                : () async {
                                    bool? confirm =
                                        await _showMarkAsPaidConfirmDialog(
                                      context,
                                      widget.bill['name']?.toString() ??
                                          'this bill',
                                    );
                                    if (confirm == true) {
                                      widget.onMarkAsPaid(widget.index);
                                    }
                                  },
                            icon: widget.bill['_isUpdating'] == true
                                ? SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                              Colors.green),
                                    ),
                                  )
                                : const Icon(Icons.check, size: 14),
                            label: widget.bill['_isUpdating'] == true
                                ? const Text('Updating...')
                                : const Text('Mark Paid'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.green,
                              side: const BorderSide(color: Colors.green),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],

                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: widget.bill['_isDeleting'] == true ||
                                  widget.bill['_isUpdating'] == true
                              ? null
                              : () => widget.onEdit(widget.index),
                          icon: widget.bill['_isDeleting'] == true
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(
                                            Colors.blue),
                                  ),
                                )
                              : const Icon(Icons.edit, size: 14),
                          label: widget.bill['_isDeleting'] == true
                              ? const Text('Deleting...')
                              : const Text('Edit'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue,
                            side: const BorderSide(color: Colors.blue),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Expandable section
            SizeTransition(
              sizeFactor: _expandAnimation,
              child: _buildExpandedContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedContent() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        border: Border(
          top: BorderSide(
            color: Colors.grey[300]!,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Additional Details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),

          // Details list
          _buildDetailRow(
            'Reminder',
            widget.bill['reminder']?.toString() ?? 'No reminder',
            Icons.notifications,
          ),
          _buildDetailRow(
            'Frequency',
            _getFrequencyText(widget.bill['frequency']?.toString()),
            Icons.repeat,
          ),
          _buildDetailRow(
            'Next billing',
            _formatNextBillingDate(widget.bill),
            Icons.event,
          ),
          _buildDetailRow(
            'Payment method',
            widget.bill['paymentMethod']?.toString() ?? 'Not specified',
            Icons.credit_card,
          ),

          const SizedBox(height: 16),

          // Delete button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.bill['_isDeleting'] == true ||
                      widget.bill['_isUpdating'] == true
                  ? null
                  : () async {
                      bool? confirm = await _showDeleteConfirmDialog(
                        context,
                        widget.bill['name']?.toString() ?? 'this bill',
                      );
                      if (confirm == true) {
                        widget.onDelete(widget.index);
                      }
                    },
              icon: widget.bill['_isDeleting'] == true
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.delete, size: 16),
              label: widget.bill['_isDeleting'] == true
                  ? const Text('Deleting...')
                  : const Text('Delete Bill'),
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
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: Colors.blue[700],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  DateTime? _parseDueDate(Map<String, dynamic> bill) {
    try {
      if (bill['dueDate'] == null) return null;
      if (bill['dueDate'] is DateTime) return bill['dueDate'];
      if (bill['dueDate'] is String) {
        return DateTime.parse(bill['dueDate']);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  String _formatNextBillingDate(Map<String, dynamic> bill) {
    final dueDate = _parseDueDate(bill);
    if (dueDate == null) return 'Not specified';
    return _formatDate(dueDate);
  }

  double _parseAmount(dynamic amount) {
    if (amount == null) return 0.0;
    if (amount is double) return amount;
    if (amount is int) return amount.toDouble();
    if (amount is String) {
      return double.tryParse(amount) ?? 0.0;
    }
    return 0.0;
  }

  String _getFrequencyText(String? frequency) {
    switch (frequency?.toLowerCase()) {
      case 'weekly':
        return 'Weekly';
      case 'bi-weekly':
        return 'Bi-weekly';
      case 'monthly':
        return 'Monthly';
      case 'quarterly':
        return 'Quarterly';
      case 'yearly':
        return 'Yearly';
      case 'one-time':
        return 'One-time';
      default:
        return 'Not specified';
    }
  }

  Color _getCategoryColor(String? categoryId) {
    // This should match the colors used in your app
    switch (categoryId) {
      case 'utilities':
        return Colors.blue;
      case 'entertainment':
        return Colors.purple;
      case 'food':
        return Colors.orange;
      case 'transportation':
        return Colors.green;
      case 'healthcare':
        return Colors.red;
      case 'education':
        return Colors.indigo;
      case 'shopping':
        return Colors.pink;
      case 'insurance':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  Future<bool?> _showMarkAsPaidConfirmDialog(
      BuildContext context, String billName) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as Paid'),
        content: Text('Are you sure you want to mark "$billName" as paid?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('Mark Paid'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showDeleteConfirmDialog(
      BuildContext context, String billName) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Bill'),
        content: Text(
            'Are you sure you want to delete "$billName"? This action cannot be undone.'),
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
}