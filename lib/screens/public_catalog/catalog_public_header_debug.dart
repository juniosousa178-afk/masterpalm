// Instrumentação temporária (somente kDebugMode) — diagnóstico header/catálogo público.
// Remover ou reduzir após validar causa raiz.

import 'dart:convert';

import 'package:flutter/foundation.dart' show kDebugMode;

import '../../core/logger.dart';
import '../../core/safe_cast.dart';
import 'catalog_config_service.dart';
import 'catalog_helpers.dart';

/// Evita logs gigantes no console.
String _truncate(String s, [int max = 2400]) {
  if (s.length <= max) return s;
  return '${s.substring(0, max)}…(trunc ${s.length - max} chars)';
}

Map<String, dynamic> _headerRelevantSlice(Map<String, dynamic> cfg) {
  return <String, dynamic>{
    'nomeLoja': cfg['nomeLoja'],
    'nome_loja': cfg['nome_loja'],
    'nome': cfg['nome'],
    'name': cfg['name'],
    'logoUrl': cfg['logoUrl'],
    'logoDesktopUrl': cfg['logoDesktopUrl'],
    'logoMobileUrl': cfg['logoMobileUrl'],
    'banners': cfg['banners'],
    'bannersDesktop': cfg['bannersDesktop'],
    'bannersMobile': cfg['bannersMobile'],
    'media': cfg['media'],
    'theme': cfg['theme'],
    'schemaVersion': cfg['schemaVersion'],
    'hasPublished': cfg['published'] != null,
    'hasDraft': cfg['draft'] != null,
  };
}

String _cfgSig(Map<String, dynamic> cfg) {
  try {
    return jsonEncode(_headerRelevantSlice(cfg));
  } catch (_) {
    return '${cfg.hashCode}';
  }
}

/// Logs no momento da resolução da loja (URL → lojaId canônico).
void catalogDebugLogStoreResolution({
  required String widgetLojaIdRaw,
  required String? resolvedCanonicalId,
  required bool preview,
  required String resolveSourceHint,
}) {
  if (!kDebugMode) return;
  final uri = Uri.base;
  logD(
    '🧭 [CATALOG-DEBUG][resolve] hint=$resolveSourceHint '
    'host=${uri.host} path=${uri.path} query=${uri.query} fragment=${uri.fragment}',
  );
  logD(
    '🧭 [CATALOG-DEBUG][resolve] slugOuIdNaEntrada="$widgetLojaIdRaw" '
    'preview=$preview lojaIdCanônico=${resolvedCanonicalId ?? "(null)"}',
  );
}

/// Pipeline de config em [CatalogCacheService._fetchConfig] ou espelho em [_cfgStream].
void catalogDebugLogConfigPipeline({
  required String phase,
  required String lojaId,
  required String cfgCol,
  required Map<String, dynamic> cfg,
}) {
  if (!kDebugMode) return;
  try {
    final slice = _headerRelevantSlice(cfg);
    final rawJson = _truncate(jsonEncode(slice));
    logD(
      '📦 [CATALOG-DEBUG][config:$phase] loja=$lojaId col=$cfgCol keys=${cfg.length} '
      'slice=$rawJson',
    );
  } catch (e) {
    logD('📦 [CATALOG-DEBUG][config:$phase] loja=$lojaId encode_err=$e');
  }
}

/// Origem da emissão do stream de config (cache memória / disco / Firestore / erro).
void catalogDebugLogConfigStreamEmit({
  required String source,
  required String lojaId,
  required bool preview,
  required Map<String, dynamic> cfg,
}) {
  if (!kDebugMode) return;
  logD(
    '📡 [CATALOG-DEBUG][stream] source=$source loja=$lojaId preview=$preview '
    'keys=${cfg.length} sig=${_cfgSig(cfg)}',
  );
  catalogDebugLogConfigPipeline(
    phase: 'stream_emit_$source',
    lojaId: lojaId,
    cfgCol: preview ? 'draft_config' : 'config',
    cfg: cfg,
  );
}

String? _lastDebugLojaId;
String? _lastHeaderSig;
Map<String, dynamic>? _lastHeaderSlice;

/// No ponto do header: valores finais + parseMedia + possível overwrite.
void catalogDebugLogHeaderUi({
  required String lojaId,
  required Map<String, dynamic> cfg,
  required bool isWide,
}) {
  if (!kDebugMode) return;

  if (_lastDebugLojaId != lojaId) {
    _lastDebugLojaId = lojaId;
    _lastHeaderSig = null;
    _lastHeaderSlice = null;
  }

  final nameFromFn = catalogHeaderStoreNameFromCfg(cfg);
  final media = parseMedia(cfg, isWide: isWide);
  final slice = _headerRelevantSlice(cfg);
  final sig = _cfgSig(cfg);

  if (_lastHeaderSig != null && _lastHeaderSig != sig) {
    logD(
      '🔴 [CATALOG-DEBUG][header] POSSÍVEL OVERWRITE DE CFG '
      'antes=$_lastHeaderSlice depois=$slice',
    );
  }
  _lastHeaderSig = sig;
  _lastHeaderSlice = Map<String, dynamic>.from(slice);

  logD(
    '🏷️ [CATALOG-DEBUG][header] loja=$lojaId isWide=$isWide '
    'catalogHeaderStoreNameFromCfg→${nameFromFn ?? "(null → UI Minha Loja)"}',
  );
  logD(
    '🏷️ [CATALOG-DEBUG][header] campos: '
    'nomeLoja=${cfg['nomeLoja']} nome_loja=${cfg['nome_loja']} nome=${cfg['nome']} name=${cfg['name']}',
  );
  logD(
    '🖼️ [CATALOG-DEBUG][header] mídia cfg: logoUrl=${cfg['logoUrl']} '
    'logoDesktop=${cfg['logoDesktopUrl']} logoMobile=${cfg['logoMobileUrl']} '
    'banners=${cfg['banners']} bd=${cfg['bannersDesktop']} bm=${cfg['bannersMobile']} '
    'media=${cfg['media'] is Map ? asMap(cfg['media']).keys.toList() : cfg['media']}',
  );
  logD(
    '🖼️ [CATALOG-DEBUG][header] parseMedia→ logoUrl="${media.logoUrl}" '
    'banners=${media.banners.length} bannerH=${media.bannerH}',
  );
  final theme = cfg['theme'];
  logD(
    '🎨 [CATALOG-DEBUG][header] theme=${theme is Map ? asMap(theme).keys.toList() : theme}',
  );
}
