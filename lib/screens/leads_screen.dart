import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/call_sync_item.dart';
import '../models/lead_item.dart';
import '../models/user_profile.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/telephony_service.dart';
import 'post_call_dialog.dart';
import 'lead_profile_dialog.dart';

class LeadsScreen extends StatefulWidget {
  final UserProfile user;

  const LeadsScreen({super.key, required this.user});

  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> with WidgetsBindingObserver {
  final _api = ApiService();
  final _telephony = TelephonyService();
  final _searchController = TextEditingController();

  List<LeadItem> _leads = [];
  bool _isLoading = true;
  String? _error;
  LeadItem? _callingLead;
  Timer? _autoSyncTimer;
  bool _isCheckingCall = false;
  bool _isPostCallDialogOpen = false;

  String _selectedFilter = 'all';

  static const List<Map<String, String>> _defaultFilters = [
    {'id': 'all', 'label': 'All'},
    {'id': 'new', 'label': 'New'},
    {'id': 'interested', 'label': 'Interested 🔥'},
    {'id': 'connected', 'label': 'Connected'},
    {'id': 'callback', 'label': 'Callbacks'},
    {'id': 'demos', 'label': 'Demos'},
    {'id': 'deal', 'label': 'In Deal'},
    {'id': 'rnr', 'label': 'RNR'},
    {'id': 'already_using', 'label': 'Already Using'},
    {'id': 'future_requirement', 'label': 'Future Req'},
    {'id': 'already_purchased', 'label': 'Purchased Other'},
    {'id': 'not_interested', 'label': 'Not Interested'},
    {'id': 'won', 'label': 'Won 🏆'},
    {'id': 'lost', 'label': 'Lost'},
    {'id': 'other', 'label': 'Other'},
  ];

  late List<Map<String, String>> _statusFilters = List.from(_defaultFilters);

  bool _isLeadMatchingFilter(LeadItem l, String filterId) {
    if (filterId == 'all') return true;
    final s = l.status.toLowerCase().trim();
    switch (filterId) {
      case 'new':
        return s == 'new' || s == 'uncontacted';
      case 'interested':
        return s == 'interested' || l.isInterested;
      case 'connected':
        return s == 'connected' || s == 'contacted';
      case 'callback':
        return s.contains('callback');
      case 'demos':
        return s.contains('demo');
      case 'deal':
        return s.contains('deal') || s == 'proposal_sent' || s == 'negotiation';
      case 'rnr':
        return s == 'rnr';
      case 'already_using':
        return s == 'already_using' || s == 'already using';
      case 'future_requirement':
        return s == 'future_requirement' || s == 'future requirement';
      case 'already_purchased':
        return s == 'already_purchased' || s == 'already purchased';
      case 'not_interested':
        return s == 'not_interested' || s == 'not interested';
      case 'won':
        return s == 'won' || s == 'converted';
      case 'lost':
        return s == 'lost' || s == 'junk';
      case 'other':
        return s == 'invalid' ||
            (!['new', 'uncontacted', 'connected', 'contacted', 'rnr', 'won', 'converted', 'lost', 'junk', 'not_interested', 'not interested', 'already_using', 'future_requirement', 'already_purchased'].contains(s) &&
             !s.contains('callback') && !s.contains('demo') && !s.contains('deal'));
      default:
        return s == filterId;
    }
  }

  Future<void> _loadTabOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('leads_tab_order');
      if (saved != null && saved.isNotEmpty) {
        final map = {for (var f in _defaultFilters) f['id']!: f};
        final reordered = <Map<String, String>>[];
        for (var id in saved) {
          if (map.containsKey(id)) {
            reordered.add(map[id]!);
            map.remove(id);
          }
        }
        reordered.addAll(map.values);
        if (mounted) {
          setState(() {
            _statusFilters = reordered;
          });
        }
      }
    } catch (_) {}
  }

  List<LeadItem> get _filteredLeads {
    if (_selectedFilter == 'all') return _leads;
    return _leads.where((l) => _isLeadMatchingFilter(l, _selectedFilter)).toList();
  }

  int _getCountForFilter(String filterId) {
    if (filterId == 'all') return _leads.length;
    return _leads.where((l) => _isLeadMatchingFilter(l, filterId)).length;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadTabOrder();
    _loadLeads();
    _telephony.checkAndRequestPermissions();
    _telephony.clearCallState();
    _api.flushOfflineQueue();

    // Auto-sync leads and offline queue every 15 seconds silently
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _callingLead == null) {
        _loadLeads(silent: true);
        _api.flushOfflineQueue();
      }
    });
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the sales rep returns to the app from the native phone call:
    if (state == AppLifecycleState.resumed) {
      if (_callingLead != null) {
        _checkRecentCall(_callingLead!);
      } else if (_telephony.activeLeadId != null) {
        final activeId = _telephony.activeLeadId;
        final matchedLead = _leads.cast<LeadItem?>().firstWhere(
          (l) => l?.id == activeId,
          orElse: () => null,
        );
        if (matchedLead != null) {
          _checkRecentCall(matchedLead);
        }
      }
    }
  }

  Future<void> _checkRecentCall(LeadItem lead) async {
    if (_isCheckingCall || _isPostCallDialogOpen) return;
    _isCheckingCall = true;
    _callingLead = null;

    // Clear active call state immediately BEFORE waiting so concurrent resumed events never re-trigger
    final targetPhone = lead.phoneNumber;
    await _telephony.clearCallState();

    try {
      // Small delay to let Android finalize the CallLog entry
      await Future.delayed(const Duration(milliseconds: 1200));

      final callRecord = await _telephony.detectLastCallOutcome(
        specificPhone: targetPhone,
      );

      if (!mounted || callRecord == null) {
        return;
      }

      final signature = 'outbound_${callRecord.phoneNumber}_${callRecord.callTimestamp}_${callRecord.durationSeconds}';
      final alreadyProcessed = await StorageService().isCallSignatureProcessed(signature);
      if (alreadyProcessed || !mounted) {
        return;
      }

      // Mark immediately so a second lifecycle trigger cannot open a duplicate sheet
      await StorageService().markCallSignatureProcessed(signature);
      if (!mounted) return;

      _isPostCallDialogOpen = true;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (_) => PostCallDialog(
          lead: lead,
          call: callRecord,
          onSaved: () => _loadLeads(silent: false),
        ),
      );
      _isPostCallDialogOpen = false;
    } finally {
      _isCheckingCall = false;
    }
  }

  Future<void> _loadLeads({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final list = await _api.getLeads(search: _searchController.text);
      if (mounted) {
        setState(() {
          _leads = list;
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

  Future<void> _startCall(LeadItem lead) async {
    setState(() => _callingLead = lead);
    final launched = await _telephony.makeCall(
      rawPhone: lead.phoneNumber,
      leadId: lead.id,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch phone dialer')),
      );
      setState(() => _callingLead = null);
    }
  }

  Future<void> _openWhatsApp(LeadItem lead) async {
    final pitch = TelephonyService.buildWAPitch(
      repName: widget.user.fullName,
      repEmail: widget.user.email,
      repPhone: widget.user.phoneNumber,
      contactName: lead.contactName,
    );
    await _telephony.openWhatsApp(rawPhone: lead.phoneNumber, message: pitch);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC);
    final appBarBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final inputBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final inputBorderColor = isDark ? const Color(0xFF334155).withValues(alpha: 0.6) : const Color(0xFFCBD5E1);
    final hintColor = isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);

    final filtered = _filteredLeads;

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.user.tenantName,
              style: const TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
            ),
            Text(
              'Assigned Calling Queue',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: titleColor),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: isDark ? Colors.white70 : const Color(0xFF475569)),
            onPressed: _loadLeads,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onSubmitted: (_) => _loadLeads(),
              style: TextStyle(color: titleColor, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search leads by phone, company, or name...',
                hintStyle: TextStyle(color: hintColor, fontSize: 12),
                prefixIcon: Icon(Icons.search, color: hintColor, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: hintColor, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _loadLeads();
                        },
                      )
                    : null,
                filled: true,
                fillColor: inputBg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: inputBorderColor, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: inputBorderColor, width: 1),
                ),
              ),
            ),
          ),

          // Horizontal Status Filter Chips Bar
          _buildFilterChips(isDark),

          // Leads Count Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _selectedFilter == 'all'
                      ? '${_leads.length} Leads Available'
                      : '${filtered.length} of ${_leads.length} Leads',
                  style: TextStyle(
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Row(
                  children: [
                    Icon(Icons.sim_card_outlined, color: Color(0xFF10B981), size: 14),
                    SizedBox(width: 4),
                    Text(
                      'SIM Calling Active',
                      style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Main List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF10B981)),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.cloud_off, color: Colors.redAccent, size: 40),
                              const SizedBox(height: 12),
                              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF475569))),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadLeads,
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
                                child: const Text('Try Again'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.filter_list_off_rounded, color: hintColor, size: 44),
                                  const SizedBox(height: 10),
                                  Text(
                                    _selectedFilter == 'all'
                                        ? 'No leads assigned yet in this queue.'
                                        : 'No leads found in "${_statusFilters.firstWhere((f) => f['id'] == _selectedFilter)['label']}" filter.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: hintColor, fontSize: 13),
                                  ),
                                  if (_selectedFilter != 'all') ...[
                                    const SizedBox(height: 12),
                                    TextButton.icon(
                                      onPressed: () => setState(() => _selectedFilter = 'all'),
                                      icon: const Icon(Icons.clear_all, size: 16),
                                      label: const Text('Clear Filter', style: TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadLeads,
                            color: const Color(0xFF10B981),
                            child: ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: filtered.length,
                              separatorBuilder: (context, index) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final lead = filtered[index];
                                return _buildLeadCard(lead, isDark);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(bool isDark) {
    return Container(
      height: 42,
      margin: const EdgeInsets.only(bottom: 6),
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        buildDefaultDragHandles: false,
        itemCount: _statusFilters.length,
        onReorder: (oldIndex, newIndex) async {
          setState(() {
            if (newIndex > oldIndex) newIndex -= 1;
            final item = _statusFilters.removeAt(oldIndex);
            _statusFilters.insert(newIndex, item);
          });
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setStringList(
              'leads_tab_order',
              _statusFilters.map((f) => f['id']!).toList(),
            );
          } catch (_) {}
        },
        itemBuilder: (context, index) {
          final filter = _statusFilters[index];
          final filterId = filter['id']!;
          final isSelected = _selectedFilter == filterId;
          final count = _getCountForFilter(filterId);

          return ReorderableDelayedDragStartListener(
            key: ValueKey(filterId),
            index: index,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedFilter = filterId;
                  });
                },
                borderRadius: BorderRadius.circular(20),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF059669)
                        : isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF10B981)
                          : isDark
                              ? const Color(0xFF334155).withValues(alpha: 0.6)
                              : const Color(0xFFCBD5E1),
                      width: isSelected ? 1.4 : 1.0,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        filter['label']!,
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
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.black.withValues(alpha: 0.25)
                              : isDark
                                  ? Colors.black.withValues(alpha: 0.2)
                                  : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            color: isSelected
                                ? Colors.white
                                : isDark
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openLeadProfile(LeadItem lead) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LeadProfileDialog(
        lead: lead,
        user: widget.user,
        onLeadUpdated: (updated) {
          setState(() {
            final idx = _leads.indexWhere((l) => l.id == updated.id);
            if (idx != -1) {
              _leads[idx] = updated;
            }
          });
        },
      ),
    );
  }

  Widget _buildLeadCard(LeadItem lead, bool isDark) {
    final cardBg = isDark ? const Color(0xFF161F30) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155).withValues(alpha: 0.5) : const Color(0xFFE2E8F0);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final editBtnBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final editBtnBorder = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
    final editBtnIcon = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openLeadProfile(lead),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lead.displayTitle,
                          style: TextStyle(
                            color: titleColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          lead.displaySubtitle,
                          style: TextStyle(
                            color: subtitleColor,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (lead.formattedAssignedAt != null) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time_rounded,
                                size: 11,
                                color: const Color(0xFF10B981),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'Assigned: ${lead.formattedAssignedAt}',
                                style: TextStyle(
                                  color: subtitleColor,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    children: [
                      if (lead.status.toLowerCase() == 'rnr')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            lead.rnrCount > 0 ? 'RNR ×${lead.rnrCount}' : 'RNR',
                            style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        )
                      else ...[
                        if (lead.rnrCount > 0)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'RNR ×${lead.rnrCount}',
                              style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        _buildLeadStatusBadge(lead.status),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Tags row
              if (lead.businessVertical != null || lead.serviceType != null) ...[
                Wrap(
                  spacing: 6,
                  children: [
                    if (lead.businessVertical != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF059669).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          lead.businessVertical!,
                          style: const TextStyle(color: Color(0xFF059669), fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ),
                    if (lead.serviceType != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          lead.serviceType!,
                          style: const TextStyle(color: Color(0xFF2563EB), fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],

              // Quick Action Buttons
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      onPressed: () => _startCall(lead),
                      icon: const Icon(Icons.call, size: 15),
                      label: const Text('Call SIM', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: OutlinedButton.icon(
                      onPressed: () => _openWhatsApp(lead),
                      icon: const Icon(Icons.chat_bubble_outline, size: 15, color: Color(0xFF10B981)),
                      label: const Text('WhatsApp', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF10B981), width: 1.2),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: editBtnBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: editBtnBorder),
                    ),
                    child: IconButton(
                      icon: Icon(Icons.edit_note_rounded, color: editBtnIcon, size: 20),
                      tooltip: 'View & Edit Lead',
                      onPressed: () => _openLeadProfile(lead),
                      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeadStatusBadge(String status) {
    Color color = const Color(0xFF94A3B8);
    String label = status.replaceAll('_', ' ').toUpperCase();

    final s = status.toLowerCase().trim();
    if (s == 'new' || s == 'uncontacted') {
      color = const Color(0xFF38BDF8);
      label = 'NEW';
    } else if (s.contains('callback')) {
      color = const Color(0xFF818CF8);
      label = 'CALLBACK';
    } else if (s == 'demo_scheduled' || s == 'demo') {
      color = const Color(0xFFA855F7);
      label = 'DEMO BOOKED';
    } else if (s == 'demo_done') {
      color = const Color(0xFF14B8A6);
      label = 'DEMO DONE';
    } else if (s.contains('deal')) {
      color = const Color(0xFFF59E0B);
      label = 'IN DEAL';
    } else if (s == 'won' || s == 'converted') {
      color = const Color(0xFF10B981);
      label = 'WON 🏆';
    } else if (s == 'lost' || s == 'junk') {
      color = Colors.redAccent;
      label = 'LOST';
    } else if (s == 'rnr') {
      color = Colors.amber;
      label = 'RNR';
    } else if (s == 'not_interested') {
      color = const Color(0xFF64748B);
      label = 'NOT INTERESTED';
    } else if (s == 'already_using') {
      color = const Color(0xFF059669);
      label = 'ALREADY USING';
    } else if (s == 'already_purchased') {
      color = const Color(0xFFEA580C);
      label = 'PURCHASED OTHER';
    } else if (s == 'future_requirement') {
      color = const Color(0xFF0284C7);
      label = 'FUTURE REQ';
    } else if (s == 'interested') {
      color = const Color(0xFFEA580C);
      label = 'INTERESTED 🔥';
    } else if (s == 'contacted' || s == 'connected') {
      color = const Color(0xFF06B6D4);
      label = 'CONNECTED';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}

