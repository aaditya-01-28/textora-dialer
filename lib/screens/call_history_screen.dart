import 'package:flutter/material.dart';
import '../models/call_sync_item.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  final _storage = StorageService();
  final _api = ApiService();

  List<CallSyncItem> _calls = [];
  bool _isLoading = true;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final list = await _storage.getCallHistory();
    if (mounted) {
      setState(() {
        _calls = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _syncPending() async {
    setState(() => _isSyncing = true);
    final count = await _api.flushOfflineQueue();
    await _loadHistory();
    if (mounted) {
      setState(() => _isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully synced $count pending calls to CRM')),
      );
    }
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _calls.where((c) => !c.isSynced).length;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC);
    final appBarBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final remarkColor = isDark ? const Color(0xFF64748B) : const Color(0xFF64748B);
    final borderColor = isDark ? const Color(0xFF334155).withValues(alpha: 0.4) : const Color(0xFFE2E8F0);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        backgroundColor: appBarBg,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(11.0),
          child: Image.asset(
            'assets/images/icon.png',
            fit: BoxFit.contain,
          ),
        ),
        title: Text(
          'Mobile Call Logs & Sync',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: titleColor),
        ),
        actions: [
          if (pendingCount > 0)
            TextButton.icon(
              onPressed: _isSyncing ? null : _syncPending,
              icon: _isSyncing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                    )
                  : const Icon(Icons.sync, size: 16, color: Color(0xFF10B981)),
              label: Text(
                'Sync ($pendingCount)',
                style: const TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold),
              ),
            )
          else
            IconButton(
              icon: Icon(Icons.refresh, color: isDark ? Colors.white70 : const Color(0xFF475569)),
              onPressed: _loadHistory,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : _calls.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_toggle_off, color: subColor, size: 48),
                        const SizedBox(height: 12),
                        Text(
                          'No calls logged yet on this device.',
                          style: TextStyle(color: titleColor, fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Calls dialed from the Leads tab will automatically appear here with exact carrier duration.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: subColor, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _calls.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final call = _calls[index];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: borderColor),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: call.durationSeconds > 0
                                  ? const Color(0xFF059669).withValues(alpha: 0.15)
                                  : Colors.amber.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              call.durationSeconds > 0 ? Icons.call_made : Icons.phone_missed,
                              color: call.durationSeconds > 0 ? const Color(0xFF10B981) : Colors.amber,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  call.phoneNumber,
                                  style: TextStyle(
                                    color: titleColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${call.disposition} • Talk Time: ${_formatDuration(call.durationSeconds)}',
                                  style: TextStyle(color: subColor, fontSize: 12),
                                ),
                                if (call.remark != null && call.remark!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    call.remark!,
                                    style: TextStyle(color: remarkColor, fontSize: 11, fontStyle: FontStyle.italic),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: call.isSynced
                                      ? const Color(0xFF059669).withValues(alpha: 0.2)
                                      : Colors.amber.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  call.isSynced ? 'Synced' : 'Pending',
                                  style: TextStyle(
                                    color: call.isSynced ? const Color(0xFF10B981) : Colors.amber,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Builder(
                                builder: (_) {
                                  String timeStr = '';
                                  try {
                                    final dt = DateTime.parse(call.callTimestamp).toLocal();
                                    final h = dt.hour.toString().padLeft(2, '0');
                                    final m = dt.minute.toString().padLeft(2, '0');
                                    timeStr = '$h:$m';
                                  } catch (_) {
                                    timeStr = call.callTimestamp.length > 16 ? call.callTimestamp.substring(11, 16) : '';
                                  }
                                  return Text(
                                    timeStr,
                                    style: TextStyle(color: subColor, fontSize: 10),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
