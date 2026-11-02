import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/relay_service.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final relay = context.watch<RelayService>();
    final logs = relay.auditHistory;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        title: const Text('Security Audit Trail'),
        backgroundColor: const Color(0xFF0A0E1A),
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0C4A6E).withOpacity(0.25),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.4)),
            ),
            child: const Row(
              children: [
                Icon(Icons.verified_user_outlined, size: 22, color: Color(0xFF38BDF8)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Zero-Knowledge Audit Trail: Passwords and personal disk files are never stored or logged.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFBAE6FD), height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: logs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: const Color(0xFF131B2E),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF1E293B)),
                          ),
                          child: const Icon(Icons.history_toggle_off_rounded, size: 36, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No Access Events Yet',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Temporary access requests will appear here in real-time.',
                          style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: relay.refreshAuditLogs,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: logs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, idx) {
                        final item = logs[idx];
                        final action = item['action'] as String? ?? 'ACCESS_REQUEST';
                        final status = item['status'] as String? ?? 'SUCCESS';
                        final timestampStr = item['timestamp'] as String?;
                        final deviceId = item['deviceId'] as String? ?? 'Laptop';
                        final duration = item['durationMinutes'];

                        DateTime? dt;
                        if (timestampStr != null) {
                          dt = DateTime.tryParse(timestampStr)?.toLocal();
                        }

                        final formattedTime = dt != null
                            ? DateFormat('MMM d, h:mm a').format(dt)
                            : 'Just now';

                        final isSuccess = status == 'SUCCESS';
                        final isRateLimit = status == 'RATE_LIMITED';

                        String displayTitle = 'Temporary Access Granted';
                        if (action.contains('TERMINATED') || action.contains('MANUAL')) {
                          displayTitle = 'Emergency Kill-Switch Used';
                        } else if (action.contains('PURGED') || action.contains('EXPIRED')) {
                          displayTitle = 'Session Expired & Purged';
                        } else if (isRateLimit) {
                          displayTitle = 'Rate Limit Throttled';
                        }

                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF131B2E),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSuccess ? const Color(0xFF1E293B) : Colors.redAccent.withOpacity(0.3),
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isSuccess
                                      ? const Color(0xFF065F46).withOpacity(0.3)
                                      : const Color(0xFF7F1D1D).withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  isSuccess
                                      ? Icons.check_circle_rounded
                                      : (isRateLimit ? Icons.block_rounded : Icons.warning_amber_rounded),
                                  color: isSuccess
                                      ? const Color(0xFF34D399)
                                      : (isRateLimit ? Colors.orangeAccent : Colors.redAccent),
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayTitle,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '$deviceId ${duration != null ? "• $duration min" : ""}',
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      formattedTime,
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isSuccess
                                      ? const Color(0xFF065F46).withOpacity(0.2)
                                      : const Color(0xFF7F1D1D).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isSuccess
                                        ? const Color(0xFF059669).withOpacity(0.4)
                                        : Colors.redAccent.withOpacity(0.4),
                                  ),
                                ),
                                child: Text(
                                  isSuccess ? 'AUTHORIZED' : status,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                    color: isSuccess ? const Color(0xFF34D399) : Colors.redAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
