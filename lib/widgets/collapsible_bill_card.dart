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
      duration: const Duration(milliseconds: 260),
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

  DateTime? _parseDueDate(Map<String, dynamic> bill) {
    try {
      final d = bill['dueDate'];
      if (d == null) return null;
      if (d is DateTime) return d;
      if (d is String) return DateTime.parse(d);
      return null;
    } catch (_) {
      return null;
    }
  }

  double _parseAmount(dynamic amount) {
    if (amount == null) return 0.0;
    if (amount is num) return amount.toDouble();
    if (amount is String) return double.tryParse(amount) ?? 0.0;
    return 0.0;
  }

  Color _getCategoryColor(String? categoryId) {
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
        return Colors.grey.shade700;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final dueDate = _parseDueDate(widget.bill);
    final now = DateTime.now();
    final isOverdue =
        dueDate != null &&
        dueDate.isBefore(now) &&
        widget.bill['status'] != 'paid';
    final isPaid = widget.bill['status'] == 'paid';

    final amountText =
        '\$${_parseAmount(widget.bill['amount']).toStringAsFixed(2)}';

    // days remaining text
    String? daysText;
    Color daysColor = Colors.grey.shade700;
    if (dueDate != null) {
      final diff = dueDate.difference(now).inDays;
      if (widget.bill['status'] == 'paid') {
        daysText =
            null; // Don't show duplicate "Paid" text here - it's already shown in the status badge
        daysColor = Colors.green;
      } else if (diff < 0) {
        final d = diff.abs();
        daysText = 'Overdue by $d ${d == 1 ? 'day' : 'days'}';
        daysColor = Colors.red;
      } else if (diff == 0) {
        daysText = 'Due today';
        daysColor = Colors.orange;
      } else {
        daysText = '$diff ${diff == 1 ? 'day' : 'days'} left';
        daysColor = Colors.grey.shade700;
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          // Professional subtle shadow
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 1),
          ),
        ],
        border: Border.all(
          color: isOverdue
              ? const Color(0xFFEF4444).withValues(alpha: 0.15)
              : const Color(0xFFE5E7EB),
          width: isOverdue ? 1.2 : 0.8,
        ),
      ),
      child: Column(
        children: [
          // Main content area
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left side content
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon with bill name and category on the side
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Big separate icon
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: _getCategoryColor(
                                widget.category?.id,
                              ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _getCategoryColor(
                                  widget.category?.id,
                                ).withValues(alpha: 0.15),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _getCategoryColor(
                                    widget.category?.id,
                                  ).withValues(alpha: 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Icon(
                                widget.category?.icon ?? Icons.receipt_outlined,
                                color: _getCategoryColor(widget.category?.id),
                                size: 32,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Bill name and category info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Bill name
                                Text(
                                  widget.bill['name']?.toString() ??
                                      'Unnamed Bill',
                                  style: GoogleFonts.poppins(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF111827),
                                    letterSpacing: 0.1,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),

                                // Category tag
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF9FAFB),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: const Color(0xFFE5E7EB),
                                      width: 1,
                                    ),
                                  ),
                                  child: Text(
                                    widget.category?.name ?? 'Uncategorized',
                                    style: GoogleFonts.poppins(
                                      fontSize: 9,
                                      color: const Color(0xFF6B7280),
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                // Date with icon below category
                                if (dueDate != null)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.calendar_today_outlined,
                                        size: 11,
                                        color: Color(0xFF9CA3AF),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        '${dueDate.month}/${dueDate.day}',
                                        style: GoogleFonts.poppins(
                                          fontSize: 9,
                                          color: const Color(0xFF6B7280),
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Action buttons
                      Row(
                        children: [
                          if (!isPaid) ...[
                            Expanded(
                              flex: 3,
                              child: Container(
                                height: 32,
                                child: ElevatedButton(
                                  onPressed: widget.bill['_isUpdating'] == true
                                      ? null
                                      : () async {
                                          final confirm =
                                              await _showMarkAsPaidConfirmDialog(
                                                context,
                                                widget.bill['name']
                                                        ?.toString() ??
                                                    'this bill',
                                              );
                                          if (confirm == true)
                                            widget.onMarkAsPaid(widget.index);
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF4F46E5),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                      side: const BorderSide(
                                        color: Color(0xFF4F46E5),
                                        width: 1,
                                      ),
                                    ),
                                    shadowColor: Colors.transparent,
                                  ),
                                  child: Center(
                                    child: widget.bill['_isUpdating'] == true
                                        ? SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    Colors.white,
                                                  ),
                                            ),
                                          )
                                        : const Text(
                                            'Mark as Paid',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.1,
                                              color: Colors.pink,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            flex: 2,
                            child: Container(
                              height: 32,
                              child: ElevatedButton(
                                onPressed:
                                    widget.bill['_isDeleting'] == true ||
                                        widget.bill['_isUpdating'] == true
                                    ? null
                                    : () => widget.onEdit(widget.index),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4F46E5),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  shadowColor: Colors.transparent,
                                ),
                                child: Center(
                                  child:
                                      widget.bill['_isDeleting'] == true ||
                                          widget.bill['_isUpdating'] == true
                                      ? SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  const Color(0xFF6B7280),
                                                ),
                                          ),
                                        )
                                      : const Text(
                                          'Edit',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                            letterSpacing: 0.1,
                                            color: Colors.black,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Right side content
                Expanded(
                  flex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Amount
                      Tooltip(
                        message: amountText,
                        child: Text(
                          amountText,
                          style: GoogleFonts.poppins(
                            fontSize: 16, // Reduced from 18 to fit more text
                            fontWeight: FontWeight.w700,
                            color: isOverdue
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF111827),
                            letterSpacing: 0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Bill status badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isPaid
                              ? const Color(0xFF10B981).withValues(alpha: 0.1)
                              : isOverdue
                              ? const Color(0xFFEF4444).withValues(alpha: 0.1)
                              : const Color(0xFFF59E0B).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isPaid
                                ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                : isOverdue
                                ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                                : const Color(
                                    0xFFF59E0B,
                                  ).withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          isPaid
                              ? 'Paid'
                              : isOverdue
                              ? 'Overdue'
                              : 'Upcoming',
                          style: GoogleFonts.poppins(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: isPaid
                                ? const Color(0xFF10B981)
                                : isOverdue
                                ? const Color(0xFFEF4444)
                                : const Color(0xFFF59E0B),
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Days remaining (if any)
                      if (daysText != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: daysColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            daysText,
                            style: GoogleFonts.poppins(
                              fontSize: 8,
                              fontWeight: FontWeight.w500,
                              color: daysColor,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      const SizedBox(height: 0),

                      // Expand arrow - aligned with action buttons
                      GestureDetector(
                        onTap: _toggleExpand,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFFE5E7EB),
                              width: 0.8,
                            ),
                          ),
                          child: Icon(
                            _isExpanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            color: const Color(0xFF6B7280),
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Professional expandable details
          SizeTransition(
            sizeFactor: _expandAnimation,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                border: const Border(
                  top: BorderSide(color: Color(0xFFE5E7EB), width: 0.8),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Additional Details',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF374151),
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildDetailRow(
                    'Reminder',
                    widget.bill['reminder']?.toString() ?? 'No reminder',
                    Icons.notifications_outlined,
                  ),
                  _buildDetailRow(
                    'Frequency',
                    (widget.bill['frequency']?.toString() ?? 'Not specified'),
                    Icons.repeat_outlined,
                  ),
                  _buildDetailRow(
                    'Next billing',
                    dueDate != null
                        ? '${dueDate.month}/${dueDate.day}/${dueDate.year}'
                        : 'Not specified',
                    Icons.event_outlined,
                  ),
                  _buildDetailRow(
                    'Payment method',
                    widget.bill['paymentMethod']?.toString() ?? 'Not specified',
                    Icons.credit_card_outlined,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 36,
                    child: ElevatedButton(
                      onPressed:
                          widget.bill['_isDeleting'] == true ||
                              widget.bill['_isUpdating'] == true
                          ? null
                          : () => widget.onDelete(widget.index),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        shadowColor: Colors.transparent,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.bill['_isDeleting'] == true)
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          else
                            const Icon(Icons.delete_outline, size: 14),
                          const SizedBox(width: 6),
                          const Text(
                            'Delete Bill',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE0E7FF), width: 0.8),
            ),
            child: Icon(icon, size: 16, color: const Color(0xFF4F46E5)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF6B7280),
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF111827),
                    letterSpacing: 0.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showMarkAsPaidConfirmDialog(
    BuildContext context,
    String billName,
  ) async {
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
            child: const Text('Mark Paid'),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
          ),
        ],
      ),
    );
  }
}
