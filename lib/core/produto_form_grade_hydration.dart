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

/// Prioridade: variacoes → estoquePorTamanho → tamanhos (sem inventar quantidade).
ProdutoFormGradeHydration produtoFormHydrateGradeRows(Produto p) {
  if (p.variacoes != null && p.variacoes!.isNotEmpty) {
    final rows = produtoFormBuildGradeRowsFromVariacoes(
      Map<String, dynamic>.from(p.variacoes!),
      variacoesExtraTipo: p.variacoesExtraTipo == null
          ? null
          : Map<String, dynamic>.from(p.variacoesExtraTipo!),
    );
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
