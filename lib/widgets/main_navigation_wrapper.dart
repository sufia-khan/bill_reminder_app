import 'package:flutter/material.dart';
import 'package:projeckt_k/screens/all_bills_screen.dart';
import 'package:projeckt_k/screens/home_screen.dart';
import 'package:projeckt_k/screens/analytics_screen.dart';
import 'package:projeckt_k/screens/settings_screen.dart';
import 'package:projeckt_k/services/sync_notification_service.dart';

class MainNavigationWrapper extends StatefulWidget {
  final SyncNotificationService? syncService;

  const MainNavigationWrapper({super.key, this.syncService});

  @override
  State<MainNavigationWrapper> createState() => _MainNavigationWrapperState();
}

class _MainNavigationWrapperState extends State<MainNavigationWrapper> {
  late final SyncNotificationService _syncService =
      widget.syncService ?? SyncNotificationService();

  int _currentIndex = 0;
  final GlobalKey<HomeScreenState> _homeScreenKey =
      GlobalKey<HomeScreenState>();

  @override
  void initState() {
    super.initState();
    _syncService.init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncService.setContext(context);
  }

  late final List<Widget> _screens = [
    HomeScreen(
      key: _homeScreenKey,
      onNavigateToSettings: () => setState(() => _currentIndex = 4),
      onNavigateToReminders: () {
        // TODO: Navigate to reminder screen when implemented
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reminder screen coming soon!'),
            duration: Duration(seconds: 2),
          ),
        );
      },
    ),
    AnalyticsScreen(),
    Container(), // Placeholder for index 2 (Add Bill - uses bottom sheet)
    AllBillsScreen(),
    SettingsScreen(
      onDataCleared: () {
        // Refresh home screen data when cleared
        _homeScreenKey.currentState?.refreshData();
        // Switch back to home screen
        setState(() => _currentIndex = 0);
      },
    ),
  ];
  // gradient for icons & active labels
  List<Color> get _iconGradientColors => [
    HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor(), // Lighter purple HSL(236, 89%, 65%)
    HSLColor.fromAHSL(1.0, 236, 0.89, 0.75).toColor(), // Light purple HSL(236, 89%, 75%)
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      extendBody: true,
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white, // nav bar background
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: _iconGradientColors.first.withValues(alpha: 0.18),
              blurRadius: 18,
              spreadRadius: 1,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(Icons.home, 0, "Home"),
            _buildNavItem(Icons.analytics_sharp, 1, "Analytics"),

            // Floating Add Button
            GestureDetector(
              onTap: () {
                if (_currentIndex == 0) {
                  _homeScreenKey.currentState?.showAddBillFullScreen(context);
                } else {
                  setState(() => _currentIndex = 0);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _homeScreenKey.currentState?.showAddBillFullScreen(
                      context,
                    );
                  });
                }
              },
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _iconGradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _iconGradientColors.first.withValues(alpha: 0.25),
                      blurRadius: 16,
                      spreadRadius: 2,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(Icons.add, size: 28, color: Colors.white),
              ),
            ),

            _buildNavItem(Icons.receipt_long, 3, "Calender"),
            _buildNavItem(Icons.settings, 4, "Settings"),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, int index, String label) {
    final bool isActive = _currentIndex == index;

    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: isActive
                  ? Border.all(
                      color: _iconGradientColors.first.withValues(alpha: 0.45),
                      width: 1.2,
                    )
                  : null,
            ),
            child: ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => LinearGradient(
                colors: _iconGradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ).createShader(bounds),
              child: Icon(icon, size: 24, color: Colors.white),
            ),
          ),
          const SizedBox(height: 4),
          isActive
              ? ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (bounds) => LinearGradient(
                    colors: _iconGradientColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(bounds),
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade500,
                  ),
                ),
        ],
      ),
    );
  }
}
