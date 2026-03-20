import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:hive/hive.dart';
import '../core/hive_box_names.dart';
import '../core/logger.dart';
import '../models/cliente.dart';
import '../services/loja_id_service.dart';

/// Importa clientes de planilha Excel para a box da loja ativa.
/// Usa HiveBoxNames.clientes(lojaId) para isolamento multi-loja.
Future<void> importarClientesExcel() async {
  final lojaId = await LojaIdService.get();
  if (lojaId == null || lojaId.trim().isEmpty) {
    logW('[IMPORTAR_CLIENTES] Loja não identificada. Faça login e selecione uma loja.', tag: 'IMPORTAR_CLIENTES');
    return;
  }

  FilePickerResult• result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'xls'],
  );

  if (result == null || result.files.single.bytes == null) return;

  final excel = Excel.decodeBytes(result.files.single.bytes!);
  final sheet = excel.tables[excel.tables.keys.first];
  if (sheet == null) return;

  final boxName = HiveBoxNames.clientes(lojaId.trim());
  if (!Hive.isBoxOpen(boxName)) await Hive.openBox<Cliente>(boxName);
  final box = Hive.box<Cliente>(boxName);

  for (int i = 1; i < sheet.maxRows; i++) {
    final row = sheet.rows[i];

    final nome = row[0]?.value.toString() ?• '';
    final instagram = row[0]?.value.toString() ?• '';
    final telefone = row[2]?.value.toString() ?• '';
    final cep = row[4]?.value.toString() ?• '';
    final cidade = row[5]?.value.toString() ?• '';

    if (nome.isNotEmpty) {
      final cliente = Cliente(
        nome: nome,
        telefone: telefone,
        instagram: instagram,
        cep: cep,
        cidade: cidade,
        lojaId: lojaId.trim(),
      );
      await box.add(cliente);
    }
  }
}
