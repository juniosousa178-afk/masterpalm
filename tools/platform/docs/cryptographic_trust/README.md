# Cryptographic Trust — Guia de Uso

**Pacote:** `masterpalm_platform`
**Sprint:** 05.2 — Cryptographic Trust Framework
**Políticas candidatas:** `artifact-signature-trust-v1`, `attestation-trust-v1`, `release-trust-v1`

## Objetivo

Cryptographic Trust consolida, verifica estruturalmente e publica **artefatos criptográficos declarados** sobre releases e artefatos upstream:

- `CryptographicTrustSubject`, digests, assinaturas, attestations
- `CryptographicTrustChain`, trust anchors, revocation e transparency references
- `ReleaseEvidenceBundle`, `ReleaseSupplyChainSnapshot`, `CicdIntegrationSnapshot` (linkages upstream)
- `CryptographicVerificationResult` e `CryptographicTrustSnapshot` auditáveis

O domínio **não autoriza** release ou deployment, **não contacta** KMS/HSM/rede, **não persiste** entre processos nesta sprint e **não recalcula** Quality Gate, Release Governance, Release Evidence, Release Supply Chain nem CI/CD Integration.

Use Cryptographic Trust para:

- Calcular digests SHA-256 reais sobre bytes de subject
- Verificar assinaturas Ed25519 reais via adapters registrados
- Avaliar attestations, revocation e transparency de forma **declarativa/offline**
- Produzir snapshots com fingerprints determinísticos
- Integrar trust criptográfico em Report, History, Dashboard e Observability
- Suportar replay e comparação de snapshots equivalentes

**Importante:**

| Conceito | Significado |
|----------|-------------|
| **Fingerprint de domínio** | Hash SHA-256 de JSON canônico — **não** é assinatura digital |
| **Assinatura válida** | Validade matemática Ed25519 — **não** implica trust completo nem autorização |
| **`verified`** | Status de verificação agregada — **não** autoriza release (Release Governance permanece única camada) |
| **`InMemoryEd25519SigningKeyProvider`** | Apenas testes — **não** produção |
| **Zeroização de memória** | Dart **não** garante zeroização completa de chaves privadas |

---

## Arquitetura

```
CryptographicTrustEvaluationRequest
       │
       ▼
PlatformCryptographicTrustProvider
       │
       ├── CryptographicTrustPolicyRegistry (3 policies candidate)
       ├── CryptographicAlgorithmRegistry (SHA-256, Ed25519 sign/verify)
       │
       ├── CryptographicTrustSourceResolver     ← injected | byId | latest (opt-in)
       │        ├── ReleaseEvidenceProvider.load/latest (NÃO evaluate)
       │        ├── ReleaseSupplyChainProvider.load/latest (NÃO evaluate)
       │        └── CicdIntegrationProvider.load/latest (NÃO evaluate)
       │
       ├── CryptographicTrustCollector          ← dedup por artifactId
       │
       ├── CryptographicDigestService
       ├── CryptographicSignatureVerificationService
       ├── CryptographicAttestationVerificationService
       ├── CryptographicRevocationEvaluator (declarativo)
       ├── CryptographicTransparencyEvaluator (offline)
       ├── CryptographicTrustChainBuilder (declarativo)
       ├── CryptographicTrustPolicyEvaluationService
       ├── CryptographicTrustEngine
       ├── CryptographicTrustSnapshotBuilder
       ├── CryptographicTrustSnapshotValidator
       │
       ├── CryptographicSigningService (opt-in, explícito — evaluate NÃO assina)
       │
       ├── CanonicalSerializer + IdentityBuilder
       │
       └── CryptographicTrustStore (in-memory nesta sprint)
```

