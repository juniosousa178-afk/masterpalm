# Architecture Review #013 — Quality Gates Foundation

| Campo | Valor |
|-------|-------|
| **ID** | AR-013 |
| **Título** | Quality Gates Foundation |
| **Sprint** | 04.1 |
| **Data** | 2026-07-21 |
| **Revisor** | MasterPalm Engineering Governance |
| **ADR relacionado** | ADR-027 |
| **Política** | `quality-gate-release-v1` (candidate) |

---

## 1. Executive Summary

A Sprint 04.1 entrega a fundação de Quality Gates na MasterPalm Engineering Platform: um engine stateless que avalia políticas versionadas sobre artefatos publicados, com provider, store in-memory, integrações Report/History/Dashboard/Observability, e política candidate com 15 regras (QG001–QG015).

A arquitetura cumpre os princípios de determinismo, não-recálculo de engines de origem, e separação entre falha operacional e reprovação normativa. Duas limitações conhecidas impedem GO pleno:

1. **QG011** — `criticalCycleCount` sem métrica autoritativa (target `unsupported`)
2. **QG015** — `historyRegressionCount` derivado de metadata, não campo autoritativo do History

**Decisão:** **GO WITH CONDITIONS — Release 4.0 Beta**

---

## 2. Scope Reviewed

| Área | Incluído |
|------|----------|
| Domínio imutável (models, enums, policy) | Sim |
| Engine e evaluators | Sim |
| Source resolver e target registry | Sim |
| Provider e store | Sim |
| Bootstrap e PlatformCore | Sim |
| Integrações Report, History, Dashboard, Observability | Sim |
| Política `quality-gate-release-v1` | Sim |
| Testes `test/quality_gate/` | Sim |
| Documentação Sprint 04.1 Part 3 | Sim |

**Fora de escopo:** CI/CD, persistência física, frontend, promoção candidate→active.

---

## 3. Architecture Baseline

A plataforma segue o padrão estabelecido por Score, MES e Dashboard:

- **Models** — tipos imutáveis com serialização canônica
- **Engine** — lógica pura, sem IO
- **Provider** — orquestração e persistência
- **Bootstrap** — composition root via `ProviderRegistry`

Quality Gate adere a este baseline sem introduzir dependências circulares.

---

## 4. Implemented Components

| Componente | Arquivo | Função |
|------------|---------|--------|
| Models | `lib/models/quality_gate/*` | Policy, request, snapshot, enums, evidence |
| Engine | `lib/quality_gate/quality_gate_engine.dart` | Avaliação stateless |
| Source resolver | `lib/quality_gate/quality_gate_source_resolver.dart` | Resolve fontes sem recalcular |
| Target registry | `lib/quality_gate/quality_gate_target_registry.dart` | 8 resolvers por domínio |
| Operator evaluator | `lib/quality_gate/quality_gate_operator_evaluator.dart` | 27 operadores tipados |
| Handlers | `lib/quality_gate/quality_gate_handlers.dart` | Missing/incompatible/impact |
| Rule evaluator | `lib/quality_gate/quality_gate_rule_evaluator.dart` | Avaliação por regra |
| Decision aggregator | `lib/quality_gate/quality_gate_decision_aggregator.dart` | Precedência de decisão |
| Provider | `lib/providers/platform_quality_gate_provider.dart` | Contrato público |
| Store | `lib/quality_gate/stores/in_memory_quality_gate_store.dart` | Persistência in-memory |
| Bootstrap | `lib/quality_gate/quality_gate_platform_bootstrap.dart` | DI |
| Policy | `lib/quality_gate/policies/quality_gate_release_policy_v1.dart` | 15 regras candidate |
| Report source | `lib/report/sources/quality_gate_report_source.dart` | Input para ReportEngine |
| History mapper | `lib/history/mappers/quality_gate_history_mapper.dart` | Artefato History |
| Dashboard builder | `lib/dashboard/builders/quality_gate_section_builder.dart` | Secção Dashboard |
| Observability | `lib/observability/instrumentation/observable_quality_gate_provider.dart` | Decorator |

