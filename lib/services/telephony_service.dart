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

  /// Start background listener for Web CRM Push-to-Dial requests
  void startPushToDialListener({Function(Map<String, dynamic>)? onCallTriggered}) {
    if (isPushToDialActive) return;
    isPushToDialActive = true;

    _pushToDialTimer?.cancel();
    _pushToDialTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
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
      } catch (_) {}
    });
  }

  /// Stop listening for Web CRM Push-to-Dial requests
  void stopPushToDialListener() {
    isPushToDialActive = false;
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
    final name = (repName != null && repName.trim().isNotEmpty) ? repName.trim() : 'Aaditya';
    final email = (repEmail != null && repEmail.trim().isNotEmpty) ? repEmail.trim() : 'aaditya@textorasms.com';
    var phone = (repPhone != null && repPhone.trim().isNotEmpty) ? repPhone.trim() : '9902101007';
    phone = phone.replaceAll(RegExp(r'\D'), '');
    if (phone.length > 10) phone = phone.substring(phone.length - 10);
    if (phone.isEmpty) phone = '9902101007';

    final greetingTarget = (contactName != null && contactName.trim().isNotEmpty)
        ? contactName.trim()
        : 'Sir';

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
        '📧 $email\n'
        'https://textorasms.com\n'
        '📱 $phone\n\n'
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
    _lastLeadCacheTime = null;
    _lastServerCallsTime = null;
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

  Future<void> _ensureServerCallCache({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastServerCallsTime != null &&
        now.difference(_lastServerCallsTime!).inSeconds < 20) {
      return;
    }
    try {
      final calls = await _api.getCallLogs(limit: 150).timeout(const Duration(seconds: 10));
      _cachedServerCalls = calls;
      _lastServerCallsTime = now;
    } catch (_) {}
  }

  bool _isAlreadyLoggedOnServer(
    LeadItem lead,
    int timestampEpoch,
    int duration, {
    required bool isInbound,
  }) {
    final leadSuffix = last10Digits(lead.phoneNumber);
    for (final sc in _cachedServerCalls) {
      final matchesLead = (sc.leadId != null && sc.leadId == lead.id) ||
          (leadSuffix.isNotEmpty && last10Digits(sc.phoneNumber) == leadSuffix);
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
        } else {
          // Non-CRM personal number: mark processed so future scans stay instant
          await _storage.markCallSignatureProcessed(signature);
        }
      }
    } catch (_) {}

    // Process oldest-first so dispositions happen in chronological order
    return pendingQueue.reversed.toList();
  }

  /// Inspect Android CallLog for the next un-synced call from active CRM leads
  Future<Map<String, dynamic>?> detectLastInboundCall() async {
    final queue = await detectPendingInboundCalls();
    return queue.isNotEmpty ? queue.first : null;
  }

  /// Locate the newest call recording file on the Android filesystem
  Future<File?> findLatestRecordingFile() async {
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
                // Filter files created or updated in last 20 minutes
                if (now.difference(stat.modified).inMinutes < 20) {
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
