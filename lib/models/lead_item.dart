class LeadItem {
  final String id;
  final String phoneNumber;
  final String? contactName;
  final String? companyName;
  final String? websiteUrl;
  final String? businessVertical;
  final String? serviceType;
  final String source;
  final String status;
  final int rnrCount;
  final String? preferredLanguage;
  final String? address;
  final String? createdAt;
  final String? updatedAt;
  final String? assignedRepName;
  final int callLogsCount;

  LeadItem({
    required this.id,
    required this.phoneNumber,
    this.contactName,
    this.companyName,
    this.websiteUrl,
    this.businessVertical,
    this.serviceType,
    required this.source,
    required this.status,
    required this.rnrCount,
    this.callLogsCount = 0,
    this.preferredLanguage,
    this.address,
    this.createdAt,
    this.updatedAt,
    this.assignedRepName,
  });

  factory LeadItem.fromJson(Map<String, dynamic> json) {
    final customMeta = json['customMetadata'] as Map<String, dynamic>?;
    final assignedRep = json['assignedRep'] as Map<String, dynamic>?;

    return LeadItem(
      id: json['id']?.toString() ?? '',
      phoneNumber: json['phoneNumber']?.toString() ?? '',
      contactName: json['contactName']?.toString(),
      companyName: json['companyName']?.toString(),
      websiteUrl: json['websiteUrl']?.toString(),
      businessVertical: json['businessVertical']?.toString(),
      serviceType: json['serviceType']?.toString(),
      source: json['source']?.toString() ?? 'Direct',
      status: json['status']?.toString() ?? 'new',
      rnrCount: (json['rnrCount'] is num) ? (json['rnrCount'] as num).toInt() : 0,
      callLogsCount: (json['callLogsCount'] is num)
          ? (json['callLogsCount'] as num).toInt()
          : (json['_count'] is Map && json['_count']['callLogs'] is num)
              ? (json['_count']['callLogs'] as num).toInt()
              : 0,
      preferredLanguage: json['preferredLanguage']?.toString() ?? customMeta?['preferredLanguage']?.toString(),
      address: json['address']?.toString() ?? customMeta?['address']?.toString(),
      createdAt: json['createdAt']?.toString(),
      updatedAt: json['updatedAt']?.toString(),
      assignedRepName: assignedRep?['fullName']?.toString() ?? json['assignedRepName']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phoneNumber': phoneNumber,
      'contactName': contactName,
      'companyName': companyName,
      'websiteUrl': websiteUrl,
      'businessVertical': businessVertical,
      'serviceType': serviceType,
      'source': source,
      'status': status,
      'rnrCount': rnrCount,
      'preferredLanguage': preferredLanguage,
      'address': address,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  LeadItem copyWith({
    String? id,
    String? phoneNumber,
    String? contactName,
    String? companyName,
    String? websiteUrl,
    String? businessVertical,
    String? serviceType,
    String? source,
    String? status,
    int? rnrCount,
    int? callLogsCount,
    String? preferredLanguage,
    String? address,
    String? createdAt,
    String? updatedAt,
    String? assignedRepName,
  }) {
    return LeadItem(
      id: id ?? this.id,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      contactName: contactName ?? this.contactName,
      companyName: companyName ?? this.companyName,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      businessVertical: businessVertical ?? this.businessVertical,
      serviceType: serviceType ?? this.serviceType,
      source: source ?? this.source,
      status: status ?? this.status,
      rnrCount: rnrCount ?? this.rnrCount,
      callLogsCount: callLogsCount ?? this.callLogsCount,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      address: address ?? this.address,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      assignedRepName: assignedRepName ?? this.assignedRepName,
    );
  }

  /// Clean display title: Avoids showing raw phone number twice!
  String get displayTitle {
    final name = contactName?.trim();
    if (name != null && name.isNotEmpty && name != phoneNumber) {
      return name;
    }
    final comp = companyName?.trim();
    if (comp != null && comp.isNotEmpty && comp != phoneNumber) {
      return comp;
    }
    return '+91 $phoneNumber';
  }

  /// Alias for backward compatibility
  String get displayName => displayTitle;

  /// Clean secondary line
  String get displaySubtitle {
    final name = contactName?.trim();
    final comp = companyName?.trim();
    if (name != null && name.isNotEmpty && name != phoneNumber) {
      if (comp != null && comp.isNotEmpty && comp != phoneNumber) {
        return '$comp • +91 $phoneNumber';
      }
      return '+91 $phoneNumber';
    }
    if (comp != null && comp.isNotEmpty && comp != phoneNumber) {
      return '+91 $phoneNumber';
    }
    return 'New Unnamed Prospect';
  }

  /// Status badge label and human text
  String get statusDisplay {
    switch (status.toLowerCase()) {
      case 'new':
        return 'NEW';
      case 'contacted':
        return 'CONTACTED';
      case 'qualified':
        return 'QUALIFIED';
      case 'proposal_sent':
        return 'PROPOSAL';
      case 'negotiation':
        return 'NEGOTIATION';
      case 'won':
        return 'WON';
      case 'lost':
        return 'LOST';
      case 'rnr':
        return 'RNR';
      case 'junk':
        return 'JUNK';
      default:
        return status.toUpperCase();
    }
  }
}
