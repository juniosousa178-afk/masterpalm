# Matriz de Rastreabilidade — Release Governance (Sprint 04.2)

**Domínio:** MasterPalm Engineering Platform — Release Governance Foundation
**Políticas candidatas:** `release-governance-v1`, `release-governance-v1.1`
**Última atualização:** 2026-07-21
**Sprint:** 04.2 Part 3

## Legenda de status

| Status | Significado |
|--------|-------------|
| `covered` | Requisito implementado e com evidência de teste ou integração verificável |
| `partiallyCovered` | Implementado com limitação conhecida, cobertura de teste incompleta ou semântica derivada |
| `notCovered` | Não implementado ou sem evidência |
| `notApplicable` | Fora do escopo desta sprint ou não aplicável ao componente |

---

## 1. Regras normativas RG001–RG020

| ID | Requisito | Target | Operador | Rule set | Componente | Arquivo | Teste | Status | Observação |
|----|-----------|--------|----------|----------|------------|---------|-------|--------|------------|
| RG001 | Consistência de projeto entre fontes | `projectConsistency` | `isTrue` | release-integrity | `CrossArtifactReleaseGovernanceTargetResolver` | `lib/release_governance/release_governance_target_registry.dart` | `release_governance_engine_test.dart`, `release_governance_semantics_test.dart` | covered | Bloqueia mismatch projeto/QG/contexto |
| RG002 | Consistência de commit entre fontes | `commitConsistency` | `isTrue` | release-integrity | `CrossArtifactReleaseGovernanceTargetResolver` | `lib/release_governance/release_governance_target_registry.dart` | `release_governance_semantics_test.dart` | covered | `notApplicable` quando `commitId` ausente |
| RG003 | Quality Gate disponível | `qualityGateDecision` | `isAvailable` | technical-gate | `QualityGateReleaseGovernanceTargetResolver` | `lib/release_governance/release_governance_target_registry.dart` | `release_governance_engine_test.dart` (QG ausente) | covered | Ausência → `unavailable`/`pending` |
| RG004 | Decisão QG permitida (passed/partial) | `qualityGateDecision` | `inSet` | technical-gate | `QualityGateReleaseGovernanceTargetResolver` | `lib/release_governance/release_governance_target_registry.dart` | `release_governance_provider_test.dart` (rejected QG) | covered | QG `failed` → `rejected` |
| RG005 | Quality Gate compatível | `qualityGateCompatibility` | `isCompatible` | technical-gate | `QualityGateReleaseGovernanceTargetResolver` | `lib/release_governance/release_governance_target_registry.dart` | `release_governance_engine_test.dart` (passing) | covered | — |
| RG006 | Quality Gate elegível | `qualityGateEligibility` | `isValid` (v1) / `isEligible` (v1.1) | technical-gate | `QualityGateReleaseGovernanceTargetResolver` | `lib/release_governance/release_governance_target_registry.dart` | `release_governance_policy_v1_test.dart`, `release_governance_semantics_test.dart` | partiallyCovered | v1: `isValid` estrutural; v1.1: `isEligible` normativo |
| RG007 | Coverage QG ≥ 80% | `qualityGateCoverage` | `greaterThanOrEqual` | technical-gate | `QualityGateReleaseGovernanceTargetResolver` | `lib/release_governance/release_governance_target_registry.dart` | `release_governance_engine_test.dart` (passing) | covered | — |
| RG008 | Freshness QG ≤ P7D | `qualityGateAge` | `lessThanOrEqual` | technical-gate | `QualityGateReleaseGovernanceTargetResolver` | `lib/release_governance/release_governance_target_registry.dart` | `release_governance_semantics_test.dart` | covered | Warning `staleQualityGate` quando próximo do limite |
| RG009 | Ambiente de release suportado | `releaseEnvironment` | `inSet` | environment-governance | `ReleaseContextReleaseGovernanceTargetResolver` | `lib/release_governance/release_governance_target_registry.dart` | `release_context_validator_test.dart` | covered | — |
| RG010 | Tipo de release suportado | `releaseType` | `inSet` | environment-governance | `ReleaseContextReleaseGovernanceTargetResolver` | `lib/release_governance/release_governance_target_registry.dart` | `release_context_validator_test.dart` | covered | — |
| RG011 | Aprovações obrigatórias completas | `missingApprovalCount` | `equals` (`0`) | approval-governance | `ApprovalReleaseGovernanceTargetResolver` | `lib/release_governance/release_governance_target_registry.dart` | `release_governance_provider_test.dart` (missing approvals) | covered | Ausência → `pending` |
| RG012 | Zero aprovações rejeitadas | `rejectedApprovalCount` | `equals` (`0`) | approval-governance | `ApprovalReleaseGovernanceTargetResolver` | `lib/release_governance/release_governance_target_registry.dart` | `release_approval_validator_test.dart`, `release_governance_semantics_test.dart` | covered | — |
| RG013 | Separation of duties satisfeita | `separationOfDutiesSatisfied` | `isTrue` | approval-governance | `ApprovalReleaseGovernanceTargetResolver` | `lib/release_governance/release_governance_target_registry.dart` | `release_governance_semantics_test.dart` | covered | — |
| RG014 | Zero aprovações expiradas | `expiredApprovalCount` | `equals` (`0`) | approval-governance | `ApprovalReleaseGovernanceTargetResolver` | `lib/release_governance/release_governance_target_registry.dart` | `release_approval_validator_test.dart` | covered | Waiver permitido com condições |
| RG015 | Zero waivers inválidos | `invalidWaiverCount` | `equals` (`0`) | waiver-governance | `WaiverReleaseGovernanceTargetResolver` | `lib/release_governance/release_governance_target_registry.dart` | `release_waiver_validator_test.dart` | covered | — |
| RG016 | Zero waivers expirados | `expiredWaiverCount` | `equals` (`0`) | waiver-governance | `WaiverReleaseGovernanceTargetResolver` | `lib/release_governance/release_governance_target_registry.dart` | `release_waiver_validator_test.dart` | covered | — |
| RG017 | Limite de waivers satisfeito | `waiverLimitSatisfied` | `isTrue` | waiver-governance | `WaiverReleaseGovernanceTargetResolver` | `lib/release_governance/release_governance_target_registry.dart` | `release_governance_semantics_test.dart` | covered | — |
| RG018 | Evidência de aprovação completa | `approvalEvidenceComplete` | `isTrue` | evidence-integrity | `ApprovalReleaseGovernanceTargetResolver` | `lib/release_governance/release_governance_target_registry.dart` | `release_approval_validator_test.dart` | covered | — |
| RG019 | Evidência de waiver completa | `waiverEvidenceComplete` | `isTrue` | evidence-integrity | `WaiverReleaseGovernanceTargetResolver` | `lib/release_governance/release_governance_target_registry.dart` | `release_waiver_validator_test.dart` | partiallyCovered | Regra **optional**; skip quando waiver set ausente |
| RG020 | Artefatos de release presentes | `releaseArtifactCount` | `greaterThan` (`0`) | final-authorization | `ReleaseContextReleaseGovernanceTargetResolver` | `lib/release_governance/release_governance_target_registry.dart` | `release_context_validator_test.dart` | partiallyCovered | Regra **optional** com severity `warning` |

