class DashboardStats {
  final int totalCalls;
  final int uniqueDials;
  final int connectedCalls;
  final int connectRate;
  final int talkTimeMins;
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
  final int winRate;
  final int totalLeadsCount;
  final List<AgendaItem> todayAgenda;
  final List<LeadStatusCount> leadsByStatus;

  DashboardStats({
    required this.totalCalls,
    required this.uniqueDials,
    required this.connectedCalls,
    required this.connectRate,
    required this.talkTimeMins,
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
    required this.winRate,
    required this.totalLeadsCount,
    required this.todayAgenda,
    required this.leadsByStatus,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    final dispMap = <String, int>{};
    if (json['dispositionMap'] is Map) {
      (json['dispositionMap'] as Map).forEach((k, v) {
        dispMap[k.toString()] = (v is num) ? v.toInt() : 0;
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

    return DashboardStats(
      totalCalls: json['totalCalls'] ?? 0,
      uniqueDials: json['uniqueDials'] ?? 0,
      connectedCalls: json['connectedCalls'] ?? 0,
      connectRate: json['connectRate'] ?? 0,
      talkTimeMins: json['talkTimeMins'] ?? 0,
      dispositionMap: dispMap,
      queueRemainingCount: json['queueRemainingCount'] ?? 0,
      unassignedLeadsCount: json['unassignedLeadsCount'] ?? 0,
      todayCallbacksCount: json['todayCallbacksCount'] ?? 0,
      todayDemosCount: json['todayDemosCount'] ?? 0,
      overdueTasksCount: json['overdueTasksCount'] ?? 0,
      activeDealsCount: json['activeDealsCount'] ?? 0,
      activePipelineValue: (json['activePipelineValue'] as num?)?.toDouble() ?? 0.0,
      wonDealsCount: json['wonDealsCount'] ?? 0,
      wonRevenueInPeriod: (json['wonRevenueInPeriod'] as num?)?.toDouble() ?? 0.0,
      winRate: json['winRate'] ?? 0,
      totalLeadsCount: json['totalLeadsCount'] ?? 0,
      todayAgenda: agendaList,
      leadsByStatus: statusList,
    );
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
      winRate: 0,
      totalLeadsCount: 0,
      todayAgenda: [],
      leadsByStatus: [],
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
      count: (json['count'] is num) ? (json['count'] as num).toInt() : 0,
    );
  }
}
