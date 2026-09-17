// Rebase CAS de replace de produto: preserva proteção de revisão e
// quantidades remotas em células que o editor não alterou desde a baseline.

import 'package:cloud_functions/cloud_functions.dart';

import 'produto_form_grade_hydration.dart';
import 'produto_variacao_extra.dart';

/// Exceção explícita: edição concorrente insegura para overwrite silencioso.
class ProdutoCasConflictException implements Exception {
  ProdutoCasConflictException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Identidade/normalização alinhada a `normKey` do backend (catalogStockProjection.js).
class ProdutoVariationIdentity {
  ProdutoVariationIdentity._();

  static String normKey(Object? value) {
    return value
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+', unicode: true), ' ');
  }

  static String canonicalSize(String raw) {
    final t = raw.trim();
    return t.isEmpty ? 'sem-tamanho' : t;
  }

  static String canonicalColor(String raw) {
    final c = raw.trim();
    return c.isEmpty ? 'sem-cor' : c;
  }

  static String cellId(String tamanho, [String cor = 'sem-cor']) {
    return '${canonicalSize(tamanho)}|${canonicalColor(cor)}';
  }

  static bool keysMatch(Object? a, Object? b) => normKey(a) == normKey(b);
}

class ProdutoVariationCasRebase {
  ProdutoVariationCasRebase._();

  static const maxConflictRetries = 3;

  static bool isStockRevisionConflict(Object error) {
    if (error is FirebaseFunctionsException) {
      if (error.code == 'aborted') return true;
      final msg = (error.message ?? '').toLowerCase();
      return msg.contains('stock revision conflict') ||
          msg.contains('revision conflict');
    }
    final text = error.toString().toLowerCase();
    return text.contains('aborted') && text.contains('revision');
  }

  static int remoteRevision(Map<String, dynamic> remote) {
    final raw = remote['stockRevision'];
    if (raw is num) return raw.toInt();
    return 0;
  }

  /// Rebase da definition de replace sobre o estoque remoto autoritativo.
  ///
  /// - Células iguais à baseline: herdam quantidade remota (preserva venda).
  /// - Células editadas/novas no editor: mantêm valor do editor.
  /// - Célula editada no editor E alterada remotamente desde a baseline: conflito.
  /// - Chave remota nova (ausente na baseline e no editor): conflito.
  static Map<String, dynamic> rebaseReplaceDefinition({
    required Map<String, dynamic> editorDefinition,
    required ProdutoFormGradeBaseline? gradeBaseline,
    required Map<String, dynamic> remoteData,
  }) {
    final out = Map<String, dynamic>.from(editorDefinition);
    final editorVars = _asStringKeyedMap(editorDefinition['variacoes']);
    final remoteVars = _asStringKeyedMap(remoteData['variacoes']);
    final baselineVars = _asStringKeyedMap(gradeBaseline?.variacoes);

    if (editorVars != null) {
      out['variacoes'] = _rebaseVariacoesMap(
        editor: editorVars,
        baseline: baselineVars,
        remote: remoteVars ?? const {},
      );
    }

    // estoquePorTamanho: preferir agregado derivado após sanitize no caller;
    // se o editor enviou mapa, rebase por chave de tamanho.
    final editorTam = _asIntMap(editorDefinition['estoquePorTamanho']);
    final remoteTam = _asIntMap(remoteData['estoquePorTamanho']);
    final baselineTam = gradeBaseline == null
        ? null
        : Map<String, int>.from(gradeBaseline.estoquePorTamanho);
    if (editorTam != null) {
      out['estoquePorTamanho'] = _rebaseIntMap(
        editor: editorTam,
        baseline: baselineTam,
        remote: remoteTam ?? const {},
      );
    }

    if (editorDefinition.containsKey('quantidade')) {
      final hasGrade = editorVars != null && editorVars.isNotEmpty;
      if (!hasGrade) {
        final editorQ = ProdutoVariacaoExtra.valorFirestoreComoInt(
          editorDefinition['quantidade'],
        );
        final baselineQ = gradeBaseline?.quantidade;
        final remoteQ =
            ProdutoVariacaoExtra.valorFirestoreComoInt(remoteData['quantidade']);
        if (baselineQ != null &&
            editorQ == baselineQ &&
            remoteData.containsKey('quantidade')) {
          out['quantidade'] = remoteQ;
        } else if (baselineQ != null &&
            editorQ != baselineQ &&
            remoteQ != baselineQ &&
            editorQ != remoteQ) {
          throw ProdutoCasConflictException(
            'Conflito de estoque: quantidade alterada na nuvem e no editor.',
          );
        }
      }
    }

    return out;
  }