---

## 2. Targets (`ReleaseGovernanceRuleTarget`)

### 2.1 Quality Gate

| Target | Resolver | Status | Teste |
|--------|----------|--------|-------|
| `qualityGateDecision` | QualityGate | covered | engine, provider |
| `qualityGatePolicyId` | QualityGate | partiallyCovered | policy test |
| `qualityGatePolicyVersion` | QualityGate | partiallyCovered | policy test |
| `qualityGateEligibility` | QualityGate | partiallyCovered | semantics (v1/v1.1) |
| `qualityGateCompatibility` | QualityGate | covered | engine |
| `qualityGateCoverage` | QualityGate | covered | engine |
| `qualityGateBlockingFailureCount` | QualityGate | partiallyCovered | — |
| `qualityGateCriticalFailureCount` | QualityGate | partiallyCovered | — |
| `qualityGateFailedRuleCount` | QualityGate | partiallyCovered | — |
| `qualityGateFingerprint` | QualityGate | covered | models test |
| `qualityGateAge` | QualityGate | covered | semantics |
| `qualityGateProjectConsistency` | QualityGate | covered | semantics |
| `qualityGateCommitConsistency` | QualityGate | partiallyCovered | — |

### 2.2 Release Context

| Target | Status | Teste |
|--------|--------|-------|
| `releaseProjectId` | covered | context validator |
| `releaseCommitId` | covered | context validator |
| `releaseBranch` | partiallyCovered | — |
| `releaseVersion` | partiallyCovered | — |
| `releaseEnvironment` | covered | context validator |
| `releaseType` | covered | context validator |
| `releaseArtifactCount` | partiallyCovered | context validator (RG020) |
| `releaseRequestedByPresent` | partiallyCovered | — |
| `releaseTargetDateValid` | partiallyCovered | — |

