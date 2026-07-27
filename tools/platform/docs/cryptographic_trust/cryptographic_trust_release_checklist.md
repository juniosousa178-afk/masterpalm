# Cryptographic Trust — Release Checklist (Sprint 05.2)

**Sprint:** 05.2 — Cryptographic Trust Framework
**Políticas:** `artifact-signature-trust-v1`, `attestation-trust-v1`, `release-trust-v1` (candidate)
**Última actualização:** 2026-07-22

Use este checklist antes de declarar a sprint concluída ou promover políticas candidate.

**Baseline Parts 1–2:** 382 testes em `test/cryptographic_trust/` (verificado antes da Parte 3).
**Após Parte 3:** suite expandida com replay, golden, audits, property, mutation, stress e performance — ver AR-018.

---

## Domain Foundation

- [x] 24 modelos imutáveis em `lib/models/cryptographic_trust/`
- [x] 19 enums com wireName/fromWireName
- [x] 14 validators estruturais com issue codes `CT_*`
- [x] 3 policies candidate v1 (models only validados)
- [x] Domain models isolados de `package:crypto` e `package:cryptography`

**Evidência:** `cryptographic_trust_models_test.dart`, `cryptographic_trust_validators_test.dart`, `cryptographic_trust_policies_test.dart`

---

## Operational Foundation

- [x] Provider, resolver, collector, engine, snapshot builder
- [x] Bootstrap com dependências upstream (RE, RSC, CI/CD)
- [x] Integrações Report, History, Dashboard, Platform Core
- [x] Release Governance inalterado

**Evidência:** `cryptographic_trust_provider_test.dart`, `cryptographic_trust_e2e_test.dart`, `cryptographic_trust_integration_test.dart`, `cryptographic_trust_architecture_boundary_test.dart`

---

## SHA-256

- [x] `Sha256DigestProvider` via `package:crypto`
- [ ] Vetores independentes validados (empty, abc, long message, binary, Unicode)
- [ ] Nenhuma implementação SHA manual

**Evidência:** `cryptographic_trust_primitives_test.dart`, `cryptographic_trust_primitives_audit_test.dart`

---

## Ed25519

- [x] `Ed25519Signer` e `Ed25519SignatureVerifier` via `package:cryptography`
- [ ] Vetores independentes RFC 8032 validados
- [ ] Alteração de bit invalida verificação
- [ ] Nenhuma implementação Ed25519 manual

**Evidência:** `cryptographic_trust_primitives_test.dart`, `cryptographic_trust_primitives_audit_test.dart`

---

## Vetores independentes

- [ ] SHA-256: string vazia, `"abc"`, mensagem longa, bytes binários, Unicode
- [ ] Ed25519: public key, message, signature conhecidos (fixtures de teste apenas)
- [ ] Seeds de teste não entram em lib, logs, reports ou telemetry

**Evidência:** `cryptographic_trust_primitives_audit_test.dart`

---

## Replay

- [ ] Snapshot fingerprint idêntico em re-evaluate (100 ciclos)
- [ ] `cryptographicTrustId` estável
- [ ] Fingerprints por secção estáveis
- [ ] JSON round-trip preserva identidade
- [ ] 15 cenários cobertos (valid/invalid/partial/conflicting)

**Evidência:** `cryptographic_trust_replay_test.dart`

---

## Golden Snapshots

- [ ] 18 goldens aprovados em `test/golden/cryptographic_trust/`
- [ ] Sem private key, handle, payload completo ou timestamps actuais
- [ ] Fingerprints estáveis entre execuções

**Evidência:** `cryptographic_trust_golden_test.dart`

---

## Serializer

- [ ] toJson/fromJson roundtrip em modelos auditados
- [ ] toComparableJson exclui campos transitórios
- [ ] Map ordering determinístico
- [ ] Identity exclusion evita circularidade

**Evidência:** `cryptographic_trust_serialization_test.dart`, `cryptographic_trust_serialization_audit_test.dart`

---

## Identity

- [ ] Apenas campos normativos em fingerprints de snapshot
- [ ] Fingerprints de componentes excluem campos transitórios
- [ ] Mutação de campo normativo altera fingerprint
- [ ] Domain fingerprint ≠ assinatura digital documentado

**Evidência:** `cryptographic_trust_identity_audit_test.dart`, `cryptographic_trust_determinism_test.dart`

