import 'package:flutter/material.dart';
import 'package:projeckt_k/services/bill_service.dart';
import 'package:projeckt_k/services/dialog_service.dart';

class BillOperationsService {
  final BillService billService;
  final BuildContext context;

  BillOperationsService(this.billService, this.context);

  void markAsPaid(int billIndex) {
    if (billIndex >= 0 && billIndex < billService.bills.length) {
      final billName = billService.bills[billIndex]['name'] ?? 'Unknown Bill';

      DialogService.showMarkAsPaidConfirmDialog(context, billName).then((confirmed) {
        if (confirmed == true) {
          billService.markBillAsPaid(billIndex);
          DialogService.showSuccessSnackBar(context, '$billName marked as paid!');
        }
      });
    }
  }

  void deleteBill(int billIndex) {
    if (billIndex >= 0 && billIndex < billService.bills.length) {
      final bill = billService.bills[billIndex];

      DialogService.showDeleteConfirmDialog(context, bill).then((confirmed) {
        if (confirmed == true) {
          final billName = bill['name'] ?? 'Unknown Bill';
          billService.deleteBill(billIndex);
          DialogService.showSuccessSnackBar(context, '$billName deleted successfully!');
        }
      });
    }
  }

  void showBillDetails(Map<String, dynamic> bill) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long, color: Colors.blue, size: 24),
                SizedBox(width: 12),
                Text(
                  'Bill Details',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),
            Divider(),
            SizedBox(height: 10),
            _buildDetailRow('Name', bill['name'] ?? 'Unknown'),
            _buildDetailRow('Amount', '\$${bill['amount'] ?? '0.00'}'),
            _buildDetailRow('Due Date', bill['dueDate'] ?? 'Not set'),
            _buildDetailRow('Status', bill['status'] ?? 'Unknown'),
            _buildDetailRow('Category', bill['category'] ?? 'Other'),
            _buildDetailRow('Frequency', bill['frequency'] ?? 'Monthly'),
            _buildDetailRow('Reminder', bill['reminder'] ?? 'Same day'),
            SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Close'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[300],
                      foregroundColor: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}