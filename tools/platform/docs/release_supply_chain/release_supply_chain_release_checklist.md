# Release Supply Chain — Release Checklist (Sprint 05.0)

**Sprint:** 05.0 — Release Supply Chain and Provenance Framework
**Políticas:** `supply-chain-v1`, `distribution-v1`, `compliance-v1` (candidate)
**Última atualização:** 2026-07-22

Use este checklist antes de declarar a sprint concluída ou promover políticas candidate.

---

## Analyze

- [ ] `dart analyze lib` sem issues
- [ ] Nenhum warning novo em `lib/release_supply_chain/`
- [ ] Nenhum contrato público alterado na Parte 3

**Evidência:** `dart analyze lib`

---

## Testes

- [ ] Suite `test/release_supply_chain/` verde
- [ ] Parte 1 (models/validators): testes base
- [ ] Parte 2 (operacional): provider, engines, integração
- [ ] Parte 3 (hardening): replay, golden, audits, stress, performance

**Evidência:** `dart test test/release_supply_chain/`

---

## Replay

- [ ] Snapshot fingerprint idêntico em re-evaluate
- [ ] Fingerprints de grafo, SBOM, registo, distribuição e compliance idênticos
- [ ] JSON round-trip preserva identidade

**Evidência:** `release_supply_chain_replay_test.dart`

---

## Golden Snapshots

- [ ] `passing_snapshot.json` — snapshot canônico
- [ ] `supply_chain_graph.json` — grafo de supply chain
- [ ] `sbom.json` — software bill of materials
- [ ] `artifact_registry.json` — registo de artefatos
- [ ] `distribution.json` — distribuição
- [ ] `compliance.json` — resultado de compliance
- [ ] Fingerprints estáveis entre execuções

**Evidência:** `release_supply_chain_golden_test.dart`, `test/golden/release_supply_chain/`

---

## Serialização (Etapa 85)

- [ ] toJson/fromJson roundtrip em todos os modelos auditados
- [ ] Enums com unknown wire name
- [ ] Timestamps UTC
- [ ] Políticas roundtrip via json

**Evidência:** `release_supply_chain_serialization_audit_test.dart`

---

## Identidade

- [ ] Apenas campos normativos em fingerprints de snapshot
- [ ] Fingerprints de componentes excluem campos transitórios
- [ ] Mutação de campo normativo altera fingerprint

**Evidência:** `release_supply_chain_identity_audit_test.dart`, `release_supply_chain_mutation_test.dart`

---

## Provider Hardening

- [ ] evaluate idempotente (5 repetições)
- [ ] evaluateAndPublish idempotente no segundo publish
- [ ] publish direct idempotente
- [ ] latest retorna snapshot mais recente
- [ ] query filtra por projectId
- [ ] invalidate remove do load

**Evidência:** `release_supply_chain_hardening_test.dart`

---

## Store Hardening

- [ ] save idempotente para mesmo fingerprint
- [ ] clear remove todos
- [ ] saves concorrentes serializados
- [ ] query com limit e offset

**Evidência:** `release_supply_chain_hardening_test.dart`

---

## Source Resolver

- [ ] injected vence byId e latest
- [ ] byId resolve quando injected ausente
- [ ] latest apenas com useLatest: true
- [ ] missing byId não faz fallback implícito para latest
- [ ] nunca chama evaluate em origem

**Evidência:** `release_supply_chain_source_resolver_audit_test.dart`

---

## Collector

- [ ] dedup por artifactId
- [ ] sem duplicação de fingerprint QG
- [ ] fontes ausentes não produzem artefatos
- [ ] fingerprints de origem preservados (sem recálculo)

**Evidência:** `release_supply_chain_collector_audit_test.dart`

---

## Engines / Builders

- [ ] ordering determinístico de stages
- [ ] builders não mutam artefatos de origem
- [ ] snapshot builder monta todos os componentes

**Evidência:** `release_supply_chain_engine_audit_test.dart`

---

## Compliance

- [ ] projectId inconsistente gera limitation
- [ ] fingerprints ausentes falham validação
- [ ] compliance nunca autoriza release
- [ ] política contém `never-approves-release`

**Evidência:** `release_supply_chain_compliance_audit_test.dart`

---

## Observability

- [ ] todas as operações emitem telemetry releaseSupplyChain
- [ ] observability não altera payload de evaluate
- [ ] eventos incluem duration

**Evidência:** `release_supply_chain_observability_audit_test.dart`

---

## Integração

- [ ] Report gera secções a partir de snapshot
- [ ] History mapper determinístico
- [ ] History comparator sem mudanças para snapshots equivalentes
- [ ] Dashboard renderiza supplyChain, sbom e compliance

**Evidência:** `release_supply_chain_integration_audit_test.dart`

---

## Property / Mutation / Stress / Performance

- [ ] property tests de ordering e fingerprint
- [ ] mutation tests rejeitam mutações inválidas
- [ ] stress 1000 nodes/components
- [ ] performance baselines dentro de thresholds

**Evidência:** `release_supply_chain_property_test.dart`, `release_supply_chain_mutation_test.dart`, `release_supply_chain_stress_test.dart`, `release_supply_chain_performance_test.dart`

---

## Security

- [ ] sentinel strings ausentes em JSON e fingerprints
- [ ] placeholders SHA-256 não implicam crypto
- [ ] limitação no-cryptographic-verification presente
- [ ] telemetry sanitizer redige secrets

**Evidência:** `release_supply_chain_security_test.dart`

---

## Public API

- [ ] Provider, Store, Bootstrap exportados em masterpalm_platform
- [ ] Modelos operacionais exportados
- [ ] Nenhuma alteração de contrato na Parte 3

**Evidência:** `release_supply_chain_public_api_test.dart`

---

## Documentação

- [ ] `docs/release_supply_chain/README.md`
- [ ] `docs/adr/ADR-030-release-supply-chain-and-provenance-framework.md`
- [ ] `docs/architecture-reviews/AR-016-release-supply-chain-foundation.md`
- [ ] Este checklist preenchido

---

## Decisão

| Resultado | Condição |
|-----------|----------|
| **GO WITH CONDITIONS** | Beta 5.0 — políticas candidate, store in-memory, sem crypto |
| **GO** | Todas as condições da AR-016 secção 8 cumpridas |
| **NO-GO** | Falha em replay, resolver chama evaluate, ou contrato público alterado |

**Decisão atual:** GO WITH CONDITIONS (ver AR-016)
