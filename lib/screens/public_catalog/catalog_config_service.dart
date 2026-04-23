// lib/screens/public_catalog/catalog_config_service.dart
// Parsing de fretes, cupons e mídia do config – extraído do public_catalog_screen.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/safe_cast.dart';

double _parseNum(dynamic v) =>
    v is num ? v.toDouble() : (double.tryParse('$v'.replaceAll(',', '.')) ?? 0.0);

double? _parseNumOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  final n = double.tryParse('$v'.replaceAll(',', '.'));
  return n;
}

List<String> _parseProdutoIdsCfg(dynamic v) {
  if (v == null) return [];
  if (v is List) {
    return v.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
  }
  final s = v.toString().trim();
  return s.isEmpty ? [] : [s];
}

// ===================================================================
// FRETES
// ===================================================================

/// Parseia fretes do config (cfg['fretes']) e retorna lista normalizada.
/// cfg['fretes'] é SEMPRE a lista manual da loja – nunca API (Melhor Envio, Super Frete etc).
/// As opções de API vêm do FreteService.calcularFrete() ao informar o CEP.
List<Map<String, dynamic>> parseFretes(Map<String, dynamic> cfg) {
  final fretes = <Map<String, dynamic>>[];

  void addFreteFromCfg(Map<String, dynamic> m) {

    final nome = (m['nome'] ?? m['label'] ?? m['titulo'] ?? m['servico'] ?? '')
        .toString()
        .trim();
    if (nome.isEmpty) return;

    final ativo = m['ativo'] != false;
    if (!ativo) return;

    final prazo = (m['prazo'] ?? m['deadline'] ?? '').toString();

    String tipoFrete =
        (m['tipo'] ?? m['provider'] ?? '').toString().toLowerCase().trim();
    if (tipoFrete.isEmpty) tipoFrete = 'manual';

    // cfg['fretes'] é sempre lista MANUAL da loja – nunca marcar como API
    final freteGratisCfg = m['freteGratis'] == true;

    final val = _parseNum(m['valor']);

    fretes.add({
      'nome': nome,
      'valor': freteGratisCfg ? 0.0 : val,
      'prazo': prazo,
      'tipo': tipoFrete,
      'plataforma': 'manual',
      'freteGratis': freteGratisCfg,
      'automatico': false,
    });
  }

  final fretesCfg = cfg['fretes'];
  if (fretesCfg is List) {
    for (final e in fretesCfg) {
      final m = asMap(e);
      if (m.isNotEmpty) addFreteFromCfg(m);
    }
  } else if (fretesCfg is Map) {
    for (final e in fretesCfg.values) {
      final m = asMap(e);
      if (m.isNotEmpty) addFreteFromCfg(m);
    }
  }

  if (fretes.isEmpty) {
    fretes.addAll([
      {
        'nome': 'Retirada',
        'valor': 0.0,
        'prazo': '',
        'freteGratis': true,
        'tipo': 'retirada',
        'plataforma': 'manual',
        'automatico': false,
      },
      {
        'nome': 'Entrega local',
        'valor': 10.0,
        'prazo': '',
        'freteGratis': false,
        'tipo': 'entrega_local',
        'plataforma': 'manual',
        'automatico': false,
      },
      {
        'nome': 'Combinar com vendedor',
        'valor': 0.0,
        'prazo': '',
        'freteGratis': true,
        'tipo': 'combinar',
        'plataforma': 'manual',
        'automatico': false,
      },
    ]);
  }

  return fretes;
}

/// A tela **Fretes e Cupons** grava os fretes manuais em
/// `lojas/{lojaId}/{config|draft_config}/fretes` no campo [manualFretes] (e em Hive no app).
/// O doc principal `.../config` muitas vezes **não** repete a chave [fretes], que o catálogo
/// usa em [parseFretes]. Sem este merge, o **link web** não via os fretes cadastrados; o app
/// às vezes via por cache Hive ou rascunho local.
Future<void> mergeCatalogFretesManualFromFirestoreSubdoc({
  required String lojaId,
  required String cfgCol,
  required Map<String, dynamic> cfg,
}) async {
  final db = FirebaseFirestore.instance;

  Future<List<Map<String, dynamic>>?> readManualFretes(String col) async {
    try {
      final snap = await db
          .collection('lojas')
          .doc(lojaId)
          .collection(col)
          .doc('fretes')
          .get();
      if (!snap.exists) return null;
      final raw = snap.data();
      if (raw == null) return null;
      final manual = raw['manualFretes'] ?? raw['fretes'];
      if (manual is! List) return null;
      return manual
          .map((e) => asMap(e))
          .where((m) => m.isNotEmpty)
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } catch (_) {
      return null;
    }
  }

  final fromCurrent = await readManualFretes(cfgCol);
  if (fromCurrent != null) {
    // Sempre usa o subdoc de fretes quando existir (inclusive lista vazia),
    // evitando catálogo web ficar preso em frete antigo.
    cfg['fretes'] = fromCurrent;
    return;
  }

  if (cfgCol == 'draft_config') {
    final fromPublished = await readManualFretes('config');
    if (fromPublished != null) {
      cfg['fretes'] = fromPublished;
    }
  }
}

