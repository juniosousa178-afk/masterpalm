# ADR-028: Release Governance autoriza progressão de release

| Campo | Valor |
|-------|-------|
| **Status** | Accepted (pending formal sign-off in AR-014) |
| **Data** | 2026-07-21 |
| **Sprint** | 04.2 — Release Governance Foundation |
| **Decisores** | MasterPalm Engineering Governance |
| **Domínio** | `tools/platform` — Release Governance |

---

## Contexto

A MasterPalm Engineering Platform já publica evidências técnicas e decisões normativas de qualidade:

- **Quality Gate** — avaliação determinística de política sobre artefatos publicados (ADR-027)
- **Guardian, Score, MES, Metrics** — engines de origem consumidos pelo Quality Gate
- **History** — diffs de artefatos ao longo do tempo
- **Report, Dashboard, Observability** — leitura e instrumentação sem recálculo

O Quality Gate responde: *as evidências técnicas publicadas satisfazem a política de qualidade?*

A progressão de release exige uma camada adicional que responda: *esta release pode avançar no pipeline, dado o Quality Gate, o contexto de release, aprovações e waivers?*

Requisitos:

1. Release Governance **consome** `QualityGateSnapshot` publicado — **não recalcula** o Quality Gate nem engines de origem
2. Mesma política + mesmas fontes → mesma decisão de release (`approved`, `approvedWithConditions`, `rejected`, `pending`, etc.)
3. Aprovações, waivers e contexto de release tratados explicitamente com validadores dedicados
4. Identidade determinística (snapshot ID, fingerprints) para replay e auditoria
5. Políticas versionadas com conteúdo normativo imutável após freeze
6. Integrações transparentes com Report, History, Dashboard e Observability

---

## Decisão

Implementamos Release Governance como **avaliações determinísticas de política** sobre **artefatos publicados**, incluindo `QualityGateSnapshot`, contexto de release, conjuntos de aprovação e waiver.

### Princípios centrais

1. **Consumir, não recalcular**
   `ReleaseGovernanceEngine` avalia regras contra `ResolvedReleaseGovernanceSources`. Nunca invoca `QualityGateEngine`, Metrics, Score, MES, Guardian nem qualquer engine de origem do Quality Gate.

2. **Quality Gate como evidência técnica**
   O snapshot do Quality Gate é referenciado por ID, fingerprint e decisão. Regras RG003–RG008 leem campos do snapshot publicado (`decision`, `compatibility`, `eligibility`, `coverage`, `age`). Ausência de snapshot é tratada explicitamente — nunca inventada.

3. **Avaliação vinculada à política**
   Cada avaliação está ligada a uma `ReleaseGovernancePolicy` explícita (ID + versão). Políticas são validadas, fingerprinted e registadas de forma imutável após freeze no `ReleaseGovernancePolicyRegistry`.

4. **Resultados determinísticos**
   Dado request normalizado, política e referências de fonte idênticas, o engine produz:
   - idêntico `releaseDecisionSnapshotId`
   - idêntico `releaseGovernanceFingerprint`
   - idêntica `decision`, `evaluations`, `coverage`, `compatibility`, `eligibility`

5. **Separação de falha operacional vs reprovação normativa**
   - `ReleaseGovernanceResultStatus.failure` — erro de engine/validação
   - `ReleaseGovernanceResultStatus.success` com `ReleaseGovernanceDecision.rejected` — reprovação normativa (operação bem-sucedida, release não autorizada)

6. **Modos de resolução de fontes**
   Fontes resolvem via `injected`, `byId` ou `latest` (opt-in via `useLatest: true`). Quality Gate resolve via `QualityGateProvider.load`/`latest` — **nunca** via `evaluate()`.

7. **Publicação idempotente**
   `InMemoryReleaseGovernanceStore` rejeita escritas conflituosas para o mesmo snapshot ID. `evaluate()` não publica; `evaluateAndPublish()` publica apenas após validação do snapshot.

8. **Integrações transparentes**
   Report (`ReportType.releaseGovernance`), History (`HistoryArtifactType.releaseGovernance`), Dashboard (`DashboardSectionType.releaseGovernance`) e Observability (`TelemetryComponent.releaseGovernance`) consomem ou decoram snapshots sem reexecutar o engine.

9. **Autorização humana sem criptografia nesta sprint**
   Aprovações e waivers são validados estruturalmente (`ReleaseApprovalValidator`, `ReleaseWaiverValidator`). Identidade de autoridade **não** é verificada criptograficamente — limitação explícita `authorityNotCryptographicallyVerified`.

---

## Arquitetura

