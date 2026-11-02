import 'dart:async';
import 'dart:ui';
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
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E293B),
        content: Text('$label copied to clipboard', style: const TextStyle(color: Colors.white)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _shareWithRoommate() {
    HapticFeedback.lightImpact();
    final message = '''
VanishKey Temporary Login for ${widget.device.deviceName}:
Username: ${widget.credential.username}
Password: ${widget.credential.password}

Note: Standard guest permissions only. This temporary session automatically logs off and purges all files in $_remainingSeconds seconds.
''';
    Clipboard.setData(ClipboardData(text: message));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF0C4A6E),
        content: const Text('Login details copied! Paste them to your guest.', style: TextStyle(color: Colors.white)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _handleEmergencyTerminate() {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('End Session Now?', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: const Text(
          'This will immediately log off the guest session, return your laptop to your primary lock screen, and permanently delete the temporary account.',
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
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                SnackBar(
                  backgroundColor: const Color(0xFF991B1B),
                  content: const Text('Kill signal sent. Guest session logged off and wiped.'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            child: const Text('Kill Session & Wipe', style: TextStyle(fontWeight: FontWeight.bold)),
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
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        title: const Text('Temporary Access Granted', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF131B2E),
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white70),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
          children: [
            // Circular Countdown Timer
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 180,
                    height: 180,
                    child: CircularProgressIndicator(
                      value: isExpired ? 0.0 : progress,
                      strokeWidth: 10,
                      backgroundColor: const Color(0xFF1E293B),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isExpired
                            ? Colors.redAccent
                            : (_remainingSeconds < 60 ? Colors.orangeAccent : const Color(0xFF38BDF8)),
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
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          color: isExpired ? Colors.redAccent : Colors.white,
                          letterSpacing: 2,
                          fontFeatures: const [FontFeature.tabularFigures()],
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
            const SizedBox(height: 28),

            if (isExpired) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF7F1D1D).withOpacity(0.35),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.redAccent.withOpacity(0.1),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock_reset_rounded, color: Colors.redAccent, size: 28),
                    SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Time limit reached. The guest session was logged out and the laptop has locked back to the primary user.',
                        style: TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Fast-Logon & Security Info Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C4A6E).withOpacity(0.25),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.4)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0284C7).withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.bolt_rounded, color: Color(0xFF38BDF8), size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Fast Desktop Sign-in: First logon animation skipped • Direct desktop access • Auto-logs out to primary lock screen on expiry.',
                        style: TextStyle(color: Color(0xFFE0F2FE), fontSize: 12, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Username Display Card
              _buildCredentialCard(
                label: 'GUEST ACCOUNT USERNAME',
                badge: 'Local User',
                value: widget.credential.username,
                onCopy: () => _copyToClipboard(widget.credential.username, 'Username'),
              ),
              const SizedBox(height: 14),

              // Password Display Card
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 3,
                  ),
                  icon: const Icon(Icons.share_outlined, color: Colors.white, size: 20),
                  label: const Text(
                    'Copy Full Login Details for Guest',
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E293B)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1E293B)),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(fontSize: 10, color: Color(0xFF38BDF8), fontWeight: FontWeight.w600),
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
