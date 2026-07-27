# Architecture Review #014 — Release Governance Foundation

| Campo | Valor |
|-------|-------|
| **ID** | AR-014 |
| **Título** | Release Governance Foundation |
| **Sprint** | 04.2 Part 3 |
| **Data** | 2026-07-21 |
| **Revisor** | MasterPalm Engineering Governance |
| **ADR relacionado** | ADR-028 |
| **Políticas** | `release-governance-v1` (candidate), `release-governance-v1.1` (candidate) |

---

## 1. Executive Summary

A Sprint 04.2 Part 3 entrega a fundação de Release Governance na MasterPalm Engineering Platform: um engine stateless que autoriza progressão de release com base em `QualityGateSnapshot` publicado, contexto de release, aprovações e waivers, com provider, store in-memory, integrações Report/History/Dashboard/Observability, e políticas candidate com 20 regras (RG001–RG020).

A arquitetura cumpre os princípios de determinismo, não-recálculo do Quality Gate, separação entre falha operacional e reprovação normativa, e tratamento explícito de aprovações/waivers. Condições que impedem GO pleno:

1. **Políticas candidate** — `release-governance-v1` e `release-governance-v1.1` não promovidas a `active`
2. **Store in-memory** — sem persistência física entre processos
3. **Sem autenticação criptográfica** — aprovações e autoridades validadas estruturalmente apenas
4. **RG006 em v1** — operador `isValid` (v1.1 corrige para `isEligible`)
5. **Sem integração CI/CD** — enforcement manual

**Decisão:** **GO WITH CONDITIONS — Release 4.1 Beta**

---

## 2. Scope Reviewed

| Área | Incluído |
|------|----------|
| Domínio imutável (models, enums, policy) | Sim |
| Engine e evaluators (rule, approval, waiver) | Sim |
| Source resolver e target registry | Sim |
| Validadores (context, approval, waiver, policy, snapshot) | Sim |
| Provider e store in-memory | Sim |
| Bootstrap e PlatformCore | Sim |
| Integrações Report, History, Dashboard, Observability | Sim |
| Políticas `release-governance-v1` e `release-governance-v1.1` | Sim |
| Testes `test/release_governance/` | Sim |
| Documentação Sprint 04.2 Part 3 | Sim |

**Fora de escopo:** CI/CD enforcement, persistência física, frontend de governança, assinatura criptográfica, promoção candidate→active, consumo automático de waivers.

---

## 3. Architecture Baseline

A plataforma segue o padrão estabelecido por Quality Gate, Score, MES e Dashboard:

- **Models** — tipos imutáveis com serialização canônica (`lib/models/release_governance/*`)
- **Engine** — lógica pura, sem IO (`ReleaseGovernanceEngine`)
- **Provider** — orquestração e persistência (`PlatformReleaseGovernanceProvider`)
- **Bootstrap** — composition root via `ProviderRegistry` (`ReleaseGovernancePlatformBootstrap`)

Release Governance adere a este baseline e depende upstream do `QualityGateProvider` apenas para **leitura** de snapshots publicados.

---

## 4. Implemented Components

| Componente | Arquivo | Função |
|------------|---------|--------|
| Models | `lib/models/release_governance/*` | Policy, request, snapshot, approval, waiver, enums |
| Engine | `lib/release_governance/release_governance_engine.dart` | Avaliação stateless |
| Source resolver | `lib/release_governance/release_governance_source_resolver.dart` | Resolve fontes sem recalcular QG |
| Target registry | `lib/release_governance/release_governance_target_registry.dart` | Resolvers por domínio |
| Operator evaluator | `lib/release_governance/release_governance_operator_evaluator.dart` | Operadores tipados |
| Handlers | `lib/release_governance/release_governance_handlers.dart` | Missing/incompatible |
| Rule evaluator | `lib/release_governance/release_governance_rule_evaluator.dart` | Avaliação por regra |
| Approval evaluator | `lib/release_governance/release_governance_approval_evaluator.dart` | Requisitos de aprovação |
| Waiver evaluator | `lib/release_governance/release_governance_waiver_evaluator.dart` | Política de waivers |
| Decision aggregator | `lib/release_governance/release_governance_decision_aggregator.dart` | Precedência de decisão |
| Condition builder | `lib/release_governance/release_governance_condition_builder.dart` | Condições de release |
| Provider | `lib/providers/platform_release_governance_provider.dart` | Contrato público |
| Store | `lib/release_governance/stores/in_memory_release_governance_store.dart` | Persistência in-memory |
| Bootstrap | `lib/release_governance/release_governance_platform_bootstrap.dart` | DI |
| Policy v1 | `lib/release_governance/policies/release_governance_policy_v1.dart` | 20 regras candidate |
| Policy v1.1 | `lib/release_governance/policies/release_governance_policy_v1_1.dart` | RG006 `isEligible` |
| Report source | `lib/report/sources/release_governance_report_source.dart` | Input para ReportEngine |
| History mapper | `lib/history/mappers/release_governance_history_mapper.dart` | Artefato History |
| Dashboard builder | `lib/dashboard/builders/release_governance_section_builder.dart` | Secção Dashboard |
| Observability | `lib/observability/instrumentation/observable_release_governance_provider.dart` | Decorator |

