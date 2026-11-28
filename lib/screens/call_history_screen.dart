import 'package:flutter/material.dart';
import '../models/call_sync_item.dart';
import '../models/lead_item.dart';
import '../models/user_profile.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/telephony_service.dart';
import 'lead_profile_dialog.dart';
import 'phone_log_sync_sheet.dart';

class CallHistoryScreen extends StatefulWidget {
  final UserProfile? user;

  const CallHistoryScreen({super.key, this.user});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  final _storage = StorageService();
  final _api = ApiService();
  final _telephony = TelephonyService();

  List<CallSyncItem> _allCalls = [];
  List<CallSyncItem> _filteredCalls = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  UserProfile? _currentUser;

  // Search & Filter state
  final TextEditingController _searchController = TextEditingController();
  String _selectedDateFilter = 'Today'; // Default to Today
  String _selectedDispositionFilter = 'All';
  DateTime? _customDate;
  final Map<String, String> _sortByTab = {}; // Independent sort per tab
  String get _currentSortBy => _sortByTab[_selectedDispositionFilter] ?? 'newest';
  Map<String, int> _rnrAttemptByKey = {};

  static const List<Map<String, String>> _dispositionFilters = [
    {'id': 'All', 'label': 'All Calls'},
    {'id': 'RNR', 'label': 'RNR'},
    {'id': 'RNR1', 'label': 'RNR 1'},
    {'id': 'RNR2', 'label': 'RNR 2'},
    {'id': 'RNR3', 'label': 'RNR 3'},
    {'id': 'RNR4', 'label': 'RNR 4+'},
    {'id': 'Connected', 'label': 'Connected'},
    {'id': 'Interested', 'label': 'Interested 🔥'},
    {'id': 'Callback', 'label': 'Callback'},
    {'id': 'Demo Scheduled', 'label': 'Demo'},
    {'id': 'Not Interested', 'label': 'Not Interested'},
    {'id': 'Invalid', 'label': 'Invalid'},
  ];

  bool _isRnrDisposition(String disposition) {
    final d = disposition.toLowerCase().trim();
    return d == 'rnr' ||
        d.contains('ringing') ||
        d.contains('no response') ||
        d.contains('no answer');
  }

  String _callIdentityKey(CallSyncItem call) =>
      call.id.isNotEmpty ? call.id : '${call.phoneNumber}_${call.callTimestamp}';

  void _rebuildRnrAttemptMap() {
    final rnrCalls = _allCalls.where((c) => _isRnrDisposition(c.disposition)).toList();
    rnrCalls.sort((a, b) => a.callTimestamp.compareTo(b.callTimestamp));

    final Map<String, int> leadCounter = {};
    final Map<String, int> map = {};
    for (final call in rnrCalls) {
      final key = _callIdentityKey(call);
      if (call.rnrAttempt != null && call.rnrAttempt! > 0) {
        map[key] = call.rnrAttempt!;
        continue;
      }
      final digits = call.phoneNumber.replaceAll(RegExp(r'\D'), '');
      final phoneKey = digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
      final groupKey = (call.leadId != null && call.leadId!.isNotEmpty) ? call.leadId! : phoneKey;
      final nextCount = (leadCounter[groupKey] ?? 0) + 1;
      leadCounter[groupKey] = nextCount;
      map[key] = nextCount;
    }
    _rnrAttemptByKey = map;
  }

