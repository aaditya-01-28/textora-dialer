import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/lead_item.dart';
import '../services/api_service.dart';
import '../services/telephony_service.dart';

class LeadProfileDialog extends StatefulWidget {
  final LeadItem lead;
  final Function(LeadItem updatedLead)? onLeadUpdated;

  const LeadProfileDialog({
    super.key,
    required this.lead,
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
  late String _selectedService;
  late String _selectedLanguage;

  static const List<String> _statusOptions = [
    'new',
    'contacted',
    'qualified',
    'proposal_sent',
    'negotiation',
    'won',
    'lost',
    'rnr',
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
    'Unspecified',
    'WhatsApp API',
    'SMS Gateway',
    'RCS Messaging',
    'Voice OTP & OBD',
    'CRM & Automation Suite',
  ];

  static const List<String> _languageOptions = [
    'English',
    'Hindi',
    'Hinglish',
    'Marathi',
    'Gujarati',
    'Tamil',
    'Telugu',
    'Bengali',
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

    _selectedService = _serviceOptions.contains(_currentLead.serviceType)
        ? _currentLead.serviceType!
        : 'Unspecified';

    _selectedLanguage = _languageOptions.contains(_currentLead.preferredLanguage)
        ? _currentLead.preferredLanguage!
        : 'English';
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
        setState(() {
          _currentLead = LeadItem.fromJson(details);
          _callLogs = logs;
          _isLoadingHistory = false;
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

    final payload = <String, dynamic>{
      'contactName': cleanName.isNotEmpty ? cleanName : null,
      'companyName': cleanCompany.isNotEmpty ? cleanCompany : null,
      'phoneNumber': cleanPhone.isNotEmpty ? cleanPhone : _currentLead.phoneNumber,
      'websiteUrl': cleanWebsite.isNotEmpty ? cleanWebsite : null,
      'businessVertical': _selectedVertical != 'Unspecified' ? _selectedVertical : null,
      'serviceType': _selectedService != 'Unspecified' ? _selectedService : null,
      'status': _selectedStatus,
      'preferredLanguage': _selectedLanguage,
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
          serviceType: _selectedService != 'Unspecified' ? _selectedService : null,
          status: _selectedStatus,
          preferredLanguage: _selectedLanguage,
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
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        throw Exception('Server rejected the update.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(e.toString().replaceAll('Exception:', '').trim()),
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
    final name = _currentLead.contactName ?? 'there';
    final pitch = 'Hello $name! This is from Textora Technologies. Are you looking to boost customer engagement with our official WhatsApp API & Messaging suite?';
    await _telephony.openWhatsApp(rawPhone: _currentLead.phoneNumber, message: pitch);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8), size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),

              // Header: Lead Title, Status, and Call Action Row
              _buildHeader(),
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
                    style: const TextStyle(
                      color: Colors.white,
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
              if (_isEditing) _buildEditForm() else _buildDossierView(),
              const SizedBox(height: 20),

              // Call History with this Lead
              _buildCallHistorySection(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: const Color(0xFF1E293B),
          child: Text(
            _currentLead.displayTitle.isNotEmpty ? _currentLead.displayTitle[0].toUpperCase() : '#',
            style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 20),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _currentLead.displayTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  const Icon(Icons.phone_outlined, color: Color(0xFF94A3B8), size: 14),
                  const SizedBox(width: 4),
                  Text(
                    '+91 ${_currentLead.phoneNumber}',
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
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
                    child: const Icon(Icons.copy_rounded, color: Color(0xFF64748B), size: 14),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _buildStatusPill(_currentLead.status),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusPill(String status) {
    Color bg = const Color(0xFF1E293B);
    Color text = Colors.white70;

    switch (status.toLowerCase()) {
      case 'new':
        bg = const Color(0xFF38BDF8).withValues(alpha: 0.15);
        text = const Color(0xFF38BDF8);
        break;
      case 'contacted':
        bg = const Color(0xFF06B6D4).withValues(alpha: 0.15);
        text = const Color(0xFF06B6D4);
        break;
      case 'qualified':
      case 'won':
        bg = const Color(0xFF10B981).withValues(alpha: 0.15);
        text = const Color(0xFF10B981);
        break;
      case 'rnr':
        bg = Colors.amber.withValues(alpha: 0.15);
        text = Colors.amber;
        break;
      case 'lost':
      case 'junk':
        bg = Colors.red.withValues(alpha: 0.15);
        text = Colors.redAccent;
        break;
      default:
        bg = const Color(0xFF818CF8).withValues(alpha: 0.15);
        text = const Color(0xFF818CF8);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: text.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: text, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }

  Widget _buildQuickActionButtons() {
    return Row(
      children: [
        Expanded(
          flex: 3,
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

  Widget _buildDossierView() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155).withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          _buildInfoRow('Contact Person', _currentLead.contactName ?? 'Not specified'),
          const Divider(color: Color(0xFF334155), height: 16),
          _buildInfoRow('Company Name', _currentLead.companyName ?? 'Not specified'),
          const Divider(color: Color(0xFF334155), height: 16),
          _buildInfoRow('Industry Vertical', _currentLead.businessVertical ?? 'Unspecified'),
          const Divider(color: Color(0xFF334155), height: 16),
          _buildInfoRow('Service Interest', _currentLead.serviceType ?? 'Unspecified'),
          const Divider(color: Color(0xFF334155), height: 16),
          _buildInfoRow('Preferred Language', _currentLead.preferredLanguage ?? 'English'),
          const Divider(color: Color(0xFF334155), height: 16),
          _buildInfoRow('Website URL', _currentLead.websiteUrl ?? 'None'),
          const Divider(color: Color(0xFF334155), height: 16),
          _buildInfoRow('Lead Source', _currentLead.source),
          if (_currentLead.address != null && _currentLead.address!.isNotEmpty) ...[
            const Divider(color: Color(0xFF334155), height: 16),
            _buildInfoRow('Address', _currentLead.address!),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTextField('Contact Name', _nameController, 'e.g. Ramesh Kumar'),
          const SizedBox(height: 12),
          _buildTextField('Company / Organization', _companyController, 'e.g. Acme Logistics Pvt Ltd'),
          const SizedBox(height: 12),
          _buildTextField('Phone Number', _phoneController, '10 digit number', isPhone: true),
          const SizedBox(height: 12),
          _buildDropdown(
            label: 'Lead Pipeline Status',
            value: _selectedStatus,
            items: _statusOptions,
            onChanged: (val) => setState(() => _selectedStatus = val!),
          ),
          const SizedBox(height: 12),
          _buildDropdown(
            label: 'Industry Vertical',
            value: _selectedVertical,
            items: _verticalOptions,
            onChanged: (val) => setState(() => _selectedVertical = val!),
          ),
          const SizedBox(height: 12),
          _buildDropdown(
            label: 'Service Interest',
            value: _selectedService,
            items: _serviceOptions,
            onChanged: (val) => setState(() => _selectedService = val!),
          ),
          const SizedBox(height: 12),
          _buildDropdown(
            label: 'Preferred Language',
            value: _selectedLanguage,
            items: _languageOptions,
            onChanged: (val) => setState(() => _selectedLanguage = val!),
          ),
          const SizedBox(height: 12),
          _buildTextField('Website URL', _websiteController, 'https://example.com'),
          const SizedBox(height: 12),
          _buildTextField('Address / City', _addressController, 'e.g. Mumbai, Maharashtra'),
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

  Widget _buildTextField(String label, TextEditingController controller, String hint, {bool isPhone = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 12),
            filled: true,
            fillColor: const Color(0xFF0F172A),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value) ? value : items.first,
              isExpanded: true,
              dropdownColor: const Color(0xFF1E293B),
              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF94A3B8)),
              style: const TextStyle(color: Colors.white, fontSize: 13),
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

  Widget _buildCallHistorySection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.history_rounded, color: Color(0xFF10B981), size: 18),
              SizedBox(width: 8),
              Text(
                'Recent Calls with this Lead',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
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
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'No previous calls recorded for this lead yet.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _callLogs.length > 5 ? 5 : _callLogs.length,
              separatorBuilder: (context, index) => const Divider(color: Color(0xFF334155), height: 14),
              itemBuilder: (context, index) {
                final log = _callLogs[index];
                final disp = log['disposition'] ?? 'Unknown';
                final dur = log['durationSeconds'] ?? 0;
                final time = log['callTimestamp']?.toString() ?? '';
                final isConnected = disp.toString().toLowerCase().contains('connect');

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isConnected ? Icons.call_made_rounded : Icons.call_missed_rounded,
                          color: isConnected ? const Color(0xFF10B981) : Colors.amber,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              disp,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            Text(
                              time.length >= 16 ? time.substring(0, 16).replaceAll('T', ' ') : time,
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Text(
                      '${dur}s',
                      style: const TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 12),
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