---

## 5. Architectural Principles

| Princípio | Conformidade | Evidência |
|-----------|--------------|-----------|
| Single responsibility | Conforme | Engine avalia; Provider faz IO |
| Immutability | Conforme | Models com listas defensivas |
| Determinism | Conforme | Fingerprints estáveis em testes |
| Explicit failure modes | Conforme | Handlers tipados |
| No silent coercion | Conforme | Ausência ≠ zero; incompatível ≠ pass |
| Policy versioning | Conforme | Registry com freeze |
| Integration without recursion | Conforme | Dashboard/Report não chamam engine |

---

## 6. Source Resolution Review

`QualityGateSourceResolver` resolve 7 tipos de fonte com precedência `injected > byId > latest`.

| Verificação | Resultado |
|-------------|-----------|
| `useLatest` opt-in | Conforme — default `false` |
| History somente injected | Conforme |
| Nenhum engine de origem invocado | Conforme — fakes em source resolver test |
| Source references com fingerprint | Conforme |
| Project mismatch detectado | Conforme — limitation gerada |
| Ordem não altera sourceSetFingerprint | Conforme — refs ordenadas |

**Risco residual:** consumidores futuros podem ignorar opt-in de latest (ver Risk Register R-QG-010).

---

## 7. Policy Governance Review

| Aspecto | Estado |
|---------|--------|
| Policy ID | `quality-gate-release-v1` |
| Version | 1 |
| Status | `candidate` |
| Owner | MasterPalm Engineering Governance |
| Validator | `QualityGatePolicyValidator` — 15 regras validadas |
| Immutability | Registry frozen após registro |
| Evidence policy | `kReleaseGateEvidencePolicy` — todas as regras |
| Decision policy | failOnCritical, failOnBlocking, partialOnRequiredUnavailable |

**Condição:** política **não** promovida a `active` nesta review.

---

## 8. Evaluation Semantics Review

Fluxo: compatibility → eligibility → rule evaluation → rule set aggregation → coverage → decision.

| Semântica | Verificado |
|-----------|------------|
| Required unavailable → `unavailable` ou `partial` | Sim |
| Optional unavailable → `skipped` | Sim (QG012–QG015) |
| Unsupported required → `error` | Sim (QG011) |
| Failed ≠ operational failure | Sim — `status: success` + `decision: failed` |
| Warnings não afetam decisão (policy) | Sim — `warningsAffectDecision: false` |

---

## 9. Determinism Review

| Propriedade | Status |
|-------------|--------|
| Snapshot ID determinístico | Verificado em integration test |
| Fingerprint determinístico | Verificado |
| Rule ordering estável | `order` + `ruleId` tie-break |
| Evidence ordering estável | Ordenação por sourceType + evidenceId |
| Replay JSON | Parcialmente verificado (models test) |
| Golden snapshots | Pendente (Part 3) |

**Conclusão:** determinismo core verificado; golden suite pendente.

---

## 10. Identity and Fingerprint Review

| Fingerprint | Inputs | Exclui timestamps |
|-------------|--------|-------------------|
| policyFingerprint | Policy canonical JSON | Sim |
| requestFingerprint | Request normalizado | Sim |
| sourceSetFingerprint | Source references | Sim |
| qualityGateFingerprint | policy + request + sources + snapshot body | Sim |
| snapshotId | project + policy + fingerprint + schema | Sim |

`toComparableJson` exclui `createdAt` e `evaluatedAt` — verificado.

---

## 11. Provider and Store Review

### Provider (`PlatformQualityGateProvider`)

| Operação | Comportamento | Verificado |
|----------|---------------|------------|
| `evaluate` | Avalia, não publica | Sim |
| `evaluateAndPublish` | Valida + idempotente | Sim |
| `publish` | Grava snapshot | Parcial |
| `load/latest/query` | Delega ao store | Parcial |
| Policy resolution | Registry + inline policy | Sim |

### Store (`InMemoryQualityGateStore`)

