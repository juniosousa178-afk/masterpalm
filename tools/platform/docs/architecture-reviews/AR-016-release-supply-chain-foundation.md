# Architecture Review #016 — Release Supply Chain Foundation

| Campo | Valor |
|-------|-------|
| **ID** | AR-016 |
| **Título** | Release Supply Chain and Provenance Framework |
| **Sprint** | 05.0 Part 3 (Hardening) |
| **Data** | 2026-07-22 |
| **Revisor** | MasterPalm Engineering Governance |
| **ADR relacionado** | ADR-030 |
| **Políticas** | `supply-chain-v1`, `distribution-v1`, `compliance-v1` (candidate) |

---

## 1. Executive Summary

A Sprint 05.0 entrega a fundação de Release Supply Chain na MasterPalm Engineering Platform: pipeline determinístico que consolida `QualityGateSnapshot`, `ReleaseDecisionSnapshot` e `ReleaseEvidenceBundle` publicados, monta provenance, grafo, SBOM, registo de artefatos, distribuição e compliance estrutural, e integra Report/History/Dashboard/Observability.

A Parte 3 (hardening) validou replay, golden snapshots, serialização, identidade, provider/store, collector, engines, compliance, observability, report, history, dashboard, property-based tests, mutation tests, stress tests e baseline de performance — **sem alterar contratos públicos nem engines existentes**.

Condições que impedem GO pleno:

1. **Políticas candidate** — três políticas não promovidas a `active`
2. **Store in-memory** — sem persistência física entre processos
3. **Sem autenticação criptográfica** — digests validados estruturalmente apenas
4. **Compliance ≠ autorização** — consumidores devem não confundir `compliant` com release autorizada
5. **Sem integração CI/CD** — enforcement manual

**Decisão:** **GO WITH CONDITIONS — Release 5.0 Beta**

---

## 2. Scope Reviewed

| Área | Incluído |
|------|----------|
| Domínio imutável (models release_supply_chain) | Sim |
| Pipeline operacional (resolver, collector, builders, compliance) | Sim |
| Provider e store in-memory | Sim |
| Bootstrap e PlatformCore | Sim |
| Integrações Report, History, Dashboard, Observability | Sim |
| Políticas candidate v1 (3) | Sim |
| Hardening Part 3 | Sim |
| Testes `test/release_supply_chain/` | Sim |
| Golden snapshots | Sim |
| Documentação Sprint 05.0 | Sim |

**Fora de escopo:** CI/CD enforcement, persistência física, assinatura criptográfica, promoção candidate→active.

---

## 3. Architecture Baseline

Release Supply Chain adere ao padrão estabelecido por Quality Gate, Release Governance e Release Evidence:

- **Models** — tipos imutáveis (`lib/models/release_supply_chain/*`)
- **Engines/Builders** — lógica pura, sem IO (`SupplyChainGraphBuilder`, `SbomBuilder`, `ComplianceEngine`, etc.)
- **Provider** — orquestração (`PlatformReleaseSupplyChainProvider`)
- **Bootstrap** — composition root (`ReleaseSupplyChainPlatformBootstrap`)

Dependências upstream: `QualityGateProvider`, `ReleaseGovernanceProvider`, `ReleaseEvidenceProvider` — apenas leitura.

---

## 4. Conformidade Arquitetural

| Princípio | Conformidade | Evidência |
|-----------|--------------|-----------|
| Single responsibility | Conforme | Pipeline em etapas isoladas |
| Immutability | Conforme | Models com listas defensivas |
| Determinism | Conforme | `release_supply_chain_replay_test.dart`, goldens |
| Consume, don't recalculate | Conforme | `release_supply_chain_source_resolver_audit_test.dart` |
| No silent coercion | Conforme | Ausência ≠ sucesso; incompatível explícito |
| Policy versioning | Conforme | 3 registries com freeze |
| Integration without recursion | Conforme | Report/Dashboard/History não chamam pipeline |
| Compliance ≠ authorization | Conforme | `release_supply_chain_compliance_audit_test.dart` |

