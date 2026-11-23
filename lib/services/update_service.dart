import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'storage_service.dart';

class AppUpdateInfo {
  final String latestVersion;
  final int buildNumber;
  final String downloadUrl;
  final List<String> releaseNotes;
  final bool isMandatory;
  final int minSupportedBuild;

  AppUpdateInfo({
    required this.latestVersion,
    required this.buildNumber,
    required this.downloadUrl,
    required this.releaseNotes,
    this.isMandatory = false,
    this.minSupportedBuild = 1,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    List<String> notes = [];
    if (json['releaseNotes'] is List) {
      notes = (json['releaseNotes'] as List).map((e) => e.toString()).toList();
    } else if (json['releaseNotes'] is String) {
      notes = [json['releaseNotes'].toString()];
    }

    return AppUpdateInfo(
      latestVersion: json['version'] ?? json['latestVersion'] ?? '1.1.0',
      buildNumber: json['buildNumber'] is int
          ? json['buildNumber']
          : int.tryParse(json['buildNumber']?.toString() ?? '2') ?? 2,
      downloadUrl: json['downloadUrl'] ?? 'https://crm.textorasms.com/downloads/textora-dialer.apk',
      releaseNotes: notes,
      isMandatory: json['isMandatory'] == true,
      minSupportedBuild: json['minSupportedBuild'] is int
          ? json['minSupportedBuild']
          : int.tryParse(json['minSupportedBuild']?.toString() ?? '1') ?? 1,
    );
  }
}

class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  final StorageService _storage = StorageService();

  /// Check if an update is available on the server
  Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final baseUrl = await _storage.getBaseUrl();
      final url = Uri.parse('$baseUrl/api/app/version');

      final res = await http.get(url, headers: {
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        return null;
      }

      final data = jsonDecode(res.body);
      final updateInfo = AppUpdateInfo.fromJson(data);

      final packageInfo = await PackageInfo.fromPlatform();
      final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 1;

      if (updateInfo.buildNumber > currentBuild) {
        return updateInfo;
      }
      return null;
    } catch (e) {
      debugPrint('[UpdateService] Check update error: $e');
      return null;
    }
  }

  /// Interactive check - used in ProfileScreen "Check for Updates" button
  Future<void> checkAndShowPrompt(BuildContext context, {bool isManual = false}) async {
    final info = await checkForUpdate();
    if (!context.mounted) return;

    if (info != null) {
      showUpdateDialog(context, info);
    } else if (isManual) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 20),
              SizedBox(width: 10),
              Text('You are using the latest version of Textora Dialer'),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Show the Update Available Dialog
  void showUpdateDialog(BuildContext context, AppUpdateInfo info) {
    showDialog(
      context: context,
      barrierDismissible: !info.isMandatory,
      builder: (ctx) => _UpdateDialog(info: info),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final AppUpdateInfo info;

  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _downloadStatus = '';
  String? _errorMessage;

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.0;
      _downloadStatus = 'Connecting to update server...';
    });

    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(widget.info.downloadUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Server returned status ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;

      final tempDir = await getTemporaryDirectory();
      final apkFile = File('${tempDir.path}/textora-dialer-update.apk');

      if (await apkFile.exists()) {
        await apkFile.delete();
      }

      final sink = apkFile.openWrite();

      await response.stream.listen(
        (chunk) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (mounted && totalBytes > 0) {
            setState(() {
              _progress = receivedBytes / totalBytes;
              final mbReceived = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
              final mbTotal = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
              _downloadStatus = 'Downloading: $mbReceived MB / $mbTotal MB (${(_progress * 100).toInt()}%)';
            });
          }
        },
        onError: (err) {
          sink.close();
          client.close();
          if (mounted) {
            setState(() {
              _isDownloading = false;
              _errorMessage = 'Download interrupted: $err';
            });
          }
        },
        cancelOnError: true,
      ).asFuture();

      await sink.flush();
      await sink.close();
      client.close();

      if (!mounted) return;

      setState(() {
        _downloadStatus = 'Download complete! Launching installer...';
        _progress = 1.0;
      });

      // Launch the Android native package installer
      final openResult = await OpenFilex.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );

      if (openResult.type != ResultType.done) {
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _errorMessage = 'Could not open package installer: ${openResult.message}';
          });
        }
      } else {
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Update error: ${e.toString().replaceAll('Exception:', '').trim()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final bodyColor = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569);

    return PopScope(
      canPop: !widget.info.isMandatory && !_isDownloading,
      child: AlertDialog(
        backgroundColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        actionsPadding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.system_update_rounded, color: Color(0xFF10B981), size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Update Available',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: titleColor),
                  ),
                  Text(
                    'Version ${widget.info.latestVersion}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: _isDownloading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                      backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _downloadStatus,
                    style: TextStyle(fontSize: 12, color: bodyColor),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Please keep the app open while downloading.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "A new version of Textora Dialer is ready to install:",
                    style: TextStyle(fontSize: 13, color: bodyColor),
                  ),
                  const SizedBox(height: 10),
                  if (widget.info.releaseNotes.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 160),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: widget.info.releaseNotes.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (ctx, idx) => Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('• ', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                            Expanded(
                              child: Text(
                                widget.info.releaseNotes[idx],
                                style: TextStyle(fontSize: 12, color: bodyColor, height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                    ),
                  ],
                ],
              ),
        actions: _isDownloading
            ? []
            : [
                if (!widget.info.isMandatory)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Later',
                      style: TextStyle(color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                    ),
                  ),
                ElevatedButton.icon(
                  onPressed: _startDownload,
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('Update Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
      ),
    );
  }
}