// ===================================================================
// CUPONS
// ===================================================================

/// Parseia cupons do config (cfg['cupons']) e retorna lista normalizada.
/// Filtra cupons expirados.
List<Map<String, dynamic>> parseCupons(Map<String, dynamic> cfg) {
  final cupons = <Map<String, dynamic>>[];
  final cuponsCfg = cfg['cupons'];

  if (cuponsCfg is! List) return cupons;

  final now = DateTime.now();

  for (final e in cuponsCfg) {
    final m = asMap(e);
    if (m.isEmpty) continue;

    final codigo = (m['codigo'] ?? m['code'] ?? m['nome'] ?? '')
        .toString()
        .toUpperCase()
        .trim();
    if (codigo.isEmpty) continue;

    final ativo = m['ativo'] != false;

    final rawTipo = (m['tipo'] ?? 'percent').toString().toLowerCase();
    String tipoNorm;
    switch (rawTipo) {
      case 'percent':
      case 'porcentagem':
      case 'percentual':
        tipoNorm = 'percent';
        break;
      case 'valor':
      case 'valor_fixo':
      case 'fixo':
        tipoNorm = 'valor';
        break;
      case 'frete':
      case 'frete_gratis':
      case 'fretegratis':
        tipoNorm = 'frete_gratis';
        break;
      default:
        tipoNorm = rawTipo;
    }

    final valor = _parseNum(m['valor']);

    final dataFim = asDateTime(m['dataFim']);
    if (dataFim != null && now.isAfter(dataFim)) {
      continue;
    }
    final validade = asDateTime(m['validade'] ?? m['dataValidade']);
    if (validade != null && now.isAfter(validade)) {
      continue;
    }

    final aplicarEm = (m['aplicarEm'] ?? 'produtos').toString();
    final freteGratis = m['freteGratis'] == true;
    final produtoIds = _parseProdutoIdsCfg(m['produtoIds'] ?? m['produtoId']);

    cupons.add({
      'codigo': codigo,
      'tipo': tipoNorm,
      'ativo': ativo,
      'valor': valor,
      'aplicarEm': aplicarEm,
      'freteGratis': freteGratis,
      if (produtoIds.isNotEmpty) 'produtoIds': produtoIds,
      'valorMinimo': _parseNumOrNull(m['valorMinimo'] ?? m['valor_minimo']),
      'dataFim': asDateTime(m['dataFim']),
      'validade': asDateTime(m['validade'] ?? m['dataValidade']),
      'dataValidade': asDateTime(m['dataValidade'] ?? m['validade']),
    });
  }

  return cupons;
}

// ===================================================================
// MÍDIA (LOGO, BANNERS)
// ===================================================================

/// Resultado do parsing de mídia (logo, banners, altura, cores da logo).
class CatalogMediaConfig {
  final String logoUrl;
  final List<String> banners;
  final double bannerH;
  /// Cor da logo no tema claro (hex int, ex. 0xFF212121). Se null, usa padrão escuro.
  final int? logoColorClaro;
  /// Cor da logo no tema escuro (hex int, ex. 0xFFFFFFFF). Se null, sem filtro (logo original).
  final int? logoColorEscuro;

  const CatalogMediaConfig({
    required this.logoUrl,
    required this.banners,
    required this.bannerH,
    this.logoColorClaro,
    this.logoColorEscuro,
  });
}

int? _parseColorInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  final hex = s.startsWith('#') ? s.substring(1) : s;
  return int.tryParse(hex, radix: 16);
}

String _firstNonEmpty(List<dynamic> candidates) {
  for (final c in candidates) {
    if (c == null) continue;
    final s = c.toString().trim();
    if (s.isNotEmpty) return s;
  }
  return '';
}

/// Um item de lista de banners no Firestore pode ser String ou Map (`url`/`image`/etc.).
String? _urlFromBannerListItem(dynamic e) {
  if (e == null) return null;
  if (e is String) {
    final t = e.trim();
    return t.isEmpty ? null : t;
  }
  if (e is Map) {
    for (final k in const [
      'url', 'src', 'image', 'imageUrl', 'image_url', 'href', 'link', 'u',
    ]) {
      final v = e[k];
      if (v is String) {
        final t = v.trim();
        if (t.isNotEmpty) return t;
      }
    }
  }
  final raw = e.toString().trim();
  if (raw.isEmpty) return null;
  if (raw.length > 10 &&
      (raw.startsWith('http://') || raw.startsWith('https://'))) {
    return raw;
  }
  return null;
}

