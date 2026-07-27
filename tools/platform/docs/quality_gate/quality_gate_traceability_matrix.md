# Matriz de Rastreabilidade — Quality Gates (Sprint 04.1)

**Domínio:** MasterPalm Engineering Platform — Quality Gates Foundation
**Política candidata:** `quality-gate-release-v1`
**Última atualização:** 2026-07-21
**Sprint:** 04.1 Part 3

## Legenda de status

| Status | Significado |
|--------|-------------|
| `covered` | Requisito implementado e com evidência de teste ou integração verificável |
| `partiallyCovered` | Implementado com limitação conhecida, cobertura de teste incompleta ou semântica derivada |
| `notCovered` | Não implementado ou sem evidência |
| `notApplicable` | Fora do escopo desta sprint ou não aplicável ao componente |

---

## 1. Regras normativas QG001–QG015

| ID | Requisito | Target | Operador | Rule set | Componente | Arquivo | Teste | Status | Observação |
|----|-----------|--------|----------|----------|------------|---------|-------|--------|------------|
| QG001 | Fontes pertencem ao mesmo projeto | `sourceProjectConsistency` | `isTrue` | source-integrity | `CrossArtifactQualityGateTargetResolver` | `lib/quality_gate/quality_gate_target_registry.dart` | `quality_gate_integration_test.dart` (cenário E) | covered | Evidência derivada; bloqueia inconsistência de projeto |
| QG002 | Fontes pertencem ao mesmo commit quando exigido | `sourceCommitConsistency` | `isTrue` | source-integrity | `CrossArtifactQualityGateTargetResolver` | `lib/quality_gate/quality_gate_target_registry.dart` | `quality_gate_models_test.dart` | partiallyCovered | `notApplicable` quando `commitId` ausente no request |
| QG003 | Guardian decision = GO | `guardianDecision` | `equals` (`GO`) | guardian-compliance | `GuardianQualityGateTargetResolver` | `lib/quality_gate/quality_gate_target_registry.dart` | `quality_gate_integration_test.dart` (cenário B) | covered | — |
| QG004 | Zero violações críticas Guardian | `guardianCriticalViolationCount` | `equals` (`0`) | guardian-compliance | `GuardianQualityGateTargetResolver` | `lib/quality_gate/quality_gate_target_registry.dart` | `quality_gate_integration_test.dart` | partiallyCovered | Integração indireta; sem teste dedicado de violações críticas |
| QG005 | Engineering Score ≥ 75 | `engineeringScoreGlobal` | `greaterThanOrEqual` | engineering-score | `ScoreQualityGateTargetResolver` | `lib/quality_gate/quality_gate_target_registry.dart` | `quality_gate_integration_test.dart` (passing) | covered | — |
| QG006 | Engineering Score coverage ≥ 80% | `engineeringScoreCoverage` | `greaterThanOrEqual` | engineering-score | `ScoreQualityGateTargetResolver` | `lib/quality_gate/quality_gate_target_registry.dart` | `quality_gate_integration_test.dart` (passing) | covered | — |
| QG007 | MES global ≥ 80 | `mesGlobalScore` | `greaterThanOrEqual` | mes-compliance | `MESQualityGateTargetResolver` | `lib/quality_gate/quality_gate_target_registry.dart` | `quality_gate_integration_test.dart` (cenário C) | covered | — |
| QG008 | MES eligible | `mesEligibility` | `equals` (`eligible`) | mes-compliance | `MESQualityGateTargetResolver` | `lib/quality_gate/quality_gate_target_registry.dart` | `quality_gate_integration_test.dart` (passing) | covered | — |
| QG009 | MES coverage ≥ 80% | `mesCoverage` | `greaterThanOrEqual` | mes-compliance | `MESQualityGateTargetResolver` | `lib/quality_gate/quality_gate_target_registry.dart` | `quality_gate_integration_test.dart` (passing) | covered | — |
| QG010 | MES compatible | `mesCompatibility` | `isCompatible` | mes-compliance | `MESQualityGateTargetResolver` | `lib/quality_gate/quality_gate_target_registry.dart` | `quality_gate_integration_test.dart` (passing) | covered | — |
| QG011 | Zero ciclos críticos | `criticalCycleCount` | `equals` (`0`) | architecture-risk | `MetricsQualityGateTargetResolver` | `lib/quality_gate/quality_gate_target_registry.dart` | `quality_gate_target_resolvers_test.dart`, `quality_gate_golden_test.dart` | **partiallyCovered** | Target retorna `unsupported` com `providerCapabilityGap`; ver `critical_cycle_mapping.md` |
| QG012 | Zero falhas de telemetria | `telemetryFailureCount` | `equals` (`0`) | operational-integrity | `TelemetryQualityGateTargetResolver` | `lib/quality_gate/quality_gate_target_registry.dart` | `quality_gate_integration_test.dart` (cenário D) | partiallyCovered | Regra optional; skip quando telemetria ausente |
| QG013 | Zero operações incompletas | `telemetryIncompleteOperationCount` | `equals` (`0`) | operational-integrity | `TelemetryQualityGateTargetResolver` | `lib/quality_gate/quality_gate_target_registry.dart` | `quality_gate_integration_test.dart` (cenário D) | partiallyCovered | Idem QG012 |
| QG014 | Telemetria compatible | `telemetryCompatibility` | `isCompatible` | operational-integrity | `TelemetryQualityGateTargetResolver` | `lib/quality_gate/quality_gate_target_registry.dart` | `quality_gate_integration_test.dart` (cenário D) | partiallyCovered | Idem QG012 |
| QG015 | Zero regressões estruturais | `historyRegressionCount` | `equals` (`0`) | historical-stability | `HistoryQualityGateTargetResolver` | `lib/quality_gate/quality_gate_target_registry.dart` | `quality_gate_target_resolvers_test.dart` | **partiallyCovered** | Valor **derivado** de `change.metadata['regression'] == 'true'`; sem campo autoritativo em `HistoryDiff` |

