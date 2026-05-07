// lib/screens/public_catalog/catalog_helpers.dart
// Helpers compartilhados para o catálogo público (cores, checkout, mapas).
//
// PIX (mpCatalogPayment): [catalogIsPlausibleMpBuyerEmail], [catalogIsValidCpfForMpPayer] e
// [catalogCheckoutBuyerValidForMpPix] devem permanecer alinhados a
// `functions/src/mpCatalogPayerBrasil.js`.

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive/hive.dart';

import '../../utils/safe_parse.dart';

/// E-mail mínimo aceitável para enviar ao Mercado Pago (evita erros de "e-mail inválido").
bool catalogIsPlausibleMpBuyerEmail(String? raw) {
  final s = (raw ?? '').trim();
  if (s.length < 6 || !s.contains('@')) return false;
  final parts = s.split('@');
  if (parts.length != 2 || parts[0].isEmpty) return false;
  final dom = parts[1];
  return dom.contains('.') && dom.length >= 4;
}

/// CPF (11 dígitos, dígitos verificadores) — espelha [isValidCpfDigits] na Cloud Function.
bool catalogIsValidCpfForMpPayer(String? raw) {
  final cpf = (raw ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (cpf.length != 11) return false;
  if (cpf.split('').toSet().length == 1) return false;
  var sum = 0;
  for (var i = 0; i < 9; i++) {
    sum += int.parse(cpf[i]) * (10 - i);
  }
  var d1 = (sum * 10) % 11;
  if (d1 == 10) d1 = 0;
  if (d1 != int.parse(cpf[9])) return false;
  sum = 0;
  for (var i = 0; i < 10; i++) {
    sum += int.parse(cpf[i]) * (11 - i);
  }
  var d2 = (sum * 10) % 11;
  if (d2 == 10) d2 = 0;
  return d2 == int.parse(cpf[10]);
}

/// Verificação imediata antes de POST `mpCatalogPayment` com type=pix.
bool catalogCheckoutBuyerValidForMpPix({required String? email, required String? cpf}) {
  return catalogIsPlausibleMpBuyerEmail(email) && catalogIsValidCpfForMpPayer(cpf);
}

// ===================================================================
// ENDPOINTS HTTP (Cloud Functions) – Mercado Pago + Fretes
// ===================================================================
const String kMpCreatePreferenceUrl =
    'https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/createPreference';

/// Proxy para criar PIX/preferência no catálogo (evita CORS na web)
const String kMpCatalogPaymentUrl =
    'https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/mpCatalogPayment';

const String kCalcMelhorEnvioUrl =
    'https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/calcularMelhorEnvio';

const String kCalcCorreiosUrl =
    'https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/calcularCorreios';

const String kCalcFrenetUrl =
    'https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/calcularFrenet';

// ===================================================================
// FIRESTORE COLLECTIONS (PADRÃO NOVO) – LIVE x RASCUNHO
// ===================================================================
const String kLiveProdutosCol = 'produtos';
const String kDraftProdutosCol = 'draft_produtos';

/// Ordenação por preço/valor no grid — [asNum] evita TypeError (web minified) com tipos inesperados.
double catalogPrecoParaOrdenacao(Map<String, dynamic> p) {
  final raw = p['valor'] ?? p['preco'] ?? p['precoFinal'];
  final n = asNum(raw);
  if (n != null) return n.toDouble();
  return double.tryParse('$raw') ?? 0.0;
}

/// `precoPorTamanho` com chaves/valores heterogéneos (Firestore/JSON na web).
Map<String, double>? catalogPrecoPorTamanhoFromDynamic(dynamic raw) {
  if (raw == null || raw is! Map) return null;
  final m = asMap(raw);
  if (m.isEmpty) return null;
  final out = <String, double>{};
  m.forEach((k, v) {
    final n = asNum(v);
    if (n != null && n > 0) out[k.toString()] = n.toDouble();
  });
  return out.isEmpty ? null : out;
}

// ===================================================================
// IDENTIDADE NO HEADER (nome exibido)
// ===================================================================

bool _catalogHeaderNameIsPlaceholder(String s) {
  final t = s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  return t == 'minha loja';
}

/// URL de ação do hero (layout minimal) — Loja Config pode usar chaves legadas.
String? catalogHeroBannerActionUrl(Map<String, dynamic> hero) {
  if (hero.isEmpty) return null;
  for (final k in const [
    'buttonLink',
    'link',
    'url',
    'href',
    'buttonUrl',
    'destino',
    'actionUrl',
  ]) {
    final s = (hero[k] ?? '').toString().trim();
    if (s.isNotEmpty) return s;
  }
  return null;
}

String? catalogHeaderStoreNameFromCfg(Map<String, dynamic> cfg) {
  for (final k in const ['nome', 'nomeLoja', 'nome_loja', 'name']) {
    final v = cfg[k];
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isEmpty) continue;
    if (_catalogHeaderNameIsPlaceholder(s)) continue;
    return s;
  }
  return null;
}

