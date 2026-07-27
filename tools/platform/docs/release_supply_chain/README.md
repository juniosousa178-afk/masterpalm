# Release Supply Chain — Guia de Uso

**Pacote:** `masterpalm_platform`
**Sprint:** 05.0 — Release Supply Chain and Provenance Framework
**Políticas candidatas:** `supply-chain-v1`, `distribution-v1`, `compliance-v1`

## Objetivo

Release Supply Chain consolida, estrutura e publica **artefatos já publicados** de release:

- `QualityGateSnapshot` (decisão técnica de qualidade)
- `ReleaseDecisionSnapshot` (autorização de progressão de release)
- `ReleaseEvidenceBundle` (evidências e attestations)
- Provenance, grafo de supply chain, SBOM, registo de artefatos, distribuição e compliance

O domínio **não recalcula** Quality Gate, Release Governance, Release Evidence nem engines de origem.

Use Release Supply Chain para:

- Produzir snapshots auditáveis com fingerprints determinísticos
- Montar provenance, grafo, SBOM e registo de artefatos estruturalmente
- Avaliar compliance estrutural (sem autorizar release)
- Integrar supply chain em Report, History, Dashboard e Observability
- Suportar replay e comparação de snapshots equivalentes

**Importante:** `ComplianceResult` descreve conformidade estrutural — **não** autoriza release nem substitui Release Governance.

---

## Arquitetura

```
ReleaseSupplyChainRequest
       │
       ▼
PlatformReleaseSupplyChainProvider
       │
       ├── PolicyRegistry (supply chain / distribution / compliance)
       │
       ├── ReleaseSupplyChainSourceResolver     ← injected | byId | latest (opt-in)
       │        ├── QualityGateProvider.load/latest (NÃO evaluate)
       │        ├── ReleaseGovernanceProvider.load/latest (NÃO evaluate)
       │        └── ReleaseEvidenceProvider.load/latest (NÃO evaluate)
       │
       ├── ReleaseSupplyChainCollector          ← dedup por artifactId
       │
       ├── ReleaseSupplyChainSnapshotBuilder  ← ordering determinístico
       │        ├── ReleaseProvenanceBuilder
       │        ├── SupplyChainGraphBuilder
       │        ├── SbomBuilder
       │        ├── ArtifactRegistryBuilder
       │        ├── DistributionBuilder
       │        └── ComplianceEngine
       │
       ├── CanonicalSerializer + IdentityBuilder
       │
       └── ReleaseSupplyChainStore (in-memory nesta sprint)
```

| Camada | Responsabilidade |
|--------|------------------|
| `ReleaseSupplyChainProvider` | Orquestração, IO, publicação |
| `ReleaseSupplyChainSourceResolver` | Resolve fontes sem recalcular origem |
| `ReleaseSupplyChainCollector` | Coleta e deduplica artefatos |
| `ReleaseSupplyChainSnapshotBuilder` | Monta snapshot com ordering canônico |
| `ComplianceEngine` | Avalia regras estruturais — nunca aprova release |
| `ReleaseSupplyChainStore` | Persistência de snapshots publicados |

### Bootstrap

```dart
ReleaseSupplyChainPlatformBootstrap.register(registry: providerRegistry);
final rsc = registry.resolve<ReleaseSupplyChainProvider>();
```

Pré-requisitos: `QualityGateProvider`, `ReleaseGovernanceProvider` e `ReleaseEvidenceProvider` registados para resolução por ID/latest.

---

## Pipeline

1. **Resolve** — políticas e fontes (injected > byId > latest)
2. **Collect** — artefatos publicados, deduplicados por `artifactId`
3. **Build** — provenance, grafo, SBOM, registo, distribuição, compliance
4. **Validate** — validação estrutural agregada do snapshot
5. **Serialize** — JSON canônico e fingerprints
6. **Publish** (opcional) — gravação idempotente no store

`evaluate()` não publica. `evaluateAndPublish()` publica após validação.

---

## Conceitos

### Snapshot vs Compliance vs Provenance

| Artefato | Significado |
|----------|-------------|
| `ReleaseSupplyChainSnapshot` | Consolidação normativa de provenance, grafo, SBOM, artefatos, distribuição e compliance |
| `SupplyChainRecord` | Grafo de estágios, atores e evidências da cadeia |
| `SoftwareBillOfMaterials` | Inventário estrutural de componentes |
| `ComplianceResult` | Resultado de conformidade estrutural — **não** é autorização de release |

### Modos de resolução

