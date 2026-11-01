import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/device.dart';
import '../models/credential.dart';
import 'crypto_service.dart';

class RelayService extends ChangeNotifier {
  final MobileCryptoService _crypto = MobileCryptoService();
  String relayBaseUrl = 'http://192.168.1.100:8080'; // Configurable in settings
  String? ownerId;

  WebSocketChannel? _channel;
  bool isConnected = false;
  List<PairedDevice> pairedDevices = [];
  List<Map<String, dynamic>> auditHistory = [];

  // Active generation response completer
  Completer<EphemeralCredential>? _pendingAccessCompleter;
  dynamic _currentEphemeralKeyPair;

  void updateRelayUrl(String url) {
    relayBaseUrl = url.replaceAll(RegExp(r'/+$'), '');
    notifyListeners();
  }

  void initialize(String owner) {
    ownerId = owner;
    connectWebSocket();
    refreshDevices();
  }

  String get _wsUrl {
    final uri = Uri.parse(relayBaseUrl);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return '$wsScheme://${uri.host}:${uri.port}/ws/mobile?ownerId=$ownerId';
  }

  void connectWebSocket() {
    if (ownerId == null) return;
    try {
      _channel?.sink.close();
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      isConnected = true;
      notifyListeners();

      _channel!.stream.listen(
        (data) {
          _handleIncomingMessage(data.toString());
        },
        onDone: () {
          isConnected = false;
          notifyListeners();
          Future.delayed(const Duration(seconds: 5), connectWebSocket);
        },
        onError: (err) {
          isConnected = false;
          notifyListeners();
          Future.delayed(const Duration(seconds: 5), connectWebSocket);
        },
      );
    } catch (e) {
      isConnected = false;
      notifyListeners();
    }
  }

  Future<void> _handleIncomingMessage(String rawJson) async {
    try {
      final Map<String, dynamic> msg = jsonDecode(rawJson);
      final type = msg['type'];

      if (type == 'DEVICE_STATUS_CHANGED') {
        final devId = msg['deviceId'] as String;
        final isOnline = msg['isOnline'] as bool;
        final idx = pairedDevices.indexWhere((d) => d.deviceId == devId);
        if (idx != -1) {
          pairedDevices[idx] = PairedDevice(
            deviceId: pairedDevices[idx].deviceId,
            deviceName: pairedDevices[idx].deviceName,
            osType: pairedDevices[idx].osType,
            pairedAt: pairedDevices[idx].pairedAt,
            isOnline: isOnline,
          );
          notifyListeners();
        }
      } else if (type == 'ACCESS_CREDENTIALS_RELAY') {
        if (_pendingAccessCompleter != null && !_pendingAccessCompleter!.isCompleted) {
          final creds = await _crypto.decryptAccessResponse(
            ephemeralPhoneKeyPair: _currentEphemeralKeyPair,
            agentPublicKeyBase64: msg['agentPublicKey'],
            encryptedPayloadBase64: msg['encryptedPayload'],
            ivBase64: msg['iv'],
            authTagBase64: msg['authTag'],
          );
          _pendingAccessCompleter!.complete(creds);
        }
      } else if (type == 'RATE_LIMIT_EXCEEDED') {
        _pendingAccessCompleter?.completeError(
          Exception(msg['message'] ?? 'Rate limit exceeded: max 3 generations per hour.'),
        );
      } else if (type == 'AGENT_OFFLINE') {
        _pendingAccessCompleter?.completeError(
          Exception(msg['message'] ?? 'Target laptop is offline or asleep.'),
        );
      } else if (type == 'ACCESS_TIMEOUT' || type == 'ACCESS_FAILED') {
        _pendingAccessCompleter?.completeError(
          Exception(msg['error'] ?? msg['message'] ?? 'Failed to generate temporary access.'),
        );
      }
    } catch (e) {
      debugPrint('Error handling WS message: $e');
    }
  }

  /// Request temporary access with E2E encryption and 15s timeout
  Future<EphemeralCredential> requestTemporaryAccess({
    required String deviceId,
    int durationMinutes = 3,
  }) async {
    if (!isConnected || _channel == null) {
      throw Exception('Not connected to VanishKey relay server.');
    }

    final keyPair = await _crypto.generateEphemeralKeyPair();
    _currentEphemeralKeyPair = keyPair;
    final phonePublicKeyBase64 = await _crypto.exportPublicKeyBase64(keyPair);

    final requestId = 'req_${DateTime.now().millisecondsSinceEpoch}';
    _pendingAccessCompleter = Completer<EphemeralCredential>();

    final requestPayload = {
      'type': 'ACCESS_REQUEST',
      'requestId': requestId,
      'ownerId': ownerId,
      'deviceId': deviceId,
      'durationMinutes': durationMinutes,
      'ephemeralPhonePublicKey': phonePublicKeyBase64,
    };

    _channel!.sink.add(jsonEncode(requestPayload));

    return _pendingAccessCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw Exception('Request timed out. Target laptop did not respond.'),
    );
  }

  /// Complete device pairing via HTTP
  Future<bool> pairDevice({
    required String deviceId,
    required String pairingSecret,
    required String devicePublicKey,
    String? customName,
  }) async {
    final res = await http.post(
      Uri.parse('$relayBaseUrl/api/v1/devices/pair'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'ownerId': ownerId,
        'deviceId': deviceId,
        'pairingSecret': pairingSecret,
        'phonePublicKey': devicePublicKey,
        'customName': customName,
      }),
    );

    if (res.statusCode == 200) {
      await refreshDevices();
      return true;
    }
    final body = jsonDecode(res.body);
    throw Exception(body['error'] ?? 'Pairing failed');
  }

  /// Revoke paired device
  Future<bool> revokeDevice(String deviceId) async {
    final res = await http.post(
      Uri.parse('$relayBaseUrl/api/v1/devices/revoke'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'ownerId': ownerId,
        'deviceId': deviceId,
      }),
    );

    if (res.statusCode == 200) {
      await refreshDevices();
      return true;
    }
    return false;
  }

  /// Fetch paired devices list
  Future<void> refreshDevices() async {
    if (ownerId == null) return;
    try {
      final res = await http.get(Uri.parse('$relayBaseUrl/api/v1/devices/list?ownerId=$ownerId'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = (data['devices'] as List).map((d) => PairedDevice.fromJson(d)).toList();
        pairedDevices = list;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to refresh devices: $e');
    }
  }

  /// Fetch audit history (metadata only)
  Future<void> refreshAuditLogs() async {
    if (ownerId == null) return;
    try {
      final res = await http.get(Uri.parse('$relayBaseUrl/api/v1/audit/logs?ownerId=$ownerId'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        auditHistory = List<Map<String, dynamic>>.from(data['logs'] ?? []).reversed.toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to refresh audit logs: $e');
    }
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }
}
