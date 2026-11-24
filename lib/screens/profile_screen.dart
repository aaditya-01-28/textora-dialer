import 'dart:async';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/theme_service.dart';
import '../services/update_service.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final UserProfile user;
  final Function(UserProfile updatedUser)? onProfileUpdated;

  const ProfileScreen({
    super.key,
    required this.user,
    this.onProfileUpdated,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _storage = StorageService();
  final _api = ApiService();

  late UserProfile _currentUser;
  bool _isLoading = false;
  String _appVersion = 'v1.1.0';
  bool _isCheckingUpdate = false;
  Timer? _autoRefreshTimer;

  // Accessibility Preferences
  double _fontScale = 1.0;
  bool _highContrast = false;
  bool _hapticFeedback = true;

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    _loadAccessibilityPrefs();
    _fetchLatestProfile(silent: true);
    _loadAppVersion();
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        _fetchLatestProfile(silent: true);
      }
    });
  }

  @override
  void didUpdateWidget(ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.user != oldWidget.user) {
      setState(() => _currentUser = widget.user);
    }
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = 'v${info.version} (Build ${info.buildNumber})';
        });
      }
    } catch (_) {}
  }

  Future<void> _loadAccessibilityPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _fontScale = prefs.getDouble('accessibility_font_scale') ?? 1.0;
        _highContrast = prefs.getBool('accessibility_high_contrast') ?? false;
        _hapticFeedback = prefs.getBool('accessibility_haptic') ?? true;
      });
    }
  }

  Future<void> _saveFontScale(double scale) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('accessibility_font_scale', scale);
    if (mounted) {
      setState(() => _fontScale = scale);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Display text scale set to ${(scale * 100).toInt()}%'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _toggleHighContrast(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('accessibility_high_contrast', val);
    if (mounted) setState(() => _highContrast = val);
  }

  Future<void> _toggleHaptic(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('accessibility_haptic', val);
    if (mounted) setState(() => _hapticFeedback = val);
  }

  Future<void> _fetchLatestProfile({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _isLoading = true);
    }
    try {
      final updated = await _api.getDetailedProfile();
      if (mounted) {
        setState(() {
          _currentUser = updated;
          if (!silent) _isLoading = false;
        });
        widget.onProfileUpdated?.call(updated);
      }
    } catch (_) {
      if (!silent && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatLanguage(String? lang) {
    if (lang == null || lang.isEmpty) return 'English (EN)';
    final l = lang.toLowerCase().trim();
    switch (l) {
      case 'hi':
      case 'hindi':
        return 'Hindi (हिन्दी)';
      case 'en':
      case 'english':
        return 'English (EN)';
      case 'mr':
      case 'marathi':
        return 'Marathi (मराठी)';
      case 'gu':
      case 'gujarati':
        return 'Gujarati (ગુજરાતી)';
      case 'te':
      case 'telugu':
        return 'Telugu (తెలుగు)';
      case 'ta':
      case 'tamil':
        return 'Tamil (தமிழ்)';
      case 'kn':
      case 'kannada':
        return 'Kannada (ಕನ್ನಡ)';
      case 'ml':
      case 'malayalam':
        return 'Malayalam (മലയാളം)';
      case 'bn':
      case 'bengali':
        return 'Bengali (বাংলা)';
      case 'pa':
      case 'punjabi':
        return 'Punjabi (ਪੰਜਾਬੀ)';
      case 'or':
      case 'odia':
        return 'Odia (ଓଡ଼ିଆ)';
      case 'ur':
      case 'urdu':
        return 'Urdu (اردو)';
      default:
        return lang.toUpperCase();
    }
  }

  Widget _buildAvatarImage(double radius) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF059669),
      child: Text(
        _currentUser.fullName.isNotEmpty ? _currentUser.fullName[0].toUpperCase() : 'U',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.78,
        ),
      ),
    );
  }

  Future<void> _showForgotPasswordDialog() async {
    final emailCtrl = TextEditingController(text: _currentUser.email);
    final notesCtrl = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            title: Row(
              children: [
                const Icon(Icons.lock_reset_rounded, color: Color(0xFF10B981), size: 22),
                const SizedBox(width: 8),
                Text(
                  'Request Password Reset',
                  style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 16),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Submit a password reset request to your Level 3 Super Admin:',
                  style: TextStyle(color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B), fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Optional Notes for Admin',
                    labelStyle: TextStyle(color: Color(0xFF94A3B8)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8))),
              ),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        setDialogState(() => isSubmitting = true);
                        try {
                          final res = await _api.requestForgotPassword(
                            emailCtrl.text.trim(),
                            notes: notesCtrl.text.trim(),
                          );
                          if (dialogCtx.mounted) {
                            Navigator.of(dialogCtx).pop();
                          }

                          if (!mounted) return;
                          showDialog(
                            context: context,
                            builder: (c) => AlertDialog(
                              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                              title: Text(
                                'Request Submitted',
                                style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 16),
                              ),
                              content: Text(
                                res['message'] ?? 'Password reset request sent.',
                                style: TextStyle(color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155), fontSize: 13, height: 1.4),
                              ),
                              actions: [
                                ElevatedButton(
                                  onPressed: () => Navigator.of(c).pop(),
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                        } catch (e) {
                          setDialogState(() => isSubmitting = false);
                          if (dialogCtx.mounted) {
                            ScaffoldMessenger.of(dialogCtx).showSnackBar(
                              SnackBar(
                                backgroundColor: Colors.redAccent,
                                content: Text(e.toString().replaceAll('Exception:', '').trim()),
                              ),
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
                child: isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Submit Request'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleLogout() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Text(
          'Confirm Sign Out',
          style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 17),
        ),
        content: Text(
          'Are you sure you want to sign out from Textora Dialer on this device?',
          style: TextStyle(color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B), fontSize: 14),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = _highContrast
        ? const Color(0xFF10B981)
        : isDark
            ? const Color(0xFF1E293B)
            : const Color(0xFFE2E8F0);
    final scaffoldBg = isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC);
    final appBarBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: scaffoldBg,
      appBar: AppBar(
        backgroundColor: appBarBg,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(11.0),
          child: Image.asset(
            'assets/images/icon.png',
            fit: BoxFit.contain,
          ),
        ),
        title: Text(
          'User Profile',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: titleColor),
        ),
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                ),
              ),
            )
          else
            IconButton(
              icon: Icon(Icons.refresh_rounded, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
              tooltip: 'Sync Profile',
              onPressed: () => _fetchLatestProfile(silent: false),
            ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFF10B981),
        onRefresh: () => _fetchLatestProfile(silent: false),
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. User Dossier Header Card with Avatar Photo & Camera Badge
          _buildUserHeaderCard(borderColor, isDark),
          const SizedBox(height: 14),

          // 2. Compact & Justified Organization & Role Details
          _buildCompactJustifiedDossier(borderColor, isDark),
          const SizedBox(height: 14),

          // 3. App Appearance & Theme Mode (System / Light / Dark)
          _buildThemeSelector(borderColor, isDark),
          const SizedBox(height: 14),

          // 4. User Level Authorization Matrix
          _buildRolePermissionsCard(borderColor, isDark),
          const SizedBox(height: 14),

          // 5. Accessibility & Reading Controls
          _buildAccessibilitySection(borderColor, isDark),
          const SizedBox(height: 14),

          // 6. Account Security Actions (Password reset & Privacy Shield)
          _buildSecurityCard(borderColor, isDark),
          const SizedBox(height: 14),

          // 7. App Version & In-App Auto-Update Card
          _buildAppUpdateCard(borderColor, isDark),
          const SizedBox(height: 20),

          // 8. Sign Out Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _handleLogout,
              icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 18),
              label: const Text(
                'Sign Out from Textora',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent, width: 1.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Platform & Server Connectivity Footer
          Center(
            child: Text(
              'Textora Dialer $_appVersion • crm.textorasms.com',
              style: TextStyle(
                color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    ),
  );
}

  /// Compact User Header with Profile Photo & Camera badge
  Widget _buildUserHeaderCard(Color borderColor, bool isDark) {
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Row(
        children: [
          _buildAvatarImage(30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentUser.fullName,
                  style: TextStyle(
                    color: titleColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  _currentUser.email,
                  style: TextStyle(color: subColor, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF10B981), width: 0.8),
                  ),
                  child: Text(
                    _currentUser.roleLevelBadge,
                    style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Compact & Justified Organization & Role Details
  Widget _buildCompactJustifiedDossier(Color borderColor, bool isDark) {
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final dividerColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Account Specifications',
            style: TextStyle(color: titleColor, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 14),
          _buildJustifiedRow('Organization', _currentUser.tenantName, icon: Icons.business_rounded, isDark: isDark),
          Divider(color: dividerColor, height: 16),
          _buildJustifiedRow('Designation', _currentUser.roleDisplayName, icon: Icons.badge_outlined, isDark: isDark),
          Divider(color: dividerColor, height: 16),
          _buildJustifiedRow('Service Tier', _currentUser.planTier ?? 'Enterprise Suite', icon: Icons.workspace_premium_rounded, isDark: isDark),
          Divider(color: dividerColor, height: 16),
          _buildJustifiedRow('Contact Phone', _currentUser.phoneNumber?.isNotEmpty == true ? _currentUser.phoneNumber! : 'Not specified', icon: Icons.phone_outlined, isDark: isDark),
          Divider(color: dividerColor, height: 16),
          _buildJustifiedRow('Assigned Language', _formatLanguage(_currentUser.language), icon: Icons.language_rounded, isDark: isDark),
          Divider(color: dividerColor, height: 16),
          _buildJustifiedRow('System Status', 'Active & Synchronized', icon: Icons.check_circle_outline_rounded, valueColor: const Color(0xFF10B981), isDark: isDark),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.5) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Profile details can only be updated via the web app (crm.textorasms.com). Updates sync here automatically in real time.',
                    style: TextStyle(
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJustifiedRow(String label, String value, {IconData? icon, Color? valueColor, required bool isDark}) {
    final subColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final valColor = valueColor ?? (isDark ? Colors.white : const Color(0xFF0F172A));

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: subColor),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(color: subColor, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: valColor,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// App Theme Mode Selector (System Default / Light / Dark)
  Widget _buildThemeSelector(Color borderColor, bool isDark) {
    final themeService = ThemeService();
    final currentMode = themeService.themeModeNotifier.value;
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.palette_outlined, color: Color(0xFF10B981), size: 18),
              const SizedBox(width: 8),
              Text(
                'App Theme & Appearance',
                style: TextStyle(
                  color: titleColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Choose your preferred visual presentation for day or night operation:',
            style: TextStyle(color: subColor, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildThemeOption(
                label: 'System',
                icon: Icons.brightness_auto_rounded,
                mode: ThemeMode.system,
                isSelected: currentMode == ThemeMode.system,
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _buildThemeOption(
                label: 'Light',
                icon: Icons.light_mode_rounded,
                mode: ThemeMode.light,
                isSelected: currentMode == ThemeMode.light,
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _buildThemeOption(
                label: 'Dark',
                icon: Icons.dark_mode_rounded,
                mode: ThemeMode.dark,
                isSelected: currentMode == ThemeMode.dark,
                isDark: isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption({
    required String label,
    required IconData icon,
    required ThemeMode mode,
    required bool isSelected,
    required bool isDark,
  }) {
    return Expanded(
      child: InkWell(
        onTap: () async {
          await ThemeService().setThemeMode(mode);
          setState(() {});
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF059669)
                : isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF10B981)
                  : isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFCBD5E1),
              width: isSelected ? 1.4 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected
                    ? Colors.white
                    : isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : isDark
                          ? const Color(0xFFCBD5E1)
                          : const Color(0xFF334155),
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Role Permissions & Authorization Info
  Widget _buildRolePermissionsCard(Color borderColor, bool isDark) {
    final isManager = _currentUser.isManagerOrAbove;
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_rounded, color: Color(0xFF10B981), size: 18),
              const SizedBox(width: 8),
              Text(
                'Access Level & Permissions',
                style: TextStyle(color: titleColor, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildPermissionItem('Direct SIM Dialing & Call Duration Capture', true, isDark),
          _buildPermissionItem('Lead Profile Editing & WhatsApp Outreach', true, isDark),
          _buildPermissionItem('Call Disposition Logging & Auto Offline Sync', true, isDark),
          _buildPermissionItem('Team Lead Distribution & Analytics', isManager, isDark),
          _buildPermissionItem('Organization User Administration', _currentUser.role.contains('admin'), isDark),
        ],
      ),
    );
  }

  Widget _buildPermissionItem(String text, bool granted, bool isDark) {
    final grantedColor = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155);
    final disabledColor = isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            granted ? Icons.check_circle_rounded : Icons.cancel_outlined,
            color: granted ? const Color(0xFF10B981) : const Color(0xFF475569),
            size: 15,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: granted ? grantedColor : disabledColor,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Accessibility Controls Section
  Widget _buildAccessibilitySection(Color borderColor, bool isDark) {
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final dividerColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.accessibility_new_rounded, color: Color(0xFF38BDF8), size: 18),
              const SizedBox(width: 8),
              Text(
                'Accessibility & Reading Controls',
                style: TextStyle(color: titleColor, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Font Scale Selector
          Text(
            'Display Text Sizing:',
            style: TextStyle(color: subColor, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildFontScaleChip('Standard (100%)', 1.0, isDark),
              const SizedBox(width: 8),
              _buildFontScaleChip('Large (115%)', 1.15, isDark),
              const SizedBox(width: 8),
              _buildFontScaleChip('XL (130%)', 1.30, isDark),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: dividerColor),

          // High Contrast Switch
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _highContrast,
            onChanged: _toggleHighContrast,
            activeThumbColor: const Color(0xFF10B981),
            title: Text(
              'High Contrast Mode',
              style: TextStyle(color: titleColor, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'Sharpens card borders & text luminance for sunlight use',
              style: TextStyle(color: subColor, fontSize: 11),
            ),
          ),

          // Haptic Feedback Switch
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _hapticFeedback,
            onChanged: _toggleHaptic,
            activeThumbColor: const Color(0xFF10B981),
            title: Text(
              'Sensory Haptic Feedback',
              style: TextStyle(color: titleColor, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'Vibrate lightly on dialing leads and saving call outcomes',
              style: TextStyle(color: subColor, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFontScaleChip(String label, double scale, bool isDark) {
    final isSelected = (_fontScale - scale).abs() < 0.05;
    final unselectedBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final unselectedText = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Expanded(
      child: InkWell(
        onTap: () => _saveFontScale(scale),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF059669) : unselectedBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? const Color(0xFF10B981) : Colors.transparent,
              width: 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : unselectedText,
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  /// Security & Privacy Card
  Widget _buildSecurityCard(Color borderColor, bool isDark) {
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.lock_outline_rounded, color: Color(0xFF10B981), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Security & Authentication',
                    style: TextStyle(color: titleColor, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              TextButton(
                onPressed: _showForgotPasswordDialog,
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                child: const Text(
                  'Reset Password',
                  style: TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Hardware AES-256 KeyStore token storage is active. Direct HTTPS communication with Zero 3rd-Party Tracking.',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );
  }

  /// App Version & In-App Auto-Update Card
  Widget _buildAppUpdateCard(Color borderColor, bool isDark) {
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.system_update_rounded, color: Color(0xFF10B981), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'App Auto-Update',
                      style: TextStyle(color: titleColor, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _appVersion,
                      style: TextStyle(color: subColor, fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: _isCheckingUpdate
                      ? null
                      : () async {
                          setState(() => _isCheckingUpdate = true);
                          await UpdateService().checkAndShowPrompt(context, isManual: true);
                          if (mounted) setState(() => _isCheckingUpdate = false);
                        },
                  icon: _isCheckingUpdate
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(_isCheckingUpdate ? 'Checking...' : 'Check Update', style: const TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'New releases and features are automatically verified and updated in-app from crm.textorasms.com without manual APK downloads.',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );
  }
}
