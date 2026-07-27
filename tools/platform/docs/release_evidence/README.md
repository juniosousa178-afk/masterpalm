# Release Evidence — Guia de Uso

**Pacote:** `masterpalm_platform`
**Sprint:** 04.3 — Release Evidence and Attestation Foundation
**Políticas candidatas:** `release-evidence-v1`, `release-attestation-v1`, `release-verification-v1`

## Objetivo

Release Evidence consolida, atesta e verifica **evidências já publicadas** de release:

- `QualityGateSnapshot` (decisão técnica de qualidade)
- `ReleaseDecisionSnapshot` (autorização de progressão de release)
- Attestations estruturais (sem criptografia nesta sprint)
- Provenance e referências de fonte

O domínio **não recalcula** Quality Gate, Release Governance nem engines de origem.

Use Release Evidence para:

- Produzir bundles auditáveis com fingerprints determinísticos
- Verificar estruturalmente attestations e provenance
- Integrar evidências em Report, History, Dashboard e Observability
- Suportar replay e comparação de snapshots equivalentes

**Importante:** `ReleaseVerificationResult` descreve verificação estrutural — **não** autoriza release nem substitui Release Governance.

---

## Arquitetura

```
ReleaseEvidenceRequest
       │
       ▼
PlatformReleaseEvidenceProvider
       │
       ├── PolicyRegistry (evidence / attestation / verification)
       │
       ├── ReleaseEvidenceSourceResolver     ← injected | byId | latest (opt-in)
       │        ├── QualityGateProvider.load/latest (NÃO evaluate)
       │        └── ReleaseGovernanceProvider.load/latest (NÃO evaluate)
       │
       ├── ReleaseEvidenceCollector          ← dedup por artifactId
       │
       ├── ReleaseEvidenceBundleBuilder      ← ordering determinístico
       │
       ├── ReleaseAttestationEngine        ← validação estrutural
       │
       ├── ReleaseVerificationEngine       ← verificação estrutural
       │
       ├── CanonicalSerializer + IdentityBuilder
       │
       └── ReleaseEvidenceStore (in-memory nesta sprint)
```

| Camada | Responsabilidade |
|--------|------------------|
| `ReleaseEvidenceProvider` | Orquestração, IO, publicação |
| `ReleaseEvidenceSourceResolver` | Resolve fontes sem recalcular origem |
| `ReleaseEvidenceCollector` | Coleta e deduplica artefatos |
| `ReleaseEvidenceBundleBuilder` | Monta bundle com ordering canônico |
| `ReleaseAttestationEngine` | Valida attestations contra política |
| `ReleaseVerificationEngine` | Verifica bundle + attestations |
| `ReleaseEvidenceStore` | Persistência de bundles publicados |

### Bootstrap

```dart
ReleaseEvidencePlatformBootstrap.register(registry: providerRegistry);
final re = registry.resolve<ReleaseEvidenceProvider>();
```

Pré-requisitos: `QualityGateProvider` e `ReleaseGovernanceProvider` registados para resolução por ID/latest.

---

## Pipeline

1. **Resolve** — políticas e fontes (injected > byId > latest)
2. **Collect** — artefatos publicados, deduplicados por `artifactId`
3. **Build** — bundle com evidence ordenada, coverage, compatibility, eligibility
4. **Attest** — validação estrutural de attestations
5. **Verify** — verificação estrutural do bundle completo
6. **Serialize** — JSON canônico e fingerprints
7. **Publish** (opcional) — gravação idempotente no store

`evaluate()` não publica. `evaluateAndPublish()` publica após validação.

---

## Conceitos

### Bundle vs Verification vs Attestation

| Artefato | Significado |
|----------|-------------|
| `ReleaseEvidenceBundle` | Consolidação normativa de evidências + attestations + provenance |
| `ReleaseAttestationSet` | Conjunto de attestations estruturais |
| `ReleaseVerificationResult` | Resultado de verificação estrutural — **não** é autorização de release |

### Compatibility, eligibility, coverage

- **Compatibility** — coerência entre artefatos (projeto, commit, políticas, schema)
- **Eligibility** — fontes obrigatórias disponíveis para avaliação
- **Coverage** — contagens e percentagens de evidence, attestation e provenance

### Modos de resolução

