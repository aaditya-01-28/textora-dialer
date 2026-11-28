import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_service.dart';

/// Agenda & Scheduled Tasks Real-Time Reminder Service
/// Polls agenda tasks and dispatches:
/// 1. Overdue / missed follow-up alert on startup or when tasks become overdue.
/// 2. 5-minute pre-reminder notification with "Call" / "Join Meeting" actions.
/// 3. Exact scheduled time high-priority alert with sound & vibration.
/// 4. Live pending count badge via [pendingCountNotifier] and tap-to-open Agenda routing.
class AgendaReminderService {
  static final AgendaReminderService _instance = AgendaReminderService._internal();
  factory AgendaReminderService() => _instance;
  AgendaReminderService._internal();

  static const MethodChannel _platformChannel =
      MethodChannel('com.textoratech.textora_dialer/telephony');

  final ApiService _api = ApiService();

  Timer? _timer;
  bool _isRunning = false;
  bool _permissionChecked = false;

  final Set<String> _notified5MinIds = {};
  final Set<String> _notifiedNowIds = {};
  final Set<String> _notifiedOverdueIds = {};

  /// Live count of Overdue + Today pending tasks for navigation badges
  final ValueNotifier<int> pendingCountNotifier = ValueNotifier<int>(0);

  Function(Map<String, dynamic> task, String reminderType)? onForegroundReminder;
  VoidCallback? onDismissForegroundReminder;
  VoidCallback? onOpenAgendaRequested;
  String? _activeForegroundTaskId;

  /// Dismisses active in-app and system notifications for a completed/rescheduled task.
  Future<void> markTaskResolved(String taskId) async {
    _notified5MinIds.add(taskId);
    _notifiedNowIds.add(taskId);
    _notifiedOverdueIds.add(taskId);
    if (_activeForegroundTaskId == taskId) {
      _activeForegroundTaskId = null;
      onDismissForegroundReminder?.call();
    }
    try {
      await _platformChannel.invokeMethod('cancelAgendaNotification', {
        'notificationId': (taskId.hashCode.abs() % 40000) + 10000,
      });
      await _platformChannel.invokeMethod('cancelAgendaNotification', {
        'notificationId': (taskId.hashCode.abs() % 40000) + 50000,
      });
    } catch (_) {}
  }

  Future<void> _ensureNotificationPermission() async {
    if (_permissionChecked) return;
    _permissionChecked = true;
    try {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    } catch (_) {}
  }

  void startListening({
    Function(Map<String, dynamic> task, String reminderType)? onReminder,
    VoidCallback? onOpenAgenda,
  }) {
    if (onReminder != null) {
      onForegroundReminder = onReminder;
    }
    if (onOpenAgenda != null) {
      onOpenAgendaRequested = onOpenAgenda;
    }

    _platformChannel.setMethodCallHandler((call) async {
      if (call.method == 'openAgenda') {
        onOpenAgendaRequested?.call();
      }
    });

    if (_isRunning) return;
    _isRunning = true;

    _ensureNotificationPermission();
    _checkPendingOpenAgendaIntent();

    // Run first check immediately, then poll every 20 seconds
    _checkReminders();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      _checkReminders();
    });
  }

  Future<void> _checkPendingOpenAgendaIntent() async {
    try {
      final shouldOpen = await _platformChannel.invokeMethod<bool>('consumeOpenAgendaIntent');
      if (shouldOpen == true) {
        onOpenAgendaRequested?.call();
      }
    } catch (_) {}
  }

  Future<void> refreshNow() async {
    await _checkReminders();
  }

  void stopListening() {
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
    _notified5MinIds.clear();
    _notifiedNowIds.clear();
    _notifiedOverdueIds.clear();
    pendingCountNotifier.value = 0;
  }

  Future<void> _checkReminders() async {
    try {
      final data = await _api.getAgendaTasks();
      final overdueTasks = (data['overdue'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      final todayTasks = (data['today'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      final upcomingTasks = (data['upcoming'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

      pendingCountNotifier.value = overdueTasks.length + todayTasks.length;

      final tasks = [...overdueTasks, ...todayTasks, ...upcomingTasks];
      final now = DateTime.now();

      // Track newly overdue tasks to fire a single summary notification if multiple
      final newlyOverdue = <Map<String, dynamic>>[];

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
        final formattedTime = DateFormat('dd MMM, hh:mm a').format(scheduledTime);
        final shortTime = DateFormat('hh:mm a').format(scheduledTime);

        // 1. 5-Minute Warning: diffMs > 0 && diffMs <= 5 min (300,000 ms)
        if (diffMs > 0 && diffMs <= 5 * 60 * 1000) {
          if (!_notified5MinIds.contains(id)) {
            _notified5MinIds.add(id);

            final notificationId = (id.hashCode.abs() % 40000) + 10000;
            final title = '⏰ 5-Min Reminder: $taskLabel';
            final body = '$targetName is scheduled at $shortTime';

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

            _activeForegroundTaskId = id;
            onForegroundReminder?.call(task, '5min');
          }
        }

        // 2. Exact Scheduled Time Alert: -3 min <= diffMs <= 0 ms
        if (diffMs <= 0 && diffMs >= -3 * 60 * 1000) {
          if (!_notifiedNowIds.contains(id)) {
            _notifiedNowIds.add(id);
            _notifiedOverdueIds.add(id); // Already alerted for this time

            final notificationId = (id.hashCode.abs() % 40000) + 50000;
            final title = '🔔 Time Now: $taskLabel!';
            final body = 'Scheduled right now with $targetName ($shortTime)';

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

            _activeForegroundTaskId = id;
            onForegroundReminder?.call(task, 'now');
          }
        }

        // 3. Missed / Overdue Alert (diffMs < -3 min)
        if (diffMs < -3 * 60 * 1000) {
          if (!_notifiedOverdueIds.contains(id)) {
            _notifiedOverdueIds.add(id);
            newlyOverdue.add({
              ...task,
              '_targetName': targetName,
              '_taskLabel': taskLabel,
              '_formattedTime': formattedTime,
            });
          }
        }
      }

      if (newlyOverdue.isNotEmpty) {
        if (newlyOverdue.length == 1) {
          final t = newlyOverdue.first;
          final lead = t['lead'] as Map<String, dynamic>? ?? {};
          try {
            await _platformChannel.invokeMethod('showAgendaNotification', {
              'notificationId': 90001,
              'title': '⚠️ Pending Agenda: ${t['_taskLabel']}',
              'body': '${t['_targetName']} was scheduled for ${t['_formattedTime']}. Tap to view Agenda.',
              'phone': lead['phoneNumber']?.toString(),
              'meetingLink': t['meetingLink']?.toString(),
              'leadId': t['leadId']?.toString(),
            });
          } catch (_) {}
        } else {
          final firstTarget = newlyOverdue.first['_targetName'];
          try {
            await _platformChannel.invokeMethod('showAgendaNotification', {
              'notificationId': 90001,
              'title': '⚠️ ${newlyOverdue.length} Pending Agenda Follow-Ups',
              'body': '$firstTarget & ${newlyOverdue.length - 1} more callbacks/demos are due. Tap to check Agenda.',
            });
          } catch (_) {}
        }
      }
    } catch (_) {
      // Silently catch network or parsing hiccups during background polling
    }
  }
}
