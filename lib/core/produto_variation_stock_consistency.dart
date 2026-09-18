// Consistency / authority for variation stock representations.
// Authority: nested `variacoes` cells. `estoquePorTamanho` is projection/legacy.
// NEVER resurrect variation qty from local-only positive estoquePorTamanho.

import '../models/produto.dart';
import 'produto_variacao_extra.dart';

/// Explicit stock representation state for editor / PDV.
enum ProdutoVariationStockConsistencyState {
  /// Representations agree (including legitimate all-zero).
  consistent,

  /// Remote/local snapshot has ept≠variacoes without unique safe mapping.
  remoteRepresentationDivergence,

  /// Local ept positive while variation cells are zero — may be stale local.
  localStaleEvidence,

  /// Needs operator / reconciliation; must not look like ordinary Qtd=0.
  recoveryRequired,

  /// Grade keys exist that are not represented as variation rows.
  incompleteGrade,

  /// Size-only stock map maps to multiple variation cells.
  ambiguousMapping,

  hydrating,
  offlinePartial,
}

class ProdutoVariationCellQty {
  const ProdutoVariationCellQty({
    required this.size,
    required this.color,
    required this.extra,
    required this.quantity,
  });

  final String size;
  final String color;
  final String extra;
  final int quantity;

  String get canonicalKey {
    if (extra.isEmpty) return '$size|$color';
    return '$size|$color|$extra';
  }
}

class ProdutoVariationStockConsistency {
  const ProdutoVariationStockConsistency({
    required this.state,
    required this.cells,
    required this.estoquePorTamanho,
    required this.variationQtySum,
    required this.estoquePorTamanhoSum,
    required this.ambiguousSizes,
    required this.incompleteStockKeys,
    required this.message,
    required this.blocksSilentZeroSave,
    required this.blocksPdvSale,
    required this.allowResurrectFromEstoquePorTamanho,
  });

  final ProdutoVariationStockConsistencyState state;
  final List<ProdutoVariationCellQty> cells;
  final Map<String, int> estoquePorTamanho;
  final int variationQtySum;
  final int estoquePorTamanhoSum;
  final List<String> ambiguousSizes;
  final List<String> incompleteStockKeys;
  final String message;
  final bool blocksSilentZeroSave;
  final bool blocksPdvSale;

  /// Always false under current authority (variacoes wins; never auto-fill from ept).
  final bool allowResurrectFromEstoquePorTamanho;

  bool get isOrdinaryTrustedZero =>
      state == ProdutoVariationStockConsistencyState.consistent &&
      variationQtySum == 0 &&
      estoquePorTamanhoSum == 0;

  bool get isUnresolved =>
      state == ProdutoVariationStockConsistencyState.remoteRepresentationDivergence ||
      state == ProdutoVariationStockConsistencyState.localStaleEvidence ||
      state == ProdutoVariationStockConsistencyState.recoveryRequired ||
      state == ProdutoVariationStockConsistencyState.incompleteGrade ||
      state == ProdutoVariationStockConsistencyState.ambiguousMapping ||
      state == ProdutoVariationStockConsistencyState.hydrating ||
      state == ProdutoVariationStockConsistencyState.offlinePartial;
}

class ProdutoVariationStockConsistencyEvaluator {
  ProdutoVariationStockConsistencyEvaluator._();

  static List<ProdutoVariationCellQty> extractCells(
    Map<String, dynamic>? variacoes,
  ) {
    final out = <ProdutoVariationCellQty>[];
    if (variacoes == null || variacoes.isEmpty) return out;
    for (final te in variacoes.entries) {
      final tamanho = te.key.toString();
      final cmap = te.value;
      if (cmap is! Map) continue;
      for (final ce in cmap.entries) {
        final cor = ce.key.toString();
        final raw = ce.value;
        if (raw is num) {
          out.add(
            ProdutoVariationCellQty(
              size: tamanho,
              color: cor,
              extra: '',
              quantity: raw.toInt(),
            ),
          );
          continue;
        }
        if (raw is Map) {
          var any = false;
          for (final ie in raw.entries) {
            final ek = ie.key.toString();
            if (ProdutoVariacaoExtra.isMetaKey(ek)) continue;
            any = true;
            final q = ie.value is num
                ? (ie.value as num).toInt()
                : int.tryParse(ie.value?.toString() ?? '') ?? 0;
            final extra =
                ProdutoVariacaoExtra.isSemExtraMapKey(ek) ? '' : ek;
            out.add(
              ProdutoVariationCellQty(
                size: tamanho,
                color: cor,
                extra: extra,
                quantity: q,
              ),
            );
          }
          if (!any) {
            out.add(
              ProdutoVariationCellQty(
                size: tamanho,
                color: cor,
                extra: '',
                quantity: 0,
              ),
            );
          }
        }
      }
    }
    return out;
  }

