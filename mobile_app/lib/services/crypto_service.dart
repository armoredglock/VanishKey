import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../models/credential.dart';

class MobileCryptoService {
  final X25519 _x25519 = X25519();
  final AesGcm _aesGcm = AesGcm.with256bits();
  final Hkdf _hkdf = Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  );

  static const String _hkdfInfo = 'VanishKey_v1_SessionKey';

  /// Generate a fresh ephemeral X25519 keypair
  Future<SimpleKeyPair> generateEphemeralKeyPair() async {
    return await _x25519.newKeyPair();
  }

  /// Export public key as raw 32-byte Base64 string
  Future<String> exportPublicKeyBase64(SimpleKeyPair keyPair) async {
    final pubKey = await keyPair.extractPublicKey();
    return base64Encode(pubKey.bytes);
  }

  /// Decrypt an end-to-end encrypted AccessResponse payload
  Future<EphemeralCredential> decryptAccessResponse({
    required SimpleKeyPair ephemeralPhoneKeyPair,
    required String agentPublicKeyBase64,
    required String encryptedPayloadBase64,
    required String ivBase64,
    required String authTagBase64,
  }) async {
    final agentPubBytes = base64Decode(agentPublicKeyBase64);
    final agentPublicKey = SimplePublicKey(agentPubBytes, type: KeyPairType.x25519);

    // Compute Diffie-Hellman Shared Secret: X25519(phonePrivate, agentPublic)
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: ephemeralPhoneKeyPair,
      remotePublicKey: agentPublicKey,
    );

    // Derive AES-256 key via HKDF-SHA256
    final sessionKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      info: utf8.encode(_hkdfInfo),
    );

    // Decrypt AES-256-GCM
    final cipherBytes = base64Decode(encryptedPayloadBase64);
    final ivBytes = base64Decode(ivBase64);
    final tagBytes = base64Decode(authTagBase64);

    final secretBox = SecretBox(
      cipherBytes,
      nonce: ivBytes,
      mac: Mac(tagBytes),
    );

    final decryptedBytes = await _aesGcm.decrypt(
      secretBox,
      secretKey: sessionKey,
    );

    final jsonStr = utf8.decode(decryptedBytes);
    final Map<String, dynamic> data = jsonDecode(jsonStr);

    return EphemeralCredential.fromJson(data);
  }
}
