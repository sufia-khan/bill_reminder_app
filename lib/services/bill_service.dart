import 'package:flutter/material.dart';
import 'package:projeckt_k/services/bill_calculation_service.dart';
import 'package:projeckt_k/services/date_format_service.dart';

class BillService {
  final List<Map<String, dynamic>> bills;

  BillService(this.bills);

  List<Map<String, dynamic>> getBillsByCategory(String category) {
    if (category == 'all') {
      return bills;
    }
    return bills.where((bill) => bill['category'] == category).toList();
  }

  List<Map<String, dynamic>> getUpcomingBills() {
    final now = DateTime.now();
    return bills.where((bill) {
      final dueDate = BillCalculationService.parseDueDate(bill);
      return dueDate != null &&
             dueDate.isAfter(now) &&
             bill['status'] != 'paid';
    }).toList();
  }

  List<Map<String, dynamic>> getOverdueBills() {
    final now = DateTime.now();
    return bills.where((bill) {
      final dueDate = BillCalculationService.parseDueDate(bill);
      return dueDate != null &&
             dueDate.isBefore(now) &&
             bill['status'] != 'paid';
    }).toList();
  }

  List<Map<String, dynamic>> getPaidBills() {
    return bills.where((bill) => bill['status'] == 'paid').toList();
  }

  List<Map<String, dynamic>> getBillsForNext7Days() {
    final now = DateTime.now();
    final sevenDaysFromNow = now.add(const Duration(days: 7));

    return bills.where((bill) {
      final dueDate = BillCalculationService.parseDueDate(bill);
      if (dueDate == null) return false;

      return (dueDate.isAtSameMomentAs(now) || dueDate.isAfter(now)) &&
             (dueDate.isAtSameMomentAs(sevenDaysFromNow) || dueDate.isBefore(sevenDaysFromNow)) &&
             bill['status'] != 'paid';
    }).toList();
  }

  Map<String, List<Map<String, dynamic>>> groupBillsByCategory() {
    final Map<String, List<Map<String, dynamic>>> categorizedBills = {};

    for (var bill in bills) {
      final categoryId = bill['category'] ?? 'other';
      if (!categorizedBills.containsKey(categoryId)) {
        categorizedBills[categoryId] = [];
      }
      categorizedBills[categoryId]!.add(bill);
    }

    return categorizedBills;
  }

  List<Map<String, dynamic>> sortBillsByDueDate(List<Map<String, dynamic>> billsToSort) {
    billsToSort.sort((a, b) {
      final aDate = BillCalculationService.parseDueDate(a);
      final bDate = BillCalculationService.parseDueDate(b);

      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return aDate.compareTo(bDate);
    });

    return billsToSort;
  }

  bool markBillAsPaid(int index) {
    if (index < 0 || index >= bills.length) return false;

    bills[index]['status'] = 'paid';
    return true;
  }

  bool deleteBill(int index) {
    if (index < 0 || index >= bills.length) return false;

    bills.removeAt(index);
    return true;
  }

  bool updateBill(int index, Map<String, dynamic> updatedBill) {
    if (index < 0 || index >= bills.length) return false;

    bills[index] = updatedBill;
    return true;
  }

  void addBill(Map<String, dynamic> bill) {
    bills.add(bill);
  }

  Map<String, dynamic> getBillStatistics() {
    return {
      'monthlyTotal': BillCalculationService.calculateMonthlyTotal(bills),
      'lastMonthTotal': BillCalculationService.calculateLastMonthTotal(bills),
      'monthlyDifference': BillCalculationService.calculateMonthlyDifference(bills),
      'monthlyPercentageChange': BillCalculationService.calculateMonthlyPercentageChange(bills),
      'isMonthlyIncrease': BillCalculationService.isMonthlyIncrease(bills),
      'upcomingCount': BillCalculationService.getUpcomingCount(bills),
      'upcomingAmount': BillCalculationService.getUpcomingAmount(bills),
      'paidCount': BillCalculationService.getPaidCount(bills),
      'paidAmount': BillCalculationService.getPaidAmount(bills),
      'overdueCount': BillCalculationService.getOverdueCount(bills),
      'overdueAmount': BillCalculationService.getOverdueAmount(bills),
      'upcoming7DaysCount': BillCalculationService.getUpcoming7DaysCount(bills),
      'upcoming7DaysTotal': BillCalculationService.getUpcoming7DaysTotal(bills),
    };
  }

  void checkForOverdueBills(Function(Map<String, dynamic>) onOverdueFound) {
    final now = DateTime.now();

    for (var bill in bills) {
      final dueDate = BillCalculationService.parseDueDate(bill);
      if (dueDate != null &&
          dueDate.isBefore(now) &&
          bill['status'] != 'paid' &&
          bill['lastOverdueNotification'] == null) {

        bill['lastOverdueNotification'] = now.toIso8601String();
        onOverdueFound(bill);
      }
    }
  }
}