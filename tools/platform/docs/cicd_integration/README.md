# CI/CD Integration — Guia de Uso

**Pacote:** `masterpalm_platform`
**Sprint:** 05.1 — CI/CD Integration Operational Architecture and Hardening
**Políticas candidatas:** `pipeline-integration-v1`, `pipeline-execution-v1`, `deployment-integration-v1`

## Objetivo

CI/CD Integration consolida, estrutura e publica **artefatos já publicados** de pipeline e deployment:

- `PipelineDefinition`, `PipelineExecution`, `PipelineExecutionResult`
- `DeploymentPlan`, `DeploymentResult`
- `ReleaseEvidenceBundle` (evidências upstream)
- `ReleaseSupplyChainSnapshot` (supply chain upstream)

O domínio **não executa** pipelines CI/CD, **não contacta** providers externos (GitHub Actions, GitLab CI, Jenkins, etc.) e **não recalcula** Release Evidence, Release Supply Chain nem engines de origem.

Use CI/CD Integration para:

- Produzir snapshots auditáveis com fingerprints determinísticos
- Montar definição de pipeline, execução, plano e resultado de deployment estruturalmente
- Avaliar consistência estrutural via `CicdIntegrationEngine` (sem autorizar release)
- Integrar CI/CD em Report, History, Dashboard e Observability
- Suportar replay e comparação de snapshots equivalentes

**Importante:** `DeploymentApprovalStatus.approved` e snapshots com status `complete` descrevem conformidade **estrutural** — **não** autorizam release nem substituem Release Governance.

---

## Arquitetura

```
CicdIntegrationRequest
       │
       ▼
PlatformCicdIntegrationProvider
       │
       ├── PolicyRegistry (pipeline integration / execution / deployment)
       │
       ├── CicdIntegrationSourceResolver     ← injected | byId | latest (opt-in)
       │        ├── CicdIntegrationArtifactRegistry (pipeline/deployment in-memory)
       │        ├── ReleaseEvidenceProvider.load/latest (NÃO evaluate)
       │        └── ReleaseSupplyChainProvider.load/latest (NÃO evaluate)
       │
       ├── CicdIntegrationCollector           ← dedup por artifactId
       │
       ├── CicdIntegrationSnapshotBuilder     ← ordering determinístico
       │        ├── PipelineSnapshotBuilder
       │        ├── PipelineExecutionBuilder
       │        ├── DeploymentPlanBuilder
       │        └── CicdIntegrationEngine (validação estrutural)
       │
       ├── CanonicalSerializer + IdentityBuilder
       │
       └── CicdIntegrationStore (in-memory nesta sprint)
```

| Camada | Responsabilidade |
|--------|------------------|
| `CicdIntegrationProvider` | Orquestração, IO, publicação |
| `CicdIntegrationSourceResolver` | Resolve fontes sem recalcular origem |
| `CicdIntegrationArtifactRegistry` | Registo in-memory de definições/execuções/deployment |
| `CicdIntegrationCollector` | Coleta e deduplica artefatos |
| `CicdIntegrationSnapshotBuilder` | Monta snapshot com ordering canônico |
| `CicdIntegrationEngine` | Avalia regras estruturais — nunca executa pipeline |
| `CicdIntegrationStore` | Persistência de snapshots publicados |

### Bootstrap

```dart
CicdIntegrationPlatformBootstrap.register(registry: providerRegistry);
final cicd = registry.resolve<CicdIntegrationProvider>();
```

Pré-requisitos: `ReleaseEvidenceProvider` e `ReleaseSupplyChainProvider` registados **antes** de `CicdIntegrationProvider`.

---

## Pipeline

1. **Resolve** — políticas e fontes (injected > byId > latest)
2. **Collect** — artefatos resolvidos, deduplicados por `artifactId`
3. **Build** — pipeline definition, execution, deployment plan/result
4. **Engine** — validação estrutural agregada (`CicdIntegrationEngine`)
5. **Validate** — validação estrutural do snapshot (`CicdIntegrationSnapshotValidator`)
6. **Serialize** — JSON canônico e fingerprints
7. **Publish** (opcional) — gravação idempotente no store

`evaluate()` não publica. `evaluateAndPublish()` publica após validação.

---

## Modelos

### Domínio imutável (`lib/models/cicd_integration/`)

