import 'package:flutter/material.dart';

enum NavigationItem {
  home,
  analytics,
  add,
  bills,
  settings,
}

class NavigationService {
  static const Map<NavigationItem, String> _itemTitles = {
    NavigationItem.home: 'Home',
    NavigationItem.analytics: 'Analytics',
    NavigationItem.add: 'Add',
    NavigationItem.bills: 'Bills',
    NavigationItem.settings: 'Settings',
  };

  static const Map<NavigationItem, IconData> _itemIcons = {
    NavigationItem.home: Icons.home,
    NavigationItem.analytics: Icons.analytics,
    NavigationItem.add: Icons.add,
    NavigationItem.bills: Icons.receipt_long,
    NavigationItem.settings: Icons.settings,
  };

  static const Map<NavigationItem, Color> _itemColors = {
    NavigationItem.home: Colors.blue,
    NavigationItem.analytics: Colors.purple,
    NavigationItem.add: Colors.green,
    NavigationItem.bills: Colors.orange,
    NavigationItem.settings: Colors.grey,
  };

  static String getTitle(NavigationItem item) {
    return _itemTitles[item] ?? '';
  }

  static IconData getIcon(NavigationItem item) {
    return _itemIcons[item] ?? Icons.home;
  }

  static Color getColor(NavigationItem item) {
    return _itemColors[item] ?? Colors.blue;
  }

  static List<NavigationItem> get items => NavigationItem.values;

  static int getIndex(NavigationItem item) {
    return items.indexOf(item);
  }

  static NavigationItem getItemFromIndex(int index) {
    if (index >= 0 && index < items.length) {
      return items[index];
    }
    return NavigationItem.home;
  }
}