import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class PinLockScreen extends StatefulWidget {
  final AuthService authService;
  final VoidCallback onAuthenticated;

  const PinLockScreen({
    super.key,
    required this.authService,
    required this.onAuthenticated,
  });

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  String _enteredPin = '';
  bool _isSettingUp = false;
  String _firstPinAttempt = '';
  String _statusMessage = 'Enter your 6-digit Owner PIN';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkSetup();
  }

  Future<void> _checkSetup() async {
    final hasPin = await widget.authService.hasConfiguredPin();
    setState(() {
      _isSettingUp = !hasPin;
      _statusMessage = _isSettingUp
          ? 'Set a 6-digit Master PIN to secure VanishKey'
          : 'Enter Owner PIN';
      _isLoading = false;
    });

    if (hasPin) {
      _tryBiometricPrompt();
    }
  }

  Future<void> _tryBiometricPrompt() async {
    final authenticated = await widget.authService.authenticateBiometrics(
      reason: 'Unlock VanishKey with Biometrics',
    );
    if (authenticated && mounted) {
      widget.onAuthenticated();
    }
  }

  void _onKeyPressed(String digit) {
    if (_enteredPin.length < 6) {
      setState(() {
        _enteredPin += digit;
      });

      if (_enteredPin.length == 6) {
        _handlePinComplete();
      }
    }
  }

  void _onDelete() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      });
    }
  }

  Future<void> _handlePinComplete() async {
    if (_isSettingUp) {
      if (_firstPinAttempt.isEmpty) {
        setState(() {
          _firstPinAttempt = _enteredPin;
          _enteredPin = '';
          _statusMessage = 'Confirm your 6-digit PIN';
        });
      } else {
        if (_enteredPin == _firstPinAttempt) {
          await widget.authService.setOwnerPin(_enteredPin);
          if (mounted) {
            widget.onAuthenticated();
          }
        } else {
          setState(() {
            _firstPinAttempt = '';
            _enteredPin = '';
            _statusMessage = 'PINs did not match. Enter a new 6-digit PIN:';
          });
        }
      }
    } else {
      final isValid = await widget.authService.verifyPin(_enteredPin);
      if (isValid) {
        if (mounted) {
          widget.onAuthenticated();
        }
      } else {
        setState(() {
          _enteredPin = '';
          _statusMessage = 'Incorrect PIN. Try again:';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            const Icon(Icons.shield_outlined, size: 72, color: Color(0xFF38BDF8)),
            const SizedBox(height: 16),
            const Text(
              'VanishKey',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 24),
            // PIN Dots Indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (index) {
                final isFilled = index < _enteredPin.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFilled ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                  ),
                );
              }),
            ),
            const Spacer(),
            // Numeric Keypad
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                children: [
                  for (var row = 0; row < 3; row++) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (var col = 1; col <= 3; col++) ...[
                          _buildNumBtn('${row * 3 + col}'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        iconSize: 32,
                        icon: const Icon(Icons.fingerprint, color: Color(0xFF38BDF8)),
                        onPressed: _isSettingUp ? null : _tryBiometricPrompt,
                      ),
                      _buildNumBtn('0'),
                      IconButton(
                        iconSize: 32,
                        icon: const Icon(Icons.backspace_outlined, color: Colors.white70),
                        onPressed: _onDelete,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildNumBtn(String digit) {
    return InkWell(
      onTap: () => _onKeyPressed(digit),
      borderRadius: BorderRadius.circular(40),
      child: Container(
        width: 72,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1E293B),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Text(
          digit,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ),
    );
  }
}
