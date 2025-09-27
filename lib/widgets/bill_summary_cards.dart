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
    this.middleBoxHeight = 17,
    this.bottomBoxHeight = 9,

    // Font sizes
    this.primaryFontSize = 24,
    this.minPrimaryFontSize = 10,
    this.bottomAmountFontSize = 7,
    this.bottomTextFontSize = 7,
    this.minBottomFontSize = 6,

    this.innerPadding = const EdgeInsets.symmetric(horizontal: 6, vertical: 3),

    // Icon configs
    this.iconSize = 18,
    this.iconOnRight = false,
    this.textIconGap = 6,

    // NEW → extra boost for bottom box only
    this.bottomHeightBoost = 6,
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
    final iconWidget = Icon(icon, color: Colors.white, size: 25.0);

    final titleWidget = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: AutoSizeText(
        title,
        textAlign: TextAlign.left,
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        minFontSize: 10,
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
              color: Colors.white,
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
              color: Colors.white70,
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
          color: hasAmount ? Colors.white : Colors.white70,
        ),
        maxLines: 1,
        minFontSize: minBottomFontSize,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const double netScale = 0.85 * 0.85; // compact scaling

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

    const double safeBuffer = 3.0;
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

    return Container(
      height: totalHeight,
      padding: finalInnerPadding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withOpacity(0.10),
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
