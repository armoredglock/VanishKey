import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'desktop_crypto_service.dart';
import 'script_service.dart';

class RelayConnectionService extends ChangeNotifier {
  final DesktopCryptoService _crypto = DesktopCryptoService();
  final DesktopScriptService _scriptService = DesktopScriptService();

  String relayWsUrl = 'ws://localhost:8080/ws/agent';
  String relayBaseUrl = 'http://localhost:8080';

  String? deviceId;
  String? deviceName;
  String? pairingSecret;
  String? deviceToken;
  String? ownerId;
  String? devicePublicKeyBase64;

  bool isConnected = false;
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;

  final List<Map<String, dynamic>> localAuditLogs = [];

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    deviceId = prefs.getString('vk_device_id');
    deviceName = prefs.getString('vk_device_name') ?? '${Platform.localHostname} (${Platform.isWindows ? "Windows" : "macOS"})';
    pairingSecret = prefs.getString('vk_pairing_secret');
    deviceToken = prefs.getString('vk_device_token');
    ownerId = prefs.getString('vk_owner_id');

    devicePublicKeyBase64 = await _crypto.getPublicKeyBase64();

    if (deviceId == null) {
      final rand = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();
      deviceId = 'dev_${Platform.isWindows ? "win" : "mac"}_$rand';
      pairingSecret = (100000 + Random().nextInt(900000)).toString();

      await prefs.setString('vk_device_id', deviceId!);
      await prefs.setString('vk_device_name', deviceName!);
      await prefs.setString('vk_pairing_secret', pairingSecret!);
    }

    _loadAuditLogs(prefs);
    connect();
  }

  void _loadAuditLogs(SharedPreferences prefs) {
    final raw = prefs.getString('vk_local_audit');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        localAuditLogs.addAll(list.cast<Map<String, dynamic>>());
      } catch (_) {}
    }
  }

  Future<void> logLocalAudit(String action, String status, {Map<String, dynamic>? details}) async {
    final entry = {
      'timestamp': DateTime.now().toIso8601String(),
      'action': action,
      'status': status,
      'details': details ?? {},
    };
    localAuditLogs.insert(0, entry);
    if (localAuditLogs.length > 200) localAuditLogs.removeLast();
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vk_local_audit', jsonEncode(localAuditLogs));
  }

  void connect() {
    _reconnectTimer?.cancel();
    try {
      _channel?.sink.close();
      _channel = WebSocketChannel.connect(Uri.parse(relayWsUrl));
      isConnected = true;
      notifyListeners();

      // Register or Authenticate
      if (deviceToken != null && deviceToken!.isNotEmpty) {
        _send({
          'type': 'AGENT_AUTH',
          'deviceId': deviceId,
          'deviceToken': deviceToken,
        });
      } else {
        _send({
          'type': 'REGISTER_PENDING_DEVICE',
          'deviceId': deviceId,
          'deviceName': deviceName,
          'osType': Platform.isWindows ? 'windows' : 'macos',
          'publicKey': devicePublicKeyBase64,
          'pairingSecret': pairingSecret,
        });
      }

      _channel!.stream.listen(
        (data) => _handleMessage(data.toString()),
        onDone: _scheduleReconnect,
        onError: (err) => _scheduleReconnect(),
      );
    } catch (e) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    isConnected = false;
    notifyListeners();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), connect);
  }

  void _send(Map<String, dynamic> msg) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(msg));
    }
  }

  Future<void> _handleMessage(String rawJson) async {
    try {
      final msg = jsonDecode(rawJson) as Map<String, dynamic>;
      final type = msg['type'];

      if (type == 'DEVICE_PAIRED_EVENT') {
        deviceToken = msg['deviceToken'];
        ownerId = msg['ownerId'];

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('vk_device_token', deviceToken!);
        await prefs.setString('vk_owner_id', ownerId!);

        await logLocalAudit('DEVICE_PAIRED', 'SUCCESS', details: {'ownerId': ownerId});
        notifyListeners();

      } else if (type == 'GENERATE_ACCESS') {
        final requestId = msg['requestId'];
        final durationMinutes = msg['durationMinutes'] as int? ?? 3;
        final ephemeralPhonePublicKey = msg['ephemeralPhonePublicKey'] as String;

        await logLocalAudit('ACCESS_REQUEST_RECEIVED', 'PENDING', details: {
          'requestId': requestId,
          'durationMinutes': durationMinutes,
        });

        // 1. Run local unprivileged account creation script
        final scriptRes = await _scriptService.createTemporaryUser(durationMinutes: durationMinutes);

        if (!scriptRes.success) {
          await logLocalAudit('ACCESS_GENERATION', 'FAILED', details: {'error': scriptRes.error});
          _send({
            'type': 'ACCESS_RESPONSE',
            'requestId': requestId,
            'deviceId': deviceId,
            'error': scriptRes.error ?? 'Failed to execute OS script',
          });
          return;
        }

        // 2. Perform End-to-End Encryption with Phone's ephemeral public key
        final encResult = await _crypto.encryptCredentials(
          credentialPayload: scriptRes.toJson(),
          phonePublicKeyBase64: ephemeralPhonePublicKey,
        );

        // 3. Send encrypted payload back to relay
        _send({
          'type': 'ACCESS_RESPONSE',
          'requestId': requestId,
          'deviceId': deviceId,
          'encryptedPayload': encResult['encryptedPayload'],
          'iv': encResult['iv'],
          'authTag': encResult['authTag'],
          'agentPublicKey': encResult['agentPublicKey'],
        });

        await logLocalAudit('ACCESS_GENERATION', 'SUCCESS', details: {
          'username': scriptRes.username,
          'expiresAt': scriptRes.expiresAt,
          'durationMinutes': durationMinutes,
        });

      } else if (type == 'REVOKED') {
        deviceToken = null;
        ownerId = null;

        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('vk_device_token');
        await prefs.remove('vk_owner_id');

        await logLocalAudit('DEVICE_REVOKED', 'REVOKED');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error handling relay message: $e');
    }
  }

  String get pairingQrPayload {
    return jsonEncode({
      'deviceId': deviceId,
      'relayUrl': relayBaseUrl,
      'pairingSecret': pairingSecret,
      'devicePublicKey': devicePublicKeyBase64,
    });
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}