// ===================================================================
// CORES
// ===================================================================
Color readColor(dynamic v, Color fallback) {
  if (v is int) return Color(v);
  return fallback;
}

Color? readColorFromCfg(dynamic v) {
  if (v is int) return Color(v);

  if (v is String) {
    final s = v.trim();
    if (s.isEmpty) return null;
    final cleaned = s.replaceAll('#', '');
    if (cleaned.length == 6 || cleaned.length == 8) {
      final value = int.tryParse(cleaned, radix: 16);
      if (value != null) {
        if (cleaned.length == 6) {
          return Color(0xFF000000 | value);
        }
        return Color(value);
      }
    }
  }
  return null;
}

// ===================================================================
// CHECKOUT CONFIG
// ===================================================================

/// Lê [cfg['payments']] (unificado com `payments_public` no stream do catálogo).
/// Com Mercado Pago conectado, o PIX deve ir para [onCheckoutMercadoPago], não chave estática.
bool catalogConfigMercadoPagoAtivo(Map<String, dynamic> cfg) {
  final pay = cfg['payments'];
  if (pay is! Map) return false;
  final p = pay.map((k, v) => MapEntry(k.toString(), v));
  final dg = (p['defaultGateway'] ?? '').toString().toLowerCase().trim();
  if (dg == 'mp' || dg == 'mercadopago') return true;
  final mp = p['mp'];
  if (mp is! Map) return false;
  final m = mp.map((k, v) => MapEntry(k.toString(), v));
  if (m['connected'] == true) return true;
  final pk = (m['public_key'] ?? m['publicKey'] ?? '').toString().trim();
  if (pk.isNotEmpty) return true;
  final hint = (m['access_token_hint'] ?? '').toString().trim();
  if (hint.isNotEmpty) return true;
  if ((m['email'] ?? m['user_id'] ?? m['nickname'] ?? '')
      .toString()
      .trim()
      .isNotEmpty) {
    return true;
  }
  return false;
}

String deepFindString(dynamic root, String keyContains) {
  if (root is Map) {
    for (final entry in root.entries) {
      final k = entry.key.toString().toLowerCase();
      final v = entry.value;
      if (k.contains(keyContains.toLowerCase()) &&
          v is String &&
          v.isNotEmpty) {
        return v;
      }
      final nested = deepFindString(v, keyContains);
      if (nested.isNotEmpty) return nested;
    }
  } else if (root is List) {
    for (final v in root) {
      final nested = deepFindString(v, keyContains);
      if (nested.isNotEmpty) return nested;
    }
  }
  return '';
}

Map<String, dynamic> resolveCheckoutCfgFromData(Map<String, dynamic> data) {
  Map<String, dynamic> result = {};

  final dynamic c1 =
      data['checkoutCfg'] ?? data['checkout'] ?? data['config_pagamentos'];
  final Map<String, dynamic> checkoutMap = asMap(c1);
  if (checkoutMap.isNotEmpty) {
    result.addAll(checkoutMap);
  }

  final dynamic payments = data['payments'] ?? data['pagamentos'];
  final Map<String, dynamic> paymentsMap = asMap(payments);
  if (paymentsMap.isNotEmpty) {
    result.addAll(paymentsMap);
  }

  if (result.isEmpty && !kIsWeb && Hive.isBoxOpen('config')) {
    try {
      final box = Hive.box('config');
      final dynamic hivePayments = box.get('payments');
      final Map<String, dynamic> hiveMap = asMap(hivePayments);
      if (hiveMap.isNotEmpty) {
        result.addAll(hiveMap);
      }
      final String pixFromHive = deepFindString(hiveMap, 'pix');
      final String gatewayFromHive = deepFindString(hiveMap, 'gateway');
      if (pixFromHive.isNotEmpty) result['pixKey'] = pixFromHive;
      if (gatewayFromHive.isNotEmpty) result['gateway'] = gatewayFromHive;
    } catch (_) {}
  }

  return result;
}

