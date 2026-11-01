import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/credential.dart';
import '../models/device.dart';

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
                label: 'TEMPORARY USERNAME',
                value: widget.credential.username,
                onCopy: () => _copyToClipboard(widget.credential.username, 'Username'),
              ),
              const SizedBox(height: 16),

              // Password Display
              _buildCredentialCard(
                label: 'CSPRNG PASSWORD (ONE-TIME VIEW)',
                value: widget.credential.password,
                isPassword: true,
                obscure: _obscurePassword,
                onToggleObscure: () => setState(() => _obscurePassword = !_obscurePassword),
                onCopy: () => _copyToClipboard(widget.credential.password, 'Password'),
              ),
              const SizedBox(height: 28),

              // Share with Roommate Action Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.share, color: Colors.white),
                  label: const Text(
                    'Copy Full Login Details for Roommate',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  onPressed: _shareWithRoommate,
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
    required String value,
    bool isPassword = false,
    bool obscure = false,
    VoidCallback? onToggleObscure,
    required VoidCallback onCopy,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8))),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  obscure ? '•' * value.length : value,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF38BDF8),
                  ),
                ),
              ),
              if (isPassword)
                IconButton(
                  icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white70),
                  onPressed: onToggleObscure,
                ),
              IconButton(
                icon: const Icon(Icons.copy, color: Colors.white70),
                onPressed: onCopy,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