| Camada | Responsabilidade |
|--------|------------------|
| `CryptographicTrustProvider` | Orquestração, IO, publicação, APIs primitivas ad-hoc |
| `CryptographicTrustSourceResolver` | Resolve fontes sem recalcular origem |
| `CryptographicTrustCollector` | Coleta e deduplica material de trust |
| `CryptographicDigestService` | Digest SHA-256 via registry |
| `CryptographicSignatureVerificationService` | Verificação Ed25519 + revocation declarativa |
| `CryptographicAttestationVerificationService` | Verificação estrutural de attestations |
| `CryptographicTrustEngine` | Consolida status — nunca autoriza release |
| `CryptographicTrustStore` | Persistência in-memory de snapshots publicados |

### Bootstrap

```dart
CryptographicTrustPlatformBootstrap.register(registry: providerRegistry);
final cryptoTrust = registry.resolve<CryptographicTrustProvider>();
```

Pré-requisitos registados **antes** de `CryptographicTrustProvider`:

1. `ReleaseEvidenceProvider`
2. `ReleaseSupplyChainProvider`
3. `CicdIntegrationProvider`

Signing é **opcional** — verificação funciona sem `CryptographicSigningKeyProvider`.

---

## Fronteiras conceituais

| Dentro do escopo | Fora do escopo (Sprint 05.2) |
|------------------|------------------------------|
| SHA-256 real (`package:crypto`) | RSA, ECDSA, algoritmos manuais |
| Ed25519 real (`package:cryptography`) | KMS, HSM, PKCS#11, TPM, Secure Enclave |
| Verificação offline/declarativa | OCSP, CRL remota, Rekor, Sigstore, HTTP |
| Store in-memory | Persistência em disco/Firestore |
| Signing explícito via `sign()` | Signing implícito em `evaluate()` |
| Policies **candidate** | Promoção automática para `active` |
| Fingerprints determinísticos | Autorização de release/deployment |

**Release Governance inalterado** — nenhum ficheiro em `lib/release_governance/` referencia `cryptographic_trust`.

**Tipos concretos de bibliotecas** ficam confinados a `lib/cryptographic_trust/adapters/` e `cryptographic_trust_canonical_serializer.dart`. Domain models não importam `package:crypto` nem `package:cryptography` (excepto helper de fingerprint).

---

## Pipeline operacional

1. **Resolve** — política e fontes (injected > byId > latest)
2. **Collect** — subjects, digests, signatures, attestations, chains
3. **Verify** — digest, signature, attestation, revocation, transparency
4. **Policy evaluation** — requisitos declarativos da policy selecionada
5. **Chain build** — trust chains declarativas
6. **Engine** — consolidação de status, issues, warnings, limitations
7. **Build snapshot** — ordering canônico + metadata
8. **Validate** — validação estrutural do snapshot
9. **Serialize** — JSON canônico e fingerprints
10. **Publish** (opcional) — gravação idempotente no store

`evaluate()` **não publica** e **não assina**. `evaluateAndPublish()` publica após validação. `sign()` é API explícita separada.

---

## Primitive interfaces

Interfaces vendor-neutral em `lib/cryptographic_trust/interfaces/`:

| Interface | Operação |
|-----------|----------|
| `CryptographicDigestProvider` | `computeDigest` |
| `CryptographicSigner` | `sign` |
| `CryptographicSignatureVerifier` | `verify` |
| `CryptographicSigningKeyProvider` | Resolve handle opaco para signing |
| `CryptographicPublicKeyResolver` | Resolve material de chave pública |
| `CryptographicTransparencyProofVerifier` | Contrato para proofs (sem implementação remota nesta sprint) |

O provider **não** contém `switch` por algoritmo — seleção via `CryptographicAlgorithmRegistry`.

---

## Adapters (SHA-256 e Ed25519)

