import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../services/relay_service.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _isProcessing = false;

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
            await _handlePairing(data);
            return;
          }
        } catch (_) {
          // Non-JSON barcode scanned, ignore
        }
      }
    }
  }

  Future<void> _handlePairing(Map<String, dynamic> data) async {
    final relay = context.read<RelayService>();
    final deviceId = data['deviceId'] as String;
    final pairingSecret = data['pairingSecret'] as String;
    final devicePublicKey = data['devicePublicKey'] as String? ?? '';
    final relayUrl = data['relayUrl'] as String?;

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
          _scannerController.start();
        }
      }
    } else {
      setState(() { _isProcessing = false; });
      _scannerController.start();
    }
  }

  @override
  void dispose() {
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
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
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
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
          ),
        ],
      ),
    );
  }
}
