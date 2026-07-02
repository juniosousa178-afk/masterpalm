// Manifesto estático de integridade do runner Emulator (Fase 6.5).
// Espelha pdv_v1_current_rules_emulator_runner.mjs — não executa Node.

/// Metadados comprovados por auditoria estática do runner .mjs existente.
class PdvV1RulesRunnerIntegrityManifest {
  const PdvV1RulesRunnerIntegrityManifest._();

  static const sdk = '@firebase/rules-unit-testing (Client SDK)';
  static const usesFirebaseAdmin = false;
  static const usesInitializeAdminApp = false;
  static const usesAssertSucceedsFails = true;
  static const projectId = 'demo-masterpalm-pdv-v1-harness';
  static const bypassOnlyInSetup = true;
  static const bypassMethod = 'withSecurityRulesDisabled';
  static const bypassLineRange = '96-127';
  static const assertUsesAuthenticatedContext = true;
  static const assertOwnerUid = 'owner_demo_pdv_v1_64';
  static const assertOutsiderUid = 'outsider_demo_pdv_v1_64';
  static const assertLineRange = '136-195';
  static const referencesProductionProject = false;

  /// Operações avaliadas (assert) — todas via authenticatedContext.
  static const assertOperations = <PdvV1RulesRunnerOperationSpec>[
    PdvV1RulesRunnerOperationSpec(
      name: '1. read marcador membro',
      sdk: sdk,
      authenticated: true,
      bypass: false,
      phase: PdvV1RulesRunnerPhase.assertOp,
    ),
    PdvV1RulesRunnerOperationSpec(
      name: '2. create marcador legado',
      sdk: sdk,
      authenticated: true,
      bypass: false,
      phase: PdvV1RulesRunnerPhase.assertOp,
    ),
    PdvV1RulesRunnerOperationSpec(
      name: '3. forge baixaAplicada:true',
      sdk: sdk,
      authenticated: true,
      bypass: false,
      phase: PdvV1RulesRunnerPhase.assertOp,
    ),
    PdvV1RulesRunnerOperationSpec(
      name: '4. forge estornoAplicado:true',
      sdk: sdk,
      authenticated: true,
      bypass: false,
      phase: PdvV1RulesRunnerPhase.assertOp,
    ),
    PdvV1RulesRunnerOperationSpec(
      name: '5. update marcador livre',
      sdk: sdk,
      authenticated: true,
      bypass: false,
      phase: PdvV1RulesRunnerPhase.assertOp,
    ),
    PdvV1RulesRunnerOperationSpec(
      name: '6. outsider read deny',
      sdk: sdk,
      authenticated: true,
      bypass: false,
      phase: PdvV1RulesRunnerPhase.assertOp,
    ),
    PdvV1RulesRunnerOperationSpec(
      name: '7. outsider write deny',
      sdk: sdk,
      authenticated: true,
      bypass: false,
      phase: PdvV1RulesRunnerPhase.assertOp,
    ),
    PdvV1RulesRunnerOperationSpec(
      name: '8. write estoque_produtos membro',
      sdk: sdk,
      authenticated: true,
      bypass: false,
      phase: PdvV1RulesRunnerPhase.assertOp,
    ),
    PdvV1RulesRunnerOperationSpec(
      name: '9. outsider estoque deny',
      sdk: sdk,
      authenticated: true,
      bypass: false,
      phase: PdvV1RulesRunnerPhase.assertOp,
    ),
    PdvV1RulesRunnerOperationSpec(
      name: 'setup fixture lojas/users/estoque',
      sdk: sdk,
      authenticated: false,
      bypass: true,
      phase: PdvV1RulesRunnerPhase.setupOnly,
    ),
  ];
}

enum PdvV1RulesRunnerPhase { setupOnly, assertOp }

class PdvV1RulesRunnerOperationSpec {
  const PdvV1RulesRunnerOperationSpec({
    required this.name,
    required this.sdk,
    required this.authenticated,
    required this.bypass,
    required this.phase,
  });

  final String name;
  final String sdk;
  final bool authenticated;
  final bool bypass;
  final PdvV1RulesRunnerPhase phase;

  bool get resultReliable =>
      phase == PdvV1RulesRunnerPhase.setupOnly ||
      (phase == PdvV1RulesRunnerPhase.assertOp && authenticated && !bypass);
}