| Adapter | Algorithm ID | Biblioteca | Notas |
|---------|--------------|------------|-------|
| `Sha256DigestProvider` | `sha256-v1` | `package:crypto` | Digest real sobre bytes |
| `Ed25519Signer` | `ed25519-v1` | `package:cryptography` | Signing real |
| `Ed25519SignatureVerifier` | `ed25519-v1` | `package:cryptography` | Verificação real |
| `InMemoryPublicKeyResolver` | — | in-memory | Testes e bootstrap default |
| `InMemoryEd25519SigningKeyProvider` | `ed25519-v1` | in-memory | **Non-production — tests only** |

Algoritmo desconhecido → `unsupported`. Key type incompatível → `algorithmMismatch`. Input malformado → erro estruturado, não exception não controlada.

---

## Algorithm Registry

`CryptographicAlgorithmRegistry`:

- Regista digest providers, signers e verifiers por `algorithmId`, `operation`, `keyType`, `format`
- `freeze()` após bootstrap default
- Lookup determinístico — sem descoberta remota nem seleção por metadata arbitrária
- Provider principal delega ao registry — **sem** switch por algoritmo

Default bootstrap regista: SHA-256 digest, Ed25519 sign, Ed25519 verify.

---

## Key material

| Tipo | Ficheiro | Regras |
|------|----------|--------|
| `CryptographicPublicKeyMaterial` | `key_material/cryptographic_public_key_material.dart` | Bytes públicos, serializável |
| `OpaqueCryptographicSigningKeyHandle` | `key_material/opaque_cryptographic_signing_key_handle.dart` | **Sem** `toJson`, **sem** fingerprint |
| `InMemoryEd25519SigningKeyHandle` | `adapters/in_memory_ed25519_signing_key_provider.dart` | Non-production |

Garantias auditadas (Parte 3):

- Private key **não** aparece em snapshot, report, history, dashboard, telemetry
- Key handle **não** serializa nem participa de comparable JSON / fingerprint
- Dart **não** garante zeroização completa de memória após dispose

---

## Signing

`CryptographicSigningService.signDigest()`:

- Requer `CryptographicSigningKeyProvider` configurado
- Sem provider → `unavailable` (`CT_SIGNING_UNAVAILABLE`)
- Resolve signer via registry + handle opaco
- Retorna `CryptographicSignatureEnvelope` — **nunca** expõe private key

`PlatformCryptographicTrustProvider.sign()` expõe signing ad-hoc. **`evaluate()` nunca invoca signing.**

`InMemoryEd25519SigningKeyProvider` é exclusivamente para testes — chaves em memória de processo, sem rotação, sem HSM.

---

## Verification

`CryptographicSignatureVerificationService`:

1. Validação estrutural do envelope
2. Resolução de chave pública
3. Avaliação de revocation declarativa
4. Verificação matemática via registry
5. Mapeamento para `CryptographicVerificationStatus`

**Assinatura matematicamente válida não eleva trust level automaticamente** — trust level deriva de policy evaluation e engine aggregation.

Payload ou assinatura alterados → `invalid`. Public key incorrecta → `invalid`.

---

## Attestation verification

`CryptographicAttestationVerificationService`:

- Consome resultados de signature verification já calculados
- Valida estrutura de `CryptographicAttestationStatement`
- **Não** contacta serviços externos de attestation
- Outcomes: verified, partiallyVerified, invalid conforme assinaturas upstream

Limitação em policies: `no-real-attestation-verification` (descriptor estrutural).

---

## Revocation evaluation

`CryptographicRevocationEvaluator`:

- Avalia `CryptographicRevocationRecord` declarativos
- Compara `referenceTime` vs `revokedAt` / `expiresAt`
- **Sem** CRL remota, **sem** OCSP
- Key revogada → status `revoked` na cadeia de verificação

---

## Transparency evaluation

`CryptographicTransparencyEvaluator`:

- Avalia `CryptographicTransparencyLogReference` estruturalmente
- Modo **offline** — **sem** contacto com log servers (Rekor, etc.)
- Distingue referência estrutural vs proof verificável remotamente

Requirement opcional em `release-trust-v1`: `require-transparency-log`.

---

## Trust chain

