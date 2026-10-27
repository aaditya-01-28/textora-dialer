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

    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text(
          'Mobile Call Logs & Sync',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          if (pendingCount > 0)
            TextButton.icon(
              onPressed: _isSyncing ? null : _syncPending,
              icon: _isSyncing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.sync, size: 16, color: Color(0xFF10B981)),
              label: Text(
                'Sync ($pendingCount)',
                style: const TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white70),
              onPressed: _loadHistory,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : _calls.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_toggle_off, color: Color(0xFF64748B), size: 48),
                        SizedBox(height: 12),
                        Text(
                          'No calls logged yet on this device.',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Calls dialed from the Leads tab will automatically appear here with exact carrier duration.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
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
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF334155).withValues(alpha: 0.4)),
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
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${call.disposition} • Talk Time: ${_formatDuration(call.durationSeconds)}',
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                ),
                                if (call.remark != null && call.remark!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    call.remark!,
                                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontStyle: FontStyle.italic),
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
                              Text(
                                call.callTimestamp.length > 16
                                    ? call.callTimestamp.substring(11, 16)
                                    : '',
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
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
