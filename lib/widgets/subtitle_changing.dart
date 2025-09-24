import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ChangingSubtitle extends StatefulWidget {
  const ChangingSubtitle({super.key});

  @override
  State<ChangingSubtitle> createState() => _ChangingSubtitleState();
}

class _ChangingSubtitleState extends State<ChangingSubtitle> {
  final List<String> _subtitles = [
    "Never miss a due date again",
    "Stay on top of your payments",
    "Track, remind, and relax",
    "Bills, all in one place",
    "Smart reminders, stress-free",
    "Pay on time, every time",
    "Simplify your subscriptions",
    "No more late fees",
    "Plan smarter, live better",
    "All your bills, one app",
  ];

  String _currentSubtitle = "";
  late Timer _timer;
  int _subtitleIndex = 0;
  int _charIndex = 0;
  bool _isErasing = false;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  void _startTyping() {
    _timer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      final fullSubtitle = _subtitles[_subtitleIndex];

      setState(() {
        if (!_isErasing) {
          // Typing forward
          if (_charIndex < fullSubtitle.length) {
            _currentSubtitle += fullSubtitle[_charIndex];
            _charIndex++;
          } else {
            // Wait 1 sec, then start erasing
            _isErasing = true;
            _timer.cancel();
            Future.delayed(const Duration(seconds: 1), () {
              if (mounted) _startTyping();
            });
          }
        } else {
          // Erasing backward
          if (_charIndex > 0) {
            _currentSubtitle = fullSubtitle.substring(0, _charIndex - 1);
            _charIndex--;
          } else {
            // Done erasing → move to next subtitle
            _isErasing = false;
            _subtitleIndex = (_subtitleIndex + 1) % _subtitles.length;
            _timer.cancel();
            _startTyping();
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22, // slightly taller to fit 2 lines nicely
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          _currentSubtitle.isEmpty ? " " : _currentSubtitle,
          style: GoogleFonts.poppins(
            color: Colors.black54,  // slightly lighter than title
            fontSize: 14,           // smaller than main title
            fontWeight: FontWeight.w500,
            letterSpacing: -0.2,
            height: 1.3,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
