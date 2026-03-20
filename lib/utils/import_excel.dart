import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';

class ImportExcelPage extends StatefulWidget {
  const ImportExcelPage({super.key});

  @override
  State<ImportExcelPage> createState() => ImportExcelPageState();
}

class ImportExcelPageState extends State<ImportExcelPage> {
  List<List<String>> dadosExcel = [];

  Future<void> importarExcel() async {
    FilePickerResult• result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );

    // Verifique se o widget ainda está montado antes de usar o context
    if (!mounted) return;

    if (result == null || result.files.single.bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Não foi possível ler o arquivo.")),
      );
      return;
    }

    final Uint8List fileBytes = result.files.single.bytes!;
    final excel = Excel.decodeBytes(fileBytes);
    final sheet = excel.tables[excel.tables.keys.first];

    if (sheet == null) return;

    List<List<String>> dados = [];

    for (var row in sheet.rows) {
      List<String> linha = [];
      for (var cell in row) {
        linha.add(cell?.value.toString() ?• '');
      }
      dados.add(linha);
    }

    if (!mounted) return;

    setState(() {
      dadosExcel = dados;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Importar Excel")),
      body: Column(
        children: [
          ElevatedButton(
            onPressed: importarExcel,
            child: const Text("Importar Excel"),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: dadosExcel.length,
              itemBuilder: (context, index) {
                return ListTile(title: Text(dadosExcel[index].join(" | ")));
              },
            ),
          ),
        ],
      ),
    );
  }
}