/// Converte para Map<String, dynamic>; delega a asMap (evita TypeError em release).
Map<String, dynamic> mpMapDyn(dynamic raw) => asMap(raw);

Map<String, String> mpMapString(dynamic raw) {
  final m = mpMapDyn(raw);
  return m.map((k, v) => MapEntry(k, (v ?? '').toString()));
}

// ===================================================================
// PARSING DEFENSIVO (Firestore/Hive → evita TypeError em release/minified)
// ===================================================================

/// Converte qualquer valor para double sem cast direto.
double parseNum(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  final s = '$v'.replaceAll(',', '.');
  return double.tryParse(s) ?? 0.0;
}

/// Converte qualquer valor para int sem cast direto.
int parseIntSafe(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? 0;
}

/// Converte para List<String> sem cast direto.
List<String> parseListString(dynamic v) {
  if (v == null) return [];
  if (v is List) return v.map((e) => '$e').where((s) => s.isNotEmpty).toList();
  final s = '$v'.trim();
  return s.isEmpty ? [] : [s];
}

/// Converte para Map<String, dynamic> sem cast direto.
Map<String, dynamic> safeMapFrom(dynamic raw) {
  if (raw == null) return {};
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) {
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }
  return {};
}

/// Converte para Map<String, int> (ex.: estoquePorTamanho).
Map<String, int> safeMapIntFrom(dynamic raw) {
  if (raw == null || raw is! Map) return {};
  final out = <String, int>{};
  raw.forEach((k, v) {
    final key = k.toString();
    final val = (v is int) ? v : ((v is num) ? v.toInt() : (int.tryParse('$v') ?? 0));
    if (val > 0) out[key] = val;
  });
  return out;
}

// ===================================================================
// URL / IMAGEM
// ===================================================================
bool isValidHttpUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
}

/// Heurística: thumbnails gerados no Storage (ex.: CF `generateProductThumbnail`) usam `.../thumbnails/...`.
bool catalogProductImageUrlLooksLikeGeneratedThumbnail(String url) {
  final t = url.trim().toLowerCase();
  if (t.isEmpty) return false;
  final normalized = t.replaceAll('%2f', '/').replaceAll('%5c', '/');
  return normalized.contains('/thumbnails/');
}

/// Dentro de uma lista já ordenada pelo utilizador, ignora só um **prefixo** de
/// thumbnails Storage (`/thumbnails/`) — ex.: sync colocou thumb antes da foto real.
String _firstCatalogCoverFromOrderedUserUrls(List<String> urls) {
  final t = urls.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  if (t.isEmpty) return '';
  var i = 0;
  while (i < t.length &&
      catalogProductImageUrlLooksLikeGeneratedThumbnail(t[i])) {
    i++;
  }
  if (i < t.length) return t[i];
  return t.first;
}

/// URL da **capa** do produto no catálogo e campos espelhados no sync (`imageUrl`, etc.).
///
/// Regra: ordem do cadastro — [imagens] → [images] → [fotos] → [imgs]; depois campos
/// soltos `imagem_principal`, `imageUrl`, `cover`, `fotoOriginalUrl`, `imagemUrl`;
/// por último `thumbnail` / `fotoThumbUrl`. Sem reordenar por formato, tamanho ou data.
/// Só se remove prefixo inicial de URLs `/thumbnails/` dentro da mesma lista (dados espúrios).
String selectCatalogCoverImageUrl({
  required List<String> imagens,
  List<String>? images,
  List<String>? fotos,
  List<String>? imgs,
  String? imageUrl,
  String? imagem_principal,
  String? cover,
  String? fotoOriginalUrl,
  String? imagemUrl,
  String? thumbnail,
  String? fotoThumbUrl,
}) {
  final imgLists = <List<String>>[
    imagens,
    images ?? const [],
    fotos ?? const [],
    imgs ?? const [],
  ];
  for (final list in imgLists) {
    final u = _firstCatalogCoverFromOrderedUserUrls(list);
    if (u.isNotEmpty) return u;
  }

  bool isStorageThumb(String u) =>
      catalogProductImageUrlLooksLikeGeneratedThumbnail(u);

  for (final raw in [imageUrl, imagem_principal, cover, fotoOriginalUrl, imagemUrl]) {
    final u = (raw ?? '').trim();
    if (u.isNotEmpty && !isStorageThumb(u)) return u;
  }
  for (final raw in [thumbnail, fotoThumbUrl]) {
    final u = (raw ?? '').trim();
    if (u.isNotEmpty && !isStorageThumb(u)) return u;
  }
  for (final raw in [
    imageUrl,
    imagem_principal,
    cover,
    fotoOriginalUrl,
    imagemUrl,
    thumbnail,
    fotoThumbUrl,
  ]) {
    final u = (raw ?? '').trim();
    if (u.isNotEmpty) return u;
  }
  return '';
}

