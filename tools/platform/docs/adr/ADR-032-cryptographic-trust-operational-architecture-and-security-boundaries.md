# ADR-032: Cryptographic Trust Operational Architecture and Security Boundaries

| Campo | Valor |
|-------|-------|
| **Status** | Accepted (pending formal sign-off in AR-018) |
| **Data** | 2026-07-22 |
| **Sprint** | 05.2 — Cryptographic Trust Framework |
| **Decisores** | MasterPalm Engineering Governance |
| **Domínio** | `tools/platform` — Cryptographic Trust |

---

## Contexto

A MasterPalm Engineering Platform publica decisões normativas em camadas:

- **Quality Gate** (ADR-027) — evidência técnica de qualidade
- **Release Governance** (ADR-028) — **única** autorização de progressão de release
- **Release Evidence** (ADR-029) — consolidação e verificação estrutural de evidências
- **Release Supply Chain** (ADR-030) — provenance, grafo, SBOM e compliance estrutural
- **CI/CD Integration** (ADR-031) — pipeline e deployment estrutural
- **History, Report, Dashboard, Observability** — leitura e diffs sem recálculo

Release exige uma camada que **verifique** integridade criptográfica de artefactos — digests, assinaturas, attestations, revocation e transparency — **sem** substituir Release Governance, **sem** KMS/HSM nesta sprint e **sem** contacto de rede.

Requisitos:

1. Consumir `ReleaseEvidenceBundle`, `ReleaseSupplyChainSnapshot` e `CicdIntegrationSnapshot` **publicados**
2. SHA-256 real e Ed25519 real via bibliotecas aprovadas, confinadas a adapters
3. Primitive interfaces vendor-neutral com Algorithm Registry
4. Key handles opacos — private key nunca serializada
5. Mesma policy + mesmas fontes → mesmo snapshot e fingerprints
6. **Verified ≠ autorização de release**
7. **Fingerprint de domínio ≠ assinatura digital**
8. Signing **explícito** — `evaluate()` nunca assina
9. Integrações transparentes com Report, History, Dashboard e Observability

---

## Problema

Sem fronteiras explícitas, consumidores podem confundir:

- Fingerprint SHA-256 de JSON canônico com prova criptográfica de origem
- Status `verified` com autorização de release
- Signing de testes (`InMemoryEd25519SigningKeyProvider`) com produção
- Verificação matemática válida com trust level elevado automático

A plataforma precisa de verificação criptográfica real **limitada** a SHA-256 + Ed25519, offline, sem persistência, preparada para evolução futura (KMS, transparency remota) sem expandir escopo prematuramente.

---

## Decisão

Implementamos Cryptographic Trust como **pipeline determinístico** sobre **material declarado e publicado**, com três políticas candidate:

| Política | ID | Versão |
|----------|-----|--------|
| Artifact Signature Trust | `artifact-signature-trust-v1` | 1 |
| Attestation Trust | `attestation-trust-v1` | 1 |
| Release Trust | `release-trust-v1` | 1 |

### Princípios centrais

1. **Consumir, não recalcular**
   `CryptographicTrustSourceResolver` usa `load`/`latest` de RE, RSC e CI/CD Integration. **Nunca** invoca `evaluate()`, `evaluateAndPublish()` ou `publish()` upstream.

2. **Primitive interfaces vendor-neutral**
   Adapters concretos (`Sha256DigestProvider`, `Ed25519Signer`, `Ed25519SignatureVerifier`) registados em `CryptographicAlgorithmRegistry`. Provider **sem** switch por algoritmo.

3. **SHA-256 via `package:crypto`**
   Digest real sobre bytes de subject. Fingerprints de domínio via SHA-256 de JSON canônico — **distintos** de assinaturas digitais.

4. **Ed25519 via `package:cryptography`**
   Sign/verify real confinado a `lib/cryptographic_trust/adapters/`. Domain models **não** importam a biblioteca.

5. **Isolamento de `package:cryptography`**
   Tipos concretos (`SimpleKeyPair`, `Ed25519`) permanecem em adapters e handles in-memory. APIs públicas expõem apenas envelopes, descriptors e outcomes.

6. **Key handles opacos**
   `OpaqueCryptographicSigningKeyHandle` — sem `toJson`, sem fingerprint, sem equality pública de material privado. Dart **não** garante zeroização completa.

7. **Signing explícito**
   `CryptographicSigningService` + `sign()` no provider. Bootstrap default **sem** signing key provider. `evaluate()` **nunca** assina.

8. **Verification sem elevação automática de trust**
   Assinatura matematicamente válida não eleva trust level — derivação via policy evaluation e engine.

9. **Trust policy declarativa**
   `CryptographicTrustPolicyEvaluationService` avalia requisitos estruturais. Policy result **não** altera Release Governance.

10. **Separação de Release Governance**
    Engine inclui warnings `verified-does-not-authorize-release` e limitations `no-release-authorization`. Nenhum ficheiro em `release_governance` referencia cryptographic trust.

11. **Canonical serialization + identity**
    `CryptographicTrustCanonicalSerializer` + `CryptographicTrustIdentityBuilder` — fingerprints determinísticos, campos transitórios excluídos.

12. **Store in-memory**
    `InMemoryCryptographicTrustStore` — idempotência por fingerprint, sem persistência entre processos.

13. **Observability sanitizada**
    `ObservableCryptographicTrustProvider` — sem payloads, digests, signature values ou keys em telemetry.

