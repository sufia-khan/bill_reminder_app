import 'package:flutter/material.dart';
import 'package:projeckt_k/models/category_model.dart';
import 'package:google_fonts/google_fonts.dart';

class BillItemWidget extends StatelessWidget {
  final Map<String, dynamic> bill;
  final Function(int) onMarkAsPaid;
  final Function(int) onDelete;
  final Function(Map<String, dynamic>) onEdit;
  final Function(Map<String, dynamic>) onShowDetails;
  final bool useHomeScreenEdit;

  const BillItemWidget({
    Key? key,
    required this.bill,
    required this.onMarkAsPaid,
    required this.onDelete,
    required this.onEdit,
    required this.onShowDetails,
    this.useHomeScreenEdit = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final dueDate = _parseDueDate(bill);
    final now = DateTime.now();
    final isOverdue =
        dueDate != null && dueDate.isBefore(now) && bill['status'] != 'paid';
    final isPaid = bill['status'] == 'paid';
    final billIndex = bill['index'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
                            _getCategoryIcon(bill['category']),
                            size: 14,
                            color: Colors.grey[700],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _getCategoryName(bill['category']),
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
                            bill['name'] ?? 'Unknown Bill',
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
                          '\$${_parseAmount(bill['amount']).toStringAsFixed(2)}',
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
                        onPressed: bill['_isUpdating'] == true ? null : () => onMarkAsPaid(billIndex),
                        icon: bill['_isUpdating'] == true
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                                ),
                              )
                            : const Icon(Icons.check, size: 14),
                        label: bill['_isUpdating'] == true ? const Text('Updating...') : const Text('Mark Paid'),
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
                      onPressed: bill['_isDeleting'] == true || bill['_isUpdating'] == true
                          ? null
                          : () => useHomeScreenEdit
                              ? onEdit({...bill, 'originalIndex': bill['index'] ?? 0})
                              : onEdit(bill),
                      icon: bill['_isDeleting'] == true
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                              ),
                            )
                          : const Icon(Icons.edit, size: 14),
                      label: bill['_isDeleting'] == true ? const Text('Deleting...') : const Text('Edit'),
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
}