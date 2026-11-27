class CallSyncItem {
  final String id;
  final String? leadId;
  final String phoneNumber;
  final int durationSeconds;
  final String disposition;
  final String callTimestamp;
  final String? remark;
  final String? recordingUrl;
  final String logSource;
  final String? leadContactName;
  final String? leadCompanyName;
  final String? leadStatus;
  final bool isInterested;
  final int? rnrAttempt;
  bool isSynced;

  CallSyncItem({
    required this.id,
    this.leadId,
    required this.phoneNumber,
    required this.durationSeconds,
    required this.disposition,
    required this.callTimestamp,
    this.remark,
    this.recordingUrl,
    this.logSource = 'apk_manual',
    this.leadContactName,
    this.leadCompanyName,
    this.leadStatus,
    this.isInterested = false,
    this.rnrAttempt,
    this.isSynced = false,
  });

  factory CallSyncItem.fromJson(Map<String, dynamic> json) {
    final leadMap = json['lead'] is Map ? json['lead'] as Map<String, dynamic> : null;
    return CallSyncItem(
      id: json['id']?.toString() ?? '',
      leadId: json['leadId']?.toString() ?? leadMap?['id']?.toString(),
      phoneNumber: json['phoneNumber'] ?? leadMap?['phoneNumber'] ?? '',
      durationSeconds: json['durationSeconds'] is int ? json['durationSeconds'] : (json['durationSeconds'] is num ? (json['durationSeconds'] as num).toInt() : 0),
      disposition: json['disposition'] ?? 'Connected',
      callTimestamp: json['callTimestamp'] ?? DateTime.now().toUtc().toIso8601String(),
      remark: json['remark'],
      recordingUrl: json['recordingUrl'] ?? json['recording_url'],
      logSource: json['logSource'] ?? 'apk_manual',
      leadContactName: leadMap?['contactName']?.toString() ?? json['leadContactName']?.toString(),
      leadCompanyName: leadMap?['companyName']?.toString() ?? json['leadCompanyName']?.toString(),
      leadStatus: leadMap?['status']?.toString() ?? json['leadStatus']?.toString(),
      isInterested: json['isInterested'] == true,
      rnrAttempt: json['rnrAttempt'] is num ? (json['rnrAttempt'] as num).toInt() : null,
      isSynced: json['isSynced'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'leadId': leadId,
      'phoneNumber': phoneNumber,
      'durationSeconds': durationSeconds,
      'disposition': disposition,
      'callTimestamp': callTimestamp,
      'remark': remark,
      'recordingUrl': recordingUrl,
      'logSource': logSource,
      if (leadContactName != null) 'leadContactName': leadContactName,
      if (leadCompanyName != null) 'leadCompanyName': leadCompanyName,
      if (leadStatus != null) 'leadStatus': leadStatus,
      'isInterested': isInterested,
      if (rnrAttempt != null) 'rnrAttempt': rnrAttempt,
      'isSynced': isSynced,
    };
  }
}