  int? _getRnrAttempt(CallSyncItem call) {
    if (!_isRnrDisposition(call.disposition)) return null;
    if (call.rnrAttempt != null && call.rnrAttempt! > 0) return call.rnrAttempt;
    return _rnrAttemptByKey[_callIdentityKey(call)];
  }

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    if (_currentUser == null) {
      _loadCurrentUser();
    }
    _loadHistory();
    _telephony.callCompletedNotifier.addListener(_onExternalCallCompleted);
  }

  void _onExternalCallCompleted() {
    if (mounted) _loadHistory();
  }

  @override
  void dispose() {
    _telephony.callCompletedNotifier.removeListener(_onExternalCallCompleted);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    final profile = await _storage.getUserProfile();
    if (mounted && profile != null) {
      setState(() => _currentUser = profile);
    }
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);

    // 1. Load local offline queue and history
    final localList = await _storage.getCallHistory();

    // 2. Fetch server call logs in background to merge
    List<CallSyncItem> serverList = [];
    try {
      serverList = await _api.getCallLogs(limit: 150);
    } catch (_) {}

    // 3. Merge server-authoritative logs first, then keep ONLY unsynced local calls or non-duplicate local items
    String suffixOf(String raw) {
      final digits = raw.replaceAll(RegExp(r'\D'), '');
      return digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
    }

    int parseEpoch(String iso) {
      try {
        return DateTime.parse(iso).toUtc().millisecondsSinceEpoch;
      } catch (_) {
        return 0;
      }
    }

    final Map<String, CallSyncItem> callMap = {};
    for (var call in serverList) {
      final key = call.id.isNotEmpty ? call.id : '${call.phoneNumber}_${call.callTimestamp}';
      callMap[key] = call;
    }

    for (var localCall in localList) {
      final key = localCall.id.isNotEmpty ? localCall.id : '${localCall.phoneNumber}_${localCall.callTimestamp}';
      if (callMap.containsKey(key)) continue;

      final lSuffix = suffixOf(localCall.phoneNumber);
      final lTs = parseEpoch(localCall.callTimestamp);

      // Skip local placeholder/synced items that already exist in serverList within 5 minutes
      final alreadyOnServer = serverList.any((s) {
        if (suffixOf(s.phoneNumber) != lSuffix) return false;
        final sTs = parseEpoch(s.callTimestamp);
        final timeDiffMs = (sTs - lTs).abs();
        final durMatch = (s.durationSeconds - localCall.durationSeconds).abs() <= 5;
        return timeDiffMs <= 5 * 60 * 1000 && (durMatch || localCall.isSynced);
      });

      if (!alreadyOnServer && (!localCall.isSynced || serverList.isEmpty)) {
        callMap[key] = localCall;
      }
    }

    final merged = callMap.values.toList();

    if (mounted) {
      setState(() {
        _allCalls = merged;
        _rebuildRnrAttemptMap();
        _applyFiltersAndSort();
        _isLoading = false;
      });
    }
  }

  Future<void> _syncPending() async {
    setState(() => _isSyncing = true);
    final count = await _api.flushOfflineQueue();
    await _loadHistory();
    if (mounted) {
      setState(() => _isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully synced $count pending calls to CRM'),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _applyFiltersAndSort() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final sevenDaysAgo = today.subtract(const Duration(days: 7));

    final searchLower = _searchController.text.trim().toLowerCase();

    List<CallSyncItem> result = _allCalls.where((call) {
      DateTime? callDate;
      try {
        callDate = DateTime.parse(call.callTimestamp).toLocal();
      } catch (_) {
        callDate = null;
      }

      // Date filtering
      if (callDate != null) {
        final callDay = DateTime(callDate.year, callDate.month, callDate.day);
        if (_selectedDateFilter == 'Today' && !callDay.isAtSameMomentAs(today)) {
          return false;
        } else if (_selectedDateFilter == 'Yesterday' && !callDay.isAtSameMomentAs(yesterday)) {
          return false;
        } else if (_selectedDateFilter == '7Days' && callDate.isBefore(sevenDaysAgo)) {
          return false;
        } else if (_selectedDateFilter == 'Custom' && _customDate != null) {
          final customDay = DateTime(_customDate!.year, _customDate!.month, _customDate!.day);
          if (!callDay.isAtSameMomentAs(customDay)) {
            return false;
          }
        }
      }

      // Search keyword filtering
      if (searchLower.isNotEmpty) {
        final phone = call.phoneNumber.toLowerCase();
        final remark = (call.remark ?? '').toLowerCase();
        final contact = (call.leadContactName ?? '').toLowerCase();
        final company = (call.leadCompanyName ?? '').toLowerCase();
        final disposition = call.disposition.toLowerCase();

        final matches = phone.contains(searchLower) ||
            remark.contains(searchLower) ||
            contact.contains(searchLower) ||
            company.contains(searchLower) ||
            disposition.contains(searchLower);

        if (!matches) return false;
      }

      // Disposition & RNR1..4 filtering
      if (_selectedDispositionFilter != 'All') {
        final dispLower = call.disposition.toLowerCase().trim();
        final isRnr = _isRnrDisposition(call.disposition);
        final attempt = _getRnrAttempt(call);
        switch (_selectedDispositionFilter) {
          case 'RNR':
            if (!isRnr) return false;
            break;
          case 'RNR1':
            if (!isRnr || attempt != 1) return false;
            break;
          case 'RNR2':
            if (!isRnr || attempt != 2) return false;
            break;
          case 'RNR3':
            if (!isRnr || attempt != 3) return false;
            break;
          case 'RNR4':
            if (!isRnr || attempt == null || attempt < 4) return false;
            break;
          case 'Connected':
            if (isRnr || dispLower == 'invalid') return false;
            if (call.durationSeconds <= 0 &&
                !dispLower.contains('connected') &&
                !dispLower.contains('interested') &&
                !dispLower.contains('callback') &&
                !dispLower.contains('demo')) {
              return false;
            }
            break;
          case 'Interested':
            if (!call.isInterested &&
                dispLower != 'interested' &&
                !dispLower.contains('callback') &&
                !dispLower.contains('demo') &&
                !dispLower.contains('future')) {
              return false;
            }
            break;
          case 'Callback':
            if (!dispLower.contains('callback')) return false;
            break;
          case 'Demo Scheduled':
            if (!dispLower.contains('demo')) return false;
            break;
          case 'Not Interested':
            if (!dispLower.contains('not interested')) return false;
            break;
          case 'Invalid':
            if (!dispLower.contains('invalid')) return false;
            break;
        }
      }

      return true;
    }).toList();

    // Sort order
    result.sort((a, b) {
      switch (_currentSortBy) {
        case 'oldest':
          return a.callTimestamp.compareTo(b.callTimestamp);
        case 'duration_desc':
          return b.durationSeconds.compareTo(a.durationSeconds);
        case 'duration_asc':
          return a.durationSeconds.compareTo(b.durationSeconds);
        case 'newest':
        default:
          return b.callTimestamp.compareTo(a.callTimestamp);
      }
    });

    _filteredCalls = result;
  }

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _customDate ?? now,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 1)),
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? const ColorScheme.dark(
                    primary: Color(0xFF10B981),
                    onPrimary: Colors.white,
                    surface: Color(0xFF1E293B),
                    onSurface: Colors.white,
                  )
                : const ColorScheme.light(
                    primary: Color(0xFF10B981),
                    onPrimary: Colors.white,
                    surface: Colors.white,
                    onSurface: Color(0xFF0F172A),
                  ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _customDate = picked;
        _selectedDateFilter = 'Custom';
        _applyFiltersAndSort();
      });
    }
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String _formatCallTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');

      if (isToday) {
        return '$h:$m';
      } else {
        final day = dt.day.toString().padLeft(2, '0');
        final monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        final mon = monthNames[dt.month - 1];
        return '$day $mon, $h:$m';
      }
    } catch (_) {
      return isoString.length > 16 ? isoString.substring(11, 16) : '';
    }
  }

  Future<void> _openLeadDetails(CallSyncItem call) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF10B981)),
      ),
    );

    LeadItem? foundLead;

    try {
      // 1. Try finding by leadId if present
      if (call.leadId != null && call.leadId!.isNotEmpty) {
        final leadMap = await _api.getLeadDetails(call.leadId!);
        if (leadMap.isNotEmpty) {
          foundLead = LeadItem.fromJson(leadMap);
        }
      }

      // 2. Fallback to searching CRM leads by phone number
      if (foundLead == null) {
        final cleanPhone = call.phoneNumber.replaceAll(RegExp(r'\D'), '');
        final suffix = cleanPhone.length >= 10 ? cleanPhone.substring(cleanPhone.length - 10) : cleanPhone;
        final list = await _api.getLeads(search: suffix);
        if (list.isNotEmpty) {
          foundLead = list.first;
        }
      }
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss loading dialog

    if (foundLead != null) {
      // Open Full Lead Dossier
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => LeadProfileDialog(
          lead: foundLead!,
          user: _currentUser,
          onLeadUpdated: (updated) {
            _loadHistory();
          },
        ),
      );
    } else {
      // If no CRM lead dossier exists yet, show quick call details modal with actions
      _showUnassignedCallSheet(call);
    }
  }

  void _showUnassignedCallSheet(CallSyncItem call) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: call.durationSeconds > 0
                        ? const Color(0xFF059669).withValues(alpha: 0.15)
                        : Colors.amber.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    call.durationSeconds > 0 ? Icons.call_made : Icons.phone_missed,
                    color: call.durationSeconds > 0 ? const Color(0xFF10B981) : Colors.amber,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        call.phoneNumber,
                        style: TextStyle(
                          color: titleColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Text(
                        '${call.disposition} • Talk Time: ${_formatDuration(call.durationSeconds)}',
                        style: TextStyle(color: subColor, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (call.remark != null && call.remark!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Notes: ${call.remark}',
                  style: TextStyle(color: titleColor, fontSize: 13, fontStyle: FontStyle.italic),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _telephony.makeCall(rawPhone: call.phoneNumber, leadId: call.leadId);
                    },
                    icon: const Icon(Icons.phone, size: 16, color: Colors.white),
                    label: const Text('Call SIM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF10B981),
                      side: const BorderSide(color: Color(0xFF10B981)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      final pitch = TelephonyService.buildWAPitch(
                        repName: _currentUser?.fullName,
                        repEmail: _currentUser?.email,
                        repPhone: _currentUser?.phoneNumber,
                      );
                      _telephony.openWhatsApp(rawPhone: call.phoneNumber, message: pitch);
                    },
                    icon: const Icon(Icons.chat, size: 16, color: Color(0xFF10B981)),
                    label: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _allCalls.where((c) => !c.isSynced).length;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC);
    final appBarBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final borderColor = isDark ? const Color(0xFF334155).withValues(alpha: 0.4) : const Color(0xFFE2E8F0);
    final chipBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);

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
          'Mobile Call Logs & Sync',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: titleColor),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.manage_search_rounded, color: Color(0xFF10B981)),
            tooltip: 'Scan Phone Dialer Logs (7 Days)',
            onPressed: () {
              PhoneLogSyncSheet.show(
                context,
                onSynced: () {
                  if (mounted) _loadHistory();
                },
              );
            },
          ),
          if (pendingCount > 0)
            TextButton.icon(
              onPressed: _isSyncing ? null : _syncPending,
              icon: _isSyncing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                    )
                  : const Icon(Icons.sync, size: 16, color: Color(0xFF10B981)),
              label: Text(
                'Sync ($pendingCount)',
                style: const TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold),
              ),
            )
          else
            IconButton(
              icon: Icon(Icons.refresh, color: isDark ? Colors.white70 : const Color(0xFF475569)),
              onPressed: _loadHistory,
            ),
        ],
      ),
      body: Column(
        children: [
          // Search & Date Filter Bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            color: appBarBg,
            child: Column(
              children: [
                // Search Input
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(_applyFiltersAndSort),
                  style: TextStyle(color: titleColor, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search by phone, name, notes...',
                    hintStyle: TextStyle(color: subColor, fontSize: 13),
                    prefixIcon: Icon(Icons.search, size: 18, color: subColor),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(_applyFiltersAndSort);
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Date Filters & Sort Row
                Row(
                  children: [
                    // Horizontal scrollable date filters
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip('All Time', 'All', isDark, chipBg),
                            const SizedBox(width: 6),
                            _buildFilterChip('Today', 'Today', isDark, chipBg),
                            const SizedBox(width: 6),
                            _buildFilterChip('Yesterday', 'Yesterday', isDark, chipBg),
                            const SizedBox(width: 6),
                            _buildFilterChip('Last 7 Days', '7Days', isDark, chipBg),
                            const SizedBox(width: 6),
                            _buildCustomDateChip(isDark, chipBg),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Sort By Dropdown Button
                    PopupMenuButton<String>(
                      key: ValueKey('calls_sort_$_selectedDispositionFilter'),
                      initialValue: _currentSortBy,
                      tooltip: 'Sort calls',
                      onSelected: (val) {
                        setState(() {
                          _sortByTab[_selectedDispositionFilter] = val;
                          _applyFiltersAndSort();
                        });
                      },
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.sort, size: 16, color: Color(0xFF10B981)),
                            const SizedBox(width: 4),
                            Text(
                              _getSortLabel(_currentSortBy),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: titleColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          value: 'newest',
                          child: Text('Newest First', style: TextStyle(fontSize: 12)),
                        ),
                        const PopupMenuItem(
                          value: 'oldest',
                          child: Text('Oldest First', style: TextStyle(fontSize: 12)),
                        ),
                        const PopupMenuItem(
                          value: 'duration_desc',
                          child: Text('Longest Duration', style: TextStyle(fontSize: 12)),
                        ),
                        const PopupMenuItem(
                          value: 'duration_asc',
                          child: Text('Shortest Duration', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Disposition & RNR1..4 Filter Row
                SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _dispositionFilters.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, idx) {
                      final f = _dispositionFilters[idx];
                      final id = f['id']!;
                      final isSelected = _selectedDispositionFilter == id;
                      final isRnrChip = id.startsWith('RNR');
                      final activeColor = isRnrChip ? const Color(0xFFD97706) : const Color(0xFF059669);
                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedDispositionFilter = id;
                            _applyFiltersAndSort();
                          });
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? activeColor
                                : (isRnrChip
                                    ? Colors.amber.withValues(alpha: isDark ? 0.14 : 0.12)
                                    : chipBg),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? activeColor
                                  : (isRnrChip
                                      ? Colors.amber.withValues(alpha: 0.45)
                                      : borderColor),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            f['label']!,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : (isRnrChip
                                      ? (isDark ? Colors.amber[300] : Colors.amber[900])
                                      : subColor),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Count indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Showing ${_filteredCalls.length} of ${_allCalls.length} calls',
                  style: TextStyle(color: subColor, fontSize: 11, fontWeight: FontWeight.w500),
                ),
                Text(
                  'Tap any call to open lead details',
                  style: TextStyle(color: const Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

          // Calls List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
                : _filteredCalls.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.history_toggle_off, color: subColor, size: 48),
                              const SizedBox(height: 12),
                              Text(
                                'No calls found matching the filter.',
                                style: TextStyle(color: titleColor, fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Change the date filter or clear your search to view calls.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: subColor, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: _filteredCalls.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final call = _filteredCalls[index];
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _openLeadDetails(call),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: cardBg,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: borderColor),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: call.durationSeconds > 0
                                            ? const Color(0xFF059669).withValues(alpha: 0.15)
                                            : Colors.amber.withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        call.durationSeconds > 0 ? Icons.call_made : Icons.phone_missed,
                                        color: call.durationSeconds > 0 ? const Color(0xFF10B981) : Colors.amber,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  call.leadContactName != null && call.leadContactName!.isNotEmpty
                                                      ? '${call.leadContactName} (${call.phoneNumber})'
                                                      : call.phoneNumber,
                                                  style: TextStyle(
                                                    color: titleColor,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                    fontFamily: call.leadContactName != null ? null : 'monospace',
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Builder(
                                            builder: (_) {
                                              final rnrNum = _getRnrAttempt(call);
                                              final rnrTag = rnrNum != null ? ' • RNR $rnrNum' : '';
                                              return Text(
                                                '${call.isInterested && call.disposition != 'Interested' ? '🔥 Interested • ' : ''}${call.disposition}$rnrTag • Talk Time: ${_formatDuration(call.durationSeconds)}',
                                                style: TextStyle(color: subColor, fontSize: 12),
                                              );
                                            },
                                          ),
                                          if (call.remark != null && call.remark!.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              call.remark!,
                                              style: TextStyle(
                                                color: isDark ? const Color(0xFF64748B) : const Color(0xFF64748B),
                                                fontSize: 11,
                                                fontStyle: FontStyle.italic,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: call.isSynced
                                                ? const Color(0xFF059669).withValues(alpha: 0.2)
                                                : Colors.amber.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            call.isSynced ? 'Synced' : 'Pending',
                                            style: TextStyle(
                                              color: call.isSynced ? const Color(0xFF10B981) : Colors.amber,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _formatCallTime(call.callTimestamp),
                                          style: TextStyle(color: subColor, fontSize: 10),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.chevron_right,
                                      size: 18,
                                      color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, bool isDark, Color chipBg) {
    final isSelected = _selectedDateFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFF10B981),
      backgroundColor: chipBg,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected
              ? const Color(0xFF10B981)
              : (isDark ? const Color(0xFF334155).withValues(alpha: 0.6) : const Color(0xFFCBD5E1)),
        ),
      ),
      onSelected: (_) {
        setState(() {
          _selectedDateFilter = value;
          _applyFiltersAndSort();
        });
      },
    );
  }

  Widget _buildCustomDateChip(bool isDark, Color chipBg) {
    final isSelected = _selectedDateFilter == 'Custom';
    String label = 'Custom Date';
    if (_customDate != null) {
      final d = _customDate!.day.toString().padLeft(2, '0');
      final m = _customDate!.month.toString().padLeft(2, '0');
      label = '$d/$m';
    }

    return ActionChip(
      avatar: Icon(
        Icons.calendar_month,
        size: 14,
        color: isSelected ? Colors.white : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
      ),
      label: Text(label),
      backgroundColor: isSelected ? const Color(0xFF10B981) : chipBg,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected
              ? const Color(0xFF10B981)
              : (isDark ? const Color(0xFF334155).withValues(alpha: 0.6) : const Color(0xFFCBD5E1)),
        ),
      ),
      onPressed: _pickCustomDate,
    );
  }

  String _getSortLabel(String code) {
    switch (code) {
      case 'oldest':
        return 'Oldest';
      case 'duration_desc':
        return 'Longest';
      case 'duration_asc':
        return 'Shortest';
      case 'newest':
      default:
        return 'Newest';
    }
  }
}