| Modelo | Significado |
|--------|-------------|
| `PipelineDefinition` | Definição estrutural de pipeline (stages, steps, triggers) |
| `PipelineExecution` | Execução declarada (sem execução real) |
| `PipelineExecutionResult` | Resultado terminal de execução |
| `DeploymentPlan` | Plano de deployment com targets, approvals e windows |
| `DeploymentResult` | Resultado de deployment declarado |
| `CicdIntegrationSnapshot` | Consolidação normativa de pipeline + deployment + linkages |
| `CicdIntegrationIdentity` | Identidade determinística e fingerprints de componentes |

### Enums descritivos (`pipeline_enums.dart`)

| Enum | Notas |
|------|-------|
| `PipelineProviderType` | **Descritor apenas** — classifica provider (githubActions, gitlabCi, jenkins, etc.) sem integração |
| `PipelineTriggerType` | Descritor de trigger — sem execução |
| `PipelineStageType`, `PipelineStepType` | Composição estrutural |
| `DeploymentStrategy`, `DeploymentApprovalStatus` | Estratégia e status de approval **estrutural** |
| `PipelineExecutionOutcome` | Outcome terminal declarado |

`PipelineProviderType` **não** invoca APIs externas nem adapters de CI/CD.

### Snapshot vs Approval vs Engine

| Artefato | Significado |
|----------|-------------|
| `CicdIntegrationSnapshot` | Consolidação normativa de pipeline, execução, deployment e linkages |
| `DeploymentApproval` | Registo estrutural de approval — **não** autoriza release |
| `CicdIntegrationMessage` | Mensagem do engine estrutural — warning/error/info |
| `CicdIntegrationSnapshotStatus` | `complete`, `partial`, `invalid` — descritivo, não normativo de release |

### Modos de resolução

| Modo | Precedência |
|------|-------------|
| `injected` | Objeto no request — sempre vence |
| `byId` | `load(id)` no artifact registry ou provider upstream |
| `latest` | Apenas com `useLatest: true` |

O resolver **nunca** chama `evaluate()` em Release Evidence ou Release Supply Chain.

---

## Políticas

Três políticas **candidate** registadas no bootstrap:

| Política | ID | Versão | Foco |
|----------|-----|--------|------|
| Pipeline Integration | `pipeline-integration-v1` | 1 | Stages obrigatórios, fingerprint de definição |
| Pipeline Execution | `pipeline-execution-v1` | 1 | Outcomes terminais, fingerprint de execução |
| Deployment Integration | `deployment-integration-v1` | 1 | Estratégias permitidas, fingerprint de plano |

Limitações explícitas em todas as políticas:

- `no-pipeline-execution`
- `no-remote-provider-fetch` (integration policy)
- `no-remote-deployment` (deployment policy)
- `structural-assembly-only` / `structural-validation-only` / `structural-plan-only`

**Approval estrutural ≠ autorização de release.** Release Governance permanece a única camada de autorização de progressão.

---

## Resolver

`CicdIntegrationSourceResolver` resolve:

| Fonte | Origem |
|-------|--------|
| Pipeline definition/execution/result | `CicdIntegrationArtifactRegistry` |
| Deployment plan/result | `CicdIntegrationArtifactRegistry` |
| Release evidence bundle | `ReleaseEvidenceProvider.latest` (opt-in) |
| Release supply chain snapshot | `ReleaseSupplyChainProvider.latest` (opt-in) |
| Políticas | Policy registries (candidate permitido) |

Checks de compatibilidade (sem bloqueio silencioso):

- `projectId` mismatch em evidence → limitation
- `definitionId` mismatch execution/definition → limitation
- `pipelineExecutionId` mismatch plan/execution → limitation

---

## Collector

`CicdIntegrationCollector`:

- Localiza artefatos das fontes resolvidas
- Deduplica por `artifactId` (steps, targets, execution artifacts)
- **Não reconstrói** snapshots upstream
- Ordena artefatos coletados por `artifactId`

---

## Builders

| Builder | Output |
|---------|--------|
| `PipelineSnapshotBuilder` | `PipelineDefinition` normalizada |
| `PipelineExecutionBuilder` | `PipelineExecution` + `PipelineExecutionResult` |
| `DeploymentPlanBuilder` | `DeploymentPlan` + `DeploymentResult` |

Builders copiam dados sem mutação de fontes. Fingerprints ausentes são calculados via `CicdIntegrationCanonicalSerializer`.

---

## Engine

`CicdIntegrationEngine` avalia consistência estrutural:

