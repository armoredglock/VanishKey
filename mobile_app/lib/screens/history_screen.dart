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
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Access History'),
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF1E293B),
            child: const Row(
              children: [
                Icon(Icons.security, size: 20, color: Color(0xFF38BDF8)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Zero-Knowledge Audit Trail. Passwords and personal disk files are never recorded.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: logs.isEmpty
                ? const Center(
                    child: Text(
                      'No access history yet.',
                      style: TextStyle(color: Color(0xFF94A3B8)),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: relay.refreshAuditLogs,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: logs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, idx) {
                        final item = logs[idx];
                        final action = item['action'] as String? ?? 'UNKNOWN';
                        final status = item['status'] as String? ?? 'UNKNOWN';
                        final timestampStr = item['timestamp'] as String?;
                        final deviceId = item['deviceId'] as String? ?? 'Unknown';
                        final duration = item['durationMinutes'];

                        DateTime? dt;
                        if (timestampStr != null) {
                          dt = DateTime.tryParse(timestampStr)?.toLocal();
                        }

                        final formattedTime = dt != null
                            ? DateFormat('MMM d, yyyy • h:mm a').format(dt)
                            : 'Unknown time';

                        final isSuccess = status == 'SUCCESS';
                        final isRateLimit = status == 'RATE_LIMITED';

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSuccess
                                    ? Icons.check_circle_outline
                                    : (isRateLimit ? Icons.block : Icons.error_outline),
                                color: isSuccess
                                    ? Colors.greenAccent
                                    : (isRateLimit ? Colors.orangeAccent : Colors.redAccent),
                                size: 28,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      action.replaceAll('_', ' '),
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Device: $deviceId ${duration != null ? "• ($duration mins)" : ""}',
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
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isSuccess
                                      ? Colors.green.withOpacity(0.2)
                                      : Colors.red.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  status,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isSuccess ? Colors.greenAccent : Colors.redAccent,
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
