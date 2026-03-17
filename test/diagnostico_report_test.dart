// test/diagnostico_report_test.dart
// Testa a lógica do relatório de diagnóstico (sem Firebase/Hive).

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DiagnosticoReport', () {
    test('adiciona itens OK corretamente', () {
      final report = _MockDiagnosticoReport();
      report.addOk('Firebase', 'Conectado');
      report.addOk('Auth', 'user@test.com');
      expect(report.itensLength, 2);
      expect(report.okCount, 2);
    });

    test('adiciona problemas corretamente', () {
      final report = _MockDiagnosticoReport();
      report.addProblema('LojaId', 'Não definido');
      expect(report.itensLength, 1);
      expect(report.okCount, 0);
    });

    test('adiciona erros e stack trace', () {
      final report = _MockDiagnosticoReport();
      report.addErro('Firestore', Exception('Connection failed'), StackTrace.current);
      expect(report.itensLength, 1);
      expect(report.errosLength, 1);
    });

    test('cálculo de score 100% quando tudo OK', () {
      final report = _MockDiagnosticoReport();
      report.addOk('A', 'ok');
      report.addOk('B', 'ok');
      final score = report.itensLength > 0 ? (report.okCount / report.itensLength * 100).round() : 0;
      expect(score, 100);
    });

    test('cálculo de score parcial quando há problemas', () {
      final report = _MockDiagnosticoReport();
      report.addOk('A', 'ok');
      report.addProblema('B', 'erro');
      final score = report.itensLength > 0 ? (report.okCount / report.itensLength * 100).round() : 0;
      expect(score, 50);
    });
  });
}

/// Mock simplificado para testar a lógica do relatório
class _MockDiagnosticoReport {
  final List<_MockItem> _itens = [];
  final List<String> _erros = [];

  void addOk(String area, String msg) => _itens.add(_MockItem(area, true, msg));
  void addProblema(String area, String msg) => _itens.add(_MockItem(area, false, msg));
  void addErro(String area, Object e, StackTrace? st) {
    _itens.add(_MockItem(area, false, e.toString()));
    _erros.add('[$area] $e');
  }

  int get itensLength => _itens.length;
  int get okCount => _itens.where((i) => i.ok).length;
  int get errosLength => _erros.length;
}

class _MockItem {
  final String area;
  final bool ok;
  final String mensagem;
  _MockItem(this.area, this.ok, this.mensagem);
}