---

## 5. Architectural Principles

| Princípio | Conformidade | Evidência |
|-----------|--------------|-----------|
| Single responsibility | Conforme | Engine avalia; Provider faz IO |
| Immutability | Conforme | Models com listas defensivas |
| Determinism | Conforme | Fingerprints estáveis em `release_governance_engine_test.dart` |
| Explicit failure modes | Conforme | Handlers tipados |
| No silent coercion | Conforme | Ausência ≠ zero; incompatível ≠ pass |
| Policy versioning | Conforme | Registry com freeze; v1 e v1.1 coexistem |
| Integration without recursion | Conforme | Dashboard/Report não chamam engine |
| Consume, don't recalculate QG | Conforme | Source resolver usa `load`/`latest` apenas |

---

## 6. Quality Gate Consumption Review

Release Governance trata `QualityGateSnapshot` como evidência técnica publicada.

| Verificação | Resultado |
|-------------|-----------|
| `ReleaseGovernanceSourceResolver` não chama `QualityGateEngine.evaluate` | Conforme |
| Quality Gate resolve via `injected`, `byId` ou `latest` (opt-in) | Conforme |
| Snapshot referenciado por ID e fingerprint no metadata | Conforme |
| Regras RG003–RG008 leem campos do snapshot | Conforme |
| QG `failed` → decisão `rejected` (provider test) | Conforme |
| QG ausente → `unavailable`/`pending` (engine test) | Conforme |
| `compatibilityPolicy` restringe `quality-gate-release-v1` v1 | Conforme |
| Nenhum recálculo de Metrics/Score/MES/Guardian | Conforme — fakes em source resolver test |

**Conclusão:** consumo do Quality Gate conforme ADR-027 e ADR-028.

---

## 7. Source Resolution Review

`ReleaseGovernanceSourceResolver` resolve 5 famílias de fonte com precedência `injected > byId > latest`.

| Fonte | Modos | Verificado |
|-------|-------|------------|
| `releaseContext` | injected | Sim |
| `qualityGateSnapshot` | injected, byId, latest | Sim |
| `approvalSet` | injected | Sim |
| `waiverSet` | injected | Sim |
| `releaseGovernancePolicy` | inline no request | Sim |

| Verificação | Resultado |
|-------------|-----------|
| `useLatest` opt-in para Quality Gate | Conforme — default `false` |
| Source references com fingerprint | Conforme |
| Project mismatch detectado | Conforme — limitation gerada |
| Refs ordenadas por `sourceType` | Conforme |
| Nenhum engine de origem invocado | Conforme — `release_governance_source_resolver_test.dart` |

**Risco residual:** consumidores futuros podem ignorar opt-in de latest (ver R-RG-010).

---

## 8. Policy Governance Review

| Aspecto | Estado |
|---------|--------|
| Policy ID (v1) | `release-governance-v1` |
| Policy ID (v1.1) | `release-governance-v1.1` |
| Versions | 1 e 2 respectivamente |
| Status | `candidate` (ambas) |
| Owner | `MasterPalm Engineering Governance` |
| Validator | `ReleaseGovernancePolicyValidator` — 20 regras validadas |
| Immutability | Registry frozen após registro |
| Evidence policy | `kReleaseGovernanceEvidenceRequirement` |
| Decision policy | failOnCritical/Blocking; pendingOnMissingApprovals |
| Limitations declaradas | no-cicd, no-crypto, no-auto-waiver-consumption |

**Condição:** políticas **não** promovidas a `active` nesta review.

---

## 9. Policy Versioning Review (v1 vs v1.1)

