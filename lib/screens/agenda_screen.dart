import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/lead_item.dart';
import '../models/user_profile.dart';
import '../services/agenda_reminder_service.dart';
import '../services/api_service.dart';
import '../services/telephony_service.dart';
import 'lead_profile_dialog.dart';

class AgendaScreen extends StatefulWidget {
  final UserProfile user;

  const AgendaScreen({super.key, required this.user});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  final _api = ApiService();
  final _telephony = TelephonyService();

  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _overdue = [];
  List<Map<String, dynamic>> _today = [];
  List<Map<String, dynamic>> _upcoming = [];
  List<Map<String, dynamic>> _unconfirmed = [];
  final Set<String> _busyTaskIds = {};
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadAgenda();
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) _loadAgenda(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAgenda({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final data = await _api.getAgendaTasks();
      if (!mounted) return;
      final overdue = (data['overdue'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      final today = (data['today'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      final upcoming = (data['upcoming'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      final unconfirmed = (data['unconfirmed'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

      setState(() {
        _overdue = overdue;
        _today = today;
        _upcoming = upcoming;
        _unconfirmed = unconfirmed;
        _isLoading = false;
      });

      AgendaReminderService().pendingCountNotifier.value = overdue.length + today.length;
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _error = e.toString().replaceAll('Exception:', '').trim();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _markTaskDone(String taskId) async {
    setState(() => _busyTaskIds.add(taskId));
    final ok = await _api.updateAgendaTask(taskId, {'status': 'completed'});
    if (!mounted) return;
    setState(() => _busyTaskIds.remove(taskId));

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agenda task marked as completed ✅'),
          backgroundColor: Color(0xFF059669),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      await _loadAgenda(silent: true);
      AgendaReminderService().refreshNow();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update task. Only the assigned rep can complete it.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openLeadProfile(Map<String, dynamic> task) {
    final leadMap = task['lead'] as Map<String, dynamic>? ?? {};
    final leadId = task['leadId']?.toString() ?? leadMap['id']?.toString();
    final phone = leadMap['phoneNumber']?.toString() ?? '';
    if (leadId == null || leadId.isEmpty) return;

    final lead = LeadItem(
      id: leadId,
      phoneNumber: phone,
      contactName: leadMap['contactName']?.toString(),
      companyName: leadMap['companyName']?.toString(),
      businessVertical: leadMap['businessVertical']?.toString(),
      source: 'crm',
      status: 'callback',
      rnrCount: 0,
      callLogsCount: 0,
    );

    showDialog(
      context: context,
      builder: (_) => LeadProfileDialog(
        lead: lead,
        user: widget.user,
        onLeadUpdated: (_) => _loadAgenda(silent: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC);
    final appBarBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final totalDue = _overdue.length + _today.length + _upcoming.length + _unconfirmed.length;

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        backgroundColor: appBarBg,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(11.0),
          child: Image.asset('assets/images/icon.png', fit: BoxFit.contain),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'FOLLOW-UP SCHEDULE',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFF10B981),
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
            Text(
              'Agenda & Reminders',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: titleColor,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                  )
                : Icon(Icons.refresh_rounded, color: subColor),
            tooltip: 'Refresh Agenda',
            onPressed: _isLoading ? null : () => _loadAgenda(silent: false),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFF10B981),
        onRefresh: () => _loadAgenda(silent: true),
        child: _isLoading && totalDue == 0
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
            : _error != null && totalDue == 0
                ? ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const SizedBox(height: 60),
                      Icon(Icons.error_outline_rounded, size: 44, color: Colors.redAccent.shade200),
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: titleColor, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: () => _loadAgenda(silent: false),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Retry'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  )
                : totalDue == 0
                    ? ListView(
                        padding: const EdgeInsets.all(32),
                        children: [
                          const SizedBox(height: 80),
                          Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.event_available_rounded,
                              size: 34,
                              color: Color(0xFF10B981),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'All Caught Up!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: titleColor,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'No pending callbacks or product demos scheduled right now.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: subColor),
                          ),
                        ],
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        children: [
                          if (_overdue.isNotEmpty) ...[
                            _buildSectionHeader(
                              'OVERDUE (${_overdue.length})',
                              Colors.redAccent,
                              Icons.warning_amber_rounded,
                            ),
                            const SizedBox(height: 8),
                            ..._overdue.map((t) => _buildTaskCard(
                                  t,
                                  accent: Colors.redAccent,
                                  isDark: isDark,
                                  cardBg: cardBg,
                                  cardBorder: cardBorder,
                                  titleColor: titleColor,
                                  subColor: subColor,
                                )),
                            const SizedBox(height: 16),
                          ],
                          if (_today.isNotEmpty) ...[
                            _buildSectionHeader(
                              "TODAY'S SCHEDULE (${_today.length})",
                              const Color(0xFF10B981),
                              Icons.today_rounded,
                            ),
                            const SizedBox(height: 8),
                            ..._today.map((t) => _buildTaskCard(
                                  t,
                                  accent: const Color(0xFF10B981),
                                  isDark: isDark,
                                  cardBg: cardBg,
                                  cardBorder: cardBorder,
                                  titleColor: titleColor,
                                  subColor: subColor,
                                )),
                            const SizedBox(height: 16),
                          ],
                          if (_upcoming.isNotEmpty) ...[
                            _buildSectionHeader(
                              'UPCOMING (${_upcoming.length})',
                              const Color(0xFF3B82F6),
                              Icons.calendar_month_rounded,
                            ),
                            const SizedBox(height: 8),
                            ..._upcoming.map((t) => _buildTaskCard(
                                  t,
                                  accent: const Color(0xFF3B82F6),
                                  isDark: isDark,
                                  cardBg: cardBg,
                                  cardBorder: cardBorder,
                                  titleColor: titleColor,
                                  subColor: subColor,
                                )),
                            const SizedBox(height: 16),
                          ],
                          if (_unconfirmed.isNotEmpty) ...[
                            _buildSectionHeader(
                              'UNCONFIRMED TIME (${_unconfirmed.length})',
                              const Color(0xFFF59E0B),
                              Icons.schedule_rounded,
                            ),
                            const SizedBox(height: 8),
                            ..._unconfirmed.map((t) => _buildTaskCard(
                                  t,
                                  accent: const Color(0xFFF59E0B),
                                  isDark: isDark,
                                  cardBg: cardBg,
                                  cardBorder: cardBorder,
                                  titleColor: titleColor,
                                  subColor: subColor,
                                )),
                          ],
                        ],
                      ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color color, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }

  Widget _buildTaskCard(
    Map<String, dynamic> task, {
    required Color accent,
    required bool isDark,
    required Color cardBg,
    required Color cardBorder,
    required Color titleColor,
    required Color subColor,
  }) {
    final id = task['id']?.toString() ?? '';
    final leadId = task['leadId']?.toString() ?? '';
    final taskType = task['taskType']?.toString() ?? 'callback';
    final isDemo = taskType == 'product_demo';
    final scheduledTimeStr = task['scheduledTime']?.toString();
    final meetingLink = task['meetingLink']?.toString();
    final notes = task['notes']?.toString();
    final lead = task['lead'] as Map<String, dynamic>? ?? {};
    final phone = lead['phoneNumber']?.toString() ?? '';
    final contactName = lead['contactName']?.toString();
    final companyName = lead['companyName']?.toString();
    final rep = task['rep'] as Map<String, dynamic>? ?? {};
    final repName = rep['fullName']?.toString();
    final isBusy = _busyTaskIds.contains(id);

    String formattedTime = 'Time not set';
    if (scheduledTimeStr != null && scheduledTimeStr.isNotEmpty) {
      try {
        final localDt = DateTime.parse(scheduledTimeStr).toLocal();
        formattedTime = DateFormat('dd MMM yyyy, hh:mm a').format(localDt);
      } catch (_) {}
    }

    final displayName = (companyName != null && companyName.isNotEmpty)
        ? companyName
        : (contactName != null && contactName.isNotEmpty)
            ? contactName
            : (phone.isNotEmpty ? phone : 'Prospect');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openLeadProfile(task),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (isDemo ? const Color(0xFF8B5CF6) : const Color(0xFF3B82F6))
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isDemo ? 'Product Demo' : 'Callback',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isDemo ? const Color(0xFFA78BFA) : const Color(0xFF60A5FA),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.access_time_rounded, size: 13, color: accent),
                  const SizedBox(width: 4),
                  Text(
                    formattedTime,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                displayName,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (phone.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  contactName != null && contactName.isNotEmpty && companyName != null && companyName.isNotEmpty
                      ? '$contactName • $phone'
                      : phone,
                  style: TextStyle(fontSize: 12.5, color: subColor),
                ),
              ],
              if (notes != null && notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    notes,
                    style: TextStyle(fontSize: 12, color: subColor),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              if (repName != null && repName.isNotEmpty && repName != widget.user.fullName) ...[
                const SizedBox(height: 6),
                Text(
                  'Assigned: $repName',
                  style: TextStyle(fontSize: 11, color: subColor, fontWeight: FontWeight.w500),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  if (phone.isNotEmpty)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          _telephony.makeCall(rawPhone: phone, leadId: leadId);
                        },
                        icon: const Icon(Icons.call_rounded, size: 16),
                        label: const Text('Call Now', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                        ),
                      ),
                    ),
                  if (meetingLink != null && meetingLink.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        launchUrl(Uri.parse(meetingLink), mode: LaunchMode.externalApplication);
                      },
                      icon: const Icon(Icons.videocam_rounded, size: 16),
                      label: const Text('Join', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF8B5CF6),
                        side: const BorderSide(color: Color(0xFF8B5CF6)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: isBusy ? null : () => _markTaskDone(id),
                    icon: isBusy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline_rounded, size: 16),
                    label: const Text('Done', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: titleColor,
                      side: BorderSide(color: cardBorder),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