  static Map<String, dynamic> _rebaseVariacoesMap({
    required Map<String, dynamic> editor,
    required Map<String, dynamic>? baseline,
    required Map<String, dynamic> remote,
  }) {
    // Detect concurrent remote-only keys.
    for (final remSize in remote.keys) {
      final inBaseline = baseline != null &&
          baseline.keys.any((k) => ProdutoVariationIdentity.keysMatch(k, remSize));
      final inEditor =
          editor.keys.any((k) => ProdutoVariationIdentity.keysMatch(k, remSize));
      if (!inBaseline && !inEditor) {
        throw ProdutoCasConflictException(
          'Conflito de grade: variação remota nova não presente no editor.',
        );
      }
      final remCell = remote[remSize];
      if (remCell is! Map) continue;
      final baseSizeKey = baseline == null
          ? null
          : _findKey(baseline, remSize);
      final editSizeKey = _findKey(editor, remSize);
      final baseCell =
          baseSizeKey == null ? null : baseline![baseSizeKey];
      for (final remCor in remCell.keys) {
        final inBaseCor = baseCell is Map &&
            baseCell.keys
                .any((k) => ProdutoVariationIdentity.keysMatch(k, remCor));
        final editCell =
            editSizeKey == null ? null : editor[editSizeKey];
        final inEditCor = editCell is Map &&
            editCell.keys
                .any((k) => ProdutoVariationIdentity.keysMatch(k, remCor));
        if (!inBaseCor && !inEditCor) {
          throw ProdutoCasConflictException(
            'Conflito de grade: cor/variação remota nova não presente no editor.',
          );
        }
      }
    }

    final out = <String, dynamic>{};
    for (final sizeEntry in editor.entries) {
      final size = sizeEntry.key.toString();
      final editColors = sizeEntry.value;
      if (editColors is! Map) {
        out[size] = editColors;
        continue;
      }
      final baseColorsRaw =
          baseline == null ? null : _lookupMap(baseline, size);
      final remoteColorsRaw = _lookupMap(remote, size);
      final colorOut = <String, dynamic>{};
      for (final corEntry in editColors.entries) {
        final cor = corEntry.key.toString();
        final editVal = corEntry.value;
        final baseVal =
            baseColorsRaw == null ? null : _lookupValue(baseColorsRaw, cor);
        final remoteVal =
            remoteColorsRaw == null ? null : _lookupValue(remoteColorsRaw, cor);
        colorOut[cor] = _rebaseCellValue(
          editor: editVal,
          baseline: baseVal,
          remote: remoteVal,
        );
      }
      out[size] = colorOut;
    }
    return out;
  }

  static dynamic _rebaseCellValue({
    required dynamic editor,
    required dynamic baseline,
    required dynamic remote,
  }) {
    // Nested extra maps.
    if (editor is Map && (baseline is Map || remote is Map || baseline == null)) {
      final editMap = Map<String, dynamic>.from(
        editor.map((k, v) => MapEntry(k.toString(), v)),
      );
      final baseMap = baseline is Map
          ? Map<String, dynamic>.from(
              baseline.map((k, v) => MapEntry(k.toString(), v)),
            )
          : null;
      final remMap = remote is Map
          ? Map<String, dynamic>.from(
              remote.map((k, v) => MapEntry(k.toString(), v)),
            )
          : null;
      final out = <String, dynamic>{};
      for (final e in editMap.entries) {
        if (e.key == '__custoUnitario') {
          out[e.key] = e.value;
          continue;
        }
        final b = baseMap == null ? null : _lookupValue(baseMap, e.key);
        final r = remMap == null ? null : _lookupValue(remMap, e.key);
        out[e.key] = _rebaseScalarQty(editor: e.value, baseline: b, remote: r);
      }
      return out;
    }
    return _rebaseScalarQty(editor: editor, baseline: baseline, remote: remote);
  }

