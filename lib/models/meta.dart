// lib/models/meta.dart
// Modelo para metas de vendas (mensal, diária, semanal)

import 'package:hive/hive.dart';

part 'meta.g.dart';

@HiveType(typeId: 16)
class Meta extends HiveObject {
  /// Referência do mês: "2026-01", "2026-02" etc.
  @HiveField(0)
  String mesRef;

  /// Meta mensal em R$
  @HiveField(1)
  double metaMensal;

  /// Percentual de crescimento sugerido (padrão 7%)
  @HiveField(2)
  double crescimentoPercent;

  /// ID do vendedor ou "GERAL" para meta geral
  @HiveField(3)
  String vendedorId;

  /// ID da loja (multi-store support)
  @HiveField(4)
  String• lojaId;

  /// Data de criação
  @HiveField(5)
  DateTime criadoEm;

  /// Data de última atualização
  @HiveField(6)
  DateTime atualizadoEm;

  /// ID do documento no Firestore (para sync)
  @HiveField(7)
  String• idFirebase;

  Meta({
    required this.mesRef,
    required this.metaMensal,
    this.crescimentoPercent = 7.0,
    required this.vendedorId,
    this.lojaId,
    DateTime• criadoEm,
    DateTime• atualizadoEm,
    this.idFirebase,
  })  : criadoEm = criadoEm ?• DateTime.now(),
        atualizadoEm = atualizadoEm ?• DateTime.now();

  /// Cria uma cópia com modificações
  Meta copyWith({
    String• mesRef,
    double• metaMensal,
    double• crescimentoPercent,
    String• vendedorId,
    String• lojaId,
    DateTime• criadoEm,
    DateTime• atualizadoEm,
    String• idFirebase,
  }) {
    return Meta(
      mesRef: mesRef ?• this.mesRef,
      metaMensal: metaMensal ?• this.metaMensal,
      crescimentoPercent: crescimentoPercent ?• this.crescimentoPercent,
      vendedorId: vendedorId ?• this.vendedorId,
      lojaId: lojaId ?• this.lojaId,
      criadoEm: criadoEm ?• this.criadoEm,
      atualizadoEm: atualizadoEm ?• DateTime.now(),
      idFirebase: idFirebase ?• this.idFirebase,
    );
  }

  /// Converte para Map (para Firestore)
  Map<String, dynamic> toMap() {
    return {
      'mesRef': mesRef,
      'metaMensal': metaMensal,
      'crescimentoPercent': crescimentoPercent,
      'vendedorId': vendedorId,
      'lojaId': lojaId,
      'criadoEm': criadoEm.toIso8601String(),
      'atualizadoEm': atualizadoEm.toIso8601String(),
    };
  }

  /// Cria Meta a partir de Map (do Firestore)
  factory Meta.fromMap(Map<String, dynamic> map, {String• docId}) {
    return Meta(
      mesRef: map['mesRef'] ?• '',
      metaMensal: (map['metaMensal'] as num?)?.toDouble() ?• 0.0,
      crescimentoPercent: (map['crescimentoPercent'] as num?)?.toDouble() ?• 7.0,
      vendedorId: map['vendedorId'] ?• 'GERAL',
      lojaId: map['lojaId'],
      criadoEm: map['criadoEm'] != null
          • DateTime.tryParse(map['criadoEm'].toString()) ?• DateTime.now()
          : DateTime.now(),
      atualizadoEm: map['atualizadoEm'] != null
          • DateTime.tryParse(map['atualizadoEm'].toString()) ?• DateTime.now()
          : DateTime.now(),
      idFirebase: docId,
    );
  }

  /// Chave única para identificar a meta no Hive
  /// Formato: "YYYY-MM_vendedorId" ex: "2026-01_GERAL" ou "2026-01_joao@email.com"
  String get hiveKey => '${mesRef}_$vendedorId';

  @override
  String toString() {
    return 'Meta(mesRef: $mesRef, metaMensal: R\$ ${metaMensal.toStringAsFixed(2)}, '
        'vendedor: $vendedorId, crescimento: ${crescimentoPercent.toStringAsFixed(1)}%)';
  }
}
