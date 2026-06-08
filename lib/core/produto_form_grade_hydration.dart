// Hidratação da grade do cadastro a partir de variacoes / estoquePorTamanho / tamanhos.
// Somente UI — não persiste no Firestore até o usuário salvar.

import '../models/produto.dart';
import '../utils/moeda_input_formatter.dart';
import 'produto_variacao_extra.dart';

/// Origem das linhas exibidas na grade do formulário.
enum ProdutoFormGradeHydrationSource {
  nenhuma,
  variacoes,
  estoquePorTamanho,
  tamanhosSomente,
}

/// Linha da grade (campos string para controllers / UI).
typedef ProdutoFormGradeRow = Map<String, String>;

class ProdutoFormGradeHydration {
  const ProdutoFormGradeHydration({
    required this.rows,
    required this.source,
  });

  final List<ProdutoFormGradeRow> rows;
  final ProdutoFormGradeHydrationSource source;
}

String produtoFormDisplayTamanhoGrade(String tamanho) {
  return tamanho == 'sem-tamanho' ? '' : tamanho;
}

String produtoFormDisplayCorGrade(String cor) {
  return cor == 'sem-cor' ? '' : cor;
}

ProdutoFormGradeRow produtoFormEmptyGradeRow() => {
      'tamanho': '',
      'cor': '',
      'extraTipo': '',
      'extraValor': '',
      'qtd': '',
      'custo': '',
    };

String _extraTipoParaCelula(
  Map<String, dynamic>? variacoesExtraTipo,
  String tamanho,
  String cor,
  String extraValor,
) {
  if (variacoesExtraTipo == null || extraValor.isEmpty) return '';
  final tm = variacoesExtraTipo[tamanho];
  if (tm is! Map) return '';
  final cm = tm[cor];
  if (cm is! Map) return '';
  for (final e in cm.entries) {
    if (ProdutoVariacaoExtra.keysMatch(e.key.toString(), extraValor)) {
      return e.value?.toString() ?? '';
    }
  }
  return '';
}

/// Monta linhas a partir de [variacoes] persistidas (mesma regra do formulário).
List<ProdutoFormGradeRow> produtoFormBuildGradeRowsFromVariacoes(
  Map<String, dynamic> variacoes, {
  Map<String, dynamic>? variacoesExtraTipo,
}) {
  final rows = <ProdutoFormGradeRow>[];
  final vet = variacoesExtraTipo;
  for (final tamanhoEntry in variacoes.entries) {
    final tamanho = tamanhoEntry.key.toString();
    final mapaCores = tamanhoEntry.value;
    if (mapaCores is! Map) continue;
    for (final corEntry in mapaCores.entries) {
      final cor = corEntry.key.toString();
      final raw = corEntry.value;
      if (raw is num) {
        rows.add({
          'tamanho': produtoFormDisplayTamanhoGrade(tamanho),
          'cor': produtoFormDisplayCorGrade(cor),
          'extraTipo': '',
          'extraValor': '',
          'qtd': raw.toInt().toString(),
          'custo': '',
        });
        continue;
      }
      if (raw is Map) {
        final custoCelula = ProdutoVariacaoExtra.custoUnitarioNaCelula(raw);
        final custoTexto = (custoCelula != null && custoCelula > 0)
            ? MoedaInputFormatter.format(custoCelula)
            : '';
        for (final ie in raw.entries) {
          if (ProdutoVariacaoExtra.isMetaKey(ie.key.toString())) continue;
          final ev = ie.key.toString();
          final q = ie.value is num
              ? (ie.value as num).toInt()
              : int.tryParse(ie.value?.toString() ?? '') ?? 0;
          final evDisp =
              ProdutoVariacaoExtra.isSemExtraMapKey(ev) ? '' : ev;
          rows.add({
            'tamanho': produtoFormDisplayTamanhoGrade(tamanho),
            'cor': produtoFormDisplayCorGrade(cor),
            'extraTipo': _extraTipoParaCelula(vet, tamanho, cor, evDisp),
            'extraValor': evDisp,
            'qtd': q.toString(),
            'custo': custoTexto,
          });
        }
      }
    }
  }
  return rows;
}

