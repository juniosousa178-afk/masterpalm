# Architecture Review #017 — CI/CD Integration Framework

| Campo | Valor |
|-------|-------|
| **ID** | AR-017 |
| **Título** | CI/CD Integration Operational Architecture and Hardening |
| **Sprint** | 05.1 Part 3 (Hardening) |
| **Data** | 2026-07-22 |
| **Revisor** | MasterPalm Engineering Governance |
| **ADR relacionado** | ADR-031 |
| **Políticas** | `pipeline-integration-v1`, `pipeline-execution-v1`, `deployment-integration-v1` (candidate) |

---

## 1. Executive Summary

A Sprint 05.1 entrega a fundação de CI/CD Integration na MasterPalm Engineering Platform: pipeline determinístico que consolida definições de pipeline, execuções declaradas, planos e resultados de deployment, linkages com `ReleaseEvidenceBundle` e `ReleaseSupplyChainSnapshot` publicados, e integração com Report/History/Dashboard/Observability.

**Parts 1–2** entregaram models imutáveis, validators, serialização, resolver, collector, builders, engine, provider, store in-memory e integrações — com **87 testes** verdes em `test/cicd_integration/`.

A **Parte 3** (hardening) adicionou replay (100 ciclos), 8 golden snapshots, auditorias de serialização/identidade/resolver/collector/engine, property/mutation/stress/performance/security, integrações cross-module e observability — **215 testes** em `test/cicd_integration/` e **1414** na suite completa, **sem alterar contratos públicos nem engines existentes**.

Condições que impedem GO pleno:

1. **Políticas candidate** — três políticas não promovidas a `active`
2. **Store in-memory** — sem persistência física entre processos
3. **Sem adapters externos** — `PipelineProviderType` é descritor apenas
4. **Sem execução CI/CD** — pipelines nunca executados
5. **Approval estrutural ≠ autorização** — consumidores não devem confundir `DeploymentApprovalStatus.approved` com release autorizada

**Decisão:** **GO WITH CONDITIONS — Release 5.1 Beta**

---

## 2. Scope Reviewed

| Área | Incluído |
|------|----------|
| Domínio imutável (models cicd_integration) | Sim |
| Pipeline operacional (resolver, collector, builders, engine) | Sim |
| Provider e store in-memory | Sim |
| Artifact registry in-memory | Sim |
| Bootstrap e PlatformCore | Sim |
| Integrações Report, History, Dashboard, Observability | Sim |
| Políticas candidate v1 (3) | Sim |
| Hardening Part 3 | Sim (documentação + testes planeados) |
| Testes `test/cicd_integration/` | Sim (87 baseline + Parte 3) |
| Golden snapshots | Planeado (Parte 3) |
| Documentação Sprint 05.1 | Sim |

**Fora de escopo:** execução CI/CD real, adapters externos (GitHub Actions, GitLab CI, Jenkins), persistência física, assinatura criptográfica, promoção candidate→active.

---

## 3. Architecture Baseline

CI/CD Integration adere ao padrão estabelecido por Quality Gate, Release Governance, Release Evidence e Release Supply Chain:

- **Models** — tipos imutáveis (`lib/models/cicd_integration/*`)
- **Engines/Builders** — lógica pura, sem IO (`PipelineSnapshotBuilder`, `CicdIntegrationEngine`, etc.)
- **Provider** — orquestração (`PlatformCicdIntegrationProvider`)
- **Bootstrap** — composition root (`CicdIntegrationPlatformBootstrap`)

Dependências upstream: `ReleaseEvidenceProvider`, `ReleaseSupplyChainProvider` — apenas leitura.

`PipelineProviderType` existe exclusivamente como enum descritivo em `pipeline_enums.dart` — nenhum código invoca providers externos com base neste tipo.

---

## 4. Conformidade Arquitetural

| Princípio | Conformidade | Evidência |
|-----------|--------------|-----------|
| Single responsibility | Conforme | Pipeline em etapas isoladas |
| Immutability | Conforme | Models com listas defensivas |
| Determinism | Conforme | `cicd_integration_provider_test.dart` (fingerprint) |
| Consume, don't recalculate | Conforme | `cicd_integration_integration_test.dart` (fake upstream) |
| No silent coercion | Conforme | Ausência → limitation; incompatível explícito |
| Policy versioning | Conforme | 3 registries com freeze |
| Integration without recursion | Conforme | Report/Dashboard/History não chamam pipeline |
| No CI/CD execution | Conforme | Limitações em políticas + snapshot builder |
| ProviderType descriptor only | Conforme | Sem adapters; `no-remote-provider-fetch` |
| Approval ≠ authorization | Conforme | Limitações `no-pipeline-execution`, `no-remote-deployment` |

---

## 5. Replay e Determinismo

