# Release Governance — Release Checklist (Sprint 04.2)

**Sprint:** 04.2 — Release Governance Foundation
**Políticas:** `release-governance-v1` (candidate), `release-governance-v1.1` (candidate)
**Última atualização:** 2026-07-21

Use este checklist antes de declarar a sprint concluída ou promover políticas candidate.

---

## Arquitetura

- [ ] `ReleaseGovernanceEngine` é stateless (sem estado mutável entre avaliações)
- [ ] Providers own IO (`PlatformReleaseGovernanceProvider` delega resolução e store)
- [ ] Nenhum Quality Gate Engine é executado durante avaliação de Release Governance
- [ ] Nenhum engine de origem do QG (Metrics/Score/MES/Guardian) é executado
- [ ] `evaluate()` não publica no store
- [ ] `evaluateAndPublish()` valida snapshot antes de gravar
- [ ] Report não executa Release Governance
- [ ] Dashboard não executa Release Governance
- [ ] Release Governance não executa Dashboard
- [ ] History permanece responsável pelo diff
- [ ] Observability não altera resultado (decorator transparente)
- [ ] Nenhuma dependência circular introduzida (engine → store → provider)

**Evidência:** `lib/release_governance/`, `test/release_governance/release_governance_engine_test.dart`, `test/release_governance/release_governance_source_resolver_test.dart`

---

## Política

- [ ] Políticas versionadas (`policyId` + `policyVersion`)
- [ ] Políticas validadas por `ReleaseGovernancePolicyValidator`
- [ ] Owner definido (`MasterPalm Engineering Governance`)
- [ ] Status explícito (`candidate` — não `active` sem AR)
- [ ] Policy fingerprint calculado e estável
- [ ] Changelog presente (v1 e v1.1)
- [ ] 20 regras (RG001–RG020) em 7 rule sets
- [ ] v1.1 com RG006 `isEligible` documentado
- [ ] Limitações no-cicd, no-crypto declaradas
- [ ] Nenhuma mutação silenciosa de v1 após registro

**Evidência:** `lib/release_governance/policies/release_governance_policy_v1.dart`, `lib/release_governance/policies/release_governance_policy_v1_1.dart`, `test/release_governance/release_governance_policy_v1_test.dart`

---

## Quality Gate Consumption

- [ ] `ReleaseGovernanceSourceResolver` resolve QG via `injected`, `byId` ou `latest` (opt-in)
- [ ] Resolver usa `QualityGateProvider.load`/`latest` — nunca `evaluate()`
- [ ] Snapshot referenciado por ID e fingerprint no metadata
- [ ] `compatibilityPolicy` restringe `quality-gate-release-v1` v1
- [ ] QG `failed` produz decisão `rejected` (não erro operacional)
- [ ] QG ausente produz `unavailable` ou `pending`
- [ ] Regras RG003–RG008 leem campos do snapshot publicado

**Evidência:** `release_governance_source_resolver_test.dart`, `release_governance_provider_test.dart` (rejected QG), `release_governance_engine_test.dart` (QG ausente)

---

## Aprovações e Waivers

- [ ] `ReleaseContextValidator` valida contexto obrigatório
- [ ] `ReleaseApprovalValidator` valida estrutura de aprovações
- [ ] `ReleaseWaiverValidator` valida estrutura de waivers
- [ ] Aprovações em falta → `pending`
- [ ] Aprovações rejeitadas → `rejected`
- [ ] Separation of duties avaliada (RG013)
- [ ] Waivers inválidos/expirados bloqueiam (RG015–RG016)
- [ ] Limitação `authorityNotCryptographicallyVerified` documentada

**Evidência:** `release_context_validator_test.dart`, `release_approval_validator_test.dart`, `release_waiver_validator_test.dart`, `release_governance_provider_test.dart` (missing approvals)

---

## Determinismo

- [ ] Mesma política + mesmas fontes → mesma decisão
- [ ] Mesma entrada → mesmo `releaseDecisionSnapshotId`
- [ ] Mesma entrada → mesmo `releaseGovernanceFingerprint`
- [ ] Ordem de entrada não altera resultado (regras e refs ordenadas)
- [ ] Serialização/deserialização preserva identidade normativa
- [ ] `toComparableJson` exclui timestamps não normativos
- [ ] Canonicalização independente de locale/timezone/path separator
- [ ] Replay: `toJson` → `fromJson` → fingerprint idêntico

**Evidência:** `release_governance_engine_test.dart` (deterministic snapshot), `release_governance_models_test.dart`

---

## Testes

### Core