/// Interpreta chave de estoque: `19`, `19|Prata`, `19|Prata|Letra|A`.
({String tamanho, String cor, String extraTipo, String extraValor})
    produtoFormParseEstoquePorTamanhoKey(String key) {
  final trimmed = key.trim();
  if (trimmed.isEmpty) {
    return (tamanho: '', cor: '', extraTipo: '', extraValor: '');
  }
  final parts = trimmed.split('|').map((s) => s.trim()).toList();
  if (parts.length >= 4) {
    return (
      tamanho: parts[0],
      cor: parts[1],
      extraTipo: parts[2],
      extraValor: parts[3],
    );
  }
  if (parts.length == 3) {
    return (
      tamanho: parts[0],
      cor: parts[1],
      extraTipo: '',
      extraValor: parts[2],
    );
  }
  if (parts.length == 2) {
    return (
      tamanho: parts[0],
      cor: parts[1],
      extraTipo: '',
      extraValor: '',
    );
  }
  return (tamanho: trimmed, cor: '', extraTipo: '', extraValor: '');
}

List<ProdutoFormGradeRow> produtoFormBuildGradeRowsFromEstoquePorTamanho(
  Map<String, int> estoquePorTamanho,
) {
  final rows = <ProdutoFormGradeRow>[];
  final keys = estoquePorTamanho.keys.toList()
    ..sort((a, b) => a.toString().compareTo(b.toString()));
  for (final key in keys) {
    final qtd = ProdutoVariacaoExtra.valorFirestoreComoInt(estoquePorTamanho[key]);
    if (qtd <= 0) continue;
    final parsed = produtoFormParseEstoquePorTamanhoKey(key.toString());
    rows.add({
      'tamanho': produtoFormDisplayTamanhoGrade(parsed.tamanho),
      'cor': produtoFormDisplayCorGrade(parsed.cor),
      'extraTipo': parsed.extraTipo,
      'extraValor': parsed.extraValor,
      'qtd': qtd.toString(),
      'custo': '',
    });
  }
  return rows;
}

List<ProdutoFormGradeRow> produtoFormBuildGradeRowsFromTamanhosSomente(
  List<String> tamanhos,
) {
  final rows = <ProdutoFormGradeRow>[];
  for (final t in tamanhos) {
    final tt = t.trim();
    if (tt.isEmpty) continue;
    rows.add({
      'tamanho': produtoFormDisplayTamanhoGrade(tt),
      'cor': '',
      'extraTipo': '',
      'extraValor': '',
      'qtd': '',
      'custo': '',
    });
  }
  return rows;
}

bool _tamanhoAutorizadoParaSuplementoGrade({
  required String tamanho,
  required List<String> tamanhosProduto,
  required Map<String, dynamic>? variacoesExtraTipo,
}) {
  if (tamanho.isEmpty) return false;
  if (tamanhosProduto.contains(tamanho)) return true;
  if (variacoesExtraTipo != null && variacoesExtraTipo.containsKey(tamanho)) {
    return true;
  }
  return false;
}

List<ProdutoFormGradeRow> _suplementarLinhasDeEstoqueAusentes(
  List<ProdutoFormGradeRow> rows,
  Map<String, int> estoquePorTamanho, {
  required List<String> tamanhosProduto,
  Map<String, dynamic>? variacoesExtraTipo,
}) {
  if (estoquePorTamanho.isEmpty) return rows;
  final tamanhosNasLinhas = rows
      .map((r) => (r['tamanho'] ?? '').trim())
      .where((t) => t.isNotEmpty)
      .toSet();
  final out = List<ProdutoFormGradeRow>.from(rows);
  for (final row in produtoFormBuildGradeRowsFromEstoquePorTamanho(
    estoquePorTamanho,
  )) {
    final t = (row['tamanho'] ?? '').trim();
    if (t.isEmpty || tamanhosNasLinhas.contains(t)) continue;
    if (!_tamanhoAutorizadoParaSuplementoGrade(
      tamanho: t,
      tamanhosProduto: tamanhosProduto,
      variacoesExtraTipo: variacoesExtraTipo,
    )) {
      continue;
    }
    out.add(row);
    tamanhosNasLinhas.add(t);
  }
  return out;
}

