import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/user_profile.dart';
import '../models/lead_item.dart';
import '../models/call_sync_item.dart';
import '../models/dashboard_stats.dart';
import 'storage_service.dart';

/// Direct API Service
/// Connects EXCLUSIVELY to your company's CRM backend.
/// ZERO external analytics, ZERO telemetry, ZERO 3rd-party tracking.
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal()
      : _storage = StorageService(),
        _client = http.Client();

  @visibleForTesting
  ApiService.forTest({required http.Client client, StorageService? storage})
      : _client = client,
        _storage = storage ?? StorageService();

  static const Duration _defaultTimeout = Duration(seconds: 15);
  static const Duration _disposeTimeout = Duration(seconds: 20);

  final StorageService _storage;
  final http.Client _client;
  Future<bool>? _refreshInFlight;
  bool _isFlushingQueue = false;
  VoidCallback? onSessionExpired;

  Future<Map<String, String>> _headers() async {
    final token = await _storage.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _handleSessionExpired() async {
    await _storage.clearAuth();
    onSessionExpired?.call();
  }

  Future<http.Response> _sendWithAuthRetry(
    Future<http.Response> Function(Map<String, String> headers) send, {
    Duration timeout = _defaultTimeout,
  }) async {
    final headers = await _headers();
    var res = await send(headers).timeout(timeout);
    if (res.statusCode == 401) {
      final refreshed = await refreshToken();
      if (refreshed) {
        final newHeaders = await _headers();
        res = await send(newHeaders).timeout(timeout);
      }
      if (res.statusCode == 401) {
        await _handleSessionExpired();
      }
    }
    return res;
  }

  /// Login with CRM Credentials
  Future<UserProfile> login(String email, String password) async {
    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/auth/login');

    final res = await _client
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email.trim(),
            'password': password,
            'client': 'mobile',
          }),
        )
        .timeout(_defaultTimeout);

    if (res.statusCode != 200) {
      final body = jsonDecode(res.body);
      throw Exception(body['error'] ?? 'Login failed (Status: ${res.statusCode})');
    }

    final data = jsonDecode(res.body);
    final user = UserProfile.fromJson(data['user']);
    final token = data['accessToken'] ?? '';
    final refreshToken = data['refreshToken'] ?? '';

    if (token.isNotEmpty) {
      await _storage.saveToken(token);
      if (refreshToken.isNotEmpty) {
        await _storage.saveRefreshToken(refreshToken);
      }
      await _storage.saveUserProfile(user);
    } else {
      throw Exception('Server did not return a valid session token.');
    }

    return user;
  }

  /// Silent Token Refresh to Prevent Repeated Disconnects in Mobile APK (single-flight)
  Future<bool> refreshToken() {
    if (_refreshInFlight != null) return _refreshInFlight!;
    _refreshInFlight = _doRefreshToken().whenComplete(() {
      _refreshInFlight = null;
    });
    return _refreshInFlight!;
  }

  Future<bool> _doRefreshToken() async {
    final refresh = await _storage.getRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;

    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/auth/refresh');

    try {
      final res = await _client
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': refresh, 'client': 'mobile'}),
          )
          .timeout(_defaultTimeout);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final token = data['accessToken'] ?? '';
        final newRefresh = data['refreshToken'] ?? '';
        if (token.isNotEmpty) {
          await _storage.saveToken(token);
          if (newRefresh.isNotEmpty) {
            await _storage.saveRefreshToken(newRefresh);
          }
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// Fetch Assigned Leads for the Logged-In Sales Rep
  Future<List<LeadItem>> getLeads({int page = 1, String? search, String? status}) async {
    final baseUrl = await _storage.getBaseUrl();
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': '10000',
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (status != null && status != 'all') 'status': status,
    };

    final url = Uri.parse('$baseUrl/api/leads').replace(queryParameters: queryParams);
    final res = await _sendWithAuthRetry((h) => _client.get(url, headers: h));
    if (res.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    }
    if (res.statusCode != 200) {
      throw Exception('Failed to load leads from CRM.');
    }

    final data = jsonDecode(res.body);
    final list = data['leads'] as List? ?? [];
    return list.map((json) => LeadItem.fromJson(json)).toList();
  }

  /// Find CRM Lead by Phone Number (matching last 10 digits)
  Future<LeadItem?> findLeadByPhone(String rawPhone) async {
    final cleanDigits = rawPhone.replaceAll(RegExp(r'\D'), '');
    final suffix = cleanDigits.length >= 10 ? cleanDigits.substring(cleanDigits.length - 10) : cleanDigits;
    if (suffix.isEmpty) return null;

    try {
      final list = await getLeads(search: suffix);
      for (var l in list) {
        final leadDigits = l.phoneNumber.replaceAll(RegExp(r'\D'), '');
        final secDigits = (l.secondaryPhone ?? '').replaceAll(RegExp(r'\D'), '');
        if (leadDigits.endsWith(suffix) ||
            suffix.endsWith(leadDigits) ||
            (secDigits.isNotEmpty &&
                (secDigits.endsWith(suffix) || suffix.endsWith(secDigits)))) {
          return l;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Get the Next Queue Lead for Fast Calling
  Future<LeadItem?> getNextQueueLead() async {
    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/leads?queue=true');

    final res = await _sendWithAuthRetry((h) => _client.get(url, headers: h));
    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body);
    if (data['lead'] != null) {
      return LeadItem.fromJson(data['lead']);
    }
    return null;
  }

  /// Sync an Individual Call Log to the CRM
  Future<bool> syncCallLog(CallSyncItem item, {bool historicalSync = false}) async {
    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/calls');

    final payload = {
      if (item.leadId != null) 'leadId': item.leadId,
      'phoneNumber': item.phoneNumber,
      'durationSeconds': item.durationSeconds,
      'disposition': item.disposition,
      'callTimestamp': item.callTimestamp,
      if (item.remark != null) 'remark': item.remark,
      if (item.recordingUrl != null) 'recordingUrl': item.recordingUrl,
      'logSource': item.logSource,
      'isInterested': item.isInterested,
      if (historicalSync) 'historicalSync': true,
    };

    try {
      final res = await _sendWithAuthRetry(
        (h) => _client.post(url, headers: h, body: jsonEncode(payload)),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        await _storage.updateCallRecordSyncStatus(item.id, true);
        return true;
      }
      return false;
    } catch (_) {
      // Offline: keep as unsynced in local queue
      return false;
    }
  }

  /// Sync Multiple Call Logs to CRM in a Single Batch
  Future<int> batchSyncCallLogs(List<CallSyncItem> items, {bool historicalSync = true}) async {
    if (items.isEmpty) return 0;
    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/calls');
    final payload = {
      'calls': items
          .map((item) => {
                if (item.leadId != null) 'leadId': item.leadId,
                'phoneNumber': item.phoneNumber,
                'durationSeconds': item.durationSeconds,
                'disposition': item.disposition,
                'callTimestamp': item.callTimestamp,
                if (item.remark != null) 'remark': item.remark,
                if (item.recordingUrl != null) 'recordingUrl': item.recordingUrl,
                'logSource': item.logSource,
                'isInterested': item.isInterested,
                if (historicalSync) 'historicalSync': true,
              })
          .toList(),
    };

    try {
      final res = await _sendWithAuthRetry(
        (h) => _client.post(url, headers: h, body: jsonEncode(payload)),
        timeout: _disposeTimeout,
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        return (data['syncedCount'] is num) ? (data['syncedCount'] as num).toInt() : items.length;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  /// Fetch Call Logs from CRM Backend (with optional dateFrom, dateTo, disposition, search)
  Future<List<CallSyncItem>> getCallLogs({
    String? dateFrom,
    String? dateTo,
    String? disposition,
    String? search,
    int limit = 100,
  }) async {
    final baseUrl = await _storage.getBaseUrl();
    final queryParams = <String, String>{
      'limit': limit.toString(),
      if (dateFrom != null && dateFrom.isNotEmpty) 'dateFrom': dateFrom,
      if (dateTo != null && dateTo.isNotEmpty) 'dateTo': dateTo,
      if (disposition != null && disposition.isNotEmpty) 'disposition': disposition,
      if (search != null && search.isNotEmpty) 'search': search,
    };
    final uri = Uri.parse('$baseUrl/api/calls').replace(queryParameters: queryParams);

    try {
      final res = await _sendWithAuthRetry((h) => _client.get(uri, headers: h));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = (data['calls'] as List?) ?? [];
        return list.map((json) {
          final item = CallSyncItem.fromJson(json);
          item.isSynced = true;
          return item;
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Upload Native Call Recording Audio File to CRM Storage
  Future<String?> uploadRecordingFile(String filePath, {String? leadId, String? callLogId}) async {
    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/telephony/recordings');

    Future<http.Response> sendMultipart(String? token) async {
      final request = http.MultipartRequest('POST', url);
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      if (leadId != null) request.fields['leadId'] = leadId;
      if (callLogId != null) request.fields['callLogId'] = callLogId;
      final file = await http.MultipartFile.fromPath('file', filePath);
      request.files.add(file);
      final streamed = await _client.send(request).timeout(const Duration(seconds: 30));
      return http.Response.fromStream(streamed);
    }

    try {
      var response = await sendMultipart(await _storage.getToken());
      if (response.statusCode == 401) {
        final refreshed = await refreshToken();
        if (refreshed) {
          response = await sendMultipart(await _storage.getToken());
        }
        if (response.statusCode == 401) {
          await _handleSessionExpired();
          return null;
        }
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['recordingUrl'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Check if Web CRM dispatched a push-to-dial call to this phone
  Future<Map<String, dynamic>?> checkPushToDialJob() async {
    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/telephony/push-to-dial?poll=true');

    try {
      final res = await _sendWithAuthRetry((h) => _client.get(url, headers: h));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['hasJob'] == true && data['job'] != null) {
          return data['job'] as Map<String, dynamic>;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Update Push-to-Dial Job Status (ringing, in_call, completed, cancelled)
  Future<bool> updatePushToDialStatus(String jobId, String status) async {
    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/telephony/push-to-dial');

    try {
      final res = await _sendWithAuthRetry(
        (h) => _client.patch(url, headers: h, body: jsonEncode({'jobId': jobId, 'status': status})),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  String? lastError;

  /// Dispose Lead with Outcome and Duration
  Future<bool> disposeLead({
    required String leadId,
    required String disposition,
    required int durationSeconds,
    String? remark,
    String? callbackDatetime,
    String? demoDatetime,
    String? decisionMakerName,
    String? meetingLink,
    String? callTimestamp,
    String? callLogId,
    String? logSource,
    bool isInterested = false,
    bool historicalSync = false,
  }) async {
    lastError = null;
    if (leadId.trim().isEmpty) {
      lastError = 'Missing lead ID for this call.';
      return false;
    }

    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/leads/$leadId/dispose');

    final payload = <String, dynamic>{
      'disposition': disposition,
      'isInterested': isInterested,
      'durationSeconds': durationSeconds,
      'remark': remark,
      'logSource': logSource ?? 'apk_manual',
    };
    if (callbackDatetime != null) payload['callbackDatetime'] = callbackDatetime;
    if (demoDatetime != null) payload['demoDatetime'] = demoDatetime;
    if (decisionMakerName != null) payload['decisionMakerName'] = decisionMakerName;
    if (meetingLink != null) payload['meetingLink'] = meetingLink;
    if (callTimestamp != null) payload['callTimestamp'] = callTimestamp;
    if (callLogId != null) payload['callLogId'] = callLogId;
    if (historicalSync) payload['historicalSync'] = true;

    try {
      final res = await _sendWithAuthRetry(
        (h) => _client.patch(url, headers: h, body: jsonEncode(payload)),
        timeout: _disposeTimeout,
      );

      if (res.statusCode == 200) return true;

      try {
        final errBody = jsonDecode(res.body);
        lastError = errBody['error']?.toString() ?? 'Server error (${res.statusCode})';
      } catch (_) {
        lastError = 'Server error (${res.statusCode})';
      }
      return false;
    } on TimeoutException {
      lastError = 'Request timed out. Please check your internet and try again.';
      return false;
    } catch (e) {
      lastError = 'Network error: ${e.toString()}';
      return false;
    }
  }

  /// Flush All Unsynced Offline Calls When Network Reconnects (mutex-guarded)
  Future<int> flushOfflineQueue() async {
    if (_isFlushingQueue) return 0;
    _isFlushingQueue = true;
    try {
      final history = await _storage.getCallHistory();
      final unsynced = history.where((c) => !c.isSynced).toList();
      int syncedCount = 0;

      for (var item in unsynced) {
        // Hold temporary SIM dialer drafts briefly so an active PostCallDialog can save cleanly first
        if (!item.needsDisposeSync && item.leadId != null && item.remark == 'Captured from SIM dialer') {
          try {
            final ts = DateTime.parse(item.callTimestamp).toUtc();
            if (DateTime.now().toUtc().difference(ts).inMinutes < 2) {
              continue;
            }
          } catch (_) {}
        }

        bool ok;
        if (item.needsDisposeSync && item.leadId != null && item.leadId!.isNotEmpty) {
          ok = await disposeLead(
            leadId: item.leadId!,
            disposition: item.disposition,
            durationSeconds: item.durationSeconds,
            remark: item.remark,
            callbackDatetime: item.callbackDatetime,
            demoDatetime: item.demoDatetime,
            decisionMakerName: item.decisionMakerName,
            meetingLink: item.meetingLink,
            callTimestamp: item.callTimestamp,
            callLogId: item.id,
            logSource: item.logSource,
            isInterested: item.isInterested,
          );
          if (ok) {
            await _storage.updateCallRecordSyncStatus(item.id, true);
          }
        } else {
          ok = await syncCallLog(item);
        }
        if (ok) syncedCount++;
      }

      return syncedCount;
    } finally {
      _isFlushingQueue = false;
    }
  }

  /// Fetch Real-Time Dashboard Statistics
  Future<DashboardStats> getDashboardStats({
    String period = 'today',
    String? dateFrom,
    String? dateTo,
    String? userId,
  }) async {
    final baseUrl = await _storage.getBaseUrl();
    final queryParams = <String, String>{
      'period': period,
      if (dateFrom != null && dateFrom.isNotEmpty) 'dateFrom': dateFrom,
      if (dateTo != null && dateTo.isNotEmpty) 'dateTo': dateTo,
      if (userId != null && userId.isNotEmpty) 'userId': userId,
    };
    final url = Uri.parse('$baseUrl/api/dashboard/stats').replace(queryParameters: queryParams);

    final res = await _sendWithAuthRetry((h) => _client.get(url, headers: h));
    if (res.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    }
    if (res.statusCode != 200) {
      throw Exception('Failed to load dashboard statistics.');
    }

    final data = jsonDecode(res.body);
    final statsJson = (data['metrics'] ?? data['stats']) as Map<String, dynamic>? ?? {};

    final members = <DashboardTeamMember>[];
    if (data['teamMembers'] is List) {
      for (var m in (data['teamMembers'] as List)) {
        if (m is Map<String, dynamic>) {
          members.add(DashboardTeamMember.fromJson(m));
        }
      }
    }

    return DashboardStats.fromJson(
      statsJson,
      teamMembers: members,
      dateFrom: data['dateFrom']?.toString(),
      dateTo: data['dateTo']?.toString(),
    );
  }

  /// Fetch Detailed User Profile with Hierarchy & Counts
  Future<UserProfile> getDetailedProfile() async {
    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/profile');

    final res = await _sendWithAuthRetry((h) => _client.get(url, headers: h));
    if (res.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    }
    if (res.statusCode != 200) {
      throw Exception('Failed to load user profile.');
    }

    final data = jsonDecode(res.body);
    final userJson = data['user'] as Map<String, dynamic>? ?? {};
    final updatedProfile = UserProfile.fromJson(userJson);
    await _storage.saveUserProfile(updatedProfile);
    return updatedProfile;
  }

  /// Update User Profile Details
  Future<bool> updateProfile({
    String? fullName,
    String? phoneNumber,
    String? avatarUrl,
    String? currentPassword,
    String? newPassword,
  }) async {
    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/profile');

    final payload = <String, dynamic>{};
    if (fullName != null) payload['fullName'] = fullName.trim();
    if (phoneNumber != null) payload['phoneNumber'] = phoneNumber.trim();
    if (avatarUrl != null) payload['avatarUrl'] = avatarUrl.trim();
    if (currentPassword != null) payload['currentPassword'] = currentPassword;
    if (newPassword != null) payload['newPassword'] = newPassword;

    final res = await _sendWithAuthRetry(
      (h) => _client.patch(url, headers: h, body: jsonEncode(payload)),
    );

    return res.statusCode == 200;
  }

  /// Request Password Reset (matches Web CRM workflow)
  Future<Map<String, dynamic>> requestForgotPassword(String email, {String? notes}) async {
    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/auth/forgot-password');

    final payload = <String, dynamic>{'email': email.trim().toLowerCase()};
    if (notes != null && notes.trim().isNotEmpty) {
      payload['notes'] = notes.trim();
    }

    final res = await _client
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(_defaultTimeout);

    final data = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Failed to submit password reset request');
    }

    return data as Map<String, dynamic>;
  }

  /// Fetch Full Lead Dossier (Contact, History, Tasks)
  Future<Map<String, dynamic>> getLeadDetails(String leadId) async {
    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/leads/$leadId');

    final res = await _sendWithAuthRetry((h) => _client.get(url, headers: h));
    if (res.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    }
    if (res.statusCode != 200) {
      throw Exception('Failed to load lead details.');
    }

    final data = jsonDecode(res.body);
    return data['lead'] as Map<String, dynamic>? ?? {};
  }

  /// Update Lead Profile Fields (Contact Name, Company, Status, Notes, etc.)
  Future<bool> updateLead(String leadId, Map<String, dynamic> payload) async {
    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/leads/$leadId');

    final res = await _sendWithAuthRetry(
      (h) => _client.patch(url, headers: h, body: jsonEncode(payload)),
    );

    if (res.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    }
    if (res.statusCode != 200) {
      try {
        final body = jsonDecode(res.body);
        throw Exception(body['error'] ?? 'Server returned status ${res.statusCode}');
      } catch (e) {
        if (e is Exception) rethrow;
        throw Exception('Server returned status ${res.statusCode}');
      }
    }
    return true;
  }

  /// Edit a logged call / stage / scheduled task (Level 2 Manager & Level 3 Super Admin)
  Future<bool> editLeadTimelineLog(String leadId, Map<String, dynamic> payload) async {
    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/leads/$leadId/timeline/edit');

    try {
      final res = await _sendWithAuthRetry(
        (h) => _client.patch(url, headers: h, body: jsonEncode(payload)),
      );

      if (res.statusCode != 200) {
        try {
          final body = jsonDecode(res.body);
          lastError = body['error']?.toString() ?? 'Failed to edit log';
        } catch (_) {}
        return false;
      }
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  /// Fetch Scheduled Agenda & Tasks (Today, Overdue, Upcoming)
  Future<Map<String, dynamic>> getAgendaTasks() async {
    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/tasks');

    final res = await _sendWithAuthRetry((h) => _client.get(url, headers: h));
    if (res.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    }
    if (res.statusCode != 200) {
      throw Exception('Failed to load tasks');
    }

    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Update an Agenda Task (mark completed, RNR, reschedule, etc.)
  Future<bool> updateAgendaTask(String taskId, Map<String, dynamic> payload) async {
    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/tasks/$taskId');

    try {
      final res = await _sendWithAuthRetry(
        (h) => _client.patch(url, headers: h, body: jsonEncode(payload)),
      );

      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}


