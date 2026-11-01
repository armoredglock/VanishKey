import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/relay_service.dart';
import '../services/auth_service.dart';
import '../models/device.dart';
import 'qr_scan_screen.dart';
import 'active_access_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatelessWidget {
  final AuthService authService;

  const HomeScreen({super.key, required this.authService});

  Future<void> _handleGenerateAccess(BuildContext context, PairedDevice device) async {
    final relay = context.read<RelayService>();

    // 1. Enforce Biometric / PIN re-authentication before sensitive credential generation
    final biometricPass = await authService.authenticateBiometrics(
      reason: 'Authorize generation of temporary login credentials for ${device.deviceName}',
    );

    if (!biometricPass) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Authentication required to generate access.')),
        );
      }
      return;
    }

    // 2. Select Duration
    int durationMinutes = 3;
    final selectedDuration = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Access Duration',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Account and home folder are automatically destroyed upon expiry.',
                style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.timer, color: Color(0xFF38BDF8)),
                title: const Text('2 Minutes', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 2),
              ),
              ListTile(
                leading: const Icon(Icons.timer, color: Color(0xFF38BDF8)),
                title: const Text('3 Minutes (Recommended)', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 3),
              ),
              ListTile(
                leading: const Icon(Icons.timer, color: Color(0xFF38BDF8)),
                title: const Text('5 Minutes (Hard Cap)', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, 5),
              ),
            ],
          ),
        );
      },
    );

    if (selectedDuration != null) {
      durationMinutes = selectedDuration;
    } else {
      return;
    }

    // 3. Trigger access request with loading indicator
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          color: Color(0xFF1E293B),
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF38BDF8)),
                SizedBox(height: 16),
                Text('Connecting to laptop & generating CSPRNG user...', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final credential = await relay.requestTemporaryAccess(
        deviceId: device.deviceId,
        durationMinutes: durationMinutes,
      );

      if (context.mounted) {
        Navigator.pop(context); // Close loading dialog
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ActiveAccessScreen(
              credential: credential,
              device: device,
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Close loading dialog
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: const Text('Generation Failed', style: TextStyle(color: Colors.redAccent)),
            content: Text(e.toString().replaceAll('Exception: ', ''), style: const TextStyle(color: Colors.white70)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(color: Color(0xFF38BDF8))),
              )
            ],
          ),
        );
      }
    }
  }

  void _confirmRevoke(BuildContext context, PairedDevice device) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text('Revoke ${device.deviceName}?', style: const TextStyle(color: Colors.white)),
        content: const Text(
          'This will permanently disconnect this laptop. You will need to scan a new QR code to reconnect.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<RelayService>().revokeDevice(device.deviceId);
            },
            child: const Text('Revoke Device', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showManualPair(BuildContext context) {
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
            onPressed: () async {
              final devId = idController.text.trim();
              final pin = pinController.text.trim();
              final url = urlController.text.trim();

              if (devId.isEmpty || pin.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please fill in both Device ID and PIN.')),
                );
                return;
              }

              if (url.isNotEmpty) {
                relay.updateRelayUrl(url);
              }

              Navigator.pop(ctx);

              try {
                await relay.pairDevice(
                  deviceId: devId,
                  pairingSecret: pin,
                  devicePublicKey: '',
                  customName: 'Laptop ($devId)',
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Laptop paired successfully!')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Pairing failed: $e')),
                  );
                }
              }
            },
            child: const Text('Pair Device', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final relay = context.watch<RelayService>();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.vpn_key_outlined, color: Color(0xFF38BDF8)),
            const SizedBox(width: 8),
            const Text('VanishKey', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: relay.isConnected ? const Color(0xFF065F46) : const Color(0xFF7F1D1D),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: relay.isConnected ? const Color(0xFF34D399) : const Color(0xFFF87171),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    relay.isConnected ? 'Relay Online' : 'Relay Offline',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: relay.isConnected ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: Colors.white70),
            onPressed: () {
              relay.refreshAuditLogs();
              Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen()));
            },
          ),
        ],
      ),
      body: relay.pairedDevices.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.laptop_mac_outlined, size: 80, color: Color(0xFF475569)),
                  const SizedBox(height: 16),
                  const Text(
                    'No Paired Laptops',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Scan the QR code displayed on the VanishKey\nDesktop Agent running on your laptop.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
                    label: const Text('Scan Desktop QR Code', style: TextStyle(fontSize: 16, color: Colors.white)),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QrScanScreen())),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    icon: const Icon(Icons.keyboard_alt_outlined, color: Color(0xFF38BDF8)),
                    label: const Text('Or Enter Pairing PIN Manually', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 14)),
                    onPressed: () => _showManualPair(context),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: relay.refreshDevices,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: relay.pairedDevices.length,
                itemBuilder: (context, idx) {
                  final dev = relay.pairedDevices[idx];
                  return Card(
                    color: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: dev.isOnline ? const Color(0xFF0284C7) : const Color(0xFF334155),
                        width: 1.5,
                      ),
                    ),
                    margin: const EdgeInsets.only(bottom: 16),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                dev.osType == 'macos' ? Icons.laptop_mac : Icons.laptop_windows,
                                size: 32,
                                color: const Color(0xFF38BDF8),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      dev.deviceName,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      dev.osType.toUpperCase(),
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: dev.isOnline ? const Color(0xFF065F46) : const Color(0xFF334155),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  dev.isOnline ? 'ONLINE' : 'OFFLINE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: dev.isOnline ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, color: Colors.white70),
                                color: const Color(0xFF1E293B),
                                onSelected: (val) {
                                  if (val == 'revoke') _confirmRevoke(context, dev);
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'revoke',
                                    child: Text('Revoke Pairing', style: TextStyle(color: Colors.redAccent)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: dev.isOnline ? const Color(0xFF0284C7) : const Color(0xFF334155),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.key, color: Colors.white),
                              label: const Text(
                                'Generate Temporary Access',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                              onPressed: dev.isOnline ? () => _handleGenerateAccess(context, dev) : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF0284C7),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QrScanScreen())),
        child: const Icon(Icons.qr_code_scanner, color: Colors.white),
      ),
    );
  }
}