| Aspecto | v1 | v1.1 |
|---------|----|------|
| Policy ID | `release-governance-v1` | `release-governance-v1.1` |
| Version | 1 | 2 |
| RG006 operator | `isValid` | `isEligible` |
| Demais regras | Baseline | Herdadas de v1 |
| Status | candidate (frozen) | candidate |
| Migração | — | Explícita por `policyId` |

`ReleaseGovernancePolicyV11` deriva de v1 alterando apenas RG006. v1 permanece congelada para replay histórico.

| Verificação | Resultado |
|-------------|-----------|
| v1 e v1.1 registadas no registry | Conforme — `release_governance_policy_v1_test.dart` |
| Fingerprints distintos entre versões | Conforme — models test |
| Sem mutação silenciosa de v1 | Conforme — immutable após freeze |

**Recomendação:** novos consumidores devem preferir v1.1 quando elegibilidade normativa for necessária.

---

## 10. Evaluation Semantics Review

Fluxo: compatibility → eligibility → rule evaluation → approval evaluation → waiver evaluation → condition building → coverage → decision.

| Semântica | Verificado |
|-----------|------------|
| Required unavailable → `unavailable` ou `pending` | Sim |
| Optional unavailable → `skipped` | Sim (RG019, RG020) |
| QG rejected → `rejected` | Sim — provider test |
| Missing approvals → `pending` | Sim — provider test |
| Failed ≠ operational failure | Sim — `status: success` + `decision: rejected` |
| Waivers válidos podem criar `approvedWithConditions` | Sim — semantics test |
| Warnings em RG020 não bloqueiam (optional) | Sim — policy definition |

---

## 11. Approval & Waiver Review

| Componente | Arquivo | Verificado |
|------------|---------|------------|
| Context validator | `release_context_validator.dart` | Sim — `release_context_validator_test.dart` |
| Approval validator | `release_approval_validator.dart` | Sim — `release_approval_validator_test.dart` |
| Waiver validator | `release_waiver_validator.dart` | Sim — `release_waiver_validator_test.dart` |
| Approval evaluator | `release_governance_approval_evaluator.dart` | Sim — semantics test |
| Waiver evaluator | `release_governance_waiver_evaluator.dart` | Sim — semantics test |
| Separation of duties (RG013) | Target `separationOfDutiesSatisfied` | Sim — policy + semantics |
| Expired approvals (RG014) | `expiredApprovalCount` | Sim — approval validator |
| Invalid waivers (RG015) | `invalidWaiverCount` | Sim — waiver validator |

| Limitação | Impacto |
|-----------|---------|
| Autoridade não verificada criptograficamente | Aprovações aceitas por estrutura |
| Sem consumo automático de waiver | Waivers avaliados mas não consumidos no store |

---

## 12. Determinism Review

| Propriedade | Status |
|-------------|--------|
| Snapshot ID determinístico | Verificado em engine test |
| Fingerprint determinístico | Verificado |
| Rule ordering estável | `order` + `ruleId` tie-break |
| Evidence ordering estável | Ordenação por sourceType + evidenceId |
| Replay JSON | Verificado em models test |
| Golden snapshots | Pendente (débito 04.3) |

**Conclusão:** determinismo core verificado; golden suite pendente.

---

## 13. Identity and Fingerprint Review

| Fingerprint | Inputs | Exclui timestamps |
|-------------|--------|-------------------|
| policyFingerprint | Policy canonical JSON | Sim |
| requestFingerprint | Request normalizado | Sim |
| sourceSetFingerprint | Source references | Sim |
| releaseGovernanceFingerprint | policy + request + sources + snapshot body | Sim |
| snapshotId | project + policy + fingerprint + schema | Sim |
| qualityGateSnapshotId | Referência ao QG publicado | Sim |

`toComparableJson` exclui `createdAt` e `evaluatedAt` — verificado em `release_governance_models_test.dart`.

---

## 14. Provider and Store Review

### Provider (`PlatformReleaseGovernanceProvider`)

| Operação | Comportamento | Verificado |
|----------|---------------|------------|
| `evaluate` | Avalia, não publica | Sim |
| `evaluateAndPublish` | Valida + idempotente | Sim |
| `publish` | Grava snapshot | Sim |
| `load/latest/query` | Delega ao store | Sim |
| Policy resolution | Registry + inline policy | Sim |

### Store (`InMemoryReleaseGovernanceStore`)

