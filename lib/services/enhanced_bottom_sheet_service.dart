import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:projeckt_k/models/category_model.dart';

class EnhancedBottomSheetService {
  // Show frequency bottom sheet with smooth animations
  static Future<String?> showFrequencyBottomSheet(
    BuildContext context,
    String currentFrequency,
  ) async {
    final frequencies = [
      'Weekly',
      'Bi-weekly',
      'Monthly',
      'Quarterly',
      'Semi-annually',
      'Annually',
      'One-time',
    ];

    return await _showEnhancedBottomSheet<String>(
      context: context,
      title: 'Select Frequency',
      child: _buildSelectionList(
        context: context,
        items: frequencies,
        selectedItem: currentFrequency,
        onTap: (item) => Navigator.pop(context, item),
      ),
    );
  }

  // Show reminder bottom sheet with smooth animations
  static Future<String?> showReminderBottomSheet(
    BuildContext context,
    String currentReminder,
  ) async {
    final reminders = [
      'Same day',
      '1 day before',
      '2 days before',
      '3 days before',
      '1 week before',
      '2 weeks before',
      '1 month before',
    ];

    return await _showEnhancedBottomSheet<String>(
      context: context,
      title: 'Select Reminder',
      child: _buildSelectionList(
        context: context,
        items: reminders,
        selectedItem: currentReminder,
        onTap: (item) => Navigator.pop(context, item),
      ),
    );
  }

  // Show category bottom sheet with smooth animations
  static Future<Category?> showCategoryBottomSheet(
    BuildContext context,
  ) async {
    return await _showEnhancedBottomSheet<Category>(
      context: context,
      title: 'Select Category',
      child: _buildCategoryList(
        context: context,
        categories: Category.defaultCategories,
        onTap: (category) => Navigator.pop(context, category),
      ),
    );
  }

  // Enhanced bottom sheet with smooth animations
  static Future<T?> _showEnhancedBottomSheet<T>({
    required BuildContext context,
    required String title,
    required Widget child,
  }) async {
    // Use the default modal bottom sheet animation controller provided by the
    // framework. Creating a controller here with an invalid vsync (Navigator)
    // caused runtime/type errors on some SDKs. If you need custom transition
    // timing, create and manage an AnimationController from a TickerProvider
    // (for example from a StatefulWidget) and pass it into
    // `showModalBottomSheet(..., transitionAnimationController: ...)` there.
    final result = await showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _EnhancedBottomSheet(
        title: title,
        child: child,
      ),
    );
    return result;
  }

  // Build selection list widget
  static Widget _buildSelectionList<T>({
    required BuildContext context,
    required List<T> items,
    required T selectedItem,
    required Function(T) onTap,
  }) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isSelected = item == selectedItem;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onTap(item),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.blue.withOpacity(0.1)
                      : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? Colors.blue
                        : Colors.grey[300]!,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.toString(),
                        style: TextStyle(
                          color: isSelected ? Colors.blue : Colors.black87,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (isSelected)
                      Icon(
                        Icons.check_circle,
                        color: Colors.blue,
                        size: 24,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Build category list widget
  static Widget _buildCategoryList({
    required BuildContext context,
    required List<Category> categories,
    required Function(Category) onTap,
  }) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onTap(category),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.grey[300]!,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: category.backgroundColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        category.icon,
                        color: category.color,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        category.name,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: Colors.grey,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// Enhanced bottom sheet widget with smooth animations
class _EnhancedBottomSheet extends StatefulWidget {
  final String title;
  final Widget child;

  const _EnhancedBottomSheet({
    required this.title,
    required this.child,
  });

  @override
  State<_EnhancedBottomSheet> createState() => _EnhancedBottomSheetState();
}

class _EnhancedBottomSheetState extends State<_EnhancedBottomSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInBack,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _closeBottomSheet() {
    HapticFeedback.lightImpact();
    _animationController.reverse().then((_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header with cross icon
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Handle bar
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        // Title
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        // Cross icon
                        GestureDetector(
                          onTap: _closeBottomSheet,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 18,
                                color: Colors.grey,
                              ),
                            ),
                        ),
                      ],
                    ),
                  ),
                  // Content
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 16),
                          widget.child,
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}