---

## 2. Targets (`QualityGateRuleTarget`)

### 2.1 Guardian

| Target | Resolver | Status | Teste |
|--------|----------|--------|-------|
| `guardianDecision` | Guardian | covered | integration |
| `guardianRiskLevel` | Guardian | partiallyCovered | sem teste dedicado |
| `guardianViolationCount` | Guardian | partiallyCovered | sem teste dedicado |
| `guardianCriticalViolationCount` | Guardian | partiallyCovered | integration indireta |
| `guardianWarningCount` | Guardian | partiallyCovered | sem teste dedicado |
| `guardianRuleStatus` | Guardian | partiallyCovered | requer `selector.guardianRuleId` |
| `guardianCompatibility` | Guardian | partiallyCovered | sem teste dedicado |

### 2.2 Metrics / Graph

| Target | Métrica / comportamento | Status | Observação |
|--------|----------------------|--------|------------|
| `metricValue` | `selector.metricId` | partiallyCovered | requer selector |
| `metricAvailability` | disponibilidade da métrica | partiallyCovered | — |
| `metricCoverage` | derivado de metadata | partiallyCovered | — |
| `cycleCount` | `graph.cycle.count` | partiallyCovered | métrica de ciclos totais |
| `criticalCycleCount` | — | **partiallyCovered** | retorna `unsupported`; gap documentado |
| `componentCount` | `graph.node.count` | partiallyCovered | — |
| `isolatedComponentCount` | `graph.component.isolated_count` | partiallyCovered | — |
| `dependencyCount` | `graph.edge.count` | partiallyCovered | — |
| `maximumFanIn` | `graph.degree.fan_in.max` | partiallyCovered | — |
| `maximumFanOut` | `graph.degree.fan_out.max` | partiallyCovered | — |
| `graphDensity` | `graph.density` | partiallyCovered | — |

### 2.3 Score

| Target | Status | Teste |
|--------|--------|-------|
| `engineeringScoreGlobal` | covered | integration |
| `engineeringScoreDimension` | partiallyCovered | requer `selector.dimensionId` |
| `engineeringScoreCoverage` | covered | integration |
| `engineeringScoreConfidence` | partiallyCovered | — |
| `engineeringScoreCompatibility` | partiallyCovered | — |
| `engineeringScoreEligibility` | partiallyCovered | — |

### 2.4 MES

| Target | Status | Teste |
|--------|--------|-------|
| `mesGlobalScore` | covered | integration |
| `mesBand` | partiallyCovered | — |
| `mesDimensionScore` | partiallyCovered | requer selector |
| `mesCoverage` | covered | integration |
| `mesConfidence` | partiallyCovered | — |
| `mesEligibility` | covered | integration |
| `mesCompatibility` | covered | integration |
| `mesPolicyId` | partiallyCovered | — |
| `mesPolicyVersion` | partiallyCovered | — |