`CryptographicTrustChainBuilder`:

- Monta cadeias declarativas a partir de anchors e intermediates
- Deteta ciclos e referências ausentes
- **Não** executa path building X.509
- Output: `CryptographicTrustChain` com status descritivo

---

## Trust Engine

`CryptographicTrustEngine` consolida:

- Resultados de verificação, policy evaluation, chain build
- Issues ordenados deterministicamente
- Warnings incluem `verified-does-not-authorize-release`
- Limitations incluem `no-release-authorization`, `no-deployment-authorization`

Tabela de status agregado (`deriveVerificationStatus`):

| Condição | Resultado |
|----------|-----------|
| Issue critical/fatal | `invalid` |
| Conflict detectado | `invalid` |
| Component unsupported | `partiallyVerified` |
| Component unavailable | `partiallyVerified` |
| Tudo verified, sem fatal | `verified` (sem release auth) |

Snapshot status `provisional` para verified/partiallyVerified — **não** normativo de release.

---

## Políticas

Três políticas **candidate** registadas no bootstrap:

| Política | ID | Versão | Foco |
|----------|-----|--------|------|
| Artifact Signature Trust | `artifact-signature-trust-v1` | 1 | Assinatura + digest de artefactos |
| Attestation Trust | `attestation-trust-v1` | 1 | Attestations build/integrity |
| Release Trust | `release-trust-v1` | 1 | Signatures + attestations + transparency opcional |

Limitações explícitas em metadata das policies:

- `no-release-authorization`
- `no-real-verification` / `structural-descriptor-only` (conforme policy)
- `no-real-attestation-verification`

**Policy result não altera Release Governance.** Candidate policies requerem seleção explícita (`allowCandidate: true`).

---

## Serializer

`CryptographicTrustCanonicalSerializer` (`cryptographic-trust-canonical-v1`):

- Fingerprints via SHA-256 de JSON normalizado
- `_normalizeJson()` — chaves ordenadas, listas normalizadas
- Fingerprints de snapshot, evaluation request, resolved sources, collected material, digests, signatures, attestations, policies, verification

Campos excluídos de identidade:

- `cryptographicTrustSnapshotId`, `createdAt`, `evaluatedAt`, `publishedAt`
- Telemetry, duration, operation context transitório
- Key handles, material privado runtime

**Domain fingerprint ≠ assinatura digital.**

---

## Identity

`CryptographicTrustIdentityBuilder`:

| Método | Output |
|--------|--------|
| `buildCryptographicTrustId()` | ID determinístico composto |
| `buildSnapshotId()` | `ct-snapshot:{project}:{release}:{fingerprint}` |
| `subjectsFingerprint()` | Hash de subjects ordenados |
| `signaturesFingerprint()` | Hash de signatures ordenadas |
| `attestationsFingerprint()` | Hash de attestations ordenadas |
| `policiesFingerprint()` | Hash de policies |
| `trustChainsFingerprint()` | Hash de chains |
| `verificationFingerprint()` | Hash de verification results |
| `snapshotFingerprint()` | Fingerprint normativo do snapshot |

Mutação de campo normativo altera fingerprint. Campos transitórios não alteram identidade.

---

## Store

`InMemoryCryptographicTrustStore`:

- `save()` idempotente para mesmo fingerprint canônico
- Conflito (`CryptographicTrustSnapshotConflictException`) se mesmo ID com fingerprint diferente
- `latest()` ordenado por `evaluatedAt` desc
- `query()` com filtros projectId, releaseId, status, policyId, trustStatus
- `invalidate()` e `clear()`

**Sem persistência entre processos. Sem KMS/HSM.**

---

## Provider

`PlatformCryptographicTrustProvider` implementa `CryptographicTrustProvider`:

