import 'dart:async';
import 'package:flutter/material.dart';
import '../models/dashboard_stats.dart';
import '../models/user_profile.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/telephony_service.dart';

class DashboardScreen extends StatefulWidget {
  final UserProfile user;
  final VoidCallback onNavigateToLeads;

  const DashboardScreen({
    super.key,
    required this.user,
    required this.onNavigateToLeads,
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
  int _unsyncedCallsCount = 0;
  bool _isSyncingOffline = false;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    _checkOfflineCalls();
    _startPushToDialCompanion();
  }

  @override
  void dispose() {
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

  Future<void> _loadDashboard({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final stats = await _api.getDashboardStats(period: _selectedPeriod);
      await _checkOfflineCalls();
      if (mounted) {
        setState(() {
          _stats = stats;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(11.0),
          child: Image.asset(
            'assets/images/icon.png',
            fit: BoxFit.contain,
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.user.tenantName,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF10B981),
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const Text(
              'Sales Performance Dashboard',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                  )
                : const Icon(Icons.refresh_rounded, color: Color(0xFF94A3B8)),
            tooltip: 'Refresh Dashboard',
            onPressed: _isLoading ? null : () => _loadDashboard(silent: false),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFF10B981),
        backgroundColor: const Color(0xFF1E293B),
        onRefresh: () => _loadDashboard(silent: true),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            // User Role Level Banner (Accessibility & Status)
            _buildUserLevelCard(),
            const SizedBox(height: 14),

            // Offline Sync Banner (If any calls pending)
            if (_unsyncedCallsCount > 0) ...[
              _buildOfflineSyncAlert(),
              const SizedBox(height: 14),
            ],

            // Period Selector Filter (High Contrast, Accessible Pills)
            _buildPeriodSelector(),
            const SizedBox(height: 16),

            if (_isLoading && _stats == null) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: CircularProgressIndicator(color: Color(0xFF10B981)),
                ),
              ),
            ] else if (_error != null && _stats == null) ...[
              _buildErrorCard(),
            ] else ...[
              // Hero Calling KPI Cards
              _buildCallingKpiGrid(),
              const SizedBox(height: 14),

              // Fast Queue Action Button
              _buildFastQueueCta(),
              const SizedBox(height: 18),

              // Call Dispositions Breakdown Card
              _buildDispositionCard(),
              const SizedBox(height: 18),

              // Today's Follow-up Agenda & Tasks
              _buildAgendaSection(),
              const SizedBox(height: 18),

              // Pipeline Snapshot (Role-aware)
              _buildPipelineSnapshot(),
              const SizedBox(height: 30),
            ],
          ],
        ),
      ),
    );
  }

  /// User Access Level & Status Card
  Widget _buildUserLevelCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: const Color(0xFF059669),
            child: Text(
              widget.user.fullName.isNotEmpty ? widget.user.fullName[0].toUpperCase() : 'U',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.user.fullName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF10B981), width: 0.8),
                      ),
                      child: Text(
                        widget.user.roleLevelBadge,
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.user.roleDisplayName,
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3), width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Text(
                            'Web CRM Linked • Push-to-Dial Active',
                            style: TextStyle(
                              color: Color(0xFF34D399),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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

  /// Period Selector Tabs
  Widget _buildPeriodSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildPeriodButton('today', 'Today'),
          _buildPeriodButton('week', 'This Week'),
          _buildPeriodButton('month', 'This Month'),
        ],
      ),
    );
  }

  Widget _buildPeriodButton(String value, String label) {
    final isSelected = _selectedPeriod == value;
    return Expanded(
      child: InkWell(
        onTap: () => _onPeriodChanged(value),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF059669) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFF94A3B8),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  /// Hero KPI Cards
  Widget _buildCallingKpiGrid() {
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
        ),
        _buildMetricCard(
          title: 'Connected Calls',
          value: '${stats.connectedCalls}',
          subtitle: '${stats.connectRate}% connect rate',
          icon: Icons.phone_in_talk_rounded,
          iconColor: const Color(0xFF10B981),
        ),
        _buildMetricCard(
          title: 'Total Talk Time',
          value: '${stats.talkTimeMins}m',
          subtitle: stats.talkTimeMins >= 60
              ? '${(stats.talkTimeMins / 60).toStringAsFixed(1)} hours'
              : 'Direct SIM talk time',
          icon: Icons.access_time_filled_rounded,
          iconColor: const Color(0xFFA855F7),
        ),
        _buildMetricCard(
          title: 'Queue Remaining',
          value: '${stats.queueRemainingCount}',
          subtitle: 'Assigned to call',
          icon: Icons.queue_play_next_rounded,
          iconColor: const Color(0xFFF59E0B),
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
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E293B), width: 1.2),
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
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
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
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              color: iconColor.withValues(alpha: 0.9),
              fontSize: 11,
              fontWeight: FontWeight.w500,
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

  /// Call Disposition Distribution
  Widget _buildDispositionCard() {
    final stats = _stats!;
    final total = stats.totalCalls;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Call Dispositions Breakdown',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                '$total logged calls',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (total == 0) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No calls recorded in this period yet.\nDial leads from the queue to populate stats.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12, height: 1.5),
                ),
              ),
            ),
          ] else ...[
            _buildDispositionRow('Connected', stats.dispositionMap['Connected'] ?? 0, total, const Color(0xFF10B981)),
            _buildDispositionRow('Demo Scheduled', stats.dispositionMap['Demo Scheduled'] ?? 0, total, const Color(0xFF38BDF8)),
            _buildDispositionRow('Callback', stats.dispositionMap['Callback'] ?? 0, total, const Color(0xFFF59E0B)),
            _buildDispositionRow('RNR (Ring No Response)', stats.dispositionMap['RNR'] ?? 0, total, const Color(0xFFEF4444)),
            _buildDispositionRow('Not Interested', stats.dispositionMap['Not Interested'] ?? 0, total, const Color(0xFF64748B)),
          ],
        ],
      ),
    );
  }

  Widget _buildDispositionRow(String label, int count, int total, Color color) {
    final pct = total > 0 ? (count / total) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12)),
              Text(
                '$count (${(pct * 100).toStringAsFixed(0)}%)',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              backgroundColor: const Color(0xFF1E293B),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  /// Today's Agenda / Scheduled Callbacks & Demos
  Widget _buildAgendaSection() {
    final stats = _stats!;
    final agenda = stats.todayAgenda;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B), width: 1.2),
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
                  const Text(
                    "Today's Agenda & Action Items",
                    style: TextStyle(
                      color: Colors.white,
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
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'No pending callbacks or demos scheduled for this period.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                ),
              ),
            ),
          ] else ...[
            for (var item in agenda) ...[
              _buildAgendaItemTile(item),
              if (item != agenda.last) const Divider(color: Color(0xFF1E293B), height: 16),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildAgendaItemTile(AgendaItem item) {
    final isDemo = item.taskType.toLowerCase().contains('demo');
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDemo ? const Color(0xFF38BDF8).withValues(alpha: 0.15) : const Color(0xFFF59E0B).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isDemo ? Icons.video_call_rounded : Icons.phone_callback_rounded,
            color: isDemo ? const Color(0xFF38BDF8) : const Color(0xFFF59E0B),
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.contactName ?? item.companyName ?? 'Lead Follow-up',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                item.phoneNumber ?? item.notes ?? 'Scheduled action',
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
              ),
            ],
          ),
        ),
        Text(
          item.scheduledTime.length >= 16 ? item.scheduledTime.substring(11, 16) : item.taskType,
          style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ],
    );
  }

  /// Pipeline & Revenue Snapshot
  Widget _buildPipelineSnapshot() {
    final stats = _stats!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Deals & Pipeline Status',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
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
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildSubStat('Active Deals', '${stats.activeDealsCount}', const Color(0xFF38BDF8)),
              ),
              Container(width: 1, height: 40, color: const Color(0xFF1E293B)),
              Expanded(
                child: _buildSubStat('Deals Won', '${stats.wonDealsCount}', const Color(0xFF10B981)),
              ),
              Container(width: 1, height: 40, color: const Color(0xFF1E293B)),
              Expanded(
                child: _buildSubStat(
                  'Won Revenue',
                  '₹${stats.wonRevenueInPeriod.toStringAsFixed(0)}',
                  const Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildErrorCard() {
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
              style: const TextStyle(color: Colors.white, fontSize: 14),
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
