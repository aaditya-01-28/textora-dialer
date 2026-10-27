class UserProfile {
  final String id;
  final String fullName;
  final String email;
  final String role;
  final String tenantName;
  final String? phoneNumber;
  final String? planTier;
  final String? language;
  final bool? isActive;
  final int? assignedLeadsCount;
  final int? callLogsCount;
  final int? dealsCount;
  final String? createdAt;
  final String? avatarUrl;

  UserProfile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.tenantName,
    this.phoneNumber,
    this.planTier,
    this.language,
    this.isActive,
    this.assignedLeadsCount,
    this.callLogsCount,
    this.dealsCount,
    this.createdAt,
    this.avatarUrl,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final tenantObj = json['tenant'] as Map<String, dynamic>?;
    final counts = json['_count'] as Map<String, dynamic>?;

    return UserProfile(
      id: json['id']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      tenantName: json['tenantName']?.toString() ?? tenantObj?['name']?.toString() ?? 'Textora',
      phoneNumber: json['phoneNumber']?.toString(),
      planTier: tenantObj?['planTier']?.toString() ?? json['planTier']?.toString(),
      language: json['language']?.toString() ?? 'en',
      isActive: json['isActive'] ?? true,
      assignedLeadsCount: (counts?['assignedLeads'] is num)
          ? (counts!['assignedLeads'] as num).toInt()
          : (json['assignedLeadsCount'] is num)
              ? (json['assignedLeadsCount'] as num).toInt()
              : null,
      callLogsCount: (counts?['callLogs'] is num)
          ? (counts!['callLogs'] as num).toInt()
          : (json['callLogsCount'] is num)
              ? (json['callLogsCount'] as num).toInt()
              : null,
      dealsCount: (counts?['deals'] is num)
          ? (counts!['deals'] as num).toInt()
          : (json['dealsCount'] is num)
              ? (json['dealsCount'] as num).toInt()
              : null,
      createdAt: json['createdAt']?.toString(),
      avatarUrl: json['avatarUrl']?.toString() ?? json['avatar_url']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fullName': fullName,
      'email': email,
      'role': role,
      'tenantName': tenantName,
      if (phoneNumber != null) 'phoneNumber': phoneNumber,
      if (planTier != null) 'planTier': planTier,
      if (language != null) 'language': language,
      if (isActive != null) 'isActive': isActive,
      if (assignedLeadsCount != null) 'assignedLeadsCount': assignedLeadsCount,
      if (callLogsCount != null) 'callLogsCount': callLogsCount,
      if (dealsCount != null) 'dealsCount': dealsCount,
      if (createdAt != null) 'createdAt': createdAt,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
    };
  }

  /// Human-friendly Display Role Name
  String get roleDisplayName {
    switch (role.toLowerCase()) {
      case 'super_admin':
        return 'Super Administrator';
      case 'org_admin':
      case 'admin':
        return 'Tenant Administrator';
      case 'sales_manager':
      case 'manager':
        return 'Sales Team Manager';
      case 'sales_rep':
      case 'agent':
      default:
        return 'Sales Representative';
    }
  }

  /// Tiered Level Badge for Role Hierarchy
  String get roleLevelBadge {
    switch (role.toLowerCase()) {
      case 'super_admin':
        return 'LEVEL 4 • PLATFORM OWNER';
      case 'org_admin':
      case 'admin':
        return 'LEVEL 3 • TENANT ADMIN';
      case 'sales_manager':
      case 'manager':
        return 'LEVEL 2 • TEAM MANAGER';
      case 'sales_rep':
      case 'agent':
      default:
        return 'LEVEL 1 • SALES REP';
    }
  }

  /// Whether the user can see organization-wide team metrics
  bool get isManagerOrAbove {
    final r = role.toLowerCase();
    return r == 'super_admin' || r == 'org_admin' || r == 'admin' || r == 'sales_manager' || r == 'manager';
  }
}
