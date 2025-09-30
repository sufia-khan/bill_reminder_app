import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:projeckt_k/models/category_model.dart';

class HorizontalCategorySelector extends StatefulWidget {
  final List<Category> categories;
  final String selectedCategory;
  final Function(String) onCategorySelected;
  final int totalBills;
  final int Function(String) getCategoryBillCount;

  const HorizontalCategorySelector({
    Key? key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.totalBills,
    required this.getCategoryBillCount,
  }) : super(key: key);

  @override
  State<HorizontalCategorySelector> createState() => _HorizontalCategorySelectorState();
}

class _HorizontalCategorySelectorState extends State<HorizontalCategorySelector> {
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
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4).copyWith(bottom: 8),
            child: Text(
              'Categories',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ),
          // Horizontal scrolling categories
          SizedBox(
            // Fixed height for the horizontal list; keeps layout stable
            // and prevents the parent Column from overflowing.
            height: 56,
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              itemCount: widget.categories.length + 1, // +1 for "All"
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemBuilder: (context, index) {
                final isAllCategories = index == 0;
                final category = isAllCategories ? null : widget.categories[index - 1];
                final categoryId = isAllCategories ? 'all' : category?.id ?? 'all';
                final isSelected = widget.selectedCategory == categoryId;

                // We no longer show bill counts here; keep the callback to remain
                // compatible with callers but ignore the returned value.
                widget.getCategoryBillCount(categoryId);

                final labelText = isAllCategories ? 'All' : category?.name ?? 'Unknown';
                final tileWidth = _computeTileWidth(labelText, isSelected);

                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: tileWidth,
                    child: _buildCategoryPill(
                      context,
                      labelText,
                      categoryId,
                      isSelected,
                      0, // billCount (unused)
                      isAllCategories ? Icons.grid_view : category?.icon,
                      isAllCategories ? null : category?.backgroundColor,
                      index,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  double _computeTileWidth(String label, bool isSelected) {
    // Base text style used in the pill
    final textStyle = GoogleFonts.inter(
      fontSize: isSelected ? 12 : 12,
      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
    );

    final tp = TextPainter(
      text: TextSpan(text: label, style: textStyle),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();

    // Add padding: when selected we show an icon on the left, so add more
    final extra = isSelected ? 44.0 : 20.0; // icon + spacing vs only padding
    final minWidth = 64.0;
    final maxWidth = 180.0;

    final computed = tp.width + extra;
    return computed.clamp(minWidth, maxWidth);
  }

  Widget _buildCategoryPill(
    BuildContext context,
    String label,
    String categoryId,
    bool isSelected,
    int billCount,
    IconData? icon,
    Color? backgroundColor,
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
            final double scrollPosition = index * 103.0; // width + margin (95 + 8)
            final double maxScroll = _scrollController.position.maxScrollExtent;
            final double viewportWidth = _scrollController.position.viewportDimension;
            final double targetPosition = (scrollPosition - viewportWidth / 2 + 47.5).clamp(0.0, maxScroll);

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
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor(),
                    HSLColor.fromAHSL(1.0, 236, 0.89, 0.75).toColor(),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : backgroundColor ?? Colors.grey[100],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? Colors.transparent
                : Colors.grey[300]!,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor().withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Show icon only when selected. Inactive tiles display only text
                  // but keep internal padding so content doesn't touch edges.
                  if (isSelected) ...[
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        icon ?? _getCategoryIcon(categoryId),
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Category name (row layout)
                  Flexible(
                    child: Text(
                      label,
                      style: GoogleFonts.inter(
                        color: isSelected ? Colors.white : Colors.grey[800],
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
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
      case 'transportation':
        return Icons.directions_car;
      case 'healthcare':
        return Icons.medical_services;
      case 'education':
        return Icons.school;
      case 'shopping':
        return Icons.shopping_bag;
      case 'insurance':
        return Icons.security;
      case 'subscriptions':
        return Icons.subscriptions;
      case 'other':
        return Icons.more_horiz;
      default:
        return Icons.category;
    }
  }
}