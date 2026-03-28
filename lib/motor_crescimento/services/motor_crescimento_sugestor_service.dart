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
      textoPromocao = ia['textoPromocao'] ?? _fallbackTextoPromocao(nome, oportunidade.tipo);
      mensagemWhatsApp = ia['mensagemWhatsApp'] ?? _fallbackMensagemWhatsApp(nome, oportunidade.tipo);
      legendaInstagram = ia['legendaInstagram'] ?? _fallbackLegendaInstagram(nome, oportunidade.tipo);
    } catch (_) {
      textoPromocao = _fallbackTextoPromocao(nome, oportunidade.tipo);
      mensagemWhatsApp = _fallbackMensagemWhatsApp(nome, oportunidade.tipo);
      legendaInstagram = _fallbackLegendaInstagram(nome, oportunidade.tipo);
    }

    final tipoCampanha = oportunidade.tipo == TipoOportunidade.produtoParado
        ? 'promocao'
        : 'urgencia';
    final titulo = oportunidade.tipo == TipoOportunidade.produtoParado
        ? 'Promoção para $nome'
        : 'Urgência: estoque de $nome';
    final descricao = oportunidade.tipo == TipoOportunidade.produtoParado
        ? 'Produto parado há 30 dias. Sugerimos desconto para movimentar o estoque.'
        : 'Estoque baixo. Destaque para venda rápida ou recompra.';
    final percentualDesconto = oportunidade.tipo == TipoOportunidade.produtoParado ? 15.0 : 0.0;
    final codigoCupomSugerido = _gerarCodigoCupomSugerido(
      nome,
      oportunidade.tipo,
      percentualDesconto,
    );

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
    final tipoWhatsApp = tipo == TipoOportunidade.produtoParado ? 'promocao' : 'novidade';
    final ctx = tipo == TipoOportunidade.produtoParado
        ? 'Produto $nome parado há 30 dias. Criar promoção.'
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
    return msg.trim();
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

  /// Cupom curto e único por peça: usa trechos do nome (ex.: Colar coração 15% → CLCORACAO15;
  /// Colar coração vazado 15% → CLCOVAZADO15).
  static String _gerarCodigoCupomSugerido(
    String nome,
    TipoOportunidade tipo,
    double percentualDesconto,
  ) {
    var slug = _slugCupomFromNomeProduto(nome);
    slug = slug.replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (slug.isEmpty) slug = 'ITEM';
    if (slug.length > 14) slug = slug.substring(0, 14);

    final pct = percentualDesconto.round().clamp(0, 100);
    if (tipo == TipoOportunidade.produtoParado && pct > 0) {
      return '$slug$pct';
    }
    if (tipo == TipoOportunidade.estoqueBaixo) {
      if (pct > 0) return '$slug$pct';
      return 'U$slug';
    }
    return pct > 0 ? '$slug$pct' : 'U$slug';
  }

  static String _normalizeAscii(String s) {
    var t = s.toLowerCase();
    const map = <String, String>{
      'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    for (final e in map.entries) {
      t = t.replaceAll(e.key, e.value);
    }
    return t;
  }

  static const Set<String> _stopwordsCupom = {
    'de', 'da', 'do', 'das', 'dos', 'e', 'para', 'com', 'em', 'no', 'na', 'nos', 'nas',
    'a', 'o', 'as', 'os', 'um', 'uma', 'por', 'ao', 'aos',
  };

  static bool _isVowelPt(String ch) {
    if (ch.isEmpty) return true;
    return 'aeiou'.contains(ch[0]);
  }

  /// Duas primeiras consoantes (pt) ou, se não houver, duas primeiras letras.
  static String _prefixoDuasConsoantes(String palavra) {
    final w = palavra.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (w.isEmpty) return 'XX';
    final buf = StringBuffer();
    for (var i = 0; i < w.length && buf.length < 2; i++) {
      final c = w[i];
      if (!_isVowelPt(c)) buf.write(c);
    }
    if (buf.length >= 2) return buf.toString();
    if (w.length >= 2) return w.substring(0, 2);
    return w.padRight(2, 'x');
  }

  static String _slugCupomFromNomeProduto(String nome) {
    final norm = _normalizeAscii(nome.trim());
    var words = norm
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where((w) => w.isNotEmpty && !_stopwordsCupom.contains(w))
        .toList();
    if (words.isEmpty) {
      words = _normalizeAscii(nome.trim())
          .split(RegExp(r'\s+'))
          .map((w) => w.replaceAll(RegExp(r'[^a-z0-9]'), ''))
          .where((w) => w.isNotEmpty)
          .toList();
    }
    if (words.isEmpty) return 'ITEM';

    if (words.length == 1) {
      final w = words[0];
      final core = w.length <= 10 ? w : w.substring(0, 10);
      return core.toUpperCase();
    }

    if (words.length == 2) {
      final p0 = _prefixoDuasConsoantes(words[0]);
      var w1 = words[1];
      if (w1.length > 8) w1 = w1.substring(0, 8);
      return (p0 + w1).toUpperCase();
    }

    // 3+ palavras: 2 consoantes da 1ª + 2 letras da 2ª + última palavra (ex.: CL + CO + VAZADO).
    final p0 = _prefixoDuasConsoantes(words[0]);
    final w1 = words[1];
    final p1 = w1.length >= 2 ? w1.substring(0, 2) : w1.padRight(2, 'x');
    var last = words.last;
    if (last.length > 8) last = last.substring(0, 8);
    return (p0 + p1 + last).toUpperCase();
  }
}
