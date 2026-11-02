import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/credential.dart';
import '../models/device.dart';
import '../services/relay_service.dart';

class ActiveAccessScreen extends StatefulWidget {
  final EphemeralCredential credential;
  final PairedDevice device;

  const ActiveAccessScreen({
    super.key,
    required this.credential,
    required this.device,
  });

  @override
  State<ActiveAccessScreen> createState() => _ActiveAccessScreenState();
}

class _ActiveAccessScreenState extends State<ActiveAccessScreen> {
  late Timer _timer;
  late int _remainingSeconds;
  bool _obscurePassword = false;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.credential.remainingSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        _timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied to clipboard')),
    );
  }

  void _shareWithRoommate() {
    final message = '''
VanishKey Temporary Login for ${widget.device.deviceName}:
Username: ${widget.credential.username}
Password: ${widget.credential.password}

Note: Standard user permissions only. This account and its files will self-destruct in $_remainingSeconds seconds.
''';
    Clipboard.setData(ClipboardData(text: message));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Login message copied! Paste it to your roommate.')),
    );
  }

  void _handleEmergencyTerminate() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('End Session Now?', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: const Text(
          'This will immediately lock your laptop, terminate all guest processes, and permanently delete the temporary account from Windows.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<RelayService>().terminateSession(
                deviceId: widget.device.deviceId,
                username: widget.credential.username,
              );
              _timer.cancel();
              setState(() {
                _remainingSeconds = 0;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  backgroundColor: Color(0xFF991B1B),
                  content: Text('Kill signal sent. Account forcefully wiped on laptop.'),
                ),
              );
            },
            child: const Text('Kill Session & Wipe', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isExpired = _remainingSeconds <= 0;
    final totalSeconds = widget.credential.durationSeconds;
    final progress = totalSeconds > 0 ? (_remainingSeconds / totalSeconds) : 0.0;
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Temporary Access Granted'),
        backgroundColor: const Color(0xFF1E293B),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Circular Countdown Timer
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 170,
                    height: 170,
                    child: CircularProgressIndicator(
                      value: isExpired ? 0.0 : progress,
                      strokeWidth: 10,
                      backgroundColor: const Color(0xFF334155),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isExpired
                            ? Colors.redAccent
                            : (_remainingSeconds < 30 ? Colors.orangeAccent : const Color(0xFF38BDF8)),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isExpired
                            ? 'EXPIRED'
                            : '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: isExpired ? Colors.redAccent : Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isExpired ? 'Account purged' : 'Remaining Time',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            if (isExpired) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF7F1D1D).withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.redAccent),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber, color: Colors.redAccent, size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This temporary credential has expired. The user session, account, and directory have been purged from the laptop.',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Security Warning Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C4A6E).withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF0284C7)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock_outline, color: Color(0xFF38BDF8), size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Standard User • Isolated from your private home folder & files • Auto-deleted upon timer expiration.',
                        style: TextStyle(color: Color(0xFFE0F2FE), fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Username Display
              _buildCredentialCard(
                label: 'GUEST ACCOUNT USERNAME',
                badge: 'Local User',
                value: widget.credential.username,
                onCopy: () => _copyToClipboard(widget.credential.username, 'Username'),
              ),
              const SizedBox(height: 16),

              // Password Display
              _buildCredentialCard(
                label: 'TEMPORARY PASSCODE',
                badge: '12-char CSPRNG',
                value: widget.credential.password,
                isPassword: true,
                obscure: _obscurePassword,
                onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
                onCopy: () => _copyToClipboard(widget.credential.password, 'Passcode'),
              ),
              const SizedBox(height: 24),

              // Share with Roommate Action Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.share_outlined, color: Colors.white, size: 20),
                  label: const Text(
                    'Copy Full Login Details for Roommate',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  onPressed: _shareWithRoommate,
                ),
              ),
              const SizedBox(height: 12),

              // Emergency Kill-Switch Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.power_settings_new_rounded, color: Colors.redAccent, size: 20),
                  label: const Text(
                    'End Session & Wipe Account Now',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.redAccent),
                  ),
                  onPressed: _handleEmergencyTerminate,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCredentialCard({
    required String label,
    required String badge,
    required String value,
    bool isPassword = false,
    bool obscure = false,
    VoidCallback? onToggleObscure,
    required VoidCallback onCopy,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8), letterSpacing: 0.5),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(fontSize: 10, color: Color(0xFF38BDF8), fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  obscure ? '••••••••••••' : value,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: Color(0xFF38BDF8),
                  ),
                ),
              ),
              if (isPassword)
                IconButton(
                  tooltip: obscure ? 'Show password' : 'Hide password',
                  icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: Colors.white70, size: 20),
                  onPressed: onToggleObscure,
                ),
              IconButton(
                tooltip: 'Copy to clipboard',
                icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 20),
                onPressed: onCopy,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
