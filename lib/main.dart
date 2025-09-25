import 'dart:async';
import 'package:flutter/material.dart';
import 'package:projeckt_k/services/auth_service.dart';
import 'package:projeckt_k/screens/login_screen.dart';
import 'package:projeckt_k/widgets/main_navigation_wrapper.dart';
import 'package:projeckt_k/services/sync_notification_service.dart';
import 'package:projeckt_k/services/notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService.initializeFirebase();

  // Initialize global services
  final syncService = SyncNotificationService();
  final notificationService = NotificationService();
  await notificationService.init();

  runApp(MyApp(syncService: syncService));
}

class MyApp extends StatelessWidget {
  final SyncNotificationService syncService;

  const MyApp({super.key, required this.syncService});

  @override
  Widget build(BuildContext context) {
    final scrollController = ScrollController();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SubManager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 4,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.blue[50],
        ),
        cardTheme: CardThemeData(
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      initialRoute: '/',
      routes: {
        '/': (context) => AuthWrapper(syncService: syncService),
        '/home': (context) => MainNavigationWrapper(syncService: syncService),
      },
      onUnknownRoute: (settings) {
        return MaterialPageRoute(builder: (context) => AuthWrapper(syncService: syncService));
      },
      builder: (context, child) {
        return PrimaryScrollController(
          controller: scrollController,
          child: child!,
        );
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  final SyncNotificationService syncService;

  const AuthWrapper({super.key, required this.syncService});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  late final AuthService _authService;
  late final StreamSubscription<User?> _authSubscription;

  @override
  void initState() {
    super.initState();
    widget.syncService.init();
    _authService = AuthService();

    // Listen to auth state changes
    _authSubscription = _authService.authStateChanges.listen((user) {
      if (user != null && mounted) {
        // User just logged in
        _requestNotificationPermissions();
      }
    });

    // Check if user is already logged in
    _requestNotificationPermissions();
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Set the context for the sync service
    widget.syncService.setContext(context);
  }

  Future<void> _requestNotificationPermissions() async {
    // Check current user using FirebaseAuth instance
    final user = _authService.currentUser;
    if (user != null && mounted) {
      final notificationService = NotificationService();
      await notificationService.requestNotificationPermissions(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService().authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.active) {
          final user = snapshot.data;
          if (user != null) {
            return MainNavigationWrapper(syncService: widget.syncService);
          } else {
            return const LoginScreen();
          }
        }

        return Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading...', style: TextStyle(fontSize: 16)),
              ],
            ),
          ),
        );
      },
    );
  }
}
