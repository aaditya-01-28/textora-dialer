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

    if (token.isNotEmpty) {
      await _storage.saveToken(token);
      await _storage.saveUserProfile(user);
    } else {
      throw Exception('Server did not return a valid session token.');
    }

    return user;
  }

  /// Fetch Assigned Leads for the Logged-In Sales Rep
  Future<List<LeadItem>> getLeads({int page = 1, String? search}) async {
    final baseUrl = await _storage.getBaseUrl();
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': '50',
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    };

    final url = Uri.parse('$baseUrl/api/leads').replace(queryParameters: queryParams);
    final headers = await _headers();

    final res = await http.get(url, headers: headers);
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

  /// Get the Next Queue Lead for Fast Calling
  Future<LeadItem?> getNextQueueLead() async {
    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/leads?queue=true');
    final headers = await _headers();

    final res = await http.get(url, headers: headers);
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
    };

    try {
      final res = await http.post(
        url,
        headers: headers,
        body: jsonEncode(payload),
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
  }) async {
    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/leads/$leadId/dispose');
    final headers = await _headers();

    try {
      final res = await http.patch(
        url,
        headers: headers,
        body: jsonEncode({
          'disposition': disposition,
          'durationSeconds': durationSeconds,
          'remark': remark,
        }),
      );
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
  Future<DashboardStats> getDashboardStats({String period = 'today'}) async {
    final baseUrl = await _storage.getBaseUrl();
    final url = Uri.parse('$baseUrl/api/dashboard/stats?period=$period');
    final headers = await _headers();

    final res = await http.get(url, headers: headers);
    if (res.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    }
    if (res.statusCode != 200) {
      throw Exception('Failed to load dashboard statistics.');
    }

    final data = jsonDecode(res.body);
    final statsJson = data['stats'] as Map<String, dynamic>? ?? {};
    return DashboardStats.fromJson(statsJson);
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

    final res = await http.patch(
      url,
      headers: headers,
      body: jsonEncode(payload),
    );

    if (res.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    }
    return res.statusCode == 200;
  }
}


