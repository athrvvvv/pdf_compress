import 'dart:convert';
import 'dart:io';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

class ReleaseInfo {
  final String tagName;
  final String title;
  final String notes;
  final String apkDownloadUrl;
  final int apkSize;
  final bool hasUpdate;

  ReleaseInfo({
    required this.tagName,
    required this.title,
    required this.notes,
    required this.apkDownloadUrl,
    required this.apkSize,
    required this.hasUpdate,
  });
}

class UpdateService {
  static const String currentVersion = '1.2.1';
  static const String repoOwner = 'athrvvvv';
  static const String repoName = 'pdf_compress';

  /// Checks GitHub releases for a newer version
  static Future<ReleaseInfo?> checkForUpdate() async {
    try {
      final client = HttpClient();
      client.userAgent = 'SmartPDFCompressor-App';
      final request = await client.getUrl(
        Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest'),
      );
      final response = await request.close();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;

        final tagName = (json['tag_name'] as String? ?? '').replaceFirst('v', '');
        final title = json['name'] as String? ?? 'New Update Available';
        final notes = json['body'] as String? ?? 'Bug fixes and performance improvements.';
        final assets = (json['assets'] as List<dynamic>? ?? []);

        String apkUrl = '';
        int apkSize = 0;

        // Look for arm64 APK first, or any .apk
        for (final asset in assets) {
          final name = (asset['name'] as String? ?? '').toLowerCase();
          final downloadUrl = asset['browser_download_url'] as String? ?? '';
          final size = asset['size'] as int? ?? 0;

          if (name.endsWith('.apk')) {
            if (name.contains('arm64') || apkUrl.isEmpty) {
              apkUrl = downloadUrl;
              apkSize = size;
            }
          }
        }

        final isNewer = _isVersionNewer(tagName, currentVersion);

        return ReleaseInfo(
          tagName: tagName,
          title: title,
          notes: notes,
          apkDownloadUrl: apkUrl,
          apkSize: apkSize,
          hasUpdate: isNewer,
        );
      }
    } catch (e) {
      // Offline or network error
    }
    return null;
  }

  /// Downloads the APK and triggers the native Android installer
  static Future<bool> downloadAndInstallApk(
    String downloadUrl,
    void Function(double progress, String status) onProgress,
  ) async {
    try {
      onProgress(0.05, 'Connecting to GitHub...');
      final client = HttpClient();
      client.userAgent = 'SmartPDFCompressor-App';
      final request = await client.getUrl(Uri.parse(downloadUrl));
      final response = await request.close();

      if (response.statusCode == 200 || response.statusCode == 302) {
        final totalBytes = response.contentLength;
        final appDocDir = await getApplicationDocumentsDirectory();
        final updateFile = File('${appDocDir.path}/update_latest.apk');

        if (await updateFile.exists()) {
          await updateFile.delete();
        }

        final sink = updateFile.openWrite();
        int receivedBytes = 0;

        await for (final chunk in response) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0) {
            final ratio = (receivedBytes / totalBytes).clamp(0.05, 0.95);
            final mbReceived = (receivedBytes / 1000000).toStringAsFixed(1);
            final mbTotal = (totalBytes / 1000000).toStringAsFixed(1);
            onProgress(ratio, 'Downloading: $mbReceived MB / $mbTotal MB');
          }
        }

        await sink.flush();
        await sink.close();

        onProgress(1.0, 'Starting installer...');

        // Trigger native Android package installer
        final result = await OpenFilex.open(
          updateFile.path,
          type: 'application/vnd.android.package-archive',
        );

        return result.type == ResultType.done;
      }
    } catch (e) {
      // Handle download error
    }
    return false;
  }

  /// Simple semver compare: '1.3.0' > '1.2.1' -> true
  static bool _isVersionNewer(String latest, String current) {
    try {
      final latestParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      for (int i = 0; i < mathMax(latestParts.length, currentParts.length); i++) {
        final l = i < latestParts.length ? latestParts[i] : 0;
        final c = i < currentParts.length ? currentParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
    } catch (_) {}
    return false;
  }

  static int mathMax(int a, int b) => a > b ? a : b;
}