- Stages obrigatórios ausentes (`CICD_STRUCT_MISSING_STAGE`)
- Fingerprints obrigatórios ausentes (policy-driven)
- Mismatch definition/execution/plan/result
- Outcomes terminais fora da política
- Estratégias de deployment não permitidas

**Nunca executa pipelines.** Mensagens ordenadas por `messageId`.

---

## Serializer

`CicdIntegrationCanonicalSerializer` (`cicd-integration-canonical-v1`):

- Fingerprints via `PipelineFingerprint.fromComparableJson`
- Normalização JSON com chaves ordenadas
- Fingerprints de snapshot, policies, componentes e source references

Campos transitórios (`cicdIntegrationSnapshotId`, `createdAt`, `evaluatedAt`) excluídos de `toComparableJson()`.

---

## Identity

`CicdIntegrationIdentityBuilder`:

- `buildCicdIntegrationId()` — ID determinístico composto
- `fingerprintForSnapshot()` — fingerprint normativo do snapshot
- Fingerprints de componentes: pipeline, execution, result, deployment plan/result

---

## Store

`InMemoryCicdIntegrationStore`:

- `save()` idempotente para mesmo fingerprint canônico
- Conflito (`CicdIntegrationSnapshotConflictException`) se mesmo ID com fingerprint diferente
- `latest()` ordenado por `evaluatedAt` desc
- `query()` com filtros projectId, releaseId, status, policyId
- `invalidate()` e `clear()`

**Sem persistência entre processos.**

---

## Provider

`PlatformCicdIntegrationProvider` implementa `CicdIntegrationProvider`:

| Método | Comportamento |
|--------|---------------|
| `evaluate()` | Resolve → collect → build → validate → result |
| `evaluateAndPublish()` | evaluate + validate + save idempotente |
| `publish()` | Grava snapshot directamente |
| `load()` / `latest()` / `query()` | Consulta store |
| `invalidate()` | Remove snapshot (throws se ausente) |

Status do result: `success`, `partial`, `failure`, `unavailable` (sem artefatos coletados).

---

## Integrações

| Consumidor | Tipo / Secção | Comportamento |
|------------|---------------|---------------|
| Report | `ReportType.cicdIntegration` | `CicdIntegrationReportSource.fromSnapshot()` |
| History | `HistoryArtifactType.cicdIntegration` | `CicdIntegrationHistoryMapper` + comparator |
| Dashboard | `cicdPipeline`, `cicdExecution`, `cicdDeployment` | Section builders sem re-evaluate |
| Observability | `TelemetryComponent.cicdIntegration` | `ObservableCicdIntegrationProvider` (opt-in) |

Integrações consomem snapshots **publicados ou injetados** — nunca reexecutam o pipeline CI/CD Integration.

---

## Exemplos

### Avaliação com artefatos injetados

```dart
final core = PlatformBootstrap.forRepo(repoPath);

final result = await core.cicdIntegration().evaluate(
  CicdIntegrationOperationalFixtures.passingRequest(
    releaseEvidenceBundle: evidenceBundle,
    releaseSupplyChainSnapshot: supplyChainSnapshot,
  ),
);

expect(result.snapshot, isNotNull);
expect(result.snapshot!.fingerprint, isNotEmpty);
expect(result.snapshot!.limitations, contains('no-pipeline-execution'));
```

### Publicação e consulta

```dart
final published = await provider.evaluateAndPublish(request);
await provider.load(published.snapshot!.metadata.cicdIntegrationSnapshotId);

final latest = await provider.latest(
  projectId: 'masterpalm-demo',
);
```

### Replay determinístico

```dart
final a = await provider.evaluate(request);
final b = await provider.evaluate(request);

expect(a.snapshot!.fingerprint, b.snapshot!.fingerprint);
expect(
  a.snapshot!.metadata.pipelineFingerprint,
  b.snapshot!.metadata.pipelineFingerprint,
);
```

---

## Replay

Replay é suportado quando:

- Mesma política (ID + versão) para integration, execution e deployment
- Mesmas fontes resolvidas (artefatos equivalentes)
- Mesmo `requestedAt` no request

Fingerprints estáveis:

- `snapshot.fingerprint`
- `metadata.pipelineFingerprint`, `executionFingerprint`, `executionResultFingerprint`
- `metadata.deploymentPlanFingerprint`, `deploymentResultFingerprint`
- Componentes ordenados deterministicamente