---

## Algorithm Registry

- [ ] Register, lookup, freeze determinísticos
- [ ] Duplicidade e conflito rejeitados
- [ ] Provider sem switch por algoritmo
- [ ] Algoritmo ausente → unsupported

**Evidência:** `cryptographic_trust_algorithm_registry_test.dart`, `cryptographic_trust_primitives_audit_test.dart`

---

## Policy Registry

- [ ] register, resolveById, latest, promote, deprecate, retire
- [ ] Candidate sem allowCandidate não resolve
- [ ] Nenhuma promoção automática
- [ ] release-trust-v1 não autoriza release

**Evidência:** `cryptographic_trust_policy_registry_test.dart`

---

## Key-material

- [ ] Private key sem toJson/fromJson/copyWith
- [ ] Key handle não serializa nem participa de fingerprint
- [ ] Private key ausente em snapshot, report, history, dashboard, telemetry
- [ ] InMemoryEd25519 documentado como non-production

**Evidência:** `cryptographic_trust_operational_security_test.dart`, `cryptographic_trust_security_test.dart`, `cryptographic_trust_architecture_boundary_test.dart`

---

## Signing Service

- [ ] Signing explícito via `sign()` apenas
- [ ] `evaluate()` não assina
- [ ] Sem provider → unavailable
- [ ] Private key nunca exposta no result

**Evidência:** `cryptographic_trust_services_test.dart`, `cryptographic_trust_provider_test.dart`

---

## Verification Service

- [ ] Assinatura válida → outcome valid
- [ ] Assinatura inválida → invalid sem exception não controlada
- [ ] Payload alterado invalida
- [ ] Assinatura válida não eleva trust automaticamente

**Evidência:** `cryptographic_trust_services_test.dart`, `cryptographic_trust_primitives_test.dart`

---

## Attestation

- [ ] Verificação estrutural sem serviços externos
- [ ] Attestation parcial mapeada correctamente
- [ ] Limitação `no-real-attestation-verification` presente

**Evidência:** `cryptographic_trust_evaluators_test.dart`, `cryptographic_trust_services_test.dart`

---

## Revocation

- [ ] Avaliação declarativa offline
- [ ] Key revogada → status revoked
- [ ] Sem CRL/OCSP remoto

**Evidência:** `cryptographic_trust_evaluators_test.dart`

---

## Transparency

- [ ] Avaliação offline de referências estruturais
- [ ] Distinção reference vs remote proof
- [ ] Sem contacto de rede

**Evidência:** `cryptographic_trust_evaluators_test.dart`

---

## Trust Chain

- [ ] Builder declarativo sem X.509 path building
- [ ] Ciclos detectados
- [ ] Referências ausentes reportadas

**Evidência:** `cryptographic_trust_engine_test.dart`, `cryptographic_trust_collector_test.dart`

---

## Trust Engine

- [ ] Status decision table conforme ADR-032
- [ ] `verified-does-not-authorize-release` em warnings
- [ ] `no-release-authorization` em limitations
- [ ] Issues ordenados deterministicamente

**Evidência:** `cryptographic_trust_engine_test.dart`

---

## Source Resolver

- [ ] injected vence byId e latest
- [ ] latest apenas com useLatest: true
- [ ] nunca chama evaluate/evaluateAndPublish/publish upstream
- [ ] projectId mismatch gera limitation

**Evidência:** `cryptographic_trust_source_resolver_test.dart`

---

## Collector

- [ ] dedup por artifactId
- [ ] fontes ausentes não produzem artefatos fictícios
- [ ] fingerprints de origem preservados

**Evidência:** `cryptographic_trust_collector_test.dart`

---

## Snapshot Validator

- [ ] Validação estrutural consistente
- [ ] Snapshot conflicting rejeitado

**Evidência:** `cryptographic_trust_operational_models_test.dart`

---

## Store

- [ ] save idempotente para mesmo fingerprint
- [ ] conflito em snapshot divergente com mesmo id
- [ ] clear remove todos
- [ ] query com limit e offset

**Evidência:** `cryptographic_trust_store_test.dart`

---

## Provider

- [ ] evaluate idempotente
- [ ] evaluateAndPublish idempotente no segundo publish
- [ ] latest retorna snapshot mais recente
- [ ] invalidate remove do load

**Evidência:** `cryptographic_trust_provider_test.dart`

