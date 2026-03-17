// lib/motor_crescimento/models/campanha_motor_result.dart
// Resultado da execução de campanha do Motor de Crescimento IA (Etapa 3).

import 'campanha_motor.dart';

/// Resultado da execução de uma campanha.
class CampanhaMotorResult {
  final bool sucesso;
  final CampanhaMotor? campanha;
  final String mensagem;
  final bool cupomCriado;
  final bool linkGerado;

  const CampanhaMotorResult({
    required this.sucesso,
    this.campanha,
    required this.mensagem,
    this.cupomCriado = false,
    this.linkGerado = false,
  });

  static CampanhaMotorResult sucessoFull({
    required CampanhaMotor campanha,
  }) {
    return CampanhaMotorResult(
      sucesso: true,
      campanha: campanha,
      mensagem: 'Campanha criada com sucesso.',
      cupomCriado: campanha.codigoCupom.isNotEmpty,
      linkGerado: campanha.linkPromocao.isNotEmpty,
    );
  }

  static CampanhaMotorResult sucessoFallback({
    required CampanhaMotor campanha,
    required String mensagem,
  }) {
    return CampanhaMotorResult(
      sucesso: true,
      campanha: campanha,
      mensagem: mensagem,
      cupomCriado: false,
      linkGerado: campanha.linkPromocao.isNotEmpty,
    );
  }

  static CampanhaMotorResult erro(String mensagem) {
    return CampanhaMotorResult(
      sucesso: false,
      mensagem: mensagem,
      cupomCriado: false,
      linkGerado: false,
    );
  }
}
