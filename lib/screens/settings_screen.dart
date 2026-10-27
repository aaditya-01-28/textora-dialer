import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/user_profile.dart';
import '../services/storage_service.dart';
import '../services/telephony_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  final UserProfile user;

  const SettingsScreen({super.key, required this.user});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storage = StorageService();
  final _telephony = TelephonyService();

  String _serverUrl = '';
  bool _phonePermissionGranted = false;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final url = await _storage.getBaseUrl();
    final status = await Permission.phone.status;
    if (mounted) {
      setState(() {
        _serverUrl = url;
        _phonePermissionGranted = status.isGranted;
      });
    }
  }

  Future<void> _requestPermissions() async {
    await _telephony.checkAndRequestPermissions();
    await _loadInfo();
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Confirm Sign Out', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to sign out from Textora Dialer?',
          style: TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _storage.clearAuth();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text(
          'Settings & Privacy',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // User Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF334155).withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFF059669),
                  child: Text(
                    widget.user.fullName.isNotEmpty ? widget.user.fullName[0].toUpperCase() : 'U',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.user.fullName,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.user.email,
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${widget.user.tenantName} • ${widget.user.role.replaceAll('_', ' ').toUpperCase()}',
                          style: const TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Privacy & Zero-Telemetry Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF059669).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.verified_user_outlined, color: Color(0xFF10B981), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Zero 3rd-Party Tracking Guarantee',
                      style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  '• No Google Firebase Analytics or AdMob.\n'
                  '• No Facebook / Meta telemetry.\n'
                  '• No external crash reporters.\n'
                  '• All API traffic is sent strictly to your company\'s encrypted CRM server.',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // System Diagnostics
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'System Configuration',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('CRM Endpoint:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                    Flexible(
                      child: Text(
                        _serverUrl,
                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const Divider(color: Color(0xFF334155), height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('CallLog Permission:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                    Row(
                      children: [
                        Text(
                          _phonePermissionGranted ? 'Granted ✅' : 'Missing ⚠️',
                          style: TextStyle(
                            color: _phonePermissionGranted ? const Color(0xFF10B981) : Colors.amber,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (!_phonePermissionGranted) ...[
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _requestPermissions,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                            ),
                            child: const Text('Grant', style: TextStyle(fontSize: 10)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Sign Out Button
          ElevatedButton.icon(
            onPressed: _handleLogout,
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.15),
              foregroundColor: Colors.redAccent,
              elevation: 0,
              side: const BorderSide(color: Color(0xFFEF4444), width: 1),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 28),
          Center(
            child: Opacity(
              opacity: 0.6,
              child: Image.asset(
                'assets/images/logo.png',
                height: 24,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'v1.0.0 • Textora Technologies Pvt Ltd',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
