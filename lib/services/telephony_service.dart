import 'dart:async';
import 'dart:io';
import 'package:call_log/call_log.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/call_sync_item.dart';
import '../models/lead_item.dart';
import 'api_service.dart';
import 'storage_service.dart';

/// Telephony & Carrier Call Tracking Service
/// Strictly reads the carrier call log on the local device via Android APIs.
/// Zero third-party data tracking.
class TelephonyService {
  static final TelephonyService _instance = TelephonyService._internal();
  factory TelephonyService() => _instance;
  TelephonyService._internal();

  static const MethodChannel _platformChannel =
      MethodChannel('com.textoratech.textora_dialer/telephony');

  final StorageService _storage = StorageService();
  final ApiService _api = ApiService();

  // Broadcast notifier so Dashboard, Leads, Agenda & Calls refresh together after any call disposition
  final ValueNotifier<int> callCompletedNotifier = ValueNotifier<int>(0);

  void notifyCallCompleted() {
    callCompletedNotifier.value = callCompletedNotifier.value + 1;
  }

  // Active call session tracking
  String? activeDialedNumber;
  String? activeLeadId;
  DateTime? callInitiatedTime;

  static String last10Digits(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
  }

  static String buildCallSignature({
    required String phoneNumber,
    required int timestampEpoch,
    required int durationSeconds,
    required bool isInbound,
  }) {
    final suffix = last10Digits(phoneNumber);
    final prefix = isInbound ? 'inbound' : 'outbound';
    return '${prefix}_${suffix}_${timestampEpoch}_$durationSeconds';
  }

  bool get hasFreshActiveCall {
    if (activeDialedNumber == null || callInitiatedTime == null) return false;
    final age = DateTime.now().difference(callInitiatedTime!);
    if (age.inMinutes >= 20 || age.isNegative) {
      activeDialedNumber = null;
      activeLeadId = null;
      callInitiatedTime = null;
      return false;
    }
    return true;
  }

  // Push-to-dial listener state
  Timer? _pushToDialTimer;
  bool isPushToDialActive = false;
  bool _isPollingPush = false;

