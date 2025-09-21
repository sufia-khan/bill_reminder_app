import 'dart:math';
import 'package:flutter/material.dart';
import 'package:projeckt_k/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

final Color kPrimaryColor = HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor();

class GridPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Draw subtle grid pattern
    for (int i = 0; i < size.width; i += 8) {
      canvas.drawLine(Offset(i.toDouble(), 0), Offset(i.toDouble(), size.height), paint);
    }
    for (int i = 0; i < size.height; i += 8) {
      canvas.drawLine(Offset(0, i.toDouble()), Offset(size.width, i.toDouble()), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      User? user;
      if (_isLogin) {
        user = await _authService.signInWithEmailAndPassword(
          _emailController.text,
          _passwordController.text,
        );
      } else {
        user = await _authService.registerWithEmailAndPassword(
          _emailController.text,
          _passwordController.text,
        );
      }

      if (user != null && mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _toggleMode() {
    setState(() {
      _isLogin = !_isLogin;
      _errorMessage = null;
      _formKey.currentState?.reset();
      _emailController.clear();
      _passwordController.clear();
    });
  }

  Widget _buildBackgroundIcons(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    List<IconData> icons = [
      Icons.subscriptions,
      Icons.notifications_active,
      Icons.credit_card,
      Icons.access_time,
      Icons.event_available,
      Icons.alarm,
      Icons.receipt_long,
      Icons.payment,
      Icons.calendar_today,
      Icons.notifications,
      Icons.schedule,
      Icons.monetization_on,
      Icons.account_balance_wallet,
      Icons.timer,
      Icons.attach_money,
      Icons.card_membership,
      Icons.star,
      Icons.bookmark,
      Icons.subscriptions_outlined,
      Icons.wallet,
    ];

    List<Color> colors = [
      Colors.red.shade300,
      Colors.orange.shade300,
      Colors.yellow.shade400,
      Colors.green.shade400,
      Colors.blue.shade300,
      Colors.indigo.shade300,
      Colors.purple.shade300,
      Colors.pink.shade300,
      Colors.red.shade400,
      Colors.orange.shade400,
      Colors.yellow.shade300,
      Colors.green.shade300,
      Colors.blue.shade400,
      Colors.indigo.shade400,
      Colors.purple.shade400,
    ];

    List<Widget> iconWidgets = [];

    // Generate 25 randomly positioned icons to ensure full coverage
    for (int i = 0; i < 25; i++) {
      final random = Random(i + 42); // Seeded for consistent random positions
      final icon = icons[random.nextInt(icons.length)];
      final color = colors[random.nextInt(colors.length)];
      final size = 30 + random.nextInt(20); // Size between 30-50
      final top = random.nextDouble() * (screenHeight + 100) - 50; // Allow icons slightly off-screen
      final left = random.nextDouble() * (screenWidth + 100) - 50; // Allow icons slightly off-screen

      iconWidgets.add(
        Positioned(
          top: top,
          left: left,
          child: Icon(icon, size: size.toDouble(), color: color),
        ),
      );
    }

    return Stack(children: iconWidgets);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
        ),
        child: Stack(
          children: [
            // Colorful random subscription-themed background pattern
            Positioned.fill(
              child: Opacity(
                opacity: 0.35,
                child: _buildBackgroundIcons(context),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(32.0),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildLogoHeader(),
                          const SizedBox(height: 32),
                          _buildEmailField(),
                          const SizedBox(height: 16),
                          _buildPasswordField(),
                          const SizedBox(height: 24),
                          _buildSubmitButton(),
                          const SizedBox(height: 20),
                          _buildToggleLink(),
                          const SizedBox(height: 24),
                          _buildTermsAndConditions(),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 24),
                            _buildErrorMessage(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoHeader() {
    return Column(
      children: [
        // Professional bell icon logo
        Container(
          width: 85,
          height: 85,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                kPrimaryColor,
                kPrimaryColor.withValues(alpha: 0.8),
                kPrimaryColor.withValues(alpha: 0.6),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: kPrimaryColor.withValues(alpha: 0.3),
                blurRadius: 25,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Subtle background circle
              Container(
                width: 75,
                height: 75,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
              ),
              // Single bell icon
              Icon(
                Icons.notifications_active,
                size: 48,
                color: Colors.white,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'SubManager',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: kPrimaryColor,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _isLogin ? 'Welcome Back!' : 'Create Account',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: kPrimaryColor.withValues(alpha: 0.8),
              ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            _isLogin
                ? 'Smart subscription management made simple'
                : 'Take control of your subscriptions today',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: kPrimaryColor.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500,
                ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextFormField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        style: const TextStyle(color: Colors.black),
        decoration: InputDecoration(
          labelText: 'Email',
          prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF1976D2), size: 22),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: kPrimaryColor.withValues(alpha: 0.6), width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: kPrimaryColor.withValues(alpha: 0.6), width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: kPrimaryColor, width: 2),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          labelStyle: TextStyle(color: kPrimaryColor.withValues(alpha: 0.8), fontWeight: FontWeight.w500),
          floatingLabelStyle: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.w600),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please enter your email';
          }
          if (!AuthService.isValidEmail(value)) {
            return 'Please enter a valid email';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildPasswordField() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withValues(alpha: 0.2),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextFormField(
        controller: _passwordController,
        obscureText: _obscurePassword,
        style: const TextStyle(color: Colors.black),
        decoration: InputDecoration(
          labelText: 'Password',
          prefixIcon: const Icon(Icons.lock_outlined, color: Color(0xFF1976D2), size: 22),
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              color: kPrimaryColor.withValues(alpha: 0.7),
              size: 20,
            ),
            onPressed: () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: kPrimaryColor.withValues(alpha: 0.6), width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: kPrimaryColor.withValues(alpha: 0.6), width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: kPrimaryColor, width: 2),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          labelStyle: TextStyle(color: kPrimaryColor.withValues(alpha: 0.8), fontWeight: FontWeight.w500),
          floatingLabelStyle: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.w600),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please enter your password';
          }
          if (!AuthService.isValidPassword(value)) {
            return 'Password must be at least 6 characters';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submitForm,
        style: ElevatedButton.styleFrom(
          backgroundColor: kPrimaryColor,
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: kPrimaryColor.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                _isLogin ? 'Sign In' : 'Sign Up',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildToggleLink() {
    return TextButton(
      onPressed: _toggleMode,
      child: Text.rich(
        TextSpan(
          text: _isLogin ? "Don't have an account? " : "Already have an account? ",
          style: TextStyle(color: Colors.grey[600]),
          children: [
            TextSpan(
              text: _isLogin ? 'Sign Up' : 'Sign In',
              style: TextStyle(
                color: Theme.of(context).primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTermsAndConditions() {
    return Text.rich(
      TextSpan(
        text: 'By continuing, you agree to our ',
        style: TextStyle(
          color: Colors.grey[600],
          fontSize: 12,
        ),
        children: [
          TextSpan(
            text: 'Terms and Conditions',
            style: TextStyle(
              color: kPrimaryColor,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.underline,
            ),
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: TextStyle(
              color: kPrimaryColor,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.underline,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Colors.red[700]),
            ),
          ),
        ],
      ),
    );
  }
}