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

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    WidgetsBinding.instance.addObserver(this);
    _startAgendaReminders();
    _startProfileSync();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }

  bool _isCheckingInbound = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshProfile();
      _checkForUpdates();
      _checkInboundCalls();
    }
  }

  Future<void> _checkInboundCalls() async {
    if (_isCheckingInbound) return;
    _isCheckingInbound = true;

    try {
      // Delay slightly so Android telephony provider can finish writing the call entry
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;

      final result = await TelephonyService().detectLastInboundCall();
      if (result != null && mounted) {
        final lead = result['lead'] as LeadItem;
        final call = result['call'] as CallSyncItem;
        final signature = result['signature'] as String;

        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          isDismissible: true,
          enableDrag: true,
          backgroundColor: Colors.transparent,
          builder: (_) => PostCallDialog(
            lead: lead,
            call: call,
            isInbound: true,
            onDismissed: () {
              StorageService().markCallSignatureProcessed(signature);
            },
            onSaved: () {
              StorageService().markCallSignatureProcessed(signature);
              _refreshProfile();
            },
          ),
        );
      }
    } catch (_) {
    } finally {
      _isCheckingInbound = false;
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
    AgendaReminderService().stopListening();
    super.dispose();
  }

  void _startAgendaReminders() {
    AgendaReminderService().startListening(
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
      ),
      LeadsScreen(user: _currentUser),
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
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() => _currentIndex = index);
            if (index == 3) {
              _refreshProfile();
            }
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: selected,
          unselectedItemColor: unselected,
          selectedFontSize: 12,
          unselectedFontSize: 11,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard_rounded),
              label: 'Dashboard',
              tooltip: 'Sales Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.contacts_outlined),
              activeIcon: Icon(Icons.contacts_rounded),
              label: 'Leads',
              tooltip: 'Calling Leads Queue',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.phone_callback_outlined),
              activeIcon: Icon(Icons.phone_callback_rounded),
              label: 'Calls',
              tooltip: 'Carrier Call Records',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline_rounded),
              activeIcon: Icon(Icons.person_rounded),
              label: 'Profile',
              tooltip: 'User Level & Accessibility',
            ),
          ],
        ),
      ),
    );
  }
}
