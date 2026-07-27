# ADR-027: Quality Gates are deterministic policy evaluations

| Campo | Valor |
|-------|-------|
| **Status** | Accepted (pending formal sign-off in AR-013) |
| **Data** | 2026-07-21 |
| **Sprint** | 04.1 — Quality Gates Foundation |
| **Decisores** | MasterPalm Engineering Governance |
| **Domínio** | `tools/platform` — Quality Gate |

---

## Context

The MasterPalm Engineering Platform already publishes multiple technical artifacts:

- **Metrics** — structural graph metrics and availability
- **Guardian** — architectural GO/NO-GO with violations
- **Engineering Score** — weighted engineering quality score
- **MES** — MasterPalm Engineering Score with eligibility and bands
- **History** — artifact diffs over time
- **Telemetry** — operational instrumentation snapshots
- **Dashboard** — composed read models

Score and MES **measure** quality dimensions. Guardian **decides** architectural compliance. Release approval requires a **separate, auditable gate** that answers: *does this published evidence satisfy the release policy?*

Requirements:

1. Same policy + same published sources → same decision
2. No silent recalculation of upstream engines
3. Explicit handling of missing and incompatible evidence
4. Deterministic identity (snapshot ID, fingerprints) for replay and audit
5. Policy versioning with immutable normative content

---

## Decision

We implement Quality Gates as **stateless, deterministic policy evaluations** over **published artifacts only**.

### Core principles

1. **Consume, do not recalculate**
   `QualityGateEngine` evaluates rules against `ResolvedQualityGateSources`. It never invokes Metrics, Score, MES, Guardian, History, Dashboard, or Observability engines.

2. **Policy-bound evaluation**
   Every evaluation is tied to an explicit `QualityGatePolicy` (ID + version). Policies are validated, fingerprinted, and registered immutably after freeze.

3. **Deterministic outcomes**
   Given identical normalized request, policy, and source references, the engine produces:
   - identical `qualityGateSnapshotId`
   - identical `qualityGateFingerprint`
   - identical `decision`, `evaluations`, `coverage`, `compatibility`, `eligibility`

4. **Explicit absence and incompatibility**
   Missing data and incompatible data map to terminal rule statuses via typed handlers (`QualityGateMissingDataHandler`, `QualityGateIncompatibleDataHandler`). Absence is never coerced to zero. Incompatibility is never coerced to pass.

5. **Separation of operational vs normative failure**
   - `QualityGateResultStatus.failure` — engine/validation error
   - `QualityGateResultStatus.success` with `QualityGateDecision.failed` — normative rejection (gate failed, operation succeeded)

6. **Source resolution modes**
   Sources resolve via `injected`, `byId`, or `latest` (opt-in via `useLatest: true`). No implicit latest.

7. **Idempotent publication**
   `InMemoryQualityGateStore` (and future persistent stores) reject conflicting writes for the same snapshot ID. `evaluate()` does not publish; `evaluateAndPublish()` publishes only after validation.

8. **Transparent integrations**
   Report, History, Dashboard, and Observability consume or decorate snapshots without re-running the engine.

---

## Architecture

```
QualityGateRequest
       │
       ▼
PlatformQualityGateProvider
       │
       ├── PolicyRegistry.resolve(policyId, version)
       │
       ├── QualityGateSourceResolver.resolveAll()  ← injected | byId | latest
       │
       └── QualityGateEngine.evaluate()            ← stateless, no IO
                 │
                 ├── CompatibilityChecker
                 ├── EligibilityEvaluator
                 ├── RuleEvaluator (per rule)
                 │     ├── TargetRegistry → resolvers
                 │     ├── OperatorEvaluator
                 │     └── Handlers (missing / incompatible)
                 ├── RuleSetEvaluator
                 ├── CoverageCalculator
                 ├── DecisionAggregator
                 └── SnapshotBuilder (identity + fingerprints)
```

---

## Consequences

### Positive

- **Reproducibility** — historical snapshots replay identically
- **Auditability** — every rule produces traceable evidence with source references
- **Decoupling** — gate logic independent of engine internals
- **Governance** — policy changes require explicit versioning
- **History integration** — snapshots are first-class artifacts

### Negative

- **Versioning rigor** — threshold or rule changes require new policy versions
- **Adapter surface** — each new target needs a typed resolver
- **No silent fixes** — missing metrics cannot be invented at gate time
- **Formal governance** — candidate policies cannot become active without Architecture Review

### Known limitations (accepted)

- `criticalCycleCount` has no authoritative metrics source (QG011 → `unsupported`)
- `historyRegressionCount` is derived from change metadata, not an authoritative History field (QG015)

---

## Alternatives considered

| Alternative | Reason rejected |
|-------------|-----------------|
| Gate recalculates Score/MES | Breaks determinism; duplicates engine logic; divergent fingerprints |
| Gate evaluates source code directly | Out of scope; couples gate to AST/Graph engines |
| Free-text expression DSL | Untyped; hard to audit; eval security risk |
| Implicit `latest` resolution | Non-deterministic without explicit opt-in |
| Simple boolean PASS/FAIL | No evidence, coverage, or explainability |
| Store only PASS/FAIL | Loses audit trail and replay capability |
| Gate blocks on engine exceptions for normative failures | Conflates operational and normative outcomes |

---

## Compliance

| Requirement | Mechanism |
|-------------|-----------|
| No origin engine execution | `QualityGateSourceResolver` loads published artifacts only |
| Deterministic ID | `QualityGateIdentityBuilder` + `QualityGateCanonicalSerializer` |
| Policy immutability | `QualityGatePolicyRegistry.freeze()` after registration |
| Evidence per rule | `QualityGateEvidenceBuilder` + `kReleaseGateEvidencePolicy` |
| Explicit limitations | `QualityGateLimitation` with typed `limitationId` |

---

## Related documents

- `docs/quality_gate/README.md` — usage guide
- `docs/quality_gate/quality_gate_traceability_matrix.md` — traceability
- `docs/quality_gate/critical_cycle_mapping.md` — QG011 limitation
- `docs/quality_gate/quality_gate_release_checklist.md` — release criteria
- `docs/architecture-reviews/AR-013-quality-gates-foundation.md` — formal review

---

## Revision history

| Versão | Data | Autor | Resumo |
|--------|------|-------|--------|
| 1 | 2026-07-21 | MasterPalm Engineering Governance | Initial acceptance for Sprint 04.1 |
