import 'diff_analyzer.dart';
import 'guardian_config.dart';
import 'models/risk_result.dart';

class RiskClassifier {
  RiskClassifier({required this.config});

  final GuardianConfig config;

  RiskResult classify(DiffAnalysis diff, List<String> domains) {
    final items = <RiskItem>[];

    for (final change in diff.changes) {
      final path = change.path.replaceAll('\\', '/');

      if (path.startsWith('docs/') &&
          !path.contains('lib/') &&
          change.status != ChangeStatus.removed) {
        items.add(RiskItem(
          file: path,
          level: RiskLevel.green,
          reason: 'Alteração apenas documental',
        ));
        continue;
      }

      final critical =
          config.criticalFiles.where((c) => path.contains(c.path)).toList();
      if (critical.isNotEmpty) {
        final cf = critical.first;
        items.add(RiskItem(
          file: path,
          level: cf.lines > 3000 ? RiskLevel.red : RiskLevel.yellow,
          reason: 'Arquivo crítico AST (${cf.lines} linhas)',
        ));
      }

      if (path.contains('estoque_transaction_service') ||
          path.contains('vendas_service') ||
          domains.contains('Estoque') ||
          domains.contains('PDV')) {
        items.add(RiskItem(
          file: path,
          level: RiskLevel.red,
          reason: 'Domínio estoque/PDV',
        ));
      }

      if (domains.contains('Financeiro') || domains.contains('Fiado')) {
        items.add(RiskItem(
          file: path,
          level: RiskLevel.red,
          reason: 'Domínio financeiro/fiado',
        ));
      }

      if (domains.contains('Sync') || domains.contains('Offline')) {
        items.add(RiskItem(
          file: path,
          level: RiskLevel.red,
          reason: 'Domínio sync/offline',
        ));
      }

      if (domains.contains('Tenant') || path.contains('loja_id')) {
        items.add(RiskItem(
          file: path,
          level: RiskLevel.red,
          reason: 'Domínio tenant/lojaId',
        ));
      }

      if (diff.securityRulesTouched) {
        items.add(RiskItem(
          file: path,
          level: RiskLevel.red,
          reason: 'Regras de segurança Firestore/Storage',
        ));
      }

      if (diff.casWeakened || diff.idempotencyWeakened) {
        items.add(RiskItem(
          file: path,
          level: RiskLevel.blocking,
          reason: 'Enfraquecimento CAS/idempotência detectado',
        ));
      }

      if (items.where((i) => i.file == path).isEmpty) {
        items.add(RiskItem(
          file: path,
          level: RiskLevel.green,
          reason: 'Alteração isolada ou baixo impacto identificado',
        ));
      }
    }

    if (items.isEmpty && domains.isNotEmpty) {
      final level = domains.any((d) =>
              {'Estoque', 'Financeiro', 'PDV', 'Sync', 'Tenant'}.contains(d))
          ? RiskLevel.red
          : RiskLevel.yellow;
      items.add(RiskItem(
        file: '<domains>',
        level: level,
        reason: 'Domínios impactados: ${domains.join(', ')}',
      ));
    }

    final overall = _maxLevel(items.map((e) => e.level).toList());
    return RiskResult(items: items, overall: overall);
  }

  RiskLevel _maxLevel(List<RiskLevel> levels) {
    if (levels.contains(RiskLevel.blocking)) return RiskLevel.blocking;
    if (levels.contains(RiskLevel.red)) return RiskLevel.red;
    if (levels.contains(RiskLevel.yellow)) return RiskLevel.yellow;
    return RiskLevel.green;
  }
}
