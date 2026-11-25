import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/lead_item.dart';
import '../models/user_profile.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/telephony_service.dart';

class LeadProfileDialog extends StatefulWidget {
  final LeadItem lead;
  final UserProfile? user;
  final Function(LeadItem updatedLead)? onLeadUpdated;

  const LeadProfileDialog({
    super.key,
    required this.lead,
    this.user,
    this.onLeadUpdated,
  });

  @override
  State<LeadProfileDialog> createState() => _LeadProfileDialogState();
}

class _LeadProfileDialogState extends State<LeadProfileDialog> {
  final _api = ApiService();
  final _telephony = TelephonyService();

  late LeadItem _currentLead;
  bool _isEditing = false;
  bool _isSaving = false;
  bool _isLoadingHistory = true;
  List<Map<String, dynamic>> _callLogs = [];

  // Controllers for editing
  late TextEditingController _nameController;
  late TextEditingController _companyController;
  late TextEditingController _phoneController;
  late TextEditingController _websiteController;
  late TextEditingController _addressController;

  late String _selectedStatus;
  late String _selectedVertical;
  List<String> _selectedServices = [];
  List<String> _selectedLanguages = [];

  static const List<String> _statusOptions = [
    'new',
    'interested',
    'callback',
    'demo_scheduled',
    'demo_done',
    'deal_created',
    'won',
    'lost',
    'rnr',
    'not_interested',
    'already_using',
    'already_purchased',
    'future_requirement',
    'contacted',
    'qualified',
    'proposal_sent',
    'negotiation',
    'junk',
  ];

  static const List<String> _verticalOptions = [
    'Unspecified',
    'Logistics & Supply Chain',
    'Real Estate & Builders',
    'E-Commerce & Retail',
    'Healthcare & Clinics',
    'Education & EdTech',
    'Financial Services & Fintech',
    'Automobile & Dealerships',
    'Travel & Hospitality',
    'Manufacturing',
    'Other Business',
  ];

  static const List<String> _serviceOptions = [
    'WhatsApp API',
    'Bulk WhatsApp',
    'Virtual WhatsApp',
    'Bulk SMS',
    'RCS Messaging',
    'Transactional SMS',
    'Promotional SMS',
    'Voice SMS / OBD',
    'OTP API',
    'DLT & SMS Gateway',
    'Combo WA+SMS',
    'Reseller',
  ];

  static const List<String> _languageOptions = [
    'English',
    'Hindi',
    'Tamil',
    'Telugu',
    'Kannada',
    'Malayalam',
    'Marathi',
    'Gujarati',
    'Bengali',
    'Punjabi',
    'Odia',
    'Assamese',
    'Urdu',
  ];

  @override
  void initState() {
    super.initState();
    _currentLead = widget.lead;
    _initControllers();
    _fetchLeadDetails();
  }

  void _initControllers() {
    _nameController = TextEditingController(text: _currentLead.contactName ?? '');
    _companyController = TextEditingController(text: _currentLead.companyName ?? '');
    _phoneController = TextEditingController(text: _currentLead.phoneNumber);
    _websiteController = TextEditingController(text: _currentLead.websiteUrl ?? '');
    _addressController = TextEditingController(text: _currentLead.address ?? '');

    _selectedStatus = _statusOptions.contains(_currentLead.status.toLowerCase())
        ? _currentLead.status.toLowerCase()
        : 'new';

    _selectedVertical = _verticalOptions.contains(_currentLead.businessVertical)
        ? _currentLead.businessVertical!
        : 'Unspecified';

    final rawService = _currentLead.serviceType ?? '';
    if (rawService.isNotEmpty && rawService.toLowerCase() != 'unspecified') {
      _selectedServices = rawService
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && s.toLowerCase() != 'unspecified')
          .toList();
    } else {
      _selectedServices = [];
    }