```
ReleaseGovernanceRequest
       │
       ▼
PlatformReleaseGovernanceProvider
       │
       ├── PolicyRegistry.resolve(policyId, version)
       │
       ├── ReleaseGovernanceSourceResolver.resolveAll()  ← injected | byId | latest
       │        └── QualityGateProvider.load/latest (NÃO evaluate)
       │
       └── ReleaseGovernanceEngine.evaluate()            ← stateless, sem IO
                 │
                 ├── CompatibilityChecker
                 ├── EligibilityEvaluator
                 ├── ApprovalEvaluator
                 ├── WaiverEvaluator
                 ├── RuleEvaluator (por regra RG001–RG020)
                 │     ├── TargetRegistry → resolvers
                 │     ├── OperatorEvaluator
                 │     └── Handlers (missing / incompatible)
                 ├── ConditionBuilder
                 ├── CoverageCalculator
                 ├── DecisionAggregator
                 └── IdentityBuilder (snapshot + fingerprints)
```

---

## Políticas

| Política | Versão | Status | Nota |
|----------|--------|--------|------|
| `release-governance-v1` | 1 | candidate | RG006 usa operador `isValid` |
| `release-governance-v1.1` | 2 | candidate | RG006 usa operador `isEligible` (migração explícita) |

Ambas permanecem **candidate** até Architecture Review de promoção. Consumidores devem selecionar explicitamente a versão desejada.

---

## Consequências

### Positivas

- **Separação de responsabilidades** — Quality Gate mede qualidade técnica; Release Governance autoriza progressão
- **Reprodutibilidade** — snapshots históricos replayam identicamente
- **Auditabilidade** — cada regra produz evidência rastreável com referências de fonte
- **Desacoplamento** — lógica de release independente dos internals do Quality Gate
- **Extensibilidade** — aprovações, waivers e condições modelados de forma tipada

### Negativas

- **Rigor de versionamento** — alterações de threshold ou regra exigem nova versão de política
- **Superfície de adaptadores** — cada novo target requer resolver tipado em `ReleaseGovernanceTargetRegistry`
- **Sem enforcement automático** — store in-memory; sem integração CI/CD nesta sprint
- **Autoridade não criptográfica** — aprovações aceitas por estrutura, não por assinatura digital

### Limitações conhecidas (aceites)

- Store in-memory (`noPhysicalPersistence`)
- Sem verificação criptográfica de autoridade (`noSignatureVerification`, `authorityNotCryptographicallyVerified`)
- Sem enforcement CI/CD (`noCiCdEnforcement`)
- RG006 em v1 usa `isValid` (semântica estrutural) — v1.1 corrige para `isEligible`
- Políticas permanecem `candidate`

---

## Alternativas consideradas

| Alternativa | Motivo de rejeição |
|-------------|-------------------|
| Release Governance recalcula Quality Gate | Quebra determinismo; duplica lógica; fingerprints divergentes |
| Release Governance avalia código-fonte diretamente | Fora de escopo; acopla release a AST/Graph engines |
| DSL de expressão livre | Não tipado; difícil de auditar; risco de segurança em eval |
| `latest` implícito para Quality Gate | Não determinístico sem opt-in explícito |
| PASS/FAIL booleano simples | Sem evidência, coverage, aprovações ou condições |
| Armazenar apenas approved/rejected | Perde trilha de auditoria e capacidade de replay |
| Bloquear em exceções de engine para falhas normativas | Confunde resultados operacionais e normativos |
| Assinatura criptográfica obrigatória na v1 | Escopo excessivo para fundação; adiado para sprint futura |

---

## Conformidade

| Requisito | Mecanismo |
|-----------|-----------|
| Sem execução do Quality Gate Engine | `ReleaseGovernanceSourceResolver` carrega snapshots publicados via `QualityGateProvider` |
| Sem recálculo de engines de origem | Resolver não invoca Metrics/Score/MES/Guardian |
| ID determinístico | `ReleaseGovernanceIdentityBuilder` + `ReleaseGovernanceCanonicalSerializer` |
| Imutabilidade de política | `ReleaseGovernancePolicyRegistry.freeze()` após registro |
| Evidência por regra | `ReleaseGovernanceEvidenceBuilder` + `kReleaseGovernanceEvidenceRequirement` |
| Limitações explícitas | `ReleaseGovernanceLimitation` com `limitationId` tipado |

---

## Documentos relacionados

- `docs/release_governance/README.md` — guia de uso
- `docs/release_governance/release_governance_traceability_matrix.md` — rastreabilidade RG001–RG020
- `docs/release_governance/release_governance_release_checklist.md` — critérios de release
- `docs/architecture-reviews/AR-014-release-governance-foundation.md` — review formal
- `docs/adr/ADR-027-quality-gates-are-deterministic-policy-evaluations.md` — ADR upstream

---

## Histórico de revisão

| Versão | Data | Autor | Resumo |
|--------|------|-------|--------|
| 1 | 2026-07-21 | MasterPalm Engineering Governance | Aceitação inicial para Sprint 04.2 Part 3 |
