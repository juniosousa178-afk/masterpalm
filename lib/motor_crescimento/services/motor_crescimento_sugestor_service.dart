// lib/motor_crescimento/services/motor_crescimento_sugestor_service.dart
// Etapa 2: Sugestão de campanha para oportunidades detectadas.
// Usa AiLojaService quando disponível; fallback local sempre funciona.

import '../models/oportunidade_crescimento.dart';
import '../../services/ai_loja_service.dart';
import '../models/sugestao_campanha.dart';

class MotorCrescimentoSugestorService {
  MotorCrescimentoSugestorService._();

  /// Gera sugestão de campanha para uma oportunidade.
  /// Tenta AiLojaService; em caso de erro usa fallback local.
  static Future<SugestaoCampanha> sugerirCampanha(
    OportunidadeCrescimento oportunidade,
  ) async {
    final nome = oportunidade.entidadeNome;
    final contexto = oportunidade.descricao;

    // Textos via IA ou fallback
    String textoPromocao = '';
    String mensagemWhatsApp = '';
    String legendaInstagram = '';

    try {
      final ia = await _gerarTextosIa(nome, oportunidade.tipo, contexto);
      textoPromocao = ia['textoPromocao'] ?• _fallbackTextoPromocao(nome, oportunidade.tipo);
      mensagemWhatsApp = ia['mensagemWhatsApp'] ?• _fallbackMensagemWhatsApp(nome, oportunidade.tipo);
      legendaInstagram = ia['legendaInstagram'] ?• _fallbackLegendaInstagram(nome, oportunidade.tipo);
    } catch (_) {
      textoPromocao = _fallbackTextoPromocao(nome, oportunidade.tipo);
      mensagemWhatsApp = _fallbackMensagemWhatsApp(nome, oportunidade.tipo);
      legendaInstagram = _fallbackLegendaInstagram(nome, oportunidade.tipo);
    }

    final tipoCampanha = oportunidade.tipo == TipoOportunidade.produtoParado
        • 'promocao'
        : 'urgencia';
    final titulo = oportunidade.tipo == TipoOportunidade.produtoParado
        • 'Promoção para $nome'
        : 'Urgência: estoque de $nome';
    final descricao = oportunidade.tipo == TipoOportunidade.produtoParado
        • 'Produto parado há 30 dias. Sugerimos desconto para movimentar o estoque.'
        : 'Estoque baixo. Destaque para venda rápida ou recompra.';
    final percentualDesconto = oportunidade.tipo == TipoOportunidade.produtoParado • 15.0 : 0.0;
    final codigoCupomSugerido = _gerarCodigoCupomSugerido(nome, oportunidade.tipo);

    return SugestaoCampanha(
      tipoCampanha: tipoCampanha,
      titulo: titulo,
      descricao: descricao,
      percentualDesconto: percentualDesconto,
      codigoCupomSugerido: codigoCupomSugerido,
      textoPromocao: textoPromocao,
      mensagemWhatsApp: mensagemWhatsApp,
      legendaInstagram: legendaInstagram,
    );
  }

  static Future<Map<String, String>> _gerarTextosIa(
    String nome,
    TipoOportunidade tipo,
    String contexto,
  ) async {
    final tipoWhatsApp = tipo == TipoOportunidade.produtoParado • 'promocao' : 'novidade';
    final ctx = tipo == TipoOportunidade.produtoParado
        • 'Produto $nome parado há 30 dias. Criar promoção.'
        : 'Produto $nome com estoque baixo. Urgência.';

    // Chamadas em paralelo para reduzir tempo por sugestão
    final results = await Future.wait([
      AiLojaService.sugerirMensagemWhatsApp(tipo: tipoWhatsApp, contexto: ctx),
      AiLojaService.sugerirLegendaInstagram(produtoNome: nome, descricao: ctx),
    ]);
    final msg = results[0];
    final legenda = results[1];

    return {
      'textoPromocao': _textoPromocaoFromIa(msg, nome, tipo),
      'mensagemWhatsApp': msg,
      'legendaInstagram': legenda,
    };
  }

  static String _textoPromocaoFromIa(String msg, String nome, TipoOportunidade tipo) {
    if (msg.length > 120) return '${msg.substring(0, 120).trim()}…';
    return msg;
  }

  static String _fallbackTextoPromocao(String nome, TipoOportunidade tipo) {
    if (tipo == TipoOportunidade.produtoParado) {
      return '🔥 Promoção especial! $nome com desconto. Aproveite!';
    }
    return '⚠️ Últimas unidades de $nome. Garanta a sua!';
  }

  static String _fallbackMensagemWhatsApp(String nome, TipoOportunidade tipo) {
    if (tipo == TipoOportunidade.produtoParado) {
      return 'Olá! Temos uma promoção especial no produto $nome. Aproveite o desconto!';
    }
    return 'Olá! O produto $nome está com estoque baixo. Garanta a sua unidade!';
  }

  static String _fallbackLegendaInstagram(String nome, TipoOportunidade tipo) {
    if (tipo == TipoOportunidade.produtoParado) {
      return 'Promoção $nome 💫\n#promocao #oferta #loja';
    }
    return 'Últimas unidades de $nome! 🔥\n#estoque #urgente #loja';
  }

  static String _gerarCodigoCupomSugerido(String nome, TipoOportunidade tipo) {
    final base = nome.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    final pre = base.length >= 4 • base.substring(0, 4) : base.padLeft(4, 'X');
    if (tipo == TipoOportunidade.produtoParado) {
      return 'PROMO${pre}15';
    }
    return 'URG$pre';
  }
}
