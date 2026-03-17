// lib/motor_crescimento/models/sugestao_campanha.dart
// Sugestão de campanha gerada pelo Motor de Crescimento IA (Etapa 2).

/// Sugestão de campanha para uma oportunidade detectada.
class SugestaoCampanha {
  final String tipoCampanha;
  final String titulo;
  final String descricao;
  final double percentualDesconto;
  final String codigoCupomSugerido;
  final String textoPromocao;
  final String mensagemWhatsApp;
  final String legendaInstagram;

  const SugestaoCampanha({
    required this.tipoCampanha,
    required this.titulo,
    required this.descricao,
    required this.percentualDesconto,
    required this.codigoCupomSugerido,
    required this.textoPromocao,
    required this.mensagemWhatsApp,
    required this.legendaInstagram,
  });
}