### 2.5 History

| Target | Status | Observação |
|--------|--------|------------|
| `historyChangeCount` | partiallyCovered | requer History injetado |
| `historyAddedCount` | partiallyCovered | — |
| `historyRemovedCount` | partiallyCovered | — |
| `historyModifiedCount` | partiallyCovered | — |
| `historyRegressionCount` | **partiallyCovered** | derivado; ver QG015 |
| `historyArtifactCompatibility` | partiallyCovered | — |

### 2.6 Telemetry

| Target | Status | Teste |
|--------|--------|-------|
| `telemetryFailureCount` | partiallyCovered | integration (skip) |
| `telemetryIncompleteOperationCount` | partiallyCovered | integration (skip) |
| `telemetrySuccessRate` | partiallyCovered | — |
| `telemetryEventCoverage` | partiallyCovered | — |
| `telemetryTerminalCoverage` | partiallyCovered | — |
| `telemetryCompatibility` | partiallyCovered | integration (skip) |
| `telemetrySnapshotStatus` | partiallyCovered | — |

### 2.7 Dashboard

| Target | Status | Observação |
|--------|--------|------------|
| `dashboardStatus` | partiallyCovered | não usado na política v1 |
| `dashboardFreshness` | partiallyCovered | — |
| `dashboardCompatibility` | partiallyCovered | — |
| `dashboardWarningCount` | partiallyCovered | — |
| `dashboardErrorCount` | partiallyCovered | — |

### 2.8 Cross-artifact

| Target | Status | Teste |
|--------|--------|-------|
| `sourceProjectConsistency` | covered | integration |
| `sourceCommitConsistency` | partiallyCovered | — |
| `sourcePolicyConsistency` | partiallyCovered | — |
| `sourceSchemaCompatibility` | partiallyCovered | — |
| `sourceFreshness` | partiallyCovered | — |
| `requiredSourcesAvailable` | partiallyCovered | — |

---

## 3. Operadores (`QualityGateRuleOperator`)

| Operador | Implementação | Teste | Status |
|----------|---------------|-------|--------|
| `equals` | `QualityGateOperatorEvaluator` | `quality_gate_operator_evaluator_test.dart` | covered |
| `notEquals` | idem | — | partiallyCovered |
| `greaterThan` | idem | — | partiallyCovered |
| `greaterThanOrEqual` | idem | `quality_gate_operator_evaluator_test.dart` | covered |
| `lessThan` | idem | — | partiallyCovered |
| `lessThanOrEqual` | idem | — | partiallyCovered |
| `contains` | idem | — | partiallyCovered |
| `notContains` | idem | — | partiallyCovered |
| `containsAny` | idem | — | partiallyCovered |
| `containsAll` | idem | — | partiallyCovered |
| `isEmpty` | idem | — | partiallyCovered |
| `isNotEmpty` | idem | — | partiallyCovered |
| `isAvailable` | idem | — | partiallyCovered |
| `isUnavailable` | idem | — | partiallyCovered |
| `isCompatible` | idem | via regras QG010/QG014 | partiallyCovered |
| `isIncompatible` | idem | — | partiallyCovered |
| `isEligible` | idem | — | partiallyCovered |
| `isNotEligible` | idem | — | partiallyCovered |
| `betweenInclusive` | idem | — | partiallyCovered |
| `betweenExclusive` | idem | — | partiallyCovered |
| `outsideRange` | idem | — | partiallyCovered |
| `inSet` | idem | `quality_gate_operator_evaluator_test.dart` | covered |
| `notInSet` | idem | — | partiallyCovered |
| `exists` | idem | `quality_gate_operator_evaluator_test.dart` | covered |
| `doesNotExist` | idem | — | partiallyCovered |
| `isTrue` | idem | via QG001/QG002 | covered |
| `isFalse` | idem | — | partiallyCovered |

**Usados na política v1:** `isTrue`, `equals`, `greaterThanOrEqual`, `isCompatible` — todos `covered` no caminho de integração.

---

## 4. Missing data policies

