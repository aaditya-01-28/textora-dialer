import 'dart:async';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'api_service.dart';

/// Agenda & Scheduled Tasks Real-Time Reminder Service
/// Polls agenda tasks and dispatches:
/// 1. 5-minute pre-reminder notification with "Call Now" / "Join" actions.
/// 2. Exact scheduled time high-priority alert with sound & vibration.
class AgendaReminderService {
  static final AgendaReminderService _instance = AgendaReminderService._internal();
  factory AgendaReminderService() => _instance;
  AgendaReminderService._internal();

  static const MethodChannel _platformChannel =
      MethodChannel('com.textoratech.textora_dialer/telephony');

  final ApiService _api = ApiService();

  Timer? _timer;
  bool _isRunning = false;

  final Set<String> _notified5MinIds = {};
  final Set<String> _notifiedNowIds = {};

  Function(Map<String, dynamic> task, String reminderType)? onForegroundReminder;

  void startListening({Function(Map<String, dynamic> task, String reminderType)? onReminder}) {
    if (onReminder != null) {
      onForegroundReminder = onReminder;
    }
    if (_isRunning) return;
    _isRunning = true;

    // Run first check immediately, then poll every 20 seconds
    _checkReminders();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      _checkReminders();
    });
  }

  void stopListening() {
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _checkReminders() async {
    try {
      final data = await _api.getAgendaTasks();
      final todayTasks = (data['today'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      final upcomingTasks = (data['upcoming'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      final tasks = [...todayTasks, ...upcomingTasks];

      final now = DateTime.now();

      for (final task in tasks) {
        final id = task['id']?.toString();
        final scheduledTimeStr = task['scheduledTime']?.toString();
        final status = task['status']?.toString();

        if (id == null || scheduledTimeStr == null || status != 'pending') continue;

        DateTime? scheduledTime;
        try {
          scheduledTime = DateTime.parse(scheduledTimeStr).toLocal();
        } catch (_) {
          continue;
        }

        final diffMs = scheduledTime.difference(now).inMilliseconds;

        final lead = task['lead'] as Map<String, dynamic>? ?? {};
        final contactName = lead['contactName']?.toString();
        final companyName = lead['companyName']?.toString();
        final phone = lead['phoneNumber']?.toString();
        final meetingLink = task['meetingLink']?.toString();
        final leadId = task['leadId']?.toString();

        final targetName = (companyName != null && companyName.isNotEmpty)
            ? companyName
            : (contactName != null && contactName.isNotEmpty)
                ? contactName
                : (phone != null && phone.isNotEmpty)
                    ? phone
                    : 'Scheduled Client';

        final taskType = task['taskType']?.toString();
        final taskLabel = taskType == 'product_demo' ? 'Product Demo' : 'Scheduled Callback';
        final formattedTime = DateFormat('hh:mm a').format(scheduledTime);

        // 1. 5-Minute Warning: diffMs > 0 && diffMs <= 5 min (300,000 ms)
        if (diffMs > 0 && diffMs <= 5 * 60 * 1000) {
          if (!_notified5MinIds.contains(id)) {
            _notified5MinIds.add(id);

            final notificationId = (id.hashCode.abs() % 40000) + 10000;
            final title = '⏰ 5-Min Reminder: $taskLabel';
            final body = '$targetName is scheduled at $formattedTime';

            try {
              await _platformChannel.invokeMethod('showAgendaNotification', {
                'notificationId': notificationId,
                'title': title,
                'body': body,
                'phone': phone,
                'meetingLink': meetingLink,
                'leadId': leadId,
              });
            } catch (_) {}

            onForegroundReminder?.call(task, '5min');
          }
        }

        // 2. Exact Scheduled Time Alert: -3 min <= diffMs <= 0 ms
        if (diffMs <= 0 && diffMs >= -3 * 60 * 1000) {
          if (!_notifiedNowIds.contains(id)) {
            _notifiedNowIds.add(id);

            final notificationId = (id.hashCode.abs() % 40000) + 50000;
            final title = '🔔 Time Now: $taskLabel!';
            final body = 'Scheduled right now with $targetName ($formattedTime)';

            try {
              await _platformChannel.invokeMethod('showAgendaNotification', {
                'notificationId': notificationId,
                'title': title,
                'body': body,
                'phone': phone,
                'meetingLink': meetingLink,
                'leadId': leadId,
              });
            } catch (_) {}

            onForegroundReminder?.call(task, 'now');
          }
        }
      }
    } catch (_) {
      // Silently catch network or parsing hiccups during background polling
    }
  }
}