| Artefato | Fingerprint estável | Evidência |
|----------|---------------------|-----------|
| Snapshot | `snapshot.fingerprint` | provider test + replay (Parte 3) |
| Pipeline | `metadata.pipelineFingerprint` | replay + golden |
| Execução | `metadata.executionFingerprint` | replay + golden |
| Resultado execução | `metadata.executionResultFingerprint` | replay + golden |
| Plano deployment | `metadata.deploymentPlanFingerprint` | replay + golden |
| Resultado deployment | `metadata.deploymentResultFingerprint` | replay + golden |

Campos transitórios (`cicdIntegrationSnapshotId`, `createdAt`, `evaluatedAt`) excluídos de fingerprints normativos — validado em `cicd_integration_identity_audit_test.dart` (Parte 3).

---

## 6. Hardening Part 3 — Cobertura

| Etapa | Área | Ficheiro |
|-------|------|----------|
| Replay | Determinismo end-to-end | `cicd_integration_replay_test.dart` |
| Golden | 5 snapshots canônicos | `cicd_integration_golden_test.dart` |
| Serialização | Roundtrip modelos | `cicd_integration_serialization_audit_test.dart` |
| Identidade | Campos normativos vs transitórios | `cicd_integration_identity_audit_test.dart` |
| Provider/Store | Idempotência, query, invalidate | `cicd_integration_hardening_test.dart` |
| Resolver | Fake providers, sem evaluate upstream | `cicd_integration_source_resolver_audit_test.dart` |
| Collector | Dedup, sem recálculo de fingerprint | `cicd_integration_collector_audit_test.dart` |
| Engine | Ordering, sem execução CI/CD | `cicd_integration_engine_audit_test.dart` |
| Observability | Telemetry cicdIntegration | `cicd_integration_observability_audit_test.dart` |
| Integração | Report, History, Dashboard | `cicd_integration_integration_audit_test.dart` |
| Property | Ordering/fingerprint invariantes | `cicd_integration_property_test.dart` |
| Mutation | Validators rejeitam mutações | `cicd_integration_mutation_test.dart` |
| Stress | Coleções grandes de artefatos | `cicd_integration_stress_test.dart` |
| Performance | Baselines generosos | `cicd_integration_performance_test.dart` |
| Security | Sem crypto assumida, sentinel strings | `cicd_integration_security_test.dart` |
| Public API | Exports masterpalm_platform | `cicd_integration_public_api_test.dart` |

**Baseline Parts 1–2 (implementado):**

| Área | Ficheiro | Testes |
|------|----------|--------|
| Models | `pipeline_models_test.dart` | Parte 1 |
| Validators | `pipeline_validators_test.dart` | Parte 1 |
| Serialização | `pipeline_serialization_test.dart` | Parte 1 |
| Operacional | `cicd_integration_operational_test.dart` | Parte 2 |
| Provider | `cicd_integration_provider_test.dart` | Parte 2 |
| Integração E2E | `cicd_integration_integration_test.dart` | Parte 2 |

Total verificado: **87 testes** antes da Parte 3.

---

## 7. Riscos Residuais

| Risco | Severidade | Mitigação |
|-------|------------|-----------|
| Confusão approval vs autorização de release | Alta | Documentação + limitações em políticas + testes |
| Expectativa de execução CI/CD real | Alta | Limitação `no-pipeline-execution` + ADR/README |
| Store in-memory | Média | AR futuro para persistência |
| Políticas candidate | Média | Promoção formal após validação em produção |
| Sem verificação criptográfica | Média | Limitação documentada + placeholders explícitos |
| ProviderType mal interpretado como integração | Média | Documentação explícita + `no-remote-provider-fetch` |
| Performance em pipelines grandes | Baixa | Stress test + baseline (Parte 3) |

---

## 8. Condições para GO Pleno

1. Promover políticas `pipeline-integration-v1`, `pipeline-execution-v1`, `deployment-integration-v1` a `active`
2. Implementar store persistente com backup e CAS
3. Implementar adapters opt-in para providers CI/CD (se necessário)
4. Validar integração com pipeline CI/CD real (enforcement externo)
5. Documentar runbook de troubleshooting em produção
6. Revisão de segurança para verificação criptográfica (se necessário)

---

## 9. Decisão Final

**GO WITH CONDITIONS — Release 5.1 Beta**

A fundação CI/CD Integration está arquiteturalmente sólida, deterministicamente reproduzível (87 testes baseline) e adequadamente documentada para beta controlado. O domínio opera exclusivamente em modo estrutural — sem execução CI/CD, sem adapters externos, com approval de deployment que não autoriza release.

Promoção a produção plena requer cumprimento das condições da secção 8.

---

## Referências

- ADR-031 — CI/CD Integration Operational Architecture and Hardening
- `docs/cicd_integration/README.md`
- `docs/cicd_integration/cicd_integration_release_checklist.md`
- ADR-030 — Release Supply Chain Foundation
