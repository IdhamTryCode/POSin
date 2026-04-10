import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/update_info.dart';

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const _githubRepo = 'IdhamTryCode/POSin';
  static const _apiUrl = 'https://api.github.com/repos/$_githubRepo/releases/latest';

  /// Marker in release body that flags a force update.
  /// Add `[force-update]` anywhere in the GitHub release notes to mandate it.
  static const _forceMarker = '[force-update]';

  final Dio _dio = Dio();

  /// Fetch latest release from GitHub. Returns null on any error.
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final pkg = await PackageInfo.fromPlatform();
      final currentVersion = pkg.version;

      final res = await _dio.get<Map<String, dynamic>>(
        _apiUrl,
        options: Options(
          headers: {'Accept': 'application/vnd.github+json'},
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      final data = res.data;
      if (data == null) return null;

      final tagName = (data['tag_name'] as String?) ?? '';
      final name = (data['name'] as String?) ?? tagName;
      final body = (data['body'] as String?) ?? '';
      final publishedRaw = data['published_at'] as String?;
      final assets = (data['assets'] as List?) ?? [];

      // Find the .apk asset
      String? apkUrl;
      int? apkSize;
      for (final a in assets) {
        if (a is Map &&
            (a['name'] as String?)?.toLowerCase().endsWith('.apk') == true) {
          apkUrl = a['browser_download_url'] as String?;
          apkSize = (a['size'] as num?)?.toInt();
          break;
        }
      }
      // Fallback: construct URL from naming convention
      apkUrl ??= 'https://github.com/$_githubRepo/releases/download/$tagName/POSin-$tagName.apk';

      final forceUpdate = body.toLowerCase().contains(_forceMarker);

      final info = UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: tagName,
        releaseName: name,
        changelog: body.replaceAll(_forceMarker, '').trim(),
        apkUrl: apkUrl,
        apkSize: apkSize,
        forceUpdate: forceUpdate,
        publishedAt: publishedRaw != null
            ? DateTime.tryParse(publishedRaw) ?? DateTime.now()
            : DateTime.now(),
      );

      return info.hasUpdate ? info : null;
    } catch (e) {
      debugPrint('UpdateService.checkForUpdate error: $e');
      return null;
    }
  }

  /// Download APK to temp directory and trigger system installer.
  /// Returns true on successful install launch (not necessarily install completion).
  Future<bool> downloadAndInstall(
    UpdateInfo info, {
    void Function(double progress, int received, int total)? onProgress,
  }) async {
    try {
      // Request install permission on Android (API 26+)
      if (Platform.isAndroid) {
        final status = await Permission.requestInstallPackages.request();
        if (!status.isGranted) {
          debugPrint('Install permission denied');
          return false;
        }
      }

      final dir = await getTemporaryDirectory();
      final filename = 'posin_${info.latestVersion}.apk';
      final filepath = '${dir.path}/$filename';

      // Delete previous file if exists
      final file = File(filepath);
      if (await file.exists()) {
        await file.delete();
      }

      await _dio.download(
        info.apkUrl,
        filepath,
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) {
            onProgress(received / total, received, total);
          }
        },
        options: Options(
          receiveTimeout: const Duration(minutes: 5),
        ),
      );

      // Trigger system installer
      final result = await OpenFilex.open(filepath);
      debugPrint('OpenFilex result: ${result.type} - ${result.message}');
      return result.type == ResultType.done;
    } catch (e) {
      debugPrint('UpdateService.downloadAndInstall error: $e');
      return false;
    }
  }
}
