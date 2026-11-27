import 'package:flutter/material.dart';
import '../models/call_sync_item.dart';
import '../models/lead_item.dart';
import '../services/agenda_reminder_service.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/telephony_service.dart';

class PostCallDialog extends StatefulWidget {
  final LeadItem lead;
  final CallSyncItem call;
  final VoidCallback onSaved;
  final VoidCallback? onDismissed;
  final bool isInbound;
  final bool isAutoDetectedOutbound;
  final String? queueLabel;

  const PostCallDialog({
    super.key,
    required this.lead,
    required this.call,
    required this.onSaved,
    this.onDismissed,
    this.isInbound = false,
    this.isAutoDetectedOutbound = false,
    this.queueLabel,
  });

  @override
  State<PostCallDialog> createState() => _PostCallDialogState();
}

class _PostCallDialogState extends State<PostCallDialog> {
  late String _disposition;
  bool _isInterested = false;
  String _serviceOwner = 'our'; // 'our' or 'other'
  final _remarkController = TextEditingController();
  final _decisionMakerController = TextEditingController();
  final _meetingLinkController = TextEditingController();
  DateTime? _scheduledDateTime;
  bool _isSaving = false;
  bool _didSave = false;
  String? _errorMessage;
  bool _showAllDispositions = false;

  bool get _isScheduledDemo => widget.lead.status.toLowerCase().trim() == 'demo_scheduled';
  bool get _isScheduledCallback => widget.lead.status.toLowerCase().trim() == 'callback';
  bool get _isScheduledCustomer => _isScheduledDemo || _isScheduledCallback;

