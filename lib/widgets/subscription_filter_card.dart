import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:projeckt_k/models/category_model.dart';

class SubscriptionFilterCard extends StatefulWidget {
  final List<Map<String, dynamic>> bills;
  final Function(String) onFilterChanged;
  final String? initialCategory;

  const SubscriptionFilterCard({
    Key? key,
    required this.bills,
    required this.onFilterChanged,
    this.initialCategory,
  }) : super(key: key);

  @override
  State<SubscriptionFilterCard> createState() => _SubscriptionFilterCardState();
}

class _SubscriptionFilterCardState extends State<SubscriptionFilterCard> {
  late String selectedCategory;

  // Get all categories from the Category model and add 'all' option
  List<Map<String, dynamic>> get categories {
    final allOption = {'id': 'all', 'name': 'All', 'icon': Icons.dashboard, 'color': Colors.grey[600], 'backgroundColor': Colors.grey[100]};
    final categoryList = [allOption];

    for (var category in Category.defaultCategories) {
      categoryList.add({
        'id': category.id,
        'name': category.name,
        'icon': category.icon,
        'color': category.color,
        'backgroundColor': category.backgroundColor,
      });
    }

    return categoryList;
  }

  @override
  void initState() {
    super.initState();
    selectedCategory = widget.initialCategory ?? 'all';
  }

  void _updateFilters() {
    widget.onFilterChanged(selectedCategory);
  }

  
  // Calculate totals for the current filter
  Map<String, dynamic> _calculateTotals() {
    double totalAmount = 0;
    int totalCount = 0;

    for (var bill in widget.bills) {
      // Check category filter only
      final billCategory = bill['category']?.toString();
      bool matchesCategory = selectedCategory == 'all' ||
                           (billCategory != null && billCategory == selectedCategory);

      if (matchesCategory) {
        final amount = double.tryParse(bill['amount']?.toString() ?? '0') ?? 0.0;
        totalAmount += amount;
        totalCount++;
      }
    }

    return {'totalAmount': totalAmount, 'totalCount': totalCount};
  }

  
  Widget _buildCategoryFilter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Category',
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(3),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: categories.map((category) {
                final isSelected = selectedCategory == category['id'];
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedCategory = category['id'];
                      _updateFilters();
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (category['backgroundColor'] ?? const Color(0xFF3B82F6))
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: isSelected
                          ? Border.all(
                              color: category['color'] ?? const Color(0xFF3B82F6),
                              width: 1.5,
                            )
                          : null,
                      boxShadow: isSelected ? [
                        BoxShadow(
                          color: (category['color'] ?? const Color(0xFF3B82F6)).withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ] : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          category['icon'],
                          size: 14,
                          color: isSelected ? Colors.white : (category['color'] ?? Colors.grey[600]),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          category['name'],
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected ? Colors.white : const Color(0xFF4B5563),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  
  Widget _buildTotalsDisplay() {
    final totals = _calculateTotals();
    final totalAmount = totals['totalAmount'] as double;
    final totalCount = totals['totalCount'] as int;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFE5E7EB),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Count
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.receipt_long,
                size: 14,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 4),
              Text(
                '$totalCount',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF374151),
                ),
              ),
            ],
          ),
          Container(
            width: 1,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            color: const Color(0xFFE5E7EB),
          ),
          // Total Amount
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.attach_money,
                size: 14,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 4),
              Text(
                totalAmount.toStringAsFixed(2),
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF374151),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFF3F4F6),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Category Filter
          _buildCategoryFilter(),
          const SizedBox(height: 4),

          // Totals Display
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Summary',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF374151),
                ),
              ),
              _buildTotalsDisplay(),
            ],
          ),
        ],
      ),
    );
  }
}