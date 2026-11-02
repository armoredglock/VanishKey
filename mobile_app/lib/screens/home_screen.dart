import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    int durationMinutes = 15;
    final selectedDuration = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (bottomCtx, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF334155),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C4A6E).withOpacity(0.4),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.timer_outlined, color: Color(0xFF38BDF8), size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Select Access Duration',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'When time runs out, Windows will automatically log off the guest and return to your primary lock screen.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8), height: 1.3),
                  ),
                  const SizedBox(height: 18),
                  _buildDurationOption(
                    bottomCtx,
                    minutes: 5,
                    title: '5 Minutes',
                    subtitle: 'Quick task (e.g. print a document or send a file)',
                    isRecommended: false,
                  ),
                  const SizedBox(height: 10),
                  _buildDurationOption(
                    bottomCtx,
                    minutes: 15,
                    title: '15 Minutes',
                    subtitle: 'Recommended duration for casual guest access',
                    isRecommended: true,
                  ),
                  const SizedBox(height: 10),
                  _buildDurationOption(
                    bottomCtx,
                    minutes: 30,
                    title: '30 Minutes',
                    subtitle: 'Work or study session / presentation',
                    isRecommended: false,
                  ),
                  const SizedBox(height: 10),
                  _buildDurationOption(
                    bottomCtx,
                    minutes: 60,
                    title: '1 Hour',
                    subtitle: 'Extended temporary guest access',
                    isRecommended: false,
                  ),
                  const SizedBox(height: 12),
                  // Custom Time Limit Option
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      HapticFeedback.lightImpact();
                      final customMinutes = await _showCustomDurationDialog(context);
                      if (customMinutes != null && context.mounted) {
                        Navigator.pop(bottomCtx, customMinutes);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF131B2E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4), width: 1.2),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF38BDF8).withOpacity(0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF38BDF8).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.tune_rounded, color: Color(0xFF38BDF8), size: 20),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Custom Duration...',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Set any custom limit in minutes (1m to 24h)',
                                  style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF38BDF8), size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
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

  static Future<int?> _showCustomDurationDialog(BuildContext context) async {
    int currentMinutes = 20;
    final controller = TextEditingController(text: currentMinutes.toString());

    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F172A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (dlgCtx) {
        return StatefulBuilder(
          builder: (modalCtx, setDlgState) {
            final hours = currentMinutes ~/ 60;
            final mins = currentMinutes % 60;
            String durationLabel = '';
            if (hours > 0 && mins > 0) {
              durationLabel = '$hours hr $mins min';
            } else if (hours > 0) {
              durationLabel = '$hours hr';
            } else {
              durationLabel = '$mins min';
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 20,
                bottom: MediaQuery.of(dlgCtx).viewInsets.bottom + 28,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Custom Time Limit',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Specify exactly how long the guest session should remain active.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  // Display Counter Card
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 28),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131B2E),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF1E293B)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '$currentMinutes',
                              style: const TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF38BDF8),
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Minutes',
                              style: TextStyle(fontSize: 18, color: Colors.white70, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '($durationLabel)',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Stepper Adjustment Buttons
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildStepChip('-15m', () {
                          HapticFeedback.lightImpact();
                          setDlgState(() {
                            currentMinutes = (currentMinutes - 15).clamp(1, 1440);
                            controller.text = currentMinutes.toString();
                          });
                        }),
                        const SizedBox(width: 8),
                        _buildStepChip('-5m', () {
                          HapticFeedback.lightImpact();
                          setDlgState(() {
                            currentMinutes = (currentMinutes - 5).clamp(1, 1440);
                            controller.text = currentMinutes.toString();
                          });
                        }),
                        const SizedBox(width: 8),
                        _buildStepChip('-1m', () {
                          HapticFeedback.lightImpact();
                          setDlgState(() {
                            currentMinutes = (currentMinutes - 1).clamp(1, 1440);
                            controller.text = currentMinutes.toString();
                          });
                        }),
                        const SizedBox(width: 8),
                        _buildStepChip('+1m', () {
                          HapticFeedback.lightImpact();
                          setDlgState(() {
                            currentMinutes = (currentMinutes + 1).clamp(1, 1440);
                            controller.text = currentMinutes.toString();
                          });
                        }),
                        const SizedBox(width: 8),
                        _buildStepChip('+5m', () {
                          HapticFeedback.lightImpact();
                          setDlgState(() {
                            currentMinutes = (currentMinutes + 5).clamp(1, 1440);
                            controller.text = currentMinutes.toString();
                          });
                        }),
                        const SizedBox(width: 8),
                        _buildStepChip('+15m', () {
                          HapticFeedback.lightImpact();
                          setDlgState(() {
                            currentMinutes = (currentMinutes + 15).clamp(1, 1440);
                            controller.text = currentMinutes.toString();
                          });
                        }),
                        const SizedBox(width: 8),
                        _buildStepChip('+30m', () {
                          HapticFeedback.lightImpact();
                          setDlgState(() {
                            currentMinutes = (currentMinutes + 30).clamp(1, 1440);
                            controller.text = currentMinutes.toString();
                          });
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Direct Input Field
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontFeatures: [FontFeature.tabularFigures()]),
                    decoration: InputDecoration(
                      labelText: 'Or enter custom minutes directly',
                      labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      prefixIcon: const Icon(Icons.edit_outlined, color: Color(0xFF38BDF8), size: 20),
                      filled: true,
                      fillColor: const Color(0xFF131B2E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF1E293B)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF1E293B)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF38BDF8)),
                      ),
                    ),
                    onChanged: (val) {
                      final parsed = int.tryParse(val);
                      if (parsed != null && parsed >= 1 && parsed <= 1440) {
                        setDlgState(() {
                          currentMinutes = parsed;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Color(0xFF334155)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => Navigator.pop(dlgCtx),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 2,
                          ),
                          icon: const Icon(Icons.check_rounded, size: 20),
                          label: Text(
                            'Grant $durationLabel',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            Navigator.pop(dlgCtx, currentMinutes);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static Widget _buildStepChip(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF38BDF8),
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  static Widget _buildDurationOption(
    BuildContext ctx, {
    required int minutes,
    required String title,
    required String subtitle,
    required bool isRecommended,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.pop(ctx, minutes);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF131B2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRecommended ? const Color(0xFF0284C7) : const Color(0xFF1E293B),
            width: isRecommended ? 1.5 : 1,
          ),
          boxShadow: isRecommended
              ? [
                  BoxShadow(
                    color: const Color(0xFF0284C7).withOpacity(0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
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
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
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
      actionHint = 'Make sure the laptop is awake and the VanishKey Host window is open.';
      icon = Icons.wifi_off_rounded;
      iconColor = Colors.orangeAccent;
    } else if (lower.contains('not paired') || lower.contains('not found')) {
      title = 'Laptop Not Connected';
      description = 'The relay server could not find your laptop.';
      actionHint = 'Run "Launch-VanishKey-Host.bat" on your laptop and re-pair using the QR scanner.';
      icon = Icons.devices_other_rounded;
      iconColor = Colors.blueAccent;
    }

    showModalBottomSheet(
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
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: iconColor, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                description,
                style: const TextStyle(fontSize: 14, color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF131B2E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1E293B)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb_outline, color: Color(0xFF38BDF8), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        actionHint,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8), height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmRevoke(BuildContext context, PairedDevice device) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Revoke Laptop Pairing?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will permanently disconnect ${device.deviceName}. You will need to scan a new QR code to reconnect.',
          style: const TextStyle(color: Colors.white70),
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
            child: const Text('Revoke', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showManualPair(BuildContext context) {
    final devIdCtrl = TextEditingController();
    final pinCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Manual Pair by PIN', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: devIdCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Device ID (e.g. dev_win32_1677AA)',
                labelStyle: TextStyle(color: Colors.white60),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white, letterSpacing: 4),
              decoration: const InputDecoration(
                labelText: '6-Digit Pairing PIN',
                labelStyle: TextStyle(color: Colors.white60),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            onPressed: () async {
              final devId = devIdCtrl.text.trim();
              final pin = pinCtrl.text.trim();
              if (devId.isEmpty || pin.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await context.read<RelayService>().pairDevice(
                  deviceId: devId,
                  pairingSecret: pin,
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
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF131B2E),
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
                      boxShadow: [
                        BoxShadow(
                          color: dev.isOnline
                              ? const Color(0xFF0284C7).withOpacity(0.15)
                              : Colors.black.withOpacity(0.3),
                          blurRadius: 16,
                          spreadRadius: 1,
                        ),
                      ],
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
