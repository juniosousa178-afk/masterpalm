// lib/services/catalog_config_published_v3_bridge.dart
// Ponte mínima: docs `lojas/{id}/config/config` com schemaVersion=3 guardam identidade
// em `published` (ex.: StoreService._ensureDefaultSettings: identidade.nome, theme.primary).
// O catálogo público lê chaves planas (nomeLoja, theme.primaria, etc.) — sem isto cai em "Minha Loja".

import '../core/safe_cast.dart';

bool _isEffectivelyEmpty(dynamic v) {
  if (v == null) return true;
  if (v is String) return v.trim().isEmpty;
  if (v is Map) return v.isEmpty;
  if (v is List) return v.isEmpty;
  return false;
}

/// Expõe `published`/`draft` (V3) no formato plano esperado por [PublicCatalogScreen] / cache.
/// Não remove chaves V3; só preenche raiz quando ainda vazia (compat com merge Loja Config).
void bridgeStoreConfigV3PublishedIntoPublicCatalogFlat(
  Map<String, dynamic> cfg, {
  bool preferDraft = false,
}) {
  final sv = cfg['schemaVersion'];
  if (sv is! num || sv.toInt() != 3) return;
  final published = cfg['published'] is Map ? asMap(cfg['published']) : <String, dynamic>{};
  final draft = cfg['draft'] is Map ? asMap(cfg['draft']) : <String, dynamic>{};
  final Map<String, dynamic> pub;
  if (preferDraft) {
    pub = draft.isNotEmpty ? draft : published;
  } else {
    pub = published.isNotEmpty ? published : draft;
  }
  if (pub.isEmpty) return;

  final ident = pub['identidade'];
  if (ident is Map) {
    final id = asMap(ident);
    final nome = (id['nome'] ?? '').toString().trim();
    if (nome.isNotEmpty) {
      if (_isEffectivelyEmpty(cfg['nomeLoja'])) cfg['nomeLoja'] = nome;
      if (_isEffectivelyEmpty(cfg['nome'])) cfg['nome'] = nome;
      if (_isEffectivelyEmpty(cfg['nome_loja'])) cfg['nome_loja'] = nome;
    }
  }

  final themeRoot = cfg['theme'];
  final themeRootEmpty = themeRoot is! Map || asMap(themeRoot).isEmpty;
  final themePub = pub['theme'];
  if (themePub is Map && themeRootEmpty) {
    final tp = asMap(themePub);
    final out = <String, dynamic>{};
    void firstOf(String target, List<String> keys) {
      for (final k in keys) {
        if (tp.containsKey(k) && !_isEffectivelyEmpty(tp[k])) {
          out[target] = tp[k];
          return;
        }
      }
    }
    firstOf('primaria', const ['primaria', 'primary']);
    firstOf('fundo', const ['fundo', 'bg', 'background']);
    firstOf('texto', const ['texto', 'text']);
    firstOf('card', const ['card', 'surface']);
    firstOf('botaoTexto', const ['botaoTexto', 'buttonText', 'onPrimary']);
    firstOf('cabecalho', const ['cabecalho', 'header']);
    for (final e in tp.entries) {
      out.putIfAbsent(e.key, () => e.value);
    }
    cfg['theme'] = out;
  }

  if (pub['layout'] is Map &&
      (cfg['layout'] == null || _isEffectivelyEmpty(cfg['layout']))) {
    cfg['layout'] = pub['layout'];
  }
  if (pub['media'] is Map &&
      (cfg['media'] == null || _isEffectivelyEmpty(cfg['media']))) {
    cfg['media'] = pub['media'];
  }
}
