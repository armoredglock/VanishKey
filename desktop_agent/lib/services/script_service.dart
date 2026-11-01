import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class ScriptExecutionResult {
  final bool success;
  final String username;
  final String password;
  final String createdAt;
  final String expiresAt;
  final int durationMinutes;
  final int durationSeconds;
  final String? error;

  ScriptExecutionResult({
    required this.success,
    this.username = '',
    this.password = '',
    this.createdAt = '',
    this.expiresAt = '',
    this.durationMinutes = 3,
    this.durationSeconds = 180,
    this.error,
  });

  Map<String, dynamic> toJson() => {
    'username': username,
    'password': password,
    'created_at': createdAt,
    'expires_at': expiresAt,
    'duration_minutes': durationMinutes,
    'duration_seconds': durationSeconds,
  };
}

class DesktopScriptService {
  /// Execute unprivileged user creation script
  Future<ScriptExecutionResult> createTemporaryUser({int durationMinutes = 3}) async {
    final clampedDuration = durationMinutes.clamp(1, 5);

    if (Platform.isWindows) {
      return _runWindowsCreate(clampedDuration);
    } else if (Platform.isMacOS) {
      return _runMacCreate(clampedDuration);
    } else {
      return ScriptExecutionResult(
        success: false,
        error: 'Unsupported operating system: ${Platform.operatingSystem}',
      );
    }
  }

  Future<ScriptExecutionResult> _runWindowsCreate(int durationMinutes) async {
    try {
      // In production, bundled with app in scripts/windows
      final scriptPath = _findScriptPath('scripts/windows/create_temp_user.ps1');

      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', scriptPath,
        '-DurationMinutes', '$durationMinutes',
      ]);

      if (result.exitCode != 0) {
        return ScriptExecutionResult(
          success: false,
          error: 'PowerShell script error (${result.exitCode}): ${result.stderr}',
        );
      }

      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(result.stdout.toString());
      if (jsonMatch == null) {
        return ScriptExecutionResult(success: false, error: 'Invalid script output: ${result.stdout}');
      }

      final data = jsonDecode(jsonMatch.group(0)!);
      return ScriptExecutionResult(
        success: data['success'] == true,
        username: data['username'] ?? '',
        password: data['password'] ?? '',
        createdAt: data['created_at'] ?? DateTime.now().toIso8601String(),
        expiresAt: data['expires_at'] ?? '',
        durationMinutes: data['duration_minutes'] ?? durationMinutes,
        durationSeconds: data['duration_seconds'] ?? (durationMinutes * 60),
        error: data['error'],
      );
    } catch (e) {
      return ScriptExecutionResult(success: false, error: e.toString());
    }
  }

  Future<ScriptExecutionResult> _runMacCreate(int durationMinutes) async {
    try {
      final scriptPath = _findScriptPath('scripts/macos/create_temp_user.sh');

      final result = await Process.run('bash', [
        scriptPath,
        '--duration', '$durationMinutes',
      ]);

      if (result.exitCode != 0) {
        return ScriptExecutionResult(
          success: false,
          error: 'macOS script error (${result.exitCode}): ${result.stderr}',
        );
      }

      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(result.stdout.toString());
      if (jsonMatch == null) {
        return ScriptExecutionResult(success: false, error: 'Invalid script output: ${result.stdout}');
      }

      final data = jsonDecode(jsonMatch.group(0)!);
      return ScriptExecutionResult(
        success: data['success'] == true,
        username: data['username'] ?? '',
        password: data['password'] ?? '',
        createdAt: data['created_at'] ?? DateTime.now().toIso8601String(),
        expiresAt: data['expires_at'] ?? '',
        durationMinutes: data['duration_minutes'] ?? durationMinutes,
        durationSeconds: data['duration_seconds'] ?? (durationMinutes * 60),
        error: data['error'],
      );
    } catch (e) {
      return ScriptExecutionResult(success: false, error: e.toString());
    }
  }

  String _findScriptPath(String relativePath) {
    // Check multiple potential locations (dev directory, app bundle, relative to exe)
    final candidates = [
      relativePath,
      '../$relativePath',
      '../../$relativePath',
      '../../../$relativePath',
      Platform.resolvedExecutable.replaceAll(RegExp(r'[^\/\\]+$'), '') + relativePath,
    ];

    for (final c in candidates) {
      if (File(c).existsSync()) {
        return c;
      }
    }
    return relativePath;
  }
}