14. **Modos de resolução**
    Precedência: `injected` > `byId` > `latest` (opt-in via `useLatest: true`).

---

## Arquitetura

```
CryptographicTrustEvaluationRequest
       │
       ▼
PlatformCryptographicTrustProvider
       │
       ├── CryptographicTrustPolicyRegistry
       ├── CryptographicAlgorithmRegistry
       ├── CryptographicTrustSourceResolver
       │        ├── ReleaseEvidenceProvider (load/latest)
       │        ├── ReleaseSupplyChainProvider (load/latest)
       │        └── CicdIntegrationProvider (load/latest)
       ├── CryptographicTrustCollector
       ├── CryptographicDigestService
       ├── CryptographicSignatureVerificationService
       ├── CryptographicAttestationVerificationService
       ├── CryptographicRevocationEvaluator
       ├── CryptographicTransparencyEvaluator
       ├── CryptographicTrustChainBuilder
       ├── CryptographicTrustPolicyEvaluationService
       ├── CryptographicTrustEngine
       ├── CryptographicTrustSnapshotBuilder
       ├── CryptographicSigningService (opt-in)
       ├── CanonicalSerializer + IdentityBuilder
       └── CryptographicTrustStore
```

---

## Alternativas rejeitadas

| Alternativa | Motivo da rejeição |
|-------------|-------------------|
| KMS/HSM nesta sprint | Complexidade operacional; fora de escopo Sprint 05.2 |
| RSA/ECDSA nesta sprint | Escopo limitado a Ed25519; extensível via registry futuro |
| Implementação criptográfica manual | Risco de segurança; bibliotecas auditadas preferidas |
| Signing implícito em evaluate | Side-effects ocultos; viola princípio explicit-signing |
| Verified como autorização de release | Sobrepõe Release Governance |
| OCSP/CRL/Rekor nesta sprint | Requer rede; fora de escopo |
| Store persistente nesta sprint | In-memory suficiente para fundação |
| Promoção automática candidate→active | Requer AR dedicado |
| HMAC como assinatura digital | Semântica incorrecta; não implementado |
| X.509 path building | Complexidade prematura; trust chains declarativas suficientes |
| Provider com switch por algoritmo | Impede extensão via registry; viola vendor-neutral |

---

## Riscos

| Risco | Severidade | Mitigação |
|-------|------------|-----------|
| Confusão fingerprint vs assinatura | Alta | Documentação + testes + warnings explícitos |
| Confusão verified vs release auth | Alta | Engine warnings/limitations + ADR/README |
| InMemoryEd25519 usado em produção | Alta | Documentação non-production + bootstrap sem key provider |
| Dart sem zeroização de chaves | Média | Documentação + handles opacos + sem serialização |
| Policies candidate mal interpretadas | Média | Selecção explícita + AR antes de promoção |
| Store in-memory | Média | AR futuro para persistência |
| Dependência `cryptography` | Baixa | Confinada a adapters; dependency review Parte 3 |

---

## Limitações

- Políticas permanecem **candidate** até Architecture Review de promoção
- Store **in-memory** — sem persistência entre processos
- **Sem KMS/HSM** — `InMemoryEd25519SigningKeyProvider` non-production only
- **Sem rede** — sem OCSP, CRL, Rekor, Sigstore, HTTP
- **Sem persistência física** — snapshots perdidos entre processos
- RSA/ECDSA **não implementados** nesta sprint
- X.509 path building **não implementado**
- Revocation e transparency **declarativos/offline**
- Dart **não garante** zeroização completa de memória
- **Verified ≠ autorização** de release ou deployment
- **Fingerprint ≠ assinatura** digital
- Observability desabilitada por default no bootstrap standard

**KMS/HSM, integração remota e persistência física não fazem parte da Sprint 05.2.**

---

## Consequências

### Positivas

- Verificação SHA-256 e Ed25519 real com fronteiras auditáveis
- Replay determinístico validável com golden snapshots (Parte 3)
- Separação clara entre verificação criptográfica e autorização de release
- Integração consistente com padrão QG/RG/RE/RSC/CI/CD da plataforma
- 382+ testes baseline (Parts 1–2) antes de hardening Parte 3
- Algorithm Registry preparado para adapters futuros (RSA, KMS) sem acoplamento

### Negativas

- Consumidores devem entender verified ≠ release autorizada
- Signing produtivo requer adapters KMS/HSM futuros
- Store in-memory não adequado para produção multi-processo
- Sem enforcement automático via transparency logs remotos

---

## Critérios de evolução futura

1. Promoção candidate → active após AR dedicado
2. KMS/HSM adapters opt-in (substituir InMemoryEd25519)
3. Store persistente com backup e CAS
4. RSA/ECDSA adapters opt-in via Algorithm Registry
5. Transparency log remoto opt-in (Rekor-compatible)
6. OCSP/CRL opt-in para revocation
7. Key rotation e lifecycle management
8. Integração normativa com Release Governance (leitura only)
9. Políticas v1.1 com requisitos adicionais

---

## Referências

- ADR-027 — Quality Gate Foundation
- ADR-028 — Release Governance
- ADR-029 — Release Evidence and Attestation Foundation
- ADR-030 — Release Supply Chain and Provenance Framework
- ADR-031 — CI/CD Integration Operational Architecture and Hardening
- AR-018 — Architecture Review Cryptographic Trust Framework
- `docs/cryptographic_trust/README.md`
