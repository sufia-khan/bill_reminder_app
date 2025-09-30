import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:projeckt_k/models/category_model.dart';

class ModernCategoryCard extends StatefulWidget {
  final String categoryId;
  final String categoryName;
  final IconData categoryIcon;
  final Color categoryColor;
  final Color categoryBackgroundColor;
  final bool isSelected;
  final VoidCallback onTap;
  final int? billCount;

  const ModernCategoryCard({
    Key? key,
    required this.categoryId,
    required this.categoryName,
    required this.categoryIcon,
    required this.categoryColor,
    required this.categoryBackgroundColor,
    required this.isSelected,
    required this.onTap,
    this.billCount,
  }) : super(key: key);

  @override
  State<ModernCategoryCard> createState() => _ModernCategoryCardState();
}

class _ModernCategoryCardState extends State<ModernCategoryCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _elevationAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _elevationAnimation = Tween<double>(
      begin: widget.isSelected ? 8.0 : 2.0,
      end: widget.isSelected ? 12.0 : 6.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _animationController.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _animationController.reverse();
    widget.onTap();
  }

  void _onTapCancel() {
    _animationController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                // Modern gradient for selected state
                gradient: widget.isSelected
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          widget.categoryColor,
                          widget.categoryColor.withValues(alpha: 0.8),
                        ],
                      )
                    : null,
                // Clean background for unselected state
                color: widget.isSelected ? null : widget.categoryBackgroundColor.withValues(alpha: 0.1),

                // Rounded borders with modern styling
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: widget.isSelected
                      ? widget.categoryColor.withValues(alpha: 0.3)
                      : widget.categoryBackgroundColor.withValues(alpha: 0.4),
                  width: widget.isSelected ? 2.0 : 1.5,
                ),

                // Subtle shadow with animation
                boxShadow: [
                  BoxShadow(
                    color: widget.isSelected
                        ? widget.categoryColor.withValues(alpha: 0.25)
                        : Colors.black.withValues(alpha: 0.08),
                    blurRadius: _elevationAnimation.value,
                    offset: Offset(0, widget.isSelected ? 4 : 2),
                    spreadRadius: widget.isSelected ? 1 : 0,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Modern icon container
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: widget.isSelected
                          ? Colors.white.withValues(alpha: 0.2)
                          : widget.categoryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: widget.isSelected
                            ? Colors.white.withValues(alpha: 0.3)
                            : widget.categoryColor.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      widget.categoryIcon,
                      size: 18,
                      color: widget.isSelected
                          ? Colors.white
                          : widget.categoryColor,
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Category name with modern typography
                  Flexible(
                    child: Text(
                      widget.categoryName,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: widget.isSelected
                            ? Colors.white
                            : widget.categoryColor,
                        letterSpacing: 0.1,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Optional bill count indicator
                  if (widget.billCount != null && widget.billCount! > 0) ...[
                    const SizedBox(width: 8),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: widget.isSelected
                            ? Colors.white.withValues(alpha: 0.25)
                            : widget.categoryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: widget.isSelected
                              ? Colors.white.withValues(alpha: 0.3)
                              : widget.categoryColor.withValues(alpha: 0.2),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        '${widget.billCount}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: widget.isSelected
                              ? Colors.white
                              : widget.categoryColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class ModernCategorySelector extends StatefulWidget {
  final List<Map<String, dynamic>> bills;
  final Function(String) onCategorySelected;
  final String? initialCategory;

  const ModernCategorySelector({
    Key? key,
    required this.bills,
    required this.onCategorySelected,
    this.initialCategory,
  }) : super(key: key);

  @override
  State<ModernCategorySelector> createState() => _ModernCategorySelectorState();
}

class _ModernCategorySelectorState extends State<ModernCategorySelector>
    with TickerProviderStateMixin {
  late String _selectedCategory;
  late AnimationController _slideAnimationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory ?? 'all';

    _slideAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideAnimationController,
      curve: Curves.easeOutCubic,
    ));

    // Start animation after widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _slideAnimationController.forward();
    });
  }

  @override
  void dispose() {
    _slideAnimationController.dispose();
    super.dispose();
  }

  Map<String, int> _getBillCounts() {
    final Map<String, int> counts = {};

    // Initialize all categories with 0
    for (var category in Category.defaultCategories) {
      counts[category.id] = 0;
    }
    counts['all'] = widget.bills.length;

    // Count bills per category
    for (var bill in widget.bills) {
      final categoryId = bill['category']?.toString() ?? 'other';
      counts[categoryId] = (counts[categoryId] ?? 0) + 1;
    }

    return counts;
  }

  List<Map<String, dynamic>> _buildCategoryList() {
    final billCounts = _getBillCounts();
    final categories = <Map<String, dynamic>>[];

    // Add "All" option first
    categories.add({
      'id': 'all',
      'name': 'All Bills',
      'icon': Icons.dashboard_outlined,
      'color': HSLColor.fromAHSL(1.0, 220, 0.15, 0.45).toColor(),
      'backgroundColor': HSLColor.fromAHSL(1.0, 220, 0.15, 0.95).toColor(),
      'billCount': billCounts['all'],
    });

    // Add predefined categories
    for (var category in Category.defaultCategories) {
      categories.add({
        'id': category.id,
        'name': category.name,
        'icon': category.icon,
        'color': category.color,
        'backgroundColor': category.backgroundColor,
        'billCount': billCounts[category.id],
      });
    }

    return categories;
  }

  @override
  Widget build(BuildContext context) {
    final categories = _buildCategoryList();

    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
              spreadRadius: 0,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
              spreadRadius: 0,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Modern header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor().withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.category_outlined,
                      size: 20,
                      color: HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Categories',
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1F2937),
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),

            // Category chips with modern styling
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Wrap(
                spacing: 0,
                runSpacing: 8,
                children: categories.map((category) {
                  return ModernCategoryCard(
                    categoryId: category['id'],
                    categoryName: category['name'],
                    categoryIcon: category['icon'],
                    categoryColor: category['color'],
                    categoryBackgroundColor: category['backgroundColor'],
                    isSelected: _selectedCategory == category['id'],
                    onTap: () {
                      setState(() {
                        _selectedCategory = category['id'];
                      });
                      widget.onCategorySelected(category['id']);
                    },
                    billCount: category['billCount'],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}