| Modo | Precedência |
|------|-------------|
| `injected` | Objeto no request — sempre vence |
| `byId` | `load(id)` no provider de origem |
| `latest` | Apenas com `useLatest: true` |

O resolver **nunca** chama `evaluate()` em QG ou RG.

---

## Exemplos

### Avaliação com snapshots injetados

```dart
final core = PlatformBootstrap.forRepo(repoPath);

final rg = await core.releaseGovernance().evaluate(passingRgRequest);
final result = await core.releaseEvidence().evaluate(
  ReleaseEvidenceRequest(
    releaseContext: context,
    qualityGateSnapshot: qgSnapshot,
    releaseDecisionSnapshot: rg.snapshot,
    attestationSet: attestationSet,
    referenceTime: '2026-06-15T12:00:00.000Z',
  ),
);

expect(result.bundle, isNotNull);
expect(result.bundle!.fingerprint, isNotEmpty);
```

### Publicação e consulta

```dart
final published = await provider.evaluateAndPublish(request);
await provider.load(published.bundle!.metadata.bundleId);

final latest = await provider.latest(
  ReleaseEvidenceQuery(projectId: 'masterpalm-demo'),
);
```

### Replay determinístico

```dart
final a = await provider.evaluate(request);
final b = await provider.evaluate(request);

expect(a.bundle!.fingerprint, b.bundle!.fingerprint);
expect(a.verification!.fingerprint, b.verification!.fingerprint);
```

---

## Replay

Replay é suportado quando:

- Mesma política (ID + versão)
- Mesmas fontes resolvidas (snapshots publicados equivalentes)
- Mesmo `referenceTime`
- Mesmo conjunto de attestations/provenance

Fingerprints estáveis:

- `bundle.fingerprint`
- `verification.fingerprint`
- `attestationSet` ordering e IDs
- `coverage`, `compatibility`, `eligibility` derivados deterministicamente

Evidência: `test/release_evidence/release_evidence_replay_test.dart`, `release_evidence_golden_test.dart`.

---

## Limitações (Sprint 04.3)

| Limitação | Impacto |
|-----------|---------|
| Políticas **candidate** | Não promovidas a `active` sem AR |
| Store **in-memory** | Sem persistência entre processos |
| **Sem criptografia** | Assinaturas não verificadas criptograficamente |
| **Verificação estrutural** | `verified` ≠ autorização de release |
| **Sem CI/CD** | Enforcement manual |
| Observability default **disabled** | Telemetry só com bootstrap habilitado |

---

## Troubleshooting

| Sintoma | Causa provável | Ação |
|---------|----------------|------|
| `publicationStatus: null` após publish | Bundle inválido (evidence duplicada, coverage mismatch) | Verificar `ReleaseEvidenceBundleValidator` |
| QG/RG ausente | Fonte não injetada e ID/latest não resolvido | Injetar snapshot ou publicar no store de origem |
| Fingerprints diferentes entre replays | `referenceTime` ou attestations diferentes | Normalizar inputs |
| `latest` não resolve | `useLatest: false` (default) | Definir `useLatest: true` explicitamente |
| Verification `invalid` | Attestation/provenance incompleta | Revisar `ReleaseAttestationEngine` warnings |
| Golden test falha | Snapshot intencional desatualizado | Atualizar `test/golden/release_evidence/*.json` explicitamente |

---

## Testes

| Área | Ficheiro |
|------|----------|
| Replay | `release_evidence_replay_test.dart` |
| Golden snapshots | `release_evidence_golden_test.dart` |
| Serialização | `release_evidence_serialization_audit_test.dart` |
| Identidade | `release_evidence_identity_audit_test.dart` |
| Provider/Store hardening | `release_evidence_hardening_test.dart` |
| Stress/Performance | `release_evidence_stress_test.dart`, `release_evidence_performance_test.dart` |
| Security | `release_evidence_security_test.dart` |

Goldens: `test/golden/release_evidence/passing_bundle.json`, `passing_verification.json`, `valid_attestation_set.json`.

---

## Documentação relacionada

- [ADR-029](../adr/ADR-029-release-evidence-and-attestation-foundation.md)
- [AR-015](../architecture-reviews/AR-015-release-evidence-foundation.md)
- [Release Checklist](release_evidence_release_checklist.md)
- [ADR-028 Release Governance](../adr/ADR-028-release-governance-authorizes-release-progression.md)