/// Compat: sync e código legado — só recebe [imagens] + campos espelhados do modelo.
String selectCatalogPrimaryImageUrl({
  required List<String> imagens,
  String? fotoOriginalUrl,
  String? imageUrl,
  String? imagem_principal,
  String? thumbnail,
}) {
  return selectCatalogCoverImageUrl(
    imagens: imagens,
    images: const [],
    fotos: const [],
    imgs: const [],
    imageUrl: imageUrl,
    imagem_principal: imagem_principal,
    cover: null,
    fotoOriginalUrl: fotoOriginalUrl,
    imagemUrl: null,
    thumbnail: thumbnail,
    fotoThumbUrl: null,
  );
}

String selectCatalogPrimaryImageUrlFromProdutoMap(Map<String, dynamic> p) {
  return selectCatalogCoverImageUrl(
    imagens: safeListString(p['imagens']),
    images: safeListString(p['images']),
    fotos: safeListString(p['fotos']),
    imgs: safeListString(p['imgs']),
    imageUrl: safeStr(p['imageUrl']),
    imagem_principal: safeStr(p['imagem_principal']),
    cover: safeStr(p['cover']),
    fotoOriginalUrl: safeStr(p['fotoOriginalUrl']),
    imagemUrl: safeStr(p['imagemUrl']),
    thumbnail: safeStr(p['thumbnail']),
    fotoThumbUrl: safeStr(p['fotoThumbUrl']),
  );
}

/// URL para logs (query mascarada — evita expor tokens longos).
String catalogImageUrlMaskForLog(String url) {
  final u = url.trim();
  if (u.isEmpty) return '';
  final uri = Uri.tryParse(u);
  if (uri == null) {
    return u.length > 120 ? '${u.substring(0, 120)}…' : u;
  }
  final base = '${uri.scheme}://${uri.host}${uri.path}';
  final shortened = base.length > 140 ? '${base.substring(0, 140)}…' : base;
  if (uri.query.isEmpty) return shortened;
  return '$shortened?…';
}

/// Mesma ordem que [catalogProductImageUrlsForDisplay] (galeria / card lista).
List<String> catalogProductImagesForHeroAndGallery(Map<String, dynamic> p) {
  return catalogProductImageUrlsForDisplay(p);
}

/// URLs do produto no catálogo: ordem do cadastro ([imagens] → [images] → …),
/// dedupe sem alterar ordem, **sem** mover thumbnails para o fim.
List<String> catalogProductImageUrlsForDisplay(Map<String, dynamic> p) {
  final raw = <String>[];

  void addOne(String s) {
    final u = s.trim();
    if (u.isNotEmpty) raw.add(u);
  }

  for (final img in safeListString(p['imagens'])) {
    addOne(img);
  }
  for (final img in safeListString(p['images'])) {
    addOne(img);
  }
  for (final img in safeListString(p['fotos'])) {
    addOne(img);
  }
  for (final img in safeListString(p['imgs'])) {
    addOne(img);
  }

  for (final k in const [
    'imageUrl',
    'imagem_principal',
    'cover',
    'fotoOriginalUrl',
    'imagemUrl',
  ]) {
    addOne(safeStr(p[k], ''));
  }

  final seen = <String>{};
  final deduped = <String>[];
  for (final u in raw) {
    if (seen.add(u)) deduped.add(u);
  }

  if (deduped.isNotEmpty) return deduped;

  final th = safeStr(p['thumbnail'], '').trim();
  if (th.isNotEmpty) return [th];
  final ft = safeStr(p['fotoThumbUrl'], '').trim();
  if (ft.isNotEmpty) return [ft];
  return [];
}

