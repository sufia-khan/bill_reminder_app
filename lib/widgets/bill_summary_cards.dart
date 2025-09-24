// bill_summary_card_flexible.dart
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
    // fixed top & bottom box heights (middle becomes flexible)
    this.topBoxHeight = 44,
    this.bottomBoxHeight = 40,
    // font sizing
    this.bottomSingleLineFontSize = 18,
    this.minBottomLineFontSize = 10,
    this.primaryFontSize = 36,
    this.minPrimaryFontSize = 12,
    this.padding = 12,
    this.iconSize = 44,
    this.iconOnRight = true,
    this.textIconGap = 8,
  })  : assert(gradientColors.length >= 2),
        super(key: key);

  final String title;
  final IconData icon;
  final List<Color> gradientColors;
  final String primaryValue;
  final String? secondaryAmount;
  final String? secondaryText;

  final double topBoxHeight;
  final double bottomBoxHeight;

  final double bottomSingleLineFontSize;
  final double minBottomLineFontSize;
  final double primaryFontSize;
  final double minPrimaryFontSize;

  final double padding;
  final double iconSize;
  final bool iconOnRight;
  final double textIconGap;

  double _halfBottom() {
    final half = bottomSingleLineFontSize / 2;
    return half < minBottomLineFontSize ? minBottomLineFontSize : half;
  }

  Widget _buildBottomBox() {
    if ((secondaryAmount?.isEmpty ?? true) && (secondaryText?.isEmpty ?? true)) {
      return const SizedBox.shrink();
    }

    if ((secondaryAmount?.isNotEmpty ?? false) && (secondaryText?.isNotEmpty ?? false)) {
      final f1 = _halfBottom();
      final f2 = _halfBottom();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AutoSizeText(
            secondaryAmount!,
            textAlign: TextAlign.right,
            style: GoogleFonts.poppins(
              fontSize: f1,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            maxLines: 1,
            minFontSize: minBottomLineFontSize,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          AutoSizeText(
            secondaryText!,
            textAlign: TextAlign.right,
            style: GoogleFonts.poppins(
              fontSize: f2,
              fontWeight: FontWeight.w400,
              color: Colors.white70,
            ),
            maxLines: 2,
            minFontSize: minBottomLineFontSize,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }

    if ((secondaryText?.isNotEmpty ?? false)) {
      return AutoSizeText(
        secondaryText!,
        textAlign: TextAlign.right,
        style: GoogleFonts.poppins(
          fontSize: bottomSingleLineFontSize,
          fontWeight: FontWeight.w600,
          color: Colors.white70,
        ),
        maxLines: 2,
        minFontSize: minBottomLineFontSize,
        overflow: TextOverflow.ellipsis,
      );
    }

    return AutoSizeText(
      secondaryAmount ?? '',
      textAlign: TextAlign.right,
      style: GoogleFonts.poppins(
        fontSize: bottomSingleLineFontSize,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
      maxLines: 1,
      minFontSize: minBottomLineFontSize,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    // NOTE: we don't enforce a rigid total height here.
    // top & bottom boxes are fixed; middle area uses Expanded to adapt.
    final textColumn = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Top (title) fixed height
          SizedBox(
            height: topBoxHeight,
            child: Align(
              alignment: Alignment.centerRight,
              child: AutoSizeText(
                title,
                textAlign: TextAlign.right,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                minFontSize: 10,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          // Middle (primary) flexible — Expanded will shrink if parent doesn't have room
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: AutoSizeText(
                primaryValue,
                textAlign: TextAlign.right,
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

          // Bottom fixed height
          SizedBox(
            height: bottomBoxHeight,
            child: Align(
              alignment: Alignment.centerRight,
              child: _buildBottomBox(),
            ),
          ),
        ],
      ),
    );

    final iconWidget = Container(
      width: iconSize,
      height: iconSize,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: Colors.white, size: iconSize * 0.55),
    );

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: gradientColors.first.withOpacity(0.12), blurRadius: 10, offset: const Offset(0, 6))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: iconOnRight
            ? [textColumn, SizedBox(width: textIconGap), iconWidget]
            : [iconWidget, SizedBox(width: textIconGap), textColumn],
      ),
    );
  }
}