### 2.3 Approval

| Target | Status | Teste |
|--------|--------|-------|
| `requiredApprovalCount` | covered | semantics |
| `validApprovalCount` | covered | approval validator |
| `missingApprovalCount` | covered | provider test |
| `rejectedApprovalCount` | covered | approval validator |
| `expiredApprovalCount` | covered | approval validator |
| `approvalAuthorityPresent` | partiallyCovered | — |
| `separationOfDutiesSatisfied` | covered | semantics |
| `approvalEvidenceComplete` | covered | approval validator |

### 2.4 Waiver

| Target | Status | Teste |
|--------|--------|-------|
| `activeWaiverCount` | partiallyCovered | semantics |
| `invalidWaiverCount` | covered | waiver validator |
| `expiredWaiverCount` | covered | waiver validator |
| `waiverScopeValid` | partiallyCovered | waiver validator |
| `waiverAuthorityValid` | partiallyCovered | — |
| `waiverEvidenceComplete` | partiallyCovered | waiver validator |
| `waiverExpirationValid` | partiallyCovered | waiver validator |
| `waiverLimitSatisfied` | covered | semantics |

### 2.5 Cross-artifact

| Target | Status | Teste |
|--------|--------|-------|
| `projectConsistency` | covered | engine, semantics |
| `commitConsistency` | covered | semantics |
| `environmentCompatibility` | partiallyCovered | — |
| `policyCompatibility` | covered | compatibility checker |
| `sourceFreshness` | partiallyCovered | — |
| `requiredSourcesAvailable` | covered | engine (QG ausente) |

---

## 3. Operadores (`ReleaseGovernanceRuleOperator`)

| Operador | Implementação | Teste | Status |
|----------|---------------|-------|--------|
| `equals` | `ReleaseGovernanceOperatorEvaluator` | semantics, validators | covered |
| `notEquals` | idem | — | partiallyCovered |
| `greaterThan` | idem | context validator (RG020) | partiallyCovered |
| `greaterThanOrEqual` | idem | engine (RG007) | covered |
| `lessThan` | idem | — | partiallyCovered |
| `lessThanOrEqual` | idem | semantics (RG008) | covered |
| `betweenInclusive` | idem | — | partiallyCovered |
| `betweenExclusive` | idem | — | notCovered |
| `inSet` | idem | provider (RG004), context (RG009–RG010) | covered |
| `notInSet` | idem | — | partiallyCovered |
| `contains` | idem | — | partiallyCovered |
| `containsAny` | idem | — | notCovered |
| `containsAll` | idem | — | notCovered |
| `exists` | idem | — | partiallyCovered |
| `doesNotExist` | idem | — | partiallyCovered |
| `isTrue` | idem | engine, semantics | covered |
| `isFalse` | idem | — | partiallyCovered |
| `isAvailable` | idem | engine (RG003) | covered |
| `isUnavailable` | idem | — | partiallyCovered |
| `isCompatible` | idem | engine (RG005) | covered |
| `isIncompatible` | idem | — | partiallyCovered |
| `isEligible` | idem | policy v1.1 test | covered |
| `isNotEligible` | idem | — | partiallyCovered |
| `isValid` | idem | policy v1 test (RG006) | covered |
| `isInvalid` | idem | — | partiallyCovered |
| `isExpired` | idem | approval/waiver validators | partiallyCovered |
| `isNotExpired` | idem | — | partiallyCovered |

---

## 4. Componentes core

