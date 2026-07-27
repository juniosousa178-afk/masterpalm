# Release Evidence — Release Checklist (Sprint 04.3)

**Sprint:** 04.3 — Release Evidence and Attestation Foundation
**Políticas:** `release-evidence-v1`, `release-attestation-v1`, `release-verification-v1` (candidate)
**Última atualização:** 2026-07-22

Use este checklist antes de declarar a sprint concluída ou promover políticas candidate.

---

## Analyze

- [x] `dart analyze lib` sem issues
- [x] Nenhum warning novo em `lib/release_evidence/`
- [x] Nenhum contrato público alterado na Parte 3

**Evidência:** `dart analyze lib` — No issues found!

---

## Testes

- [x] Suite total verde (**1018** testes)
- [x] Testes Release Evidence (**186**)
- [x] Parte 1 (models/validators): 62 testes base
- [x] Parte 2 (operacional): provider, engines, integração
- [x] Parte 3 (hardening): replay, golden, audits, stress, performance

**Evidência:** `dart test`, `dart test test/release_evidence/`

---

## Replay (Etapa 83)

- [x] Bundle fingerprint idêntico em re-evaluate
- [x] Verification fingerprint idêntico
- [x] Attestations idênticas (ordering + fingerprints)
- [x] Coverage/compatibility/eligibility idênticos
- [x] JSON round-trip preserva identidade

**Evidência:** `release_evidence_replay_test.dart`

---

## Golden Snapshots (Etapa 84)

- [x] `passing_bundle.json` — bundle canônico
- [x] `passing_verification.json` — verification result
- [x] `valid_attestation_set.json` — attestation set
- [x] Fingerprints estáveis entre execuções
- [x] Canonical ordering validado

**Evidência:** `release_evidence_golden_test.dart`, `test/golden/release_evidence/`

---

## Serialização (Etapa 85)

- [x] toJson/fromJson roundtrip em todos os modelos auditados
- [x] Enums com unknown wire name
- [x] Timestamps UTC
- [x] Coleções imutáveis
- [x] Campos opcionais/obrigatórios

**Evidência:** `release_evidence_serialization_audit_test.dart`

---

## Identidade (Etapa 86)

- [x] Apenas campos normativos em fingerprints de bundle
- [x] Verification fingerprint exclui campos transitórios
- [x] Attestation fingerprint estável
- [x] Mutação de campo normativo altera fingerprint

**Evidência:** `release_evidence_identity_audit_test.dart`, `release_evidence_mutation_test.dart`

---

## Provider Hardening (Etapa 87)

- [x] evaluate repetido idempotente
- [x] publish repetido idempotente
- [x] evaluateAndPublish repetido
- [x] latest, query, invalidate, clear

**Evidência:** `release_evidence_hardening_test.dart`, `release_evidence_provider_test.dart`

---

## Store Hardening (Etapa 88)

- [x] save, overwrite, invalidate, clear
- [x] latest e query
- [x] Concorrência simulada

**Evidência:** `release_evidence_hardening_test.dart`

---

## Source Resolver (Etapa 89)

- [x] Objeto injetado vence byId/latest
- [x] Resolução por ID
- [x] latest opt-in (`useLatest: true`)
- [x] Artefatos ausentes/incompatíveis
- [x] Nunca chama evaluate() em origem

**Evidência:** `release_evidence_source_resolver_audit_test.dart`

---

## Collector (Etapa 90)

- [x] Deduplicação por artifactId
- [x] Artefatos inválidos/incompatíveis/ausentes
- [x] Nenhum payload duplicado

**Evidência:** `release_evidence_collector_audit_test.dart`

---

## Bundle (Etapa 91)

- [x] Ordering por artifactId
- [x] Evidence references, provenance, attestations
- [x] Coverage, compatibility, eligibility
- [x] Warnings, explanations, limitations

**Evidência:** `release_evidence_bundle_audit_test.dart`