| Operação | Comportamento | Verificado |
|----------|---------------|------------|
| `save` | Idempotente; conflito se conteúdo difere | Sim |
| `latest` | Ordenação por evaluatedAt desc | Sim |
| `query` | Filtros + paginação | Parcial |
| `invalidate` | Remove por ID | Parcial |

**Limitação:** store in-memory — sem persistência entre processos (R-QG-006).

---

## 12. Report Integration Review

`QualityGateReportSource` transforma snapshot em `QualityGateReportInputData`.

| Verificação | Resultado |
|-------------|-----------|
| Report não chama Provider | Conforme |
| Report não chama Engine | Conforme — integration test |
| Decisão, coverage, failed rules expostos | Conforme |
| Limitations e warnings incluídos | Conforme |

---

## 13. History Integration Review

`QualityGateHistoryMapper` produz `HistoryArtifact` tipo `qualityGate`.

| Verificação | Resultado |
|-------------|-----------|
| Adapter produz artefato válido | Conforme |
| Compare detecta mudança de decision | Conforme |
| Gate não executa History | Conforme |
| History não depende de Gate engine | Conforme |

**Limitação:** `historyRegressionCount` derivado — ver secção 19.

---

## 14. Dashboard Integration Review

`QualityGateSectionBuilder` renderiza widgets a partir de snapshot injetado.

| Verificação | Resultado |
|-------------|-----------|
| Dashboard não chama evaluate | Conforme |
| Gate não chama DashboardEngine | Conforme |
| Secção unavailable quando snapshot ausente | Conforme |
| Widgets: decision, coverage, eligibility, compatibility | Conforme |

**Risco:** lazy ProviderRegistry no Dashboard (R-QG-001).

---

## 15. Observability Review

`ObservableQualityGateProvider` decora todas as operações com `TelemetryInstrumentation`.

| Operação | Instrumentada |
|----------|---------------|
| evaluate | Sim |
| evaluateAndPublish | Sim |
| publish, load, latest, query, invalidate | Sim |

| Verificação | Resultado |
|-------------|-----------|
| Resultado inalterado pelo decorator | Conforme (design) |
| Snapshot completo não logado | Conforme (sanitizer) |
| Erro de sink não substitui erro funcional | Parcialmente verificado — teste dedicado pendente (04.2) |

---

## 16. Security and Data Minimization

| Controle | Estado |
|----------|--------|
| Sem código-fonte em evidence | Conforme |
| Sem tokens/secrets em errors | Conforme (design) |
| Sem stack traces integrais | Conforme |
| Paths absolutos não normativos | Conforme — canonical serializer |
| Payloads completos filtrados | Conforme |

Testes com strings sentinela — `quality_gate_security_test.dart` (básico).

---

## 17. Test Evidence

**Validação (2026-07-21):** `dart analyze lib` — sem issues; `dart test` — **721 passed**; `dart test test/quality_gate/` — **108 passed**.

| Suite | Ficheiro | Estado |
|-------|----------|--------|
| Models / policy | `quality_gate_models_test.dart` | Verde |
| Integration | `quality_gate_integration_test.dart` | Verde |
| Source resolver | `quality_gate_source_resolver_test.dart` | Verde |
| Target resolvers (consolidado) | `quality_gate_target_resolvers_test.dart` | Verde |
| Handlers | `quality_gate_handlers_test.dart` | Verde |
| Precedência | `quality_gate_decision_precedence_test.dart` | Verde |
| Replay | `quality_gate_replay_test.dart` | Verde |
| Policy versioning | `quality_gate_policy_versioning_test.dart` | Verde |
| Golden | `quality_gate_golden_test.dart` | Verde |
| Store | `quality_gate_store_test.dart` | Verde |
| Operators (básico) | `quality_gate_operator_evaluator_test.dart` | Verde |
| PlatformCore | `quality_gate_platform_core_test.dart` | Verde |
| Report | `quality_gate_report_test.dart` | Verde |
| History | `quality_gate_history_integration_test.dart` | Verde |
| Dashboard | `quality_gate_dashboard_integration_test.dart` | Verde |
| Security | `quality_gate_security_test.dart` | Verde |
| **Total `test/quality_gate/`** | **16 ficheiros** | **108 testes** |

