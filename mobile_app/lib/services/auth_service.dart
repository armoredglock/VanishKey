import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class AuthService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();

  static const String _pinKey = 'vanishkey_owner_pin_hash';
  static const String _ownerIdKey = 'vanishkey_owner_id';

  /// Check if the user has already configured an owner PIN
  Future<bool> hasConfiguredPin() async {
    final pinHash = await _storage.read(key: _pinKey);
    return pinHash != null && pinHash.isNotEmpty;
  }

  /// Set new owner PIN
  Future<void> setOwnerPin(String pin) async {
    final hash = _hashPin(pin);
    await _storage.write(key: _pinKey, value: hash);
  }

  /// Verify entered PIN against stored hash
  Future<bool> verifyPin(String pin) async {
    final storedHash = await _storage.read(key: _pinKey);
    if (storedHash == null) return false;
    return storedHash == _hashPin(pin);
  }

  /// Authenticate with device Biometrics (Fingerprint / FaceID)
  Future<bool> authenticateBiometrics({String reason = 'Authenticate to generate temporary access key'}) async {
    try {
      final isAvailable = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();

      if (!isAvailable || !isDeviceSupported) {
        // Biometrics unavailable on hardware, fallback to PIN gate only
        return true;
      }

      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }

  /// Get or create persistent unique Owner ID
  Future<String> getOrCreateOwnerId() async {
    var ownerId = await _storage.read(key: _ownerIdKey);
    if (ownerId == null) {
      final rand = DateTime.now().millisecondsSinceEpoch.toString();
      final digest = crypto.sha256.convert(utf8.encode('owner_' + rand));
      ownerId = 'owner_' + digest.toString().substring(0, 16);
      await _storage.write(key: _ownerIdKey, value: ownerId);
    }
    return ownerId;
  }

  String _hashPin(String pin) {
    const salt = 'VanishKey_Salt_2026_Secure';
    return crypto.sha256.convert(utf8.encode(pin + salt)).toString();
  }
}
