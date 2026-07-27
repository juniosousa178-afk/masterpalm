# ADR-031: CI/CD Integration Operational Architecture and Hardening

| Campo | Valor |
|-------|-------|
| **Status** | Accepted (pending formal sign-off in AR-017) |
| **Data** | 2026-07-22 |
| **Sprint** | 05.1 — CI/CD Integration Operational Architecture and Hardening |
| **Decisores** | MasterPalm Engineering Governance |
| **Domínio** | `tools/platform` — CI/CD Integration |

---

## Contexto

A MasterPalm Engineering Platform publica decisões normativas em camadas:

- **Quality Gate** (ADR-027) — evidência técnica de qualidade
- **Release Governance** (ADR-028) — autorização de progressão de release
- **Release Evidence** (ADR-029) — consolidação e verificação estrutural de evidências
- **Release Supply Chain** (ADR-030) — provenance, grafo, SBOM e compliance estrutural
- **History, Report, Dashboard, Observability** — leitura e diffs sem recálculo

Release exige uma camada que estruture integração CI/CD — definições de pipeline, execuções declaradas, planos e resultados de deployment — **sem** executar pipelines, contactar providers externos nem substituir Release Governance.

Requisitos:

1. Consumir `ReleaseEvidenceBundle` e `ReleaseSupplyChainSnapshot` **publicados**
2. Modelar pipeline e deployment como artefatos estruturais imutáveis
3. Mesma política + mesmas fontes → mesmo snapshot e fingerprints
4. Identidade determinística para replay
5. Políticas versionadas com freeze no registry
6. Integrações transparentes com Report, History, Dashboard e Observability
7. `PipelineProviderType` como **descritor de domínio apenas** — sem adapters

---

## Decisão

Implementamos CI/CD Integration como **pipeline determinístico** sobre **artefatos declarados e publicados**, com três políticas candidate:

| Política | ID | Versão |
|----------|-----|--------|
| Pipeline Integration | `pipeline-integration-v1` | 1 |
| Pipeline Execution | `pipeline-execution-v1` | 1 |
| Deployment Integration | `deployment-integration-v1` | 1 |

### Princípios centrais

1. **Consumir, não recalcular**
   `CicdIntegrationSourceResolver` usa `load`/`latest` de Release Evidence e Release Supply Chain. Nunca invoca `evaluate()` em RE ou RSC.

2. **Não executar CI/CD**
   O domínio monta e valida artefatos estruturalmente. Nenhum step de pipeline é executado. Limitação `no-pipeline-execution` em todas as políticas.

3. **ProviderType descritor apenas**
   `PipelineProviderType` (githubActions, gitlabCi, jenkins, etc.) classifica metadata — **sem** adapters, webhooks ou APIs externas. Limitação `no-remote-provider-fetch`.

4. **Collector com deduplicação**
   `CicdIntegrationCollector` deduplica por `artifactId`. Fingerprints de origem preservados sem recálculo indevido.

5. **Snapshot com ordering canônico**
   Artefatos coletados ordenados por `artifactId`. Fingerprints via `CicdIntegrationCanonicalSerializer` + `CicdIntegrationIdentityBuilder`.

6. **Engine estrutural**
   `CicdIntegrationEngine` avalia regras estruturais contra artefatos montados. **Nunca** executa pipeline nem deployment.

7. **Approval estrutural ≠ autorização**
   `DeploymentApprovalStatus.approved` é descritivo. Status `complete` no snapshot **não** autoriza release — isso é responsabilidade de Release Governance.

8. **Modos de resolução**
   Precedência: `injected` > `byId` > `latest` (opt-in via `useLatest: true`).

9. **Publicação idempotente**
   `evaluate()` não publica. `evaluateAndPublish()` valida antes de gravar. Store in-memory com overwrite controlado.

