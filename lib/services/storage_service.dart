import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../models/call_sync_item.dart';

/// Privacy-First Local Encrypted Storage Service
/// Uses Android KeyStore (hardware-backed AES-256) to ensure credentials
/// never leak to third-party applications.
class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const String _keyToken = 'auth_token';
  static const String _keyRefreshToken = 'auth_refresh_token';
  static const String _keyUser = 'user_profile';
  static const String _keyBaseUrl = 'crm_base_url';
  static const String _keyCallQueue = 'offline_call_queue';
  static const String _defaultUrl = 'https://crm.textorasms.com';

  Future<void> saveToken(String token) async {
    await _secureStorage.write(key: _keyToken, value: token);
  }

  Future<String?> getToken() async {
    return await _secureStorage.read(key: _keyToken);
  }

  Future<void> saveRefreshToken(String token) async {
    await _secureStorage.write(key: _keyRefreshToken, value: token);
  }

  Future<String?> getRefreshToken() async {
    return await _secureStorage.read(key: _keyRefreshToken);
  }

  Future<void> saveUserProfile(UserProfile user) async {
    final raw = jsonEncode(user.toJson());
    await _secureStorage.write(key: _keyUser, value: raw);
  }

  Future<UserProfile?> getUserProfile() async {
    final raw = await _secureStorage.read(key: _keyUser);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw);
      return UserProfile.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveBaseUrl(String url) async {
    final trimmed = url.trim().replaceAll(RegExp(r'/+$'), '');
    await _secureStorage.write(key: _keyBaseUrl, value: trimmed);
  }

  Future<String> getBaseUrl() async {
    final url = await _secureStorage.read(key: _keyBaseUrl);
    if (url == null || url.contains('192.168.') || url.contains('workers.dev')) {
      return _defaultUrl;
    }
    return url;
  }

  Future<void> clearAuth() async {
    await _secureStorage.delete(key: _keyToken);
    await _secureStorage.delete(key: _keyRefreshToken);
    await _secureStorage.delete(key: _keyUser);
  }

  // --- Offline Call Queue & History ---

  Future<List<CallSyncItem>> getCallHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_keyCallQueue) ?? [];
    return rawList.map((str) {
      try {
        return CallSyncItem.fromJson(jsonDecode(str));
      } catch (_) {
        return null;
      }
    }).whereType<CallSyncItem>().toList();
  }

  Future<void> saveCallRecord(CallSyncItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getCallHistory();
    // Add to top of list
    current.insert(0, item);
    // Keep last 200 logs
    final trimmed = current.take(200).toList();
    final encoded = trimmed.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_keyCallQueue, encoded);
  }

  static const String _keyProcessedInboundCalls = 'processed_inbound_calls';

  Future<bool> isCallSignatureProcessed(String signature) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyProcessedInboundCalls) ?? [];
    return list.contains(signature);
  }

  Future<void> markCallSignatureProcessed(String signature) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyProcessedInboundCalls) ?? [];
    if (!list.contains(signature)) {
      list.insert(0, signature);
      await prefs.setStringList(_keyProcessedInboundCalls, list.take(300).toList());
    }
  }

  Future<void> updateCallRecordSyncStatus(String id, bool isSynced) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getCallHistory();
    for (var item in current) {
      if (item.id == id) {
        item.isSynced = isSynced;
      }
    }
    final encoded = current.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_keyCallQueue, encoded);
  }
}