/// Prioridade: variacoes → estoquePorTamanho → tamanhos (sem inventar quantidade).
ProdutoFormGradeHydration produtoFormHydrateGradeRows(Produto p) {
  if (p.variacoes != null && p.variacoes!.isNotEmpty) {
    var rows = produtoFormBuildGradeRowsFromVariacoes(
      Map<String, dynamic>.from(p.variacoes!),
      variacoesExtraTipo: p.variacoesExtraTipo == null
          ? null
          : Map<String, dynamic>.from(p.variacoesExtraTipo!),
    );
    if (p.estoquePorTamanho.isNotEmpty &&
        (p.tamanhos.isNotEmpty || p.variacoesExtraTipo != null)) {
      rows = _suplementarLinhasDeEstoqueAusentes(
        rows,
        p.estoquePorTamanho,
        tamanhosProduto: p.tamanhos,
        variacoesExtraTipo: p.variacoesExtraTipo == null
            ? null
            : Map<String, dynamic>.from(p.variacoesExtraTipo!),
      );
    }
    return ProdutoFormGradeHydration(
      rows: rows.isEmpty ? [produtoFormEmptyGradeRow()] : rows,
      source: ProdutoFormGradeHydrationSource.variacoes,
    );
  }

  if (p.estoquePorTamanho.isNotEmpty) {
    final rows = produtoFormBuildGradeRowsFromEstoquePorTamanho(p.estoquePorTamanho);
    if (rows.isNotEmpty) {
      return ProdutoFormGradeHydration(
        rows: rows,
        source: ProdutoFormGradeHydrationSource.estoquePorTamanho,
      );
    }
  }

  if (p.tamanhos.isNotEmpty) {
    final rows = produtoFormBuildGradeRowsFromTamanhosSomente(p.tamanhos);
    if (rows.isNotEmpty) {
      return ProdutoFormGradeHydration(
        rows: rows,
        source: ProdutoFormGradeHydrationSource.tamanhosSomente,
      );
    }
  }

  return const ProdutoFormGradeHydration(
    rows: [],
    source: ProdutoFormGradeHydrationSource.nenhuma,
  );
}

/// Mesma regra da lista de estoque: produto “tem variação” na UI.
bool produtoListaIndicaVariacao(Produto p) {
  return p.usaVariacoes || p.estoquePorTamanho.isNotEmpty || p.tamanhos.isNotEmpty;
}

/// Snapshot da grade ao abrir o formulário (antes de edições na sessão).
class ProdutoFormGradeBaseline {
  const ProdutoFormGradeBaseline({
    this.variacoes,
    this.variacoesExtraTipo,
    this.estoquePorTamanho = const {},
    this.tamanhos = const [],
    this.hydrationSource = ProdutoFormGradeHydrationSource.nenhuma,
  });

  final Map<String, dynamic>? variacoes;
  final Map<String, dynamic>? variacoesExtraTipo;
  final Map<String, int> estoquePorTamanho;
  final List<String> tamanhos;
  final ProdutoFormGradeHydrationSource hydrationSource;

  static ProdutoFormGradeBaseline capture(Produto p) {
    final hydration = produtoFormHydrateGradeRows(p);
    return ProdutoFormGradeBaseline(
      variacoes: p.variacoes != null && p.variacoes!.isNotEmpty
          ? Map<String, dynamic>.from(p.variacoes!)
          : null,
      variacoesExtraTipo:
          p.variacoesExtraTipo != null && p.variacoesExtraTipo!.isNotEmpty
              ? Map<String, dynamic>.from(p.variacoesExtraTipo!)
              : null,
      estoquePorTamanho: Map<String, int>.from(p.estoquePorTamanho),
      tamanhos: List<String>.from(p.tamanhos),
      hydrationSource: hydration.source,
    );
  }
}

bool produtoFormBaselineHadGrade(ProdutoFormGradeBaseline baseline) {
  if (baseline.variacoes != null && baseline.variacoes!.isNotEmpty) {
    return true;
  }
  if (baseline.variacoesExtraTipo != null &&
      baseline.variacoesExtraTipo!.isNotEmpty) {
    return true;
  }
  if (baseline.estoquePorTamanho.isNotEmpty) return true;
  if (baseline.tamanhos.isNotEmpty) return true;
  return baseline.hydrationSource != ProdutoFormGradeHydrationSource.nenhuma;
}

