import 'package:flutter/material.dart';

class Category {
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final Color backgroundColor;

  Category({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.backgroundColor,
  });

  // Predefined categories with pastel colors
  static List<Category> get defaultCategories => [
    Category(
      id: 'subscription',
      name: 'Subscription',
      icon: Icons.subscriptions,
      color: const Color(0xFFFF9800),
      backgroundColor: const Color(0xFFFFF3E0),
    ),
    Category(
      id: 'rent',
      name: 'Rent',
      icon: Icons.home,
      color: const Color(0xFF00897B),
      backgroundColor: const Color(0xFFE0F2F1),
    ),
    Category(
      id: 'internet',
      name: 'Internet',
      icon: Icons.wifi,
      color: const Color(0xFF1976D2),
      backgroundColor: const Color(0xFFE3F2FD),
    ),
    Category(
      id: 'education',
      name: 'Education',
      icon: Icons.school,
      color: const Color(0xFFF57C00),
      backgroundColor: const Color(0xFFFFF3E0),
    ),
    Category(
      id: 'utilities',
      name: 'Utilities',
      icon: Icons.power,
      color: const Color(0xFFFF9800),
      backgroundColor: const Color(0xFFFFF3E0),
    ),
    Category(
      id: 'insurance',
      name: 'Insurance',
      icon: Icons.health_and_safety,
      color: const Color(0xFFD32F2F),
      backgroundColor: const Color(0xFFFFEBEE),
    ),
    Category(
      id: 'transport',
      name: 'Transport',
      icon: Icons.directions_car,
      color: const Color(0xFF388E3C),
      backgroundColor: const Color(0xFFE8F5E8),
    ),
    Category(
      id: 'entertainment',
      name: 'Entertainment',
      icon: Icons.movie,
      color: const Color(0xFF7B1FA2),
      backgroundColor: const Color(0xFFF3E5F5),
    ),
    Category(
      id: 'food',
      name: 'Food & Dining',
      icon: Icons.restaurant,
      color: const Color(0xFFE65100),
      backgroundColor: const Color(0xFFFFF8E1),
    ),
    Category(
      id: 'shopping',
      name: 'Shopping',
      icon: Icons.shopping_bag,
      color: const Color(0xFFC2185B),
      backgroundColor: const Color(0xFFFCE4EC),
    ),
    Category(
      id: 'health',
      name: 'Health',
      icon: Icons.medical_services,
      color: const Color(0xFF0288D1),
      backgroundColor: const Color(0xFFE1F5FE),
    ),
    Category(
      id: 'fitness',
      name: 'Fitness',
      icon: Icons.fitness_center,
      color: const Color(0xFF00796B),
      backgroundColor: const Color(0xFFE0F2F1),
    ),
    Category(
      id: 'other',
      name: 'Other',
      icon: Icons.more_horiz,
      color: const Color(0xFF607D8B),
      backgroundColor: const Color(0xFFECEFF1),
    ),
  ];

  static Category? findById(String id) {
    try {
      return defaultCategories.firstWhere((category) => category.id == id);
    } catch (e) {
      return null;
    }
  }
}