  /// Counts how many variation cells share a given size key.
  static Map<String, int> cellCountBySize(List<ProdutoVariationCellQty> cells) {
    final m = <String, int>{};
    for (final c in cells) {
      m[c.size] = (m[c.size] ?? 0) + 1;
    }
    return m;
  }

  /// Pure evaluation over local/Hive or remote snapshot fields.
  /// Does NOT read network. Does NOT mutate.
  ///
  /// [remoteAuthoritative] when true treats [estoquePorTamanho] divergence
  /// against zeroed variacoes as remote representation divergence
  /// (still never resurrects qty from ept — authority is variacoes).
  static ProdutoVariationStockConsistency evaluate({
    required Map<String, dynamic>? variacoes,
    required Map<String, int> estoquePorTamanho,
    bool remoteAuthoritative = false,
    bool hydrating = false,
    bool offlinePartial = false,
  }) {
    if (hydrating) {
      return const ProdutoVariationStockConsistency(
        state: ProdutoVariationStockConsistencyState.hydrating,
        cells: [],
        estoquePorTamanho: {},
        variationQtySum: 0,
        estoquePorTamanhoSum: 0,
        ambiguousSizes: [],
        incompleteStockKeys: [],
        message: 'Estoque em atualização',
        blocksSilentZeroSave: true,
        blocksPdvSale: true,
        allowResurrectFromEstoquePorTamanho: false,
      );
    }
    if (offlinePartial) {
      return const ProdutoVariationStockConsistency(
        state: ProdutoVariationStockConsistencyState.offlinePartial,
        cells: [],
        estoquePorTamanho: {},
        variationQtySum: 0,
        estoquePorTamanhoSum: 0,
        ambiguousSizes: [],
        incompleteStockKeys: [],
        message: 'Estoque inconsistente — sincronização necessária',
        blocksSilentZeroSave: true,
        blocksPdvSale: true,
        allowResurrectFromEstoquePorTamanho: false,
      );
    }

    final cells = extractCells(variacoes);
    final ept = Map<String, int>.from(estoquePorTamanho);
    final varSum = cells.fold<int>(0, (a, c) => a + c.quantity);
    final eptSum = ept.values.fold<int>(0, (a, b) => a + b);
    final bySize = cellCountBySize(cells);

    final ambiguous = <String>[];
    for (final e in ept.entries) {
      if (e.value <= 0) continue;
      final size = e.key.toString().split('|').first;
      final n = bySize[size] ?? 0;
      if (n > 1) ambiguous.add(size);
    }

    // Stock-map sizes not represented in any variation row.
    final cellSizes = cells.map((c) => c.size).toSet();
    final incomplete = <String>[];
    for (final k in ept.keys) {
      final size = k.toString().split('|').first;
      if (size.isEmpty) continue;
      if (!cellSizes.contains(size) && (ept[k] ?? 0) != 0) {
        incomplete.add(k.toString());
      }
    }
    // Also: ept has keys with any qty while variacoes empty but ept non-empty
    // and product claims variations via non-empty ept alone → incomplete if
    // we expected rows (caller may still use tamanhos). Keep incomplete list.

    if (ambiguous.isNotEmpty) {
      return ProdutoVariationStockConsistency(
        state: ProdutoVariationStockConsistencyState.ambiguousMapping,
        cells: cells,
        estoquePorTamanho: ept,
        variationQtySum: varSum,
        estoquePorTamanhoSum: eptSum,
        ambiguousSizes: ambiguous..sort(),
        incompleteStockKeys: incomplete..sort(),
        message: 'Estoque inconsistente — sincronização necessária',
        blocksSilentZeroSave: true,
        blocksPdvSale: true,
        allowResurrectFromEstoquePorTamanho: false,
      );
    }

    if (incomplete.isNotEmpty && cells.isNotEmpty) {
      return ProdutoVariationStockConsistency(
        state: ProdutoVariationStockConsistencyState.incompleteGrade,
        cells: cells,
        estoquePorTamanho: ept,
        variationQtySum: varSum,
        estoquePorTamanhoSum: eptSum,
        ambiguousSizes: const [],
        incompleteStockKeys: incomplete..sort(),
        message: 'Estoque inconsistente — sincronização necessária',
        blocksSilentZeroSave: true,
        blocksPdvSale: true,
        allowResurrectFromEstoquePorTamanho: false,
      );
    }

    final hasZeroVar = cells.any((c) => c.quantity == 0);
    final hasPosEpt = ept.values.any((v) => v > 0);
    final hasPosVar = cells.any((c) => c.quantity > 0);

    // Legitimate zero: both representations empty/zero.
    if (cells.isNotEmpty && varSum == 0 && eptSum == 0) {
      return ProdutoVariationStockConsistency(
        state: ProdutoVariationStockConsistencyState.consistent,
        cells: cells,
        estoquePorTamanho: ept,
        variationQtySum: 0,
        estoquePorTamanhoSum: 0,
        ambiguousSizes: const [],
        incompleteStockKeys: const [],
        message: '',
        blocksSilentZeroSave: false,
        blocksPdvSale: false,
        allowResurrectFromEstoquePorTamanho: false,
      );
    }

    // var positive and ept matches sum (or ept empty) → consistent
    if (hasPosVar && (ept.isEmpty || eptSum == varSum)) {
      return ProdutoVariationStockConsistency(
        state: ProdutoVariationStockConsistencyState.consistent,
        cells: cells,
        estoquePorTamanho: ept,
        variationQtySum: varSum,
        estoquePorTamanhoSum: eptSum,
        ambiguousSizes: const [],
        incompleteStockKeys: const [],
        message: '',
        blocksSilentZeroSave: false,
        blocksPdvSale: false,
        allowResurrectFromEstoquePorTamanho: false,
      );
    }

    // Core unsafe pattern: variation zeros with positive ept.
    if (hasZeroVar && hasPosEpt && !hasPosVar) {
      if (remoteAuthoritative) {
        // Authority is still variacoes (=0). ept positive is divergent projection.
        return ProdutoVariationStockConsistency(
          state:
              ProdutoVariationStockConsistencyState.remoteRepresentationDivergence,
          cells: cells,
          estoquePorTamanho: ept,
          variationQtySum: varSum,
          estoquePorTamanhoSum: eptSum,
          ambiguousSizes: const [],
          incompleteStockKeys: const [],
          message: 'Estoque inconsistente — sincronização necessária',
          blocksSilentZeroSave: true,
          blocksPdvSale: true,
          allowResurrectFromEstoquePorTamanho: false,
        );
      }
      return ProdutoVariationStockConsistency(
        state: ProdutoVariationStockConsistencyState.localStaleEvidence,
        cells: cells,
        estoquePorTamanho: ept,
        variationQtySum: varSum,
        estoquePorTamanhoSum: eptSum,
        ambiguousSizes: const [],
        incompleteStockKeys: const [],
        message: 'Estoque inconsistente — sincronização necessária',
        blocksSilentZeroSave: true,
        blocksPdvSale: true,
        allowResurrectFromEstoquePorTamanho: false,
      );
    }

    // Sum mismatch without the zero-var/pos-ept pattern.
    if (cells.isNotEmpty && ept.isNotEmpty && varSum != eptSum) {
      return ProdutoVariationStockConsistency(
        state: ProdutoVariationStockConsistencyState.recoveryRequired,
        cells: cells,
        estoquePorTamanho: ept,
        variationQtySum: varSum,
        estoquePorTamanhoSum: eptSum,
        ambiguousSizes: const [],
        incompleteStockKeys: const [],
        message: 'Estoque inconsistente — sincronização necessária',
        blocksSilentZeroSave: true,
        blocksPdvSale: true,
        allowResurrectFromEstoquePorTamanho: false,
      );
    }

    return ProdutoVariationStockConsistency(
      state: ProdutoVariationStockConsistencyState.consistent,
      cells: cells,
      estoquePorTamanho: ept,
      variationQtySum: varSum,
      estoquePorTamanhoSum: eptSum,
      ambiguousSizes: const [],
      incompleteStockKeys: const [],
      message: '',
      blocksSilentZeroSave: false,
      blocksPdvSale: false,
      allowResurrectFromEstoquePorTamanho: false,
    );
  }

  static ProdutoVariationStockConsistency evaluateProduto(
    Produto p, {
    bool remoteAuthoritative = false,
    bool hydrating = false,
    bool offlinePartial = false,
  }) {
    return evaluate(
      variacoes: p.variacoes == null
          ? null
          : Map<String, dynamic>.from(p.variacoes!),
      estoquePorTamanho: Map<String, int>.from(p.estoquePorTamanho),
      remoteAuthoritative: remoteAuthoritative,
      hydrating: hydrating,
      offlinePartial: offlinePartial,
    );
  }
}
