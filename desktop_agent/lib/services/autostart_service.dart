import 'dart:io';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AutoStartService {
  static Future<void> initialize() async {
    if (!Platform.isWindows && !Platform.isMacOS) return;

    final packageInfo = await PackageInfo.fromPlatform();
    launchAtStartup.setup(
      appName: packageInfo.appName.isNotEmpty ? packageInfo.appName : 'VanishKeyAgent',
      appPath: Platform.resolvedExecutable,
    );
  }

  static Future<bool> isEnabled() async {
    if (!Platform.isWindows && !Platform.isMacOS) return false;
    return await launchAtStartup.isEnabled();
  }

  static Future<void> setEnabled(bool enabled) async {
    if (!Platform.isWindows && !Platform.isMacOS) return;
    if (enabled) {
      await launchAtStartup.enable();
    } else {
      await launchAtStartup.disable();
    }
  }
}
