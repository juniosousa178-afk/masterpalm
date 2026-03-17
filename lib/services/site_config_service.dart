// lib/services/site_config_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Configurações do site de divulgação (landing page)
/// Salvas em Firestore para edição pelo programador no APK
class SiteConfig {
  final String apkDownloadUrl;
  final String appWebUrl;
  final String supportWhatsappUrl;
  final String instagramUrl;
  final String supportEmail;
  final String apkVersion;
  final String apkSize;
  final String apkReleaseDate;
  final String apkChangelog;
  final DateTime? lastUpdated;
  final String? updatedBy;

  SiteConfig({
    this.apkDownloadUrl = 'https://mastepalm.com.br/downloads/masterpalm.apk',
    this.appWebUrl = 'https://app.mastepalm.com.br',
    this.supportWhatsappUrl = 'https://wa.me/55SEUNUMERO',
    this.instagramUrl = 'https://instagram.com/SEUINSTAGRAM',
    this.supportEmail = 'suporte@SEUDOMINIO.COM',
    this.apkVersion = '1.0.0',
    this.apkSize = '~25 MB',
    this.apkReleaseDate = '2025',
    this.apkChangelog = '',
    this.lastUpdated,
    this.updatedBy,
  });

  /// Normaliza URL do Instagram: "username" ou "@user" -> "https://instagram.com/username"
  static String normalizeInstagram(String value) {
    final t = value.trim();
    if (t.isEmpty) return t;
    if (t.startsWith('http://') || t.startsWith('https://')) {
      return t.replaceAll(RegExp(r'/+$'), '');
    }
    final user = t.replaceFirst(RegExp(r'^@'), '').replaceFirst(RegExp(r'^https?://(www\.)?instagram\.com/', caseSensitive: false), '').split('/').first.trim();
    return user.isEmpty ? t : 'https://instagram.com/$user';
  }

  Map<String, dynamic> toMap() => {
        'apkDownloadUrl': apkDownloadUrl,
        'appWebUrl': appWebUrl,
        'supportWhatsappUrl': supportWhatsappUrl,
        'instagramUrl': instagramUrl,
        'supportEmail': supportEmail,
        'apkVersion': apkVersion,
        'apkSize': apkSize,
        'apkReleaseDate': apkReleaseDate,
        'apkChangelog': apkChangelog,
        'lastUpdated': lastUpdated?.toIso8601String(),
        'updatedBy': updatedBy,
      };

  factory SiteConfig.fromMap(Map<String, dynamic> m) {
    final apkUrl = (m['apkDownloadUrl'] ?? '').toString();
    final useDefaultApk = apkUrl.isEmpty || apkUrl.contains('SEU-LINK-AQUI') || apkUrl.contains('seu-link-aqui');
    return SiteConfig(
        apkDownloadUrl: useDefaultApk ? 'https://mastepalm.com.br/downloads/masterpalm.apk' : apkUrl,
        appWebUrl: (m['appWebUrl'] ?? 'https://app.mastepalm.com.br').toString(),
        supportWhatsappUrl: (m['supportWhatsappUrl'] ?? '').toString(),
        instagramUrl: (m['instagramUrl'] ?? '').toString(),
        supportEmail: (m['supportEmail'] ?? '').toString(),
        apkVersion: (m['apkVersion'] ?? '1.0.0').toString(),
        apkSize: (m['apkSize'] ?? '~25 MB').toString(),
        apkReleaseDate: (m['apkReleaseDate'] ?? '2025').toString(),
        apkChangelog: (m['apkChangelog'] ?? '').toString(),
        lastUpdated: m['lastUpdated'] != null ? DateTime.tryParse(m['lastUpdated'].toString()) : null,
        updatedBy: m['updatedBy']?.toString(),
      );
  }
}

class SiteConfigService {
  SiteConfigService._();

  static final _firestore = FirebaseFirestore.instance;
  static const String _collection = 'app_config';
  static const String _docId = 'site_config';

  /// Carrega configuração do site do Firestore
  static Future<SiteConfig> load() async {
    try {
      final doc = await _firestore.collection(_collection).doc(_docId).get();
      if (doc.exists && doc.data() != null) {
        return SiteConfig.fromMap(doc.data()!);
      }
    } catch (e) {
      // ignore
    }
    return SiteConfig();
  }

  /// Salva configuração do site no Firestore
  static Future<void> save(SiteConfig config, {required String updatedBy}) async {
    final data = config.toMap();
    data['lastUpdated'] = DateTime.now().toIso8601String();
    data['updatedBy'] = updatedBy;

    await _firestore.collection(_collection).doc(_docId).set(data, SetOptions(merge: true));
  }
}
