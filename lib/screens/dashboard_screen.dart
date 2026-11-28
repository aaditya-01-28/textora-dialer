import 'dart:async';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/dashboard_stats.dart';
import '../models/user_profile.dart';
import '../services/agenda_reminder_service.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/telephony_service.dart';

class DashboardScreen extends StatefulWidget {
  final UserProfile user;
  final VoidCallback onNavigateToLeads;
  final VoidCallback? onNavigateToAgenda;

  const DashboardScreen({
    super.key,
    required this.user,
    required this.onNavigateToLeads,
    this.onNavigateToAgenda,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _api = ApiService();
  final _storage = StorageService();
  final _telephony = TelephonyService();

  DashboardStats? _stats;
  bool _isLoading = true;
  String? _error;
  String _selectedPeriod = 'today';
  DateTimeRange? _customDateRange;
  String? _selectedUserId;
  List<DashboardTeamMember> _teamMembers = [];
  String _appVersion = 'v1.2.5';
  Timer? _refreshTimer;

  int _unsyncedCallsCount = 0;
  bool _isSyncingOffline = false;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    _checkOfflineCalls();
    _startPushToDialCompanion();
    _loadAppVersion();
    _telephony.callCompletedNotifier.addListener(_onCallCompleted);

    // Real-time automatic background refresh every 15 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        _loadDashboard(silent: true);
        _checkOfflineCalls();
      }
    });
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = 'v${info.version}';
        });
      }
    } catch (_) {}
  }

  void _onCallCompleted() {
    if (mounted) _loadDashboard(silent: true);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _telephony.callCompletedNotifier.removeListener(_onCallCompleted);
    _telephony.stopPushToDialListener();
    super.dispose();
  }

  void _startPushToDialCompanion() {
    _telephony.startPushToDialListener(
      onCallTriggered: (job) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF059669),
              duration: const Duration(seconds: 4),
              content: Row(
                children: [
                  const Icon(Icons.phone_forwarded_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Web CRM Push-to-Dial: Calling ${job['contactName'] ?? job['phoneNumber']}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      },
    );
  }

  Future<void> _checkOfflineCalls() async {
    final history = await _storage.getCallHistory();
    final count = history.where((c) => !c.isSynced).length;
    if (mounted) {
      setState(() => _unsyncedCallsCount = count);
    }
  }

  Future<void> _triggerManualSync() async {
    if (_isSyncingOffline) return;
    setState(() => _isSyncingOffline = true);
    try {
      final synced = await _api.flushOfflineQueue();
      await _checkOfflineCalls();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF059669),
            content: Text(
              synced > 0 ? 'Synced $synced offline calls successfully!' : 'All calls are up-to-date with CRM.',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Failed to sync offline calls. Check network connection.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncingOffline = false);
    }
  }

  String _formatDateParam(DateTime d) {
    final year = d.year.toString().padLeft(4, '0');
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _formatDisplayDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  Future<void> _loadDashboard({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      String? dateFrom;
      String? dateTo;
      if (_selectedPeriod == 'custom' && _customDateRange != null) {
        dateFrom = _formatDateParam(_customDateRange!.start);
        dateTo = _formatDateParam(_customDateRange!.end);
      }

      final stats = await _api.getDashboardStats(
        period: _selectedPeriod,
        dateFrom: dateFrom,
        dateTo: dateTo,
        userId: _selectedUserId,
      );
      await _checkOfflineCalls();
      if (mounted) {
        setState(() {
          _stats = stats;
          if (stats.teamMembers.isNotEmpty) {
            _teamMembers = stats.teamMembers;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() {
          _error = e.toString().replaceAll('Exception:', '').trim();
          _isLoading = false;
        });
      }
    }
  }

  void _onPeriodChanged(String period) {
    if (_selectedPeriod == period) return;
    setState(() => _selectedPeriod = period);
    _loadDashboard();
  }

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final initialRange = _customDateRange ??
        DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now,
        );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: initialRange,
      helpText: 'SELECT DATE RANGE FOR STATS',
      confirmText: 'APPLY',
      cancelText: 'CANCEL',
      builder: (context, child) {
        return Theme(
          data: isDark
              ? ThemeData.dark().copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: Color(0xFF10B981),
                    onPrimary: Colors.white,
                    surface: Color(0xFF0F172A),
                    onSurface: Colors.white,
                  ),
                  dialogTheme: const DialogThemeData(
                    backgroundColor: Color(0xFF0F172A),
                  ),
                )
              : ThemeData.light().copyWith(
                  colorScheme: const ColorScheme.light(
                    primary: Color(0xFF059669),
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Color(0xFF0F172A),
                  ),
                  dialogTheme: const DialogThemeData(
                    backgroundColor: Colors.white,
                  ),
                ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedPeriod = 'custom';
        _customDateRange = picked;
      });
      _loadDashboard();
    }
  }

  String _formatCurrency(num amount) {
    if (amount >= 10000000) {
      return '${(amount / 10000000).toStringAsFixed(2)} Cr';
    } else if (amount >= 100000) {
      return '${(amount / 100000).toStringAsFixed(2)} L';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}k';
    }
    return amount.toStringAsFixed(0);
  }

  String _formatStageLabel(String stage) {
    final s = stage.replaceAll('_', ' ').trim();
    if (s.isEmpty) return 'Stage';
    return s.split(' ').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC);
    final appBarBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final cardBgSubtle = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final cardBorder = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final dividerColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);

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
        title: Row(
          children: [
            Text(
              'Dashboard',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: titleColor,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                _appVersion,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF10B981),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (widget.onNavigateToAgenda != null)
            ValueListenableBuilder<int>(
              valueListenable: AgendaReminderService().pendingCountNotifier,
              builder: (context, pendingCount, _) {
                return IconButton(
                  tooltip: 'Agenda & Reminders',
                  onPressed: widget.onNavigateToAgenda,
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        pendingCount > 0
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_none_rounded,
                        color: pendingCount > 0
                            ? const Color(0xFFF59E0B)
                            : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
                      ),
                      if (pendingCount > 0)
                        Positioned(
                          right: -5,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 14),
                            child: Text(
                              pendingCount > 99 ? '99+' : '$pendingCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                  )
                : Icon(Icons.refresh_rounded, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
            tooltip: 'Refresh Dashboard',
            onPressed: _isLoading ? null : () => _loadDashboard(silent: false),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFF10B981),
        backgroundColor: cardBgSubtle,
        onRefresh: () => _loadDashboard(silent: true),
        child: ListView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          children: [
            // Manager / Admin Level: Team View Selector
            _buildTeamScopeSelector(isDark, cardBg, cardBorder, titleColor, subColor),

            // Offline Sync Banner (If any calls pending)
            if (_unsyncedCallsCount > 0) ...[
              _buildOfflineSyncAlert(),
              const SizedBox(height: 14),
            ],

            // Period Selector Filter (Today / This Week / This Month / Last Month / Custom Date)
            _buildPeriodSelector(isDark, cardBgSubtle, subColor),
            const SizedBox(height: 16),

            if (_isLoading && _stats == null) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: CircularProgressIndicator(color: Color(0xFF10B981)),
                ),
              ),
            ] else if (_error != null && _stats == null) ...[
              _buildErrorCard(titleColor),
            ] else ...[
              // Hero Calling KPI Cards
              _buildCallingKpiGrid(isDark, cardBg, cardBorder, titleColor, subColor),
              const SizedBox(height: 14),

              // Fast Queue Action Button
              _buildFastQueueCta(),
              const SizedBox(height: 18),

              // Pipeline & Deals Snapshot (Real-time Deals & Value)
              _buildPipelineSnapshot(isDark, cardBg, cardBorder, titleColor, subColor, dividerColor),
              const SizedBox(height: 18),

              // Call Dispositions Breakdown Card
              _buildDispositionCard(isDark, cardBg, cardBorder, titleColor, subColor),
              const SizedBox(height: 18),

              // Follow-up Agenda & Tasks for the Period
              _buildAgendaSection(isDark, cardBg, cardBorder, titleColor, subColor, dividerColor),
              const SizedBox(height: 30),
            ],
          ],
        ),
      ),
    );
  }

  /// Manager / Admin Team Scope Filter
  Widget _buildTeamScopeSelector(
    bool isDark,
    Color cardBg,
    Color cardBorder,
    Color titleColor,
    Color subColor,
  ) {
    if (!widget.user.isManagerOrAbove) return const SizedBox.shrink();

    final team = _stats?.teamMembers ?? _teamMembers;
    if (team.isEmpty) return const SizedBox.shrink();

    final selectedMember = _selectedUserId != null
        ? team.firstWhere((m) => m.id == _selectedUserId, orElse: () => team.first)
        : null;

    final scopeLabel = selectedMember != null
        ? selectedMember.fullName
        : 'All Team Members (Company Total)';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder, width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.people_alt_rounded, color: Color(0xFF38BDF8), size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scope: $scopeLabel',
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _selectedUserId == null
                      ? 'Viewing entire organization sales performance'
                      : 'Viewing sales rep individual performance',
                  style: TextStyle(color: subColor, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => _showTeamPickerModal(isDark, team, titleColor, subColor),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(color: const Color(0xFF38BDF8).withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Change',
                  style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
                SizedBox(width: 3),
                Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF38BDF8), size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showTeamPickerModal(bool isDark, List<DashboardTeamMember> team, Color titleColor, Color subColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Select Stats View Scope',
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: subColor),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.15),
                  child: const Icon(Icons.business_rounded, color: Color(0xFF10B981)),
                ),
                title: Text(
                  'All Team Members (Company Total)',
                  style: TextStyle(
                    color: titleColor,
                    fontWeight: _selectedUserId == null ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
                subtitle: Text('Aggregated tenant performance', style: TextStyle(color: subColor, fontSize: 11)),
                trailing: _selectedUserId == null
                    ? const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981))
                    : null,
                onTap: () {
                  Navigator.of(ctx).pop();
                  setState(() => _selectedUserId = null);
                  _loadDashboard();
                },
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: team.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final member = team[i];
                    final isSelected = _selectedUserId == member.id;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                        child: Text(
                          member.fullName.isNotEmpty ? member.fullName[0].toUpperCase() : 'U',
                          style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(
                        member.fullName,
                        style: TextStyle(
                          color: titleColor,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        member.role == 'sales_manager' ? 'Sales Manager' : 'Sales Representative',
                        style: TextStyle(color: subColor, fontSize: 11),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981))
                          : null,
                      onTap: () {
                        Navigator.of(ctx).pop();
                        setState(() => _selectedUserId = member.id);
                        _loadDashboard();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Offline Sync Alert
  Widget _buildOfflineSyncAlert() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Colors.amber, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$_unsyncedCallsCount offline call${_unsyncedCallsCount > 1 ? 's' : ''} saved locally',
              style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: _isSyncingOffline ? null : _triggerManualSync,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: _isSyncingOffline
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Text('Sync Now', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  /// Period Selector Tabs (Today / This Week / This Month / Last Month / Custom Date)
  Widget _buildPeriodSelector(bool isDark, Color cardBgSubtle, Color subColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: cardBgSubtle,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPeriodButton('today', 'Today', subColor),
                const SizedBox(width: 3),
                _buildPeriodButton('week', 'This Week', subColor),
                const SizedBox(width: 3),
                _buildPeriodButton('month', 'This Month', subColor),
                const SizedBox(width: 3),
                _buildPeriodButton('last_month', 'Last Month', subColor),
                const SizedBox(width: 3),
                _buildPeriodButton('custom', 'Custom 📅', subColor, isCustom: true),
              ],
            ),
          ),
        ),
        if (_selectedPeriod == 'custom' && _customDateRange != null) ...[
          const SizedBox(height: 10),
          _buildActiveCustomDateBadge(isDark),
        ],
      ],
    );
  }

  Widget _buildActiveCustomDateBadge(bool isDark) {
    final range = _customDateRange!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF059669).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.date_range_rounded, color: Color(0xFF059669), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Custom Range: ${_formatDisplayDate(range.start)} – ${_formatDisplayDate(range.end)}',
              style: const TextStyle(
                color: Color(0xFF059669),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          InkWell(
            onTap: _pickCustomDateRange,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                'Change',
                style: TextStyle(
                  color: Color(0xFF059669),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () {
              setState(() {
                _selectedPeriod = 'today';
                _customDateRange = null;
              });
              _loadDashboard();
            },
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close_rounded, color: Color(0xFF059669), size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodButton(String value, String label, Color subColor, {bool isCustom = false}) {
    final isSelected = _selectedPeriod == value;
    return InkWell(
      onTap: () {
        if (isCustom) {
          _pickCustomDateRange();
        } else {
          _onPeriodChanged(value);
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF059669) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF059669).withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.white : subColor,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }

  /// Hero KPI Cards
  Widget _buildCallingKpiGrid(
    bool isDark,
    Color cardBg,
    Color cardBorder,
    Color titleColor,
    Color subColor,
  ) {
    final stats = _stats!;
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.35,
      children: [
        _buildMetricCard(
          title: 'Total Calls Dialed',
          value: '${stats.totalCalls}',
          subtitle: '${stats.uniqueDials} unique leads',
          icon: Icons.phone_forwarded_rounded,
          iconColor: const Color(0xFF38BDF8),
          isDark: isDark,
          cardBg: cardBg,
          cardBorder: cardBorder,
          titleColor: titleColor,
          subColor: subColor,
        ),
        _buildMetricCard(
          title: 'Connected Calls',
          value: '${stats.connectedCalls}',
          subtitle: '${stats.connectRate}% connect rate',
          icon: Icons.phone_in_talk_rounded,
          iconColor: const Color(0xFF10B981),
          isDark: isDark,
          cardBg: cardBg,
          cardBorder: cardBorder,
          titleColor: titleColor,
          subColor: subColor,
        ),
        _buildMetricCard(
          title: 'Total Talk Time',
          value: stats.displayTalkTime,
          subtitle: stats.totalDurationSeconds >= 3600 || stats.talkTimeMins >= 60
              ? '${(stats.totalDurationSeconds > 0 ? (stats.totalDurationSeconds / 3600).toStringAsFixed(1) : (stats.talkTimeMins / 60).toStringAsFixed(1))} hours'
              : 'Direct SIM talk time',
          icon: Icons.access_time_filled_rounded,
          iconColor: const Color(0xFFA855F7),
          isDark: isDark,
          cardBg: cardBg,
          cardBorder: cardBorder,
          titleColor: titleColor,
          subColor: subColor,
        ),
        _buildMetricCard(
          title: 'Queue Remaining',
          value: '${stats.queueRemainingCount}',
          subtitle: widget.user.isManagerOrAbove && _selectedUserId == null
              ? 'Company pending'
              : 'Assigned to call',
          icon: Icons.queue_play_next_rounded,
          iconColor: const Color(0xFFF59E0B),
          isDark: isDark,
          cardBg: cardBg,
          cardBorder: cardBorder,
          titleColor: titleColor,
          subColor: subColor,
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool isDark,
    required Color cardBg,
    required Color cardBorder,
    required Color titleColor,
    required Color subColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    color: subColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icon, color: iconColor, size: 20),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              color: titleColor,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              color: iconColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Fast Action CTA to Jump into Queue
  Widget _buildFastQueueCta() {
    return ElevatedButton.icon(
      onPressed: widget.onNavigateToLeads,
      icon: const Icon(Icons.play_arrow_rounded, size: 24),
      label: const Text(
        'Open Leads Queue & Start Calling',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF059669),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),
    );
  }

  /// Real-Time Pipeline & Deals Snapshot
  Widget _buildPipelineSnapshot(
    bool isDark,
    Color cardBg,
    Color cardBorder,
    Color titleColor,
    Color subColor,
    Color dividerColor,
  ) {
    final stats = _stats!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.monetization_on_rounded, color: Color(0xFF10B981), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Deals & Pipeline Status',
                    style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${stats.winRate}% Win Rate',
                  style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 4-Quadrant Deal Stats Grid
          Row(
            children: [
              Expanded(
                child: _buildSubStat(
                  'Active Deals',
                  '${stats.activeDealsCount}',
                  const Color(0xFF38BDF8),
                  subColor,
                ),
              ),
              Container(width: 1, height: 42, color: dividerColor),
              Expanded(
                child: _buildSubStat(
                  'Active Pipeline',
                  '₹${_formatCurrency(stats.activePipelineValue)}',
                  const Color(0xFF818CF8),
                  subColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: dividerColor, height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSubStat(
                  'Deals Won',
                  '${stats.wonDealsCount}',
                  const Color(0xFF10B981),
                  subColor,
                ),
              ),
              Container(width: 1, height: 42, color: dividerColor),
              Expanded(
                child: _buildSubStat(
                  'Won Revenue',
                  '₹${_formatCurrency(stats.wonRevenueInPeriod)}',
                  const Color(0xFFF59E0B),
                  subColor,
                ),
              ),
            ],
          ),

          // Pipeline Stages Breakdown (If available)
          if (stats.allDealsByStage.isNotEmpty) ...[
            const SizedBox(height: 16),
            Divider(color: dividerColor, height: 1),
            const SizedBox(height: 12),
            Text(
              'Pipeline Stages Breakdown',
              style: TextStyle(
                color: titleColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            for (var stage in stats.allDealsByStage) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatStageLabel(stage.stage),
                          style: TextStyle(color: titleColor, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${stage.count}',
                            style: const TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '₹${_formatCurrency(stage.value)}',
                      style: TextStyle(color: subColor, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSubStat(String label, String value, Color color, Color subColor) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: subColor, fontSize: 11),
        ),
      ],
    );
  }

  /// Call Disposition Distribution
  Widget _buildDispositionCard(
    bool isDark,
    Color cardBg,
    Color cardBorder,
    Color titleColor,
    Color subColor,
  ) {
    final stats = _stats!;
    final total = stats.totalCalls;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Call Dispositions Breakdown',
                style: TextStyle(
                  color: titleColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                '$total logged calls',
                style: TextStyle(color: subColor, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (total == 0) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No calls recorded in this period yet.\nDial leads from the queue to populate stats.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: subColor, fontSize: 12, height: 1.5),
                ),
              ),
            ),
          ] else ...[
            _buildDispositionRow('Connected', stats.dispositionMap['Connected'] ?? 0, total, const Color(0xFF10B981), isDark, titleColor, subColor),
            _buildDispositionRow('Demo Scheduled', stats.dispositionMap['Demo Scheduled'] ?? 0, total, const Color(0xFF38BDF8), isDark, titleColor, subColor),
            _buildDispositionRow('Callback', stats.dispositionMap['Callback'] ?? 0, total, const Color(0xFFF59E0B), isDark, titleColor, subColor),
            _buildDispositionRow('RNR (Ring No Response)', stats.dispositionMap['RNR'] ?? 0, total, const Color(0xFFEF4444), isDark, titleColor, subColor),
            _buildDispositionRow('Not Interested', stats.dispositionMap['Not Interested'] ?? 0, total, const Color(0xFF64748B), isDark, titleColor, subColor),
          ],
        ],
      ),
    );
  }

  Widget _buildDispositionRow(
    String label,
    int count,
    int total,
    Color color,
    bool isDark,
    Color titleColor,
    Color subColor,
  ) {
    final pct = total > 0 ? (count / total) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(color: subColor, fontSize: 12)),
              Text(
                '$count (${(pct * 100).toStringAsFixed(0)}%)',
                style: TextStyle(color: titleColor, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  /// Today's Agenda / Scheduled Callbacks & Demos
  Widget _buildAgendaSection(
    bool isDark,
    Color cardBg,
    Color cardBorder,
    Color titleColor,
    Color subColor,
    Color dividerColor,
  ) {
    final stats = _stats!;
    final agenda = stats.todayAgenda;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.event_note_rounded, color: Color(0xFF10B981), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    "Agenda & Scheduled Actions",
                    style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              if (stats.overdueTasksCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.redAccent, width: 0.8),
                  ),
                  child: Text(
                    '${stats.overdueTasksCount} overdue',
                    style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (agenda.isEmpty) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'No pending callbacks or demos scheduled for this period.',
                  style: TextStyle(color: subColor, fontSize: 12),
                ),
              ),
            ),
          ] else ...[
            for (var item in agenda) ...[
              _buildAgendaItemTile(item, titleColor, subColor),
              if (item != agenda.last) Divider(color: dividerColor, height: 16),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildAgendaItemTile(AgendaItem item, Color titleColor, Color subColor) {
    final isDemo = item.taskType.toLowerCase().contains('demo');
    final isCompleted = item.status.toLowerCase() == 'completed';
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isCompleted
                ? const Color(0xFF10B981).withValues(alpha: 0.15)
                : isDemo
                ? const Color(0xFF38BDF8).withValues(alpha: 0.15)
                : const Color(0xFFF59E0B).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isCompleted
                ? Icons.check_circle_rounded
                : isDemo
                ? Icons.video_call_rounded
                : Icons.phone_callback_rounded,
            color: isCompleted
                ? const Color(0xFF10B981)
                : isDemo
                ? const Color(0xFF38BDF8)
                : const Color(0xFFF59E0B),
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      item.contactName ?? item.companyName ?? 'Lead Follow-up',
                      style: TextStyle(color: titleColor, fontWeight: FontWeight.bold, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isCompleted) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Demo Done',
                        style: TextStyle(color: Color(0xFF10B981), fontSize: 9.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                item.phoneNumber ?? item.notes ?? 'Scheduled action',
                style: TextStyle(color: subColor, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          () {
            if (item.scheduledTime.isEmpty) return 'Pending';
            final parsed = DateTime.tryParse(item.scheduledTime)?.toLocal();
            if (parsed != null) {
              final h = parsed.hour % 12 == 0 ? 12 : parsed.hour % 12;
              final m = parsed.minute.toString().padLeft(2, '0');
              final ampm = parsed.hour >= 12 ? 'PM' : 'AM';
              return '$h:$m $ampm';
            }
            return item.scheduledTime.length >= 16
                ? item.scheduledTime.substring(11, 16)
                : item.taskType;
          }(),
          style: TextStyle(
            color: isCompleted ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorCard(Color titleColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.amber, size: 48),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Failed to load dashboard data',
              textAlign: TextAlign.center,
              style: TextStyle(color: titleColor, fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadDashboard(silent: false),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
