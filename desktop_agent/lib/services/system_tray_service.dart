import 'dart:io';
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class SystemTrayService with TrayListener {
  final VoidCallback onShowDashboard;
  final VoidCallback onShowAudit;

  SystemTrayService({
    required this.onShowDashboard,
    required this.onShowAudit,
  });

  Future<void> initialize() async {
    if (!Platform.isWindows && !Platform.isMacOS) return;

    trayManager.addListener(this);

    // Default icon path for Windows .ico / macOS .png
    final iconPath = Platform.isWindows ? 'assets/tray_icon.ico' : 'assets/tray_icon.png';

    try {
      if (File(iconPath).existsSync()) {
        await trayManager.setIcon(iconPath);
      }
    } catch (_) {}
    await trayManager.setToolTip('VanishKey Agent - Running');

    await updateMenu(isOnline: false, isPaired: false);
  }

  Future<void> updateMenu({required bool isOnline, required bool isPaired}) async {
    final statusText = isPaired
        ? (isOnline ? 'Status: Online & Ready' : 'Status: Offline')
        : 'Status: Unpaired';

    final menu = Menu(
      items: [
        MenuItem(
          key: 'status',
          label: 'VanishKey: $statusText',
          disabled: true,
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'dashboard',
          label: 'Show Dashboard / Pairing QR',
        ),
        MenuItem(
          key: 'audit',
          label: 'View Local Audit Log',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'quit',
          label: 'Quit VanishKey',
        ),
      ],
    );

    await trayManager.setContextMenu(menu);
  }

  @override
  void onTrayIconMouseDown() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'dashboard') {
      onShowDashboard();
      await windowManager.show();
      await windowManager.focus();
    } else if (menuItem.key == 'audit') {
      onShowAudit();
      await windowManager.show();
      await windowManager.focus();
    } else if (menuItem.key == 'quit') {
      trayManager.removeListener(this);
      await trayManager.destroy();
      exit(0);
    }
  }

  void dispose() {
    trayManager.removeListener(this);
  }
}