    final rawLang = _currentLead.preferredLanguage ?? '';
    if (rawLang.isNotEmpty) {
      _selectedLanguages = rawLang
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else {
      _selectedLanguages = [];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _companyController.dispose();
    _phoneController.dispose();
    _websiteController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _fetchLeadDetails() async {
    try {
      final details = await _api.getLeadDetails(_currentLead.id);
      if (details.isNotEmpty && mounted) {
        final logs = (details['callLogs'] as List?)?.map((e) => e as Map<String, dynamic>).toList() ?? [];
        final fetchedLead = LeadItem.fromJson(details);
        setState(() {
          _currentLead = fetchedLead;
          _callLogs = logs;
          _isLoadingHistory = false;
          if (!_isEditing) {
            _initControllers();
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _saveLeadProfile() async {
    setState(() => _isSaving = true);

    final cleanName = _nameController.text.trim();
    final cleanCompany = _companyController.text.trim();
    final cleanPhone = _phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
    final cleanWebsite = _websiteController.text.trim();
    final cleanAddress = _addressController.text.trim();
    final cleanServices = _selectedServices.join(', ');
    final cleanLanguages = _selectedLanguages.join(', ');

    final payload = <String, dynamic>{
      'contactName': cleanName.isNotEmpty ? cleanName : null,
      'companyName': cleanCompany.isNotEmpty ? cleanCompany : null,
      'phoneNumber': cleanPhone.isNotEmpty ? cleanPhone : _currentLead.phoneNumber,
      'websiteUrl': cleanWebsite.isNotEmpty ? cleanWebsite : null,
      'businessVertical': _selectedVertical != 'Unspecified' ? _selectedVertical : null,
      'serviceType': cleanServices.isNotEmpty ? cleanServices : null,
      'status': _selectedStatus,
      'preferredLanguage': cleanLanguages.isNotEmpty ? cleanLanguages : null,
      'address': cleanAddress.isNotEmpty ? cleanAddress : null,
    };

    try {
      final ok = await _api.updateLead(_currentLead.id, payload);
      if (ok) {
        final updated = _currentLead.copyWith(
          contactName: cleanName.isNotEmpty ? cleanName : null,
          companyName: cleanCompany.isNotEmpty ? cleanCompany : null,
          phoneNumber: cleanPhone.isNotEmpty ? cleanPhone : _currentLead.phoneNumber,
          websiteUrl: cleanWebsite.isNotEmpty ? cleanWebsite : null,
          businessVertical: _selectedVertical != 'Unspecified' ? _selectedVertical : null,
          serviceType: cleanServices.isNotEmpty ? cleanServices : null,
          status: _selectedStatus,
          preferredLanguage: cleanLanguages.isNotEmpty ? cleanLanguages : null,
          address: cleanAddress.isNotEmpty ? cleanAddress : null,
        );

        if (mounted) {
          setState(() {
            _currentLead = updated;
            _isEditing = false;
            _isSaving = false;
          });
          widget.onLeadUpdated?.call(updated);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFF059669),
              content: Text('Lead profile updated successfully!'),
            ),
          );
        }
      } else {
        if (mounted) {
          setState(() => _isSaving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text('Failed to update lead. Please try again.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Error: ${e.toString().replaceAll('Exception:', '').trim()}'),
          ),
        );
      }
    }
  }

  Future<void> _callLead() async {
    Navigator.of(context).pop();
    await _telephony.makeCall(
      rawPhone: _currentLead.phoneNumber,
      leadId: _currentLead.id,
    );
  }

  Future<void> _openWhatsApp() async {
    UserProfile? currentUser = widget.user;
    currentUser ??= await StorageService().getUserProfile();

    final pitch = TelephonyService.buildWAPitch(
      repName: currentUser?.fullName,
      repEmail: currentUser?.email,
      repPhone: currentUser?.phoneNumber,
      contactName: _currentLead.contactName,
    );
    await _telephony.openWhatsApp(rawPhone: _currentLead.phoneNumber, message: pitch);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final modalBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final cardBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC);
    final borderColor = isDark ? const Color(0xFF334155).withValues(alpha: 0.5) : const Color(0xFFE2E8F0);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final dragHandleColor = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
    final dividerColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return Container(
      decoration: BoxDecoration(
        color: modalBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top drag bar & close
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: dragHandleColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: subColor, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),

              // Header: Lead Title, Status, and Call Action Row
              _buildHeader(isDark, titleColor, subColor),
              const SizedBox(height: 16),

              // Quick Actions: Call SIM & WhatsApp
              _buildQuickActionButtons(),
              const SizedBox(height: 16),

              // Edit / View Toggle Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isEditing ? 'Editing Lead Profile' : 'Lead Profile Dossier',
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _isSaving ? null : () => setState(() => _isEditing = !_isEditing),
                    icon: Icon(
                      _isEditing ? Icons.visibility_outlined : Icons.edit_outlined,
                      size: 16,
                      color: const Color(0xFF10B981),
                    ),
                    label: Text(
                      _isEditing ? 'View Mode' : 'Edit Profile',
                      style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Body: Either Edit Form or Compact Dossier View
              if (_isEditing)
                _buildEditForm(isDark, cardBg, borderColor, titleColor, subColor)
              else
                _buildDossierView(cardBg, borderColor, titleColor, subColor, dividerColor),
              const SizedBox(height: 20),

              // Call History with this Lead
              _buildCallHistorySection(isDark, cardBg, borderColor, titleColor, subColor, dividerColor),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark, Color titleColor, Color subColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFE6F4EA),
          child: Text(
            _currentLead.displayTitle.isNotEmpty ? _currentLead.displayTitle[0].toUpperCase() : '#',
            style: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold, fontSize: 20),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _currentLead.displayTitle,
                style: TextStyle(
                  color: titleColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Icon(Icons.phone_outlined, color: subColor, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '+91 ${_currentLead.phoneNumber}',
                    style: TextStyle(
                      color: subColor,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: _currentLead.phoneNumber));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Phone number copied to clipboard!'), duration: Duration(seconds: 1)),
                      );
                    },
                    child: Icon(Icons.copy_rounded, color: subColor, size: 14),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (_currentLead.status.toLowerCase() == 'rnr') ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        _currentLead.rnrCount > 0 ? 'RNR ×${_currentLead.rnrCount}' : 'RNR',
                        style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ] else ...[
                    _buildStatusPill(_currentLead.status),
                    if (_currentLead.rnrCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'RNR ×${_currentLead.rnrCount}',
                          style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusPill(String status) {
    Color bg = const Color(0xFF1E293B);
    Color text = Colors.white70;

    final s = status.toLowerCase();
    if (s == 'new' || s == 'uncontacted') {
      bg = const Color(0xFF38BDF8).withValues(alpha: 0.15);
      text = const Color(0xFF38BDF8);
    } else if (s.contains('callback')) {
      bg = const Color(0xFF818CF8).withValues(alpha: 0.15);
      text = const Color(0xFF818CF8);
    } else if (s.contains('demo')) {
      bg = const Color(0xFFA855F7).withValues(alpha: 0.15);
      text = const Color(0xFFA855F7);
    } else if (s.contains('deal')) {
      bg = const Color(0xFFF59E0B).withValues(alpha: 0.15);
      text = const Color(0xFFF59E0B);
    } else if (s == 'won' || s == 'converted') {
      bg = const Color(0xFF10B981).withValues(alpha: 0.15);
      text = const Color(0xFF10B981);
    } else if (s == 'rnr') {
      bg = Colors.amber.withValues(alpha: 0.15);
      text = Colors.amber;
    } else if (s == 'lost' || s == 'junk') {
      bg = Colors.red.withValues(alpha: 0.15);
      text = Colors.redAccent;
    } else {
      bg = const Color(0xFF64748B).withValues(alpha: 0.15);
      text = const Color(0xFF64748B);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: text.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(color: text, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }

  Widget _buildQuickActionButtons() {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: ElevatedButton.icon(
            onPressed: _callLead,
            icon: const Icon(Icons.phone_forwarded_rounded, size: 18),
            label: const Text('Call SIM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 3,
          child: OutlinedButton.icon(
            onPressed: _openWhatsApp,
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: Color(0xFF22C55E)),
            label: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF22C55E))),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF22C55E), width: 1.2),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDossierView(
    Color cardBg,
    Color borderColor,
    Color titleColor,
    Color subColor,
    Color dividerColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          _buildInfoRow('Contact Person', _currentLead.contactName ?? 'Not specified', titleColor, subColor),
          Divider(color: dividerColor, height: 16),
          _buildInfoRow('Company Name', _currentLead.companyName ?? 'Not specified', titleColor, subColor),
          Divider(color: dividerColor, height: 16),
          _buildInfoRow('Industry Vertical', _currentLead.businessVertical ?? 'Unspecified', titleColor, subColor),
          Divider(color: dividerColor, height: 16),
          _buildInfoRow(
            'Service Interest',
            (_currentLead.serviceType != null && _currentLead.serviceType!.trim().isNotEmpty && _currentLead.serviceType != 'Unspecified')
                ? _currentLead.serviceType!
                : 'Unspecified',
            titleColor,
            subColor,
          ),
          Divider(color: dividerColor, height: 16),
          _buildInfoRow(
            'Preferred Language',
            (_currentLead.preferredLanguage != null && _currentLead.preferredLanguage!.trim().isNotEmpty)
                ? _currentLead.preferredLanguage!
                : 'English',
            titleColor,
            subColor,
          ),
          Divider(color: dividerColor, height: 16),
          _buildInfoRow('Website URL', _currentLead.websiteUrl ?? 'None', titleColor, subColor),
          Divider(color: dividerColor, height: 16),
          _buildInfoRow('Lead Source', _currentLead.source, titleColor, subColor),
          if (_currentLead.formattedAssignedAt != null) ...[
            Divider(color: dividerColor, height: 16),
            _buildInfoRow('Assigned On', _currentLead.formattedAssignedAt!, titleColor, subColor),
          ],
          if (_currentLead.assignedRepName != null && _currentLead.assignedRepName!.isNotEmpty) ...[
            Divider(color: dividerColor, height: 16),
            _buildInfoRow('Assigned Rep', _currentLead.assignedRepName!, titleColor, subColor),
          ],
          if (_currentLead.address != null && _currentLead.address!.isNotEmpty) ...[
            Divider(color: dividerColor, height: 16),
            _buildInfoRow('Address', _currentLead.address!, titleColor, subColor),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color titleColor, Color subColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: subColor, fontSize: 12),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: titleColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditForm(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color titleColor,
    Color subColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTextField('Contact Name', _nameController, 'e.g. Ramesh Kumar', isDark, titleColor, subColor),
          const SizedBox(height: 12),
          _buildTextField('Company / Organization', _companyController, 'e.g. Acme Logistics Pvt Ltd', isDark, titleColor, subColor),
          const SizedBox(height: 12),
          _buildTextField('Phone Number', _phoneController, '10 digit number', isDark, titleColor, subColor, isPhone: true),
          const SizedBox(height: 12),
          _buildDropdown(
            label: 'Lead Pipeline Status',
            value: _selectedStatus,
            items: _statusOptions,
            isDark: isDark,
            titleColor: titleColor,
            subColor: subColor,
            onChanged: (val) => setState(() => _selectedStatus = val!),
          ),
          const SizedBox(height: 12),
          _buildDropdown(
            label: 'Industry Vertical',
            value: _selectedVertical,
            items: _verticalOptions,
            isDark: isDark,
            titleColor: titleColor,
            subColor: subColor,
            onChanged: (val) => setState(() => _selectedVertical = val!),
          ),
          const SizedBox(height: 12),
          _buildMultiSelectField(
            label: 'Interested Services (Multi-Select)',
            selectedItems: _selectedServices,
            allItems: _serviceOptions,
            primaryColor: const Color(0xFF10B981),
            isDark: isDark,
            titleColor: titleColor,
            subColor: subColor,
            onChanged: (newList) => setState(() => _selectedServices = newList),
          ),
          const SizedBox(height: 12),
          _buildMultiSelectField(
            label: 'Preferred Languages (Multi-Select)',
            selectedItems: _selectedLanguages,
            allItems: _languageOptions,
            primaryColor: const Color(0xFF6366F1),
            isDark: isDark,
            titleColor: titleColor,
            subColor: subColor,
            onChanged: (newList) => setState(() => _selectedLanguages = newList),
          ),
          const SizedBox(height: 12),
          _buildTextField('Website URL', _websiteController, 'https://example.com', isDark, titleColor, subColor),
          const SizedBox(height: 12),
          _buildTextField('Address / City', _addressController, 'e.g. Mumbai, Maharashtra', isDark, titleColor, subColor),
          const SizedBox(height: 18),

          ElevatedButton(
            onPressed: _isSaving ? null : _saveLeadProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Save Lead Changes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    String hint,
    bool isDark,
    Color titleColor,
    Color subColor, {
    bool isPhone = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: subColor, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
          style: TextStyle(color: titleColor, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8), fontSize: 12),
            filled: true,
            fillColor: isDark ? const Color(0xFF0F172A) : Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required bool isDark,
    required Color titleColor,
    required Color subColor,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: subColor, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value) ? value : items.first,
              isExpanded: true,
              dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              icon: Icon(Icons.arrow_drop_down, color: subColor),
              style: TextStyle(color: titleColor, fontSize: 13),
              items: items.map((opt) {
                return DropdownMenuItem<String>(
                  value: opt,
                  child: Text(opt.replaceAll('_', ' ').toUpperCase()),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMultiSelectField({
    required String label,
    required List<String> selectedItems,
    required List<String> allItems,
    required Color primaryColor,
    required bool isDark,
    required Color titleColor,
    required Color subColor,
    required ValueChanged<List<String>> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: subColor, fontSize: 12, fontWeight: FontWeight.w600)),
            Text(
              '${selectedItems.length} selected',
              style: TextStyle(color: subColor, fontSize: 10),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectedItems.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: selectedItems.map((item) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: primaryColor.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item,
                            style: TextStyle(
                              color: isDark ? Colors.white : primaryColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () {
                              final updated = List<String>.from(selectedItems)..remove(item);
                              onChanged(updated);
                            },
                            child: Icon(Icons.close, size: 14, color: primaryColor),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'None selected',
                    style: TextStyle(color: subColor, fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => _openMultiSelectPicker(
                  label: label,
                  selectedItems: selectedItems,
                  allItems: allItems,
                  primaryColor: primaryColor,
                  isDark: isDark,
                  onChanged: onChanged,
                ),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_circle_outline, size: 14, color: primaryColor),
                      const SizedBox(width: 4),
                      Text(
                        '+ Select / Modify',
                        style: TextStyle(color: primaryColor, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openMultiSelectPicker({
    required String label,
    required List<String> selectedItems,
    required List<String> allItems,
    required Color primaryColor,
    required bool isDark,
    required ValueChanged<List<String>> onChanged,
  }) {
    final tempSelected = List<String>.from(selectedItems);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final modalBg = isDark ? const Color(0xFF1E293B) : Colors.white;
            final txtColor = isDark ? Colors.white : const Color(0xFF0F172A);

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.75,
              ),
              decoration: BoxDecoration(
                color: modalBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        label,
                        style: TextStyle(color: txtColor, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: allItems.length,
                      itemBuilder: (context, idx) {
                        final item = allItems[idx];
                        final isChecked = tempSelected.contains(item);
                        return CheckboxListTile(
                          value: isChecked,
                          title: Text(
                            item,
                            style: TextStyle(
                              color: txtColor,
                              fontSize: 13,
                              fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          activeColor: primaryColor,
                          checkColor: Colors.white,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          onChanged: (bool? val) {
                            setModalState(() {
                              if (val == true) {
                                if (!tempSelected.contains(item)) tempSelected.add(item);
                              } else {
                                tempSelected.remove(item);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      onChanged(tempSelected);
                      Navigator.of(ctx).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Apply Selection', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCallHistorySection(
    bool isDark,
    Color cardBg,
    Color borderColor,
    Color titleColor,
    Color subColor,
    Color dividerColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, color: Color(0xFF10B981), size: 18),
              const SizedBox(width: 8),
              Text(
                'Recent Calls with this Lead',
                style: TextStyle(color: titleColor, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoadingHistory)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                ),
              ),
            )
          else if (_callLogs.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'No previous calls recorded for this lead yet.',
                  style: TextStyle(color: subColor, fontSize: 12),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _callLogs.length > 5 ? 5 : _callLogs.length,
              separatorBuilder: (context, index) => Divider(color: dividerColor, height: 14),
              itemBuilder: (context, index) {
                final log = _callLogs[index];
                final disp = log['disposition'] ?? 'Unknown';
                final dur = log['durationSeconds'] ?? 0;
                final rawTime = log['callTimestamp']?.toString() ?? '';
                final remark = log['remark']?.toString().trim();
                final isConnected = disp.toString().toLowerCase().contains('connect');

                String displayTime = rawTime;
                try {
                  final parsed = DateTime.parse(rawTime).toLocal();
                  final y = parsed.year.toString().padLeft(4, '0');
                  final mo = parsed.month.toString().padLeft(2, '0');
                  final da = parsed.day.toString().padLeft(2, '0');
                  final ho = parsed.hour.toString().padLeft(2, '0');
                  final mi = parsed.minute.toString().padLeft(2, '0');
                  displayTime = '$y-$mo-$da $ho:$mi';
                } catch (_) {
                  displayTime = rawTime.length >= 16 ? rawTime.substring(0, 16).replaceAll('T', ' ') : rawTime;
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              isConnected ? Icons.call_made_rounded : Icons.call_missed_rounded,
                              color: isConnected ? const Color(0xFF10B981) : Colors.amber,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  disp,
                                  style: TextStyle(color: titleColor, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                Text(
                                  displayTime,
                                  style: TextStyle(color: subColor, fontSize: 10),
                                ),
                                if (remark != null && remark.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    '💬 $remark',
                                    style: TextStyle(
                                      color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF2563EB),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${dur}s',
                      style: TextStyle(color: subColor, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
