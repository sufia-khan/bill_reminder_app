// bill_summary_card_icon_with_title_fixed_bottom.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:google_fonts/google_fonts.dart';

class BillSummaryCard extends StatelessWidget {
  const BillSummaryCard({
    Key? key,
    required this.title,
    required this.icon,
    required this.gradientColors,
    required this.primaryValue,
    this.secondaryAmount,
    this.secondaryText,

    // Box section heights
    this.topBoxHeight = 2,
    this.middleBoxHeight = 12,
    this.bottomBoxHeight = 6,

    // Font sizes
    this.primaryFontSize = 20,
    this.minPrimaryFontSize = 8,
    this.bottomAmountFontSize = 6,
    this.bottomTextFontSize = 6,
    this.minBottomFontSize = 5,

    this.innerPadding = const EdgeInsets.symmetric(horizontal: 4, vertical: 2),

    // Icon configs
    this.iconSize = 16,
    this.iconOnRight = false,
    this.textIconGap = 4,

    // NEW → extra boost for bottom box only
    this.bottomHeightBoost = 4,
  }) : assert(gradientColors.length >= 2),
       super(key: key);

  final String title;
  final IconData icon;
  final List<Color> gradientColors;
  final String primaryValue;
  final String? secondaryAmount;
  final String? secondaryText;

  final double topBoxHeight;
  final double middleBoxHeight;
  final double bottomBoxHeight;

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
    final isWhiteCard = gradientColors.every((color) => color == Colors.white);

    final iconWidget = Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isWhiteCard ? HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor().withValues(alpha: 0.1) : Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: isWhiteCard ? HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor() : Colors.white, size: iconSize),
    );

    final titleWidget = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isWhiteCard ? Colors.grey.shade100 : Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: AutoSizeText(
        title,
        textAlign: TextAlign.left,
        style: GoogleFonts.poppins(
          color: isWhiteCard ? Colors.grey.shade700 : Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        minFontSize: 8,
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
    final isWhiteCard = gradientColors.every((color) => color == Colors.white);
    final hasAmount = (secondaryAmount?.trim().isNotEmpty ?? false);
    final hasText = (secondaryText?.trim().isNotEmpty ?? false);

    if (hasAmount && hasText) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AutoSizeText(
            secondaryAmount!,
            textAlign: TextAlign.left,
            style: GoogleFonts.poppins(
              fontSize: bottomAmountFontSize,
              fontWeight: FontWeight.bold,
              color: isWhiteCard ? Colors.grey.shade700 : Colors.white,
            ),
            maxLines: 1,
            minFontSize: minBottomFontSize,
            overflow: TextOverflow.ellipsis,
          ),
          AutoSizeText(
            secondaryText!,
            textAlign: TextAlign.left,
            style: GoogleFonts.poppins(
              fontSize: bottomTextFontSize,
              fontWeight: FontWeight.w500,
              color: isWhiteCard ? Colors.grey.shade500 : Colors.white70,
            ),
            maxLines: 1,
            minFontSize: minBottomFontSize,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }

    final single = (hasAmount
        ? secondaryAmount!
        : (hasText ? secondaryText! : ''));
    if (single.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: AutoSizeText(
        single,
        textAlign: TextAlign.left,
        style: GoogleFonts.poppins(
          fontSize: bottomAmountFontSize,
          fontWeight: hasAmount ? FontWeight.bold : FontWeight.w600,
          color: isWhiteCard ? (hasAmount ? Colors.grey.shade700 : Colors.grey.shade500) : (hasAmount ? Colors.white : Colors.white70),
        ),
        maxLines: 1,
        minFontSize: minBottomFontSize,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWhiteCard = gradientColors.every((color) => color == Colors.white);
    const double netScale = 0.75 * 0.75; // more compact scaling

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
      12.0,
      math.max(
        math.max(scaledInnerPadding.left, scaledInnerPadding.top),
        math.max(scaledInnerPadding.right, scaledInnerPadding.bottom),
      ),
    );
    final EdgeInsets finalInnerPadding = EdgeInsets.all(perSidePad);

    final bool hasAmount = (secondaryAmount?.trim().isNotEmpty ?? false);
    final bool hasText = (secondaryText?.trim().isNotEmpty ?? false);

    const double lineHeightFactor = 1.25;
    double requiredBottomH;
    if (hasAmount && hasText) {
      requiredBottomH =
          (bottomAmountFontSize + bottomTextFontSize) * lineHeightFactor + 2.0;
    } else if (hasAmount || hasText) {
      final double used = (hasAmount
          ? bottomAmountFontSize
          : bottomTextFontSize);
      requiredBottomH = used * lineHeightFactor + 2.0;
    } else {
      requiredBottomH = 0.0;
    }

    double bottomH = math.max(baseBottomH, requiredBottomH);

    // 🔹 add boost only to bottom box
    bottomH += bottomHeightBoost;

    const double safeBuffer = 1.0;
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
                  color: isWhiteCard ? Colors.grey.shade900 : Colors.white,
                  fontSize: primaryFontSize,
                  fontWeight: FontWeight.w700, // Slightly bolder for modern look
                  letterSpacing: -0.5, // Slight letter spacing for premium feel
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
                    padding: const EdgeInsets.only(right: 4.0),
                    child: _buildBottom(constraints.maxWidth),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {}, // Placeholder for future interaction
        splashFactory: InkRipple.splashFactory,
        splashColor: Colors.white.withOpacity(0.1),
        highlightColor: Colors.white.withOpacity(0.05),
        child: Container(
          height: totalHeight,
          padding: finalInnerPadding,
          decoration: BoxDecoration(
            gradient: isWhiteCard ? null : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
            color: isWhiteCard ? Colors.white : null,
            border: isWhiteCard ? Border.all(
              color: title == "This Month"
                ? HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor().withValues(alpha: 0.3)
                : HSLColor.fromAHSL(1.0, 25, 0.90, 0.60).toColor().withValues(alpha: 0.3),
              width: 1.5,
            ) : null,
            borderRadius: BorderRadius.circular(16), // Slightly more rounded for modern look
            boxShadow: [
              BoxShadow(
                color: isWhiteCard
                  ? Colors.grey.shade300.withOpacity(0.3)
                  : gradientColors.first.withValues(alpha: 0.15), // Increased opacity for better shadow
                blurRadius: 12, // Increased blur for softer shadow
                offset: const Offset(0, 6), // Slightly increased offset
              ),
              BoxShadow(
                color: isWhiteCard
                  ? Colors.grey.shade200.withOpacity(0.1)
                  : gradientColors.first.withValues(alpha: 0.05), // Additional subtle shadow
                blurRadius: 20,
                offset: const Offset(0, 2),
                spreadRadius: -2,
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [textColumn],
          ),
        ),
      ),
    );
  }
}
