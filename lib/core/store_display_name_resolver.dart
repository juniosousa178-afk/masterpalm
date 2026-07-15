// M3.8 S2-R6.2 — resolução canônica do nome de exibição da loja (Home).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'hive_box_names.dart';
import 'logger.dart';

/// Resultado da resolução (auditoria / Home).
class StoreDisplayNameResult {
  const StoreDisplayNameResult({
    required this.name,
    required this.source,
    required this.resolved,
    this.field,
  });

  final String name;
  /// firestore | hive_sessao | hive_config | slug | fallback
  final String source;
  final String? field;
  /// false apenas quando caiu em "Minha Loja".
  final bool resolved;

  static const fallbackName = 'Minha Loja';
}

/// Extrai e normaliza o nome público da loja (nunca e-mail/login/uid).
abstract final class StoreDisplayNameResolver {
  static const _flatFields = <String>[
    'nome',
    'nomeLoja',
    'nome_loja',
    'nomeFantasia',
    'name',
    'razaoSocial',
    'titulo',
    'storeName',
    'store_name',
  ];

  /// Preferências tipográficas genéricas a evitar se houver fonte melhor.
  static bool isWeakPlaceholder(String value) {
    final v = value.trim().toLowerCase();
    return v.isEmpty ||
        v == 'null' ||
        v == 'undefined' ||
        v == 'minha loja' ||
        v == 'minha-loja' ||
        v == 'loja';
  }

  static bool looksLikeUserCredential(String value) {
    final v = value.trim();
    if (v.isEmpty) return true;
    if (v.contains('@')) return true;
    // UID / docId Firestore típico (não é slug humano).
    if (RegExp(r'^[0-9a-fA-F]{20,}$').hasMatch(v)) return true;
    if (RegExp(r'^[0-9a-fA-F-]{28,}$').hasMatch(v)) return true;
    return false;
  }

  /// Normaliza dynamic → String utilizável, ou null.
  static String? normalizeCandidate(dynamic raw) {
    if (raw == null) return null;
    if (raw is! String && raw is! num && raw is! bool) {
      // Map/List não são nome.
      return null;
    }
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    if (s.toLowerCase() == 'null' || s.toLowerCase() == 'undefined') {
      return null;
    }
    if (looksLikeUserCredential(s)) return null;
    return s;
  }

  static String? _pickFromFlatMap(Map<dynamic, dynamic> data) {
    for (final key in _flatFields) {
      final n = normalizeCandidate(data[key]);
      if (n != null && !isWeakPlaceholder(n)) return n;
    }
    // Aceita placeholder fraco só se for a única opção flat.
    for (final key in _flatFields) {
      final n = normalizeCandidate(data[key]);
      if (n != null) return n;
    }
    return null;
  }

  static Map<dynamic, dynamic>? _asMap(dynamic v) {
    if (v is Map) return Map<dynamic, dynamic>.from(v);
    return null;
  }

  /// Lê campos planos + identidade aninhada (V3 draft/published).
  static String? pickFromLojaMap(Map<dynamic, dynamic>? data) {
    if (data == null || data.isEmpty) return null;

    final flat = _pickFromFlatMap(data);
    if (flat != null && !isWeakPlaceholder(flat)) {
      return flat;
    }

    final nestedCandidates = <Map<dynamic, dynamic>?>[
      _asMap(data['identidade']),
      _asMap(_asMap(data['published'])?['identidade']),
      _asMap(_asMap(data['draft'])?['identidade']),
      _asMap(data['empresa']),
      _asMap(data['store']),
    ];

    String? weak;
    for (final m in nestedCandidates) {
      if (m == null) continue;
      final n = _pickFromFlatMap(m);
      if (n == null) continue;
      if (!isWeakPlaceholder(n)) return n;
      weak ??= n;
    }

    return flat ?? weak;
  }

  /// Campo que produziu o valor (para logs).
  static String? fieldHitFromLojaMap(Map<dynamic, dynamic>? data) {
    if (data == null) return null;
    for (final key in _flatFields) {
      final n = normalizeCandidate(data[key]);
      if (n != null && !isWeakPlaceholder(n)) return key;
    }
    final identidade = _asMap(data['identidade']);
    if (identidade != null) {
      for (final key in _flatFields) {
        final n = normalizeCandidate(identidade[key]);
        if (n != null && !isWeakPlaceholder(n)) return 'identidade.$key';
      }
    }
    final published = _asMap(_asMap(data['published'])?['identidade']);
    if (published != null) {
      for (final key in _flatFields) {
        final n = normalizeCandidate(published[key]);
        if (n != null && !isWeakPlaceholder(n)) {
          return 'published.identidade.$key';
        }
      }
    }
    return null;
  }

