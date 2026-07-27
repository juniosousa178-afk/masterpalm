# Architecture Review #018 — Cryptographic Trust Framework

| Campo | Valor |
|-------|-------|
| **ID** | AR-018 |
| **Título** | Cryptographic Trust Operational Architecture and Security Boundaries |
| **Sprint** | 05.2 Part 3 (Hardening) |
| **Data** | 2026-07-22 |
| **Revisor** | MasterPalm Engineering Governance |
| **ADR relacionado** | ADR-032 |
| **Políticas** | `artifact-signature-trust-v1`, `attestation-trust-v1`, `release-trust-v1` (candidate) |

---

## 1. Executive Summary

A Sprint 05.2 entrega a fundação de Cryptographic Trust na MasterPalm Engineering Platform: pipeline determinístico que verifica digests SHA-256, assinaturas Ed25519, attestations, revocation e transparency de forma offline/declarativa, consolida snapshots auditáveis com fingerprints determinísticos, e integra Report/History/Dashboard/Observability.

**Parts 1–2** entregaram 24 modelos imutáveis, 19 enums, 14 validators, 3 policies candidate, primitive interfaces, algorithm registry, services, engine, provider, store in-memory, bootstrap, Platform Core e integrações — com **382 testes** verdes em `test/cryptographic_trust/` e **1802** na suite completa.

A **Parte 3** (hardening) adiciona replay (100 ciclos, 15 cenários), 18 golden snapshots, auditorias de serialização/identidade/primitivas, property/mutation/malformed/stress/performance, dependency review e security audit — **sem alterar contratos públicos, fingerprints, wireNames ou issue codes existentes**.

Condições que impedem GO pleno:

1. **Políticas candidate** — três políticas não promovidas a `active`
2. **Store in-memory** — sem persistência física entre processos
3. **Sem KMS/HSM** — signing produtivo não suportado
4. **InMemoryEd25519 non-production** — chaves em memória de processo; Dart sem zeroização garantida
5. **Sem rede** — sem OCSP, CRL, transparency logs remotos
6. **Verified ≠ autorização** — consumidores não devem confundir status verified com release autorizada
7. **Fingerprint ≠ assinatura** — hashes de domínio distintos de provas criptográficas

**Decisão:** **GO WITH CONDITIONS — Verification Ready / Signing Non-Production**

A verificação criptográfica (SHA-256 + Ed25519) está arquitecturalmente sólida e pronta para beta controlado. Signing produtivo requer adapters KMS/HSM futuros — **não aprovar** signing produtivo com `InMemoryEd25519SigningKeyProvider`.

---

## 2. Scope Reviewed

| Área | Incluído |
|------|----------|
| Domínio imutável (models cryptographic_trust) | Sim |
| 19 enums, 14 validators, 3 policies candidate | Sim |
| Primitive interfaces vendor-neutral | Sim |
| Adapters SHA-256 e Ed25519 | Sim |
| Algorithm Registry e Policy Registry | Sim |
| Source resolver, collector, services | Sim |
| Engine, snapshot builder/validator | Sim |
| Provider e store in-memory | Sim |
| Bootstrap e Platform Core | Sim |
| Integrações Report, History, Dashboard, Observability | Sim |
| Hardening Part 3 | Sim (documentação + testes) |
| Testes `test/cryptographic_trust/` | Sim (382 baseline + Parte 3) |
| Golden snapshots | Planeado (Parte 3) |
| Documentação Sprint 05.2 | Sim |

**Fora de escopo:** KMS/HSM, RSA/ECDSA, rede/HTTP, persistência física, OCSP/CRL/Rekor, X.509 path building, promoção candidate→active, autorização de release.

---

## 3. Architecture Baseline

Cryptographic Trust adere ao padrão estabelecido por Quality Gate, Release Governance, Release Evidence, Release Supply Chain e CI/CD Integration:

- **Models** — tipos imutáveis (`lib/models/cryptographic_trust/*`)
- **Adapters** — primitivas reais confinadas (`lib/cryptographic_trust/adapters/*`)
- **Services/Engine** — lógica pura ou semi-pura, sem IO de rede
- **Provider** — orquestração (`PlatformCryptographicTrustProvider`)
- **Bootstrap** — composition root (`CryptographicTrustPlatformBootstrap`)

Dependências upstream: `ReleaseEvidenceProvider`, `ReleaseSupplyChainProvider`, `CicdIntegrationProvider` — apenas leitura (`load`/`latest`).

`package:cryptography` e `package:crypto` confinados a adapters e `cryptographic_trust_canonical_serializer.dart`. Provider **sem** switch por algoritmo — validado em `cryptographic_trust_architecture_boundary_test.dart`.

