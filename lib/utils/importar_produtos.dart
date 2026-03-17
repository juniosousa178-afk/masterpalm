import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/produto.dart';
import '../services/produto_upsert_service.dart';

Future<Map<String, int>> importarProdutosDoExcel(
  Uint8List fileBytes,
  Box<Produto> produtosBox,
  String lojaId,
) async {
  final excel = Excel.decodeBytes(fileBytes);
  int adicionados = 0;
  int atualizados = 0;
  int ignorados = 0;

  for (var table in excel.tables.keys) {
    final sheet = excel.tables[table];
    if (sheet == null) continue;

    for (int i = 1; i < sheet.rows.length; i++) {
      try {
        final row = sheet.rows[i];

        final nome = row[0]?.value.toString().trim() ?? '';
        final precoUnitario = double.tryParse(
              row[1]?.value.toString().replaceAll(',', '.') ?? '',
            ) ??
            0.0;
        final quantidade = int.tryParse(
              row[2]?.value.toString().replaceAll(RegExp(r'[^\d]'), '') ?? '',
            ) ??
            0;
        final categoria =
            row.length > 3 ? row[3]?.value.toString().trim() ?? '' : '';

        // Valida dados essenciais
        if (nome.isEmpty || precoUnitario <= 0 || quantidade <= 0) {
          ignorados++;
          continue;
        }

        final sku = (row.length > 4 ? row[4]?.value.toString().trim() : null) ?? '';
        final codigoBarras = (row.length > 5 ? row[5]?.value.toString().trim() : null) ?? '';

        final novoProduto = Produto(
          nome: nome,
          custoReal: 0.0,
          frete: 0.0,
          gastosFixos: 0.0,
          gastosVariaveis: 0.0,
          precoSugerido: 0.0,
          precoFinal: precoUnitario,
          quantidade: quantidade,
          precoUnitario: precoUnitario,
          categoria: categoria,
          dataEntrada: DateTime.now(),
        );

        final (result, _) = await upsertProduto(
          produtosBox,
          lojaId,
          novoProduto,
          codigoBarras: codigoBarras.isNotEmpty ? codigoBarras : null,
          sku: sku.isNotEmpty ? sku : null,
        );

        if (result == UpsertResult.inserted) {
          adicionados++;
        } else if (result == UpsertResult.updated) {
          atualizados++;
        } else {
          ignorados++;
        }
      } catch (e) {
        debugPrint("Erro ao importar linha $i (type=${e.runtimeType})");
        ignorados++;
      }
    }
  }

  return {
    'adicionados': adicionados,
    'atualizados': atualizados,
    'ignorados': ignorados,
  };
}
