class DealStageStat {
  final String stage;
  final int count;
  final double value;

  DealStageStat({
    required this.stage,
    required this.count,
    required this.value,
  });

  factory DealStageStat.fromJson(Map<String, dynamic> json) {
    return DealStageStat(
      stage: json['stage']?.toString() ?? '',
      count: _parseInt(json['count']),
      value: _parseDouble(json['value']),
    );
  }

  static int _parseInt(dynamic val) {
    if (val == null) return 0;
    if (val is num) return val.toInt();
    return int.tryParse(val.toString()) ?? 0;
  }

  static double _parseDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }
}

class DashboardTeamMember {
  final String id;
  final String fullName;
  final String email;
  final String role;
  final String? phoneNumber;

  DashboardTeamMember({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    this.phoneNumber,
  });

  factory DashboardTeamMember.fromJson(Map<String, dynamic> json) {
    return DashboardTeamMember(
      id: json['id']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      phoneNumber: json['phoneNumber']?.toString(),
    );
  }
}

class DashboardStats {
  final int totalCalls;
  final int uniqueDials;
  final int connectedCalls;
  final int connectRate;
  final int talkTimeMins;
  final int totalDurationSeconds;
  final String? talkTimeFormatted;
  final Map<String, int> dispositionMap;
  final int queueRemainingCount;
  final int unassignedLeadsCount;
  final int todayCallbacksCount;
  final int todayDemosCount;
  final int overdueTasksCount;
  final int activeDealsCount;
  final double activePipelineValue;
  final int wonDealsCount;
  final double wonRevenueInPeriod;
  final double verifiedRevenue;
  final int winRate;
  final int totalLeadsCount;
  final List<AgendaItem> todayAgenda;
  final List<LeadStatusCount> leadsByStatus;
  final List<DealStageStat> allDealsByStage;
  final List<DashboardTeamMember> teamMembers;
  final String? dateFrom;
  final String? dateTo;

  DashboardStats({
    required this.totalCalls,
    required this.uniqueDials,
    required this.connectedCalls,
    required this.connectRate,
    required this.talkTimeMins,
    this.totalDurationSeconds = 0,
    this.talkTimeFormatted,
    required this.dispositionMap,
    required this.queueRemainingCount,
    required this.unassignedLeadsCount,
    required this.todayCallbacksCount,
    required this.todayDemosCount,
    required this.overdueTasksCount,
    required this.activeDealsCount,
    required this.activePipelineValue,
    required this.wonDealsCount,
    required this.wonRevenueInPeriod,
    required this.verifiedRevenue,
    required this.winRate,
    required this.totalLeadsCount,
    required this.todayAgenda,
    required this.leadsByStatus,
    required this.allDealsByStage,
    this.teamMembers = const [],
    this.dateFrom,
    this.dateTo,
  });

  static int _parseInt(dynamic val) {
    if (val == null) return 0;
    if (val is num) return val.toInt();
    return int.tryParse(val.toString()) ?? 0;
  }

