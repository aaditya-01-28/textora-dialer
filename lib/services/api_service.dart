import 'dart:convert';
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
  ApiService._internal();

  final StorageService _storage = StorageService();

  Future<Map<String, String>> _headers() async {
    final token = await _storage.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Login with CRM Credentials
  Future<UserProfile> login(String email, String password) async {
    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/auth/login');

    final res = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim(), 'password': password}),
    );

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

  /// Silent Token Refresh to Prevent Repeated Disconnects in Mobile APK
  Future<bool> refreshToken() async {
    final refresh = await _storage.getRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;

    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/auth/refresh');

    try {
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refresh}),
      );

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
    final headers = await _headers();

    var res = await http.get(url, headers: headers);
    if (res.statusCode == 401) {
      final refreshed = await refreshToken();
      if (refreshed) {
        final newHeaders = await _headers();
        res = await http.get(url, headers: newHeaders);
      }
    }
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
        if (leadDigits.endsWith(suffix) || suffix.endsWith(leadDigits)) {
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
    final headers = await _headers();

    var res = await http.get(url, headers: headers);
    if (res.statusCode == 401) {
      final refreshed = await refreshToken();
      if (refreshed) {
        final newHeaders = await _headers();
        res = await http.get(url, headers: newHeaders);
      }
    }
    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body);
    if (data['lead'] != null) {
      return LeadItem.fromJson(data['lead']);
    }
    return null;
  }

  /// Sync an Individual Call Log to the CRM
  Future<bool> syncCallLog(CallSyncItem item) async {
    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/calls');
    final headers = await _headers();

    final payload = {
      if (item.leadId != null) 'leadId': item.leadId,
      'phoneNumber': item.phoneNumber,
      'durationSeconds': item.durationSeconds,
      'disposition': item.disposition,
      'callTimestamp': item.callTimestamp,
      if (item.remark != null) 'remark': item.remark,
      if (item.recordingUrl != null) 'recordingUrl': item.recordingUrl,
      'logSource': item.logSource,
    };

    try {
      var res = await http.post(
        url,
        headers: headers,
        body: jsonEncode(payload),
      );

      if (res.statusCode == 401) {
        final refreshed = await refreshToken();
        if (refreshed) {
          final newHeaders = await _headers();
          res = await http.post(
            url,
            headers: newHeaders,
            body: jsonEncode(payload),
          );
        }
      }

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

  /// Fetch Call Logs from CRM Backend (with optional dateFrom, dateTo, search)
  Future<List<CallSyncItem>> getCallLogs({
    String? dateFrom,
    String? dateTo,
    String? search,
    int limit = 100,
  }) async {
    final baseUrl = await _storage.getBaseUrl();
    final queryParams = <String, String>{
      'limit': limit.toString(),
      if (dateFrom != null && dateFrom.isNotEmpty) 'dateFrom': dateFrom,
      if (dateTo != null && dateTo.isNotEmpty) 'dateTo': dateTo,
      if (search != null && search.isNotEmpty) 'search': search,
    };
    final uri = Uri.parse('$baseUrl/api/calls').replace(queryParameters: queryParams);
    final headers = await _headers();

    try {
      var res = await http.get(uri, headers: headers);
      if (res.statusCode == 401) {
        final refreshed = await refreshToken();
        if (refreshed) {
          final newHeaders = await _headers();
          res = await http.get(uri, headers: newHeaders);
        }
      }

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
    final token = await _storage.getToken();

    try {
      final request = http.MultipartRequest('POST', url);
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      if (leadId != null) request.fields['leadId'] = leadId;
      if (callLogId != null) request.fields['callLogId'] = callLogId;

      final file = await http.MultipartFile.fromPath('file', filePath);
      request.files.add(file);

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

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
    final headers = await _headers();

    try {
      final res = await http.get(url, headers: headers);
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
    final headers = await _headers();

    try {
      final res = await http.patch(
        url,
        headers: headers,
        body: jsonEncode({'jobId': jobId, 'status': status}),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

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
  }) async {
    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/leads/$leadId/dispose');
    final headers = await _headers();

    final payload = <String, dynamic>{
      'disposition': disposition,
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

    try {
      var res = await http.patch(
        url,
        headers: headers,
        body: jsonEncode(payload),
      );

      if (res.statusCode == 401) {
        final refreshed = await refreshToken();
        if (refreshed) {
          final newHeaders = await _headers();
          res = await http.patch(
            url,
            headers: newHeaders,
            body: jsonEncode(payload),
          );
        }
      }

      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Flush All Unsynced Offline Calls When Network Reconnects
  Future<int> flushOfflineQueue() async {
    final history = await _storage.getCallHistory();
    final unsynced = history.where((c) => !c.isSynced).toList();
    int syncedCount = 0;

    for (var item in unsynced) {
      final ok = await syncCallLog(item);
      if (ok) syncedCount++;
    }

    return syncedCount;
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
    final headers = await _headers();

    var res = await http.get(url, headers: headers);
    if (res.statusCode == 401) {
      final refreshed = await refreshToken();
      if (refreshed) {
        final newHeaders = await _headers();
        res = await http.get(url, headers: newHeaders);
      }
    }
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
    final headers = await _headers();

    final res = await http.get(url, headers: headers);
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
    final headers = await _headers();

    final payload = <String, dynamic>{};
    if (fullName != null) payload['fullName'] = fullName.trim();
    if (phoneNumber != null) payload['phoneNumber'] = phoneNumber.trim();
    if (avatarUrl != null) payload['avatarUrl'] = avatarUrl.trim();
    if (currentPassword != null) payload['currentPassword'] = currentPassword;
    if (newPassword != null) payload['newPassword'] = newPassword;

    final res = await http.patch(
      url,
      headers: headers,
      body: jsonEncode(payload),
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

    final res = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

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
    final headers = await _headers();

    final res = await http.get(url, headers: headers);
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
    final headers = await _headers();

    var res = await http.patch(
      url,
      headers: headers,
      body: jsonEncode(payload),
    );

    if (res.statusCode == 401) {
      final refreshed = await refreshToken();
      if (refreshed) {
        final newHeaders = await _headers();
        res = await http.patch(
          url,
          headers: newHeaders,
          body: jsonEncode(payload),
        );
      }
    }

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

  /// Fetch Scheduled Agenda & Tasks (Today, Overdue, Upcoming)
  Future<Map<String, dynamic>> getAgendaTasks() async {
    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/tasks');
    final headers = await _headers();

    final res = await http.get(url, headers: headers);
    if (res.statusCode == 401) {
      final refreshed = await refreshToken();
      if (refreshed) {
        final retryHeaders = await _headers();
        final retryRes = await http.get(url, headers: retryHeaders);
        if (retryRes.statusCode == 200) {
          return jsonDecode(retryRes.body) as Map<String, dynamic>;
        }
      }
      throw Exception('Session expired. Please log in again.');
    }
    if (res.statusCode != 200) {
      throw Exception('Failed to load tasks');
    }

    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}