| Operação | Comportamento | Verificado |
|----------|---------------|------------|
| `save` | Idempotente; conflito se conteúdo difere | Sim — store test |
| `latest` | Ordenação por evaluatedAt desc | Sim |
| `query` | Filtros + paginação | Sim |
| `invalidate` | Remove por ID | Parcial |

**Limitação:** store in-memory — sem persistência entre processos (R-RG-006).

---

## 15. Bootstrap & PlatformCore Review

| Verificação | Resultado |
|-------------|-----------|
| `ReleaseGovernancePlatformBootstrap.register()` no composition root | Conforme |
| `PlatformCore` expõe `ReleaseGovernanceProvider` | Conforme — `platform_core.dart` |
| Dependência de `QualityGateProvider` registada | Conforme |
| `ObservableReleaseGovernanceProvider` decora delegate | Conforme — bootstrap |
| Sem dependência circular engine → store → provider | Conforme |

Pré-requisitos de bootstrap: `QualityGateProvider`, `TelemetryInstrumentation` (para observability decorator).

---

## 16. Report Integration Review

`ReleaseGovernanceReportSource` transforma snapshot em `ReleaseGovernanceReportInputData`.

| Verificação | Resultado |
|-------------|-----------|
| `ReportType.releaseGovernance` registado | Conforme — `report_type.dart` |
| Report não chama Provider | Conforme |
| Report não chama Engine | Conforme — design |
| Decisão, coverage, failed rules expostos | Conforme |
| Pending approvals, active waivers, conditions incluídos | Conforme |
| `ReportComposer` aceita input RG | Conforme — `report_composer.dart` |

**Nota:** teste de integração dedicado pendente; cobertura via design review e composição.

---

## 17. History Integration Review

`ReleaseGovernanceHistoryMapper` produz `HistoryArtifact` tipo `releaseGovernance`.

| Verificação | Resultado |
|-------------|-----------|
| Adapter produz artefato válido | Conforme — mapper implementation |
| Compare detecta mudança de decision | Conforme — `history_comparator.dart` |
| RG não executa History | Conforme |
| History não depende de RG engine | Conforme |
| `HistoryArtifactFactory` suporta `releaseDecisionSnapshot` | Conforme |

---

## 18. Dashboard Integration Review

`ReleaseGovernanceSectionBuilder` renderiza widgets a partir de snapshot injetado.

| Verificação | Resultado |
|-------------|-----------|
| `DashboardSectionType.releaseGovernance` registado | Conforme |
| Dashboard não chama `evaluate` | Conforme |
| RG não chama DashboardEngine | Conforme |
| Secção unavailable quando snapshot ausente | Conforme |
| Widgets: decision, release, environment, QG, approvals, waivers, conditions | Conforme |
| `DashboardSourceResolver` resolve RG por injected/byId/latest | Conforme |

---

## 19. Observability Review

`ObservableReleaseGovernanceProvider` decora todas as operações com `TelemetryInstrumentation`.

| Operação | Instrumentada |
|----------|---------------|
| evaluate | Sim |
| evaluateAndPublish | Sim |
| publish, load, latest, query, invalidate | Sim |

| Verificação | Resultado |
|-------------|-----------|
| `TelemetryComponent.releaseGovernance` registado | Conforme — `telemetry_enums.dart` |
| Resultado inalterado pelo decorator | Conforme (design) |
| Snapshot completo não logado | Conforme (sanitizer) |
| Erro de sink não substitui erro funcional | Parcialmente verificado — teste dedicado pendente |

---

## 20. Security and Data Minimization

| Controle | Estado |
|----------|--------|
| Sem código-fonte em evidence | Conforme |
| Sem tokens/secrets em errors | Conforme (design) |
| Sem stack traces integrais | Conforme |
| Paths absolutos não normativos | Conforme — canonical serializer |
| Limitação `authorityNotCryptographicallyVerified` declarada | Conforme |
| Limitação `noSignatureVerification` na política | Conforme |

Aprovações e waivers validados estruturalmente — identidade externa não verificada nesta sprint.

---

## 21. Test Evidence

**Validação (2026-07-21):** `dart test test/release_governance/` — **61 passed**.

