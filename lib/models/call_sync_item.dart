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
    this.isSynced = false,
  });

  factory CallSyncItem.fromJson(Map<String, dynamic> json) {
    return CallSyncItem(
      id: json['id'] ?? '',
      leadId: json['leadId'],
      phoneNumber: json['phoneNumber'] ?? '',
      durationSeconds: json['durationSeconds'] is int ? json['durationSeconds'] : 0,
      disposition: json['disposition'] ?? 'Connected',
      callTimestamp: json['callTimestamp'] ?? DateTime.now().toIso8601String(),
      remark: json['remark'],
      recordingUrl: json['recordingUrl'] ?? json['recording_url'],
      logSource: json['logSource'] ?? 'apk_manual',
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
      'isSynced': isSynced,
    };
  }
}
