// lib/services/master_config_service.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../models/master_config.dart';

/// Serviço para gerenciar configurações globais do aplicativo (apenas root)
class MasterConfigService {
  static FirebaseFirestore? _firestoreOverride;
  static FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  @visibleForTesting
  static set firestoreForTesting(FirebaseFirestore? value) =>
      _firestoreOverride = value;

  static const String _masterConfigDoc = 'master_config';
  static const String _masterConfigCollection = 'app_config';

  /// Box Hive de versões antigas: guardava o documento inteiro (incluindo senha e credenciais
  /// legadas) e era relido sem consultar o Firestore, o que permitia regravar campos removidos.
  static const String _legacyHiveBox = 'master_config';
  static bool _legacyCachePurged = false;

  static Future<void> _purgeLegacyCache() async {
    if (_legacyCachePurged) return;
    _legacyCachePurged = true;
    try {
      await Hive.deleteBoxFromDisk(_legacyHiveBox);
    } catch (e) {
      debugPrint('⚠️ [MasterConfig] cache legado não removido (type=${e.runtimeType})');
    }
  }

  /// Payload gravado no Firestore: só os campos de [MasterConfig.allowedFields].
  @visibleForTesting
  static Map<String, dynamic> buildWritePayload(MasterConfig config) {
    final map = config.toMap();
    return {
      for (final key in MasterConfig.allowedFields)
        if (map.containsKey(key)) key: map[key],
    };
  }

  /// Carrega configuração mestre sempre do Firestore (fonte autoritativa).
  static Future<MasterConfig> loadMasterConfig() async {
    await _purgeLegacyCache();
    try {
      final doc = await _firestore
          .collection(_masterConfigCollection)
          .doc(_masterConfigDoc)
          .get();
      final data = doc.data();
      return data == null ? MasterConfig() : MasterConfig.fromMap(data);
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final isPermissionDenied = msg.contains('permission') && msg.contains('denied');
      if (isPermissionDenied) {
        debugPrint('⚠️ [MasterConfig] PERMISSION_DENIED ao ler app_config/master_config. Usando config padrão (fallback seguro).');
      } else {
        debugPrint('❌ Erro ao carregar master config (type=${e.runtimeType})');
      }
      return MasterConfig();
    }
  }

  static const int _maxAuditLogEntries = 50;

  static MasterConfig _addAuditEntry(
    MasterConfig config,
    String action,
    String user,
    String details,
  ) {
    final settings = Map<String, dynamic>.from(config.globalSettings);
    final log = List<Map<String, dynamic>>.from(
      (settings['auditLog'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)) ?? [],
    );
    log.insert(0, {
      'timestamp': DateTime.now().toIso8601String(),
      'action': action,
      'user': user,
      'details': details,
    });
    if (log.length > _maxAuditLogEntries) {
      log.removeRange(_maxAuditLogEntries, log.length);
    }
    settings['auditLog'] = log;
    return config.copyWith(globalSettings: settings);
  }

  /// Salva configuração mestre no Firestore (somente campos da allowlist)
  static Future<void> saveMasterConfig(
    MasterConfig config, {
    required String updatedBy,
    String? auditAction,
    String? auditDetails,
  }) async {
    try {
      if (auditAction != null && auditDetails != null) {
        config = _addAuditEntry(config, auditAction, updatedBy, auditDetails);
      }
      config = config.copyWith(
        lastUpdated: DateTime.now(),
        updatedBy: updatedBy,
      );

      await _firestore
          .collection(_masterConfigCollection)
          .doc(_masterConfigDoc)
          .set(buildWritePayload(config), SetOptions(merge: true));
      debugPrint('✅ Master config sincronizado com Firestore');
    } catch (e) {
      debugPrint('❌ Erro ao salvar master config (type=${e.runtimeType})');
      rethrow;
    }
  }

