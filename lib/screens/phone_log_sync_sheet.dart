import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/call_sync_item.dart';
import '../models/lead_item.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/telephony_service.dart';
import 'post_call_dialog.dart';

/// Shared bottom sheet to inspect native Android phone dialer call logs
/// (for a single Lead or across all CRM Leads) and dispose or bulk-sync
/// missing talk-time & RNR records to the CRM.
class PhoneLogSyncSheet extends StatefulWidget {
  final LeadItem? lead;
  final VoidCallback? onSynced;

  const PhoneLogSyncSheet({
    super.key,
    this.lead,
    this.onSynced,
  });

  static Future<void> show(
    BuildContext context, {
    LeadItem? lead,
    VoidCallback? onSynced,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PhoneLogSyncSheet(lead: lead, onSynced: onSynced),
    );
  }

  @override
  State<PhoneLogSyncSheet> createState() => _PhoneLogSyncSheetState();
}

class _PhoneLogSyncSheetState extends State<PhoneLogSyncSheet> {
  final _telephony = TelephonyService();
  final _api = ApiService();
  final _storage = StorageService();

  int _lookbackDays = 7;
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _showOnlyMissing = false;
  List<Map<String, dynamic>> _entries = [];
  final Set<String> _selectedSignatures = {};

  @override
  void initState() {
    super.initState();
    _showOnlyMissing = widget.lead == null;
    _scanCalls();
  }

  Future<void> _scanCalls() async {
    setState(() => _isLoading = true);
    List<Map<String, dynamic>> scanned = [];
    if (widget.lead != null) {
      scanned = await _telephony.scanPhoneCallsForLead(
        widget.lead!,
        lookbackDays: _lookbackDays,
      );
    } else {
      scanned = await _telephony.scanAllCrmPhoneCalls(
        lookbackDays: _lookbackDays,
      );
    }

    if (!mounted) return;
    setState(() {
      _entries = scanned;
      _selectedSignatures.clear();
      for (final item in scanned) {
        if (item['isLogged'] != true) {
          _selectedSignatures.add(item['signature'] as String);
        }
      }
      _isLoading = false;
    });
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0s';
    final mins = seconds ~/ 60;
    final rem = seconds % 60;
    if (mins > 0) return '${mins}m ${rem}s';
    return '${seconds}s';
  }

  List<Map<String, dynamic>> get _selectedUnloggedEntries {
    final list = _entries
        .where((e) =>
            e['isLogged'] != true && _selectedSignatures.contains(e['signature']))
        .toList();
    // Process oldest-first so the newest call ultimately governs lead status
    list.sort((a, b) =>
        (a['timestampEpoch'] as int).compareTo(b['timestampEpoch'] as int));
    return list;
  }

