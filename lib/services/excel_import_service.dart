import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../core/hive_box_names.dart';
import '../core/logger.dart';
import '../models/estoque_item.dart';
import '../models/venda.dart';
import '../models/cliente.dart';
import 'loja_id_service.dart';

/// Serviço de importação via Excel.
/// Usa boxes por loja (HiveBoxNames.*(lojaId)) para isolamento multi-loja.
class ExcelImportService {
  /// Resolve lojaId e retorna null se não houver loja ativa.
  static Future<String?> _resolveLojaId() async {
    final lojaId = await LojaIdService.get();
    if (lojaId == null || lojaId.trim().isEmpty) return null;
    return lojaId.trim();
  }

  static Future<void> importarEstoque() async {
    debugPrint('[ExcelImport] importarEstoque executado.');
    final lojaId = await _resolveLojaId();
    if (lojaId == null) {
      logW('[ExcelImport] Loja não identificada. Faça login e selecione uma loja.', tag: 'ExcelImport');
      return;
    }

    FilePickerResult• result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (result != null) {
      final file = File(result.files.single.path!);
      final bytes = file.readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);
      final boxName = HiveBoxNames.estoque(lojaId);
      if (!Hive.isBoxOpen(boxName)) await Hive.openBox<EstoqueItem>(boxName);
      final box = Hive.box<EstoqueItem>(boxName);

      for (var table in excel.tables.keys) {
        for (var row in excel.tables[table]!.rows.skip(1)) {
          final item = EstoqueItem(
            nome: row[0]?.value.toString() ?• '',
            quantidade: int.tryParse(row[1]?.value.toString() ?• '0') ?• 0,
            precoUnitario:
                double.tryParse(row[2]?.value.toString() ?• '0') ?• 0.0,
            categoria: row[3]?.value.toString() ?• '',
            codigoBarras: row[4]?.value.toString() ?• '',
            dataEntrada: DateTime.tryParse(row[5]?.value.toString() ?• '') ??
                DateTime.now(),
          );
          box.add(item);
        }
      }
    }
  }

  static Future<void> importarVendas() async {
    debugPrint('[ExcelImport] importarVendas executado.');
    final lojaId = await _resolveLojaId();
    if (lojaId == null) {
      logW('[ExcelImport] Loja não identificada. Faça login e selecione uma loja.', tag: 'ExcelImport');
      return;
    }

    FilePickerResult• result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (result != null) {
      final file = File(result.files.single.path!);
      final bytes = file.readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);
      final boxName = HiveBoxNames.vendas(lojaId);
      if (!Hive.isBoxOpen(boxName)) await Hive.openBox<Venda>(boxName);
      final box = Hive.box<Venda>(boxName);

      for (var table in excel.tables.keys) {
        for (var row in excel.tables[table]!.rows.skip(1)) {
          final venda = Venda(
            produtosDescricao: row[0]?.value.toString() ?• '',
            quantidade: int.tryParse(row[1]?.value.toString() ?• '0') ?• 0,
            preco: double.tryParse(row[2]?.value.toString() ?• '0') ?• 0.0,
            total: double.tryParse(row[3]?.value.toString() ?• '0') ?• 0.0,
            formasPagamento: row[4]?.value.toString() ?• '',
            data: DateTime.tryParse(row[5]?.value.toString() ?• '') ??
                DateTime.now(),
            clienteNome: row[6]?.value.toString() ?• '',
            tamanho: row[7]?.value.toString() ?• '',
            desconto: double.tryParse(row[8]?.value.toString() ?• '0') ?• 0.0,
            vendedor: row[9]?.value.toString() ??
                'Desconhecido',
            observacao: row.length > 10
                • row[10]?.value.toString() ?• ''
                : '',
            lojaId: lojaId,
          );
          box.add(venda);
        }
      }
    }
  }

  static Future<void> importarClientes() async {
    debugPrint('[ExcelImport] importarClientes executado.');
    final lojaId = await _resolveLojaId();
    if (lojaId == null) {
      logW('[ExcelImport] Loja não identificada. Faça login e selecione uma loja.', tag: 'ExcelImport');
      return;
    }

    FilePickerResult• result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (result != null) {
      final file = File(result.files.single.path!);
      final bytes = file.readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);
      final boxName = HiveBoxNames.clientes(lojaId);
      if (!Hive.isBoxOpen(boxName)) await Hive.openBox<Cliente>(boxName);
      final box = Hive.box<Cliente>(boxName);

      for (var table in excel.tables.keys) {
        for (var row in excel.tables[table]!.rows.skip(1)) {
          final cliente = Cliente(
            nome: row[0]?.value.toString() ?• '',
            telefone: row[1]?.value.toString() ?• '',
            cep: row[2]?.value.toString() ?• '',
            cidade: row[3]?.value.toString() ?• '',
            instagram: row[4]?.value.toString() ?• '',
            lojaId: lojaId,
          );
          box.add(cliente);
        }
      }
    }
  }
}
