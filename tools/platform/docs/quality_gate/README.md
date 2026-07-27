# Quality Gates — Guia de Uso

**Pacote:** `masterpalm_platform`
**Sprint:** 04.1 — Quality Gates Foundation
**Política candidata:** `quality-gate-release-v1`

## Objetivo

Quality Gates avaliam se artefatos técnicos **já publicados** satisfazem uma **política de release** versionada. O gate **não recalcula** Metrics, Score, MES, Guardian nem qualquer outro engine de origem.

Use o gate para:

- Aprovar ou reprovar tecnicamente um conjunto de evidências
- Produzir snapshots auditáveis com fingerprints determinísticos
- Integrar decisões em Report, History, Dashboard e Observability

---

## Arquitetura

```
Request → Provider → SourceResolver → Engine → Snapshot
                         ↑                ↓
                   artefatos           Store (opcional)
                   publicados
```

| Camada | Responsabilidade |
|--------|------------------|
| `QualityGateProvider` | Orquestração, IO, publicação |
| `QualityGateSourceResolver` | Resolve fontes (injected / byId / latest) |
| `QualityGateEngine` | Avaliação stateless da política |
| `QualityGateStore` | Persistência de snapshots (in-memory nesta sprint) |

### Bootstrap

```dart
QualityGatePlatformBootstrap.register(registry: providerRegistry);
final gate = registry.resolve<QualityGateProvider>();
```

Pré-requisitos: `MetricsProvider`, `ScoreProvider`, `MESProvider`, `HistoryProvider`, `ObservabilityProvider`, `DashboardProvider` registados.

---

## Conceitos

### Policy vs Decision

- **Policy** (`QualityGatePolicy`) — conjunto imutável de rule sets, regras, thresholds e governança
- **Decision** (`QualityGateDecision`) — resultado normativo: `passed`, `failed`, `partial`, `unavailable`, `incompatible`, `error`

### Result status vs Gate decision

| `QualityGateResultStatus` | Significado |
|---------------------------|-------------|
| `success` | Avaliação concluída (decisão pode ser `passed` ou `failed`) |
| `partial` | Decisão `partial` |
| `unavailable` | Decisão `unavailable` |
| `incompatible` | Decisão `incompatible` |
| `failure` | Erro de engine ou validação — **não** é reprovação normativa |

**Importante:** `decision: failed` com `status: success` é comportamento correto — o gate reprovou, mas a operação funcionou.

### Eligibility, compatibility, coverage

- **Eligibility** — fontes obrigatórias disponíveis para avaliação
- **Compatibility** — coerência entre artefatos (projeto, schema, versão)
- **Coverage** — percentagem de regras avaliadas vs total normativo

---

## Resolução de fontes

Cada fonte (`metrics`, `guardian`, `score`, `mes`, `history`, `telemetry`, `dashboard`) resolve por precedência:

1. **injected** — snapshot/map no `QualityGateRequest`
2. **byId** — ID explícito no request
3. **latest** — apenas com `useLatest: true` (opt-in)

`latest` **nunca** é implícito. History aceita **somente** injeção.

---

## Request básico

```dart
final request = QualityGateRequest(
  projectId: 'my-project',
  policyId: 'quality-gate-release-v1',
  policyVersion: 1,
  commitId: 'abc123',           // opcional; QG002 usa quando presente
  createdAt: '2026-01-01T10:00:00.000Z',
  referenceTime: '2026-01-01T10:00:01.000Z',
  metricsSnapshot: metrics,     // injected
  guardianAnalysis: guardian,   // injected
  engineeringScoreSnapshot: score,
  mesSnapshot: mes,
  // telemetrySnapshot, historyDiff, dashboardSnapshot — opcionais
);
```

---

## Avaliação sem publicação

```dart
final result = await provider.evaluate(request);

print(result.status);              // success | partial | ...
print(result.snapshot?.decision);  // passed | failed | ...
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
final snapshot = await provider.load('qg-snapshot-id');

final latest = await provider.latest(
  projectId: 'my-project',
  policyId: 'quality-gate-release-v1',
);

final history = await provider.query(QualityGateQuery(
  projectId: 'my-project',
  decision: QualityGateDecision.failed,
  limit: 10,
));
```

---

## Geração de report

O Report consome snapshot publicado — **não executa** o Quality Gate:

```dart
final report = await reportEngine.generate(ReportRequest(
  reportType: ReportType.qualityGate,
  projectId: 'my-project',
  qualityGateSnapshot: snapshot.toJson(),
));
```

Fonte: `QualityGateReportSource.fromSnapshot(snapshot)`.

---

## Uso em Dashboard

O Dashboard exibe secção Quality Gate a partir de snapshot **injetado** ou resolvido por ID/latest no request do Dashboard. O `QualityGateSectionBuilder` **não chama** `evaluate()`.

```dart
DashboardRequest(
  projectId: 'my-project',
  qualityGateSnapshot: gateSnapshot,  // injected
);
```

---

## Integração com History

`QualityGateHistoryMapper` converte snapshots em `HistoryArtifact` e compara decisões, policy version e coverage entre versões. O History permanece responsável pelo diff — o Gate não executa History.

---

## Limitações da política candidate

| Regra | Limitação |
|-------|-----------|
| QG011 | `criticalCycleCount` sem métrica autoritativa → target `unsupported` |
| QG015 | `historyRegressionCount` derivado de metadata `regression=true` |
| Status | Política permanece **candidate** — não active até Architecture Review |

Ver `critical_cycle_mapping.md` e `quality_gate_traceability_matrix.md`.

---

## Exemplos de decisão

### Passed

Todas as regras required avaliadas com sucesso; fontes compatíveis.

```
decision: passed
status: success
blockingFailureCount: 0
```

### Failed

Violação normativa (ex.: Guardian NO-GO, MES abaixo do mínimo).

```
decision: failed
status: success          ← operação OK, gate reprovou
failedRuleCount: 1
```

### Partial

Regra required indisponível com policy `partialOnRequiredUnavailable`.

```
decision: partial
status: partial
```

### Incompatible

Artefatos de projetos ou schemas incompatíveis.

```
decision: incompatible
status: incompatible
```

---

## Referências

| Documento | Conteúdo |
|-----------|----------|
| `quality_gate_traceability_matrix.md` | Matriz de rastreabilidade |
| `critical_cycle_mapping.md` | QG011 / ciclos críticos |
| `quality_gate_release_checklist.md` | Checklist de release |
| `../adr/ADR-027-quality-gates-are-deterministic-policy-evaluations.md` | ADR arquitetural |
| `../architecture-reviews/AR-013-quality-gates-foundation.md` | Architecture Review |

---

## Fora de escopo (Sprint 04.1)

- CI/CD integration
- Persistência em banco
- Políticas remotas / YAML externo
- Frontend de governança
- Promoção automática candidate → active