| Suite | Ficheiro | Estado |
|-------|----------|--------|
| Models / policy | `release_governance_models_test.dart` | Verde |
| Engine | `release_governance_engine_test.dart` | Verde |
| Semantics | `release_governance_semantics_test.dart` | Verde |
| Policy v1 / v1.1 | `release_governance_policy_v1_test.dart` | Verde |
| Policy validator | `release_governance_policy_validator_test.dart` | Verde |
| Source resolver | `release_governance_source_resolver_test.dart` | Verde |
| Provider | `release_governance_provider_test.dart` | Verde |
| Store | `release_governance_store_test.dart` | Verde |
| Context validator | `release_context_validator_test.dart` | Verde |
| Approval validator | `release_approval_validator_test.dart` | Verde |
| Waiver validator | `release_waiver_validator_test.dart` | Verde |
| **Total `test/release_governance/`** | **11 ficheiros + fixtures** | **61 testes** |

Cenários cobertos: avaliação passing end-to-end, determinismo/replay, QG ausente, QG rejeitado, aprovações em falta, publicação idempotente, validação de policy/context/approval/waiver, semântica de decisão, store query/latest.

**Débito residual:** integração dedicada Report/History/Dashboard, golden snapshots, observability hardening, stress test, operadores exaustivos.

---

## 22. Performance Evidence

Sem benchmark formal nesta sprint. Engine stateless com 20 regras executa em tempo negligível em testes.

| Cenário | Observação |
|---------|------------|
| 20 regras (policy v1) | < 100ms em ambiente de teste |
| 100 regras (stress) | Pendente |
| Store query 1000 snapshots | Pendente |

Guardrail: sem critério absoluto de latência nesta fase.

---

## 23. Known Limitations

| ID | Limitação | Impacto | Mitigação |
|----|-----------|---------|-----------|
| L-001 | Políticas candidate | Não normativas para produção | Manter status; AR para promoção |
| L-002 | Store in-memory | Sem persistência | Sprint futura |
| L-003 | Sem verificação criptográfica | Aprovações não assinadas | Limitation explícita; sprint futura |
| L-004 | RG006 v1 usa `isValid` | Semântica estrutural vs elegibilidade | Migrar para v1.1 |
| L-005 | Sem CI/CD enforcement | Release manual | Sprint 04.3+ |
| L-006 | Sem consumo automático de waiver | Waivers não consumidos no store | Limitation na política |
| L-007 | Integrações sem teste dedicado | Risco de regressão residual | Plano 04.3 |

---

## 24. Technical Debt

| Item | Prioridade | Sprint alvo |
|------|------------|-------------|
| Testes de integração Report/History/Dashboard | Média | 04.3 |
| Golden snapshots normativos | Média | 04.3 |
| Observability hardening dedicado | Média | 04.3 |
| Operadores/handlers — matriz exaustiva | Baixa | 04.3 |
| Stress test + performance baseline | Baixa | 04.3 |
| Assinatura criptográfica de aprovações | Média | Futura |
| Persistência de store | Média | 04.3+ |
| Integração CI/CD | Alta | 04.3+ |
| Promoção v1.1 como default active | Média | AR de promoção |

---

## 25. Risk Register

| ID | Descrição | Prob. | Impacto | Severidade | Mitigação | Owner | Status |
|----|-----------|-------|---------|------------|-----------|-------|--------|
| R-RG-001 | Dashboard lazy ProviderRegistry resolve RG tardiamente | Média | Baixo | Baixa | Bootstrap explícito | Platform | Aberto |
| R-RG-002 | RG006 `isValid` em v1 não reflete elegibilidade normativa | Média | Médio | **Média** | v1.1 com `isEligible`; documentação | Governance | Mitigado |
| R-RG-003 | Aprovações sem verificação criptográfica | Alta | Alto | **Alta** | Limitation explícita; sprint futura | Security | Aceito |
| R-RG-004 | Política candidate não active | Baixa | Médio | Baixa | AR obrigatória para promoção | Governance | Aceito |
| R-RG-005 | Store in-memory sem persistência | Média | Médio | Média | Invalidate + store persistente | Platform | Aberto |
| R-RG-006 | `latest` em consumidores sem opt-in | Média | Alto | Média | Default `useLatest: false` | Platform | Mitigado |
| R-RG-007 | QG snapshot stale (RG008 freshness) | Média | Médio | Média | Regra P7D + warning `staleQualityGate` | Platform | Monitorado |
| R-RG-008 | Policy drift pós-registro | Baixa | Alto | Média | Registry freeze + fingerprint | Governance | Mitigado |
| R-RG-009 | Sem CI/CD gate | Alta | Alto | **Alta** | Sprint 04.3 | Governance | Adiado |
| R-RG-010 | Integração futura com pipeline externo | Média | Alto | Média | Design baseado em snapshots | Platform | Adiado |

