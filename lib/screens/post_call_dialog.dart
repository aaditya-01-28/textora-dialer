import 'package:flutter/material.dart';
import '../models/call_sync_item.dart';
import '../models/lead_item.dart';
import '../services/api_service.dart';

class PostCallDialog extends StatefulWidget {
  final LeadItem lead;
  final CallSyncItem call;
  final VoidCallback onSaved;

  const PostCallDialog({
    super.key,
    required this.lead,
    required this.call,
    required this.onSaved,
  });

  @override
  State<PostCallDialog> createState() => _PostCallDialogState();
}

class _PostCallDialogState extends State<PostCallDialog> {
  late String _disposition;
  final _remarkController = TextEditingController();
  bool _isSaving = false;

  final List<String> _dispositions = [
    'Connected',
    'Callback',
    'Demo Scheduled',
    'RNR',
    'Not Interested',
    'Already Using',
    'Invalid',
  ];

  @override
  void initState() {
    super.initState();
    _disposition = widget.call.disposition;
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0s (Not Connected)';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    final remark = _remarkController.text.trim();

    final api = ApiService();
    // 1. Dispose in CRM
    await api.disposeLead(
      leadId: widget.lead.id,
      disposition: _disposition,
      durationSeconds: widget.call.durationSeconds,
      remark: remark.isNotEmpty ? remark : null,
    );

    // 2. Also ensure CallLog is synced
    final updatedCall = CallSyncItem(
      id: widget.call.id,
      leadId: widget.lead.id,
      phoneNumber: widget.lead.phoneNumber,
      durationSeconds: widget.call.durationSeconds,
      disposition: _disposition,
      callTimestamp: widget.call.callTimestamp,
      remark: remark.isNotEmpty ? remark : null,
    );
    await api.syncCallLog(updatedCall);

    if (!mounted) return;
    widget.onSaved();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Call Completed',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.lead.displayName,
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.4)),
                ),
                child: Text(
                  _formatDuration(widget.call.durationSeconds),
                  style: const TextStyle(
                    color: Color(0xFF10B981),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          const Text(
            'Select Call Outcome / Disposition:',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),

          // Disposition Chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _dispositions.map((d) {
              final isSelected = _disposition == d;
              return ChoiceChip(
                label: Text(d),
                selected: isSelected,
                selectedColor: const Color(0xFF059669),
                backgroundColor: const Color(0xFF1E293B),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isSelected ? const Color(0xFF10B981) : Colors.transparent,
                  ),
                ),
                onSelected: (_) => setState(() => _disposition = d),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // Remarks Input
          TextField(
            controller: _remarkController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Discussion notes, price discussed, next action...',
              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Save Button
          ElevatedButton(
            onPressed: _isSaving ? null : _handleSave,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isSaving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text(
                    'Save & Sync to Web Dashboard',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
          ),
        ],
      ),
    );
  }
}
