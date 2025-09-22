import 'package:flutter/material.dart';
import 'package:projeckt_k/models/category_model.dart';
import 'package:projeckt_k/services/bill_service.dart';

class BottomSheetService {
  static void showFrequencyBottomSheet(
    BuildContext context,
    String currentFrequency,
    Function(String) onSelected,
  ) {
    final frequencies = [
      'Weekly',
      'Bi-weekly',
      'Monthly',
      'Quarterly',
      'Semi-annually',
      'Annually',
      'One-time',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Select Frequency',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: frequencies.length,
                itemBuilder: (context, index) {
                  final frequency = frequencies[index];
                  return ListTile(
                    title: Text(
                      frequency,
                      style: TextStyle(
                        color: Colors.black,
                      ),
                    ),
                    trailing: frequency == currentFrequency
                        ? Icon(Icons.check, color: Colors.green)
                        : null,
                    onTap: () {
                      onSelected(frequency);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
            SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  static void showReminderBottomSheet(
    BuildContext context,
    String currentReminder,
    Function(String) onSelected,
  ) {
    final reminders = [
      'Same day',
      '1 day before',
      '2 days before',
      '3 days before',
      '1 week before',
      '2 weeks before',
      '1 month before',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Select Reminder',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: reminders.length,
                itemBuilder: (context, index) {
                  final reminder = reminders[index];
                  return ListTile(
                    title: Text(
                      reminder,
                      style: TextStyle(
                        color: Colors.black,
                      ),
                    ),
                    trailing: reminder == currentReminder
                        ? Icon(Icons.check, color: Colors.green)
                        : null,
                    onTap: () {
                      onSelected(reminder);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
            SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  static void showCategoryBottomSheet(
    BuildContext context,
    Function(Category) onSelected,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Select Category',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                itemCount: Category.defaultCategories.length,
                itemBuilder: (context, index) {
                  final category = Category.defaultCategories[index];
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: category.backgroundColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        category.icon,
                        color: category.color,
                      ),
                    ),
                    title: Text(
                      category.name,
                      style: TextStyle(
                        color: Colors.black,
                      ),
                    ),
                    onTap: () {
                      onSelected(category);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
            SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}