Cenários cobertos: QG011 capability gap (`error`), Guardian NO-GO (regra QG003), MES abaixo do mínimo (QG007), telemetria optional ausente, score ausente, mismatch de projeto (QG001), determinismo, idempotência, report sem engine, replay JSON, golden normativo.

**Débito residual:** operadores/handlers matriz 100%, store/provider avançados, observability hardening dedicado, stress 500 regras, property/mutation-oriented, 8 ficheiros de target por domínio (substituídos por suite consolidada).

---

## 18. Performance Evidence

Sem benchmark formal nesta sprint. Engine stateless com 15 regras executa em tempo negligível em testes de integração.

| Cenário | Observação |
|---------|------------|
| 15 regras (policy v1) | < 100ms em ambiente de teste |
| 500 regras (stress) | Pendente Part 3 |
| Store query 1000 snapshots | Pendente Part 3 |

Guardrail: sem critério absoluto de latência nesta fase.

---

## 19. Known Limitations

| ID | Limitação | Impacto | Mitigação |
|----|-----------|---------|-----------|
| L-001 | `criticalCycleCount` sem métrica autoritativa | QG011 não avaliável | Target `unsupported`; doc `critical_cycle_mapping.md` |
| L-002 | `historyRegressionCount` derivado | QG015 semântica fraca | Limitation `history.regressionCount.derived`; regra optional |
| L-003 | Política candidate | Não normativa para produção | Manter status; AR para promoção |
| L-004 | Store in-memory | Sem persistência | Sprint futura |
| L-005 | Cobertura exaustiva Part 3 (stress, observability, operadores 100%) | Risco de regressão residual | Plano Sprint 04.2 |
| L-006 | Sem CI/CD gate | Gate manual | Sprint 04.2+ |

---

## 20. Technical Debt

| Item | Prioridade | Sprint alvo |
|------|------------|-------------|
| Operadores/handlers — matriz exaustiva | Média | 04.2 |
| Store/provider/observability — testes avançados | Média | 04.2 |
| Stress 500 regras + performance baseline | Baixa | 04.2 |
| Métrica `graph.cycle.critical_count` no Metrics Engine | Média | Futura |
| Campo autoritativo `regressionCount` no History | Média | Futura |
| Exemplos sem dependência de `test/` | Baixa | 04.2 |
| Persistência de store | Baixa | 04.2+ |
| Integração CI/CD | Baixa | 04.2+ |

**Concluído na Part 3:** precedência, replay, golden (QG011), target resolvers consolidados, history/dashboard/report/platform core, policy versioning, security básico.

---

## 21. Risk Register

| ID | Descrição | Prob. | Impacto | Severidade | Mitigação | Owner | Status | Fechamento |
|----|-----------|-------|---------|------------|-----------|-------|--------|------------|
| R-QG-001 | Dashboard lazy ProviderRegistry pode resolver Gate tardiamente | Média | Baixo | Baixa | Bootstrap explícito; testes de integração | Platform | Aberto | Teste dedicado dashboard |
| R-QG-002 | `criticalCycleCount` sem métrica autoritativa | Alta | Médio | **Média** | Target `unsupported`; doc; não mapear `graph.cycle.count` | Platform | Aceito | Métrica oficial ou policy v2 |
| R-QG-003 | `historyRegressionCount` derivado de metadata | Média | Médio | **Média** | Limitation explícita; regra optional | Platform | Aceito | Campo autoritativo no History |
| R-QG-004 | Política candidate não active | Baixa | Médio | Baixa | AR obrigatória para promoção | Governance | Aceito | AR de promoção |
| R-QG-005 | Serializers em snapshots grandes | Baixa | Médio | Baixa | Stress test Part 3 | Platform | Aberto | Benchmark |
| R-QG-006 | Crescimento do store in-memory | Média | Baixo | Baixa | Invalidate + persistência futura | Platform | Aberto | Store persistente |
| R-QG-007 | Evolução de schemas externos | Média | Alto | Média | Compatibility checker + schema version | Platform | Monitorado | Testes de compatibilidade |
| R-QG-008 | Policy drift (mutação pós-registro) | Baixa | Alto | Média | Registry freeze + fingerprint | Governance | Mitigado | Testes de versioning |
| R-QG-009 | Golden snapshot maintenance | Média | Baixo | Baixa | Atualização explícita apenas | Platform | Aberto | Golden suite |
| R-QG-010 | `latest` em consumidores futuros sem opt-in | Média | Alto | Média | Default `useLatest: false`; documentação | Platform | Mitigado | Lint/review em novos consumidores |
| R-QG-011 | Integração futura CI/CD | Baixa | Alto | Média | Sprint 04.2 Release Governance | Governance | Adiado | Design 04.2 |