10. **Integrações transparentes**
    Report (`ReportType.cicdIntegration`), History (`HistoryArtifactType.cicdIntegration`), Dashboard (`cicdPipeline`, `cicdExecution`, `cicdDeployment`) e Observability (`TelemetryComponent.cicdIntegration`) consomem snapshots sem reexecutar o pipeline.

---

## Arquitetura

```
CicdIntegrationRequest
       │
       ▼
PlatformCicdIntegrationProvider
       │
       ├── PolicyRegistry (integration / execution / deployment)
       ├── CicdIntegrationSourceResolver
       │        ├── CicdIntegrationArtifactRegistry (in-memory)
       │        ├── ReleaseEvidenceProvider (load/latest)
       │        └── ReleaseSupplyChainProvider (load/latest)
       ├── CicdIntegrationCollector
       ├── CicdIntegrationSnapshotBuilder
       │        ├── PipelineSnapshotBuilder
       │        ├── PipelineExecutionBuilder
       │        ├── DeploymentPlanBuilder
       │        └── CicdIntegrationEngine
       ├── CanonicalSerializer + IdentityBuilder
       └── CicdIntegrationStore
```

---

## Alternativas rejeitadas

| Alternativa | Motivo da rejeição |
|-------------|-------------------|
| Executar pipelines CI/CD reais | Fora de escopo; viola princípio structural-only; risco operacional |
| Adapters para GitHub Actions / GitLab CI nesta sprint | Complexidade prematura; `PipelineProviderType` suficiente como descritor |
| Recalcular RE/RSC durante CI/CD integration | Viola consume-don't-recalculate; quebra determinismo |
| Deployment approval como autorização de release | Sobrepõe Release Governance; viola separação de responsabilidades |
| Store persistente nesta sprint | Fora de escopo; in-memory suficiente para fundação |
| Verificação criptográfica de digests | Complexidade prematura; placeholders documentados como limitação |
| Engine monolítica | Impede testes isolados e evolução independente de componentes |

---

## Limitações

- Políticas permanecem **candidate** até Architecture Review de promoção
- Store **in-memory** — sem persistência entre processos
- `CicdIntegrationArtifactRegistry` **in-memory** — pipeline/deployment sources não persistem
- Digests SHA-256 são **placeholders estruturais** — sem verificação criptográfica
- **Sem execução CI/CD** — limitação explícita em políticas e snapshot
- **Sem adapters externos** — `PipelineProviderType` é metadata apenas
- Approval estrutural **nunca aprova release**
- Observability desabilitada por default no bootstrap standard

---

## Evolução futura

1. Promoção candidate → active após AR dedicado
2. Store persistente (Firestore ou equivalente)
3. Adapters opt-in para providers CI/CD (GitHub Actions, GitLab CI, Jenkins)
4. Execução de pipeline delegada a runners externos (opt-in, fora do core)
5. Verificação criptográfica de artefatos de pipeline (opt-in)
6. Políticas v1.1 com regras adicionais de promotion gates
7. Cache de snapshots publicados com invalidação explícita

---

## Consequências

### Positivas

- Replay determinístico validável com golden snapshots (Parte 3)
- Separação clara entre integração, execução e deployment estrutural
- Integração consistente com padrão QG/RG/RE/RSC da plataforma
- 87+ testes baseline (Parts 1–2) antes de hardening Parte 3
- Descritores de provider preparados para adapters futuros sem acoplamento

### Negativas

- Consumidores devem entender que approval/deployment `complete` ≠ release autorizada
- Dependência de snapshots publicados em RE e RSC para linkages completos
- Store in-memory não adequado para produção multi-processo
- Sem enforcement automático em pipelines CI/CD reais

---

## Referências

- ADR-027 — Quality Gate Foundation
- ADR-028 — Release Governance
- ADR-029 — Release Evidence and Attestation Foundation
- ADR-030 — Release Supply Chain and Provenance Framework
- AR-017 — Architecture Review CI/CD Integration Framework
- `docs/cicd_integration/README.md`
