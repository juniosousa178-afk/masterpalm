import 'package:masterpalm_platform/masterpalm_platform.dart';

import 'diff_analyzer.dart';
import 'documentation_checker.dart';
import 'guardian_config.dart';
import 'impact_analyzer.dart';
import 'models/guardian_result.dart';
import 'models/impact_result.dart';
import 'models/risk_result.dart';
import 'models/rule_violation.dart';
import 'risk_classifier.dart';
import 'rule_engine.dart';
import 'test_selector.dart';

class GuardianEngine {
  GuardianEngine._({
    required this.repoRoot,
    required this.platform,
    required this.config,
    required this.ast,
    required this.diffAnalyzer,
    required this.impactAnalyzer,
    required this.riskClassifier,
    required this.testSelector,
    required this.docChecker,
    required this.ruleEngine,
  });

  /// Composition-only constructor used by [GuardianPlatformBootstrap].
  factory GuardianEngine.compose({
    required String repoRoot,
    required PlatformCore platform,
    required GuardianConfig config,
    required AstProvider ast,
  }) {
    return GuardianEngine._(
      repoRoot: repoRoot,
      platform: platform,
      config: config,
      ast: ast,
      diffAnalyzer: DiffAnalyzer(repoRoot: repoRoot),
      impactAnalyzer: ImpactAnalyzer(config: config, ast: ast),
      riskClassifier: RiskClassifier(config: config),
      testSelector: TestSelector(repoRoot: repoRoot, config: config),
      docChecker: DocumentationChecker(config: config),
      ruleEngine: RuleEngine(config: config, ast: ast),
    );
  }

  final String repoRoot;
  final PlatformCore platform;
  final GuardianConfig config;
  final AstProvider ast;
  final DiffAnalyzer diffAnalyzer;
  final ImpactAnalyzer impactAnalyzer;
  final RiskClassifier riskClassifier;
  final TestSelector testSelector;
  final DocumentationChecker docChecker;
  final RuleEngine ruleEngine;

  Future<GuardianResult> analyze({
    bool workingTree = false,
    bool staged = false,
    String? base,
    String? head,
    List<String>? files,
    bool simulationOnly = true,
    DiffAnalysis? injectedDiff,
    bool g009EvidenceSatisfied = false,
    String? explicitBaseHead,
  }) async {
    final diff = injectedDiff ??
        await diffAnalyzer.fromGit(
          workingTree: workingTree,
          staged: staged,
          base: base,
          head: head,
          explicitFiles: files,
          explicitBaseHead: explicitBaseHead,
        );

    final impact = impactAnalyzer.analyze(diff);
    final risk = riskClassifier.classify(diff, impact.domains);
    final changedPaths = diff.changes.map((c) => c.path).toList();
    final tests = testSelector.select(impact, changedPaths);
    final violations = ruleEngine.evaluate(
      diff: diff,
      impact: impact,
      missingTests: tests.missing,
      simulationOnly: simulationOnly,
      g009EvidenceSatisfied: g009EvidenceSatisfied,
    );
    final requiredDocs = docChecker.requiredDocs(impact, changedPaths);

    final decision = _decide(risk, violations);
    final summary = _summary(diff, impact, risk, violations, decision);

    return GuardianResult(
      decision: decision,
      summary: summary,
      filesAdded: diff.changes
          .where((c) => c.status == ChangeStatus.added)
          .map((c) => c.path)
          .toList(),
      filesModified: diff.changes
          .where((c) => c.status == ChangeStatus.modified)
          .map((c) => c.path)
          .toList(),
      filesRemoved: diff.changes
          .where((c) => c.status == ChangeStatus.removed)
          .map((c) => c.path)
          .toList(),
      methodsChanged: diff.methodsChanged,
      classesChanged: diff.classesChanged,
      importsChanged: diff.importsChanged,
      impact: impact,
      risk: risk,
      violations: violations,
      requiredTests: tests.required,
      foundTests: tests.found,
      missingTests: tests.missing,
      recommendedTests: tests.recommended,
      suggestedTestCommand: tests.suggestedCommand,
      requiredDocumentation: requiredDocs,
      recommendations: _recommendations(impact, violations),
      simulationOnly: simulationOnly,
    );
  }

  GuardianDecision _decide(RiskResult risk, List<RuleViolation> violations) {
    if (violations.any((v) => v.severity == RuleSeverity.blocking)) {
      return GuardianDecision.noGo;
    }
    if (risk.overall == RiskLevel.blocking || risk.overall == RiskLevel.red) {
      if (violations.any((v) =>
          v.severity == RuleSeverity.red &&
          v.code != 'G001' &&
          v.code != 'G004')) {
        return GuardianDecision.noGo;
      }
    }
    if (violations.any((v) => v.severity == RuleSeverity.red)) {
      return GuardianDecision.noGo;
    }
    return GuardianDecision.go;
  }

  String _summary(
    DiffAnalysis diff,
    ImpactResult impact,
    RiskResult risk,
    List<RuleViolation> violations,
    GuardianDecision decision,
  ) {
    return 'Guardian V4: ${diff.changes.length} ficheiro(s), '
        'domínios [${impact.domains.join(', ')}], '
        'risco ${risk.overall.name}, '
        '${violations.length} violação(ões), '
        'decisão ${decision.name.toUpperCase()}';
  }

  List<String> _recommendations(
    ImpactResult impact,
    List<RuleViolation> violations,
  ) {
    final rec = <String>[];
    if (impact.domains.contains('Estoque')) {
      rec.add(
          'Revisar docs/intelligence/CHANGE_IMPACT.md — EstoqueTransactionService');
    }
    if (violations.any((v) => v.code == 'G006')) {
      rec.add('Considerar extrair métodos para reduzir complexidade.');
    }
    if (impact.relatedRcas.isNotEmpty) {
      rec.add('RCAs relacionados: ${impact.relatedRcas.join(', ')}');
    }
    return rec;
  }
}
