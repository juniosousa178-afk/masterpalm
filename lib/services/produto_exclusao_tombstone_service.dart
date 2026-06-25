// Tombstone pós-exclusão: Firestore + cache local. Impede ressurreição por sync/fila/merge.
//
// Coleção: lojas/{lojaId}/exclusao_produto/{estoqueDocId}
// { p: true = produto inteiro excluído, p: false + v: { "V::..": true, "T::..": true } }

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/firestore_access_guard.dart';
import '../core/logger.dart';
import '../core/produto_variacao_extra.dart';
import '../models/produto.dart';
import 'firestore_paths.dart';

const _prefsKey = 'exclusao_produto_tomb_v1';
const _sep = '\u001E';
const _pfxV = 'V::';
const _pfxT = 'T::';
const _pfxE = 'E::';

class _LojaTomb {
  const _LojaTomb(
    this.produtoCheio,
    this.varKeys,
  );
  final Set<String> produtoCheio;
  final Map<String, Set<String>> varKeys;
}

class ProdutoExclusaoTombstoneService {
  ProdutoExclusaoTombstoneService._();

  @visibleForTesting
  static FirebaseFirestore? debugFirestoreOverride;

  static FirebaseFirestore get _db => FirestoreAccessGuard.resolve(
        override: debugFirestoreOverride,
      );
  static final Map<String, _LojaTomb> _byLoja = {};
  static String? _lastHydrateLoja;
  static DateTime? _lastHydrateAt;
  static const _hydrateTtl = Duration(minutes: 3);
  static bool _prefsCarregou = false;

  static _LojaTomb _loja(String l) {
    l = l.trim();
    return _byLoja[l] ??= _LojaTomb(
      <String>{},
      <String, Set<String>>{},
    );
  }

  static String tKeySoloTamanho(String tamanho) => '$_pfxT${tamanho.trim()}';

  static String vKeyCelula(String t, String c) =>
      '$_pfxV${t.trim()}$_sep${c.trim()}$_sep';

  static String eKey(String outer, String cor) => '$_pfxE${outer.trim()}$_sep${cor.trim()}';

