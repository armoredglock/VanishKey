import 'dart:convert';
import 'package:cryptography/cryptography.dart';

class DesktopCryptoService {
  final X25519 _x25519 = X25519();
  final AesGcm _aesGcm = AesGcm.with256Bits();
  final Hkdf _hkdf = Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  );

  static const String _hkdfInfo = 'VanishKey_v1_SessionKey';

  SimpleKeyPair? _deviceKeyPair;

  Future<SimpleKeyPair> getOrCreateDeviceKeyPair() async {
    if (_deviceKeyPair == null) {
      _deviceKeyPair = await _x25519.newKeyPair();
    }
    return _deviceKeyPair!;
  }

  Future<String> getPublicKeyBase64() async {
    final kp = await getOrCreateDeviceKeyPair();
    final pub = await kp.extractPublicKey();
    return base64Encode(pub.bytes);
  }

  /// Encrypt credential payload using Phone's ephemeral public key
  Future<Map<String, String>> encryptCredentials({
    required Map<String, dynamic> credentialPayload,
    required String phonePublicKeyBase64,
  }) async {
    final kp = await getOrCreateDeviceKeyPair();
    final phonePubBytes = base64Decode(phonePublicKeyBase64);
    final phonePublicKey = SimplePublicKey(phonePubBytes, type: KeyPairType.x25519);

    // Compute Diffie-Hellman Shared Secret: X25519(agentPrivate, phonePublic)
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: kp,
      remotePublicKey: phonePublicKey,
    );

    // Derive 256-bit AES key via HKDF
    final sessionKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      info: utf8.encode(_hkdfInfo),
    );

    final jsonBytes = utf8.encode(jsonEncode(credentialPayload));
    final secretBox = await _aesGcm.encrypt(
      jsonBytes,
      secretKey: sessionKey,
    );

    return {
      'encryptedPayload': base64Encode(secretBox.cipherText),
      'iv': base64Encode(secretBox.nonce),
      'authTag': base64Encode(secretBox.mac.bytes),
      'agentPublicKey': await getPublicKeyBase64(),
    };
  }
}
