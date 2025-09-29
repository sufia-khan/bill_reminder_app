// Enhanced modern bill summary card with glassmorphism and improved design
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:google_fonts/google_fonts.dart';

class BillSummaryCard extends StatelessWidget {
  const BillSummaryCard({
    super.key,
    required this.title,
    required this.icon,
    required this.gradientColors,
    required this.primaryValue,
    this.secondaryAmount,
    this.secondaryText,

    // Box section heights - reduced for compact layout
    this.topBoxHeight = 1.5,
    this.middleBoxHeight = 12,
    this.bottomBoxHeight = 7,

    // Font sizes - reduced for compact layout
    this.primaryFontSize = 20,
    this.minPrimaryFontSize = 9,
    this.bottomAmountFontSize = 6,
    this.bottomTextFontSize = 6,
    this.minBottomFontSize = 5,

    // Reduced padding for compact layout
    this.innerPadding = const EdgeInsets.symmetric(horizontal: 4, vertical: 2),

    // Icon configs - slightly reduced
    this.iconSize = 16,
    this.iconOnRight = false,
    this.textIconGap = 4,

    // Reduced bottom height boost
    this.bottomHeightBoost = 4,

    // Remove card appearance
    this.removeCardStyle = false,
  }) : assert(gradientColors.length >= 2);

  final String title;
  final IconData icon;
  final List<Color> gradientColors;
  final String primaryValue;
  final String? secondaryAmount;
  final String? secondaryText;

  final double topBoxHeight;
  final double middleBoxHeight;
  final double bottomBoxHeight;
  final bool removeCardStyle;

  final double primaryFontSize;
  final double minPrimaryFontSize;
  final double bottomAmountFontSize;
  final double bottomTextFontSize;
  final double minBottomFontSize;

  final EdgeInsets innerPadding;
  final double iconSize;
  final bool iconOnRight;
  final double textIconGap;

  final double bottomHeightBoost; // new field

  // ----------------------
  Widget _topRow() {
    final iconWidget = Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: Colors.white, size: iconSize),
    );

    final titleWidget = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: AutoSizeText(
        title,
        textAlign: TextAlign.left,
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        maxLines: 1,
        minFontSize: 9,
        overflow: TextOverflow.ellipsis,
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: iconOnRight
          ? [titleWidget, SizedBox(width: textIconGap), iconWidget]
          : [iconWidget, SizedBox(width: textIconGap), titleWidget],
    );
  }

  /// Bottom widget
  Widget _buildBottom(double widthAvailable) {
    final hasAmount = (secondaryAmount?.trim().isNotEmpty ?? false);
    final hasText = (secondaryText?.trim().isNotEmpty ?? false);

    // Always use a Column with consistent spacing to ensure equal height
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasAmount)
          AutoSizeText(
            secondaryAmount!,
            textAlign: TextAlign.left,
            style: GoogleFonts.poppins(
              fontSize: bottomAmountFontSize,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            maxLines: 1,
            minFontSize: minBottomFontSize,
            overflow: TextOverflow.ellipsis,
          )
        else if (hasText)
          // When there's only text, we still want it to look like an amount
          AutoSizeText(
            secondaryText!,
            textAlign: TextAlign.left,
            style: GoogleFonts.poppins(
              fontSize: bottomAmountFontSize,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            maxLines: 1,
            minFontSize: minBottomFontSize,
            overflow: TextOverflow.ellipsis,
          ),

        if (hasAmount && hasText)
          AutoSizeText(
            secondaryText!,
            textAlign: TextAlign.left,
            style: GoogleFonts.poppins(
              fontSize: bottomTextFontSize,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
            ),
            maxLines: 1,
            minFontSize: minBottomFontSize,
            overflow: TextOverflow.ellipsis,
          )
        // No empty space needed - height consistency is handled in the main calculation
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const double netScale = 0.75 * 0.75; // ultra-compact scaling

    final double topH = topBoxHeight * netScale;
    final double midH = middleBoxHeight * netScale;
    final double baseBottomH = bottomBoxHeight * netScale;

    final EdgeInsets scaledInnerPadding = EdgeInsets.fromLTRB(
      innerPadding.left * netScale,
      innerPadding.top * netScale,
      innerPadding.right * netScale,
      innerPadding.bottom * netScale,
    );

    final double perSidePad = math.max(
      8.0,
      math.max(
        math.max(scaledInnerPadding.left, scaledInnerPadding.top),
        math.max(scaledInnerPadding.right, scaledInnerPadding.bottom),
      ),
    );
    final EdgeInsets finalInnerPadding = EdgeInsets.all(perSidePad);

    final bool hasAmount = (secondaryAmount?.trim().isNotEmpty ?? false);
    final bool hasText = (secondaryText?.trim().isNotEmpty ?? false);

    const double lineHeightFactor = 1.15;
    const double bottomSpacing = 2.0;
    double requiredBottomH;
    if (hasAmount && hasText) {
      requiredBottomH =
          (bottomAmountFontSize + bottomTextFontSize) * lineHeightFactor + bottomSpacing;
    } else if (hasAmount || hasText) {
      // For single-line content, calculate height as if there were two lines
      // This ensures consistent height regardless of content
      requiredBottomH = (bottomAmountFontSize + bottomTextFontSize) * lineHeightFactor + bottomSpacing;
    } else {
      requiredBottomH = 0.0;
    }

    double bottomH = math.max(baseBottomH, requiredBottomH);

    // 🔹 add boost only to bottom box
    bottomH += bottomHeightBoost;

    const double safeBuffer = 2.0;
    final double totalHeight =
        topH +
        midH +
        bottomH +
        finalInnerPadding.top +
        finalInnerPadding.bottom +
        safeBuffer;

    final textColumn = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: topH,
            child: Align(alignment: Alignment.centerLeft, child: _topRow()),
          ),
          SizedBox(
            height: midH,
            child: Align(
              alignment: Alignment.centerLeft,
              child: AutoSizeText(
                primaryValue,
                textAlign: TextAlign.left,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: primaryFontSize,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                minFontSize: minPrimaryFontSize,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          SizedBox(
            height: bottomH,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 2.0),
                    child: _buildBottom(constraints.maxWidth),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    return Container(
      height: totalHeight,
      padding: finalInnerPadding,
      decoration: removeCardStyle
          ? null
          : BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: gradientColors.first.withValues(alpha: 0.10),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [textColumn],
      ),
    );
  }
}