| Componente | Arquivo | Teste | Status |
|------------|---------|-------|--------|
| Engine | `lib/release_governance/release_governance_engine.dart` | `release_governance_engine_test.dart` | covered |
| Source resolver | `lib/release_governance/release_governance_source_resolver.dart` | `release_governance_source_resolver_test.dart` | covered |
| Policy validator | `lib/release_governance/release_governance_policy_validator.dart` | `release_governance_policy_validator_test.dart` | covered |
| Context validator | `lib/release_governance/release_context_validator.dart` | `release_context_validator_test.dart` | covered |
| Approval validator | `lib/release_governance/release_approval_validator.dart` | `release_approval_validator_test.dart` | covered |
| Waiver validator | `lib/release_governance/release_waiver_validator.dart` | `release_waiver_validator_test.dart` | covered |
| Snapshot validator | `lib/release_governance/release_decision_snapshot_validator.dart` | provider test (publish) | covered |
| Compatibility checker | `lib/release_governance/release_governance_compatibility_checker.dart` | semantics test | covered |
| Eligibility evaluator | `lib/release_governance/release_governance_eligibility_evaluator.dart` | semantics test | covered |
| Approval evaluator | `lib/release_governance/release_governance_approval_evaluator.dart` | semantics test | covered |
| Waiver evaluator | `lib/release_governance/release_governance_waiver_evaluator.dart` | semantics test | covered |
| Decision aggregator | `lib/release_governance/release_governance_decision_aggregator.dart` | semantics test | covered |
| Condition builder | `lib/release_governance/release_governance_condition_builder.dart` | semantics test | partiallyCovered |
| Coverage calculator | `lib/release_governance/release_governance_coverage_calculator.dart` | engine test | covered |
| Identity builder | `lib/release_governance/release_governance_identity_builder.dart` | models test | covered |
| Canonical serializer | `lib/release_governance/release_governance_canonical_serializer.dart` | models test | covered |
| Provider | `lib/providers/platform_release_governance_provider.dart` | `release_governance_provider_test.dart` | covered |
| Store (in-memory) | `lib/release_governance/stores/in_memory_release_governance_store.dart` | `release_governance_store_test.dart` | covered |
| Policy registry | `lib/release_governance/release_governance_policy_registry.dart` | policy v1 test | covered |
| Bootstrap | `lib/release_governance/release_governance_platform_bootstrap.dart` | provider test (indireto) | partiallyCovered |

---

## 5. Integrações

| Integração | Tipo / Enum | Componente | Arquivo | Teste dedicado | Status | Observação |
|------------|-------------|------------|---------|----------------|--------|------------|
| Report | `ReportType.releaseGovernance` | `ReleaseGovernanceReportSource` | `lib/report/sources/release_governance_report_source.dart` | Pendente | partiallyCovered | Consome snapshot; não executa engine — design verificado |
| History | `HistoryArtifactType.releaseGovernance` | `ReleaseGovernanceHistoryMapper` | `lib/history/mappers/release_governance_history_mapper.dart` | Pendente | partiallyCovered | Factory + comparator registados; teste dedicado pendente |
| Dashboard | `DashboardSectionType.releaseGovernance` | `ReleaseGovernanceSectionBuilder` | `lib/dashboard/builders/release_governance_section_builder.dart` | Pendente | partiallyCovered | Não chama `evaluate()`; resolver em `dashboard_source_resolver.dart` |
| Observability | `TelemetryComponent.releaseGovernance` | `ObservableReleaseGovernanceProvider` | `lib/observability/instrumentation/observable_release_governance_provider.dart` | Pendente | partiallyCovered | Decorator transparente; hardening pendente |

### 5.1 Report — campos expostos

| Campo | Status |
|-------|--------|
| `decision` | covered (implementação) |
| `releaseContext` | covered |
| `qualityGateReference` | covered |
| `failedRules` / `passedRules` / `waivedRules` | covered |
| `pendingApprovals` / `rejectedApprovals` | covered |
| `activeWaivers` / `invalidWaivers` | covered |
| `openConditions` | covered |
| `coverage` / `compatibility` / `eligibility` | covered |
| `limitations` / `warnings` | covered |

### 5.2 Dashboard — widgets

