import 'package:flutter/material.dart';
import 'package:projeckt_k/screens/all_bills_screen.dart';
import 'package:projeckt_k/screens/home_screen.dart';
import 'package:projeckt_k/screens/analytics_screen.dart';
import 'package:projeckt_k/screens/add_bill_screen.dart';
import 'package:projeckt_k/screens/profile_screen.dart';
import 'package:projeckt_k/screens/settings_screen.dart';
import 'package:projeckt_k/services/sync_notification_service.dart';

class MainNavigationWrapper extends StatefulWidget {
  final SyncNotificationService syncService;

  const MainNavigationWrapper({Key? key, required this.syncService}) : super(key: key);

  @override
  State<MainNavigationWrapper> createState() => _MainNavigationWrapperState();
}

class _MainNavigationWrapperState extends State<MainNavigationWrapper> {
  int _currentIndex = 0;
  final GlobalKey<HomeScreenState> _homeScreenKey =
      GlobalKey<HomeScreenState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Update the sync service context when navigating
    widget.syncService.setContext(context);
  }

  late final List<Widget> _screens = [
    HomeScreen(key: _homeScreenKey),
    AnalyticsScreen(),
    HomeScreen(), // Placeholder for index 2 (Add Bill - uses bottom sheet)
    AllBillsScreen(),
    SettingsScreen(),
  ];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      extendBody: true,
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(
          vertical: 4,
          horizontal: 8,
        ), // 🔹 less vertical padding
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 2,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(Icons.home, 0, "Home"),
            _buildNavItem(Icons.analytics, 1, "Analytics"),

            // Floating center button
            GestureDetector(
              onTap: () {
                if (_currentIndex == 0) {
                  _homeScreenKey.currentState?.showAddBillBottomSheet(context);
                } else {
                  setState(() => _currentIndex = 0);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _homeScreenKey.currentState?.showAddBillBottomSheet(
                      context,
                    );
                  });
                }
              },
              child: Container(
                width: 54, // 🔹 smaller size
                height: 54,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      HSLColor.fromAHSL(1.0, 236, 0.89, 0.65).toColor(),
                      HSLColor.fromAHSL(1.0, 236, 0.89, 0.75).toColor(),
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: HSLColor.fromAHSL(
                        1.0,
                        236,
                        0.89,
                        0.65,
                      ).toColor().withOpacity(0.5),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.add,
                  color: Colors.white,
                  size: 26,
                ), // 🔹 smaller icon
              ),
            ),

            _buildNavItem(Icons.receipt_long, 3, "Bills"),
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(6), // 🔹 smaller padding
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isActive
              ? Border.all(
                  color: HSLColor.fromAHSL(
                    1.0,
                    236,
                    0.89,
                    0.65,
                  ).toColor().withOpacity(0.5),
                  width: 0.5,
                )
              : null,
        ),
        child: Icon(
          icon,
          color: HSLColor.fromAHSL(
            1.0,
            236,
            0.89,
            0.65,
          ).toColor().withOpacity(0.5),

          size: 22, // 🔹 smaller icon size
        ),
      ),
    );
  }
}