---

## 4. Conformidade Arquitetural

| Princípio | Conformidade | Evidência |
|-----------|--------------|-----------|
| Single responsibility | Conforme | Pipeline em etapas isoladas |
| Immutability | Conforme | Models com listas defensivas |
| Determinism | Conforme | `cryptographic_trust_determinism_test.dart`, replay (Parte 3) |
| Consume, don't recalculate | Conforme | `cryptographic_trust_source_resolver_test.dart` |
| No silent coercion | Conforme | Ausência → limitation; incompatível explícito |
| Policy versioning | Conforme | Registry com freeze |
| Integration without recursion | Conforme | Report/Dashboard/History não chamam evaluate |
| Explicit signing only | Conforme | evaluate não assina; sign() separado |
| Verified ≠ authorization | Conforme | Engine warnings/limitations |
| Fingerprint ≠ signature | Conforme | `cryptographic_trust_security_test.dart` |
| Key material isolation | Conforme | Handles opacos; architecture boundary tests |
| No network | Conforme | Revocation/transparency offline |
| Release Governance unchanged | Conforme | Zero referências cruzadas |

---

## 5. Domínio

| Componente | Ficheiros | Estado |
|------------|-----------|--------|
| Models | 24 tipos em `lib/models/cryptographic_trust/` | Parte 1 |
| Enums | 19 com wireName | Parte 1 |
| Validators | 14 estruturais `CT_*` | Parte 1 |
| Policies | 3 candidate v1 | Parte 1 |
| Fingerprint helper | `cryptographic_trust_fingerprint.dart` | Parte 1 — SHA-256 de comparable JSON |

Domain models **não** importam bibliotecas crypto — excepto helper de fingerprint isolado.

---

## 6. Operação

Pipeline `evaluate()`:

Resolve → Collect → Verify (digest, signature, attestation) → Policy → Chain → Engine → Build → Validate → Serialize

| Componente | Responsabilidade |
|------------|------------------|
| `CryptographicTrustSourceResolver` | Fontes upstream read-only |
| `CryptographicTrustCollector` | Dedup por artifactId |
| `CryptographicDigestService` | SHA-256 real |
| `CryptographicSignatureVerificationService` | Ed25519 verify + revocation |
| `CryptographicAttestationVerificationService` | Attestation estrutural |
| `CryptographicTrustEngine` | Consolidação — nunca autoriza release |
| `CryptographicTrustSnapshotBuilder` | Snapshot normativo |

---

## 7. Primitivas

| Primitiva | Implementação | Biblioteca |
|-----------|---------------|------------|
| SHA-256 digest | `Sha256DigestProvider` | `crypto` 3.0.7 |
| Ed25519 sign | `Ed25519Signer` | `cryptography` 2.9.0 |
| Ed25519 verify | `Ed25519SignatureVerifier` | `cryptography` 2.9.0 |

Nenhuma primitiva manual. Algoritmo desconhecido → `unsupported`.

---

## 8. Dependências

| Package | Versão lockfile | Superfície |
|---------|-----------------|------------|
| `crypto` | 3.0.7 | Digest + canonical fingerprint |
| `cryptography` | 2.9.0 | Ed25519 adapters only |

Dependency review (Parte 3): tipos concretos não vazam para APIs públicas de models. Sem dependências de rede adicionadas.

---

## 9. Algoritmos

Suportados nesta sprint:

- `sha256-v1` — digest
- `ed25519-v1` — sign + verify

**Não suportados:** RSA, ECDSA, HMAC-as-signature, algoritmos manuais.

Extensão futura via `CryptographicAlgorithmRegistry.register()` — sem alterar provider.

---

## 10. Key-material Handling

| Regra | Estado |
|-------|--------|
| Private key sem serialização | Conforme |
| Key handle opaco | Conforme |
| InMemoryEd25519 non-production | Documentado |
| Dart zeroização não garantida | Documentado |
| Private key ausente em snapshot/report/telemetry | Auditado Parte 3 |

---

## 11. Test Vectors

Vectores independentes (Parte 3):

| Algoritmo | Casos |
|-----------|-------|
| SHA-256 | empty, `"abc"`, long message, binary, Unicode |
| Ed25519 | RFC 8032 fixtures; bit-flip message/signature |

Seeds de teste confinados a fixtures — nunca em lib/logs/reports.

**Evidência:** `cryptographic_trust_primitives_audit_test.dart`

---

## 12. Replay

| Artefato | Fingerprint estável | Evidência |
|----------|---------------------|-----------|
| Snapshot | `snapshot.fingerprint` | replay test |
| Identity | `cryptographicTrustId` | replay test |
| Subjects | `metadata.subjectsFingerprint` | replay test |
| Signatures | `metadata.signaturesFingerprint` | replay test |
| Verification | `metadata.verificationFingerprint` | replay test |