  /// Start background listener for Web CRM Push-to-Dial requests
  void startPushToDialListener({Function(Map<String, dynamic>)? onCallTriggered}) {
    if (isPushToDialActive) return;
    isPushToDialActive = true;

    _pushToDialTimer?.cancel();
    _pushToDialTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_isPollingPush || !isPushToDialActive) return;
      _isPollingPush = true;
      try {
        final job = await _api.checkPushToDialJob();
        if (job != null && job['id'] != null) {
          final jobId = job['id'].toString();
          final phone = job['phoneNumber']?.toString() ?? '';
          final leadId = job['leadId']?.toString();

          if (phone.isNotEmpty) {
            await _api.updatePushToDialStatus(jobId, 'ringing');
            final launched = await makeCall(rawPhone: phone, leadId: leadId);
            if (launched) {
              await _api.updatePushToDialStatus(jobId, 'in_call');
            } else {
              await _api.updatePushToDialStatus(jobId, 'failed');
            }
            onCallTriggered?.call(job);
          }
        }
      } catch (_) {
      } finally {
        _isPollingPush = false;
      }
    });
  }

  /// Stop listening for Web CRM Push-to-Dial requests
  void stopPushToDialListener() {
    isPushToDialActive = false;
    _isPollingPush = false;
    _pushToDialTimer?.cancel();
    _pushToDialTimer = null;
  }

  /// Request runtime permissions from Android
  Future<bool> checkAndRequestPermissions() async {
    final phoneStatus = await Permission.phone.status;
    if (!phoneStatus.isGranted) {
      final res = await Permission.phone.request();
      if (!res.isGranted) return false;
    }
    return true;
  }

  /// Trigger Native SIM Call
  Future<bool> makeCall({
    required String rawPhone,
    String? leadId,
  }) async {
    final cleanDigits = rawPhone.replaceAll(RegExp(r'\D'), '');
    final phone = cleanDigits.length > 10 ? cleanDigits.substring(cleanDigits.length - 10) : cleanDigits;

    activeDialedNumber = phone;
    activeLeadId = leadId;
    callInitiatedTime = DateTime.now();

    // Notify Android native layer that an authorized CRM call was initiated from Textora
    try {
      await _platformChannel.invokeMethod('setCallInitiated', {
        'phone': phone,
        'leadId': leadId ?? '',
      });
    } catch (_) {}

    final telUri = Uri.parse('tel:+91$phone');
    if (await canLaunchUrl(telUri)) {
      return await launchUrl(telUri);
    }
    return false;
  }

  /// Reset CRM Call State in Native Android layer
  Future<void> clearCallState() async {
    activeDialedNumber = null;
    activeLeadId = null;
    callInitiatedTime = null;
    try {
      await _platformChannel.invokeMethod('clearCallState');
    } catch (_) {}
  }

  /// Build Dynamic WhatsApp Pitch matching official company template
  static String buildWAPitch({
    String? repName,
    String? repEmail,
    String? repPhone,
    String? contactName,
  }) {
    final name = (repName != null && repName.trim().isNotEmpty) ? repName.trim() : 'Sales Team';
    final email = (repEmail != null && repEmail.trim().isNotEmpty) ? repEmail.trim() : '';
    var phone = (repPhone != null && repPhone.trim().isNotEmpty) ? repPhone.trim() : '';
    phone = phone.replaceAll(RegExp(r'\D'), '');
    if (phone.length > 10) phone = phone.substring(phone.length - 10);

    final greetingTarget = (contactName != null && contactName.trim().isNotEmpty)
        ? contactName.trim()
        : 'Sir';
    final emailLine = email.isNotEmpty ? '📧 $email\n' : '';
    final phoneLine = phone.isNotEmpty ? '📱 $phone\n\n' : '\n';

    return 'Hello $greetingTarget 👋\n'
        'This is $name from Textora Technologies Pvt Ltd.\n\n'
        'Looking to grow your business faster and reach more customers instantly? 🚀\n'
        'We offer smart messaging solutions to boost sales, engagement, and brand visibility 📈\n\n'
        '✨ Our Services:\n'
        '📲 Business WhatsApp API – Official & automated messaging\n'
        '💬 Virtual WhatsApp – Bulk & personalised campaigns\n'
        '📩 RCS Messaging – Rich, interactive messages\n'
        '🔐 Transactional SMS – OTPs, alerts & notifications\n'
        '📢 Promotional SMS – Offers, campaigns & branding\n'
        '📞 Voice SMS – Automated voice calls at scale\n'
        '🌐Website development: Build Premium Websites That Grow Your Business\n\n'
        '📢 Reach customers instantly | Improve response rate | Increase conversions\n\n'
        '📞 For details & free demo:\n'
        '$name\n'
        '$emailLine'
        'https://textorasms.com\n'
        '$phoneLine'
        'Reply YES to get started 👍';
  }

  /// Launch WhatsApp with Company Pitch
  Future<bool> openWhatsApp({
    required String rawPhone,
    required String message,
  }) async {
    final cleanDigits = rawPhone.replaceAll(RegExp(r'\D'), '');
    final phone = cleanDigits.length > 10 ? cleanDigits.substring(cleanDigits.length - 10) : cleanDigits;
    final encoded = Uri.encodeComponent(message);
    final waUri = Uri.parse('https://wa.me/91$phone?text=$encoded');

    if (await canLaunchUrl(waUri)) {
      return await launchUrl(waUri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  /// Inspect Native Android CallLog for the Call That Just Finished
  Future<CallSyncItem?> detectLastCallOutcome({String? specificPhone}) async {
    final targetPhone = specificPhone ?? activeDialedNumber;
    if (targetPhone == null) return null;

    final hasPerms = await checkAndRequestPermissions();
    if (!hasPerms) return null;

    try {
      // Lookback from when call was initiated (with 5 second buffer for OS clock drift),
      // or at most 5 minutes if initiated time was not set.
      final startTimeEpoch = (callInitiatedTime != null)
          ? callInitiatedTime!.subtract(const Duration(seconds: 5)).millisecondsSinceEpoch
          : DateTime.now().subtract(const Duration(minutes: 5)).millisecondsSinceEpoch;

      final Iterable<CallLogEntry> entries = await CallLog.query(
        dateFrom: startTimeEpoch,
      );

      CallLogEntry? matchedEntry;

      // Match by phone number suffix (last 10 digits)
      final cleanTarget = targetPhone.replaceAll(RegExp(r'\D'), '');
      final targetSuffix = cleanTarget.length >= 10 ? cleanTarget.substring(cleanTarget.length - 10) : cleanTarget;

      for (var entry in entries) {
        // Strict Check 1: Must be an outgoing call! (skip incoming, missed, blocked, rejected)
        if (entry.callType != null && entry.callType != CallType.outgoing) {
          continue;
        }

        // Strict Check 2: Must have taken place after the user tapped Call SIM in the app
        if (entry.timestamp != null && entry.timestamp! < startTimeEpoch) {
          continue;
        }

        // Strict Check 3: Number must match the dialed lead number
        final number = (entry.number ?? '').replaceAll(RegExp(r'\D'), '');
        if (number.isNotEmpty && (number.endsWith(targetSuffix) || targetSuffix.endsWith(number))) {
          matchedEntry = entry;
          break;
        }
      }

      // DO NOT fallback to entries.first!
      // If no outgoing call was placed to this target number, matchedEntry is null.
      // Returning null ensures no ghost call is recorded and no false disposition popup appears.
      if (matchedEntry == null) {
        return null;
      }

      final duration = (matchedEntry.duration != null && matchedEntry.duration! > 0)
          ? matchedEntry.duration!
          : 0;
      final timestampEpoch = matchedEntry.timestamp ?? DateTime.now().millisecondsSinceEpoch;
      // Use isUtc: true so ISO string ends with 'Z' and is parsed correctly without timezone distortion
      final timestampIso = DateTime.fromMillisecondsSinceEpoch(timestampEpoch, isUtc: true).toIso8601String();
      final disposition = duration > 0 ? 'Connected' : 'RNR';

        // Check for newly recorded audio file from native recorder
        String? recordingUrl;
        try {
          final recFile = await findLatestRecordingFile();
          if (recFile != null) {
            recordingUrl = await _api.uploadRecordingFile(
              recFile.path,
              leadId: activeLeadId,
            );
          }
        } catch (_) {}

        final item = CallSyncItem(
          id: '${DateTime.now().millisecondsSinceEpoch}',
          leadId: activeLeadId,
          phoneNumber: matchedEntry.number ?? targetPhone,
          durationSeconds: duration,
          disposition: disposition,
          callTimestamp: timestampIso,
          remark: 'Captured from SIM dialer',
          recordingUrl: recordingUrl,
          logSource: duration > 0 ? 'dialer_connected' : 'dialer_rnr',
          isSynced: false,
        );

        // Store locally
        await _storage.saveCallRecord(item);

        // If this call belongs to an active lead, PostCallDialog will handle disposition.
        // Only auto-sync here if there is no active lead dossier attached to avoid duplicate entries.
        if (activeLeadId == null) {
          _api.syncCallLog(item);
        }

        return item;
    } catch (e) {
      // Android permission or provider error
    }

    return null;
  }

  Map<String, LeadItem> _cachedLeadBySuffix = {};
  Map<String, LeadItem> _cachedLeadById = {};
  DateTime? _lastLeadCacheTime;
  List<CallSyncItem> _cachedServerCalls = [];
  DateTime? _lastServerCallsTime;

  void clearCaches() {
    _cachedLeadBySuffix = {};
    _cachedLeadById = {};
    _lastLeadCacheTime = null;
    _cachedServerCalls = [];
    _lastServerCallsTime = null;
    activeDialedNumber = null;
    activeLeadId = null;
    callInitiatedTime = null;
  }

  Future<void> _ensureLeadCache({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _cachedLeadBySuffix.isNotEmpty &&
        _lastLeadCacheTime != null &&
        now.difference(_lastLeadCacheTime!).inSeconds < 60) {
      return;
    }
    try {
      final leads = await _api.getLeads().timeout(const Duration(seconds: 15));
      final nextBySuffix = <String, LeadItem>{};
      final nextById = <String, LeadItem>{};
      for (final l in leads) {
        nextById[l.id] = l;
        final pSuffix = last10Digits(l.phoneNumber);
        if (pSuffix.isNotEmpty) {
          nextBySuffix[pSuffix] = l;
        }
        final sSuffix = last10Digits(l.secondaryPhone ?? '');
        if (sSuffix.isNotEmpty) {
          nextBySuffix[sSuffix] = l;
        }
      }
      if (nextBySuffix.isNotEmpty) {
        _cachedLeadBySuffix = nextBySuffix;
        _cachedLeadById = nextById;
        _lastLeadCacheTime = now;
      }
    } catch (_) {
      // Keep existing cache when offline / slow
    }
  }

  Future<void> _ensureServerCallCache({bool force = false, int limit = 150}) async {
    final now = DateTime.now();
    if (!force &&
        _cachedServerCalls.length >= (limit > 150 ? limit : 0) &&
        _lastServerCallsTime != null &&
        now.difference(_lastServerCallsTime!).inSeconds < 20) {
      return;
    }
    try {
      final calls = await _api.getCallLogs(limit: limit).timeout(const Duration(seconds: 12));
      _cachedServerCalls = calls;
      _lastServerCallsTime = now;
    } catch (_) {}
  }

  Future<bool> isCallAlreadyLoggedOnServer(
    LeadItem lead,
    CallSyncItem call, {
    bool isInbound = false,
    bool forceRefresh = true,
  }) async {
    await _ensureServerCallCache(force: forceRefresh);
    int callEpoch = 0;
    try {
      callEpoch = DateTime.parse(call.callTimestamp).toUtc().millisecondsSinceEpoch;
    } catch (_) {}
    if (callEpoch == 0) callEpoch = DateTime.now().toUtc().millisecondsSinceEpoch;
    return _isCallInServerList(
      _cachedServerCalls,
      lead,
      callEpoch,
      call.durationSeconds,
      isInbound: isInbound,
    );
  }

  bool _isCallInServerList(
    List<CallSyncItem> serverList,
    LeadItem lead,
    int timestampEpoch,
    int duration, {
    required bool isInbound,
  }) {
    final leadSuffix = last10Digits(lead.phoneNumber);
    final secSuffix = last10Digits(lead.secondaryPhone ?? '');
    for (final sc in serverList) {
      final scSuffix = last10Digits(sc.phoneNumber);
      final matchesLead = (sc.leadId != null && sc.leadId == lead.id) ||
          (leadSuffix.isNotEmpty && scSuffix == leadSuffix) ||
          (secSuffix.isNotEmpty && scSuffix == secSuffix);
      if (!matchesLead) continue;

      final scIsInbound =
          sc.logSource == 'inbound_sim' || sc.logSource == 'inbound_missed';
      // An outbound attempt (e.g. RNR at 11:44) must never suppress a later inbound callback (e.g. 11:46)
      if (scIsInbound != isInbound) continue;

      int scEpoch = 0;
      try {
        scEpoch = DateTime.parse(sc.callTimestamp).toUtc().millisecondsSinceEpoch;
      } catch (_) {}
      if (scEpoch == 0) continue;

      final diffMs = (scEpoch - timestampEpoch).abs();
      final sameConnectOutcome = (sc.durationSeconds > 0) == (duration > 0);
      // Match same interaction window (±5 minutes) only if connection outcome agrees
      if (sameConnectOutcome && diffMs <= 5 * 60 * 1000) return true;
      if (duration > 0 &&
          diffMs <= 20 * 60 * 1000 &&
          (sc.durationSeconds - duration).abs() <= 3) {
        return true;
      }
    }
    return false;
  }

  bool _isAlreadyLoggedOnServer(
    LeadItem lead,
    int timestampEpoch,
    int duration, {
    required bool isInbound,
  }) {
    return _isCallInServerList(
      _cachedServerCalls,
      lead,
      timestampEpoch,
      duration,
      isInbound: isInbound,
    );
  }

  /// Resolve a CRM LeadItem by ID or phone number for foreground active call handling
  Future<LeadItem?> findLeadForActiveCall({String? leadId, String? phone}) async {
    await _ensureLeadCache();
    if (leadId != null && leadId.isNotEmpty) {
      if (_cachedLeadById.containsKey(leadId)) {
        return _cachedLeadById[leadId];
      }
      try {
        final map = await _api.getLeadDetails(leadId).timeout(const Duration(seconds: 8));
        if (map.isNotEmpty) {
          final l = LeadItem.fromJson(map);
          _cachedLeadById[l.id] = l;
          return l;
        }
      } catch (_) {}
    }
    if (phone != null && phone.isNotEmpty) {
      final s = last10Digits(phone);
      if (s.isNotEmpty && _cachedLeadBySuffix.containsKey(s)) {
        return _cachedLeadBySuffix[s];
      }
      return await _api.findLeadByPhone(phone);
    }
    return null;
  }

  /// Inspect Android CallLog for ALL un-logged incoming, missed, and native-dialed outgoing CRM calls
  Future<List<Map<String, dynamic>>> detectPendingInboundCalls({
    bool forceServerRefresh = false,
  }) async {
    // Only pause background scan while an in-app call is actively in progress in background
    if (hasFreshActiveCall && WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return [];
    }

    final hasPerms = await checkAndRequestPermissions();
    if (!hasPerms) return [];

    final pendingQueue = <Map<String, dynamic>>[];

    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final lookbackEpoch = DateTime.now().subtract(const Duration(hours: 12)).millisecondsSinceEpoch;
      final outgoingRnrCutoffEpoch = DateTime.now().subtract(const Duration(minutes: 30)).millisecondsSinceEpoch;

      final entries = await CallLog.query(dateFrom: lookbackEpoch);
      final prevCacheEmpty = _cachedLeadBySuffix.isEmpty;
      await _ensureLeadCache();
      if (_cachedLeadBySuffix.isEmpty) return [];

      await _ensureServerCallCache(force: forceServerRefresh || prevCacheEmpty);

      final seenSignatures = <String>{};

      for (final entry in entries) {
        final callType = entry.callType;
        final isIncoming =
            callType == CallType.incoming ||
            callType == CallType.wifiIncoming ||
            callType == CallType.answeredExternally;
        final isMissed = callType == CallType.missed || callType == CallType.rejected;
        final isOutgoing = callType == CallType.outgoing || callType == CallType.wifiOutgoing;

        if (!isIncoming && !isMissed && !isOutgoing) continue;

        final timestampEpoch = entry.timestamp;
        if (timestampEpoch == null || timestampEpoch < lookbackEpoch || timestampEpoch > nowMs + 60000) {
          continue;
        }

        final duration = (!isMissed && entry.duration != null && entry.duration! > 0) ? entry.duration! : 0;

        // For outgoing calls dialed natively outside in-app tracker:
        // Always capture ALL connected calls (duration > 0) across 12h, and unanswered 0s RNRs from last 30 mins
        if (isOutgoing && duration == 0 && timestampEpoch < outgoingRnrCutoffEpoch) {
          continue;
        }

        final rawNumber = entry.number ?? '';
        final suffix = last10Digits(rawNumber);
        if (suffix.isEmpty) continue;

        final isInboundOrMissed = isIncoming || isMissed;
        final signature = buildCallSignature(
          phoneNumber: suffix,
          timestampEpoch: timestampEpoch,
          durationSeconds: duration,
          isInbound: isInboundOrMissed,
        );
        if (seenSignatures.contains(signature)) continue;
        seenSignatures.add(signature);

        if (await _storage.isCallSignatureProcessed(signature)) continue;

        final matchedLead = _cachedLeadBySuffix[suffix];
        if (matchedLead != null) {
          // Cross-check CRM server logs so already-disposed calls are never prompted twice
          if (_isAlreadyLoggedOnServer(
            matchedLead,
            timestampEpoch,
            duration,
            isInbound: isInboundOrMissed,
          )) {
            await _storage.markCallSignatureProcessed(signature);
            continue;
          }

          final timestampIso = DateTime.fromMillisecondsSinceEpoch(timestampEpoch, isUtc: true).toIso8601String();
          final isMissedCall = isInboundOrMissed && (isMissed || duration == 0);

          final callItem = CallSyncItem(
            id: '${isInboundOrMissed ? "inbound" : "outbound"}_${timestampEpoch}_$suffix',
            leadId: matchedLead.id,
            phoneNumber: rawNumber.isNotEmpty ? rawNumber : matchedLead.phoneNumber,
            durationSeconds: duration,
            disposition: isInboundOrMissed
                ? (isMissedCall ? 'RNR' : 'Connected')
                : (duration > 0 ? 'Connected' : 'RNR'),
            callTimestamp: timestampIso,
            remark: isInboundOrMissed
                ? (isMissedCall ? 'Missed inbound call from customer' : 'Inbound call from customer')
                : 'Synced from Phone Dialer',
            logSource: isInboundOrMissed
                ? (isMissedCall ? 'inbound_missed' : 'inbound_sim')
                : 'apk_manual',
            isSynced: false,
          );

          pendingQueue.add({
            'lead': matchedLead,
            'call': callItem,
            'signature': signature,
            'isMissed': isMissedCall,
            'isInbound': isInboundOrMissed,
          });
        }
        // NOTE: Do NOT mark non-CRM numbers as processed so when an existing customer
        // is later added to CRM, their earlier calls can still be discovered and logged.
      }
    } catch (_) {}

    // Process oldest-first so dispositions happen in chronological order
    return pendingQueue.reversed.toList();
  }

  /// Inspect Android CallLog specifically for a CRM lead (primary + alternate phone),
  /// cross-checked against all server call logs for that lead (regardless of age or global cache).
  Future<List<Map<String, dynamic>>> scanPhoneCallsForLead(
    LeadItem lead, {
    int lookbackDays = 7,
  }) async {
    final hasPerms = await checkAndRequestPermissions();
    if (!hasPerms) return [];

    final primarySuffix = last10Digits(lead.phoneNumber);
    final secondarySuffix = last10Digits(lead.secondaryPhone ?? '');
    final targetSuffixes = <String>{
      if (primarySuffix.isNotEmpty) primarySuffix,
      if (secondarySuffix.isNotEmpty) secondarySuffix,
    };
    if (targetSuffixes.isEmpty) return [];

    // Fetch complete callLogs directly for this lead from server
    List<CallSyncItem> leadServerCalls = [];
    try {
      final details = await _api.getLeadDetails(lead.id).timeout(const Duration(seconds: 12));
      final rawLogs = details['callLogs'] as List? ?? [];
      leadServerCalls = rawLogs.map((j) {
        final m = Map<String, dynamic>.from(j as Map);
        m['phoneNumber'] ??= lead.phoneNumber;
        m['leadId'] ??= lead.id;
        return CallSyncItem.fromJson(m);
      }).toList();
    } catch (_) {
      await _ensureServerCallCache(force: true, limit: 300);
      leadServerCalls = _cachedServerCalls;
    }

    final results = <Map<String, dynamic>>[];
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final daysToQuery = lookbackDays > 0 ? lookbackDays : 90;
      final lookbackEpoch =
          DateTime.now().subtract(Duration(days: daysToQuery)).millisecondsSinceEpoch;

      final entries = await CallLog.query(dateFrom: lookbackEpoch);
      final seenSignatures = <String>{};

      for (final entry in entries) {
        final callType = entry.callType;
        final isIncoming = callType == CallType.incoming ||
            callType == CallType.wifiIncoming ||
            callType == CallType.answeredExternally;
        final isMissed = callType == CallType.missed || callType == CallType.rejected;
        final isOutgoing = callType == CallType.outgoing || callType == CallType.wifiOutgoing;
        if (!isIncoming && !isMissed && !isOutgoing) continue;

        final timestampEpoch = entry.timestamp;
        if (timestampEpoch == null || timestampEpoch < lookbackEpoch || timestampEpoch > nowMs + 60000) {
          continue;
        }

        final rawNumber = entry.number ?? '';
        final suffix = last10Digits(rawNumber);
        if (!targetSuffixes.contains(suffix)) continue;

        final duration = (!isMissed && entry.duration != null && entry.duration! > 0)
            ? entry.duration!
            : 0;
        final isInboundOrMissed = isIncoming || isMissed;
        final signature = buildCallSignature(
          phoneNumber: suffix,
          timestampEpoch: timestampEpoch,
          durationSeconds: duration,
          isInbound: isInboundOrMissed,
        );
        if (seenSignatures.contains(signature)) continue;
        seenSignatures.add(signature);

        final isLogged = _isCallInServerList(
          leadServerCalls,
          lead,
          timestampEpoch,
          duration,
          isInbound: isInboundOrMissed,
        );

        final timestampIso =
            DateTime.fromMillisecondsSinceEpoch(timestampEpoch, isUtc: true).toIso8601String();
        final isMissedCall = isInboundOrMissed && (isMissed || duration == 0);

        final callItem = CallSyncItem(
          id: '${isInboundOrMissed ? "inbound" : "outbound"}_${timestampEpoch}_$suffix',
          leadId: lead.id,
          phoneNumber: rawNumber.isNotEmpty ? rawNumber : lead.phoneNumber,
          durationSeconds: duration,
          disposition: isInboundOrMissed
              ? (isMissedCall ? 'RNR' : 'Connected')
              : (duration > 0 ? 'Connected' : 'RNR'),
          callTimestamp: timestampIso,
          remark: isInboundOrMissed
              ? (isMissedCall ? 'Missed inbound call from customer' : 'Inbound call from customer')
              : 'Synced from Phone Dialer',
          logSource: isInboundOrMissed
              ? (isMissedCall ? 'inbound_missed' : 'inbound_sim')
              : 'apk_manual',
          isSynced: isLogged,
        );

        results.add({
          'lead': lead,
          'call': callItem,
          'signature': signature,
          'isInbound': isInboundOrMissed,
          'isMissed': isMissedCall,
          'isLogged': isLogged,
          'timestampEpoch': timestampEpoch,
        });
      }
    } catch (_) {}

    // Newest first for UI display
    results.sort((a, b) => (b['timestampEpoch'] as int).compareTo(a['timestampEpoch'] as int));
    return results;
  }

  /// Scan phone call logs across ALL CRM leads (e.g. last 7 days) and return unlogged calls (oldest-first).
  Future<List<Map<String, dynamic>>> scanAllCrmPhoneCalls({
    int lookbackDays = 7,
  }) async {
    final hasPerms = await checkAndRequestPermissions();
    if (!hasPerms) return [];

    await _ensureLeadCache(force: true);
    if (_cachedLeadBySuffix.isEmpty) return [];
    await _ensureServerCallCache(force: true, limit: 500);

    final pending = <Map<String, dynamic>>[];
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final daysToQuery = lookbackDays > 0 ? lookbackDays : 30;
      final lookbackEpoch =
          DateTime.now().subtract(Duration(days: daysToQuery)).millisecondsSinceEpoch;
      final entries = await CallLog.query(dateFrom: lookbackEpoch);
      final seenSignatures = <String>{};

      for (final entry in entries) {
        final callType = entry.callType;
        final isIncoming = callType == CallType.incoming ||
            callType == CallType.wifiIncoming ||
            callType == CallType.answeredExternally;
        final isMissed = callType == CallType.missed || callType == CallType.rejected;
        final isOutgoing = callType == CallType.outgoing || callType == CallType.wifiOutgoing;
        if (!isIncoming && !isMissed && !isOutgoing) continue;

        final timestampEpoch = entry.timestamp;
        if (timestampEpoch == null || timestampEpoch < lookbackEpoch || timestampEpoch > nowMs + 60000) {
          continue;
        }

        final rawNumber = entry.number ?? '';
        final suffix = last10Digits(rawNumber);
        final matchedLead = _cachedLeadBySuffix[suffix];
        if (matchedLead == null) continue;

        final duration = (!isMissed && entry.duration != null && entry.duration! > 0)
            ? entry.duration!
            : 0;
        final isInboundOrMissed = isIncoming || isMissed;
        final signature = buildCallSignature(
          phoneNumber: suffix,
          timestampEpoch: timestampEpoch,
          durationSeconds: duration,
          isInbound: isInboundOrMissed,
        );
        if (seenSignatures.contains(signature)) continue;
        seenSignatures.add(signature);

        if (_isCallInServerList(
          _cachedServerCalls,
          matchedLead,
          timestampEpoch,
          duration,
          isInbound: isInboundOrMissed,
        )) {
          continue;
        }

        final timestampIso =
            DateTime.fromMillisecondsSinceEpoch(timestampEpoch, isUtc: true).toIso8601String();
        final isMissedCall = isInboundOrMissed && (isMissed || duration == 0);

        pending.add({
          'lead': matchedLead,
          'call': CallSyncItem(
            id: '${isInboundOrMissed ? "inbound" : "outbound"}_${timestampEpoch}_$suffix',
            leadId: matchedLead.id,
            phoneNumber: rawNumber.isNotEmpty ? rawNumber : matchedLead.phoneNumber,
            durationSeconds: duration,
            disposition: isInboundOrMissed
                ? (isMissedCall ? 'RNR' : 'Connected')
                : (duration > 0 ? 'Connected' : 'RNR'),
            callTimestamp: timestampIso,
            remark: isInboundOrMissed
                ? (isMissedCall ? 'Missed inbound call from customer' : 'Inbound call from customer')
                : 'Synced from Phone Dialer',
            logSource: isInboundOrMissed
                ? (isMissedCall ? 'inbound_missed' : 'inbound_sim')
                : 'apk_manual',
            isSynced: false,
          ),
          'signature': signature,
          'isInbound': isInboundOrMissed,
          'isMissed': isMissedCall,
          'timestampEpoch': timestampEpoch,
        });
      }
    } catch (_) {}

    pending.sort((a, b) => (a['timestampEpoch'] as int).compareTo(b['timestampEpoch'] as int));
    return pending;
  }

  /// Inspect Android CallLog for the next un-synced call from active CRM leads
  Future<Map<String, dynamic>?> detectLastInboundCall() async {
    final queue = await detectPendingInboundCalls();
    return queue.isNotEmpty ? queue.first : null;
  }

  /// Locate the newest call recording file on the Android filesystem
  Future<File?> findLatestRecordingFile() async {
    if (!Platform.isAndroid) return null;
    const int maxRecordingBytes = 15 * 1024 * 1024;
    try {
      final candidateDirs = [
        Directory('/storage/emulated/0/Recordings/Call'),
        Directory('/storage/emulated/0/MIUI/sound_recorder/call_rec'),
        Directory('/storage/emulated/0/Music/Recordings/Call'),
        Directory('/storage/emulated/0/CallRecordings'),
        Directory('/storage/emulated/0/Recordings'),
        Directory('/storage/emulated/0/Sounds'),
      ];

      final now = DateTime.now();
      final validExtensions = ['.m4a', '.mp3', '.amr', '.wav', '.aac', '.3gp', '.ogg'];

      File? newestFile;
      DateTime? newestTime;

      for (var dir in candidateDirs) {
        if (await dir.exists()) {
          final entities = dir.listSync();
          for (var entity in entities) {
            if (entity is File) {
              final lower = entity.path.toLowerCase();
              if (validExtensions.any((ext) => lower.endsWith(ext))) {
                final stat = entity.statSync();
                // Filter files created or updated in last 10 minutes and under 15 MB
                if (stat.size > 0 &&
                    stat.size <= maxRecordingBytes &&
                    now.difference(stat.modified).inMinutes < 10) {
                  if (newestTime == null || stat.modified.isAfter(newestTime)) {
                    newestTime = stat.modified;
                    newestFile = entity;
                  }
                }
              }
            }
          }
        }
      }
      return newestFile;
    } catch (_) {
      return null;
    }
  }
}