| Policy | Handler | Status | Teste |
|--------|---------|--------|-------|
| `fail` | `QualityGateMissingDataHandler` | partiallyCovered | via rule evaluator |
| `partial` | idem | partiallyCovered | — |
| `unavailable` | idem | partiallyCovered | integration (score ausente) |
| `skip` | idem | partiallyCovered | integration (telemetria) |
| `notApplicable` | idem | partiallyCovered | QG002 |

---

## 5. Incompatible data policies

| Policy | Handler | Status | Teste |
|--------|---------|--------|-------|
| `fail` | `QualityGateIncompatibleDataHandler` | partiallyCovered | — |
| `partial` | idem | partiallyCovered | — |
| `incompatible` | idem | partiallyCovered | integration (projeto) |
| `skip` | idem | partiallyCovered | regras optional |

---

## 6. Decisões e status

### 6.1 `QualityGateDecision`

| Valor | Agregador | Status | Teste |
|-------|-----------|--------|-------|
| `passed` | `QualityGateDecisionAggregator` | covered | integration |
| `failed` | idem | covered | integration |
| `partial` | idem | partiallyCovered | integration (score ausente) |
| `unavailable` | idem | partiallyCovered | — |
| `incompatible` | idem | partiallyCovered | integration |
| `error` | idem | partiallyCovered | — |

### 6.2 `QualityGateResultStatus`

| Valor | Status | Observação |
|-------|--------|------------|
| `success` | covered | Gate `passed`/`failed` não é falha operacional |
| `partial` | partiallyCovered | — |
| `unavailable` | partiallyCovered | — |
| `incompatible` | partiallyCovered | — |
| `failure` | partiallyCovered | Erro de engine/validação |

### 6.3 `QualityGateRuleStatus`

Todos os valores (`passed`, `failed`, `unavailable`, `incompatible`, `skipped`, `notApplicable`, `error`) são produzidos pelo `QualityGateRuleEvaluator` — **partiallyCovered** (sem matriz exaustiva por status).

### 6.4 `QualityGateRuleSetAggregationMode`

| Modo | Status | Observação |
|------|--------|------------|
| `all` | covered | Usado em todos os rule sets v1 |
| `any` | partiallyCovered | implementado, não usado na v1 |
| `minimumCount` | partiallyCovered | — |
| `minimumPercentage` | partiallyCovered | — |

---

## 7. Source resolution

| Modo | Resolver | Status | Teste |
|------|----------|--------|-------|
| `injected` | `QualityGateSourceResolver` | covered | `quality_gate_source_resolver_test.dart` |
| `byId` | idem | covered | source resolver test |
| `latest` | idem | covered | opt-in via `useLatest: true` |
| `unavailable` | idem | covered | source resolver test |
| `incompatible` | idem | partiallyCovered | — |

**Princípio:** nenhum engine de origem (Metrics, Score, MES, Guardian, etc.) é recalculado — **covered** (`quality_gate_source_resolver_test.dart` com fakes que falham se engines forem invocados).

---

## 8. Identidade e fingerprints

| Requisito | Componente | Arquivo | Status | Teste |
|-----------|------------|---------|--------|-------|
| Snapshot ID determinístico | `QualityGateIdentityBuilder` | `lib/quality_gate/quality_gate_identity_builder.dart` | covered | integration (deterministic id) |
| Policy fingerprint | `QualityGateCanonicalSerializer` | `lib/quality_gate/quality_gate_canonical_serializer.dart` | covered | models test |
| Request fingerprint | idem | idem | partiallyCovered | — |
| Source set fingerprint | idem | idem | partiallyCovered | source resolver (ordem) |
| Quality gate fingerprint | idem | idem | covered | integration |
| `toComparableJson` exclui timestamps | `QualityGateSnapshot` | `lib/models/quality_gate/quality_gate_snapshot.dart` | covered | models test |

---

## 9. Provider e store

| Requisito | Componente | Arquivo | Status | Teste |
|-----------|------------|---------|--------|-------|
| `evaluate` sem publicar | `PlatformQualityGateProvider` | `lib/providers/platform_quality_gate_provider.dart` | covered | integration |
| `evaluateAndPublish` idempotente | idem | idem | covered | integration |
| `publish` manual | idem | idem | partiallyCovered | — |
| `load` / `latest` / `query` | idem + store | idem | partiallyCovered | store test |
| `invalidate` | idem | idem | partiallyCovered | — |
| Store idempotente | `InMemoryQualityGateStore` | `lib/quality_gate/stores/in_memory_quality_gate_store.dart` | covered | store test |
| Conflito de fingerprint | idem | idem | partiallyCovered | — |
| Bootstrap / DI | `QualityGatePlatformBootstrap` | `lib/quality_gate/quality_gate_platform_bootstrap.dart` | covered | integration (PlatformCore) |

