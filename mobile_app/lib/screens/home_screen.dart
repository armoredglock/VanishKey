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

    // 2. Select Duration with High-Craft Bottom Sheet
    int durationMinutes = 3;
    final selectedDuration = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Row(
                children: [
                  Icon(Icons.timer_outlined, color: Color(0xFF38BDF8), size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Select Access Duration',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Windows will automatically sign out and wipe the user profile when time runs out.',
                style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8), height: 1.3),
              ),
              const SizedBox(height: 20),
              _buildDurationOption(
                ctx,
                minutes: 2,
                title: '2 Minutes',
                subtitle: 'Quick task (e.g. print a document, check an email)',
                isRecommended: false,
              ),
              const SizedBox(height: 10),
              _buildDurationOption(
                ctx,
                minutes: 3,
                title: '3 Minutes',
                subtitle: 'Recommended duration for casual roommate access',
                isRecommended: true,
              ),
              const SizedBox(height: 10),
              _buildDurationOption(
                ctx,
                minutes: 5,
                title: '5 Minutes',
                subtitle: 'Maximum security hard cap',
                isRecommended: false,
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
        _showHumanFriendlyError(context, e.toString());
      }
    }
  }

  static Widget _buildDurationOption(
    BuildContext ctx, {
    required int minutes,
    required String title,
    required String subtitle,
    required bool isRecommended,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.pop(ctx, minutes),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isRecommended ? const Color(0xFF0284C7) : const Color(0xFF334155),
            width: isRecommended ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isRecommended ? const Color(0xFF0C4A6E) : const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.timer_outlined,
                color: isRecommended ? const Color(0xFF38BDF8) : Colors.white60,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      if (isRecommended) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0284C7).withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'RECOMMENDED',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8)),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
          ],
        ),
      ),
    );
  }

  void _showHumanFriendlyError(BuildContext context, String rawError) {
    String title = 'Generation Failed';
    String description = 'Something went wrong while communicating with your laptop.';
    String actionHint = 'Please check that the host agent is active on your laptop.';
    IconData icon = Icons.error_outline_rounded;
    Color iconColor = Colors.redAccent;

    final lower = rawError.toLowerCase();
    if (lower.contains('administrative privileges') || lower.contains('admin')) {
      title = 'Administrator Rights Needed';
      description = 'Windows requires administrator privileges to create the temporary local user.';
      actionHint = 'On your laptop, right-click "Launch-VanishKey-Host.bat" and choose "Run as administrator".';
      icon = Icons.admin_panel_settings_outlined;
      iconColor = Colors.amberAccent;
    } else if (lower.contains('timed out') || lower.contains('timeout') || lower.contains('not respond')) {
      title = 'Laptop Did Not Respond';
      description = 'Your laptop appears to be asleep, locked without host running, or disconnected.';
      actionHint = 'Open the "VanishKey Host" terminal on your laptop to resume connection.';
      icon = Icons.laptop_chromebook_rounded;
      iconColor = const Color(0xFF38BDF8);
    } else if (lower.contains('rate limit')) {
      title = 'Hourly Quota Reached';
      description = 'To protect your system, VanishKey caps temporary accesses at 3 per hour.';
      actionHint = 'Please wait a short while before generating new access.';
      icon = Icons.hourglass_top_rounded;
      iconColor = Colors.orangeAccent;
    } else if (lower.contains('socketexception') || lower.contains('connection refused')) {
      title = 'Network Connection Error';
      description = 'Unable to reach the VanishKey Relay Server.';
      actionHint = 'Check your internet connection or verify the Render cloud service status.';
      icon = Icons.wifi_off_rounded;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(icon, color: iconColor, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(description, style: const TextStyle(fontSize: 13, color: Colors.white, height: 1.4)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline, size: 16, color: Color(0xFF38BDF8)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      actionHint,
                      style: const TextStyle(fontSize: 12, color: Color(0xFFE2E8F0), height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Understood', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0C4A6E).withOpacity(0.3),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.5), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0284C7).withOpacity(0.15),
                            blurRadius: 24,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.laptop_windows_rounded, size: 48, color: Color(0xFF38BDF8)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'No Laptop Paired Yet',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.3),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Run VanishKey Host on your computer to display a pairing QR code, then scan it below to connect.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Color(0xFF94A3B8), height: 1.4),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 3,
                        ),
                        icon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 22),
                        label: const Text(
                          'Scan Desktop QR Code',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QrScanScreen())),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextButton.icon(
                      icon: const Icon(Icons.keyboard_alt_outlined, color: Color(0xFF38BDF8), size: 18),
                      label: const Text(
                        'Enter 6-Digit PIN Manually',
                        style: TextStyle(color: Color(0xFF38BDF8), fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      onPressed: () => _showManualPair(context),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: relay.refreshDevices,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: relay.pairedDevices.length,
                itemBuilder: (context, idx) {
                  final dev = relay.pairedDevices[idx];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131B2E),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: dev.isOnline ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
                        width: dev.isOnline ? 1.5 : 1.2,
                      ),
                      boxShadow: dev.isOnline
                          ? [
                              BoxShadow(
                                color: const Color(0xFF0284C7).withOpacity(0.15),
                                blurRadius: 16,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(18.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0C4A6E).withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  dev.osType == 'macos' ? Icons.laptop_mac_rounded : Icons.laptop_windows_rounded,
                                  size: 26,
                                  color: const Color(0xFF38BDF8),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      dev.deviceName,
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${dev.osType.toUpperCase()} • ${dev.deviceId}',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), letterSpacing: 0.3),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: dev.isOnline ? const Color(0xFF065F46) : const Color(0xFF1E293B),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: dev.isOnline ? const Color(0xFF34D399) : const Color(0xFF64748B),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      dev.isOnline ? 'ONLINE' : 'OFFLINE',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: dev.isOnline ? const Color(0xFF34D399) : const Color(0xFF94A3B8),
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
                                color: const Color(0xFF1E293B),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                onSelected: (val) {
                                  if (val == 'revoke') _confirmRevoke(context, dev);
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'revoke',
                                    child: Row(
                                      children: [
                                        Icon(Icons.link_off_rounded, color: Colors.redAccent, size: 18),
                                        SizedBox(width: 8),
                                        Text('Revoke Laptop', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: dev.isOnline ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
                                foregroundColor: Colors.white,
                                elevation: dev.isOnline ? 2 : 0,
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: Icon(
                                Icons.key_rounded,
                                color: dev.isOnline ? Colors.white : const Color(0xFF64748B),
                                size: 18,
                              ),
                              label: Text(
                                dev.isOnline ? 'Generate Temporary Access' : 'Laptop Offline (Waiting for Host)',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: dev.isOnline ? Colors.white : const Color(0xFF64748B),
                                ),
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