---

## 26. ADR Compliance

| ADR | Decisão | Conformidade |
|-----|---------|--------------|
| ADR-028 | RG consome QualityGateSnapshot publicado | **Conforme** |
| ADR-028 | RG não recalcula Quality Gate | **Conforme** |
| ADR-028 | Determinismo e fingerprints | **Conforme** |
| ADR-028 | Ausência/incompatibilidade explícitas | **Conforme** |
| ADR-028 | Publicação idempotente | **Conforme** |
| ADR-028 | Policy version obrigatória | **Conforme** |
| ADR-027 (upstream) | QG não recalcula engines | **Conforme** — RG herda via consumo |

---

## 27. Traceability Summary

Matriz completa: `docs/release_governance/release_governance_traceability_matrix.md`.

| Categoria | Total | covered | partiallyCovered | notCovered | notApplicable |
|-----------|-------|---------|------------------|------------|---------------|
| Regras RG001–RG020 | 20 | 18 | 2 | 0 | 0 |
| Integrações (Report, History, Dashboard, Observability) | 4 | 2 | 2 | 0 | 0 |
| Store/Provider core | 8 | 7 | 1 | 0 | 0 |
| Validadores | 4 | 4 | 0 | 0 | 0 |

Regras críticas (RG001–RG004, RG011–RG012, RG015) com status `covered` baseado em evidência de teste. RG019/RG020 optional com cobertura parcial. Integrações Report/Dashboard sem teste dedicado — `partiallyCovered`.

---

## 28. Release Decision

### **GO WITH CONDITIONS — Release 4.1 Beta**

**Fundamentação:**

| Critério GO | Estado |
|-------------|--------|
| `dart analyze` sem issues nos ficheiros RG | Conforme |
| Testes verdes | Conforme (**61** em `test/release_governance/`) |
| Nenhum item crítico `notCovered` | Conforme — limitações explícitas |
| Sem dependência circular | Conforme |
| Replay determinístico | Conforme (core) |
| Source resolver não executa QG engine | Conforme |
| Report/Dashboard não executam RG engine | Conforme |
| Store idempotente | Conforme |
| Observability transparente | Conforme (design) |
| ADR-028 concluído | Conforme |
| Documentação Part 3 concluída | Conforme |

**Condições que impedem GO pleno:**

1. Políticas permanecem `candidate`
2. Store in-memory sem persistência
3. Sem autenticação criptográfica de aprovações/autoridades
4. RG006 em v1 usa `isValid` — preferir v1.1 para elegibilidade
5. Sem integração CI/CD
6. Débitos residuais: testes de integração dedicados, golden, observability hardening

---

## 29. Conditions

Para promoção a **GO** pleno ou política `active`:

1. Completar testes de integração Report/History/Dashboard/Observability
2. Implementar persistência de store (se requerida para produção)
3. Avaliar requisitos de assinatura criptográfica com Security Governance
4. Promover `release-governance-v1.1` como baseline (RG006 `isEligible`)
5. Architecture Review de promoção candidate → active
6. Integração CI/CD (se requerida para enforcement)

Até lá, consumidores devem tratar `release-governance-v1` e `release-governance-v1.1` como **candidate** com limitações documentadas.

---

## 30. Final Sign-off

| Papel | Nome | Decisão | Data |
|-------|------|---------|------|
| Engineering Lead | _pendente_ | GO WITH CONDITIONS | 2026-07-21 |
| Architecture Governance | _pendente_ | GO WITH CONDITIONS | 2026-07-21 |
| QA / Test | _pendente_ | Condicional — débitos residuais 04.3 | 2026-07-21 |
| Security Governance | _pendente_ | Condicional — sem crypto auth | 2026-07-21 |

**Assinatura eletrônica:** documento produzido como parte da Sprint 04.2 Part 3. Sign-off formal requer aprovação humana explícita.

---

## Anexos

- `docs/release_governance/release_governance_traceability_matrix.md`
- `docs/release_governance/README.md`
- `docs/release_governance/release_governance_release_checklist.md`
- `docs/adr/ADR-028-release-governance-authorizes-release-progression.md`
- `docs/adr/ADR-027-quality-gates-are-deterministic-policy-evaluations.md`
