import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/relay_service.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> with WidgetsBindingObserver {
  late MobileScannerController _scannerController;
  bool _hasCameraPermission = false;
  bool _isCheckingPermission = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
      autoStart: false,
    );
    _initPermissionsAndCamera();
  }

  Future<void> _initPermissionsAndCamera() async {
    setState(() { _isCheckingPermission = true; });
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }

    if (mounted) {
      setState(() {
        _hasCameraPermission = status.isGranted;
        _isCheckingPermission = false;
      });

      if (_hasCameraPermission) {
        try {
          await _scannerController.start();
        } catch (e) {
          debugPrint('Error starting camera: $e');
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initPermissionsAndCamera();
    }
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        final raw = barcode.rawValue!;
        try {
          final data = jsonDecode(raw);
          if (data is Map<String, dynamic> &&
              data.containsKey('deviceId') &&
              data.containsKey('pairingSecret')) {
            setState(() { _isProcessing = true; });
            _scannerController.stop();
            await _handlePairing(
              deviceId: data['deviceId'] as String,
              pairingSecret: data['pairingSecret'] as String,
              relayUrl: data['relayUrl'] as String?,
              devicePublicKey: data['devicePublicKey'] as String? ?? '',
            );
            return;
          }
        } catch (_) {}
      }
    }
  }

  Future<void> _handlePairing({
    required String deviceId,
    required String pairingSecret,
    String? relayUrl,
    String devicePublicKey = '',
  }) async {
    final relay = context.read<RelayService>();

    if (relayUrl != null && relayUrl.isNotEmpty) {
      relay.updateRelayUrl(relayUrl);
    }

    final nameController = TextEditingController(text: 'Laptop ($deviceId)');
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Pair Laptop', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter a friendly name for this laptop:', style: TextStyle(color: Color(0xFF94A3B8))),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Pairing', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await relay.pairDevice(
          deviceId: deviceId,
          pairingSecret: pairingSecret,
          devicePublicKey: devicePublicKey,
          customName: nameController.text.trim(),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Laptop paired successfully!')),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Pairing failed: $e')),
          );
          setState(() { _isProcessing = false; });
          if (_hasCameraPermission) {
            _scannerController.start();
          }
        }
      }
    } else {
      setState(() { _isProcessing = false; });
      if (_hasCameraPermission) {
        _scannerController.start();
      }
    }
  }

  void _showManualPairDialog() {
    final relay = context.read<RelayService>();
    final urlController = TextEditingController(text: relay.relayBaseUrl);
    final idController = TextEditingController();
    final pinController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.keyboard_alt_outlined, color: Color(0xFF38BDF8)),
            SizedBox(width: 8),
            Text('Manual Pairing', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter the pairing info shown on your laptop screen:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
              const SizedBox(height: 16),
              const Text('Relay Server Address / IP:', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: urlController,
                style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'http://192.168.1.X:8080',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Device ID (e.g. dev_win32_1677AA):', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: idController,
                style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'dev_win32_XXXXXX',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              const Text('6-Digit Pairing PIN:', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 6),
              TextField(
                controller: pinController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontFamily: 'monospace', letterSpacing: 2),
                decoration: InputDecoration(
                  hintText: '123456',
                  hintStyle: const TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            onPressed: () {
              final devId = idController.text.trim();
              final pin = pinController.text.trim();
              final url = urlController.text.trim();

              if (devId.isEmpty || pin.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please fill in both Device ID and PIN.')),
                );
                return;
              }

              Navigator.pop(ctx);
              _handlePairing(
                deviceId: devId,
                pairingSecret: pin,
                relayUrl: url.isNotEmpty ? url : null,
              );
            },
            child: const Text('Pair Device', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scan Desktop QR Code'),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          if (_hasCameraPermission) ...[
            IconButton(
              icon: const Icon(Icons.flash_on, color: Colors.white70),
              tooltip: 'Toggle Flash',
              onPressed: () => _scannerController.toggleTorch(),
            ),
            IconButton(
              icon: const Icon(Icons.flip_camera_ios, color: Colors.white70),
              tooltip: 'Flip Camera',
              onPressed: () => _scannerController.switchCamera(),
            ),
          ],
        ],
      ),
      body: _isCheckingPermission
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8)))
          : (!_hasCameraPermission
              ? _buildPermissionFallback()
              : Stack(
                  children: [
                    MobileScanner(
                      controller: _scannerController,
                      onDetect: _onDetect,
                      errorBuilder: (context, error, child) {
                        return _buildCameraErrorView(error);
                      },
                    ),
                    Center(
                      child: Container(
                        width: 260,
                        height: 260,
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF38BDF8), width: 3),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 30,
                      left: 20,
                      right: 20,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B).withOpacity(0.9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Point camera at the QR code displayed on your laptop screen',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E293B),
                              side: const BorderSide(color: Color(0xFF38BDF8)),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.keyboard_alt_outlined, color: Color(0xFF38BDF8)),
                            label: const Text(
                              "Can't scan? Enter PIN manually",
                              style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                            ),
                            onPressed: _showManualPairDialog,
                          ),
                        ],
                      ),
                    ),
                  ],
                )),
    );
  }

  Widget _buildPermissionFallback() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined, size: 72, color: Colors.orangeAccent),
            const SizedBox(height: 20),
            const Text(
              'Camera Permission Required',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'To scan the pairing QR code, allow camera access. Or pair directly using the 6-digit PIN shown on your laptop.',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.settings, color: Colors.white),
              label: const Text('Open App Settings', style: TextStyle(color: Colors.white, fontSize: 15)),
              onPressed: () => openAppSettings(),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF38BDF8)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.keyboard_alt_outlined, color: Color(0xFF38BDF8)),
              label: const Text('Enter 6-Digit PIN Manually', style: TextStyle(color: Color(0xFF38BDF8))),
              onPressed: _showManualPairDialog,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraErrorView(MobileScannerException error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_outlined, size: 64, color: Colors.orangeAccent),
            const SizedBox(height: 16),
            const Text(
              'Camera Initializing Issue',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '${error.errorCode.name}: ${error.errorDetails?.message ?? "Device camera hardware could not be locked."}',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
              icon: const Icon(Icons.keyboard, color: Colors.white),
              label: const Text('Enter PIN Manually Instead', style: TextStyle(color: Colors.white)),
              onPressed: _showManualPairDialog,
            ),
          ],
        ),
      ),
    );
  }
}