| Widget ID | Status |
|-----------|--------|
| `releaseGovernance.decision` | covered (implementação) |
| `releaseGovernance.release` | covered |
| `releaseGovernance.environment` | covered |
| `releaseGovernance.releaseType` | covered |
| `releaseGovernance.policy-version` | covered |
| `releaseGovernance.qualityGate` | covered |
| `releaseGovernance.pending-approvals` | covered |
| `releaseGovernance.active-waivers` | covered |
| `releaseGovernance.open-conditions` | covered |
| `releaseGovernance.coverage` | covered |
| `releaseGovernance.compatibility` | covered |
| `releaseGovernance.eligibility` | covered |

### 5.3 History — campos comparáveis

| Campo | Status |
|-------|--------|
| `decision` | covered (mapper) |
| `policyVersion` | covered |
| `qualityGateSnapshotId` | covered |
| `coverage` | covered |
| `failedRuleCount` | covered |
| `pendingApprovalCount` | partiallyCovered |

---

## 6. Políticas

| Política | Versão | Regras | RG006 | Validator | Teste | Status |
|----------|--------|--------|-------|-----------|-------|--------|
| `release-governance-v1` | 1 | RG001–RG020 | `isValid` | `ReleaseGovernancePolicyValidator` | `release_governance_policy_v1_test.dart` | covered |
| `release-governance-v1.1` | 2 | RG001–RG020 | `isEligible` | idem | `release_governance_policy_v1_test.dart` | covered |

| Aspecto de governança | Status |
|-----------------------|--------|
| Policy fingerprint estável | covered |
| Registry freeze | covered |
| Status `candidate` | covered |
| Limitations declaradas (no-cicd, no-crypto) | covered |
| `compatibilityPolicy` restringe QG policy | covered |
| Approval requirements definidos | covered |
| Waiver rules definidos | covered |
| Decision policy (failOnCritical, pendingOnMissing) | covered |
| Promoção candidate → active | notCovered | Fora de escopo Sprint 04.2 |

---

## 7. Limitações e requisitos não funcionais

| ID | Requisito / Limitação | Mecanismo | Status |
|----|----------------------|-----------|--------|
| RG-NF-001 | Não recalcular Quality Gate | `ReleaseGovernanceSourceResolver` | covered |
| RG-NF-002 | Determinismo de snapshot ID | `ReleaseGovernanceIdentityBuilder` | covered |
| RG-NF-003 | Publicação idempotente | `InMemoryReleaseGovernanceStore.save` | covered |
| RG-NF-004 | Store in-memory | `InMemoryReleaseGovernanceStore` | covered |
| RG-NF-005 | Sem verificação criptográfica | `authorityNotCryptographicallyVerified` | covered |
| RG-NF-006 | Sem CI/CD enforcement | `noCiCdEnforcement` | covered |
| RG-NF-007 | Sem consumo automático de waiver | `noAutomaticWaiverConsumption` | covered |
| RG-NF-008 | Persistência física | — | notCovered | Sprint futura |
| RG-NF-009 | Assinatura digital de aprovações | — | notCovered | Sprint futura |
| RG-NF-010 | Integração CI/CD pipeline | — | notCovered | Sprint 04.3+ |

---

## 8. Resumo executivo

| Categoria | Total | covered | partiallyCovered | notCovered | notApplicable |
|-----------|-------|---------|------------------|------------|---------------|
| Regras RG001–RG020 | 20 | 18 | 2 | 0 | 0 |
| Integrações | 4 | 0 | 4 | 0 | 0 |
| Componentes core | 20 | 18 | 2 | 0 | 0 |
| Operadores (uso na policy) | 8 usados | 6 | 2 | 0 | 18 não usados |
| Limitações NF | 10 | 7 | 0 | 3 | 0 |

**Regras críticas (RG001–RG004, RG011–RG012, RG015):** todas `covered` com evidência de teste.

**Condições residuais:** RG006 semântica v1 (`partiallyCovered`); RG019/RG020 optional (`partiallyCovered`); integrações sem teste dedicado (`partiallyCovered`); persistência e crypto auth (`notCovered` — fora de escopo).

---

## Referências

- `README.md` — guia de uso
- `release_governance_release_checklist.md` — checklist de release
- `../adr/ADR-028-release-governance-authorizes-release-progression.md`
- `../architecture-reviews/AR-014-release-governance-foundation.md`
- `test/release_governance/` — **61 testes** (2026-07-21)