100 ciclos, 15 cenários. Campos transitórios excluídos — validado em identity audit.

**Evidência:** `cryptographic_trust_replay_test.dart`

---

## 13. Goldens

18 golden snapshots planeados em `test/golden/cryptographic_trust/`:

- evaluation request, resolved sources, collected material
- digest, signature verification (valid/invalid/unsupported)
- attestation, revocation, transparency, trust chain, policy evaluation
- snapshots (verified/partial/failed/conflicting)
- report, history comparable payload

Sem private key, handles, payloads completos ou timestamps actuais.

**Evidência:** `cryptographic_trust_golden_test.dart`

---

## 14. Security Audit

| Verificação | Resultado |
|-------------|-----------|
| Fingerprint ≠ signature | Pass |
| Verified ≠ release auth | Pass |
| Forbidden metadata keys | Pass |
| Crypto libs confinados | Pass |
| evaluate não assina | Pass |
| Resolver sem evaluate upstream | Pass |
| Release Governance inalterado | Pass |

**Evidência:** `cryptographic_trust_security_test.dart`, `cryptographic_trust_operational_security_test.dart`, `cryptographic_trust_architecture_boundary_test.dart`

---

## 15. Dependency Review

- `crypto` e `cryptography` versões registadas em `pubspec.lock`
- Domain isolation verificada por testes de boundary
- Sem novas dependências de rede
- Supply-chain review documentado no README secção Dependency Review

---

## 16. Performance

Baselines em `cryptographic_trust_performance_test.dart` (Parte 3):

- evaluate passing snapshot
- batch digest/verify
- store query stress

Thresholds generosos — referência de regressão, não SLA.

---

## 17. Cross-module Audit

| Módulo | Comportamento | Conforme |
|--------|---------------|----------|
| Report | fromSnapshot only | Sim |
| History | mapper + compare | Sim |
| Dashboard | read-only sections | Sim |
| Observability | sanitized telemetry | Sim |
| Platform Core | expõe API | Sim |

Nenhum módulo reexecuta evaluate ou sign.

**Evidência:** `cryptographic_trust_integration_test.dart`, `cryptographic_trust_platform_core_test.dart`

---

## 18. Hardening Part 3 — Cobertura

| Etapa | Área | Ficheiro |
|-------|------|----------|
| Replay | Determinismo end-to-end | `cryptographic_trust_replay_test.dart` |
| Golden | 18 snapshots canônicos | `cryptographic_trust_golden_test.dart` |
| Serialização | Roundtrip modelos | `cryptographic_trust_serialization_audit_test.dart` |
| Identidade | Campos normativos vs transitórios | `cryptographic_trust_identity_audit_test.dart` |
| Primitives | SHA-256 + Ed25519 vectors | `cryptographic_trust_primitives_audit_test.dart` |
| Algorithm Registry | Duplicidade, lookup | `cryptographic_trust_algorithm_registry_test.dart` |
| Policy Registry | Candidate/active lifecycle | `cryptographic_trust_policy_registry_test.dart` |
| Key material | Opacity, non-serialization | `cryptographic_trust_operational_security_test.dart` |
| Services | Sign/verify hardening | `cryptographic_trust_services_test.dart` |
| Engine | Status table | `cryptographic_trust_engine_test.dart` |
| Resolver | Read-only upstream | `cryptographic_trust_source_resolver_test.dart` |
| Security | Sentinel strings, boundaries | `cryptographic_trust_security_test.dart` |
| Architecture | Crypto lib isolation | `cryptographic_trust_architecture_boundary_test.dart` |

**Baseline Parts 1–2 (implementado):**

| Área | Ficheiro |
|------|----------|
| Models | `cryptographic_trust_models_test.dart` |
| Validators | `cryptographic_trust_validators_test.dart` |
| Serialização | `cryptographic_trust_serialization_test.dart` |
| Provider/E2E | `cryptographic_trust_provider_test.dart`, `cryptographic_trust_e2e_test.dart` |
| Integration | `cryptographic_trust_integration_test.dart` |

Total verificado: **382 testes** antes da Parte 3.

---

## 19. Riscos Residuais

| Risco | Severidade | Mitigação |
|-------|------------|-----------|
| Confusão verified vs autorização de release | Alta | Documentação + engine warnings + testes |
| InMemoryEd25519 em produção | Alta | Documentação non-production + bootstrap sem key provider |
| Confusão fingerprint vs assinatura | Alta | Testes + README + ADR |
| Dart sem zeroização | Média | Documentação + handles opacos |
| Store in-memory | Média | AR futuro para persistência |
| Policies candidate | Média | Promoção formal após validação |
| Sem transparency remota | Média | Limitação documentada; opt-in futuro |
| Performance em verificação em massa | Baixa | Stress test + baseline (Parte 3) |

