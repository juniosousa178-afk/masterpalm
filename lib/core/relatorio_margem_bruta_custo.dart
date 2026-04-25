// lib/core/relatorio_margem_bruta_custo.dart
// Apenas para relatórios: resolve custo por linha com fallbacks, sem impactar
// venda, estoque ou cadastro.

import '../models/venda.dart';
import '../models/venda_item.dart';

/// Tenta extrair de um mapa (ex.: import Firestore) o custo total da linha,
/// quando ainda não houver [VendaItem.custoUnitario] no modelo.
double? _custoTotalLegadoDeMapaItem(Map<String, dynamic> m) {
  const chavesTotais = <String>[
    'custoTotalItem',
    'custoTotal',
    'custoProduto',
    'custoProdutos', // raro por linha
    'custoLinha',
    'custo',
  ];
  for (final k in chavesTotais) {
    if (!m.containsKey(k)) continue;
    final v = m[k];
    if (v is num) return v.toDouble();
  }
  return null;
}

/// Tenta [custo unitário] legado; se houver, retorna [unitário × quantidade].
double? _custoLinhaDeUnitarioLegadoDeMapaItem(
  Map<String, dynamic> m,
  int quantidade,
) {
  if (quantidade <= 0) return null;
  for (final k in const [
    'custoUnitarioItem',
    'custoUnitarioVenda',
    'custoUnit',
  ]) {
    if (!m.containsKey(k)) continue;
    final v = m[k];
    if (v is num) return v.toDouble() * quantidade;
  }
  return null;
}

/// Custo em R\$ por linha de [itens] para o relatório de margem bruta. Regras:
/// 1) [VendaItem.custoUnitario] (incluindo 0) × quantidade se não for null;
/// 2) Totais / custo unit. legado em [mapasItensRaw] (quando existir, ex.: import JSON);
/// 3) Ratear o restante de [Venda.custoProdutos] entre as linhas ainda sem custo;
/// 4) 0 para linhas restantes se não houver o que ratear.
///
/// [mapasItensRaw] alinhado por índice a [itens] (opcional).
List<double> custoRelatorioPorLinhasVenda(
  Venda venda,
  List<VendaItem> itens, {
  List<Map<String, dynamic>>? mapasItensRaw,
}) {
  if (itens.isEmpty) return const [];

  final n = itens.length;
  final raws = mapasItensRaw;
  final fixed = List<double?>.filled(n, null);
  var somaConhecida = 0.0;
  const eps = 1e-9;

  for (var i = 0; i < n; i++) {
    final it = itens[i];

    if (it.custoUnitario != null) {
      final linha = it.custoUnitario! * it.quantidade;
      fixed[i] = linha;
      somaConhecida += linha;
      continue;
    }

    if (raws != null && i < raws.length) {
      final m = raws[i];
      final t = _custoTotalLegadoDeMapaItem(m);
      if (t != null) {
        fixed[i] = t;
        somaConhecida += t;
        continue;
      }
      final u = _custoLinhaDeUnitarioLegadoDeMapaItem(m, it.quantidade);
      if (u != null) {
        fixed[i] = u;
        somaConhecida += u;
        continue;
      }
    }
  }

  final cTotal = venda.custoProdutos;
  var rem = cTotal - somaConhecida;
  if (rem < 0) rem = 0;

  final pendentes = <int>[];
  for (var i = 0; i < n; i++) {
    if (fixed[i] == null) pendentes.add(i);
  }

  final out = List<double>.filled(n, 0.0);
  for (var i = 0; i < n; i++) {
    if (fixed[i] != null) {
      out[i] = fixed[i]!;
    }
  }
  if (pendentes.isEmpty) return out;
  if (rem <= 0) {
    return out;
  }

  var somaReceita = 0.0;
  for (final j in pendentes) {
    final it = itens[j];
    somaReceita += it.precoUnitario * it.quantidade;
  }
  if (somaReceita > eps) {
    for (final j in pendentes) {
      final it = itens[j];
      out[j] = rem * (it.precoUnitario * it.quantidade) / somaReceita;
    }
  } else {
    var somaQ = 0;
    for (final j in pendentes) {
      somaQ += itens[j].quantidade;
    }
    if (somaQ > 0) {
      for (final j in pendentes) {
        out[j] = rem * (itens[j].quantidade / somaQ);
      }
    } else {
      final fat = 1.0 / pendentes.length;
      for (final j in pendentes) {
        out[j] = rem * fat;
      }
    }
  }

  return out;
}