/// Agrega linhas string da grade (mesma regra de [produtoFormMergeVariacoesGrade]).
({Map<String, dynamic> variacoes, Map<String, dynamic>? variacoesExtraTipo})
    produtoFormMergeVariacoesGradeRows(List<Map<String, String>> rows) {
  final acc = <String, Map<String, Map<String, dynamic>>>{};
  final tiposAcc = <String, Map<String, Map<String, String>>>{};

  for (final r in rows) {
    final tamanho = (r['tamanho'] ?? '').trim();
    final cor = (r['cor'] ?? '').trim();
    final extraTipo = (r['extraTipo'] ?? '').trim();
    final extraValor = (r['extraValor'] ?? '').trim();
    final custoStr = (r['custo'] ?? '').trim();
    final qStr = (r['qtd'] ?? '').trim();
    if (qStr.isEmpty || (tamanho.isEmpty && cor.isEmpty)) continue;
    final qtd = int.tryParse(qStr) ?? 0;
    if (qtd <= 0) continue;
    final chaveTamanho = tamanho.isEmpty ? 'sem-tamanho' : tamanho;
    final corFinal = cor.isEmpty ? 'sem-cor' : cor;
    final ek =
        extraValor.isEmpty ? ProdutoVariacaoExtra.kSemExtraKey : extraValor;

    acc.putIfAbsent(chaveTamanho, () => {});
    acc[chaveTamanho]!.putIfAbsent(corFinal, () => {});
    acc[chaveTamanho]![corFinal]![ek] = qtd;
    final custoUnitario = MoedaInputFormatter.parse(custoStr);
    if (custoUnitario > 0) {
      acc[chaveTamanho]![corFinal]![
              ProdutoVariacaoExtra.kMetaCustoUnitarioKey] =
          custoUnitario;
    }

    if (ek.isNotEmpty) {
      tiposAcc.putIfAbsent(chaveTamanho, () => {});
      tiposAcc[chaveTamanho]!.putIfAbsent(corFinal, () => {});
      final label =
          extraTipo.isEmpty ? kVariacaoExtraTipoFallback : extraTipo;
      tiposAcc[chaveTamanho]![corFinal]![ek] = label;
    }
  }

  final variacoesMap = <String, dynamic>{};
  for (final te in acc.entries) {
    final innerOut = <String, dynamic>{};
    for (final ce in te.value.entries) {
      final m = ce.value;
      if (m.isEmpty) continue;
      final hasMetaCusto =
          m.containsKey(ProdutoVariacaoExtra.kMetaCustoUnitarioKey);
      if (!hasMetaCusto &&
          m.length == 1 &&
          (m.containsKey(ProdutoVariacaoExtra.kSemExtraKey) ||
              m.containsKey(ProdutoVariacaoExtra.kSemExtraKeyLegacy) ||
              m.containsKey(''))) {
        innerOut[ce.key] = m[ProdutoVariacaoExtra.kSemExtraKey] ??
            m[ProdutoVariacaoExtra.kSemExtraKeyLegacy] ??
            m[''] ??
            0;
      } else {
        innerOut[ce.key] = Map<String, dynamic>.from(m);
      }
    }
    if (innerOut.isNotEmpty) variacoesMap[te.key] = innerOut;
  }

  Map<String, dynamic>? tiposOut;
  for (final te in tiposAcc.entries) {
    final inner = <String, dynamic>{};
    for (final ce in te.value.entries) {
      if (ce.value.isNotEmpty) {
        inner[ce.key] = Map<String, dynamic>.from(ce.value);
      }
    }
    if (inner.isNotEmpty) {
      tiposOut ??= {};
      tiposOut[te.key] = inner;
    }
  }

  return (variacoes: variacoesMap, variacoesExtraTipo: tiposOut);
}

Map<String, int> produtoFormEstoquePorTamanhoFromVariacoes(
  Map<String, dynamic> variacoes,
) {
  final out = <String, int>{};
  for (final t in variacoes.keys) {
    if (t == 'sem-tamanho') continue;
    final m = variacoes[t];
    if (m is! Map) continue;
    var sum = 0;
    for (final v in m.values) {
      sum += ProdutoVariacaoExtra.somarCelula(v);
    }
    if (sum > 0) out[t.toString()] = sum;
  }
  return out;
}

List<String> produtoFormTamanhosFromVariacoes(Map<String, dynamic> variacoes) {
  return variacoes.keys.map((k) => k.toString()).where((k) => k != 'sem-tamanho').toList();
}

Map<String, dynamic> produtoFormVariacoesFromEstoquePorTamanho(
  Map<String, int> estoquePorTamanho,
) {
  final rows = produtoFormBuildGradeRowsFromEstoquePorTamanho(estoquePorTamanho);
  return produtoFormMergeVariacoesGradeRows(rows).variacoes;
}

/// Remoção parcial (algumas chaves, não wipe total) — tombstone explícito.
/// Com UI vazia, diff de tombstone não conta como intenção (evita wipe acidental).
bool produtoFormIsExplicitPartialGradeRemoval({
  required Set<String> baselineVarKeys,
  required Set<String> baselineTamKeys,
  required Set<String> removedVarKeys,
  required Set<String> removedTamKeys,
  required bool uiGradeEmpty,
}) {
  if (uiGradeEmpty) return false;
  final totalBaseline = baselineVarKeys.length + baselineTamKeys.length;
  final totalRemoved = removedVarKeys.length + removedTamKeys.length;
  if (totalRemoved == 0 || totalBaseline == 0) return false;
  if (totalRemoved >= totalBaseline) return false;
  return true;
}

