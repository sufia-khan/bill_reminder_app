import 'package:flutter/material.dart';

class DateFormatService {
  static String formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  static String formatDateTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${formatDate(date)} $hour:$minute';
  }

  static String formatRelativeDate(DateTime date) {
    final now = DateTime.now();
    final difference = date.difference(now);

    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Tomorrow';
    } else if (difference.inDays == -1) {
      return 'Yesterday';
    } else if (difference.inDays > 0 && difference.inDays <= 7) {
      return '${difference.inDays} days from now';
    } else if (difference.inDays < 0 && difference.inDays >= -7) {
      return '${difference.inDays.abs()} days ago';
    } else {
      return formatDate(date);
    }
  }

  static String formatMonthYear(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  static TimeOfDay parseTime(String timeString) {
    // Handle formats like "8:30 AM" or "14:30"
    final RegExp timeRegExp = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)?');
    final match = timeRegExp.firstMatch(timeString);

    if (match != null) {
      int hour = int.parse(match.group(1)!);
      int minute = int.parse(match.group(2)!);
      String? period = match.group(3);

      if (period == 'PM' && hour != 12) {
        hour += 12;
      } else if (period == 'AM' && hour == 12) {
        hour = 0;
      }

      return TimeOfDay(hour: hour, minute: minute);
    }

    // Default to current time if parsing fails
    return TimeOfDay.now();
  }
}