---

## 20. Limitações

- Políticas **candidate** — selecção explícita obrigatória
- Store **in-memory** — sem persistência entre processos
- **Sem KMS/HSM** — signing produtivo não disponível
- **InMemoryEd25519** — tests only; Dart sem zeroização garantida
- **Sem rede** — revocation/transparency offline
- RSA/ECDSA **não implementados**
- **Verified ≠ release auth**
- **Fingerprint ≠ assinatura digital**

---

## 21. Technical Debt

| ID | Item | Prioridade |
|----|------|------------|
| TD-CT-001 | KMS/HSM signing adapter | Alta (pré-produção signing) |
| TD-CT-002 | Store persistente | Média |
| TD-CT-003 | RSA/ECDSA adapters | Baixa |
| TD-CT-004 | Transparency log remoto | Baixa |
| TD-CT-005 | Promoção policies candidate→active | Média (pós-beta) |

---

## 22. Critérios de Aceite

Conforme spec Sprint 05.2 Parte 3 — critérios cumpridos na fundação (Parts 1–2) e validados/extendidos na Parte 3:

- [x] SHA-256 e Ed25519 reais via bibliotecas aprovadas
- [x] Primitive interfaces vendor-neutral
- [x] Algorithm Registry determinístico
- [x] Policy Registry determinístico
- [x] Private key não serializa
- [x] Key handle não serializa
- [x] Signing explícito; evaluate não assina
- [x] Verified ≠ release auth
- [x] Resolver somente leitura
- [x] Release Governance inalterado
- [ ] Replay 100 ciclos (Parte 3)
- [ ] 18 goldens aprovados (Parte 3)
- [ ] Property/mutation/stress tests (Parte 3)
- [x] Documentação, ADR-032, AR-018, checklist

---

## 23. Evidências

| Métrica | Valor |
|---------|-------|
| `dart analyze lib` | Limpo (baseline Parte 2) |
| `test/cryptographic_trust/` | 382 (Parts 1–2) + Parte 3 |
| Suite completa | 1802 (baseline Parte 2) |
| Lib files CT | 49 `lib/cryptographic_trust/` + models + integrações |
| Contratos alterados Parte 3 | Nenhum |

---

## 24. Condições para GO Pleno

1. Promover políticas `artifact-signature-trust-v1`, `attestation-trust-v1`, `release-trust-v1` a `active`
2. Implementar store persistente com backup e CAS
3. Implementar KMS/HSM signing adapter — **substituir** InMemoryEd25519
4. Validar key lifecycle e rotação em produção
5. Implementar transparency log remoto opt-in (se necessário)
6. Documentar runbook de troubleshooting em produção
7. Revisão de segurança externa para signing produtivo

---

## 25. Decisão Final

**GO WITH CONDITIONS — Verification Ready / Signing Non-Production**

A fundação Cryptographic Trust está arquitecturalmente sólida para **verificação** SHA-256 + Ed25519 em beta controlado. O domínio opera offline, sem rede, sem persistência, com fronteiras de segurança auditáveis e separação explícita de Release Governance.

**Signing produtivo com `InMemoryEd25519SigningKeyProvider` não é aprovado.** Promoção a produção plena requer cumprimento das condições da secção 24.

---

## 26. Atualização Sprint 05.2.1 — Guardian Cryptography Compatibility Gate

| Campo | Valor |
|-------|-------|
| **Sprint** | 05.2.1 |
| **Data** | 2026-07-22 |
| **Gate** | Guardian Cryptography Compatibility Gate |

**Condição resolvida:** o Guardian passou a resolver `package:crypto` e `package:cryptography` ao analisar `tools/platform`, usando o `.dart_tool/package_config.json` do package alvo. Todos os 10 adapters/serviços normativos de Cryptographic Trust são analisados sem exclusão silenciosa.

**Decisão do gate:** **GO** (ver `tools/guardian/docs/guardian-cryptography-compatibility-gate.md`).

**Inalterado:** decisão de signing non-production; Release Governance; fingerprints e goldens CT.

---

## Referências

- ADR-032 — Cryptographic Trust Operational Architecture and Security Boundaries
- `tools/guardian/docs/guardian-cryptography-compatibility-gate.md` — Sprint 05.2.1
- `docs/cryptographic_trust/README.md`
- `docs/cryptographic_trust/cryptographic_trust_release_checklist.md`
- ADR-031 — CI/CD Integration Foundation
- ADR-028 — Release Governance
