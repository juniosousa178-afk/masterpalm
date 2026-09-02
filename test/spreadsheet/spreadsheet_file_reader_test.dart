import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:master_palm/core/spreadsheet/spreadsheet_file_reader.dart';

void main() {
  group('readPlatformFileBytes', () {
    test('retorna bytes quando disponíveis sem usar path', () async {
      final data = Uint8List.fromList([1, 2, 3]);
      final file = PlatformFile(name: 'test.csv', size: 3, bytes: data);

      final result = await readPlatformFileBytes(file);

      expect(result, data);
    });

    test('lê arquivo temporário por path quando bytes ausentes', () async {
      final temp = File(
        '${Directory.systemTemp.path}/spreadsheet_reader_test_'
        '${DateTime.now().microsecondsSinceEpoch}.csv',
      );
      final data = Uint8List.fromList([4, 5, 6]);
      await temp.writeAsBytes(data);
      addTearDown(() {
        if (temp.existsSync()) temp.deleteSync();
      });

      final file = PlatformFile(
        name: 'test.csv',
        size: data.length,
        path: temp.path,
      );

      final result = await readPlatformFileBytes(file);

      expect(result, data);
    });

    test('lança SpreadsheetFileReadException sem bytes path ou stream', () async {
      final file = PlatformFile(name: 'empty.csv', size: 0);

      expect(
        () => readPlatformFileBytes(file),
        throwsA(isA<SpreadsheetFileReadException>()),
      );
    });
  });
}