| Método | Comportamento |
|--------|---------------|
| `evaluate()` | Pipeline completo — **não** publica, **não** assina |
| `evaluateAndPublish()` | evaluate + validate + save idempotente |
| `publish()` | Grava snapshot directamente |
| `load()` / `latest()` / `query()` | Consulta store |
| `invalidate()` | Remove snapshot (throws se ausente) |
| `computeDigest()` | Digest ad-hoc via registry |
| `verifySignature()` | Verificação ad-hoc |
| `verifyAttestation()` | Attestation ad-hoc |
| `sign()` | Signing explícito — requer key provider |

Status do result: `success`, `partial`, `failure`, `unavailable`.

---

## Platform Core

`PlatformBootstrap.forRepo()` regista `CryptographicTrustPlatformBootstrap` após RE, RSC e CI/CD Integration.

```dart
final core = PlatformBootstrap.forRepo(repoPath);
final result = await core.cryptographicTrust().evaluate(request);
```

Integração transparente — Platform Core **não** reexecuta evaluate upstream nem autoriza release.

---

## Report

| Consumidor | Tipo | Comportamento |
|------------|------|---------------|
| Report | `ReportType.cryptographicTrust` | `CryptographicTrustReportSource.fromSnapshot()` |

Consome snapshot publicado ou injetado — **nunca** executa evaluate ou sign. Payload sanitizado — sem private keys, signature values completas ou digests sensíveis desnecessários.

---

## History

| Consumidor | Tipo | Comportamento |
|------------|------|---------------|
| History | `HistoryArtifactType.cryptographicTrust` | `CryptographicTrustHistoryMapper` + comparator |

Mapper produz artefacto history com comparable JSON. History **não** reexecuta evaluation.

---

## Dashboard

Secções read-only em `cryptographic_trust_section_builders.dart`:

| Secção | Conteúdo |
|--------|----------|
| `cryptographicTrustSummary` | Status, verified count, limitations |
| `cryptographicTrustVerification` | Resultados de verificação |
| `cryptographicTrustSignatures` | Resumo de assinaturas |
| `cryptographicTrustPolicies` | Policies aplicadas |

Dashboard **não** invoca evaluate — consome snapshot injetado ou de sources.

---

## Observability

| Componente | Tipo |
|------------|------|
| Observability | `TelemetryComponent.cryptographicTrust` |

`ObservableCryptographicTrustProvider` (opt-in):

- Emite telemetry sanitizada — **sem** payloads, digests, signature values ou keys
- Observability **não** altera payload de evaluate
- Default disabled no bootstrap standard

---

## Replay

Replay suportado quando:

- Mesma policy (ID + versão) com mesmas fontes
- Mesmo `requestedAt` no request
- Material coletado equivalente

Fingerprints estáveis:

- `snapshot.fingerprint`
- `metadata.subjectsFingerprint`, `signaturesFingerprint`, etc.
- `cryptographicTrustId`

Cenários cobertos (Parte 3 — mínimo 15):

1. Subject com digest
2. Subject sem payload
3. Assinatura válida / inválida / unsupported
4. Attestation válida / parcial
5. Key revogada
6. Transparency reference estrutural
7. Policy satisfeita / não satisfeita
8. Snapshot partial / failed / conflicting
9. Sources em ordens diferentes

100 ciclos de re-evaluate em `cryptographic_trust_replay_test.dart`.

---

## Golden snapshots

Goldens versionados em `test/golden/cryptographic_trust/` (Parte 3):

1. `evaluation_request.json`
2. `resolved_sources.json`
3. `collected_trust_material.json`
4. `digest_result.json`
5. `signature_verification_valid.json`
6. `signature_verification_invalid.json`
7. `signature_verification_unsupported.json`
8. `attestation_verification_result.json`
9. `revocation_result.json`
10. `transparency_result.json`
11. `trust_chain.json`
12. `policy_evaluation_result.json`
13. `snapshot_verified.json`
14. `snapshot_partial.json`
15. `snapshot_failed.json`
16. `snapshot_conflicting.json`
17. `report.json`
18. `history_comparable_payload.json`