Evidência baseline: `cicd_integration_provider_test.dart` (determinismo). Parte 3 adiciona `cicd_integration_replay_test.dart` e goldens.

---

## Limitações (Sprint 05.1)

| Limitação | Impacto |
|-----------|---------|
| Políticas **candidate** | Não promovidas a `active` sem AR |
| Store **in-memory** | Sem persistência entre processos |
| **Sem adapters externos** | `PipelineProviderType` é descritor apenas |
| **Sem execução CI/CD** | Pipelines nunca são executados |
| **Approval estrutural** | `approved` ≠ autorização de release |
| **Artifact registry in-memory** | Definições/execuções não persistem entre processos |
| Observability default **disabled** | Telemetry só com bootstrap habilitado |

---

## Procedimento de atualização de Golden Snapshots

1. Confirmar que a alteração de snapshot é **intencional** (mudança normativa, não bug)
2. Executar `dart test test/cicd_integration/cicd_integration_golden_test.dart`
3. Revisar diff dos ficheiros em `test/golden/cicd_integration/`
4. Atualizar goldens explicitamente: `dart run test --update-goldens test/cicd_integration/cicd_integration_golden_test.dart`
5. Verificar fingerprints estáveis em `cicd_integration_replay_test.dart`
6. Documentar motivo no PR/commit

Goldens previstos (Parte 3):

- `passing_snapshot.json` — snapshot canônico
- `pipeline_definition.json` — definição de pipeline
- `pipeline_execution.json` — execução
- `deployment_plan.json` — plano de deployment
- `deployment_result.json` — resultado

---

## Procedimento de Replay

1. Construir request fixo com artefatos injetados (fixtures)
2. Executar `evaluate()` duas vezes no mesmo provider
3. Comparar `snapshot.fingerprint` e fingerprints de componentes
4. Executar JSON round-trip: `toJson()` → `fromJson()` → re-fingerprint
5. Confirmar que mutação de campo normativo altera fingerprint
6. Confirmar que campos transitórios não alteram fingerprint

Evidência: `cicd_integration_replay_test.dart`, `cicd_integration_identity_audit_test.dart`.

---

## Troubleshooting

| Sintoma | Causa provável | Ação |
|---------|----------------|------|
| `publicationStatus: skipped` após publish | Snapshot já publicado com mesmo fingerprint | Comportamento esperado (idempotência) |
| RE/RSC ausente | Fonte não injetada e `useLatest: false` | Injetar snapshot ou publicar no store upstream |
| Fingerprints diferentes entre replays | `requestedAt` ou fontes diferentes | Normalizar inputs |
| `latest` não resolve | `useLatest: false` (default) | Definir `useLatest: true` explicitamente |
| Status `partial` | Execução ou deployment ausentes | Esperado para requests parciais |
| `CicdIntegrationSnapshotConflictException` | Mesmo ID, fingerprint diferente | Usar novo request ou invalidar snapshot |
| Golden test falha | Snapshot intencional desatualizado | Seguir procedimento de golden update |
| ProviderType sem efeito | Descritor apenas — by design | Não esperar integração externa |

---

## Testes

| Área | Ficheiro |
|------|----------|
| Models/validators (Parte 1) | `pipeline_models_test.dart`, `pipeline_validators_test.dart` |
| Serialização (Parte 1) | `pipeline_serialization_test.dart` |
| Operacional (Parte 2) | `cicd_integration_operational_test.dart` |
| Provider (Parte 2) | `cicd_integration_provider_test.dart` |
| Integração (Parte 2) | `cicd_integration_integration_test.dart` |
| Replay (Parte 3) | `cicd_integration_replay_test.dart` |
| Golden (Parte 3) | `cicd_integration_golden_test.dart` |
| Hardening (Parte 3) | `cicd_integration_hardening_test.dart`, audits |

**Baseline antes da Parte 3:** 87 testes em `test/cicd_integration/`.
**Após Parte 3 (hardening):** 215 testes em `test/cicd_integration/`, 1414 na suite completa.

---

## Documentação relacionada

- [ADR-031](../adr/ADR-031-cicd-integration-operational-architecture-and-hardening.md)
- [AR-017](../architecture-reviews/AR-017-cicd-integration-framework.md)
- [Release Checklist](cicd_integration_release_checklist.md)
- [ADR-030 Release Supply Chain](../adr/ADR-030-release-supply-chain-and-provenance-framework.md)