---

## 22. ADR Compliance

| ADR | Decisão | Conformidade |
|-----|---------|--------------|
| ADR-027 | Gate consome artefatos publicados | **Conforme** |
| ADR-027 | Gate não recalcula engines | **Conforme** |
| ADR-027 | Determinismo e fingerprints | **Conforme** |
| ADR-027 | Ausência/incompatibilidade explícitas | **Conforme** |
| ADR-027 | Publicação idempotente | **Conforme** |
| ADR-027 | Policy version obrigatória | **Conforme** |

---

## 23. Release Decision

### **GO WITH CONDITIONS — Release 4.0 Beta**

**Fundamentação:**

| Critério GO | Estado |
|-------------|--------|
| `dart analyze` sem issues | Conforme (`lib` sem issues) |
| Testes verdes | Conforme (**721** total; **108** em `test/quality_gate/`) |
| Nenhum item crítico `notCovered` | Conforme — limitações explícitas |
| Sem dependência circular | Conforme |
| Replay determinístico | Conforme (core) |
| Source resolver não executa engines | Conforme |
| Report/Dashboard não executam Gate | Conforme |
| Store idempotente | Conforme |
| Observability transparente | Conforme (design) |
| ADR-027 concluído | Conforme |
| Documentação concluída | Conforme (Part 3) |

**Condições que impedem GO pleno:**

1. QG011 — capability gap em `criticalCycleCount`
2. QG015 — regressão derivada, não autoritativa
3. Política permanece `candidate`
4. Débitos residuais: operadores/handlers 100%, observability hardening, stress test, exemplos públicos sem `test/`

---

## 24. Conditions

Para promoção a **GO** pleno ou política `active`:

1. Resolver ou reformular QG011 (métrica oficial ou policy v2)
2. Formalizar contrato de `historyRegressionCount` no History ou tornar QG015 informational
3. Completar débitos residuais de teste (operadores 100%, observability, stress)
4. Architecture Review de promoção candidate → active
5. Persistência de store (se requerida para produção)

Até lá, consumidores devem tratar `quality-gate-release-v1` como **candidate** com limitações documentadas.

---

## 25. Final Sign-off

| Papel | Nome | Decisão | Data |
|-------|------|---------|------|
| Engineering Lead | _pendente_ | GO WITH CONDITIONS | 2026-07-21 |
| Architecture Governance | _pendente_ | GO WITH CONDITIONS | 2026-07-21 |
| QA / Test | _pendente_ | Condicional — débitos residuais 04.2 | 2026-07-21 |

**Assinatura eletrônica:** documento produzido como parte da Sprint 04.1 Part 3. Sign-off formal requer aprovação humana explícita.

---

## Anexos

- `docs/quality_gate/quality_gate_traceability_matrix.md`
- `docs/quality_gate/critical_cycle_mapping.md`
- `docs/quality_gate/README.md`
- `docs/quality_gate/quality_gate_release_checklist.md`
- `docs/adr/ADR-027-quality-gates-are-deterministic-policy-evaluations.md`