  final List<String> _dispositions = [
    'Interested',
    'Connected',
    'Callback',
    'Demo Scheduled',
    'Demo Done',
    'Future Requirement',
    'RNR',
    'Not Interested',
    'Already Using',
    'Invalid',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.isInbound) {
      if (widget.call.durationSeconds == 0) {
        _disposition = 'RNR';
        _remarkController.text = 'Missed inbound call from customer';
      } else {
        _disposition = 'Connected';
        _remarkController.text = 'Customer called back';
      }
    } else if (_isScheduledDemo) {
      _disposition = widget.call.durationSeconds > 0 ? 'Demo Done' : 'RNR';
    } else if (_isScheduledCallback) {
      _disposition = widget.call.durationSeconds > 0 ? 'Connected' : 'RNR';
    } else {
      final d = widget.call.disposition;
      if (d.contains('Other') || d.contains('Competitor') || d.contains('Purchased')) {
        _disposition = 'Already Using';
        _serviceOwner = 'other';
      } else if (d.contains('Our Service')) {
        _disposition = 'Already Using';
        _serviceOwner = 'our';
      } else {
        _disposition = d;
      }
    }
  }

  @override
  void dispose() {
    _remarkController.dispose();
    _decisionMakerController.dispose();
    _meetingLinkController.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0s (Not Connected)';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _scheduledDateTime ?? now,
      firstDate: now.subtract(const Duration(hours: 1)),
      lastDate: now.add(const Duration(days: 365)),
      helpText: _disposition == 'Demo Scheduled'
          ? 'SELECT DEMO DATE'
          : _disposition == 'Demo Done'
              ? 'SELECT POST-DEMO CALLBACK DATE'
              : _disposition == 'Future Requirement'
                  ? 'SELECT EXPECTED DATE'
                  : 'SELECT CALLBACK DATE',
    );

    if (pickedDate == null || !mounted) return;

    final initialTime = _scheduledDateTime != null
        ? TimeOfDay.fromDateTime(_scheduledDateTime!)
        : TimeOfDay.now();

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: _disposition == 'Demo Scheduled'
          ? 'SELECT DEMO TIME'
          : _disposition == 'Future Requirement'
              ? 'SELECT EXPECTED TIME'
              : 'SELECT CALLBACK TIME',
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child!,
        );
      },
    );

    if (pickedTime == null || !mounted) return;

    setState(() {
      _scheduledDateTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  String _formatDateTime(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year;
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$day-$month-$year  $hour:$minute $ampm';
  }

  Future<void> _handleSave() async {
    final remark = _remarkController.text.trim();
    if (remark.isEmpty) {
      setState(() => _errorMessage = 'Please enter discussion notes or a remark before saving.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    String finalDisposition = _disposition;
    if (_disposition == 'Already Using') {
      finalDisposition = _serviceOwner == 'other'
          ? 'Already Purchased or Using Other Company Service'
          : 'Already Using Our Service';
    }

    final callbackDatetimeIso = (_disposition == 'Callback' || _disposition == 'Future Requirement' || _disposition == 'Demo Done' || (_isScheduledCustomer && _disposition == 'RNR')) && _scheduledDateTime != null
        ? _scheduledDateTime!.toUtc().toIso8601String()
        : null;

    final demoDatetimeIso = _disposition == 'Demo Scheduled' && _scheduledDateTime != null
        ? _scheduledDateTime!.toUtc().toIso8601String()
        : null;

    final decisionMakerName = _disposition == 'Demo Scheduled' && _decisionMakerController.text.trim().isNotEmpty
        ? _decisionMakerController.text.trim()
        : null;

    final meetingLink = _disposition == 'Demo Scheduled' && _meetingLinkController.text.trim().isNotEmpty
        ? _meetingLinkController.text.trim()
        : null;

    final api = ApiService();
    // 1. Dispose in CRM — this updates lead status, tasks, pipeline, and records the call log as apk_manual
    final success = await api.disposeLead(
      leadId: widget.lead.id,
      disposition: finalDisposition,
      durationSeconds: widget.call.durationSeconds,
      remark: remark,
      callbackDatetime: callbackDatetimeIso,
      demoDatetime: demoDatetimeIso,
      decisionMakerName: decisionMakerName,
      meetingLink: meetingLink,
      callTimestamp: widget.call.callTimestamp,
      callLogId: widget.call.id,
      logSource: widget.isInbound
          ? (widget.call.durationSeconds == 0 ? 'inbound_missed' : 'inbound_sim')
          : 'apk_manual',
      isInterested: _isInterested || _disposition == 'Interested',
    );

    if (!mounted) return;
    if (success) {
      await StorageService().finalizeLocalCallRecord(
        callId: widget.call.id,
        phoneNumber: widget.call.phoneNumber,
        disposition: finalDisposition,
        durationSeconds: widget.call.durationSeconds,
        remark: remark,
        isInterested: _isInterested || _disposition == 'Interested',
      );
      _didSave = true;
      TelephonyService().clearCaches();
      TelephonyService().notifyCallCompleted();
      AgendaReminderService().refreshNow();
      widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } else {
      setState(() {
        _isSaving = false;
        _errorMessage = api.lastError ?? 'Failed to save disposition. Please check your network connection.';
      });
    }
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

    final isMissedInbound = widget.isInbound && widget.call.durationSeconds == 0;

    return PopScope(
      canPop: widget.isInbound && widget.call.durationSeconds == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          if (!_didSave) {
            widget.onDismissed?.call();
          }
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Call disposition is required. Please select an option and click Save to finish.'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
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
        child: SingleChildScrollView(
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
              const SizedBox(height: 12),
              if (widget.isInbound || widget.isAutoDetectedOutbound) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (isMissedInbound ? const Color(0xFFD97706) : const Color(0xFF0284C7)).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: (isMissedInbound ? const Color(0xFFD97706) : const Color(0xFF0284C7)).withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isMissedInbound ? Icons.phone_missed : Icons.call_received,
                            size: 12,
                            color: isMissedInbound ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.isAutoDetectedOutbound
                                ? 'PHONE DIALER CALL LOG${widget.queueLabel != null ? ' • ${widget.queueLabel}' : ''}'
                                : isMissedInbound
                                    ? 'MISSED INBOUND CALL${widget.queueLabel != null ? ' • ${widget.queueLabel}' : ''}'
                                    : 'INBOUND CUSTOMER CALL${widget.queueLabel != null ? ' • ${widget.queueLabel}' : ''}',
                            style: TextStyle(
                              color: isMissedInbound ? const Color(0xFFF59E0B) : const Color(0xFF38BDF8),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        if (!_didSave) {
                          widget.onDismissed?.call();
                        }
                        Navigator.of(context).pop();
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(40, 24),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isInbound ? (isMissedInbound ? 'Missed Inbound Call' : 'Inbound Call Connected') : 'Call Completed',
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.isInbound
                              ? '${widget.lead.displayName} (Customer Called Back)'
                              : widget.lead.displayName,
                          style: TextStyle(color: subColor, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
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
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isScheduledCustomer && !_showAllDispositions
                        ? (_isScheduledDemo ? 'Update Demo Outcome *' : 'Update Callback Outcome *')
                        : 'Select Call Outcome / Disposition *',
                    style: TextStyle(color: subColor, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  if (_isScheduledCustomer)
                    GestureDetector(
                      onTap: () => setState(() => _showAllDispositions = !_showAllDispositions),
                      child: Text(
                        _showAllDispositions ? 'Outcome Options' : 'All Dispositions',
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Scheduled Customer Update Outcome Options (matches Agenda Update Outcome)
              if (_isScheduledCustomer && !_showAllDispositions)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    {
                      'value': _isScheduledDemo ? 'Demo Done' : 'Connected',
                      'label': _isScheduledDemo ? 'Demo Completed ✅' : 'Callback Completed ✅',
                      'color': const Color(0xFF059669),
                      'border': const Color(0xFF10B981),
                    },
                    {
                      'value': 'RNR',
                      'label': 'Not Picking / RNR 📵',
                      'color': const Color(0xFFD97706),
                      'border': const Color(0xFFF59E0B),
                    },
                    {
                      'value': _isScheduledDemo ? 'Demo Scheduled' : 'Callback',
                      'label': _isScheduledDemo ? 'Reschedule Demo 📅' : 'Reschedule Callback 📅',
                      'color': _isScheduledDemo ? const Color(0xFF9333EA) : const Color(0xFF2563EB),
                      'border': _isScheduledDemo ? const Color(0xFFA855F7) : const Color(0xFF3B82F6),
                    },
                    {
                      'value': 'Not Interested',
                      'label': 'Not Interested ❌',
                      'color': const Color(0xFFE11D48),
                      'border': const Color(0xFFF43F5E),
                    },
                  ].map((opt) {
                    final val = opt['value'] as String;
                    final isSelected = _disposition == val;
                    final selColor = opt['color'] as Color;
                    final bdrColor = opt['border'] as Color;
                    return ChoiceChip(
                      label: Text(opt['label'] as String),
                      selected: isSelected,
                      selectedColor: selColor,
                      backgroundColor: chipBg,
                      labelStyle: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : isDark
                                ? const Color(0xFFE2E8F0)
                                : const Color(0xFF334155),
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isSelected
                              ? bdrColor
                              : isDark
                                  ? const Color(0xFF334155).withValues(alpha: 0.7)
                                  : const Color(0xFFCBD5E1),
                        ),
                      ),
                      onSelected: (_) => setState(() {
                        _isInterested = false;
                        _disposition = val;
                      }),
                    );
                  }).toList(),
                )
              else
                // Standard Disposition Chips
                Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _dispositions.map((d) {
                  final isSelected = d == 'Interested'
                      ? (_isInterested || _disposition == 'Interested')
                      : (_disposition == d);
                  String labelText = d == 'Interested' ? '🔥 Interested' : d;
                  if (d == 'Already Using' && isSelected) {
                    labelText = _serviceOwner == 'other'
                        ? 'Already Using (Other)'
                        : 'Already Using (Our)';
                  }
                  final chipSelectedColor = (d == 'Interested')
                      ? const Color(0xFFEA580C)
                      : (d == 'Already Using' && _serviceOwner == 'other')
                      ? const Color(0xFFEA580C)
                      : (d == 'Demo Scheduled')
                          ? const Color(0xFF9333EA)
                          : (d == 'Callback')
                              ? const Color(0xFF2563EB)
                              : (d == 'Future Requirement')
                                  ? const Color(0xFF0284C7)
                                  : const Color(0xFF059669);
                  final chipBorderColor = (d == 'Interested')
                      ? const Color(0xFFF97316)
                      : (d == 'Already Using' && _serviceOwner == 'other')
                      ? const Color(0xFFF97316)
                      : (d == 'Demo Scheduled')
                          ? const Color(0xFFA855F7)
                          : (d == 'Callback')
                              ? const Color(0xFF3B82F6)
                              : (d == 'Future Requirement')
                                  ? const Color(0xFF38BDF8)
                                  : const Color(0xFF10B981);

                  return ChoiceChip(
                    label: Text(labelText),
                    selected: isSelected,
                    selectedColor: chipSelectedColor,
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
                            ? chipBorderColor
                            : isDark
                                ? const Color(0xFF334155).withValues(alpha: 0.6)
                                : const Color(0xFFCBD5E1),
                      ),
                    ),
                    onSelected: (_) => setState(() {
                      const incompatibleWithInterested = {'RNR', 'Not Interested', 'Invalid'};
                      if (d == 'Interested') {
                        if (_isInterested || _disposition == 'Interested') {
                          _isInterested = false;
                          if (_disposition == 'Interested') _disposition = 'Connected';
                        } else {
                          _isInterested = true;
                          if (incompatibleWithInterested.contains(_disposition) ||
                              (_disposition == 'Already Using' && _serviceOwner == 'our') ||
                              _disposition == 'Connected') {
                            _disposition = 'Interested';
                          }
                        }
                      } else if (incompatibleWithInterested.contains(d)) {
                        _isInterested = false;
                        _disposition = d;
                      } else {
                        if (_isInterested) {
                          if (_disposition == d) {
                            _disposition = 'Interested';
                          } else {
                            _disposition = d;
                            if (d == 'Already Using' && _serviceOwner == 'our') {
                              _serviceOwner = 'other';
                            }
                          }
                        } else {
                          _disposition = d;
                        }
                      }
                    }),
                  );
                }).toList(),
              ),

              // Sub-options: Callback / Future Requirement / Demo Done / Scheduled RNR Date & Time (matches Web CRM UI)
              if (_disposition == 'Callback' || _disposition == 'Future Requirement' || _disposition == 'Demo Done' || (_isScheduledCustomer && _disposition == 'RNR')) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.5),
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.access_time_rounded, size: 16, color: Color(0xFF2563EB)),
                              const SizedBox(width: 6),
                              Text(
                                _disposition == 'Future Requirement'
                                    ? 'Expected Requirement Date'
                                    : _disposition == 'Demo Done'
                                        ? 'Post-Demo Follow-Up Date'
                                        : _disposition == 'RNR'
                                            ? 'Retry Callback Date & Time'
                                            : 'Callback Date & Time',
                                style: const TextStyle(
                                  color: Color(0xFF1D4ED8),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            _disposition == 'Future Requirement'
                                ? '(Optional expected date)'
                                : _disposition == 'Demo Done'
                                    ? '(Optional closing callback)'
                                    : '(Optional if client hasn\'t confirmed)',
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _pickDateTime,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: inputBorder),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_month_outlined, size: 18, color: Color(0xFF2563EB)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _scheduledDateTime != null
                                      ? _formatDateTime(_scheduledDateTime!)
                                      : 'dd-mm-yyyy --:--',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: _scheduledDateTime != null ? titleColor : subColor,
                                    fontWeight: _scheduledDateTime != null ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (_scheduledDateTime != null)
                                GestureDetector(
                                  onTap: () => setState(() => _scheduledDateTime = null),
                                  child: const Icon(Icons.cancel, size: 16, color: Color(0xFF94A3B8)),
                                )
                              else
                                const Icon(Icons.edit_calendar, size: 16, color: Color(0xFF2563EB)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '💡 If left blank, this callback will still appear in your Follow-Up agenda and reminders so you won\'t miss it.',
                        style: TextStyle(fontSize: 10, color: subColor),
                      ),
                    ],
                  ),
                ),
              ],

              // Sub-options: Demo Scheduled Date, Time, Decision Maker, Meeting Link (matches Web CRM UI)
              if (_disposition == 'Demo Scheduled') ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFAF5FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFA855F7).withValues(alpha: 0.5),
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.access_time_rounded, size: 16, color: Color(0xFF9333EA)),
                              SizedBox(width: 6),
                              Text(
                                'Demo Date & Time',
                                style: TextStyle(
                                  color: Color(0xFF7E22CE),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '(Optional if client hasn\'t confirmed)',
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _pickDateTime,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF0F172A) : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: inputBorder),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_month_outlined, size: 18, color: Color(0xFF9333EA)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _scheduledDateTime != null
                                      ? _formatDateTime(_scheduledDateTime!)
                                      : 'dd-mm-yyyy --:--',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: _scheduledDateTime != null ? titleColor : subColor,
                                    fontWeight: _scheduledDateTime != null ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (_scheduledDateTime != null)
                                GestureDetector(
                                  onTap: () => setState(() => _scheduledDateTime = null),
                                  child: const Icon(Icons.cancel, size: 16, color: Color(0xFF94A3B8)),
                                )
                              else
                                const Icon(Icons.edit_calendar, size: 16, color: Color(0xFF9333EA)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '💡 If left blank, this demo reminder will still appear in your Follow-Up agenda so you won\'t miss it.',
                        style: TextStyle(fontSize: 10, color: subColor),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Decision Maker Name (Optional)',
                                  style: TextStyle(fontSize: 11, color: subColor, fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 4),
                                TextField(
                                  controller: _decisionMakerController,
                                  style: TextStyle(color: titleColor, fontSize: 12),
                                  decoration: InputDecoration(
                                    hintText: 'e.g. Rajesh Kumar',
                                    hintStyle: TextStyle(
                                      color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                      fontSize: 11,
                                    ),
                                    filled: true,
                                    fillColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(color: inputBorder),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(color: inputBorder),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Meeting Link (Optional)',
                                  style: TextStyle(fontSize: 11, color: subColor, fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 4),
                                TextField(
                                  controller: _meetingLinkController,
                                  style: TextStyle(color: titleColor, fontSize: 12),
                                  keyboardType: TextInputType.url,
                                  decoration: InputDecoration(
                                    hintText: 'https://meet.google.com/...',
                                    hintStyle: TextStyle(
                                      color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                      fontSize: 11,
                                    ),
                                    filled: true,
                                    fillColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(color: inputBorder),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(color: inputBorder),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              // Sub-options: Using Whose Service? (Our Service vs Other Company)
              if (_disposition == 'Already Using') ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _serviceOwner == 'our'
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF97316),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.business,
                            size: 15,
                            color: _serviceOwner == 'our'
                                ? const Color(0xFF10B981)
                                : const Color(0xFFF97316),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Using Whose Service?',
                            style: TextStyle(
                              color: titleColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => setState(() => _serviceOwner = 'our'),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: _serviceOwner == 'our'
                                      ? const Color(0xFF059669)
                                      : (isDark ? const Color(0xFF0F172A) : Colors.white),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: _serviceOwner == 'our'
                                        ? const Color(0xFF059669)
                                        : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      size: 14,
                                      color: _serviceOwner == 'our' ? Colors.white : Colors.grey,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Our Service',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: _serviceOwner == 'our'
                                            ? Colors.white
                                            : titleColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: InkWell(
                              onTap: () => setState(() => _serviceOwner = 'other'),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: _serviceOwner == 'other'
                                      ? const Color(0xFFEA580C)
                                      : (isDark ? const Color(0xFF0F172A) : Colors.white),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: _serviceOwner == 'other'
                                        ? const Color(0xFFEA580C)
                                        : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.store,
                                      size: 14,
                                      color: _serviceOwner == 'other' ? Colors.white : Colors.grey,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Other Company',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: _serviceOwner == 'other'
                                            ? Colors.white
                                            : titleColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // Discussion Notes / Remark input with required indicator
              Row(
                children: [
                  Text(
                    'Discussion Notes / Remark',
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '*',
                    style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _remarkController,
                style: TextStyle(color: titleColor, fontSize: 13),
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Enter discussion notes, price discussed, next action...',
                  hintStyle: TextStyle(
                    color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                    fontSize: 12,
                  ),
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
              const SizedBox(height: 12),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

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
        ),
      ),
    );
  }
}
