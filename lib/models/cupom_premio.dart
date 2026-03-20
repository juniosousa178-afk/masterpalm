// lib/models/cupom_premio.dart

import 'package:hive/hive.dart';

part 'cupom_premio.g.dart';

@HiveType(typeId: 14)
class CupomPremio extends HiveObject {
  @HiveField(0)
  String codigo; // Código único do cupom

  @HiveField(1)
  String tipo; // 'percentual' | 'valor' | 'frete_gratis'

  @HiveField(2)
  double valorDesconto; // Valor ou percentual de desconto

  @HiveField(3)
  DateTime dataExpiracao; // Válido por 60 dias

  @HiveField(4)
  bool usado; // Se já foi utilizado

  @HiveField(5)
  DateTime? dataUso; // Quando foi usado

  @HiveField(6)
  String? vendaId; // ID da venda onde foi usado

  @HiveField(7)
  String premioOriginal; // Descrição do prêmio original

  @HiveField(8)
  String lojaId; // ID da loja

  @HiveField(9)
  String? clienteEmail; // Email do cliente (opcional)

  @HiveField(10)
  DateTime dataCriacao; // Quando ganhou na roleta

  CupomPremio({
    required this.codigo,
    required this.tipo,
    required this.valorDesconto,
    required this.dataExpiracao,
    this.usado = false,
    this.dataUso,
    this.vendaId,
    required this.premioOriginal,
    required this.lojaId,
    this.clienteEmail,
    required this.dataCriacao,
  });

  /// Verifica se o cupom está válido
  bool get isValido {
    if (usado) return false;
    if (DateTime.now().isAfter(dataExpiracao)) return false;
    return true;
  }

  /// Verifica se o cupom expirou
  bool get expirou {
    return DateTime.now().isAfter(dataExpiracao);
  }

  /// Dias restantes para expirar
  int get diasRestantes {
    if (expirou) return 0;
    return dataExpiracao.difference(DateTime.now()).inDays;
  }

  /// Marca cupom como usado
  Future<void> marcarComoUsado(String vendaId) async {
    usado = true;
    dataUso = DateTime.now();
    this.vendaId = vendaId;
    await save();
  }

  /// Gera código único de cupom
  static String gerarCodigo() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp % 10000).toString().padLeft(4, '0');
    return 'PREMIO-$random';
  }

  /// Calcula o desconto para um valor de compra
  double calcularDesconto(double valorCompra) {
    if (!isValido) return 0.0;

    switch (tipo) {
      case 'percentual':
        return valorCompra * (valorDesconto / 100);
      case 'valor':
        return valorDesconto.clamp(0, valorCompra);
      case 'frete_gratis':
        return 0.0; // O frete será zerado separadamente
      default:
        return 0.0;
    }
  }

  /// Descrição formatada do cupom
  String get descricaoFormatada {
    switch (tipo) {
      case 'percentual':
        return '${valorDesconto.toStringAsFixed(0)}% de desconto';
      case 'valor':
        return 'R\$ ${valorDesconto.toStringAsFixed(2)} de desconto';
      case 'frete_gratis':
        return 'Frete Grátis';
      default:
        return premioOriginal;
    }
  }

  @override
  String toString() => '$codigo - $descricaoFormatada';
}
