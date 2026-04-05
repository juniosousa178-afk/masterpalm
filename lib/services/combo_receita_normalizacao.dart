// lib/services/combo_receita_normalizacao.dart
// Normalização segura da receita de combo: productId canônico; nome/slug só como apoio.

import 'package:flutter/foundation.dart';

import '../models/produto.dart';

/// Mesma regra que [normalizeKey] em `produto_upsert_service` (evita import circular).
String _normalizeNomeCombo(String s) {
  if (s.isEmpty) return '';
  const from = 'áàãâäéèêëíìîïóòõôöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  var out = s.toLowerCase().trim();
  for (var i = 0; i < from.length; i++) {
    out = out.replaceAll(from[i], to[i]);
  }
  return out.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Prefixo de log para itens sem resolução segura ou pendências.
const String kLogComboReceita = '[COMBO_RECEITA]';
const String kLogComboReceitaPendente = '[COMBO_RECEITA_PENDENTE]';

class ComboReceitaNormalizacao {
  ComboReceitaNormalizacao._();

  /// productId / id / produtoId (legado) — nunca sobrescrever se já vier preenchido.
  static String pidFrom(Map<String, dynamic> m) {
    return (m['productId'] ?? m['id'] ?? m['produtoId'] ?? '').toString().trim();
  }

  /// Mesma normalização de nome usada na receita; exposta para auditoria passiva (somente leitura).
  static String normalizarNomeComparacao(String s) => _normalizeNomeCombo(s);

  static void _log(void Function(String msg)? onLog, String msg) {
    if (onLog != null) {
      onLog(msg);
    } else if (kDebugMode) {
      // ignore: avoid_print
      print(msg);
    }
  }

  /// Resolve [productId] quando ausente: slug exato único, depois nome normalizado único.
  /// Não adivinha se houver 0 ou >1 candidatos.
  static Map<String, dynamic> normalizeItem(
    Map<String, dynamic> raw,
    Iterable<Produto> produtosLoja, {
    void Function(String msg)? onLog,
  }) {
    final out = Map<String, dynamic>.from(raw);
    final existente = pidFrom(out);
    if (existente.isNotEmpty) {
      return out;
    }

    final slug = (out['slug'] ?? '').toString().trim();
    if (slug.isNotEmpty) {
      final porSlug = produtosLoja.where((p) => p.slug.trim() == slug).toList();
      if (porSlug.length == 1) {
        final p = porSlug.first;
        final fid = p.idFirebase.trim();
        if (fid.isNotEmpty) {
          out['productId'] = fid;
          out['nome'] = p.nome;
          out['slug'] = p.slug;
          return out;
        }
        _log(
          onLog,
          '$kLogComboReceitaPendente slug="$slug" resolve a produto sem idFirebase; sem productId.',
        );
      } else if (porSlug.length > 1) {
        _log(
          onLog,
          '$kLogComboReceitaPendente slug="$slug" ambíguo (${porSlug.length} produtos); não inferir productId.',
        );
      }
    }

    final nome = (out['nome'] ?? '').toString().trim();
    if (nome.isEmpty) {
      _log(onLog, '$kLogComboReceitaPendente item sem nome e sem productId.');
      return out;
    }

    final alvo = _normalizeNomeCombo(nome);
    final porNome =
        produtosLoja.where((p) => _normalizeNomeCombo(p.nome) == alvo).toList();
    if (porNome.length == 1) {
      final p = porNome.first;
      final fid = p.idFirebase.trim();
      if (fid.isNotEmpty) {
        out['productId'] = fid;
        out['nome'] = p.nome;
        out['slug'] = p.slug;
        return out;
      }
      _log(
        onLog,
        '$kLogComboReceitaPendente nome="$nome" único mas produto sem idFirebase.',
      );
    } else if (porNome.length > 1) {
      _log(
        onLog,
        '$kLogComboReceitaPendente nome="$nome" ambíguo (${porNome.length} produtos); não inferir productId.',
      );
    } else {
      _log(
        onLog,
        '$kLogComboReceitaPendente nome="$nome" sem correspondência na loja.',
      );
    }

    return out;
  }

  static List<Map<String, dynamic>> normalizeLista(
    List<Map<String, dynamic>> itens,
    Iterable<Produto> produtosLoja, {
    void Function(String msg)? onLog,
  }) {
    return itens
        .map((m) => normalizeItem(m, produtosLoja, onLog: onLog))
        .toList();
  }

  /// True se algum item ganhou [productId] novo sem perder ids existentes.
  static bool receitaGanhouProductIdsSeguros(
    List<Map<String, dynamic>>? antes,
    List<Map<String, dynamic>> depois,
  ) {
    if (antes == null || antes.length != depois.length) return false;
    var ganhou = false;
    for (var i = 0; i < antes.length; i++) {
      final a = pidFrom(antes[i]);
      final d = pidFrom(depois[i]);
      if (a.isNotEmpty && d != a) return false;
      if (a.isEmpty && d.isNotEmpty) ganhou = true;
    }
    return ganhou;
  }

  /// Indica item ainda sem productId após normalização.
  static bool itemPendente(Map<String, dynamic> m) => pidFrom(m).isEmpty;
}
