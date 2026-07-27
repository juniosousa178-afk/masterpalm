# CI/CD Integration — Release Checklist (Sprint 05.1)

**Sprint:** 05.1 — CI/CD Integration Operational Architecture and Hardening
**Políticas:** `pipeline-integration-v1`, `pipeline-execution-v1`, `deployment-integration-v1` (candidate)
**Última atualização:** 2026-07-22

Use este checklist antes de declarar a sprint concluída ou promover políticas candidate.

**Baseline Parts 1–2:** 87 testes em `test/cicd_integration/` (verificado antes da Parte 3).
**Após Parte 3:** 215 testes em `test/cicd_integration/`, 1414 na suite completa.

---

## Analyze

- [ ] `dart analyze lib` sem issues
- [ ] Nenhum warning novo em `lib/cicd_integration/`
- [ ] Nenhum contrato público alterado na Parte 3

**Evidência:** `dart analyze lib`

---

## Testes

- [x] Suite `test/cicd_integration/` verde (215 testes após Parte 3)
- [ ] Parte 1 (models/validators/serialization): testes base
- [ ] Parte 2 (operacional): provider, resolver, collector, integração
- [ ] Parte 3 (hardening): replay, golden, audits, stress, performance

**Evidência:** `dart test test/cicd_integration/`

---

## Replay

- [ ] Snapshot fingerprint idêntico em re-evaluate
- [ ] Fingerprints de pipeline, execução, resultado, plano e deployment idênticos
- [ ] JSON round-trip preserva identidade

**Evidência:** `cicd_integration_replay_test.dart`

---

## Golden Snapshots

- [ ] `passing_snapshot.json` — snapshot canônico
- [ ] `pipeline_definition.json` — definição de pipeline
- [ ] `pipeline_execution.json` — execução e resultado
- [ ] `deployment_plan.json` — plano de deployment
- [ ] `deployment_result.json` — resultado de deployment
- [ ] Fingerprints estáveis entre execuções

**Evidência:** `cicd_integration_golden_test.dart`, `test/golden/cicd_integration/`

---

## Serialização

- [ ] toJson/fromJson roundtrip em todos os modelos auditados
- [ ] Enums com wire name (incl. `PipelineProviderType` descritor)
- [ ] Timestamps UTC
- [ ] Políticas roundtrip via json

**Evidência:** `pipeline_serialization_test.dart`, `cicd_integration_serialization_audit_test.dart`

---

## Identidade

- [ ] Apenas campos normativos em fingerprints de snapshot
- [ ] Fingerprints de componentes excluem campos transitórios
- [ ] Mutação de campo normativo altera fingerprint

**Evidência:** `cicd_integration_identity_audit_test.dart`, `cicd_integration_mutation_test.dart`

---

## Provider Hardening

- [ ] evaluate idempotente (5 repetições)
- [ ] evaluateAndPublish idempotente no segundo publish
- [ ] publish direct idempotente
- [ ] latest retorna snapshot mais recente
- [ ] query filtra por projectId
- [ ] invalidate remove do load

**Evidência:** `cicd_integration_hardening_test.dart`

---

## Store Hardening

- [ ] save idempotente para mesmo fingerprint
- [ ] conflito em snapshot divergente com mesmo id
- [ ] clear remove todos
- [ ] query com limit e offset

**Evidência:** `cicd_integration_hardening_test.dart`

---

## Source Resolver

- [ ] injected vence byId e latest
- [ ] byId resolve quando injected ausente (artifact registry)
- [ ] latest apenas com useLatest: true
- [ ] missing byId não faz fallback implícito para latest
- [ ] nunca chama evaluate em Release Evidence ou Release Supply Chain
- [ ] projectId mismatch em evidence gera limitation

**Evidência:** `cicd_integration_source_resolver_audit_test.dart`, `cicd_integration_integration_test.dart`

---

## Collector

- [ ] dedup por artifactId
- [ ] steps e targets deduplicados
- [ ] fontes ausentes não produzem artefatos
- [ ] fingerprints de origem preservados (sem recálculo indevido)

**Evidência:** `cicd_integration_collector_audit_test.dart`

---

## Engine / Builders

- [ ] ordering determinístico de stages e artefatos
- [ ] builders não mutam artefatos de origem
- [ ] snapshot builder monta todos os componentes
- [ ] engine nunca executa pipeline
- [ ] mensagens ordenadas por messageId

**Evidência:** `cicd_integration_engine_audit_test.dart`

---

## Deployment Approval (estrutural)

- [ ] `DeploymentApprovalStatus.approved` não autoriza release
- [ ] políticas contêm `no-pipeline-execution` e `no-remote-deployment`
- [ ] snapshot inclui limitações estruturais explícitas
- [ ] engine valida estratégias permitidas sem invocar deployment real

**Evidência:** `cicd_integration_engine_audit_test.dart`, `cicd_integration_integration_test.dart`

---

## PipelineProviderType (descritor)

- [ ] enum serializa/deserializa correctamente
- [ ] nenhum adapter externo invocado por providerType
- [ ] limitação `no-remote-provider-fetch` presente na política integration

**Evidência:** `pipeline_serialization_test.dart`, `cicd_integration_integration_test.dart`

---

## Observability

- [ ] todas as operações emitem telemetry cicdIntegration
- [ ] observability não altera payload de evaluate
- [ ] eventos incluem duration

**Evidência:** `cicd_integration_observability_audit_test.dart`

---

## Integração

- [ ] Report gera secções a partir de snapshot (`ReportType.cicdIntegration`)
- [ ] History mapper determinístico
- [ ] History comparator sem mudanças para snapshots equivalentes
- [ ] Dashboard renderiza cicdPipeline, cicdExecution e cicdDeployment

**Evidência:** `cicd_integration_integration_test.dart`, `cicd_integration_integration_audit_test.dart`

---

## Property / Mutation / Stress / Performance

- [ ] property tests de ordering e fingerprint
- [ ] mutation tests rejeitam mutações inválidas
- [ ] stress em coleções grandes de artefatos
- [ ] performance baselines dentro de thresholds

**Evidência:** `cicd_integration_property_test.dart`, `cicd_integration_mutation_test.dart`, `cicd_integration_stress_test.dart`, `cicd_integration_performance_test.dart`

---

## Security

- [ ] sentinel strings ausentes em JSON e fingerprints
- [ ] placeholders SHA-256 não implicam crypto
- [ ] limitação no-cryptographic-verification presente
- [ ] telemetry sanitizer redige secrets

**Evidência:** `cicd_integration_security_test.dart`

---

## Public API

- [ ] Provider, Store, Bootstrap exportados em masterpalm_platform
- [ ] Modelos operacionais exportados
- [ ] Nenhuma alteração de contrato na Parte 3

**Evidência:** `cicd_integration_public_api_test.dart`

---

## Documentação

- [ ] `docs/cicd_integration/README.md`
- [ ] `docs/adr/ADR-031-cicd-integration-operational-architecture-and-hardening.md`
- [ ] `docs/architecture-reviews/AR-017-cicd-integration-framework.md`
- [ ] Este checklist preenchido

---

## Decisão

| Resultado | Condição |
|-----------|----------|
| **GO WITH CONDITIONS** | Beta 5.1 — políticas candidate, store in-memory, sem adapters externos |
| **GO** | Todas as condições da AR-017 secção 8 cumpridas |
| **NO-GO** | Falha em replay, resolver chama evaluate upstream, ou execução CI/CD real introduzida |

**Decisão atual:** GO WITH CONDITIONS (ver AR-017)