/// Payload final de grade para save/sync.
class ProdutoFormGradeSavePayload {
  const ProdutoFormGradeSavePayload({
    required this.variacoes,
    this.variacoesExtraTipo,
    required this.estoquePorTamanho,
    required this.tamanhos,
    this.preservedFromBaseline = false,
    this.abortMessage,
  });

  final Map<String, dynamic> variacoes;
  final Map<String, dynamic>? variacoesExtraTipo;
  final Map<String, int> estoquePorTamanho;
  final List<String> tamanhos;
  final bool preservedFromBaseline;
  final String? abortMessage;

  bool get shouldAbort => abortMessage != null && abortMessage!.isNotEmpty;
}

ProdutoFormGradeSavePayload produtoFormBaselineGradePayload(
  ProdutoFormGradeBaseline baseline,
) {
  Map<String, dynamic> variacoes = {};
  Map<String, dynamic>? extra = baseline.variacoesExtraTipo != null
      ? Map<String, dynamic>.from(baseline.variacoesExtraTipo!)
      : null;
  Map<String, int> estoque = Map<String, int>.from(baseline.estoquePorTamanho);
  List<String> tamanhos = List<String>.from(baseline.tamanhos);

  if (baseline.variacoes != null && baseline.variacoes!.isNotEmpty) {
    variacoes = Map<String, dynamic>.from(baseline.variacoes!);
    estoque = produtoFormEstoquePorTamanhoFromVariacoes(variacoes);
    if (tamanhos.isEmpty) {
      tamanhos = produtoFormTamanhosFromVariacoes(variacoes);
    }
  } else if (estoque.isNotEmpty) {
    variacoes = produtoFormVariacoesFromEstoquePorTamanho(estoque);
    final merged = produtoFormMergeVariacoesGradeRows(
      produtoFormBuildGradeRowsFromEstoquePorTamanho(estoque),
    );
    if (extra == null && merged.variacoesExtraTipo != null) {
      extra = Map<String, dynamic>.from(merged.variacoesExtraTipo!);
    }
    if (tamanhos.isEmpty) {
      tamanhos = produtoFormTamanhosFromVariacoes(variacoes);
    }
  }

  return ProdutoFormGradeSavePayload(
    variacoes: variacoes,
    variacoesExtraTipo: extra,
    estoquePorTamanho: estoque,
    tamanhos: tamanhos,
    preservedFromBaseline: true,
  );
}

/// Impede save acidental com grade vazia quando o produto tinha grade ao abrir.
ProdutoFormGradeSavePayload produtoFormResolveGradeForSave({
  ProdutoFormGradeBaseline? baseline,
  required Map<String, dynamic> uiVariacoes,
  required Map<String, dynamic>? uiVariacoesExtraTipo,
  required Map<String, int> uiEstoquePorTamanho,
  required List<String> uiTamanhos,
  required Set<String> removedVarKeys,
  required Set<String> removedTamKeys,
  required Set<String> baselineVarKeys,
  required Set<String> baselineTamKeys,
}) {
  final uiEmpty =
      uiVariacoes.isEmpty && uiEstoquePorTamanho.isEmpty;

  if (baseline == null || !produtoFormBaselineHadGrade(baseline)) {
    return ProdutoFormGradeSavePayload(
      variacoes: uiVariacoes,
      variacoesExtraTipo: uiVariacoesExtraTipo,
      estoquePorTamanho: uiEstoquePorTamanho,
      tamanhos: uiTamanhos,
    );
  }

  if (!uiEmpty) {
    return ProdutoFormGradeSavePayload(
      variacoes: uiVariacoes,
      variacoesExtraTipo: uiVariacoesExtraTipo,
      estoquePorTamanho: uiEstoquePorTamanho,
      tamanhos: uiTamanhos,
    );
  }

  final partialRemoval = produtoFormIsExplicitPartialGradeRemoval(
    baselineVarKeys: baselineVarKeys,
    baselineTamKeys: baselineTamKeys,
    removedVarKeys: removedVarKeys,
    removedTamKeys: removedTamKeys,
    uiGradeEmpty: uiEmpty,
  );

  if (partialRemoval) {
    return ProdutoFormGradeSavePayload(
      variacoes: uiVariacoes,
      variacoesExtraTipo: uiVariacoesExtraTipo,
      estoquePorTamanho: uiEstoquePorTamanho,
      tamanhos: uiTamanhos,
    );
  }

  // UI vazia sem remoção parcial explícita: preservar baseline (evita wipe acidental).
  return produtoFormBaselineGradePayload(baseline);
}