Goldens **não** incluem: private key, key handle, public key completa, payload completo, horário actual, IDs aleatórios.

---

## Procedimento de atualização de Golden Snapshots

1. Confirmar que a alteração de snapshot é **intencional** (mudança normativa, não bug)
2. Executar `dart test test/cryptographic_trust/cryptographic_trust_golden_test.dart`
3. Revisar diff dos ficheiros em `test/golden/cryptographic_trust/`
4. Atualizar goldens explicitamente: `dart run test --update-goldens test/cryptographic_trust/cryptographic_trust_golden_test.dart`
5. Verificar fingerprints estáveis em `cryptographic_trust_replay_test.dart`
6. Documentar motivo no PR/commit

Goldens **não** devem ser actualizados automaticamente durante CI.

---

## Security limitations

| Limitação | Impacto |
|-----------|---------|
| **Fingerprint ≠ assinatura** | Fingerprints são hashes de JSON canônico — não provam origem criptográfica |
| **Verified ≠ release auth** | Status verified não autoriza progressão de release |
| **InMemoryEd25519 non-production** | Chaves em memória de processo — inaceitável para produção |
| **Dart sem zeroização garantida** | Private keys podem permanecer em memória após GC |
| **Sem KMS/HSM** | Nenhuma protecção hardware de chaves |
| **Sem rede** | Sem OCSP, CRL, transparency logs remotos |
| **Sem persistência** | Store in-memory — snapshots perdidos entre processos |
| **Policies candidate** | Não promovidas a `active` sem AR dedicado |
| **Signing explícito apenas** | `evaluate()` nunca assina — evita side-effects ocultos |

Evidência: `cryptographic_trust_security_test.dart`, `cryptographic_trust_operational_security_test.dart`, `cryptographic_trust_architecture_boundary_test.dart`.

---

## Performance baseline

Baselines registados em `cryptographic_trust_performance_test.dart` (Parte 3):

| Operação | Threshold orientativo |
|----------|----------------------|
| `evaluate()` passing snapshot | Documentado no teste |
| `evaluate()` × 100 subjects | Stress test |
| Digest SHA-256 batch | Primitives audit |
| Signature verify batch | Primitives audit |
| Store query 1000 snapshots | Store hardening |

Performance não é SLA de produção — referência para regressão local.

---

## Dependency review

| Dependência | Versão (lockfile) | Uso | Superfície |
|-------------|-------------------|-----|------------|
| `crypto` | 3.0.7 | SHA-256 digest, canonical fingerprint | `adapters/`, `canonical_serializer` |
| `cryptography` | 2.9.0 | Ed25519 sign/verify | `adapters/` apenas |

Verificações (Parte 3):

- Tipos concretos das bibliotecas **não** vazam para APIs públicas de models
- Domain models isolados de imports crypto
- Interfaces sem dependência de packages crypto
- Nenhuma dependência de rede adicionada

---

## Exemplos de uso seguro

### Avaliação com material injetado

```dart
final stack = CryptographicTrustOperationalFixtures.createTestStack();
await stack.registerTestKeys();

final result = await stack.provider.evaluate(
  CryptographicTrustOperationalFixtures.evaluationRequest(),
);

expect(result.snapshot, isNotNull);
expect(result.snapshot!.fingerprint, isNotEmpty);
expect(result.snapshot!.limitations, contains('no-release-authorization'));
expect(result.snapshot!.warnings, contains('verified-does-not-authorize-release'));
```

### Verificação ad-hoc (sem publicar)

```dart
final verifyResult = await provider.verifySignature(
  envelope: signatureEnvelope,
  subjectBytes: artifactBytes,
  projectId: 'masterpalm-demo',
);

expect(verifyResult?.status, isNot(CryptographicVerificationStatus.invalid));
// verified ainda não autoriza release
```

### Signing explícito (testes only)

