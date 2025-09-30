import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:projeckt_k/widgets/enhanced_category_selector.dart';
import 'package:projeckt_k/widgets/modern_category_selector.dart';

// Example implementation showing how to integrate the modern category selector
class CategorySelectorExample extends StatefulWidget {
  const CategorySelectorExample({Key? key}) : super(key: key);

  @override
  State<CategorySelectorExample> createState() => _CategorySelectorExampleState();
}

class _CategorySelectorExampleState extends State<CategorySelectorExample> {
  String selectedCategory = 'all';

  // Sample bill data (replace with your actual data)
  final List<Map<String, dynamic>> sampleBills = [
    {'name': 'Netflix', 'amount': '15.99', 'category': 'entertainment'},
    {'name': 'Internet', 'amount': '59.99', 'category': 'internet'},
    {'name': 'Gym Membership', 'amount': '29.99', 'category': 'fitness'},
    {'name': 'Grocery Store', 'amount': '150.00', 'category': 'food'},
    {'name': 'Car Insurance', 'amount': '120.00', 'category': 'insurance'},
    {'name': 'Electric Bill', 'amount': '85.00', 'category': 'utilities'},
    {'name': 'Spotify', 'amount': '9.99', 'category': 'entertainment'},
    {'name': 'Rent', 'amount': '1200.00', 'category': 'rent'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Modern Category Selector',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            color: const Color(0xFF1F2937),
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section title
            Text(
              'Enhanced Category Selector',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 16),

            // Enhanced version with all features
            EnhancedCategorySelector(
              bills: sampleBills,
              initialCategory: selectedCategory,
              showBillCounts: true,
              enableRippleEffect: true,
              onCategorySelected: (categoryId) {
                setState(() {
                  selectedCategory = categoryId;
                });
                _showSelectedCategory(categoryId);
              },
            ),

            const SizedBox(height: 32),

            // Alternative modern version
            Text(
              'Alternative Modern Design',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 16),

            ModernCategorySelector(
              bills: sampleBills,
              initialCategory: selectedCategory,
              onCategorySelected: (categoryId) {
                setState(() {
                  selectedCategory = categoryId;
                });
                _showSelectedCategory(categoryId);
              },
            ),

            const SizedBox(height: 32),

            // Selected category display
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Currently Selected:',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    selectedCategory == 'all' ? 'All Bills' : selectedCategory,
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSelectedCategory(String categoryId) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Selected category: ${categoryId == 'all' ? 'All Bills' : categoryId}',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor(),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// Integration guide for replacing your existing SubscriptionFilterCard
class CategorySelectorIntegrationGuide {
  /*
   HOW TO REPLACE YOUR EXISTING SubscriptionFilterCard:

   1. In your home_screen.dart, replace this line:
      ```
      SubscriptionFilterCard(
        bills: _bills,
        initialCategory: selectedCategory,
        onFilterChanged: (category) {
          setState(() {
            selectedCategory = category;
          });
        },
      ),
      ```

   2. With either of these options:

   OPTION A - Enhanced Version (Recommended):
      ```
      EnhancedCategorySelector(
        bills: _bills,
        initialCategory: selectedCategory,
        showBillCounts: true, // Optional: show/hide bill counts
        enableRippleEffect: true, // Optional: enable/disable ripple animations
        onCategorySelected: (category) {
          setState(() {
            selectedCategory = category;
          });
        },
      ),
      ```

   OPTION B - Modern Version:
      ```
      ModernCategorySelector(
        bills: _bills,
        initialCategory: selectedCategory,
        onCategorySelected: (category) {
          setState(() {
            selectedCategory = category;
          });
        },
      ),
      ```

   3. Update the import statement at the top of home_screen.dart:
      ```
      import 'package:projeckt_k/widgets/enhanced_category_selector.dart';
      // OR
      import 'package:projeckt_k/widgets/modern_category_selector.dart';
      ```

   KEY IMPROVEMENTS:
   - ✅ Rounded borders (24-28px radius instead of sharp corners)
   - ✅ Removed summary section completely
   - ✅ Modern Material Design 3 color scheme
   - ✅ Smooth animations and transitions
   - ✅ Interactive feedback (ripple effects, scale animations)
   - ✅ Better spacing and typography
   - ✅ Bill count indicators (optional)
   - ✅ Staggered entry animations
   - ✅ Enhanced shadow system
   - ✅ Clean, minimalist approach
   */
}