import 'dart:io';

import 'package:path/path.dart' as p;

import 'guardian_config.dart';
import 'models/impact_result.dart';

class TestSelector {
  TestSelector({required this.repoRoot, required this.config});

  final String repoRoot;
  final GuardianConfig config;

  TestSelection select(ImpactResult impact, List<String> changedPaths) {
    final required = <String>{};
    final recommended = <String>{};

    for (final domain in impact.domains) {
      final tests = config.domainTests[domain] ?? [];
      required.addAll(tests);
    }

    for (final service in impact.services) {
      for (final entry in _serviceTestMap.entries) {
        if (service.contains(entry.key)) {
          required.addAll(entry.value);
        }
      }
    }

    final found = <String>{};
    final testDir = Directory(p.join(repoRoot, 'test'));
    if (testDir.existsSync()) {
      for (final entity in testDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('_test.dart')) continue;
        final rel =
            p.relative(entity.path, from: repoRoot).replaceAll('\\', '/');
        final name = p.basename(rel);
        for (final req in required) {
          if (name.contains(
                  req.replaceAll('test/', '').replaceAll('.dart', '')) ||
              rel.contains(req)) {
            found.add(rel);
          }
        }
      }
    }

    // Also mark tests explicitly changed
    for (final path in changedPaths) {
      if (path.startsWith('test/')) found.add(path);
    }

    final missing = required.where((r) {
      final pattern = r.replaceAll('test/', '').replaceAll('.dart', '');
      return !found.any((f) => f.contains(pattern));
    }).toList()
      ..sort();

    final cmd = missing.isEmpty
        ? 'flutter test ${found.take(5).join(' ')}'
        : 'flutter test ${missing.take(3).map((m) => 'test/$m').join(' ')}';

    return TestSelection(
      required: required.toList()..sort(),
      found: found.toList()..sort(),
      missing: missing,
      recommended: recommended.toList(),
      suggestedCommand: cmd,
    );
  }

  static const _serviceTestMap = <String, List<String>>{
    'estoque_transaction_service': [
      'estoque_transaction_service_test.dart',
      'venda_estoque_operation_id_idempotencia_test.dart',
      'm39_hotfix_estoque_variacoes_multiplas_test.dart',
      'm39_consignado_variacoes_estoque_test.dart',
      'venda_exclusao_estorno_estoque_test.dart',
    ],
    'vendas_service': [
      'venda_fase4_durabilidade_recuperacao_test.dart',
      'venda_sale_intent_fiado_rollback_test.dart',
      'm39_hotfix_exclusao_venda_idempotencia_test.dart',
      'pdv_sale_intent_lifecycle_test.dart',
    ],
    'full_sync_service': [
      'm39_sprint4_r21_produto_estoque_test.dart',
    ],
    'loja_id_service': [
      'm38_sprint3_multiusuario_r1_test.dart',
      'm38_sprint3_multiusuario_r2_test.dart',
    ],
    'financeiro': [
      'financeiro_baixa_cr_duplicada_nao_altera_venda_estoque_test.dart',
      'contas_receber_excluir_recuperada_nao_altera_estoque_test.dart',
    ],
    'sync_queue': [
      'm39_sprint4_r21_produto_estoque_test.dart',
    ],
  };
}

class TestSelection {
  TestSelection({
    required this.required,
    required this.found,
    required this.missing,
    required this.recommended,
    required this.suggestedCommand,
  });

  final List<String> required;
  final List<String> found;
  final List<String> missing;
  final List<String> recommended;
  final String suggestedCommand;
}
