import 'package:flutter/material.dart';
import 'package:projeckt_k/models/category_model.dart';
import 'package:google_fonts/google_fonts.dart';

class BillItemWidget extends StatefulWidget {
  final Map<String, dynamic> bill;
  final Function(int) onMarkAsPaid;
  final Function(int) onDelete;
  final Function(Map<String, dynamic>) onEdit;
  final Function(Map<String, dynamic>) onShowDetails;
  final bool useHomeScreenEdit;

  const BillItemWidget({
    super.key,
    required this.bill,
    required this.onMarkAsPaid,
    required this.onDelete,
    required this.onEdit,
    required this.onShowDetails,
    this.useHomeScreenEdit = false,
  });

  @override
  State<BillItemWidget> createState() => _BillItemWidgetState();
}

class _BillItemWidgetState extends State<BillItemWidget> {
  Map<String, dynamic> get bill => widget.bill;

  @override
  Widget build(BuildContext context) {
    final dueDate = _parseDueDate(widget.bill);
    final now = DateTime.now();
    final isOverdue =
        dueDate != null && dueDate.isBefore(now) && widget.bill['status'] != 'paid';
    final isPaid = widget.bill['status'] == 'paid';
    final billIndex = widget.bill['index'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: Key('bill_${widget.bill['id']}_${widget.bill['localId']}_${billIndex}_${DateTime.now().millisecondsSinceEpoch}'),
        background: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.delete, color: Colors.white, size: 32),
              SizedBox(height: 6),
              Text(
                'Delete',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
        secondaryBackground: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.red[800],
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 24),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.delete_forever, color: Colors.white, size: 32),
              SizedBox(height: 6),
              Text(
                'Delete',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
        direction: DismissDirection.endToStart,
        dismissThresholds: {
          DismissDirection.endToStart: 0.3, // Lower threshold for easier swipe
          DismissDirection.startToEnd: 0.3,
        },
        confirmDismiss: (direction) async {
          debugPrint('🔍 Swipe detected: $direction for bill ${widget.bill['name']}');
          // Prevent dismissal if bill is already being processed
          if (widget.bill['_isDeleting'] == true || widget.bill['_isUpdating'] == true) {
            debugPrint('⚠️ Bill is already being processed, preventing dismissal');
            return false;
          }
          return await _showDeleteConfirmDialog(context, widget.bill);
        },
        onDismissed: (direction) async {
          debugPrint('🗑️ Bill dismissed: ${widget.bill['name']} in direction: $direction');
          // Set deleting state to prevent multiple dismissals
          setState(() {
            widget.bill['_isDeleting'] = true;
          });
          // Call delete callback
          widget.onDelete(billIndex);
        },
        child: Card(
          elevation: 3,
          shadowColor: Colors.black.withOpacity(0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isPaid
                  ? Colors.green.withOpacity(0.3)
                  : (isOverdue
                        ? Colors.red.withOpacity(0.3)
                        : Colors.orange.withOpacity(0.3)),
              width: 1,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: isPaid
                      ? Colors.green.withOpacity(0.08)
                      : (isOverdue
                            ? Colors.red.withOpacity(0.08)
                            : Colors.orange.withOpacity(0.08)),
                  blurRadius: 12,
                  spreadRadius: 1,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category Row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getCategoryIcon(widget.bill['category']),
                              size: 14,
                              color: Colors.grey[700],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _getCategoryName(widget.bill['category']),
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
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
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Main Content Row
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.bill['name'] ?? 'Unknown Bill',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: isPaid
                                        ? Colors.green.withOpacity(0.1)
                                        : (isOverdue
                                              ? Colors.red.withOpacity(0.1)
                                              : Colors.orange.withOpacity(0.1)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    isPaid
                                        ? Icons.check_circle
                                        : (isOverdue ? Icons.error : Icons.access_time),
                                    color: isPaid
                                        ? Colors.green
                                        : (isOverdue ? Colors.red : Colors.orange),
                                    size: 16,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
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
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '\$${_parseAmount(widget.bill['amount']).toStringAsFixed(2)}',
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (!isPaid) ...[
                        OutlinedButton.icon(
                          onPressed: widget.bill['_isUpdating'] == true ? null : () => widget.onMarkAsPaid(billIndex),
                          icon: widget.bill['_isUpdating'] == true
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                                  ),
                                )
                              : const Icon(Icons.check, size: 14),
                          label: widget.bill['_isUpdating'] == true ? const Text('Updating...') : const Text('Mark Paid'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                            side: const BorderSide(color: Colors.green),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: Size(0, 32),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      OutlinedButton.icon(
                        onPressed: widget.bill['_isDeleting'] == true || widget.bill['_isUpdating'] == true
                            ? null
                            : () => widget.useHomeScreenEdit
                                ? widget.onEdit({...widget.bill, 'originalIndex': widget.bill['index'] ?? 0})
                                : widget.onEdit(widget.bill),
                        icon: widget.bill['_isDeleting'] == true
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                ),
                              )
                            : const Icon(Icons.edit, size: 14),
                        label: widget.bill['_isDeleting'] == true ? const Text('Deleting...') : const Text('Edit'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue,
                          side: const BorderSide(color: Colors.blue),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: Size(0, 32),
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
    );
  }

  DateTime? _parseDueDate(Map<String, dynamic> bill) {
    try {
      if (bill['dueDate'] == null) return null;

      if (bill['dueDate'] is DateTime) {
        return bill['dueDate'];
      }

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

  String _getCategoryName(dynamic category) {
    if (category == null) return 'Other';
    if (category is String) {
      final cat = Category.findById(category);
      return cat?.name ?? 'Other';
    }
    return 'Other';
  }

  IconData _getCategoryIcon(dynamic category) {
    if (category == null) return Icons.more_horiz;
    if (category is String) {
      final cat = Category.findById(category);
      return cat?.icon ?? Icons.more_horiz;
    }
    return Icons.more_horiz;
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

  Future<bool?> _showDeleteConfirmDialog(BuildContext context, Map<String, dynamic> bill) async {
    final billName = bill['name']?.toString() ?? 'Unknown Bill';

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Bill'),
        content: Text(
          'Are you sure you want to delete "$billName"? This action cannot be undone.',
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
}