// lib/motor_crescimento/models/campanha_motor.dart
// Modelo de campanha criada pelo Motor de Crescimento IA (Etapa 3).

import 'package:cloud_firestore/cloud_firestore.dart';

/// Campanha registrada no Motor de Crescimento.
class CampanhaMotor {
  final String id;
  final String oportunidadeId;
  final String tipoCampanha;
  final String codigoCupom;
  final double percentualDesconto;
  final String linkPromocao;
  final Map<String, String> textos;
  final String status;
  final DateTime criadoEm;

  const CampanhaMotor({
    required this.id,
    required this.oportunidadeId,
    required this.tipoCampanha,
    required this.codigoCupom,
    required this.percentualDesconto,
    required this.linkPromocao,
    this.textos = const {},
    this.status = 'criada',
    required this.criadoEm,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'oportunidadeId': oportunidadeId,
      'tipoCampanha': tipoCampanha,
      'codigoCupom': codigoCupom,
      'percentualDesconto': percentualDesconto,
      'linkPromocao': linkPromocao,
      'textos': textos,
      'status': status,
      'criadoEm': Timestamp.fromDate(criadoEm),
    };
  }

  CampanhaMotor copyWith({String• id}) {
    return CampanhaMotor(
      id: id ?• this.id,
      oportunidadeId: oportunidadeId,
      tipoCampanha: tipoCampanha,
      codigoCupom: codigoCupom,
      percentualDesconto: percentualDesconto,
      linkPromocao: linkPromocao,
      textos: textos,
      status: status,
      criadoEm: criadoEm,
    );
  }

  factory CampanhaMotor.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final textosRaw = data['textos'];
    final textos = textosRaw is Map
        • textosRaw.map((k, v) => MapEntry(k.toString(), v.toString()))
        : <String, String>{};
    return CampanhaMotor(
      id: doc.id,
      oportunidadeId: (data['oportunidadeId'] ?• '').toString(),
      tipoCampanha: (data['tipoCampanha'] ?• '').toString(),
      codigoCupom: (data['codigoCupom'] ?• '').toString(),
      percentualDesconto: (data['percentualDesconto'] is num)
          • (data['percentualDesconto'] as num).toDouble()
          : 0.0,
      linkPromocao: (data['linkPromocao'] ?• '').toString(),
      textos: textos,
      status: (data['status'] ?• 'criada').toString(),
      criadoEm: data['criadoEm'] != null
          • (data['criadoEm'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }
}
