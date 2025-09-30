import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SummaryInformationBar extends StatelessWidget {
  final int billCount;
  final double totalAmount;

  const SummaryInformationBar({
    Key? key,
    required this.billCount,
    required this.totalAmount,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left side - Bill count (font size matched to total amount on the right)
          Text(
            '$billCount bills',
            style: GoogleFonts.inter(
              color: const Color(0xFF1F2937),
              fontWeight: FontWeight.w600,
              fontSize: 18,
              letterSpacing: -0.25,
            ),
          ),

          // Right side - Total amount
          Text(
            '\$${totalAmount.toStringAsFixed(2)}',
            style: GoogleFonts.inter(
              color: const Color(0xFF1F2937),
              fontWeight: FontWeight.w700,
              fontSize: 18,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}