---

## 10. Integrações

| Integração | Componente | Arquivo | Status | Observação |
|------------|------------|---------|--------|------------|
| Report | `QualityGateReportSource` | `lib/report/sources/quality_gate_report_source.dart` | covered | `quality_gate_report_test.dart` |
| History | `QualityGateHistoryMapper` | `lib/history/mappers/quality_gate_history_mapper.dart` | covered | `quality_gate_history_integration_test.dart` |
| Dashboard | `QualityGateSectionBuilder` | `lib/dashboard/builders/quality_gate_section_builder.dart` | covered | `quality_gate_dashboard_integration_test.dart` |
| Observability | `ObservableQualityGateProvider` | `lib/observability/instrumentation/observable_quality_gate_provider.dart` | partiallyCovered | decorator transparente; sem teste dedicado |

---

## 11. Engine e precedência

| Componente | Arquivo | Status | Observação |
|------------|---------|--------|------------|
| Engine stateless | `quality_gate_engine.dart` | covered | sem estado mutável |
| Rule evaluator | `quality_gate_rule_evaluator.dart` | covered | — |
| Rule set evaluator | `quality_gate_rule_set_evaluator.dart` | partiallyCovered | — |
| Compatibility checker | `quality_gate_compatibility_checker.dart` | partiallyCovered | — |
| Eligibility evaluator | `quality_gate_eligibility_evaluator.dart` | partiallyCovered | — |
| Coverage calculator | `quality_gate_coverage_calculator.dart` | partiallyCovered | — |
| Decision aggregator | `quality_gate_decision_aggregator.dart` | covered | `quality_gate_decision_precedence_test.dart` |
| Decision impact resolver | `quality_gate_handlers.dart` | partiallyCovered | — |

---

## 12. Itens críticos — resumo

| Item | Status | Ação |
|------|--------|------|
| QG011 `criticalCycleCount` | partiallyCovered | Documentado em `critical_cycle_mapping.md`; target `unsupported` |
| QG015 `historyRegressionCount` | partiallyCovered | Derivado; limitation `history.regressionCount.derived` |
| Nenhum item crítico `notCovered` | — | Todos os requisitos críticos têm implementação ou limitação explícita |

---

## 13. Lacunas de teste conhecidas (pós Part 3)

**Estado validado:** `dart test test/quality_gate/` — **108 testes verdes** (2026-07-21).

### Concluído na Part 3

- Source resolver isolado (`quality_gate_source_resolver_test.dart`)
- Target resolvers consolidados (`quality_gate_target_resolvers_test.dart`)
- Handlers e impact resolver (`quality_gate_handlers_test.dart`)
- Precedência (`quality_gate_decision_precedence_test.dart`)
- Replay e identidade (`quality_gate_replay_test.dart`)
- Golden normativo QG011 (`test/golden/quality_gate/error_qg011_capability_gap.json`)
- History integration (`quality_gate_history_integration_test.dart`)
- Dashboard integration (`quality_gate_dashboard_integration_test.dart`)
- Report por decisão (`quality_gate_report_test.dart`)
- Policy versioning (`quality_gate_policy_versioning_test.dart`)
- PlatformCore (`quality_gate_platform_core_test.dart`)
- Security básico (`quality_gate_security_test.dart`)

### Débito residual (Sprint 04.2)

- 8 ficheiros de target por domínio (spec original) — cobertos por suite consolidada
- Matriz exaustiva de handlers (todas combinações requirement × severity × policy)
- Operadores exaustivos (todos os 27 com todos os edge cases)
- Store/provider avançados (paginação, concorrência, telemetry sink)
- Observability hardening dedicado
- Stress test (~500 regras) e performance baseline
- Property-based e mutation-oriented tests
- Exemplos em `example/quality_gate/` ainda referenciam helpers de `test/`

Estes itens não invalidam a arquitetura; limitações QG011/QG015 permanecem as condições principais para **GO WITH CONDITIONS**.
