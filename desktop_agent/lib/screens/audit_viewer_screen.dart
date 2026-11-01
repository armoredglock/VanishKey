import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/relay_connection_service.dart';

class AuditViewerScreen extends StatelessWidget {
  const AuditViewerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final agent = context.watch<RelayConnectionService>();
    final logs = agent.localAuditLogs;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Host Local Audit Log'),
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: logs.isEmpty
          ? const Center(
              child: Text('No local audit records yet.', style: TextStyle(color: Color(0xFF94A3B8))),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: logs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, idx) {
                final log = logs[idx];
                final action = log['action'] ?? 'UNKNOWN';
                final status = log['status'] ?? 'UNKNOWN';
                final timestampStr = log['timestamp'];
                final details = log['details'] as Map<String, dynamic>? ?? {};

                DateTime? dt;
                if (timestampStr != null) {
                  dt = DateTime.tryParse(timestampStr)?.toLocal();
                }

                final formattedTime = dt != null
                    ? DateFormat('yyyy-MM-dd HH:mm:ss').format(dt)
                    : 'Unknown';

                final isSuccess = status == 'SUCCESS';

                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isSuccess ? Icons.check_circle : Icons.info_outline,
                            size: 18,
                            color: isSuccess ? Colors.greenAccent : const Color(0xFF38BDF8),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            action,
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const Spacer(),
                          Text(formattedTime, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                        ],
                      ),
                      if (details.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          details.entries.map((e) => '${e.key}: ${e.value}').join(' • '),
                          style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontFamily: 'monospace'),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }
}
