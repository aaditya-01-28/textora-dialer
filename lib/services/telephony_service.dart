import 'dart:async';
import 'dart:io';
import 'package:call_log/call_log.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/call_sync_item.dart';
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

  // Active call session tracking
  String? activeDialedNumber;
  String? activeLeadId;
  DateTime? callInitiatedTime;

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
      // Query recent calls from the last 15 minutes
      final lookbackEpoch = DateTime.now().subtract(const Duration(minutes: 15)).millisecondsSinceEpoch;
      final Iterable<CallLogEntry> entries = await CallLog.query(
        dateFrom: lookbackEpoch,
      );

      CallLogEntry? matchedEntry;

      // Match by phone number suffix (last 10 digits)
      final cleanTarget = targetPhone.replaceAll(RegExp(r'\D'), '');
      final targetSuffix = cleanTarget.length >= 10 ? cleanTarget.substring(cleanTarget.length - 10) : cleanTarget;

      for (var entry in entries) {
        final number = (entry.number ?? '').replaceAll(RegExp(r'\D'), '');
        if (number.endsWith(targetSuffix)) {
          matchedEntry = entry;
          break;
        }
      }

      // If exact number not matched, take the latest outgoing entry
      matchedEntry ??= entries.isNotEmpty ? entries.first : null;

      if (matchedEntry != null) {
        final duration = matchedEntry.duration ?? 0;
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
          logSource: 'dialer_connected',
        );

        // Store locally
        await _storage.saveCallRecord(item);

        // If this call belongs to an active lead, PostCallDialog will handle disposition.
        // Only auto-sync here if there is no active lead dossier attached to avoid duplicate entries.
        if (activeLeadId == null) {
          _api.syncCallLog(item);
        }

        return item;
      }
    } catch (e) {
      // Android permission or provider error
    }

    return null;
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
