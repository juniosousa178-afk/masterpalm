# Release Governance — Guia de Uso

**Pacote:** `masterpalm_platform`
**Sprint:** 04.2 — Release Governance Foundation
**Políticas candidatas:** `release-governance-v1`, `release-governance-v1.1`

## Objetivo

Release Governance autoriza ou bloqueia a **progressão de release** com base em evidências **já publicadas**:

- `QualityGateSnapshot` (decisão técnica de qualidade)
- Contexto de release (projeto, commit, ambiente, tipo)
- Conjuntos de aprovação e waiver

O domínio **não recalcula** o Quality Gate nem qualquer engine de origem (Metrics, Score, MES, Guardian).

Use Release Governance para:

- Autorizar ou rejeitar tecnicamente uma release
- Produzir snapshots auditáveis com fingerprints determinísticos
- Integrar decisões em Report, History, Dashboard e Observability
- Modelar aprovações, waivers e condições de release

---

## Arquitetura

```
Request → Provider → SourceResolver → Engine → ReleaseDecisionSnapshot
                         ↑                    ↓
                   QG snapshot            Store (opcional)
                   (publicado)
                   aprovações/waivers
```

| Camada | Responsabilidade |
|--------|------------------|
| `ReleaseGovernanceProvider` | Orquestração, IO, publicação |
| `ReleaseGovernanceSourceResolver` | Resolve fontes (injected / byId / latest) |
| `ReleaseGovernanceEngine` | Avaliação stateless da política |
| `ReleaseGovernanceStore` | Persistência de snapshots (in-memory nesta sprint) |

### Bootstrap

```dart
ReleaseGovernancePlatformBootstrap.register(registry: providerRegistry);
final rg = registry.resolve<ReleaseGovernanceProvider>();
```

Pré-requisitos: `QualityGateProvider` registado (para resolução de snapshots por ID/latest). Para Observability: `TelemetryInstrumentation` via decorator.

---

## Conceitos

### Policy vs Decision

- **Policy** (`ReleaseGovernancePolicy`) — conjunto imutável de rule sets, regras (RG001–RG020), requisitos de aprovação, waiver rules e governança
- **Decision** (`ReleaseGovernanceDecision`) — resultado normativo: `approved`, `approvedWithConditions`, `rejected`, `pending`, `unavailable`, `incompatible`, `expired`, `cancelled`, `error`

### Result status vs Release decision

| `ReleaseGovernanceResultStatus` | Significado |
|---------------------------------|-------------|
| `success` | Avaliação concluída (decisão pode ser `approved` ou `rejected`) |
| `partial` | Decisão parcial |
| `unavailable` | Fontes obrigatórias indisponíveis |
| `incompatible` | Artefatos incompatíveis |
| `failure` | Erro de engine ou validação — **não** é reprovação normativa |

**Importante:** `decision: rejected` com `status: success` é comportamento correto — a release foi reprovada, mas a operação funcionou.

### Eligibility, compatibility, coverage

- **Eligibility** — fontes obrigatórias (Quality Gate, contexto, aprovações) disponíveis para avaliação
- **Compatibility** — coerência entre artefatos (projeto, commit, policy do QG, schema)
- **Coverage** — percentagem de regras avaliadas vs total normativo

### Quality Gate como evidência

Release Governance **consome** o snapshot publicado do Quality Gate:

- Referencia `qualityGateSnapshotId` e fingerprint no metadata do snapshot
- Regras RG003–RG008 leem `decision`, `compatibility`, `eligibility`, `coverage`, `age`
- Nunca invoca `QualityGateProvider.evaluate()`

---

## Políticas disponíveis

| Policy ID | Versão | RG006 | Quando usar |
|-----------|--------|-------|-------------|
| `release-governance-v1` | 1 | `isValid` | Baseline; compatibilidade histórica |
| `release-governance-v1.1` | 2 | `isEligible` | Elegibilidade normativa do QG |

Ambas permanecem **candidate** até Architecture Review de promoção.

---

## Resolução de fontes

| Fonte | Modos | Notas |
|-------|-------|-------|
| `releaseContext` | injected | Obrigatório |
| `qualityGateSnapshot` | injected, byId, latest | `latest` requer `useLatest: true` |
| `approvalSet` | injected | Obrigatório para avaliação completa |
| `waiverSet` | injected | Opcional |
| `releaseGovernancePolicy` | registry ou inline | Via `policyId` + `policyVersion` |

`latest` **nunca** é implícito para Quality Gate.

---

## Request básico

```dart
final request = ReleaseGovernanceRequest(
  releaseContext: ReleaseContext(
    projectId: 'my-project',
    commitId: 'abc123',
    branch: 'main',
    version: '1.2.0',
    environment: ReleaseEnvironment.staging,
    releaseType: ReleaseType.releaseCandidate,
    requestedBy: 'release-manager@example.com',
    targetDate: '2026-07-21T18:00:00.000Z',
    artifacts: [
      ReleaseArtifact(
        artifactId: 'app-bundle-1.2.0',
        artifactType: 'apk',
        uri: 'gs://bucket/app-1.2.0.apk',
      ),
    ],
  ),
  policyId: 'release-governance-v1',
  policyVersion: 1,
  qualityGateSnapshot: qgSnapshot,       // injected (recomendado)
  approvalSet: productionApprovalSet,
  waiverSet: activeWaivers,              // opcional
  referenceTime: '2026-07-21T10:00:01.000Z',
);
```

---

## Avaliação sem publicação

