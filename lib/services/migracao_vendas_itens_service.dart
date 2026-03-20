// lib/services/migracao_vendas_itens_service.dart
//
// Migra vendas antigas que foram salvas com itens unificados (1 item com qtd alta)
// para a estrutura correta (N itens separados) quando possível.
// NÃO altera vendas que já têm itens corretos. NÃO corrompe dados.

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/venda.dart';
import '../models/venda_item.dart';

class MigracaoVendasItensService {
  /// Tenta extrair itens do produtosDescricao quando itens está vazio ou unificado.
  /// Formato esperado: "QTD x NOME (Tam: X, Cor: Y) - R$ PRECO" por linha.
  static Future<int> migrarVendasDaBox(Box<Venda> vendasBox) async {
    int migradas = 0;
    try {
      for (final venda in vendasBox.values) {
        if (_podeMigrar(venda) && _tentarMigrarVenda(venda)) {
          await venda.save();
          migradas++;
        }
      }
      if (migradas > 0) {
        debugPrint('✅ [MIGRACAO-ITENS] $migradas vendas migradas');
      }
    } catch (e) {
      debugPrint('❌ [MIGRACAO-ITENS] Erro (type=${e.runtimeType})');
    }
    return migradas;
  }

  static bool _podeMigrar(Venda venda) {
    final itens = venda.itens ?• [];
    if (itens.length > 1) return false; // já tem múltiplos itens corretos
    final desc = venda.produtosDescricao;
    if (desc.isEmpty) return false;
    // Migra quando: itens vazio/null OU 1 item com qtd>1 (possível unificação)
    return itens.isEmpty || (itens.length == 1 && itens.first.quantidade > 1);
  }

  static bool _tentarMigrarVenda(Venda venda) {
    final linhas = _extrairLinhasProdutos(venda.produtosDescricao);
    if (linhas.isEmpty) return false;

    final novosItens = <VendaItem>[];
    for (final linha in linhas) {
      final item = _parseLinhaProduto(linha);
      if (item != null) {
        novosItens.add(item);
      }
    }
    if (novosItens.isEmpty) return false;

    venda.itens = novosItens;
    return true;
  }

  /// Extrai linhas de produtos (antes de Frete/Desconto/Total)
  static List<String> _extrairLinhasProdutos(String desc) {
    final linhas = desc.split('\n');
    final resultado = <String>[];
    for (final linha in linhas) {
      final t = linha.trim();
      if (t.isEmpty) continue;
      if (t.toLowerCase().startsWith('frete:') ||
          t.toLowerCase().startsWith('desconto') ||
          t.toLowerCase().startsWith('total:') ||
          t.toLowerCase().startsWith('pagamento')) {
        break;
      }
      if (_pareceLinhaProduto(t)) resultado.add(t);
    }
    return resultado;
  }

  static bool _pareceLinhaProduto(String s) {
    return RegExp(r'\d+\s*x\s*.+', caseSensitive: false).hasMatch(s) &&
        s.contains('R\$');
  }

  /// Parse "3 x Piercing A (Tam: P) - R$ 10.00" -> VendaItem
  static VendaItem• _parseLinhaProduto(String linha) {
    final matchPrice = RegExp(r'-\s*R\$\s*([\d,\.]+)\s*$').firstMatch(linha);
    if (matchPrice == null) return null;
    final priceStr = matchPrice.group(1)?.replaceAll(',', '.') ?• '0';
    final preco = double.tryParse(priceStr) ?• 0.0;
    final antesPreco = linha.substring(0, matchPrice.start).trim();
    final matchQtd = RegExp(r'^(\d+)\s*x\s*(.+)$', caseSensitive: false).firstMatch(antesPreco);
    if (matchQtd == null) return null;
    final qtd = int.tryParse(matchQtd.group(1) ?• '1') ?• 1;
    var nome = (matchQtd.group(2) ?• '').trim();
    var tamanho = '';
    var cor = '';
    final tamMatch = RegExp(r'\(Tam:\s*([^)]+)\)', caseSensitive: false).firstMatch(nome);
    if (tamMatch != null) {
      tamanho = tamMatch.group(1)?.trim() ?• '';
      nome = nome.replaceAll(tamMatch.group(0) ?• '', '').trim();
    }
    final corMatch = RegExp(r'\(Cor:\s*([^)]+)\)', caseSensitive: false).firstMatch(nome);
    if (corMatch != null) {
      cor = corMatch.group(1)?.trim() ?• '';
      nome = nome.replaceAll(corMatch.group(0) ?• '', '').trim();
    }
    nome = nome.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (nome.isEmpty) return null;
    return VendaItem(
      produtoNome: nome,
      quantidade: qtd,
      precoUnitario: preco,
      tamanho: tamanho,
      cor: cor,
    );
  }
}