  Future<void> _disposeOneByOne() async {
    final queue = _selectedUnloggedEntries;
    if (queue.isEmpty) return;

    int processed = 0;
    for (int i = 0; i < queue.length; i++) {
      if (!mounted) break;
      final item = queue[i];
      final lead = item['lead'] as LeadItem;
      final call = item['call'] as CallSyncItem;
      final sig = item['signature'] as String;
      final isInbound = item['isInbound'] == true;

      bool shouldStop = false;
      bool savedThis = false;

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        isDismissible: true,
        enableDrag: true,
        backgroundColor: Colors.transparent,
        builder: (_) => PostCallDialog(
          lead: lead,
          call: call,
          isInbound: isInbound,
          isAutoDetectedOutbound: !isInbound,
          historicalSync: true,
          queueLabel: queue.length > 1 ? '${i + 1} of ${queue.length}' : null,
          onSaved: () async {
            savedThis = true;
            processed += 1;
            await _storage.markCallSignatureProcessed(sig);
          },
          onDismissed: () {
            if (!savedThis && queue.length > 1) {
              // Closing/skipping continues to next unless cancelled
            }
          },
        ),
      );

      if (!savedThis && i + 1 < queue.length && mounted) {
        final cont = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Continue Remaining Calls?'),
            content: Text(
              'You skipped ${call.phoneNumber}. Continue disposing the remaining ${queue.length - i - 1} call(s)?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Stop Queue'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Next Call'),
              ),
            ],
          ),
        );
        if (cont != true) shouldStop = true;
      }
      if (shouldStop) break;
    }

    _telephony.clearCaches();
    _telephony.notifyCallCompleted();
    widget.onSynced?.call();
    if (mounted) {
      await _scanCalls();
      if (processed > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF059669),
            content: Text('Disposed $processed phone call log(s) to CRM ✅'),
          ),
        );
      }
    }
  }

  Future<void> _bulkSyncSelected() async {
    final queue = _selectedUnloggedEntries;
    if (queue.isEmpty) return;

    String selectedOutcome = 'Auto';
    final remarkCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('Bulk Log ${queue.length} Phone Call(s)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Exact talk durations and original phone timestamps will be preserved.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedOutcome,
                decoration: const InputDecoration(
                  labelText: 'Disposition',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Auto',
                    child: Text('Auto (Connected for >0s, RNR for 0s)'),
                  ),
                  DropdownMenuItem(value: 'Connected', child: Text('Connected')),
                  DropdownMenuItem(value: 'Interested', child: Text('Interested 🔥')),
                  DropdownMenuItem(value: 'Callback', child: Text('Callback')),
                  DropdownMenuItem(value: 'RNR', child: Text('RNR')),
                ],
                onChanged: (val) {
                  if (val != null) setDlgState(() => selectedOutcome = val);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: remarkCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notes / Remark (Optional)',
                  hintText: 'e.g. Historical phone call log synced',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              ),
              child: Text('Sync ${queue.length} Call(s)'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) {
      remarkCtrl.dispose();
      return;
    }

    setState(() => _isSyncing = true);
    final customRemark = remarkCtrl.text.trim();
    remarkCtrl.dispose();

    final itemsToSync = <CallSyncItem>[];
    for (final entry in queue) {
      final call = entry['call'] as CallSyncItem;
      final isInbound = entry['isInbound'] == true;
      final isMissed = entry['isMissed'] == true;
      final disp = selectedOutcome == 'Auto'
          ? (isInbound
              ? (isMissed ? 'RNR' : 'Connected')
              : (call.durationSeconds > 0 ? 'Connected' : 'RNR'))
          : selectedOutcome;

      itemsToSync.add(CallSyncItem(
        id: call.id,
        leadId: call.leadId,
        phoneNumber: call.phoneNumber,
        durationSeconds: call.durationSeconds,
        disposition: disp,
        callTimestamp: call.callTimestamp,
        remark: customRemark.isNotEmpty ? customRemark : call.remark,
        logSource: call.logSource,
        isInterested: disp == 'Interested',
      ));
    }

    final syncedCount = await _api.batchSyncCallLogs(
      itemsToSync,
      historicalSync: true,
    );
    if (syncedCount > 0) {
      for (final entry in queue) {
        await _storage.markCallSignatureProcessed(entry['signature'] as String);
      }
      _telephony.clearCaches();
      _telephony.notifyCallCompleted();
      widget.onSynced?.call();
    }

    if (!mounted) return;
    setState(() => _isSyncing = false);
    await _scanCalls();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: syncedCount > 0 ? const Color(0xFF059669) : Colors.redAccent,
          content: Text(
            syncedCount > 0
                ? 'Synced $syncedCount historical call(s) & talk time to CRM ✅'
                : 'Failed to sync phone logs. Please check connection.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final cardBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final unloggedEntries = _entries.where((e) => e['isLogged'] != true).toList();
    final missingTalkSecs = unloggedEntries.fold<int>(
      0,
      (sum, e) => sum + (e['call'] as CallSyncItem).durationSeconds,
    );
    final visibleEntries = _showOnlyMissing ? unloggedEntries : _entries;
    final selectedCount = _selectedUnloggedEntries.length;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle + Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: borderColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.phone_in_talk_rounded, color: Color(0xFF10B981), size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.lead != null
                                ? 'Phone Call Logs — ${widget.lead!.displayTitle}'
                                : 'Scan Phone Dialer Logs (CRM Leads)',
                            style: TextStyle(
                              color: titleColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            widget.lead != null
                                ? 'Review carrier calls for +91 ${widget.lead!.phoneNumber} & dispose missing logs'
                                : 'Find missed/historical phone calls across CRM leads',
                            style: TextStyle(color: subColor, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.refresh_rounded, color: subColor, size: 20),
                      onPressed: _isLoading ? null : _scanCalls,
                      tooltip: 'Rescan Phone Logs',
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: subColor, size: 22),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Lookback filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final opt in const [
                        {'days': 1, 'label': 'Today'},
                        {'days': 7, 'label': '7 Days'},
                        {'days': 30, 'label': '30 Days'},
                        {'days': 90, 'label': 'All (90d)'},
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(opt['label'] as String),
                            selected: _lookbackDays == (opt['days'] as int),
                            selectedColor: const Color(0xFF10B981),
                            labelStyle: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _lookbackDays == (opt['days'] as int)
                                  ? Colors.white
                                  : subColor,
                            ),
                            onSelected: (_) {
                              setState(() => _lookbackDays = opt['days'] as int);
                              _scanCalls();
                            },
                          ),
                        ),
                      if (widget.lead != null)
                        FilterChip(
                          label: const Text('Missing Only'),
                          selected: _showOnlyMissing,
                          selectedColor: Colors.amber.withValues(alpha: 0.25),
                          labelStyle: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _showOnlyMissing ? Colors.amber : subColor,
                          ),
                          onSelected: (v) => setState(() => _showOnlyMissing = v),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Summary Strip
                if (!_isLoading)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: unloggedEntries.isNotEmpty
                          ? Colors.amber.withValues(alpha: 0.12)
                          : const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: unloggedEntries.isNotEmpty
                            ? Colors.amber.withValues(alpha: 0.35)
                            : const Color(0xFF10B981).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          unloggedEntries.isNotEmpty
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 16,
                          color: unloggedEntries.isNotEmpty
                              ? Colors.amber
                              : const Color(0xFF10B981),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            unloggedEntries.isNotEmpty
                                ? '${unloggedEntries.length} unlogged call(s) • ${_formatDuration(missingTalkSecs)} missing talk time'
                                : 'All ${_entries.length} phone call(s) in this period are synced to CRM',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: titleColor,
                            ),
                          ),
                        ),
                        if (unloggedEntries.isNotEmpty)
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () {
                              setState(() {
                                if (selectedCount == unloggedEntries.length) {
                                  _selectedSignatures.clear();
                                } else {
                                  for (final e in unloggedEntries) {
                                    _selectedSignatures.add(e['signature'] as String);
                                  }
                                }
                              });
                            },
                            child: Text(
                              selectedCount == unloggedEntries.length
                                  ? 'Clear All'
                                  : 'Select All',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Call List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF10B981)),
                  )
                : visibleEntries.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            widget.lead != null
                                ? 'No phone calls found for this number in the last $_lookbackDays day(s).'
                                : 'No unlogged CRM calls found in the last $_lookbackDays day(s).',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: subColor, fontSize: 13),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: visibleEntries.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, idx) {
                          final item = visibleEntries[idx];
                          final lead = item['lead'] as LeadItem;
                          final call = item['call'] as CallSyncItem;
                          final sig = item['signature'] as String;
                          final isInbound = item['isInbound'] == true;
                          final isMissed = item['isMissed'] == true;
                          final isLogged = item['isLogged'] == true;
                          final isSelected = _selectedSignatures.contains(sig);

                          String timeLabel = call.callTimestamp;
                          try {
                            final dt = DateTime.parse(call.callTimestamp).toLocal();
                            timeLabel = DateFormat('dd MMM yyyy, hh:mm a').format(dt);
                          } catch (_) {}

                          final dirLabel = isMissed
                              ? 'Missed Inbound'
                              : isInbound
                                  ? 'Incoming Call'
                                  : 'Outgoing Call';
                          final iconData = isMissed
                              ? Icons.call_missed_rounded
                              : isInbound
                                  ? Icons.call_received_rounded
                                  : Icons.call_made_rounded;
                          final iconColor = isMissed
                              ? Colors.amber
                              : call.durationSeconds > 0
                                  ? const Color(0xFF10B981)
                                  : Colors.amber;

                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: isLogged
                                ? null
                                : () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedSignatures.remove(sig);
                                      } else {
                                        _selectedSignatures.add(sig);
                                      }
                                    });
                                  },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: !isLogged && isSelected
                                      ? const Color(0xFF10B981)
                                      : borderColor,
                                ),
                              ),
                              child: Row(
                                children: [
                                  if (!isLogged)
                                    Checkbox(
                                      value: isSelected,
                                      activeColor: const Color(0xFF10B981),
                                      visualDensity: VisualDensity.compact,
                                      onChanged: (v) {
                                        setState(() {
                                          if (v == true) {
                                            _selectedSignatures.add(sig);
                                          } else {
                                            _selectedSignatures.remove(sig);
                                          }
                                        });
                                      },
                                    )
                                  else
                                    const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 10),
                                      child: Icon(
                                        Icons.check_circle_rounded,
                                        color: Color(0xFF10B981),
                                        size: 20,
                                      ),
                                    ),
                                  Icon(iconData, color: iconColor, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                widget.lead == null
                                                    ? '${lead.displayTitle} • $dirLabel'
                                                    : dirLabel,
                                                style: TextStyle(
                                                  color: titleColor,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isLogged
                                                    ? const Color(0xFF10B981).withValues(alpha: 0.14)
                                                    : Colors.amber.withValues(alpha: 0.16),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                isLogged ? 'In CRM' : 'Missing',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: isLogged
                                                      ? const Color(0xFF10B981)
                                                      : Colors.amber,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$timeLabel • ${call.phoneNumber}',
                                          style: TextStyle(color: subColor, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _formatDuration(call.durationSeconds),
                                    style: TextStyle(
                                      color: call.durationSeconds > 0
                                          ? const Color(0xFF10B981)
                                          : subColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // Action Bar
          if (!_isLoading && selectedCount > 0)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              decoration: BoxDecoration(
                color: sheetBg,
                border: Border(top: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSyncing ? null : _bulkSyncSelected,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF10B981),
                        side: const BorderSide(color: Color(0xFF10B981)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: _isSyncing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF10B981),
                              ),
                            )
                          : const Icon(Icons.bolt_rounded, size: 16),
                      label: Text(
                        'Bulk Log ($selectedCount)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isSyncing ? null : _disposeOneByOne,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
                      label: Text(
                        'Dispose Selected ($selectedCount)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
