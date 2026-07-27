# Quality Gate — Release Checklist (Sprint 04.1)

**Sprint:** 04.1 — Quality Gates Foundation
**Política:** `quality-gate-release-v1` (candidate)
**Última atualização:** 2026-07-21

Use este checklist antes de declarar a sprint concluída ou promover a política candidate.

---

## Arquitetura

- [ ] `QualityGateEngine` é stateless (sem estado mutável entre avaliações)
- [ ] Providers own IO (`PlatformQualityGateProvider` delega resolução e store)
- [ ] Nenhum engine de origem é executado durante avaliação do Gate
- [ ] `evaluate()` não publica no store
- [ ] `evaluateAndPublish()` valida snapshot antes de gravar
- [ ] Report não executa Quality Gate
- [ ] Dashboard não executa Quality Gate
- [ ] Quality Gate não executa Dashboard
- [ ] History permanece responsável pelo diff
- [ ] Observability não altera resultado (decorator transparente)
- [ ] Nenhuma dependência circular introduzida (engine → store → provider)

**Evidência:** `lib/quality_gate/`, `test/quality_gate/quality_gate_integration_test.dart`, `test/quality_gate/quality_gate_source_resolver_test.dart`

---

## Política

- [ ] Política versionada (`policyId` + `policyVersion`)
- [ ] Política validada por `QualityGatePolicyValidator`
- [ ] Owner definido (`MasterPalm Engineering Governance`)
- [ ] Status explícito (`candidate` — não `active` sem AR)
- [ ] Policy fingerprint calculado e estável
- [ ] Changelog presente
- [ ] 15 regras (QG001–QG015) em 7 rule sets
- [ ] Limitações QG011 e QG015 documentadas
- [ ] Nenhuma mutação silenciosa da v1 após registro

**Evidência:** `lib/quality_gate/policies/quality_gate_release_policy_v1.dart`, `test/quality_gate/quality_gate_models_test.dart`

---

## Determinismo

- [ ] Mesma política + mesmas fontes → mesma decisão
- [ ] Mesma entrada → mesmo `qualityGateSnapshotId`
- [ ] Mesma entrada → mesmo `qualityGateFingerprint`
- [ ] Ordem de entrada não altera resultado (regras e refs ordenadas)
- [ ] Serialização/deserialização preserva identidade normativa
- [ ] `toComparableJson` exclui timestamps não normativos
- [ ] Canonicalização independente de locale/timezone/path separator
- [ ] Replay: `toJson` → `fromJson` → fingerprint idêntico

**Evidência:** `quality_gate_integration_test.dart` (deterministic snapshot id), `quality_gate_models_test.dart`

---

## Testes

### Core

- [x] `dart analyze lib` sem issues
- [x] `dart test test/quality_gate` verde (**108** testes)
- [x] Testes de integração (cenários A–F, determinismo, report)
- [x] Testes de source resolver isolados
- [x] Testes de store (idempotência, query)
- [x] Testes de operadores (casos básicos)

### Cobertura alvo (Part 3)

- [x] Target resolvers (suite consolidada `quality_gate_target_resolvers_test.dart`)
- [ ] Operadores exaustivos (todos os 27)
- [x] Handlers (missing + incompatible) — casos principais
- [x] Precedência de decisão (`quality_gate_decision_precedence_test.dart`)
- [x] Golden snapshot QG011 (`test/golden/quality_gate/error_qg011_capability_gap.json`)
- [x] History integration dedicado
- [x] Dashboard integration dedicado
- [ ] Observability hardening dedicado
- [ ] Stress test (~500 regras)
- [ ] Property-based / mutation-oriented tests

### Integrações

- [x] Report consome snapshot sem engine
- [x] History mapper produz artefato válido
- [x] Dashboard section com snapshot injetado
- [ ] Observability instrumenta sem alterar retorno (teste dedicado pendente)

---

## Compatibilidade

- [ ] Consistência de `projectId` entre fontes (QG001)
- [ ] Consistência de `commitId` quando exigido (QG002)
- [ ] Schema version verificado por compatibility checker
- [ ] Calculation version preservado em source references
- [ ] Policy version explícita no request ou registry
- [ ] Incompatibilidade nunca convertida silenciosamente em `passed`
- [ ] Ausência nunca convertida silenciosamente em zero

---

## Segurança e minimização de dados

- [ ] Erros sanitizados (sem stack trace integral)
- [ ] Evidence não contém código-fonte
- [ ] Telemetry não loga snapshot completo
- [ ] Report não expõe secrets
- [x] Strings sentinela sensíveis ausentes de outputs (teste básico)

---

## Limitações conhecidas (aceitas com condição)

- [ ] QG011: `criticalCycleCount` → `unsupported` (documentado)
- [ ] QG015: `historyRegressionCount` derivado (documentado)
- [ ] Política permanece `candidate`
- [ ] Store in-memory apenas (sem persistência física)
- [ ] Sem integração CI/CD

---

## Documentação

- [ ] `docs/quality_gate/quality_gate_traceability_matrix.md`
- [ ] `docs/quality_gate/critical_cycle_mapping.md`
- [ ] `docs/quality_gate/README.md`
- [ ] `docs/quality_gate/quality_gate_release_checklist.md` (este documento)
- [ ] `docs/adr/ADR-027-quality-gates-are-deterministic-policy-evaluations.md`
- [ ] `docs/architecture-reviews/AR-013-quality-gates-foundation.md`

---

## Release

- [ ] `dart format --output=none --set-exit-if-changed lib test`
- [ ] `dart analyze lib test`
- [x] `dart test` — todos verdes (**721**)
- [ ] Architecture Review #013 concluída
- [ ] Decisão formal registrada (GO / GO WITH CONDITIONS / NO-GO)
- [ ] **Não** fazer commit sem pedido explícito
- [ ] **Não** fazer push
- [ ] **Não** fazer deploy
- [ ] **Não** promover política candidate → active sem AR

---

## Decisão esperada

Com base no estado atual da Sprint 04.1 Part 3:

| Resultado | Condição |
|-----------|----------|
| **GO WITH CONDITIONS** | Arquitetura sólida; limitações QG011/QG015 documentadas; **108** testes QG verdes; débitos residuais 04.2 |
| **GO** | Todos os itens acima marcados; zero itens críticos `notCovered` |
| **NO-GO** | Determinismo quebrado, dependência circular, ou recálculo de engines |

Ver decisão fundamentada em `AR-013-quality-gates-foundation.md`.