  /// Adiciona usuário com acesso ilimitado
  static Future<void> grantUnlimitedAccess({
    required String userEmail,
    required String grantedBy,
  }) async {
    final config = await loadMasterConfig();

    if (!config.usersWithUnlimitedAccess.contains(userEmail)) {
      final updatedList = [...config.usersWithUnlimitedAccess, userEmail];
      final updatedConfig =
          config.copyWith(usersWithUnlimitedAccess: updatedList);
      await saveMasterConfig(
        updatedConfig,
        updatedBy: grantedBy,
        auditAction: 'Acesso ilimitado concedido',
        auditDetails: userEmail,
      );

      // Atualiza também no documento do usuário
      await _firestore.collection('usuarios').doc(userEmail).set({
        'unlimitedAccess': true,
        'grantedBy': grantedBy,
        'grantedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Remove acesso ilimitado de um usuário
  static Future<void> revokeUnlimitedAccess({
    required String userEmail,
    required String revokedBy,
  }) async {
    final config = await loadMasterConfig();

    if (config.usersWithUnlimitedAccess.contains(userEmail)) {
      final updatedList = config.usersWithUnlimitedAccess
          .where((email) => email != userEmail)
          .toList();
      final updatedConfig =
          config.copyWith(usersWithUnlimitedAccess: updatedList);
      await saveMasterConfig(
        updatedConfig,
        updatedBy: revokedBy,
        auditAction: 'Acesso ilimitado revogado',
        auditDetails: userEmail,
      );

      // Atualiza também no documento do usuário
      await _firestore.collection('usuarios').doc(userEmail).set({
        'unlimitedAccess': false,
        'revokedBy': revokedBy,
        'revokedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Verifica se um usuário tem acesso ilimitado
  static Future<bool> hasUnlimitedAccess(String userEmail) async {
    try {
      final config = await loadMasterConfig();
      return config.usersWithUnlimitedAccess.contains(userEmail);
    } catch (e) {
      debugPrint('❌ Erro ao verificar acesso ilimitado (type=${e.runtimeType})');
      return false;
    }
  }

  /// Stream de configurações (para UI reativa)
  static Stream<MasterConfig> streamMasterConfig() {
    return _firestore
        .collection(_masterConfigCollection)
        .doc(_masterConfigDoc)
        .snapshots()
        .map((doc) {
      if (doc.exists) {
        return MasterConfig.fromMap(doc.data()!);
      }
      return MasterConfig();
    });
  }

  /// Atualiza configuração global específica
  static Future<void> updateGlobalSetting({
    required String key,
    required dynamic value,
    required String updatedBy,
    String? auditAction,
    String? auditDetails,
  }) async {
    final config = await loadMasterConfig();
    final updatedSettings = Map<String, dynamic>.from(config.globalSettings);
    updatedSettings[key] = value;

    final updatedConfig = config.copyWith(globalSettings: updatedSettings);
    await saveMasterConfig(
      updatedConfig,
      updatedBy: updatedBy,
      auditAction: auditAction ?? 'Configuração alterada',
      auditDetails: auditDetails ?? '$key = $value',
    );
  }

  /// Obtém configuração global específica
  static Future<dynamic> getGlobalSetting(String key,
      {dynamic defaultValue}) async {
    try {
      final config = await loadMasterConfig();
      return config.globalSettings[key] ?? defaultValue;
    } catch (e) {
      debugPrint('❌ Erro ao obter configuração $key (type=${e.runtimeType})');
      return defaultValue;
    }
  }

  /// Modo manutenção
  static Future<bool> getMaintenanceMode() async {
    return (await getGlobalSetting('maintenanceMode', defaultValue: false)) as bool;
  }

  static Future<String> getMaintenanceMessage() async {
    return (await getGlobalSetting(
      'maintenanceMessage',
      defaultValue: 'Em manutenção. Volte em breve.',
    )) as String;
  }

  static Future<void> setMaintenanceMode({
    required bool enabled,
    String? message,
    required String updatedBy,
  }) async {
    final config = await loadMasterConfig();
    final settings = Map<String, dynamic>.from(config.globalSettings);
    settings['maintenanceMode'] = enabled;
    if (message != null) settings['maintenanceMessage'] = message;
    final updated = config.copyWith(globalSettings: settings);
    await saveMasterConfig(
      updated,
      updatedBy: updatedBy,
      auditAction: enabled ? 'Modo manutenção ativado' : 'Modo manutenção desativado',
      auditDetails: message ?? (enabled ? 'App indisponível' : 'App disponível'),
    );
  }

  /// Telefone de suporte (exibido na tela Ajuda para dúvidas)
  static Future<String> getSupportPhone() async {
    final v = await getGlobalSetting('supportPhone', defaultValue: '');
    return v is String ? v : '';
  }

  static Future<void> setSupportPhone({
    required String phone,
    required String updatedBy,
  }) async {
    await updateGlobalSetting(
      key: 'supportPhone',
      value: phone.trim(),
      updatedBy: updatedBy,
      auditAction: 'Telefone de suporte alterado',
      auditDetails: 'Novo número: ${phone.trim().isEmpty ? "(vazio)" : phone.trim()}',
    );
  }

  /// Feature flags
  static Future<bool> getFeatureFlag(String key, {bool defaultValue = true}) async {
    final v = await getGlobalSetting('feature_$key', defaultValue: defaultValue);
    return v is bool ? v : defaultValue;
  }

  static Future<void> setFeatureFlag({
    required String key,
    required bool value,
    required String updatedBy,
  }) async {
    await updateGlobalSetting(
      key: 'feature_$key',
      value: value,
      updatedBy: updatedBy,
    );
  }

  /// Log de auditoria
  static Future<List<Map<String, dynamic>>> getAuditLog() async {
    try {
      final config = await loadMasterConfig();
      final log = config.globalSettings['auditLog'] as List?;
      if (log == null) return [];
      return log.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('❌ Erro ao obter audit log (type=${e.runtimeType})');
      return [];
    }
  }

  /// Adiciona múltiplos usuários com acesso ilimitado
  static Future<int> grantBulkUnlimitedAccess({
    required List<String> emails,
    required String grantedBy,
  }) async {
    int added = 0;
    for (final email in emails) {
      final trimmed = email.trim().toLowerCase();
      if (trimmed.isEmpty) continue;
      try {
        await grantUnlimitedAccess(userEmail: trimmed, grantedBy: grantedBy);
        added++;
      } catch (_) {}
    }
    return added;
  }

  /// Exporta config (o model não carrega dados sensíveis)
  static Future<String> exportConfigJson() async {
    final config = await loadMasterConfig();
    return const JsonEncoder.withIndent('  ').convert(buildWritePayload(config));
  }

  /// Importa config de JSON (merge globalSettings apenas)
  static Future<void> importConfigJson(String json, {required String updatedBy}) async {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final importedSettings = map['globalSettings'] as Map<String, dynamic>?;
    if (importedSettings == null || importedSettings.isEmpty) return;

    final config = await loadMasterConfig();
    final settings = Map<String, dynamic>.from(config.globalSettings);
    for (final e in importedSettings.entries) {
      if (e.key != 'auditLog') {
        settings[e.key] = e.value;
      }
    }
    final updated = config.copyWith(globalSettings: settings);
    await saveMasterConfig(
      updated,
      updatedBy: updatedBy,
      auditAction: 'Config importada',
      auditDetails: 'Importação via JSON',
    );
  }
}