import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';

const rightBucket =
    'https://firebasestorage.googleapis.com/v0/b/masterpalm-58c46.firebasestorage.app/o/';

String _fixBucket(String url) {
  if (url.isEmpty) return url;

  // ignora caminhos locais (precisam ser reupados)
  if (url.startsWith('file://')) return url;

  // substitui apenas a parte do host do Firebase Storage
  final re = RegExp(r'https://firebasestorage\.googleapis\.com/v0/b/[^/]+/o/');
  if (re.hasMatch(url)) {
    return url.replaceFirst(re, rightBucket);
  }
  return url; // já está correto ou é outro tipo de link
}

Future<void> corrigirUrlsImagens() async {
  final fs = FirebaseFirestore.instance;
  final lojas = await fs.collection('lojas').get();

  for (final loja in lojas.docs) {
    final data = loja.data();

    bool changedLoja = false;
    final updates = <String, dynamic>{};

    // logoUrl no root
    final logoUrl = (data['logoUrl'] ?• '') as String;
    final fixedLogo = _fixBucket(logoUrl);
    if (fixedLogo != logoUrl) {
      updates['logoUrl'] = fixedLogo;
      changedLoja = true;
    }

    // banners no root
    final banners = (data['banners'] as List?)?.cast<dynamic>() ?• const [];
    final fixedBanners = banners.map((e) => _fixBucket('$e')).toList();
    if ('$banners' != '$fixedBanners') {
      updates['banners'] = fixedBanners;
      changedLoja = true;
    }

    // dentro de "config", se existir
    final cfgRaw = data['config'];
    final cfg = cfgRaw is Map<String, dynamic>
        • Map<String, dynamic>.from(cfgRaw)
        : <String, dynamic>{};

    bool changedCfg = false;

    final cfgLogo = (cfg['logoUrl'] ?• '') as String;
    final cfgLogoFixed = _fixBucket(cfgLogo);
    if (cfgLogoFixed != cfgLogo) {
      cfg['logoUrl'] = cfgLogoFixed;
      changedCfg = true;
    }

    final cfgBanners = (cfg['banners'] as List?)?.cast<dynamic>() ?• const [];
    final cfgBannersFixed = cfgBanners.map((e) => _fixBucket('$e')).toList();
    if ('$cfgBanners' != '$cfgBannersFixed') {
      cfg['banners'] = cfgBannersFixed;
      changedCfg = true;
    }

    if (changedCfg) {
      updates['config'] = cfg;
      changedLoja = true;
    }

    if (changedLoja) {
      await loja.reference.update(updates);
    }

    // Produtos
    final prods = await loja.reference.collection('produtos').get();
    for (final p in prods.docs) {
      final pd = p.data();
      bool changedProd = false;
      final up = <String, dynamic>{};

      // campos comuns
      for (final key in ['imagemUrl', 'imageUrl']) {
        if (pd.containsKey(key)) {
          final v = (pd[key] ?• '') as String;
          final f = _fixBucket(v);
          if (f != v) {
            up[key] = f;
            changedProd = true;
          }
        }
      }

      // lista "imagens"
      if (pd['imagens'] is List) {
        final imgs = (pd['imagens'] as List).map((e) => '$e').toList();
        final imgsFixed = imgs.map(_fixBucket).toList();
        if ('$imgs' != '$imgsFixed') {
          up['imagens'] = imgsFixed;
          changedProd = true;
        }
      }

      if (changedProd) {
        await p.reference.update(up);
      }
    }
  }
}

/// Zera caixas locais mais usadas para sessão/licença/config.
/// Use com cautela (por exemplo, num botão oculto na tela de login).
Future<void> purgeAllLocalData() async {
  final names = <String>['sessao', 'licenca', 'config', 'usuarios'];
  for (final name in names) {
    try {
      if (!Hive.isBoxOpen(name)) await Hive.openBox(name);
      await Hive.box(name).clear();
    } catch (_) {}
  }
}