---

## 5. Replay e Determinismo

| Artefato | Fingerprint estável | Evidência |
|----------|---------------------|-----------|
| Snapshot | `snapshot.fingerprint` | replay + golden |
| Grafo | `metadata.graphFingerprint` | replay + golden |
| SBOM | `metadata.sbomFingerprint` | replay + golden |
| Registo | `metadata.registryFingerprint` | replay + golden |
| Distribuição | `metadata.distributionFingerprint` | replay + golden |
| Compliance | `metadata.complianceFingerprint` | replay + golden |

Campos transitórios (`supplyChainSnapshotId`, `createdAt`, `evaluatedAt`) excluídos de fingerprints normativos — validado em `release_supply_chain_identity_audit_test.dart`.

---

## 6. Hardening Part 3 — Cobertura

| Etapa | Área | Ficheiro |
|-------|------|----------|
| Replay | Determinismo end-to-end | `release_supply_chain_replay_test.dart` |
| Golden | 6 snapshots canônicos | `release_supply_chain_golden_test.dart` |
| Serialização | Roundtrip modelos | `release_supply_chain_serialization_audit_test.dart` |
| Identidade | Campos normativos vs transitórios | `release_supply_chain_identity_audit_test.dart` |
| Provider/Store | Idempotência, query, invalidate | `release_supply_chain_hardening_test.dart` |
| Resolver | Fake providers, sem evaluate | `release_supply_chain_source_resolver_audit_test.dart` |
| Collector | Dedup, sem recálculo de fingerprint | `release_supply_chain_collector_audit_test.dart` |
| Engines | Ordering, sem mutação de fontes | `release_supply_chain_engine_audit_test.dart` |
| Compliance | projectId, fingerprints, sem autorização | `release_supply_chain_compliance_audit_test.dart` |
| Observability | Telemetry releaseSupplyChain | `release_supply_chain_observability_audit_test.dart` |
| Integração | Report, History, Dashboard | `release_supply_chain_integration_audit_test.dart` |
| Property | Ordering/fingerprint invariantes | `release_supply_chain_property_test.dart` |
| Mutation | Validators rejeitam mutações | `release_supply_chain_mutation_test.dart` |
| Stress | 1000 nodes/components | `release_supply_chain_stress_test.dart` |
| Performance | Baselines generosos | `release_supply_chain_performance_test.dart` |
| Security | Sem crypto assumida, sentinel strings | `release_supply_chain_security_test.dart` |
| Public API | Exports masterpalm_platform | `release_supply_chain_public_api_test.dart` |

---

## 7. Riscos Residuais

| Risco | Severidade | Mitigação |
|-------|------------|-----------|
| Confusão compliance vs autorização | Alta | Documentação + limitação na política + testes |
| Store in-memory | Média | AR futuro para persistência |
| Políticas candidate | Média | Promoção formal após validação em produção |
| Sem verificação criptográfica | Média | Limitação documentada + placeholders explícitos |
| Performance em grafos grandes | Baixa | Stress test 1000 nodes + baseline |

---

## 8. Condições para GO Pleno

1. Promover políticas `supply-chain-v1`, `distribution-v1`, `compliance-v1` a `active`
2. Implementar store persistente com backup e CAS
3. Validar integração CI/CD com pipeline real
4. Documentar runbook de troubleshooting em produção
5. Revisão de segurança para verificação criptográfica (se necessário)

---

## 9. Decisão Final

**GO WITH CONDITIONS — Release 5.0 Beta**

A fundação Release Supply Chain está arquiteturalmente sólida, deterministicamente reproduzível e adequadamente testada para beta controlado. Promoção a produção plena requer cumprimento das condições da secção 8.

---

## Referências

- ADR-030 — Release Supply Chain and Provenance Framework
- `docs/release_supply_chain/README.md`
- `docs/release_supply_chain/release_supply_chain_release_checklist.md`
- ADR-029 — Release Evidence Foundation
