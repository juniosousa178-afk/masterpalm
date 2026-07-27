import 'package:masterpalm_platform/masterpalm_platform.dart';

import 'diff_analyzer.dart';
import 'guardian_config.dart';
import 'models/impact_result.dart';
import 'models/rule_violation.dart';

class RuleEngine {
  RuleEngine({
    required this.config,
    required this.ast,
  });

  final GuardianConfig config;
  final AstProvider ast;

  List<RuleViolation> evaluate({
    required DiffAnalysis diff,
    required ImpactResult impact,
    required List<String> missingTests,
    required bool simulationOnly,
    bool g009EvidenceSatisfied = false,
  }) {
    final violations = <RuleViolation>[];

    // G001 — informational always
    violations.add(RuleViolation(
      code: 'G001',
      severity: RuleSeverity.info,
      message:
          'Nenhum commit, push ou deploy sem autorização explícita do utilizador.',
      requiredAction: 'Confirmar autorização antes de commit/push/deploy.',
    ));

    if (impact.domains.contains('Estoque')) {
      _requireTests(
          violations,
          'G002',
          missingTests,
          [
            'estoque_transaction',
            'variacoes',
            'consignado',
            'estorno',
            'idempotencia',
          ],
          'Mudança em estoque exige testes de venda, variações, consignado, devolução e idempotência.');
    }

    if (impact.domains.contains('Financeiro') ||
        impact.domains.contains('Fiado')) {
      _requireTests(
          violations,
          'G003',
          missingTests,
          [
            'conta_receber',
            'fiado',
            'financeiro',
            'duplicada',
          ],
          'Mudança financeira exige testes de CR, fiado, cancelamento e duplicidade.');
    }

    if (diff.transactionsTouched ||
        diff.firestoreTouched.isNotEmpty ||
        impact.domains.contains('Firestore')) {
      violations.add(RuleViolation(
        code: 'G004',
        severity: RuleSeverity.yellow,
        message:
            'Mudança em Firestore write — verificar transaction, batch, CAS, retry, idempotência e rollback.',
        evidence: diff.firestoreTouched.join(', '),
        requiredAction: 'Revisar TRANSACTION_MAP e WRITE_CALLERS.',
      ));
    }

    if (impact.domains.contains('Sync') ||
        impact.domains.contains('Offline') ||
        impact.domains.contains('Hive')) {
      _requireTests(
          violations,
          'G005',
          missingTests,
          [
            'sync',
            'recovery',
            'offline',
            'hive',
          ],
          'Mudança Hive/sync exige testes offline, replay, conflito e recovery.');
    }

    for (final change in diff.changes) {
      final path = change.path.replaceAll('\\', '/');
      final maxComplexity = ast.complexityForFile(path);
      if (maxComplexity != null && maxComplexity > 80) {
        final increased = _complexityIncreased(change);
        violations.add(RuleViolation(
          code: 'G006',
          severity: increased ? RuleSeverity.red : RuleSeverity.yellow,
          file: path,
          message:
              'Método com complexidade AST > 80 ($maxComplexity). Não aumentar; exige teste e justificativa.',
          evidence: 'complexity=$maxComplexity',
          requiredAction:
              'Adicionar teste direcionado e justificativa no relatório.',
        ));
      }

      final critical = config.criticalFiles.where((c) => path.contains(c.path));
      for (final cf in critical) {
        if (cf.lines > 3000 && change.addedLines.length > 30) {
          violations.add(RuleViolation(
            code: 'G007',
            severity: g009EvidenceSatisfied && simulationOnly
                ? RuleSeverity.yellow
                : RuleSeverity.red,
            file: path,
            message:
                'Arquivo crítico > 3000 linhas com alteração funcional extensa.',
            evidence: '${cf.lines} linhas, +${change.addedLines.length} linhas',
            requiredAction: 'Plano de redução de risco antes de continuar.',
          ));
        }
      }
    }

    if (diff.newImportCycleSuspected ||
        _suspectedNewCycle(diff.importsChanged, diff.allPaths)) {
      violations.add(RuleViolation(
        code: 'G008',
        severity: RuleSeverity.blocking,
        message: 'Novo ciclo de import detectado ou suspeito.',
        evidence: diff.importsChanged.join(', '),
        requiredAction: 'Quebrar ciclo antes de continuar.',
      ));
    }

    if (diff.securityRulesTouched && !g009EvidenceSatisfied) {
      violations.add(RuleViolation(
        code: 'G009',
        severity: RuleSeverity.red,
        message:
            'Alteração em Firestore/Storage Rules exige testes de segurança.',
        requiredAction:
            'Executar validação rules (emulator) — ver docs/engineering/Checklists/Firestore.md',
      ));
    } else if (diff.securityRulesTouched && g009EvidenceSatisfied) {
      violations.add(RuleViolation(
        code: 'G009',
        severity: RuleSeverity.info,
        message:
            'Evidência emulator rules validada (guardian-evidence.json).',
        requiredAction: 'Nenhuma — evidência aceite.',
      ));
    }

    if (impact.domains.contains('Tenant') ||
        diff.allPaths.any(
            (p) => p.contains('loja_id') || p.contains('store_resolver'))) {
      _requireTests(
          violations,
          'G010',
          missingTests,
          [
            'multiusuario',
            'multiusuario',
            'store',
          ],
          'Mudança tenant/lojaId exige teste multi-tenant.');
    }

    if (missingTests.isNotEmpty &&
        (impact.domains.contains('Estoque') ||
            impact.domains.contains('PDV') ||
            impact.domains.contains('Financeiro'))) {
      violations.add(RuleViolation(
        code: 'G011',
        severity: RuleSeverity.red,
        message: 'Mudança crítica sem teste correspondente identificado.',
        evidence: missingTests.join(', '),
        requiredAction: 'Adicionar ou executar testes listados.',
      ));
    }

    if (diff.casWeakened || diff.idempotencyWeakened) {
      violations.add(RuleViolation(
        code: 'G012',
        severity: RuleSeverity.blocking,
        message: 'Remoção ou enfraquecimento de CAS/idempotência detectado.',
        requiredAction: 'Reverter alteração ou documentar exceção aprovada.',
      ));
    }

    if (diff.repairScriptTouched) {
      final hasDryRun = diff.changes.any((c) => c.addedLines
          .any((l) => l.contains('dry-run') || l.contains('dryRun')));
      if (!hasDryRun) {
        violations.add(RuleViolation(
          code: 'G013',
          severity: RuleSeverity.blocking,
          message:
              'Script de reparo sem evidência de dry-run/backup/CAS/repairId.',
          requiredAction:
              'Incluir dry-run, backup, CAS updateTime e repairId — ver Engineering Playbook.',
        ));
      }
    }

    if (impact.domains.contains('Venda') || impact.domains.contains('PDV')) {
      violations.add(RuleViolation(
        code: 'G014',
        severity: RuleSeverity.yellow,
        message:
            'Mudança em venda — cruzar estoque, financeiro, cliente, sync e journal.',
        requiredAction: 'Revisar EVENT_MAP e CALL_GRAPH.',
      ));
    }

    if (diff.listenersTouched) {
      violations.add(RuleViolation(
        code: 'G015',
        severity: RuleSeverity.yellow,
        message:
            'Mudança em listener/stream — verificar cancelamento, lifecycle e duplicação.',
        requiredAction: 'Revisar PERFORMANCE_MAP e READ_CALLERS.',
      ));
    }

    return violations;
  }

  void _requireTests(
    List<RuleViolation> violations,
    String code,
    List<String> missingTests,
    List<String> patterns,
    String message,
  ) {
    final relevantMissing = missingTests.where((t) {
      return patterns.any((p) => t.toLowerCase().contains(p.toLowerCase()));
    }).toList();
    if (relevantMissing.isNotEmpty) {
      violations.add(RuleViolation(
        code: code,
        severity: code == 'G002' || code == 'G003'
            ? RuleSeverity.red
            : RuleSeverity.yellow,
        message: message,
        evidence: relevantMissing.join(', '),
        requiredAction: 'Executar testes obrigatórios antes de GO.',
      ));
    }
  }

  bool _complexityIncreased(FileChange change) {
    final added = change.addedLines.where((l) =>
        l.contains('if ') ||
        l.contains('for ') ||
        l.contains('while ') ||
        l.contains('switch '));
    return added.length > change.removedLines.length + 2;
  }

  bool _suspectedNewCycle(List<String> imports, List<String> paths) {
    final touchesPlanAccess =
        paths.any((p) => p.contains('effective_plan_access'));
    final importsPlanos =
        imports.any((i) => i.toLowerCase().contains('planos'));
    return touchesPlanAccess && importsPlanos;
  }
}