---

## Engines (Etapa 92)

- [x] AttestationEngine — issuer/authority/signature/predicates
- [x] VerificationEngine — evidence/provenance incompleta
- [x] Verificação estrutural apenas (sem crypto)

**Evidência:** `release_evidence_engine_audit_test.dart`, `release_evidence_engines_test.dart`

---

## Observability (Etapa 93)

- [x] Eventos emitidos por operação
- [x] Métricas e timings (duration)
- [x] Correlação preservada
- [x] Resultado inalterado pelo decorator

**Evidência:** `release_evidence_observability_audit_test.dart`, `release_evidence_observability_test.dart`

---

## Report (Etapa 94)

- [x] Bundle completo gera secções
- [x] Bundle parcial renderiza
- [x] Bundle incompatível tratado

**Evidência:** `release_evidence_integration_audit_test.dart`

---

## History (Etapa 95)

- [x] Diff determinístico
- [x] Replay de snapshots equivalentes
- [x] Comparação sem falsos positivos

**Evidência:** `release_evidence_integration_audit_test.dart`

---

## Dashboard (Etapa 96)

- [x] Renderização de bundle e verification
- [x] Coverage e warnings
- [x] Consome snapshots publicados

**Evidência:** `release_evidence_integration_audit_test.dart`

---

## Property-Based (Etapa 97)

- [x] Ordering determinístico (20 seeds)
- [x] Identity invariant
- [x] Serialization invariant
- [x] Validation rejeita mutações

**Evidência:** `release_evidence_property_test.dart`

---

## Mutation (Etapa 98)

- [x] Bundle validator rejeita mutações (4 casos)
- [x] Policy validator rejeita rules vazias
- [x] Identity muda com campo normativo

**Evidência:** `release_evidence_mutation_test.dart`

---

## Stress (Etapa 99)

- [x] 1000 evidence artifacts < 5s
- [x] Collector dedup em escala (200)

**Evidência:** `release_evidence_stress_test.dart`

---

## Performance (Etapa 100)

- [x] evaluate < 3s
- [x] publish + load < 3s
- [x] query < 1s
- [x] replay 10× < 5s

**Evidência:** `release_evidence_performance_test.dart`

---

## Security (Etapa 101)

- [x] Sem sentinel em bundle/report/fingerprint
- [x] Assinatura não implica validade criptográfica
- [x] Telemetry sanitizer redige secrets

**Evidência:** `release_evidence_security_test.dart`

---

## Public API (Etapa 102)

- [x] Provider, Store, Bootstrap exportados
- [x] Validators exportados para consumidores
- [x] Políticas v1 exportadas

**Evidência:** `release_evidence_public_api_test.dart`, `masterpalm_platform.dart`

---

## Documentação (Etapa 103)

- [x] `docs/release_evidence/README.md`
- [x] Arquitetura, pipeline, exemplos
- [x] Limitações, replay, troubleshooting

---

## ADR (Etapa 104)

- [x] ADR-029 criado
- [x] Motivação, arquitetura, decisões, alternativas, limitações, evolução

**Evidência:** `docs/adr/ADR-029-release-evidence-and-attestation-foundation.md`

---

## Architecture Review (Etapa 105)

- [x] AR-015 emitido
- [x] Conclusão: **GO WITH CONDITIONS**

**Evidência:** `docs/architecture-reviews/AR-015-release-evidence-foundation.md`

---

## Restrições Parte 3

- [x] Nenhuma funcionalidade nova adicionada
- [x] Nenhuma engine existente modificada
- [x] Nenhum contrato público alterado
- [x] Nenhum fingerprint/ID existente alterado
- [x] Nenhum commit realizado
- [x] Nenhum push realizado
- [x] Nenhum deploy realizado

---

## Decisão Sprint 04.3

**Status: CONCLUÍDA — GO WITH CONDITIONS (Release 4.2 Beta)**