  static int _rebaseScalarQty({
    required dynamic editor,
    required dynamic baseline,
    required dynamic remote,
  }) {
    final e = ProdutoVariacaoExtra.valorFirestoreComoInt(editor);
    final b = baseline == null
        ? null
        : ProdutoVariacaoExtra.valorFirestoreComoInt(baseline);
    final r = remote == null
        ? null
        : ProdutoVariacaoExtra.valorFirestoreComoInt(remote);
    if (b != null && e == b && r != null) return r;
    if (b != null && e != b && r != null && r != b && e != r) {
      throw ProdutoCasConflictException(
        'Conflito de grade: a mesma variação foi alterada na nuvem e no editor.',
      );
    }
    return e;
  }

  static Map<String, int> _rebaseIntMap({
    required Map<String, int> editor,
    required Map<String, int>? baseline,
    required Map<String, int> remote,
  }) {
    for (final remKey in remote.keys) {
      final inBase = baseline != null &&
          baseline.keys
              .any((k) => ProdutoVariationIdentity.keysMatch(k, remKey));
      final inEdit = editor.keys
          .any((k) => ProdutoVariationIdentity.keysMatch(k, remKey));
      if (!inBase && !inEdit) {
        throw ProdutoCasConflictException(
          'Conflito de grade: tamanho remoto novo não presente no editor.',
        );
      }
    }
    final out = <String, int>{};
    for (final e in editor.entries) {
      final b = baseline == null
          ? null
          : _lookupInt(baseline, e.key);
      final r = _lookupInt(remote, e.key);
      if (b != null && e.value == b && r != null) {
        out[e.key] = r;
      } else if (b != null &&
          e.value != b &&
          r != null &&
          r != b &&
          e.value != r) {
        throw ProdutoCasConflictException(
          'Conflito de estoquePorTamanho: célula alterada na nuvem e no editor.',
        );
      } else {
        out[e.key] = e.value;
      }
    }
    return out;
  }

  static Map<String, dynamic>? _asStringKeyedMap(dynamic raw) {
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(
      raw.map((k, v) => MapEntry(k.toString(), v)),
    );
  }

  static Map<String, int>? _asIntMap(dynamic raw) {
    if (raw is! Map) return null;
    return raw.map(
      (k, v) => MapEntry(
        k.toString(),
        ProdutoVariacaoExtra.valorFirestoreComoInt(v),
      ),
    );
  }

  static String? _findKey(Map<String, dynamic> map, Object key) {
    for (final k in map.keys) {
      if (ProdutoVariationIdentity.keysMatch(k, key)) return k;
    }
    return null;
  }

  static Map<String, dynamic>? _lookupMap(
    Map<String, dynamic> map,
    Object key,
  ) {
    final k = _findKey(map, key);
    if (k == null) return null;
    final v = map[k];
    if (v is! Map) return null;
    return Map<String, dynamic>.from(
      v.map((a, b) => MapEntry(a.toString(), b)),
    );
  }

  static dynamic _lookupValue(Map<String, dynamic> map, Object key) {
    final k = _findKey(map, key);
    return k == null ? null : map[k];
  }

  static int? _lookupInt(Map<String, int> map, Object key) {
    for (final e in map.entries) {
      if (ProdutoVariationIdentity.keysMatch(e.key, key)) return e.value;
    }
    return null;
  }
}
