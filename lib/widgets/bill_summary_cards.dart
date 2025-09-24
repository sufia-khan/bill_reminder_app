// bill_summary_card_icon_with_title_fixed_bottom.dart
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
    // layout heights
    this.topBoxHeight = 36,
    this.middleBoxHeight = 70,
    this.bottomBoxHeight = 45,
    // font sizing
    this.primaryFontSize = 36,
    this.minPrimaryFontSize = 8,
    this.bottomAmountFontSize = 12,
    this.bottomTextFontSize = 13,
    this.minBottomFontSize = 10,
    // inner padding (space INSIDE the card between border and content)
    this.innerPadding = const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 16,
    ),
    // icon + misc
    this.iconSize = 36,
    this.iconOnRight = false,
    this.textIconGap = 6,
  }) : assert(gradientColors.length >= 2),
       super(key: key);

  final String title;
  final IconData icon;
  final List<Color> gradientColors;
  final String primaryValue;
  final String? secondaryAmount; // e.g. "$12.34"
  final String? secondaryText; // e.g. "more than last month"

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

  Widget _topRow() {
    final iconWidget = Container(
      width: iconSize,
      height: iconSize,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: Colors.white, size: iconSize * 0.55),
    );

    final titleWidget = AutoSizeText(
      title,
      textAlign: TextAlign.left,
      style: GoogleFonts.poppins(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      maxLines: 1,
      minFontSize: 10,
      overflow: TextOverflow.ellipsis,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: iconOnRight
          ? [
              Expanded(child: titleWidget),
              SizedBox(width: textIconGap),
              iconWidget,
            ]
          : [
              iconWidget,
              SizedBox(width: textIconGap),
              Expanded(child: titleWidget),
            ],
    );
  }

  /// Bottom widget: If both secondaryAmount & secondaryText present -> always two lines.
  /// If only one present -> single line left-aligned and vertically centered within bottomBoxHeight.
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

    // LEFT-align single-line content, vertically centered inside bottom area.
    return SizedBox(
      height: bottomBoxHeight,
      child: Align(
        alignment: Alignment.centerLeft, // left aligned now
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // total height must account for innerPadding vertical space
    final totalHeight =
        topBoxHeight +
        middleBoxHeight +
        bottomBoxHeight +
        innerPadding.top +
        innerPadding.bottom;

    final textColumn = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row - title + icon
          SizedBox(
            height: topBoxHeight,
            child: Align(alignment: Alignment.centerLeft, child: _topRow()),
          ),

          // Middle - primary value
          SizedBox(
            height: middleBoxHeight,
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

          // Bottom - either two-line (always for This Month when both provided) or single-line left-aligned
          SizedBox(
            height: bottomBoxHeight,
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
      padding: innerPadding, // <<-- inner padding applied here
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
