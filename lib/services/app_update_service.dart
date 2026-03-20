// lib/services/app_update_service.dart
// Verifica se há nova versão disponível e permite download/atualização do APK

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart' show TargetPlatform;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'site_config_service.dart';

/// Informação sobre atualização disponível
class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final String changelog;

  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    this.changelog = '',
  });
}

class AppUpdateService {
  AppUpdateService._();

  /// Compara versões no formato semver (ex: 1.0.0, 1.2.3)
  /// Retorna true se [latest] é maior que [current]
  static bool _isNewerVersion(String current, String latest) {
    try {
      final c = _parseVersion(current);
      final l = _parseVersion(latest);
      for (int i = 0; i < 3; i++) {
        if (l[i] > c[i]) return true;
        if (l[i] < c[i]) return false;
      }
      return false; // igual
    } catch (_) {
      return false;
    }
  }

  static List<int> _parseVersion(String v) {
    final parts = v.trim().split(RegExp(r'[.\-+]'));
    return [
      int.tryParse(parts.elementAtOrNull(0) ?? '0') ?? 0,
      int.tryParse(parts.elementAtOrNull(1) ?? '0') ?? 0,
      int.tryParse(parts.elementAtOrNull(2) ?? '0') ?? 0,
    ];
  }

  /// Verifica se há atualização disponível (apenas Android, não Web)
  static Future<AppUpdateInfo?> checkForUpdate() async {
    if (kIsWeb) return null;
    // Só verifica em Android (APK distribuído fora da Play Store)
    if (defaultTargetPlatform != TargetPlatform.android) return null;

    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;
      final config = await SiteConfigService.load();
      final latestVersion = (config.apkVersion).trim();
      final downloadUrl = (config.apkDownloadUrl).trim();

      if (downloadUrl.isEmpty) return null;
      if (!downloadUrl.startsWith('http')) return null;

      if (_isNewerVersion(currentVersion, latestVersion)) {
        debugPrint(
            '📱 [AppUpdate] Nova versão disponível: $currentVersion → $latestVersion');
        return AppUpdateInfo(
          currentVersion: currentVersion,
          latestVersion: latestVersion,
          downloadUrl: downloadUrl,
          changelog: config.apkChangelog.trim(),
        );
      }
    } catch (e) {
      debugPrint('⚠️ [AppUpdate] Erro ao verificar atualização (type=${e.runtimeType})');
    }
    return null;
  }

  /// Abre o link de download do APK (navegador ou instalador)
  static Future<bool> openDownload(Uri url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('⚠️ [AppUpdate] Erro ao abrir link (type=${e.runtimeType})');
      return false;
    }
  }
}