  /// Mesma regra de [Produto._resolverCorKeyParaTamanho] para checagem de tombstone.
  static String normalizarCorParaChecagem({
    required String tamanho,
    required String cor,
    Map<String, dynamic>? variacoes,
  }) {
    final tam = tamanho.trim();
    final corTrim = cor.trim();
    if (tam.isEmpty) return corTrim.isEmpty ? 'sem-cor' : corTrim;
    if (corTrim.isNotEmpty) return corTrim;
    if (variacoes == null) return 'sem-cor';
    final mapaCor = variacoes[tam];
    if (mapaCor is! Map) return 'sem-cor';
    final coresValidas = mapaCor.keys
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty && e != 'sem-cor')
        .toSet()
        .toList();
    if (coresValidas.length == 1) return coresValidas.first;
    return 'sem-cor';
  }

  @visibleForTesting
  static void resetCacheForTests() {
    _byLoja.clear();
    _lastHydrateLoja = null;
    _lastHydrateAt = null;
    _prefsCarregou = false;
    debugFirestoreOverride = null;
    FirestoreAccessGuard.resetForTests();
  }

  // --- chaves a partir de mapa remoto / local (mesma regra em diff e filtro) ---

  static Set<String> _flattenVarKeys(Map<String, dynamic>? variacoes) {
    if (variacoes == null || variacoes.isEmpty) return {};
    final o = <String>{};
    for (final e in variacoes.entries) {
      final t = e.key.toString();
      if (e.value is Map) {
        for (final c in (e.value as Map).keys) {
          o.add(vKeyCelula(t, c.toString()));
        }
      }
    }
    return o;
  }

  static Set<String> _keysEstoquePorTamanho(Map? m) {
    if (m == null || m.isEmpty) return {};
    return m.keys.map((k) => tKeySoloTamanho(k.toString())).toSet();
  }

  static Future<void> _garantirPrefsUmaVez() async {
    if (_prefsCarregou) return;
    _prefsCarregou = true;
    await _loadFromPrefs();
  }

  static Future<void> ensureHydratedForLoja(String lojaId) async {
    final loja = lojaId.trim();
    if (loja.isEmpty) return;
    await _garantirPrefsUmaVez();
    if (_lastHydrateLoja == loja &&
        _lastHydrateAt != null &&
        DateTime.now().difference(_lastHydrateAt!) < _hydrateTtl) {
      return;
    }
    try {
      final snap = await _db
          .collection('lojas')
          .doc(loja)
          .collection(FSPaths.exclusaoProdutoCol)
          .get();
      final t = _loja(loja);
      t.produtoCheio.clear();
      t.varKeys.clear();
      for (final d in snap.docs) {
        final data = d.data();
        if (data['p'] == true) {
          t.produtoCheio.add(d.id);
        }
        final vm = data['v'];
        if (vm is Map) {
          final s = t.varKeys.putIfAbsent(d.id, () => <String>{});
          for (final e in vm.entries) {
            if (e.value == true) s.add(e.key.toString());
          }
        }
      }
      _lastHydrateLoja = loja;
      _lastHydrateAt = DateTime.now();
      await _savePrefs();
    } catch (e) {
      if (kDebugMode) {
        logW('⚠️ [TOMBSTONE] ensureHydrate (type=${e.runtimeType})', tag: 'TOMBSTONE');
      }
    }
  }

  static Future<void> _savePrefs() async {
    final enc = <String, dynamic>{};
    for (final e in _byLoja.entries) {
      enc[e.key] = {
        'p': e.value.produtoCheio.toList(),
        'v': e.value.varKeys.map(
          (k, v) => MapEntry(k, v.toList()),
        ),
      };
    }
    final p = await SharedPreferences.getInstance();
    if (enc.isEmpty) {
      await p.remove(_prefsKey);
    } else {
      await p.setString(_prefsKey, jsonEncode(enc));
    }
  }

  static Future<void> _loadFromPrefs() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_prefsKey);
    if (raw == null) return;
    try {
      final o = jsonDecode(raw);
      if (o is! Map) return;
      o.forEach((k, v) {
        if (k is! String) return;
        if (v is! Map) return;
        final t = _loja(k);
        t.produtoCheio
          ..clear()
          ..addAll(
            (v['p'] is List)
                ? (v['p'] as List).map((e) => e.toString())
                : <String>[],
          );
        t.varKeys.clear();
        final vm = v['v'];
        if (vm is Map) {
          vm.forEach((dk, dv) {
            if (dk is! String) return;
            if (dv is List) {
              t.varKeys[dk] = dv.map((e) => e.toString()).toSet();
            }
          });
        }
      });
    } catch (e) {
      if (kDebugMode) logW('⚠️ [TOMBSTONE] JSON prefs: $e');
    }
  }

  static bool isProdutoBloqueadoSinc(String lojaId, String id) {
    return _loja(lojaId).produtoCheio.contains(id.trim());
  }

  static bool isVarChaveBloqueadaSinc(
    String lojaId,
    String estoqueDocId,
    String chave,
  ) {
    final t = _loja(lojaId);
    if (t.produtoCheio.contains(estoqueDocId)) return true;
    return t.varKeys[estoqueDocId]?.contains(chave) ?? false;
  }

  static Future<bool> isProdutoBloqueadoRemoto({
    required String lojaId,
    required String estoqueDocId,
  }) async {
    final id = estoqueDocId.trim();
    final l = lojaId.trim();
    if (l.isEmpty || id.isEmpty) return false;
    await _garantirPrefsUmaVez();
    await ensureHydratedForLoja(l);
    if (_loja(l).produtoCheio.contains(id)) return true;
    try {
      final snap = await _db
          .collection('lojas')
          .doc(l)
          .collection(FSPaths.exclusaoProdutoCol)
          .doc(id)
          .get();
      if (snap.exists) {
        final p = snap.data()?['p'];
        if (p == true) {
          _loja(l).produtoCheio.add(id);
          _lastHydrateLoja = l;
          _lastHydrateAt = DateTime.now();
          await _savePrefs();
        }
        return p == true;
      }
    } catch (_) {}
    return false;
  }

  static const int _maxTentativasExclusaoProd = 3;
  static const int _maxTentativasTombVarSessao = 3;

  /// Mesma regra que [filtrarMapVariacoes] (chaves `V::` por tamanho + cor de primeiro nível do mapa).
  static Set<String> chavesCelulaDeVariacoes(
    Map<String, dynamic>? variacoes,
  ) =>
      _flattenVarKeys(variacoes);

  static Set<String> chavesSoloTamanhoDeEstoquePorTamanho(Map? m) =>
      _keysEstoquePorTamanho(m);

  /// `true` se a escrita com `p: true` no Firestore e cache local forem confirmadas.
  static Future<bool> registrarExclusaoProdutoCompleto({
    required String lojaId,
    required String estoqueDocId,
    String? slug,
  }) async {
    final l = lojaId.trim();
    final id = estoqueDocId.trim();
    if (l.isEmpty || id.isEmpty) return false;

    Object? lastErr;
    for (var tent = 0; tent < _maxTentativasExclusaoProd; tent++) {
      if (tent > 0) {
        await Future<void>.delayed(Duration(milliseconds: 180 * tent));
      }
      try {
        await _db
            .collection('lojas')
            .doc(l)
            .collection(FSPaths.exclusaoProdutoCol)
            .doc(id)
            .set(
              {
                'p': true,
                'v': FieldValue.delete(),
                'sl': slug,
                'at': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
        _loja(l).produtoCheio.add(id);
        await _savePrefs();
        logD(
          '[TOMBSTONE_OK] exclusao_produto gravado: loja=$l doc=$id',
          tag: 'TOMBSTONE',
        );
        return true;
      } catch (e, st) {
        lastErr = e;
        final msg = e.toString();
        final denegado = msg.toLowerCase().contains('permission-denied') ||
            msg.toLowerCase().contains('permission');
        logW(
          '[TOMBSTONE] tentativa ${tent + 1}/$_maxTentativasExclusaoProd '
          'falhou (denied=$denegado): $msg',
          tag: 'TOMBSTONE',
        );
        if (kDebugMode) {
          logW('⚠️ [TOMBSTONE] stack: $st', tag: 'TOMBSTONE');
        }
      }
    }
    final denegadoF = lastErr != null &&
        (lastErr.toString().toLowerCase().contains('permission-denied') ||
            lastErr.toString().toLowerCase().contains('permission'));
    logE(
      '[TOMBSTONE_FAIL] exclusao_produto nao persistiu apos $_maxTentativasExclusaoProd; '
      'RISCO: outro aparelho ainda pode recriar o doc. permission_denied=$denegadoF loja=$l id=$id',
      error: lastErr,
      tag: 'TOMBSTONE',
    );
    return false;
  }

  /// Remoção explícita de linha(s) de variação no cadastro: merge em `v`, mantém [p: false] (não exclui o produto).
  static Future<bool> registrarTombstoneExclusaoVarSessaoExplicita({
    required String lojaId,
    required String estoqueDocId,
    required Set<String> chaves,
  }) async {
    final l = lojaId.trim();
    final id = estoqueDocId.trim();
    if (l.isEmpty || id.isEmpty || chaves.isEmpty) return true;
    if (isProdutoBloqueadoSinc(l, id)) return true;

    Object? lastErr;
    for (var tent = 0; tent < _maxTentativasTombVarSessao; tent++) {
      if (tent > 0) {
        await Future<void>.delayed(Duration(milliseconds: 180 * tent));
      }
      try {
        await _db
            .collection('lojas')
            .doc(l)
            .collection(FSPaths.exclusaoProdutoCol)
            .doc(id)
            .set(
              {
                'p': false,
                'v': {for (final e in chaves) e: true},
                'at': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
        final s = _loja(l).varKeys.putIfAbsent(id, () => <String>{})..addAll(chaves);
        await _savePrefs();
        logD(
          '[TOMBSTONE_OK] exclusao var sessao: loja=$l doc=$id n=${s.length} keys=${chaves.length}',
          tag: 'TOMBSTONE',
        );
        return true;
      } catch (e, st) {
        lastErr = e;
        final msg = e.toString();
        final denegado = msg.toLowerCase().contains('permission-denied') ||
            msg.toLowerCase().contains('permission');
        logW(
          '[TOMBSTONE_VAR] tent ${tent + 1}/$_maxTentativasTombVarSessao '
          'falhou (denied=$denegado): $msg',
          tag: 'TOMBSTONE',
        );
        if (kDebugMode) {
          logW('⚠️ [TOMBSTONE_VAR] stack: $st', tag: 'TOMBSTONE');
        }
      }
    }
    logE(
      '[TOMBSTONE_VAR_FAIL] nao persistiu v apos $_maxTentativasTombVarSessao; '
      'loja=$l id=$id',
      error: lastErr,
      tag: 'TOMBSTONE',
    );
    return false;
  }

  /// Não usado no `syncProduto` genérico (falso positivo com payload local incompleto).
  /// Reservado a fluxos explícitos no futuro (p.ex. fechar linha de variação com prova de intenção).
  static Future<void> registrarDiferencaVarAposCompararRemoto({
    required String lojaId,
    required String estoqueDocId,
    required Map<String, dynamic>? dataRemoto,
    required Map<String, dynamic> variacoesLocalPush,
    required Map<String, int> estoquePorTamanhoLocalPush,
  }) async {
    if (dataRemoto == null) return;
    final l = lojaId.trim();
    final id = estoqueDocId.trim();
    if (l.isEmpty || id.isEmpty) return;
    if (isProdutoBloqueadoSinc(l, id)) return;

    final rV = _flattenVarKeys(
      (dataRemoto['variacoes'] as Map<String, dynamic>?) != null
          ? Map<String, dynamic>.from(dataRemoto['variacoes']! as Map)
          : null,
    );
    final lV = _flattenVarKeys(variacoesLocalPush);
    final er = dataRemoto['estoquePorTamanho'];
    final rT = _keysEstoquePorTamanho(er is Map ? er : null);
    final lT = _keysEstoquePorTamanho(estoquePorTamanhoLocalPush);
    final novos = rV.difference(lV)..addAll(rT.difference(lT));
    if (novos.isEmpty) return;

    final s = _loja(l).varKeys.putIfAbsent(id, () => <String>{})..addAll(novos);
    try {
      await _db
          .collection('lojas')
          .doc(l)
          .collection(FSPaths.exclusaoProdutoCol)
          .doc(id)
          .set(
            {
              'p': false,
              'v': {for (final e in s) e: true},
              'at': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
    } catch (e) {
      if (kDebugMode) {
        logW('⚠️ [TOMBSTONE] var merge (type=${e.runtimeType})', tag: 'TOMBSTONE');
      }
    }
    await _savePrefs();
  }

  static Map<String, dynamic> filtrarMapVariacoes(
    String lojaId,
    String estoqueDocId,
    Map<String, dynamic> m,
  ) {
    if (m.isEmpty) return m;
    if (isProdutoBloqueadoSinc(lojaId, estoqueDocId)) {
      if (kDebugMode) {
        logD(
          '[TOMBSTONE_BLOCK] variação removida: prod excl $estoqueDocId',
          tag: 'TOMBSTONE',
        );
      }
      return {};
    }
    final bloq = _loja(lojaId).varKeys[estoqueDocId] ?? <String>{};
    if (bloq.isEmpty) return m;
    final out = Map<String, dynamic>.from(m);
    for (final e in m.entries) {
      if (e.value is Map) {
        final inner = Map<String, dynamic>.from(e.value as Map);
        for (final k in (e.value as Map).keys) {
          if (bloq.contains(vKeyCelula(e.key, k.toString()))) {
            // Célula ainda presente no payload remoto/local = tombstone legado; manter.
            continue;
          }
          inner.remove(k);
          if (kDebugMode) {
            logD(
              '[TOMBSTONE_BLOCK] var excl do payload: ${e.key} / $k',
              tag: 'TOMBSTONE',
            );
          }
        }
        if (inner.isEmpty) {
          out.remove(e.key);
        } else {
          out[e.key] = inner;
        }
      }
    }
    return out;
  }

  static Map<String, int> filtrarEstoquePorTamanho(
    String lojaId,
    String estoqueDocId,
    Map<String, int> m,
  ) {
    if (m.isEmpty) return m;
    if (isProdutoBloqueadoSinc(lojaId, estoqueDocId)) {
      if (kDebugMode) {
        logD(
          '[TOMBSTONE_BLOCK] estoquePorTam limpo: prod excl $estoqueDocId',
          tag: 'TOMBSTONE',
        );
      }
      return {};
    }
    final bloq = _loja(lojaId).varKeys[estoqueDocId] ?? <String>{};
    if (bloq.isEmpty) return m;
    final out = Map<String, int>.from(m);
    for (final k in m.keys) {
      if (bloq.contains(tKeySoloTamanho(k))) {
        // Tamanho ainda no mapa = tombstone T:: legado; manter.
        continue;
      }
      out.remove(k);
      if (kDebugMode) {
        logD('[TOMBSTONE_BLOCK] tam excl: $k', tag: 'TOMBSTONE');
      }
    }
    return out;
  }

  static Map<String, dynamic> filtrarVariacoesExtraTipo(
    String lojaId,
    String estoqueDocId,
    Map<String, dynamic> m,
  ) {
    if (m.isEmpty) return m;
    if (isProdutoBloqueadoSinc(lojaId, estoqueDocId)) return {};
    final bloq = _loja(lojaId).varKeys[estoqueDocId] ?? <String>{};
    if (bloq.isEmpty) return m;
    final out = Map<String, dynamic>.from(m);
    for (final outer in m.keys) {
      final raw = m[outer];
      if (raw is! Map) continue;
      var innerM = Map<String, dynamic>.from(raw);
      for (final c in raw.keys) {
        if (bloq.contains(eKey(outer.toString(), c.toString()))) {
          innerM.remove(c);
          if (kDebugMode) {
            logD('[TOMBSTONE_BLOCK] extra excl: $outer / $c', tag: 'TOMBSTONE');
          }
        }
      }
      if (innerM.isEmpty) {
        out.remove(outer);
      } else {
        out[outer] = innerM;
      }
    }
    return out;
  }

  /// Ajusta o doc de estoque logo após leitura no pull.
  static Map<String, dynamic> filtrarDocEstoqueParaPull(
    String lojaId,
    String docId,
    Map<String, dynamic> d,
  ) {
    if (d.isEmpty) return d;
    final w = Map<String, dynamic>.from(d);
    final v0 = w['variacoes'];
    if (v0 is Map) {
      w['variacoes'] = filtrarMapVariacoes(
        lojaId,
        docId,
        Map<String, dynamic>.from(v0),
      );
    }
    final e0 = w['estoquePorTamanho'];
    if (e0 is Map) {
      w['estoquePorTamanho'] = filtrarEstoquePorTamanho(
        lojaId,
        docId,
        e0.map(
          (k, v) => MapEntry(
            k.toString(),
            ProdutoVariacaoExtra.valorFirestoreComoInt(v),
          ),
        ),
      );
    }
    final x0 = w['variacoesExtraTipo'];
    if (x0 is Map) {
      w['variacoesExtraTipo'] = filtrarVariacoesExtraTipo(
        lojaId,
        docId,
        Map<String, dynamic>.from(x0),
      );
    }
    return w;
  }

  /// Pull com [preserveLocalEdits] (fila pendente / `updatedAt` local) não aplica
  /// [variacoes] remotas; remove no Hive células/tamanhos cobertos por [exclusao_produto] `v` ou `p`.
  static void filtrarMapasLocaisDoProdutoPeloTombstone(
    String lojaId,
    String estoqueDocId,
    Produto p,
  ) {
    final id = estoqueDocId.trim();
    final l = lojaId.trim();
    if (l.isEmpty || id.isEmpty) return;
    if (isProdutoBloqueadoSinc(l, id)) return;
    if (p.variacoes != null && p.variacoes!.isNotEmpty) {
      final f = filtrarMapVariacoes(
        l,
        id,
        Map<String, dynamic>.from(p.variacoes!),
      );
      p.variacoes = f.isEmpty ? null : f;
    }
    if (p.estoquePorTamanho.isNotEmpty) {
      p.estoquePorTamanho = filtrarEstoquePorTamanho(
        l,
        id,
        p.estoquePorTamanho,
      );
    }
    if (p.variacoesExtraTipo != null && p.variacoesExtraTipo!.isNotEmpty) {
      final f = filtrarVariacoesExtraTipo(
        l,
        id,
        Map<String, dynamic>.from(p.variacoesExtraTipo!),
      );
      p.variacoesExtraTipo = f.isEmpty ? null : f;
    }
  }

  static Future<Map<String, dynamic>?> _lerDocEstoqueRemoto(
    String lojaId,
    String estoqueDocId,
  ) async {
    final l = lojaId.trim();
    final id = estoqueDocId.trim();
    if (l.isEmpty || id.isEmpty) return null;
    try {
      final snap = await _db
          .collection('lojas')
          .doc(l)
          .collection(FSPaths.estoqueProdutosCol)
          .doc(id)
          .get();
      if (!snap.exists) return null;
      return snap.data();
    } catch (_) {
      return null;
    }
  }

  static bool _celulaAtivaNoMapaRemoto({
    required Map<String, dynamic>? data,
    required String tamanho,
    required String corKey,
  }) {
    if (data == null || tamanho.isEmpty) return false;
    final v = data['variacoes'];
    if (v is Map) {
      final mapaTam = v[tamanho];
      if (mapaTam is Map && mapaTam.containsKey(corKey)) {
        return ProdutoVariacaoExtra.somarCelula(mapaTam[corKey]) > 0;
      }
    }
    final ep = data['estoquePorTamanho'];
    if (ep is Map) {
      return ProdutoVariacaoExtra.valorFirestoreComoInt(ep[tamanho]) > 0;
    }
    return false;
  }

  static bool _tombstoneIgnoradoPorCelulaAtiva({
    required String chave,
    required Map<String, dynamic>? dataRemoto,
    required String tamanho,
    required String corKey,
  }) {
    if (dataRemoto == null) return false;
    if (chave.startsWith(_pfxV)) {
      return _celulaAtivaNoMapaRemoto(
        data: dataRemoto,
        tamanho: tamanho,
        corKey: corKey,
      );
    }
    if (chave.startsWith(_pfxT)) {
      final tamTomb = chave.substring(_pfxT.length);
      if (tamTomb != tamanho.trim()) return false;
      return _celulaAtivaNoMapaRemoto(
        data: dataRemoto,
        tamanho: tamanho,
        corKey: corKey,
      );
    }
    return false;
  }

  /// Remove tombstones obsoletos quando células/tamanhos voltam ao mapa ativo do produto.
  static Future<void> liberarTombstonesVariacoesAtivas({
    required String lojaId,
    required String estoqueDocId,
    required Map<String, dynamic> variacoesMap,
    required Map<String, int> estoquePorTamanho,
  }) async {
    final l = lojaId.trim();
    final id = estoqueDocId.trim();
    if (l.isEmpty || id.isEmpty) return;
    if (isProdutoBloqueadoSinc(l, id)) return;

    await _garantirPrefsUmaVez();
    await ensureHydratedForLoja(l);

    final chavesV = chavesCelulaDeVariacoes(variacoesMap);
    final chavesT = chavesSoloTamanhoDeEstoquePorTamanho(estoquePorTamanho);
    final bloq = _loja(l).varKeys[id];
    if (bloq == null || bloq.isEmpty) return;

    final toRemove = <String>{};
    for (final k in bloq) {
      if (chavesV.contains(k) || chavesT.contains(k)) {
        toRemove.add(k);
        continue;
      }
      if (k.startsWith(_pfxT)) {
        final tam = k.substring(_pfxT.length);
        for (final vk in chavesV) {
          if (vk.startsWith('$_pfxV$tam$_sep')) {
            toRemove.add(k);
            break;
          }
        }
      }
    }
    if (toRemove.isEmpty) return;

    bloq.removeAll(toRemove);
    if (bloq.isEmpty) {
      _loja(l).varKeys.remove(id);
    }

    try {
      final updates = <String, dynamic>{
        'at': FieldValue.serverTimestamp(),
      };
      for (final k in toRemove) {
        updates['v.$k'] = FieldValue.delete();
      }
      await _db
          .collection('lojas')
          .doc(l)
          .collection(FSPaths.exclusaoProdutoCol)
          .doc(id)
          .set(updates, SetOptions(merge: true));
      if (kDebugMode) {
        logD(
          '[TOMBSTONE] liberadas ${toRemove.length} chaves obsoletas: loja=$l doc=$id',
          tag: 'TOMBSTONE',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        logW(
          '⚠️ [TOMBSTONE] liberar obsoletas (type=${e.runtimeType})',
          tag: 'TOMBSTONE',
        );
      }
    }
    await _savePrefs();
  }

  static Future<bool> isVendaBloqueadaParaCelula({
    required String lojaId,
    required String estoqueDocId,
    String tamanho = '',
    String cor = '',
    String variacaoExtra = '',
  }) async {
    final l = lojaId.trim();
    final id = estoqueDocId.trim();
    if (await isProdutoBloqueadoRemoto(lojaId: l, estoqueDocId: id)) {
      return true;
    }
    await ensureHydratedForLoja(l);

    final t = tamanho.trim();
    final dataRemoto = await _lerDocEstoqueRemoto(l, id);
    Map<String, dynamic>? variacoesRemotas;
    if (dataRemoto != null) {
      final vr = dataRemoto['variacoes'];
      if (vr is Map) {
        variacoesRemotas = Map<String, dynamic>.from(vr);
      }
    }
    final corKey = normalizarCorParaChecagem(
      tamanho: t,
      cor: cor,
      variacoes: variacoesRemotas,
    );

    if (t.isNotEmpty) {
      final tk = tKeySoloTamanho(t);
      if (isVarChaveBloqueadaSinc(l, id, tk)) {
        if (!_tombstoneIgnoradoPorCelulaAtiva(
          chave: tk,
          dataRemoto: dataRemoto,
          tamanho: t,
          corKey: corKey,
        )) {
          return true;
        }
      }
    }
    if (t.isNotEmpty || corKey.isNotEmpty) {
      final vk = vKeyCelula(t, corKey);
      if (isVarChaveBloqueadaSinc(l, id, vk)) {
        if (!_tombstoneIgnoradoPorCelulaAtiva(
          chave: vk,
          dataRemoto: dataRemoto,
          tamanho: t,
          corKey: corKey,
        )) {
          return true;
        }
      }
    }
    return false;
  }
}