  static double _parseDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  factory DashboardStats.fromJson(
    Map<String, dynamic> json, {
    List<DashboardTeamMember> teamMembers = const [],
    String? dateFrom,
    String? dateTo,
  }) {
    final dispMap = <String, int>{};
    if (json['dispositionMap'] is Map) {
      (json['dispositionMap'] as Map).forEach((k, v) {
        dispMap[k.toString()] = _parseInt(v);
      });
    }

    final agendaList = <AgendaItem>[];
    if (json['todayAgenda'] is List) {
      for (var a in (json['todayAgenda'] as List)) {
        if (a is Map<String, dynamic>) {
          agendaList.add(AgendaItem.fromJson(a));
        }
      }
    }

    final statusList = <LeadStatusCount>[];
    if (json['leadsByStatus'] is List) {
      for (var s in (json['leadsByStatus'] as List)) {
        if (s is Map<String, dynamic>) {
          statusList.add(LeadStatusCount.fromJson(s));
        }
      }
    }

    final dealsByStageList = <DealStageStat>[];
    if (json['allDealsByStage'] is List) {
      for (var d in (json['allDealsByStage'] as List)) {
        if (d is Map<String, dynamic>) {
          dealsByStageList.add(DealStageStat.fromJson(d));
        }
      }
    }

    return DashboardStats(
      totalCalls: _parseInt(json['totalCalls']),
      uniqueDials: _parseInt(json['uniqueDials']),
      connectedCalls: _parseInt(json['connectedCalls']),
      connectRate: _parseInt(json['connectRate']),
      talkTimeMins: _parseInt(json['talkTimeMins']),
      totalDurationSeconds: _parseInt(json['totalDurationSeconds']),
      talkTimeFormatted: json['talkTimeFormatted']?.toString(),
      dispositionMap: dispMap,
      queueRemainingCount: _parseInt(json['queueRemainingCount']),
      unassignedLeadsCount: _parseInt(json['unassignedLeadsCount']),
      todayCallbacksCount: _parseInt(json['todayCallbacksCount']),
      todayDemosCount: _parseInt(json['todayDemosCount']),
      overdueTasksCount: _parseInt(json['overdueTasksCount']),
      activeDealsCount: _parseInt(json['activeDealsCount']),
      activePipelineValue: _parseDouble(json['activePipelineValue']),
      wonDealsCount: _parseInt(json['wonDealsCount']),
      wonRevenueInPeriod: _parseDouble(json['wonRevenueInPeriod']),
      verifiedRevenue: _parseDouble(json['verifiedRevenue']),
      winRate: _parseInt(json['winRate']),
      totalLeadsCount: _parseInt(json['totalLeadsCount']),
      todayAgenda: agendaList,
      leadsByStatus: statusList,
      allDealsByStage: dealsByStageList,
      teamMembers: teamMembers,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
  }

  /// Exact human-readable talk time duration (e.g. 0m 22s, 2m 14s, 1h 05m 12s)
  String get displayTalkTime {
    if (talkTimeFormatted != null && talkTimeFormatted!.isNotEmpty) {
      return talkTimeFormatted!;
    }
    final secs = totalDurationSeconds;
    if (secs > 0) {
      final hours = secs ~/ 3600;
      final minutes = (secs % 3600) ~/ 60;
      final remainingSecs = secs % 60;
      if (hours > 0) {
        return '${hours}h ${minutes}m ${remainingSecs}s';
      }
      return '${minutes}m ${remainingSecs}s';
    }
    if (talkTimeMins > 0) {
      return '${talkTimeMins}m 00s';
    }
    return '0m 00s';
  }

  factory DashboardStats.empty() {
    return DashboardStats(
      totalCalls: 0,
      uniqueDials: 0,
      connectedCalls: 0,
      connectRate: 0,
      talkTimeMins: 0,
      dispositionMap: {},
      queueRemainingCount: 0,
      unassignedLeadsCount: 0,
      todayCallbacksCount: 0,
      todayDemosCount: 0,
      overdueTasksCount: 0,
      activeDealsCount: 0,
      activePipelineValue: 0.0,
      wonDealsCount: 0,
      wonRevenueInPeriod: 0.0,
      verifiedRevenue: 0.0,
      winRate: 0,
      totalLeadsCount: 0,
      todayAgenda: [],
      leadsByStatus: [],
      allDealsByStage: [],
      teamMembers: [],
    );
  }
}

class AgendaItem {
  final String id;
  final String taskType;
  final String scheduledTime;
  final String status;
  final String? notes;
  final String? contactName;
  final String? phoneNumber;
  final String? companyName;

  AgendaItem({
    required this.id,
    required this.taskType,
    required this.scheduledTime,
    required this.status,
    this.notes,
    this.contactName,
    this.phoneNumber,
    this.companyName,
  });

  factory AgendaItem.fromJson(Map<String, dynamic> json) {
    final lead = json['lead'] as Map<String, dynamic>?;
    return AgendaItem(
      id: json['id']?.toString() ?? '',
      taskType: json['taskType']?.toString() ?? 'callback',
      scheduledTime: json['scheduledTime']?.toString() ?? '',
      status: json['status']?.toString() ?? 'pending',
      notes: json['notes']?.toString(),
      contactName: lead?['contactName']?.toString() ?? json['contactName']?.toString(),
      phoneNumber: lead?['phoneNumber']?.toString() ?? json['phoneNumber']?.toString(),
      companyName: lead?['companyName']?.toString() ?? json['companyName']?.toString(),
    );
  }
}

class LeadStatusCount {
  final String status;
  final int count;

  LeadStatusCount({required this.status, required this.count});

  factory LeadStatusCount.fromJson(Map<String, dynamic> json) {
    return LeadStatusCount(
      status: json['status']?.toString() ?? '',
      count: (json['count'] is num)
          ? (json['count'] as num).toInt()
          : int.tryParse(json['count']?.toString() ?? '0') ?? 0,
    );
  }
}
