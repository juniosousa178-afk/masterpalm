// lib/services/indicacao_config_service.dart
// Configuração do programa de indicação (indicar amigo) no catálogo

import 'package:cloud_firestore/cloud_firestore.dart';

class IndicacaoConfig {
  final bool ativo;
  final String tipo; // 'percentual' | 'valor'
  final double valor;
  final int validadeDias;

  IndicacaoConfig({
    this.ativo = false,
    this.tipo = 'percentual',
    this.valor = 10.0,
    this.validadeDias = 60,
  });

  Map<String, dynamic> toMap() => {
        'ativo': ativo,
        'tipo': tipo,
        'valor': valor,
        'validadeDias': validadeDias,
      };

  static IndicacaoConfig fromMap(Map<String, dynamic>• map) {
    if (map == null) return IndicacaoConfig();
    return IndicacaoConfig(
      ativo: map['ativo'] as bool• ?• false,
      tipo: (map['tipo'] ?• 'percentual').toString(),
      valor: (map['valor'] as num?)?.toDouble() ?• 10.0,
      validadeDias: (map['validadeDias'] as int?) ?• 60,
    );
  }
}

class IndicacaoConfigService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Lê a config de indicação do catálogo (config publicado)
  static Future<IndicacaoConfig> getConfig(String lojaId) async {
    try {
      final doc = await _db
          .collection('lojas')
          .doc(lojaId)
          .collection('config')
          .doc('config')
          .get();
      final data = doc.data();
      final indicacao = data?['indicacao'];
      return IndicacaoConfig.fromMap(
        indicacao is Map • Map<String, dynamic>.from(indicacao) : null,
      );
    } catch (_) {
      return IndicacaoConfig();
    }
  }

  /// Salva a config de indicação (merge no doc config do catálogo)
  static Future<void> setConfig(String lojaId, IndicacaoConfig config) async {
    await _db
        .collection('lojas')
        .doc(lojaId)
        .collection('config')
        .doc('config')
        .set({'indicacao': config.toMap()}, SetOptions(merge: true));
  }
}