  /// Slug humano `nathy-pratas-e-folheados` → `Nathy Pratas E Folheados`.
  static String? formatSlug(String? slug) {
    final s = (slug ?? '').trim();
    if (s.isEmpty || looksLikeUserCredential(s)) return null;
    if (!s.contains('-') && !s.contains('_') && s.length < 3) return null;
    // Aceita slug com hífens/underscores; evita misturar UID.
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{1,80}$').hasMatch(s)) {
      return null;
    }
    final parts = s
        .split(RegExp(r'[-_]+'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;
    final titled = parts
        .map((p) {
          final lower = p.toLowerCase();
          return '${lower[0].toUpperCase()}${lower.substring(1)}';
        })
        .join(' ');
    if (isWeakPlaceholder(titled)) return null;
    return titled;
  }

  /// Texto da saudação na Home: `null` = skeleton (ainda a resolver).
  /// Nunca devolve e-mail/UID; “Minha Loja” só após resolução sem fontes.
  static String? homeGreetingLabel({
    required bool resolving,
    required String currentName,
  }) {
    final n = normalizeCandidate(currentName);
    if (n != null && !isWeakPlaceholder(n)) return n;
    if (resolving) return null;
    return StoreDisplayNameResult.fallbackName;
  }

  /// Resolução síncrona a partir de fontes já carregadas (testes + Home).
  ///
  /// Ordem: Firestore loja → Firestore config → Hive sessão → Hive config →
  /// slug formatado → “Minha Loja”.
  static StoreDisplayNameResult resolveFromSources({
    String? hiveSessaoNome,
    Map<dynamic, dynamic>? firestoreLoja,
    Map<dynamic, dynamic>? firestoreConfig,
    String? hiveConfigStoreName,
    String? slug,
  }) {
    final fromLoja = pickFromLojaMap(firestoreLoja);
    if (fromLoja != null && !isWeakPlaceholder(fromLoja)) {
      return StoreDisplayNameResult(
        name: fromLoja,
        source: 'firestore',
        field: fieldHitFromLojaMap(firestoreLoja) ?? 'nome',
        resolved: true,
      );
    }

    final fromCfg = pickFromLojaMap(firestoreConfig);
    if (fromCfg != null && !isWeakPlaceholder(fromCfg)) {
      return StoreDisplayNameResult(
        name: fromCfg,
        source: 'firestore',
        field: 'config/${fieldHitFromLojaMap(firestoreConfig) ?? 'nome'}',
        resolved: true,
      );
    }

    final sessao = normalizeCandidate(hiveSessaoNome);
    if (sessao != null && !isWeakPlaceholder(sessao)) {
      return StoreDisplayNameResult(
        name: sessao,
        source: 'hive_sessao',
        field: 'nome_loja',
        resolved: true,
      );
    }

    final hiveCfg = normalizeCandidate(hiveConfigStoreName);
    if (hiveCfg != null && !isWeakPlaceholder(hiveCfg)) {
      return StoreDisplayNameResult(
        name: hiveCfg,
        source: 'hive_config',
        field: 'store_name',
        resolved: true,
      );
    }

    // Placeholders fracos das fontes acima, se foi o melhor disponível.
    final weak = fromLoja ?? fromCfg ?? sessao ?? hiveCfg;
    if (weak != null) {
      return StoreDisplayNameResult(
        name: weak,
        source: 'weak',
        field: 'placeholder',
        resolved: true,
      );
    }

    final slugFmt = formatSlug(slug);
    if (slugFmt != null) {
      return StoreDisplayNameResult(
        name: slugFmt,
        source: 'slug',
        field: 'slug',
        resolved: true,
      );
    }

    return const StoreDisplayNameResult(
      name: StoreDisplayNameResult.fallbackName,
      source: 'fallback',
      field: null,
      resolved: false,
    );
  }

  /// Carrega Firestore/Hive e resolve.
  static Future<StoreDisplayNameResult> resolve({
    required String lojaId,
    required Box sessao,
    String? slugPublico,
    bool debugLog = false,
  }) async {
    final lid = lojaId.trim();
    final slug = (slugPublico ?? '').trim();

    final hiveSessao = (sessao.get('nome_loja') ?? sessao.get('nomeLoja') ?? '')
        .toString();

    Map<String, dynamic>? lojaMap;
    Map<String, dynamic>? cfgMap;
    String? hiveConfigName;

    if (lid.isNotEmpty) {
      try {
        final doc =
            await FirebaseFirestore.instance.collection('lojas').doc(lid).get();
        final d = doc.data();
        if (d != null) lojaMap = Map<String, dynamic>.from(d);
      } catch (_) {}

      try {
        final cfg = await FirebaseFirestore.instance
            .collection('lojas')
            .doc(lid)
            .collection('config')
            .doc('config')
            .get();
        final raw = cfg.data();
        if (raw != null) {
          cfgMap = Map<String, dynamic>.from(raw);
          // V3: prefer published/draft identidade já coberto por pickFromLojaMap.
          final published = raw['published'];
          if (published is Map) {
            cfgMap = {
              ...cfgMap,
              ...Map<String, dynamic>.from(published),
            };
          }
        }
      } catch (_) {}

      try {
        final boxName = HiveBoxNames.config();
        final box = Hive.isBoxOpen(boxName)
            ? Hive.box(boxName)
            : await Hive.openBox(boxName);
        hiveConfigName = (box.get('store_name') ?? '').toString();
      } catch (_) {}
    }

    final result = resolveFromSources(
      hiveSessaoNome: hiveSessao,
      firestoreLoja: lojaMap,
      firestoreConfig: cfgMap,
      hiveConfigStoreName: hiveConfigName,
      slug: slug.isNotEmpty ? slug : lid,
    );

    if (debugLog || kDebugMode) {
      logD(
        '[M38-STORE-NAME] lojaIdLen=${lid.length} '
        'source=${result.source} field=${result.field ?? '-'} '
        'resolved=${result.resolved}',
      );
    }

    if (result.resolved &&
        result.source != 'slug' &&
        result.source != 'fallback' &&
        result.source != 'weak') {
      try {
        await sessao.put('nome_loja', result.name);
      } catch (_) {}
    }

    return result;
  }
}
