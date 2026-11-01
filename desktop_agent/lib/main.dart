import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'services/relay_connection_service.dart';
import 'services/system_tray_service.dart';
import 'services/autostart_service.dart';
import 'screens/dashboard_screen.dart';
import 'screens/audit_viewer_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isMacOS) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(540, 720),
      minimumSize: Size(480, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      title: 'VanishKey Desktop Host',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    await AutoStartService.initialize();
  }

  final relayConnection = RelayConnectionService();
  await relayConnection.initialize();

  runApp(
    ChangeNotifierProvider.value(
      value: relayConnection,
      child: const VanishKeyDesktopApp(),
    ),
  );
}

class VanishKeyDesktopApp extends StatefulWidget {
  const VanishKeyDesktopApp({super.key});

  @override
  State<VanishKeyDesktopApp> createState() => _VanishKeyDesktopAppState();
}

class _VanishKeyDesktopAppState extends State<VanishKeyDesktopApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  SystemTrayService? _trayService;

  @override
  void initState() {
    super.initState();
    _initTray();
  }

  Future<void> _initTray() async {
    _trayService = SystemTrayService(
      onShowDashboard: () {
        _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      },
      onShowAudit: () {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const AuditViewerScreen()),
        );
      },
    );
    await _trayService!.initialize();
  }

  @override
  void dispose() {
    _trayService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'VanishKey Desktop Host',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        primaryColor: const Color(0xFF0284C7),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8),
          secondary: Color(0xFF0284C7),
          surface: Color(0xFF1E293B),
          background: const Color(0xFF0F172A),
        ),
        fontFamily: 'Inter',
      ),
      home: const DashboardScreen(),
    );
  }
}
