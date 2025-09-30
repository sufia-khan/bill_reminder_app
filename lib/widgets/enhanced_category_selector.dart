import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:projeckt_k/models/category_model.dart';

// Modern Material Design 3 color scheme
class ModernCategoryColors {
  static const Map<String, Map<String, Color>> categoryColorScheme = {
    'subscription': {
      'primary': Color(0xFF6750A4),
      'surface': Color(0xFFF7F2FA),
      'onSurface': Color(0xFF49454F),
    },
    'rent': {
      'primary': Color(0xFF00BFA5),
      'surface': Color(0xFFE0F2F1),
      'onSurface': Color(0xFF004D40),
    },
    'internet': {
      'primary': Color(0xFF1976D2),
      'surface': Color(0xFFE3F2FD),
      'onSurface': Color(0xFF0D47A1),
    },
    'education': {
      'primary': Color(0xFFFF9800),
      'surface': Color(0xFFFFF3E0),
      'onSurface': Color(0xFFE65100),
    },
    'utilities': {
      'primary': Color(0xFF607D8B),
      'surface': Color(0xFFECEFF1),
      'onSurface': Color(0xFF37474F),
    },
    'insurance': {
      'primary': Color(0xFFE53935),
      'surface': Color(0xFFFFEBEE),
      'onSurface': Color(0xFFB71C1C),
    },
    'transport': {
      'primary': Color(0xFF43A047),
      'surface': Color(0xFFE8F5E8),
      'onSurface': Color(0xFF1B5E20),
    },
    'entertainment': {
      'primary': Color(0xFF8E24AA),
      'surface': Color(0xFFF3E5F5),
      'onSurface': Color(0xFF4A148C),
    },
    'food': {
      'primary': Color(0xFFFF6F00),
      'surface': Color(0xFFFFF8E1),
      'onSurface': Color(0xFFE65100),
    },
    'shopping': {
      'primary': Color(0xFFEC407A),
      'surface': Color(0xFFFCE4EC),
      'onSurface': Color(0xFF880E4F),
    },
    'health': {
      'primary': Color(0xFF039BE5),
      'surface': Color(0xFFE1F5FE),
      'onSurface': Color(0xFF01579B),
    },
    'fitness': {
      'primary': Color(0xFF00ACC1),
      'surface': Color(0xFFE0F7FA),
      'onSurface': Color(0xFF006064),
    },
    'other': {
      'primary': Color(0xFF78909C),
      'surface': Color(0xFFECEFF1),
      'onSurface': Color(0xFF455A64),
    },
    'all': {
      'primary': Color(0xFF5E35B1),
      'surface': Color(0xFFEDE7F6),
      'onSurface': Color(0xFF311B92),
    },
  };

  static Color getCategoryColor(String categoryId, String type) {
    final colors = categoryColorScheme[categoryId] ?? categoryColorScheme['other']!;
    return colors[type] ?? colors['primary']!;
  }
}

class EnhancedCategorySelector extends StatefulWidget {
  final List<Map<String, dynamic>> bills;
  final Function(String) onCategorySelected;
  final String? initialCategory;
  final bool showBillCounts;
  final bool enableRippleEffect;

  const EnhancedCategorySelector({
    Key? key,
    required this.bills,
    required this.onCategorySelected,
    this.initialCategory,
    this.showBillCounts = true,
    this.enableRippleEffect = true,
  }) : super(key: key);

  @override
  State<EnhancedCategorySelector> createState() => _EnhancedCategorySelectorState();
}

