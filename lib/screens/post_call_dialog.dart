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
    // 1. Dispose in CRM — this updates lead status, tasks, pipeline, and records the call log as apk_manual
    await api.disposeLead(
      leadId: widget.lead.id,
      disposition: _disposition,
      durationSeconds: widget.call.durationSeconds,
      remark: remark.isNotEmpty ? remark : null,
    );

    if (!mounted) return;
    widget.onSaved();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final modalBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final inputBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final inputBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final chipBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: modalBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Call Completed',
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.lead.displayName,
                    style: TextStyle(color: subColor, fontSize: 13),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.15),
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

          Text(
            'Select Call Outcome / Disposition:',
            style: TextStyle(color: subColor, fontSize: 12, fontWeight: FontWeight.w600),
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
                backgroundColor: chipBg,
                labelStyle: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF475569),
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isSelected
                        ? const Color(0xFF10B981)
                        : isDark
                            ? const Color(0xFF334155).withValues(alpha: 0.6)
                            : const Color(0xFFCBD5E1),
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
            style: TextStyle(color: titleColor, fontSize: 13),
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Discussion notes, price discussed, next action...',
              hintStyle: TextStyle(color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8), fontSize: 12),
              filled: true,
              fillColor: inputBg,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: inputBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: inputBorder),
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
