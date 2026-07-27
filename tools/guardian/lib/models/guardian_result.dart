import 'impact_result.dart';
import 'risk_result.dart';
import 'rule_violation.dart';

enum GuardianDecision { go, noGo }

class GuardianResult {
  GuardianResult({
    required this.decision,
    required this.summary,
    required this.filesAdded,
    required this.filesModified,
    required this.filesRemoved,
    required this.methodsChanged,
    required this.classesChanged,
    required this.importsChanged,
    required this.impact,
    required this.risk,
    required this.violations,
    required this.requiredTests,
    required this.foundTests,
    required this.missingTests,
    required this.recommendedTests,
    required this.suggestedTestCommand,
    required this.requiredDocumentation,
    required this.recommendations,
    this.simulationOnly = true,
  });

  final GuardianDecision decision;
  final String summary;
  final List<String> filesAdded;
  final List<String> filesModified;
  final List<String> filesRemoved;
  final List<String> methodsChanged;
  final List<String> classesChanged;
  final List<String> importsChanged;
  final ImpactResult impact;
  final RiskResult risk;
  final List<RuleViolation> violations;
  final List<String> requiredTests;
  final List<String> foundTests;
  final List<String> missingTests;
  final List<String> recommendedTests;
  final String suggestedTestCommand;
  final List<String> requiredDocumentation;
  final List<String> recommendations;
  final bool simulationOnly;

  Map<String, dynamic> toJson() => {
        'decision': decision.name,
        'summary': summary,
        'simulation_only': simulationOnly,
        'files': {
          'added': filesAdded,
          'modified': filesModified,
          'removed': filesRemoved,
        },
        'methods_changed': methodsChanged,
        'classes_changed': classesChanged,
        'imports_changed': importsChanged,
        'impact': impact.toJson(),
        'risk': risk.toJson(),
        'violations': violations.map((e) => e.toJson()).toList(),
        'tests': {
          'required': requiredTests,
          'found': foundTests,
          'missing': missingTests,
          'recommended': recommendedTests,
          'suggested_command': suggestedTestCommand,
        },
        'required_documentation': requiredDocumentation,
        'recommendations': recommendations,
      };
}
