import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'services/relay_service.dart';
import 'screens/pin_lock_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final authService = AuthService();
  final relayService = RelayService();

  final ownerId = await authService.getOrCreateOwnerId();
  relayService.initialize(ownerId);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: relayService),
        Provider.value(value: authService),
      ],
      child: const VanishKeyMobileApp(),
    ),
  );
}

class VanishKeyMobileApp extends StatefulWidget {
  const VanishKeyMobileApp({super.key});

  @override
  State<VanishKeyMobileApp> createState() => _VanishKeyMobileAppState();
}

class _VanishKeyMobileAppState extends State<VanishKeyMobileApp> {
  bool _isAuthenticated = false;

  @override
  Widget build(BuildContext context) {
    final authService = context.read<AuthService>();

    return MaterialApp(
      title: 'VanishKey Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        primaryColor: const Color(0xFF0284C7),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8),
          secondary: Color(0xFF0284C7),
          surface: Color(0xFF1E293B),
          background: Color(0xFF0F172A),
        ),
        fontFamily: 'Inter',
      ),
      home: _isAuthenticated
          ? HomeScreen(authService: authService)
          : PinLockScreen(
              authService: authService,
              onAuthenticated: () {
                setState(() {
                  _isAuthenticated = true;
                });
              },
            ),
    );
  }
}
