import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:provider/provider.dart';
import '../services/relay_connection_service.dart';
import '../services/autostart_service.dart';
import 'audit_viewer_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _autoStart = false;

  @override
  void initState() {
    super.initState();
    _checkAutoStart();
  }

  Future<void> _checkAutoStart() async {
    final enabled = await AutoStartService.isEnabled();
    setState(() {
      _autoStart = enabled;
    });
  }

  Future<void> _toggleAutoStart(bool val) async {
    await AutoStartService.setEnabled(val);
    setState(() {
      _autoStart = val;
    });
  }

  @override
  Widget build(BuildContext context) {
    final agent = context.watch<RelayConnectionService>();
    final isPaired = agent.deviceToken != null && agent.deviceToken!.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('VanishKey Desktop Host'),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt, color: Colors.white70),
            tooltip: 'View Local Audit Log',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AuditViewerScreen()),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: agent.isConnected ? const Color(0xFF065F46) : const Color(0xFF7F1D1D),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    agent.isConnected ? Icons.cloud_done : Icons.cloud_off,
                    color: agent.isConnected ? const Color(0xFF34D399) : const Color(0xFFF87171),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      agent.isConnected
                          ? 'Connected to Relay Server • Host is Ready'
                          : 'Connecting to Relay Server (${agent.relayWsUrl})...',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: agent.isConnected ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            if (!isPaired) ...[
              // Unpaired State - Show QR code
              Card(
                color: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      const Text(
                        'Pair with VanishKey Mobile App',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Open VanishKey on your phone and scan this QR code to establish zero-knowledge control.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: QrImageView(
                          data: agent.pairingQrPayload,
                          version: QrVersions.auto,
                          size: 200.0,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Device ID: ${agent.deviceId}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFF38BDF8)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pairing PIN: ${agent.pairingSecret}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // Paired State
              Card(
                color: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.verified_user, color: Color(0xFF34D399), size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Laptop Successfully Paired', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                                Text('Owner: ${agent.ownerId}', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                              ],
                            ),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                            onPressed: () {
                              agent.deviceToken = null;
                              agent.ownerId = null;
                              agent.connect();
                            },
                            child: const Text('Unpair'),
                          ),
                        ],
                      ),
                      const Divider(color: Color(0xFF334155), height: 32),
                      const Text(
                        'Security Configuration:',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      const Text('• Standard User Role: Enforced (Administrators membership blocked)', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                      const Text('• Cross-Drive Isolation: C:\\Users siblings denied', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                      const Text('• Session Purge & Deletion: Hard-capped at 5 minutes maximum', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),

            // Settings & Preferences
            const Text(
              'Host Settings',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                activeColor: const Color(0xFF38BDF8),
                title: const Text('Start at system login', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Keep host agent active in system tray on startup', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                value: _autoStart,
                onChanged: _toggleAutoStart,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
