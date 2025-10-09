import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:projeckt_k/models/category_model.dart';

// Primary color matching the summary cards
final Color kPrimaryColor = HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor();

class HorizontalCategorySelector extends StatefulWidget {
  final List<Category> categories;
  final String selectedCategory;
  final Function(String) onCategorySelected;
  final int totalBills;
  final int Function(String) getCategoryBillCount;

  const HorizontalCategorySelector({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.totalBills,
    required this.getCategoryBillCount,
  });

  @override
  State<HorizontalCategorySelector> createState() =>
      _HorizontalCategorySelectorState();
}

class _HorizontalCategorySelectorState
    extends State<HorizontalCategorySelector> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Categories',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ),
          // Horizontal scrolling categories with React-style design
          SizedBox(
            height: 48,
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              itemCount: widget.categories.length + 1, // +1 for "All"
              padding: EdgeInsets.zero,
              itemBuilder: (context, index) {
                final isAllCategories = index == 0;
                final category = isAllCategories
                    ? null
                    : widget.categories[index - 1];
                final categoryId = isAllCategories
                    ? 'all'
                    : category?.id ?? 'all';
                final isSelected = widget.selectedCategory == categoryId;

                // We no longer show bill counts here; keep the callback to remain
                // compatible with callers but ignore the returned value.
                widget.getCategoryBillCount(categoryId);

                final labelText = isAllCategories
                    ? 'All'
                    : category?.name ?? 'Unknown';

                return Container(
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.grey[50],
                  ),
                  child: _buildCategoryPill(
                    context,
                    labelText,
                    categoryId,
                    isSelected,
                    0, // billCount (unused)
                    isAllCategories ? Icons.grid_view : category?.icon,
                    isAllCategories ? null : category?.backgroundColor,
                    isAllCategories ? null : category?.color,
                    index,
                  ),
                );
              },
            ),
          ),
        ],
      ));
    
  }

  Widget _buildCategoryPill(
    BuildContext context,
    String label,
    String categoryId,
    bool isSelected,
    int billCount,
    IconData? icon,
    Color? backgroundColor,
    Color? categoryColor,
    int index,
  ) {
    return GestureDetector(
      onTap: () {
        widget.onCategorySelected(categoryId);
        // Haptic feedback for better user experience
        HapticFeedback.lightImpact();

        // Animate to center the selected category
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            final double scrollPosition =
                index * 103.0; // width + margin (95 + 8)
            final double maxScroll = _scrollController.position.maxScrollExtent;
            final double viewportWidth =
                _scrollController.position.viewportDimension;
            final double targetPosition =
                (scrollPosition - viewportWidth / 2 + 47.5).clamp(
                  0.0,
                  maxScroll,
                );

            _scrollController.animateTo(
              targetPosition,
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOut,
            );
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isSelected
              ? (categoryId == 'all' ? kPrimaryColor : (categoryColor ?? kPrimaryColor))
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.transparent : Colors.grey[200]!,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: (categoryId == 'all' ? kPrimaryColor : (categoryColor ?? kPrimaryColor)).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Show icon only when selected (React-style)
              if (isSelected) ...[
                Icon(
                  icon ?? _getCategoryIcon(categoryId),
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 8),
              ],

              // Category name
              Text(
                label,
                style: GoogleFonts.inter(
                  color: isSelected ? Colors.white : Colors.grey[600],
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String categoryId) {
    switch (categoryId) {
      case 'all':
        return Icons.grid_view;
      case 'utilities':
        return Icons.electrical_services;
      case 'entertainment':
        return Icons.movie;
      case 'food':
        return Icons.restaurant;
      case 'transport':
        return Icons.directions_car;
      case 'health':
        return Icons.medical_services;
      case 'education':
        return Icons.school;
      case 'shopping':
        return Icons.shopping_bag;
      case 'insurance':
        return Icons.health_and_safety;
      case 'subscription':
        return Icons.subscriptions;
      case 'other':
        return Icons.more_horiz;
      default:
        return Icons.category;
    }
  }
}
