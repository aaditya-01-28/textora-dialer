import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/user_profile.dart';
import '../models/lead_item.dart';
import '../models/call_sync_item.dart';
import '../services/agenda_reminder_service.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/telephony_service.dart';
import '../services/update_service.dart';
import 'dashboard_screen.dart';
import 'leads_screen.dart';
import 'agenda_screen.dart';
import 'call_history_screen.dart';
import 'profile_screen.dart';
import 'post_call_dialog.dart';

class HomeShell extends StatefulWidget {
  final UserProfile user;

  const HomeShell({super.key, required this.user});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  late UserProfile _currentUser;
  Timer? _profileSyncTimer;
  Timer? _inboundPollTimer;
  bool _isInboundDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    WidgetsBinding.instance.addObserver(this);
    _startAgendaReminders();
    _startProfileSync();
    _startInboundPolling();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
      _checkInboundCalls();
    });
  }

  bool _isCheckingInbound = false;

  void _startInboundPolling() {
    _inboundPollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && !_isInboundDialogOpen) {
        _checkInboundCalls(delayMs: 0);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshProfile();
      _checkForUpdates();
      _handleResumeCallChecks();
    }
  }

  Future<void> _handleResumeCallChecks() async {
    // 1. Handle active in-app dialed call first (from Leads, Agenda, Calls, Dashboard, or Push-to-Dial)
    await _checkActiveOutboundCall();
    // 2. Then scan carrier call log for any inbound, missed, or unlogged native-dialed calls
    await _checkInboundCalls(delayMs: 400);
  }

  Future<void> _checkActiveOutboundCall() async {
    final tel = TelephonyService();
    if (!tel.hasFreshActiveCall || _isCheckingInbound || _isInboundDialogOpen) return;

    _isCheckingInbound = true;
    final targetPhone = tel.activeDialedNumber;
    final targetLeadId = tel.activeLeadId;
    await tel.clearCallState();

    try {
      await Future.delayed(const Duration(milliseconds: 1100));
      final callRecord = await tel.detectLastCallOutcome(specificPhone: targetPhone);
      if (!mounted || callRecord == null) return;

      int callEpoch = 0;
      try {
        callEpoch = DateTime.parse(callRecord.callTimestamp).toUtc().millisecondsSinceEpoch;
      } catch (_) {}
      final canonicalSig = TelephonyService.buildCallSignature(
        phoneNumber: callRecord.phoneNumber,
        timestampEpoch: callEpoch,
        durationSeconds: callRecord.durationSeconds,
        isInbound: false,
      );
      if (await StorageService().isCallSignatureProcessed(canonicalSig) || !mounted) return;

      final lead = await tel.findLeadForActiveCall(
        leadId: callRecord.leadId ?? targetLeadId,
        phone: targetPhone ?? callRecord.phoneNumber,
      );
      if (!mounted || lead == null) return;

      await StorageService().markCallSignatureProcessed(canonicalSig);
      if (!mounted) return;

      _isInboundDialogOpen = true;
      try {
        await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          isDismissible: false,
          enableDrag: false,
          backgroundColor: Colors.transparent,
          builder: (_) => PostCallDialog(
            lead: lead,
            call: callRecord,
            onSaved: () {
              _refreshProfile();
            },
          ),
        );
      } finally {
        _isInboundDialogOpen = false;
      }
    } catch (_) {
    } finally {
      _isCheckingInbound = false;
    }
  }

  Future<void> _checkInboundCalls({int delayMs = 1200}) async {
    if (_isCheckingInbound || _isInboundDialogOpen) return;
    _isCheckingInbound = true;

    try {
      if (delayMs > 0) {
        await Future.delayed(Duration(milliseconds: delayMs));
      }
      if (!mounted || _isInboundDialogOpen) return;

      final queue = await TelephonyService().detectPendingInboundCalls();
      if (queue.isNotEmpty && mounted) {
        await _showInboundQueue(queue, 0);
      }
    } catch (_) {
    } finally {
      _isCheckingInbound = false;
    }
  }

  Future<void> _showInboundQueue(List<Map<String, dynamic>> queue, int index) async {
    if (!mounted || index >= queue.length) return;
    final item = queue[index];
    final lead = item['lead'] as LeadItem;
    final call = item['call'] as CallSyncItem;
    final signature = item['signature'] as String;
    final isInboundCall = item['isInbound'] != false;
    final queueLabel = queue.length > 1 ? '${index + 1} of ${queue.length}' : null;

    _isInboundDialogOpen = true;
    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        isDismissible: call.durationSeconds == 0,
        enableDrag: call.durationSeconds == 0,
        backgroundColor: Colors.transparent,
        builder: (_) => PostCallDialog(
          lead: lead,
          call: call,
          isInbound: isInboundCall,
          isAutoDetectedOutbound: !isInboundCall,
          queueLabel: queueLabel,
          onDismissed: () async {
            await StorageService().markCallSignatureProcessed(signature);
            // Talk-time protection: if any connected call is skipped, still log its exact talk time
            if (call.durationSeconds > 0) {
              try {
                await ApiService().disposeLead(
                  leadId: lead.id,
                  disposition: 'Connected',
                  remark: isInboundCall
                      ? 'Inbound call auto-logged (${call.durationSeconds}s talk time)'
                      : 'Phone dialer call auto-logged (${call.durationSeconds}s talk time)',
                  durationSeconds: call.durationSeconds,
                  callTimestamp: call.callTimestamp,
                  logSource: isInboundCall ? 'inbound_sim' : 'apk_manual',
                );
                TelephonyService().clearCaches();
                TelephonyService().notifyCallCompleted();
              } catch (_) {}
            }
          },
          onSaved: () async {
            await StorageService().markCallSignatureProcessed(signature);
            _refreshProfile();
          },
        ),
      );
    } finally {
      _isInboundDialogOpen = false;
    }

    if (mounted && index + 1 < queue.length) {
      await _showInboundQueue(queue, index + 1);
    }
  }

  void _startProfileSync() {
    // Check for profile changes (phone, language, etc.) every 20 seconds
    _profileSyncTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _refreshProfile();
    });
  }

  Future<void> _refreshProfile() async {
    try {
      final updated = await ApiService().getDetailedProfile();
      if (mounted) {
        setState(() => _currentUser = updated);
      }
    } catch (_) {}
  }

  void _checkForUpdates() async {
    try {
      final info = await UpdateService().checkForUpdate();
      if (info != null && mounted) {
        UpdateService().showUpdateDialog(context, info);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _profileSyncTimer?.cancel();
    _inboundPollTimer?.cancel();
    AgendaReminderService().stopListening();
    super.dispose();
  }

  void _startAgendaReminders() {
    AgendaReminderService().startListening(
      onOpenAgenda: () {
        if (mounted) {
          setState(() => _currentIndex = 2);
        }
      },
      onReminder: (task, type) {
        if (!mounted) return;
        final lead = task['lead'] as Map<String, dynamic>? ?? {};
        final contactName = lead['contactName']?.toString();
        final companyName = lead['companyName']?.toString();
        final phone = lead['phoneNumber']?.toString();
        final meetingLink = task['meetingLink']?.toString();
        final leadId = task['leadId']?.toString();

        final target = (companyName != null && companyName.isNotEmpty)
            ? companyName
            : (contactName != null && contactName.isNotEmpty)
                ? contactName
                : (phone != null && phone.isNotEmpty)
                    ? phone
                    : 'Scheduled Task';

        final is5Min = type == '5min';
        final title = is5Min ? '⏰ In 5 Min' : '🔔 Time Now!';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: is5Min ? const Color(0xFFD97706) : const Color(0xFF059669),
            duration: const Duration(seconds: 12),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      is5Min ? Icons.access_time_filled : Icons.notifications_active,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$title: $target',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (task['notes'] != null && task['notes'].toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    task['notes'].toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ],
            ),
            action: phone != null && phone.isNotEmpty
                ? SnackBarAction(
                    label: 'CALL NOW',
                    textColor: Colors.white,
                    onPressed: () {
                      TelephonyService().makeCall(rawPhone: phone, leadId: leadId);
                    },
                  )
                : meetingLink != null && meetingLink.isNotEmpty
                    ? SnackBarAction(
                        label: 'JOIN',
                        textColor: Colors.white,
                        onPressed: () {
                          launchUrl(Uri.parse(meetingLink), mode: LaunchMode.externalApplication);
                        },
                      )
                    : null,
          ),
        );
      },
    );
  }

  void _onProfileUpdated(UserProfile updated) {
    setState(() => _currentUser = updated);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final navBorder = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final unselected = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    const selected = Color(0xFF10B981);

    final screens = [
      DashboardScreen(
        user: _currentUser,
        onNavigateToLeads: () => setState(() => _currentIndex = 1),
        onNavigateToAgenda: () => setState(() => _currentIndex = 2),
      ),
      LeadsScreen(user: _currentUser),
      AgendaScreen(user: _currentUser),
      CallHistoryScreen(user: _currentUser),
      ProfileScreen(
        user: _currentUser,
        onProfileUpdated: _onProfileUpdated,
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: navBg,
          border: Border(top: BorderSide(color: navBorder, width: 1)),
        ),
        child: ValueListenableBuilder<int>(
          valueListenable: AgendaReminderService().pendingCountNotifier,
          builder: (context, pendingCount, _) {
            return BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) {
                setState(() => _currentIndex = index);
                if (index == 2) {
                  AgendaReminderService().refreshNow();
                } else if (index == 4) {
                  _refreshProfile();
                }
              },
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedItemColor: selected,
              unselectedItemColor: unselected,
              selectedFontSize: 11.5,
              unselectedFontSize: 10.5,
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
              type: BottomNavigationBarType.fixed,
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard_outlined),
                  activeIcon: Icon(Icons.dashboard_rounded),
                  label: 'Dashboard',
                  tooltip: 'Sales Dashboard',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.contacts_outlined),
                  activeIcon: Icon(Icons.contacts_rounded),
                  label: 'Leads',
                  tooltip: 'Calling Leads Queue',
                ),
                BottomNavigationBarItem(
                  icon: _buildBadgeIcon(Icons.event_note_outlined, pendingCount),
                  activeIcon: _buildBadgeIcon(Icons.event_note_rounded, pendingCount),
                  label: 'Agenda',
                  tooltip: 'Follow-Up Agenda & Reminders',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.phone_callback_outlined),
                  activeIcon: Icon(Icons.phone_callback_rounded),
                  label: 'Calls',
                  tooltip: 'Carrier Call Records',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline_rounded),
                  activeIcon: Icon(Icons.person_rounded),
                  label: 'Profile',
                  tooltip: 'User Level & Accessibility',
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBadgeIcon(IconData icon, int count) {
    if (count <= 0) return Icon(icon);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        Positioned(
          right: -7,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(10),
            ),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 14),
            child: Text(
              count > 99 ? '99+' : '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}