| Modo | Precedência |
|------|-------------|
| `injected` | Objeto no request — sempre vence |
| `byId` | `load(id)` no provider de origem |
| `latest` | Apenas com `useLatest: true` |

O resolver **nunca** chama `evaluate()` em QG, RG ou RE.

---

## Exemplos

### Avaliação com snapshots injetados

```dart
final core = PlatformBootstrap.forRepo(repoPath);

final rg = await core.releaseGovernance().evaluate(passingRgRequest);
final re = await core.releaseEvidence().evaluate(passingReRequest);
final result = await core.releaseSupplyChain().evaluate(
  ReleaseSupplyChainRequest(
    releaseContext: context,
    qualityGateSnapshot: qgSnapshot,
    releaseDecisionSnapshot: rg.snapshot,
    releaseEvidenceBundle: re.bundle,
    referenceTime: '2026-07-22T12:00:00.000Z',
  ),
);

expect(result.snapshot, isNotNull);
expect(result.snapshot!.fingerprint, isNotEmpty);
```

### Publicação e consulta

```dart
final published = await provider.evaluateAndPublish(request);
await provider.load(published.snapshot!.metadata.supplyChainSnapshotId);

final latest = await provider.latest(
  projectId: 'masterpalm-demo',
);
```

### Replay determinístico

```dart
final a = await provider.evaluate(request);
final b = await provider.evaluate(request);

expect(a.snapshot!.fingerprint, b.snapshot!.fingerprint);
expect(a.snapshot!.metadata.graphFingerprint, b.snapshot!.metadata.graphFingerprint);
```

---

## Replay

Replay é suportado quando:

- Mesma política (ID + versão) para supply chain, distribution e compliance
- Mesmas fontes resolvidas (snapshots publicados equivalentes)
- Mesmo `referenceTime`

Fingerprints estáveis:

- `snapshot.fingerprint`
- `metadata.graphFingerprint`, `sbomFingerprint`, `registryFingerprint`
- `metadata.distributionFingerprint`, `complianceFingerprint`
- Componentes ordenados deterministicamente

Evidência: `test/release_supply_chain/release_supply_chain_replay_test.dart`, `release_supply_chain_golden_test.dart`.

---

## Limitações (Sprint 05.0)

| Limitação | Impacto |
|-----------|---------|
| Políticas **candidate** | Não promovidas a `active` sem AR |
| Store **in-memory** | Sem persistência entre processos |
| **Sem criptografia** | Digests são placeholders estruturais |
| **Compliance estrutural** | `compliant` ≠ autorização de release |
| **Sem CI/CD** | Enforcement manual |
| Observability default **disabled** | Telemetry só com bootstrap habilitado |

---

## Troubleshooting

| Sintoma | Causa provável | Ação |
|---------|----------------|------|
| `publicationStatus: skipped` após publish | Snapshot já publicado com mesmo fingerprint | Comportamento esperado (idempotência) |
| QG/RG/RE ausente | Fonte não injetada e ID/latest não resolvido | Injetar snapshot ou publicar no store de origem |
| Fingerprints diferentes entre replays | `referenceTime` ou fontes diferentes | Normalizar inputs |
| `latest` não resolve | `useLatest: false` (default) | Definir `useLatest: true` explicitamente |
| Compliance `nonCompliant` | Regra estrutural falhou | Revisar `ComplianceEngine` e evidências |
| Golden test falha | Snapshot intencional desatualizado | Atualizar `test/golden/release_supply_chain/*.json` explicitamente |

---

## Testes

| Área | Ficheiro |
|------|----------|
| Replay | `release_supply_chain_replay_test.dart` |
| Golden snapshots | `release_supply_chain_golden_test.dart` |
| Serialização | `release_supply_chain_serialization_audit_test.dart` |
| Identidade | `release_supply_chain_identity_audit_test.dart` |
| Provider/Store hardening | `release_supply_chain_hardening_test.dart` |
| Stress/Performance | `release_supply_chain_stress_test.dart`, `release_supply_chain_performance_test.dart` |
| Security | `release_supply_chain_security_test.dart` |

Goldens: `test/golden/release_supply_chain/passing_snapshot.json`, `supply_chain_graph.json`, `sbom.json`, `artifact_registry.json`, `distribution.json`, `compliance.json`.

---

## Documentação relacionada

- [ADR-030](../adr/ADR-030-release-supply-chain-and-provenance-framework.md)
- [AR-016](../architecture-reviews/AR-016-release-supply-chain-foundation.md)
- [Release Checklist](release_supply_chain_release_checklist.md)
- [ADR-029 Release Evidence](../adr/ADR-029-release-evidence-and-attestation-foundation.md)
