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

    // ↓ More compact (extra -10%)
    this.topBoxHeight = 2,
    this.middleBoxHeight = 18, // was 20 → -10%
    this.bottomBoxHeight = 10, // was 11 → -10%
    // Font sizes
    this.primaryFontSize = 24, // keep mid value same
    this.minPrimaryFontSize = 10,
    this.bottomAmountFontSize = 8,
    this.bottomTextFontSize = 8,
    this.minBottomFontSize = 7,

    this.innerPadding = const EdgeInsets.symmetric(horizontal: 6, vertical: 3),

    // ↓ Icon smaller (used in _topRow via constant 25.0 previously)
    this.iconSize = 18,
    this.iconOnRight = false,
    this.textIconGap = 6,
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

  // ----------------------
  Widget _topRow() {
    final iconWidget = Icon(
      icon,
      color: Colors.white,
      size: 25.0, // kept same visual weight as before
    );

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

  /// Bottom widget: If both secondaryAmount & secondaryText present -> always two lines.
  /// If only one present -> single line left-aligned and vertically centered within the outer bottom box.
  Widget _buildBottom(double widthAvailable) {
    final hasAmount = (secondaryAmount?.trim().isNotEmpty ?? false);
    final hasText = (secondaryText?.trim().isNotEmpty ?? false);

    if (hasAmount && hasText) {
      // Two-line bottom: amount (bold) then descriptor (regular).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Amount line - bold
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
          const SizedBox(height: 2),
          // Descriptor line - normal
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

    // Single line present (either amount or text).
    final single = (hasAmount
        ? secondaryAmount!
        : (hasText ? secondaryText! : ''));
    if (single.isEmpty) return const SizedBox.shrink();

    // Return just the aligned text (outer SizedBox supplies the height)
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
    // previous scale was 0.9 (we reduced by 10% earlier).
    // Now reduce another 10% from that state → net scale = 0.9 * 0.9 = 0.81
    const double netScale = 0.9 * 0.9; // 0.81

    // scaled section heights
    final double topH = topBoxHeight * netScale;
    final double midH = middleBoxHeight * netScale;
    final double bottomH = bottomBoxHeight * netScale;

    // scale inner padding proportionally
    final EdgeInsets scaledInnerPadding = EdgeInsets.fromLTRB(
      innerPadding.left * netScale,
      innerPadding.top * netScale,
      innerPadding.right * netScale,
      innerPadding.bottom * netScale,
    );

    // Enforce uniform minimum padding on all sides.
    // Minimum per-side padding = 12.0 (so all sides are same and noticeably padded)
    final double perSidePad = math.max(
      12.0,
      math.max(
        math.max(scaledInnerPadding.left, scaledInnerPadding.top),
        math.max(scaledInnerPadding.right, scaledInnerPadding.bottom),
      ),
    );

    final EdgeInsets finalInnerPadding = EdgeInsets.all(perSidePad);

    // compute total height (small safe buffer)
    final totalHeight =
        topH +
        midH +
        bottomH +
        finalInnerPadding.top +
        finalInnerPadding.bottom +
        5;

    final textColumn = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row - title + icon (scaled height)
          SizedBox(
            height: topH,
            child: Align(alignment: Alignment.centerLeft, child: _topRow()),
          ),

          // Middle - primary value (height scaled, font NOT changed)
          SizedBox(
            height: midH,
            child: Align(
              alignment: Alignment.centerLeft,
              child: AutoSizeText(
                primaryValue,
                textAlign: TextAlign.left,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: primaryFontSize, // <-- kept the same as requested
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                minFontSize: minPrimaryFontSize,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          // Bottom - single/two-line (outer height scaled)
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
      padding: finalInnerPadding, // <-- uniform padding all sides
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
        children: [
          // single column (icon lives inside topRow)
          textColumn,
        ],
      ),
    );
  }
}
