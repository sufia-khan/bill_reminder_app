import 'package:flutter/material.dart';
import 'package:projeckt_k/models/category_model.dart';
import 'package:projeckt_k/services/enhanced_bottom_sheet_service.dart';

class BottomSheetService {
  static Future<void> showFrequencyBottomSheet(
    BuildContext context,
    String currentFrequency,
    Function(String) onSelected,
  ) async {
    final result = await EnhancedBottomSheetService.showFrequencyBottomSheet(
      context,
      currentFrequency,
    );

    if (result != null) {
      onSelected(result);
    }
  }

  static Future<void> showReminderBottomSheet(
    BuildContext context,
    String currentReminder,
    Function(String) onSelected,
  ) async {
    final result = await EnhancedBottomSheetService.showReminderBottomSheet(
      context,
      currentReminder,
    );

    if (result != null) {
      onSelected(result);
    }
  }

  static Future<void> showCategoryBottomSheet(
    BuildContext context,
    Function(Category) onSelected,
  ) async {
    final result = await EnhancedBottomSheetService.showCategoryBottomSheet(
      context,
    );

    if (result != null) {
      onSelected(result);
    }
  }
}