class _EnhancedCategorySelectorState extends State<EnhancedCategorySelector>
    with TickerProviderStateMixin {
  late String _selectedCategory;
  late AnimationController _staggeredAnimationController;
  late List<Animation<double>> _itemAnimations;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory ?? 'all';

    // Staggered animation for items
    _staggeredAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    final categories = _buildCategoryList();
    _itemAnimations = List.generate(
      categories.length,
      (index) => Tween<double>(
        begin: 0.0,
        end: 1.0,
      ).animate(
        CurvedAnimation(
          parent: _staggeredAnimationController,
          curve: Interval(
            index * 0.1,
            (index + 1) * 0.1 + 0.4,
            curve: Curves.easeOutCubic,
          ),
        ),
      ),
    );

    // Start animation after widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _staggeredAnimationController.forward();
    });
  }

  @override
  void dispose() {
    _staggeredAnimationController.dispose();
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
      'billCount': billCounts['all'],
    });

    // Add predefined categories
    for (var category in Category.defaultCategories) {
      categories.add({
        'id': category.id,
        'name': category.name,
        'icon': category.icon,
        'billCount': billCounts[category.id],
      });
    }

    return categories;
  }

  @override
  Widget build(BuildContext context) {
    final categories = _buildCategoryList();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          // Elevation Level 3 - Material Design 3
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Modern header with gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor().withValues(alpha: 0.05),
                  HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor().withValues(alpha: 0.02),
                ],
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Row(
              children: [
                // Animated icon
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: Transform.rotate(
                        angle: (1 - value) * 0.5,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor(),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor().withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.category_rounded,
                            size: 24,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Category',
                      style: GoogleFonts.inter(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1F2937),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Choose a category to filter your bills',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF6B7280),
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Category pills with Material Design 3
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: categories.asMap().entries.map((entry) {
                final index = entry.key;
                final category = entry.value;

                return AnimatedBuilder(
                  animation: _itemAnimations[index],
                  builder: (context, child) {
                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.3),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: _itemAnimations[index],
                        curve: Curves.easeOutCubic,
                      )),
                      child: FadeTransition(
                        opacity: _itemAnimations[index],
                        child: Transform.scale(
                          scale: 0.9 + (_itemAnimations[index].value * 0.1),
                          child: _ModernCategoryPill(
                            categoryId: category['id'],
                            categoryName: category['name'],
                            categoryIcon: category['icon'],
                            isSelected: _selectedCategory == category['id'],
                            onTap: () {
                              setState(() {
                                _selectedCategory = category['id'];
                              });
                              widget.onCategorySelected(category['id']);
                            },
                            billCount: widget.showBillCounts ? category['billCount'] : null,
                            enableRipple: widget.enableRippleEffect,
                          ),
                        ),
                      ),
                    );
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModernCategoryPill extends StatefulWidget {
  final String categoryId;
  final String categoryName;
  final IconData categoryIcon;
  final bool isSelected;
  final VoidCallback onTap;
  final int? billCount;
  final bool enableRipple;

  const _ModernCategoryPill({
    required this.categoryId,
    required this.categoryName,
    required this.categoryIcon,
    required this.isSelected,
    required this.onTap,
    this.billCount,
    required this.enableRipple,
  });

  @override
  State<_ModernCategoryPill> createState() => _ModernCategoryPillState();
}

class _ModernCategoryPillState extends State<_ModernCategoryPill>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rippleAnimation;

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

    _rippleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.enableRipple) {
      _animationController.forward();
    }
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.enableRipple) {
      _animationController.reverse();
    }
    widget.onTap();
  }

  void _onTapCancel() {
    if (widget.enableRipple) {
      _animationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = ModernCategoryColors.getCategoryColor(widget.categoryId, 'primary');
    final surfaceColor = ModernCategoryColors.getCategoryColor(widget.categoryId, 'surface');
    final onSurfaceColor = ModernCategoryColors.getCategoryColor(widget.categoryId, 'onSurface');

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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                // Modern gradient for selected state
                gradient: widget.isSelected
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          primaryColor,
                          primaryColor.withValues(alpha: 0.85),
                        ],
                      )
                    : null,
                // Clean surface background
                color: widget.isSelected ? null : surfaceColor,

                // Material Design 3 rounded corners
                borderRadius: BorderRadius.circular(28),

                // Modern border styling
                border: Border.all(
                  color: widget.isSelected
                      ? primaryColor.withValues(alpha: 0.4)
                      : surfaceColor,
                  width: widget.isSelected ? 2.0 : 1.5,
                ),

                // Enhanced shadow system
                boxShadow: widget.isSelected
                    ? [
                        // Elevated shadow
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                          spreadRadius: 0,
                        ),
                        // Ambient shadow
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                          spreadRadius: -5,
                        ),
                      ]
                    : [
                        // Subtle ambient shadow
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Modern icon with animation
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: widget.isSelected
                          ? Colors.white.withValues(alpha: 0.25)
                          : primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: widget.isSelected
                            ? Colors.white.withValues(alpha: 0.4)
                            : primaryColor.withValues(alpha: 0.2),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      widget.categoryIcon,
                      size: 20,
                      color: widget.isSelected
                          ? Colors.white
                          : primaryColor,
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Modern typography
                  Flexible(
                    child: Text(
                      widget.categoryName,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: widget.isSelected
                            ? Colors.white
                            : onSurfaceColor,
                        letterSpacing: 0.1,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  // Modern bill count indicator
                  if (widget.billCount != null && widget.billCount! > 0) ...[
                    const SizedBox(width: 10),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: widget.isSelected
                            ? Colors.white.withValues(alpha: 0.2)
                            : primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: widget.isSelected
                              ? Colors.white.withValues(alpha: 0.3)
                              : primaryColor.withValues(alpha: 0.2),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        '${widget.billCount}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: widget.isSelected
                              ? Colors.white
                              : primaryColor,
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