void _addParsedBannerList(List<dynamic> raw, List<String> out) {
  for (final e in raw) {
    final u = _urlFromBannerListItem(e);
    if (u != null) out.add(u);
  }
}

/// Parseia mídia do config (cfg['media']) e retorna logo, banners e altura.
CatalogMediaConfig parseMedia(Map<String, dynamic> cfg, {required bool isWide}) {
  final Map<String, dynamic> media = asMap(cfg['media']);

  final platformKey = isWide ? 'desktop' : 'mobile';
  final Map<String, dynamic> mediaDesktop = asMap(media['desktop']);
  final Map<String, dynamic> mediaMobile = asMap(media['mobile']);

  final mediaPlat = platformKey == 'desktop' ? mediaDesktop : mediaMobile;

  final logoUrl = _firstNonEmpty([
    mediaPlat['logoUrl'],
    mediaPlat['logo'],
    platformKey == 'mobile' ? cfg['logoMobileUrl'] : cfg['logoDesktopUrl'],
    cfg['logoMobileUrl'],
    cfg['logoDesktopUrl'],
    cfg['logo_mobile'],
    cfg['logo_desktop'],
    cfg['logoUrl'],
    cfg['logo'],
    mediaMobile['logoUrl'],
    mediaMobile['logo'],
    mediaDesktop['logoUrl'],
    mediaDesktop['logo'],
  ]);

  final bannerHRaw = mediaPlat['bannerH'];
  final bannerH = (bannerHRaw is num)
      ? bannerHRaw.toDouble()
      : (double.tryParse('$bannerHRaw') ?? (isWide ? 260.0 : 220.0));

  final banners = <String>[];
  final mediaBanners = mediaPlat['banners'];
  if (mediaBanners is List && mediaBanners.isNotEmpty) {
    _addParsedBannerList(mediaBanners, banners);
  } else {
    final specificBanners =
        platformKey == 'mobile' ? cfg['bannersMobile'] : cfg['bannersDesktop'];
    if (specificBanners is List && specificBanners.isNotEmpty) {
      _addParsedBannerList(specificBanners, banners);
    } else {
      final mobileBanners = cfg['bannersMobile'];
      final desktopBanners = cfg['bannersDesktop'];
      if (mobileBanners is List && mobileBanners.isNotEmpty) {
        _addParsedBannerList(mobileBanners, banners);
      } else if (desktopBanners is List && desktopBanners.isNotEmpty) {
        _addParsedBannerList(desktopBanners, banners);
      } else {
        final legacy = cfg['banners'];
        if (legacy is List && legacy.isNotEmpty) {
          _addParsedBannerList(legacy, banners);
        }
      }
    }
  }

  final logoColorClaro = _parseColorInt(media['logoColorClaro'] ?? mediaPlat['logoColorClaro'] ?? cfg['logoColorClaro']);
  final logoColorEscuro = _parseColorInt(media['logoColorEscuro'] ?? mediaPlat['logoColorEscuro'] ?? cfg['logoColorEscuro']);

  return CatalogMediaConfig(
    logoUrl: logoUrl,
    banners: banners,
    bannerH: bannerH,
    logoColorClaro: logoColorClaro,
    logoColorEscuro: logoColorEscuro,
  );
}

// ===================================================================
// VÍDEOS FLUTUANTES
// ===================================================================

/// Config do carrossel de vídeos flutuantes
class VideoCarouselConfig {
  final bool enabled;
  final List<String> urls;
  /// Formato do vídeo do produto (overlay): 'circle' ou 'square'
  final String productVideoShape;
  /// Formato do card flutuante: 'circle' ou 'square'
  final String videoCarouselShape;

  const VideoCarouselConfig({
    required this.enabled,
    required this.urls,
    this.productVideoShape = 'circle',
    this.videoCarouselShape = 'circle',
  });

  bool get productVideoIsCircle => productVideoShape != 'square';
  bool get carouselIsCircle => videoCarouselShape != 'square';
}

VideoCarouselConfig parseVideoCarousel(Map<String, dynamic> cfg) {
  final enabled = cfg['videoCarouselEnabled'] == true;
  final urlsRaw = cfg['videoCarouselUrls'];
  final urls = (urlsRaw is List)
      ? urlsRaw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty && s.startsWith('http')).take(3).toList()
      : <String>[];
  final shapeStr = (cfg['productVideoShape'] ?? cfg['videoCarouselShape'] ?? 'circle').toString().toLowerCase();
  final productVideoShape = shapeStr == 'square' ? 'square' : 'circle';
  final carouselShapeStr = (cfg['videoCarouselShape'] ?? 'circle').toString().toLowerCase();
  final videoCarouselShape = carouselShapeStr == 'square' ? 'square' : 'circle';
  return VideoCarouselConfig(
    enabled: enabled && urls.isNotEmpty,
    urls: urls,
    productVideoShape: productVideoShape,
    videoCarouselShape: videoCarouselShape,
  );
}