```dart
// Requer InMemoryEd25519SigningKeyProvider — NON-PRODUCTION
final signResult = await provider.sign(
  keyReference: keyRef,
  digestBytes: digestBytes,
  template: envelopeTemplate,
);
expect(signResult.outcome, CryptographicPrimitiveOutcome.valid);
```

### Replay determinístico

```dart
final a = await provider.evaluate(request);
final b = await provider.evaluate(request);
expect(a.snapshot!.fingerprint, b.snapshot!.fingerprint);
```

---

## Limitações (Sprint 05.2)

| Limitação | Impacto |
|-----------|---------|
| Políticas **candidate** | Selecção explícita obrigatória |
| Store **in-memory** | Sem persistência entre processos |
| **Sem KMS/HSM** | Signing produtivo não suportado |
| **Sem rede** | Sem OCSP, CRL, Rekor, Sigstore |
| **InMemoryEd25519** | Signing apenas para testes |
| **Verified ≠ autorização** | Release Governance inalterado |
| Observability default **disabled** | Telemetry só com bootstrap habilitado |
| RSA/ECDSA | Não implementados nesta sprint |
| X.509 path building | Não implementado |

---

## Roadmap

1. Promoção candidate → active após AR dedicado
2. Store persistente (Firestore ou equivalente) com backup e CAS
3. KMS/HSM adapters opt-in (AWS KMS, GCP KMS, PKCS#11)
4. RSA/ECDSA adapters opt-in
5. Transparency log remoto opt-in (Rekor-compatible)
6. OCSP/CRL opt-in para revocation
7. Key rotation e lifecycle management
8. Signing produtivo com HSM — **substituir** InMemoryEd25519
9. Políticas v1.1 com requisitos adicionais de supply chain
10. Integração normativa com Release Governance (leitura only — sem auto-authorize)

---

## Testes

| Área | Ficheiro |
|------|----------|
| Models/validators (Parte 1) | `cryptographic_trust_models_test.dart`, `cryptographic_trust_validators_test.dart` |
| Serialização (Parte 1) | `cryptographic_trust_serialization_test.dart` |
| Operacional (Parte 2) | `cryptographic_trust_provider_test.dart`, `cryptographic_trust_e2e_test.dart` |
| Primitives (Parte 2) | `cryptographic_trust_primitives_test.dart`, `cryptographic_trust_services_test.dart` |
| Integração (Parte 2) | `cryptographic_trust_integration_test.dart`, `cryptographic_trust_platform_core_test.dart` |
| Replay (Parte 3) | `cryptographic_trust_replay_test.dart` |
| Golden (Parte 3) | `cryptographic_trust_golden_test.dart` |
| Serialization audit (Parte 3) | `cryptographic_trust_serialization_audit_test.dart` |
| Identity audit (Parte 3) | `cryptographic_trust_identity_audit_test.dart` |
| Primitives audit (Parte 3) | `cryptographic_trust_primitives_audit_test.dart` |
| Security (Parte 1–3) | `cryptographic_trust_security_test.dart`, `cryptographic_trust_operational_security_test.dart` |
| Architecture boundaries | `cryptographic_trust_architecture_boundary_test.dart` |

**Baseline antes da Parte 3:** 382 testes em `test/cryptographic_trust/`.
**Após Parte 3 (hardening):** suite expandida — ver Release Checklist e AR-018.

---

## Documentação relacionada

- [ADR-032](../adr/ADR-032-cryptographic-trust-operational-architecture-and-security-boundaries.md)
- [AR-018](../architecture-reviews/AR-018-cryptographic-trust-framework.md)
- [Release Checklist](cryptographic_trust_release_checklist.md)
- [ADR-031 CI/CD Integration](../adr/ADR-031-cicd-integration-operational-architecture-and-hardening.md)
- [ADR-030 Release Supply Chain](../adr/ADR-030-release-supply-chain-and-provenance-framework.md)