---

## Report

- [ ] Report gera secções a partir de snapshot (`ReportType.cryptographicTrust`)
- [ ] Report não executa evaluate ou sign
- [ ] Payload sanitizado

**Evidência:** `cryptographic_trust_integration_test.dart`

---

## History

- [ ] History mapper determinístico
- [ ] Comparable payload sem material sensível

**Evidência:** `cryptographic_trust_integration_test.dart`, golden `history_comparable_payload.json`

---

## Dashboard

- [ ] Dashboard renderiza secções cryptographicTrust*
- [ ] Dashboard não invoca evaluate

**Evidência:** `cryptographic_trust_integration_test.dart`, `cryptographic_trust_platform_core_test.dart`

---

## Observability

- [ ] Telemetry sanitizada — sem payloads, digests, signatures ou keys
- [ ] Observability não altera payload de evaluate

**Evidência:** `cryptographic_trust_operational_security_test.dart`

---

## Property / Mutation / Malformed / Stress / Performance

- [ ] property tests de ordering e fingerprint
- [ ] mutation tests rejeitam mutações inválidas
- [ ] malformed-input tests (fuzz-style)
- [ ] stress em coleções grandes
- [ ] performance baselines documentadas

**Evidência:** `cryptographic_trust_property_test.dart`, `cryptographic_trust_mutation_test.dart`, `cryptographic_trust_malformed_input_test.dart`, `cryptographic_trust_stress_test.dart`, `cryptographic_trust_performance_test.dart`

---

## Dependency Review

- [ ] Versões `crypto` e `cryptography` registadas no lockfile
- [ ] Tipos concretos confinados a adapters e serializer
- [ ] Nenhuma dependência de rede adicionada

**Evidência:** `pubspec.lock`, `cryptographic_trust_architecture_boundary_test.dart`

---

## Static Security Review

- [ ] sentinel strings ausentes em JSON e fingerprints
- [ ] forbidden metadata keys rejeitados (`privateKey`, `secret`, etc.)
- [ ] verified ≠ release auth testado
- [ ] fingerprint ≠ signature testado

**Evidência:** `cryptographic_trust_security_test.dart`, `cryptographic_trust_operational_security_test.dart`

---

## Cross-module Audit

- [ ] Report/History/Dashboard/Observability não reexecutam pipeline
- [ ] Platform Core expõe API sem side-effects ocultos
- [ ] Release Governance inalterado

**Evidência:** `cryptographic_trust_integration_test.dart`, `cryptographic_trust_platform_core_test.dart`, `cryptographic_trust_architecture_boundary_test.dart`

---

## Analyze

- [ ] `dart analyze lib` sem issues
- [ ] Nenhum warning novo em `lib/cryptographic_trust/`
- [ ] Nenhum contrato público alterado na Parte 3

**Evidência:** `dart analyze lib`

---

## Testes

- [x] Baseline `test/cryptographic_trust/` verde (382 testes Parts 1–2)
- [ ] Parte 3 (hardening): replay, golden, audits, property, mutation, stress, performance
- [ ] Suite completa verde

**Evidência:** `dart test test/cryptographic_trust/`, `dart test`

---

## Documentação

- [x] `docs/cryptographic_trust/README.md`
- [x] `docs/adr/ADR-032-cryptographic-trust-operational-architecture-and-security-boundaries.md`
- [x] `docs/architecture-reviews/AR-018-cryptographic-trust-framework.md`
- [ ] Este checklist preenchido

---

## Restrições absolutas

- [x] Sem segredo em lib (models/validators)
- [x] Sem rede
- [x] Sem persistência física
- [x] Sem KMS/HSM
- [x] Sem autorização de release
- [x] Sem commit/push/deploy (processo)

---

## Decisão

| Resultado | Condição |
|-----------|----------|
| **GO WITH CONDITIONS — Verification Ready / Signing Non-Production** | Verificação Ed25519/SHA-256 pronta; signing apenas InMemoryEd25519; policies candidate; store in-memory |
| **GO** | Todas as condições da AR-018 secção 8 cumplidas + signing produtivo com KMS/HSM |
| **NO-GO** | Private key em snapshot/telemetry, evaluate assina implicitamente, ou resolver chama evaluate upstream |

**Decisão actual:** GO WITH CONDITIONS — Verification Ready / Signing Non-Production (ver AR-018)