- [x] `dart analyze lib` sem issues nos ficheiros RG
- [x] `dart test test/release_governance` verde (**61** testes)
- [x] Testes de engine (passing, QG ausente, determinismo)
- [x] Testes de source resolver isolados
- [x] Testes de store (idempotência, query, latest)
- [x] Testes de provider (passing, rejected QG, missing approvals, publish)
- [x] Testes de semantics (decisão, aprovações, waivers)
- [x] Testes de policy v1 e v1.1
- [x] Testes de validators (context, approval, waiver, policy)

### Cobertura alvo (Part 3)

- [x] Engine end-to-end com fixtures
- [x] Provider cenários principais (approved, rejected, pending)
- [x] Store idempotência
- [x] Policy versioning v1 vs v1.1 (RG006)
- [ ] Integração Report dedicada
- [ ] Integração History dedicada
- [ ] Integração Dashboard dedicada
- [ ] Observability hardening dedicado
- [ ] Golden snapshots normativos
- [ ] Stress test (~100 regras)
- [ ] Operadores exaustivos (todos os 28)

### Integrações

- [x] Report source implementado (`ReleaseGovernanceReportSource`)
- [x] History mapper implementado (`ReleaseGovernanceHistoryMapper`)
- [x] Dashboard section implementada (`ReleaseGovernanceSectionBuilder`)
- [x] Observability decorator implementado (`ObservableReleaseGovernanceProvider`)
- [ ] Testes de integração dedicados para cada consumidor

---

## Compatibilidade

- [ ] Consistência de `projectId` entre fontes (RG001)
- [ ] Consistência de `commitId` quando exigido (RG002)
- [ ] Schema version verificado por compatibility checker
- [ ] Policy version explícita no request ou registry
- [ ] Quality Gate policy restrita por `compatibilityPolicy`
- [ ] Incompatibilidade nunca convertida silenciosamente em `approved`
- [ ] Ausência nunca convertida silenciosamente em zero

---

## Segurança e minimização de dados

- [ ] Erros sanitizados (sem stack trace integral)
- [ ] Evidence não contém código-fonte
- [ ] Telemetry não loga snapshot completo
- [ ] Report não expõe secrets
- [ ] Limitação crypto auth documentada e aceite
- [ ] Aprovações validadas estruturalmente (não criptograficamente)

---

## Limitações conhecidas (aceites com condição)

- [ ] Políticas permanecem `candidate`
- [ ] Store in-memory apenas (sem persistência física)
- [ ] Sem verificação criptográfica de aprovações/autoridades
- [ ] RG006 v1 usa `isValid` — v1.1 disponível com `isEligible`
- [ ] Sem integração CI/CD
- [ ] Sem consumo automático de waivers no store

---

## Documentação

- [x] `docs/release_governance/release_governance_traceability_matrix.md`
- [x] `docs/release_governance/README.md`
- [x] `docs/release_governance/release_governance_release_checklist.md` (este documento)
- [x] `docs/adr/ADR-028-release-governance-authorizes-release-progression.md`
- [x] `docs/architecture-reviews/AR-014-release-governance-foundation.md`

---

## Release

- [ ] `dart format --output=none --set-exit-if-changed lib test`
- [ ] `dart analyze lib test`
- [x] `dart test test/release_governance` — verde (**61** testes)
- [ ] Architecture Review #014 concluída com sign-off humano
- [ ] Decisão formal registrada (GO / GO WITH CONDITIONS / NO-GO)
- [ ] **Não** fazer commit sem pedido explícito
- [ ] **Não** fazer push
- [ ] **Não** fazer deploy
- [ ] **Não** promover política candidate → active sem AR

---

## Decisão esperada

Com base no estado atual da Sprint 04.2 Part 3:

| Resultado | Condição |
|-----------|----------|
| **GO WITH CONDITIONS** | Arquitetura sólida; políticas candidate; store in-memory; sem crypto auth; **61** testes RG verdes; débitos residuais 04.3 |
| **GO** | Todos os itens acima marcados; testes de integração dedicados; zero itens críticos `notCovered` |
| **NO-GO** | Determinismo quebrado, recálculo de QG, dependência circular, ou reprovação normativa como erro operacional |

Ver decisão fundamentada em `AR-014-release-governance-foundation.md`.

---

## Condições para GO pleno

1. Completar testes de integração Report/History/Dashboard/Observability
2. Implementar persistência de store (se requerida)
3. Avaliar requisitos de assinatura criptográfica
4. Promover `release-governance-v1.1` como baseline active
5. Architecture Review de promoção candidate → active
6. Integração CI/CD (se requerida)