```dart
final result = await provider.evaluate(request);

print(result.status);              // success | partial | ...
print(result.snapshot?.decision);  // approved | rejected | pending | ...
```

`evaluate()` **não grava** no store.

---

## Avaliação com publicação

```dart
final result = await provider.evaluateAndPublish(request);
// snapshot validado e persistido (idempotente por snapshot ID)
```

Publicação repetida com mesmo conteúdo retorna o snapshot existente.

---

## Consulta ao store

```dart
final snapshot = await provider.load('rg-snapshot-id');

final latest = await provider.latest(
  projectId: 'my-project',
  policyId: 'release-governance-v1',
);

final history = await provider.query(ReleaseGovernanceQuery(
  projectId: 'my-project',
  decision: ReleaseGovernanceDecision.rejected,
  limit: 10,
));
```

---

## Geração de report

O Report consome snapshot publicado — **não executa** Release Governance:

```dart
final report = await reportEngine.generate(ReportRequest(
  reportType: ReportType.releaseGovernance,
  projectId: 'my-project',
  releaseDecisionSnapshot: snapshot.toJson(),
));
```

Fonte: `ReleaseGovernanceReportSource.fromSnapshot(snapshot)`.

---

## Uso em Dashboard

O Dashboard exibe secção Release Governance a partir de snapshot **injetado** ou resolvido por ID/latest. O `ReleaseGovernanceSectionBuilder` **não chama** `evaluate()`.

```dart
DashboardRequest(
  projectId: 'my-project',
  releaseDecisionSnapshot: rgSnapshot,  // injected
);
```

Widgets expostos: decision, release info, environment, release type, policy version, quality gate reference, pending approvals, active waivers, open conditions, coverage, compatibility, eligibility.

---

## Integração com History

`ReleaseGovernanceHistoryMapper` converte snapshots em `HistoryArtifact` tipo `releaseGovernance` e compara decisões, policy version e coverage entre versões. O History permanece responsável pelo diff — Release Governance não executa History.

```dart
final artifact = ReleaseGovernanceHistoryMapper().fromMap(snapshot.toJson());
// HistoryArtifactType.releaseGovernance
```

---

## Observability

`ObservableReleaseGovernanceProvider` instrumenta operações com `TelemetryComponent.releaseGovernance` sem alterar resultados.

Operações instrumentadas: `evaluate`, `evaluateAndPublish`, `publish`, `load`, `latest`, `query`, `invalidate`.

---

## Regras da política candidate (resumo)

| Rule set | Regras | Foco |
|----------|--------|------|
| `release-integrity` | RG001–RG002 | Consistência projeto/commit |
| `technical-gate` | RG003–RG008 | Quality Gate (decisão, compat, elegibilidade, coverage, freshness) |
| `environment-governance` | RG009–RG010 | Ambiente e tipo de release |
| `approval-governance` | RG011–RG014 | Aprovações obrigatórias, rejeições, SoD, expiração |
| `waiver-governance` | RG015–RG017 | Waivers inválidos, expirados, limites |
| `evidence-integrity` | RG018–RG019 | Evidência de aprovação e waiver |
| `final-authorization` | RG020 | Artefatos de release (optional) |

Ver matriz completa em `release_governance_traceability_matrix.md`.

---

## Exemplos de decisão

### Approved

Quality Gate `passed`, aprovações completas, sem violações críticas.

```
decision: approved
status: success
blockingFailureCount: 0
```

### Approved with conditions

Waivers válidos ou aprovações com condições pendentes de follow-up.

```
decision: approvedWithConditions
status: success
openConditionCount: 1
```

### Rejected

Quality Gate `failed` ou aprovação rejeitada.

```
decision: rejected
status: success          ← operação OK, release reprovada
failedRuleCount: 1
```

### Pending

Aprovações obrigatórias em falta.

```
decision: pending
status: success
missingApprovalCount: 2
```

### Unavailable

Quality Gate snapshot ausente.

```
decision: unavailable
status: unavailable
```

---

## Limitações da sprint

| Limitação | Código | Impacto |
|-----------|--------|---------|
| Políticas candidate | `ReleaseGovernancePolicyStatus.candidate` | Não normativas para produção |
| Store in-memory | `InMemoryReleaseGovernanceStore` | Sem persistência entre processos |
| Sem crypto auth | `authorityNotCryptographicallyVerified` | Aprovações estruturais apenas |
| RG006 v1 `isValid` | `release_governance_policy_v1.dart` | Usar v1.1 para `isEligible` |
| Sem CI/CD | `noCiCdEnforcement` | Enforcement manual |

---

## Referências

| Documento | Conteúdo |
|-----------|----------|
| `release_governance_traceability_matrix.md` | Matriz RG001–RG020 e integrações |
| `release_governance_release_checklist.md` | Checklist de release |
| `../adr/ADR-028-release-governance-authorizes-release-progression.md` | ADR arquitetural |
| `../architecture-reviews/AR-014-release-governance-foundation.md` | Architecture Review |
| `../adr/ADR-027-quality-gates-are-deterministic-policy-evaluations.md` | ADR upstream (Quality Gate) |
| `../quality_gate/README.md` | Guia do Quality Gate |

---

## Fora de escopo (Sprint 04.2)

- CI/CD integration e pipeline enforcement
- Persistência em banco
- Assinatura criptográfica de aprovações
- Políticas remotas / YAML externo
- Frontend de governança de release
- Promoção automática candidate → active
- Consumo automático de waivers no store
