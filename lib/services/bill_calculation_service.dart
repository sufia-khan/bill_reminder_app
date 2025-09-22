import 'package:flutter/foundation.dart';

class BillCalculationService {
  static double parseAmount(dynamic amount) {
    if (amount == null) return 0.0;
    if (amount is double) return amount;
    if (amount is int) return amount.toDouble();
    if (amount is String) {
      return double.tryParse(amount) ?? 0.0;
    }
    return 0.0;
  }

  static DateTime? parseDueDate(Map<String, dynamic> bill) {
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
      if (kDebugMode) {
        print('Error parsing due date: $e');
      }
      return null;
    }
  }

  static double calculateMonthlyTotal(List<Map<String, dynamic>> bills) {
    double total = 0.0;
    final now = DateTime.now();

    for (var bill in bills) {
      try {
        final dueDate = parseDueDate(bill);
        if (dueDate != null &&
            dueDate.month == now.month &&
            dueDate.year == now.year &&
            bill['status'] != 'paid') {
          total += parseAmount(bill['amount']);
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error calculating monthly total: $e');
        }
      }
    }
    return total;
  }

  static double calculateLastMonthTotal(List<Map<String, dynamic>> bills) {
    double total = 0.0;
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1, now.day);

    for (var bill in bills) {
      try {
        final dueDate = parseDueDate(bill);
        if (dueDate != null &&
            dueDate.month == lastMonth.month &&
            dueDate.year == lastMonth.year &&
            bill['status'] != 'paid') {
          total += parseAmount(bill['amount']);
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error calculating last month total: $e');
        }
      }
    }
    return total;
  }

  static double calculateMonthlyDifference(List<Map<String, dynamic>> bills) {
    double thisMonthTotal = calculateMonthlyTotal(bills);
    double lastMonthTotal = calculateLastMonthTotal(bills);
    return thisMonthTotal - lastMonthTotal;
  }

  static double calculateMonthlyPercentageChange(List<Map<String, dynamic>> bills) {
    double thisMonthTotal = calculateMonthlyTotal(bills);
    double difference = calculateMonthlyDifference(bills);
    double lastMonthTotal = calculateLastMonthTotal(bills);

    if (lastMonthTotal == 0) {
      return thisMonthTotal > 0 ? 100.0 : 0.0;
    }

    return (difference / lastMonthTotal) * 100;
  }

  static bool isMonthlyIncrease(List<Map<String, dynamic>> bills) {
    return calculateMonthlyDifference(bills) > 0;
  }

  static double getUpcomingAmount(List<Map<String, dynamic>> bills) {
    double total = 0.0;
    final now = DateTime.now();

    for (var bill in bills) {
      try {
        final dueDate = parseDueDate(bill);
        if (dueDate != null &&
            dueDate.isAfter(now) &&
            bill['status'] != 'paid') {
          total += parseAmount(bill['amount']);
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error calculating upcoming amount: $e');
        }
      }
    }
    return total;
  }

  static double getPaidAmount(List<Map<String, dynamic>> bills) {
    double total = 0.0;
    final now = DateTime.now();

    for (var bill in bills) {
      try {
        final dueDate = parseDueDate(bill);
        if (dueDate != null &&
            dueDate.month == now.month &&
            dueDate.year == now.year &&
            bill['status'] == 'paid') {
          total += parseAmount(bill['amount']);
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error calculating paid amount: $e');
        }
      }
    }
    return total;
  }

  static double getOverdueAmount(List<Map<String, dynamic>> bills) {
    double total = 0.0;
    final now = DateTime.now();

    for (var bill in bills) {
      try {
        final dueDate = parseDueDate(bill);
        if (dueDate != null &&
            dueDate.isBefore(now) &&
            bill['status'] != 'paid') {
          total += parseAmount(bill['amount']);
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error calculating overdue amount: $e');
        }
      }
    }
    return total;
  }

  static int getUpcomingCount(List<Map<String, dynamic>> bills) {
    int count = 0;
    final now = DateTime.now();

    for (var bill in bills) {
      try {
        final dueDate = parseDueDate(bill);
        if (dueDate != null &&
            dueDate.isAfter(now) &&
            bill['status'] != 'paid') {
          count++;
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error counting upcoming bills: $e');
        }
      }
    }
    return count;
  }

  static int getPaidCount(List<Map<String, dynamic>> bills) {
    int count = 0;
    final now = DateTime.now();

    for (var bill in bills) {
      try {
        final dueDate = parseDueDate(bill);
        if (dueDate != null &&
            dueDate.month == now.month &&
            dueDate.year == now.year &&
            bill['status'] == 'paid') {
          count++;
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error counting paid bills: $e');
        }
      }
    }
    return count;
  }

  static int getOverdueCount(List<Map<String, dynamic>> bills) {
    int count = 0;
    final now = DateTime.now();

    for (var bill in bills) {
      try {
        final dueDate = parseDueDate(bill);
        if (dueDate != null &&
            dueDate.isBefore(now) &&
            bill['status'] != 'paid') {
          count++;
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error counting overdue bills: $e');
        }
      }
    }
    return count;
  }

  static int getUpcoming7DaysCount(List<Map<String, dynamic>> bills) {
    int count = 0;
    final now = DateTime.now();
    final sevenDaysFromNow = now.add(const Duration(days: 7));

    for (var bill in bills) {
      try {
        final dueDate = parseDueDate(bill);
        if (dueDate != null) {
          if ((dueDate.isAtSameMomentAs(now) || dueDate.isAfter(now)) &&
              (dueDate.isAtSameMomentAs(sevenDaysFromNow) ||
                  dueDate.isBefore(sevenDaysFromNow)) &&
              bill['status'] != 'paid') {
            count++;
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error getting upcoming 7 days count: $e');
        }
      }
    }
    return count;
  }

  static double getUpcoming7DaysTotal(List<Map<String, dynamic>> bills) {
    double total = 0.0;
    final now = DateTime.now();
    final sevenDaysFromNow = now.add(const Duration(days: 7));

    for (var bill in bills) {
      try {
        final dueDate = parseDueDate(bill);
        if (dueDate != null) {
          if ((dueDate.isAtSameMomentAs(now) || dueDate.isAfter(now)) &&
              (dueDate.isAtSameMomentAs(sevenDaysFromNow) ||
                  dueDate.isBefore(sevenDaysFromNow)) &&
              bill['status'] != 'paid') {
            total += parseAmount(bill['amount']);
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error calculating upcoming 7 days total: $e');
        }
      }
    }
    return total;
  }

  static Map<String, dynamic> getBillStatistics(List<Map<String, dynamic>> bills) {
    return {
      'monthlyTotal': calculateMonthlyTotal(bills),
      'upcomingCount': getUpcomingCount(bills),
      'paidCount': getPaidCount(bills),
      'overdueCount': getOverdueCount(bills),
    };
  }
}