String catalogPrimaryProductImageUrl(Map<String, dynamic> p) {
  return selectCatalogPrimaryImageUrlFromProdutoMap(p);
}

/// Normaliza texto de categoria/subcategoria para sugestões do detalhe.
String catalogNormCatSub(dynamic v) =>
    (v ?? '').toString().trim().toLowerCase();

/// Sugestões com dados já em memória: prioriza mesma subcategoria, depois mesma categoria.
List<Map<String, dynamic>> catalogSugestoesRelacionadasParaDetalhe({
  required List<Map<String, dynamic>> fonteCompletaCatalogo,
  required Map<String, dynamic> produtoAtual,
  int limite = 8,
}) {
  if (fonteCompletaCatalogo.isEmpty || limite <= 0) return const [];
  final idAtual = safeStr(produtoAtual['id']);
  final cat = catalogNormCatSub(
      produtoAtual['categoria'] ?? produtoAtual['categoriaId']);
  final sub = catalogNormCatSub(
      produtoAtual['subcategoria'] ?? produtoAtual['subcategoriaId']);

  final outros = fonteCompletaCatalogo
      .where((p) => safeStr(p['id']).isNotEmpty && safeStr(p['id']) != idAtual)
      .toList();

  bool temEstoquePositivo(Map<String, dynamic> p) =>
      safeInt(p['quantidade']) > 0;

  bool mesmaSub(Map<String, dynamic> p) {
    final s =
        catalogNormCatSub(p['subcategoria'] ?? p['subcategoriaId']);
    return sub.isNotEmpty && s.isNotEmpty && s == sub;
  }

  bool mesmaCat(Map<String, dynamic> p) {
    final c =
        catalogNormCatSub(p['categoria'] ?? p['categoriaId']);
    return cat.isNotEmpty && c.isNotEmpty && c == cat;
  }

  final vista = <String>{};
  final saida = <Map<String, dynamic>>[];

  void addAll(
    Iterable<Map<String, dynamic>> candidatos,
    bool Function(Map<String, dynamic>) pred,
  ) {
    for (final p in candidatos) {
      if (saida.length >= limite) return;
      final id = safeStr(p['id']);
      if (!temEstoquePositivo(p) || !pred(p) || !vista.add(id)) continue;
      saida.add(p);
    }
  }

  addAll(outros, mesmaSub);
  addAll(outros, mesmaCat);

  if (saida.length < limite) {
    for (final p in outros) {
      if (saida.length >= limite) break;
      final id = safeStr(p['id']);
      if (temEstoquePositivo(p) && vista.add(id)) {
        saida.add(p);
      }
    }
  }

  return saida;
}

// ===================================================================
// BANNER HERO (CATÁLOGO MINIMALISTA)
// ===================================================================

/// Caixa de texto do banner: `none` | `lowercase` | `uppercase`.
String applyHeroLetterCase(String text, String mode) {
  final m = mode.trim().toLowerCase();
  if (m == 'uppercase') return text.toUpperCase();
  if (m == 'lowercase') return text.toLowerCase();
  return text;
}

/// Peso da fonte (config loja: 400–900, "w600", "bold").
FontWeight parseFontWeightCfg(dynamic v, FontWeight fallback) {
  if (v == null) return fallback;
  if (v is int) {
    final n = v.clamp(100, 900);
    if (n % 100 == 0) {
      final i = (n ~/ 100) - 1;
      if (i >= 0 && i < FontWeight.values.length) return FontWeight.values[i];
    }
  }
  final s = v.toString().trim().toLowerCase();
  if (s == 'bold' || s == 'w700' || s == '700') return FontWeight.w700;
  if (s == 'w800' || s == '800') return FontWeight.w800;
  if (s == 'w600' || s == '600' || s == 'semibold') return FontWeight.w600;
  if (s == 'w500' || s == '500' || s == 'medium') return FontWeight.w500;
  if (s == 'w400' || s == '400' || s == 'normal' || s == 'regular') {
    return FontWeight.w400;
  }
  final parsed = int.tryParse(s);
  if (parsed != null && parsed % 100 == 0 && parsed >= 100 && parsed <= 900) {
    final i = (parsed ~/ 100) - 1;
    if (i >= 0 && i < FontWeight.values.length) return FontWeight.values[i];
  }
  return fallback;
}
