# Architecture Review #015 — Release Evidence Foundation

| Campo | Valor |
|-------|-------|
| **ID** | AR-015 |
| **Título** | Release Evidence and Attestation Foundation |
| **Sprint** | 04.3 Part 3 (Hardening) |
| **Data** | 2026-07-22 |
| **Revisor** | MasterPalm Engineering Governance |
| **ADR relacionado** | ADR-029 |
| **Políticas** | `release-evidence-v1`, `release-attestation-v1`, `release-verification-v1` (candidate) |

---

## 1. Executive Summary

A Sprint 04.3 entrega a fundação de Release Evidence na MasterPalm Engineering Platform: pipeline determinístico que consolida `QualityGateSnapshot` e `ReleaseDecisionSnapshot` publicados, valida attestations estruturalmente, produz verificação auditável, e integra Report/History/Dashboard/Observability.

A Parte 3 (hardening) validou replay, golden snapshots, serialização, identidade, provider/store, collector, bundle, engines, observability, report, history, dashboard, property-based tests, mutation tests, stress tests e baseline de performance — **sem alterar contratos públicos nem engines existentes**.

Condições que impedem GO pleno:

1. **Políticas candidate** — três políticas não promovidas a `active`
2. **Store in-memory** — sem persistência física entre processos
3. **Sem autenticação criptográfica** — attestations validadas estruturalmente apenas
4. **Verification ≠ autorização** — consumidores devem não confundir `verified` com release autorizada
5. **Sem integração CI/CD** — enforcement manual

**Decisão:** **GO WITH CONDITIONS — Release 4.2 Beta**

---

## 2. Scope Reviewed

| Área | Incluído |
|------|----------|
| Domínio imutável (30 models) | Sim |
| Pipeline operacional (resolver, collector, builder, engines) | Sim |
| Provider e store in-memory | Sim |
| Bootstrap e PlatformCore | Sim |
| Integrações Report, History, Dashboard, Observability | Sim |
| Políticas candidate v1 (3) | Sim |
| Hardening Part 3 (Etapas 83–107) | Sim |
| Testes `test/release_evidence/` (186) | Sim |
| Golden snapshots | Sim |
| Documentação Sprint 04.3 | Sim |

**Fora de escopo:** CI/CD enforcement, persistência física, assinatura criptográfica, promoção candidate→active.

---

## 3. Architecture Baseline

Release Evidence adere ao padrão estabelecido por Quality Gate e Release Governance:

- **Models** — tipos imutáveis (`lib/models/release_evidence/*`)
- **Engines** — lógica pura, sem IO (`ReleaseAttestationEngine`, `ReleaseVerificationEngine`)
- **Provider** — orquestração (`PlatformReleaseEvidenceProvider`)
- **Bootstrap** — composition root (`ReleaseEvidencePlatformBootstrap`)

Dependências upstream: `QualityGateProvider`, `ReleaseGovernanceProvider` — apenas leitura.

---

## 4. Conformidade Arquitetural

| Princípio | Conformidade | Evidência |
|-----------|--------------|-----------|
| Single responsibility | Conforme | Pipeline em etapas isoladas |
| Immutability | Conforme | Models com listas defensivas |
| Determinism | Conforme | `release_evidence_replay_test.dart`, goldens |
| Consume, don't recalculate | Conforme | `release_evidence_source_resolver_audit_test.dart` |
| No silent coercion | Conforme | Ausência ≠ sucesso; incompatível explícito |
| Policy versioning | Conforme | 3 registries com freeze |
| Integration without recursion | Conforme | Report/Dashboard/History não chamam pipeline |
| Verification ≠ authorization | Conforme | `release_evidence_semantics_test.dart` |

---

## 5. Replay e Determinismo

| Verificação | Resultado |
|-------------|-----------|
| Re-evaluate → mesmo bundle fingerprint | Conforme |
| Re-evaluate → mesma verification fingerprint | Conforme |
| Attestations idênticas (ordering + IDs) | Conforme |
| Coverage/compatibility/eligibility idênticos | Conforme |
| JSON round-trip preserva identidade | Conforme |
| Golden snapshots estáveis | Conforme |

**Evidência:** `release_evidence_replay_test.dart`, `test/golden/release_evidence/*.json`

---

## 6. Integrações

| Integração | Consumo | Recálculo |
|------------|---------|-----------|
| Report (`ReportType.releaseEvidence`) | Bundle publicado | Não |
| History (`HistoryArtifactType.releaseEvidence`) | Snapshot mapeado | Não |
| Dashboard (`DashboardSectionType.releaseEvidence`) | Bundle injetado | Não |
| Observability (`TelemetryComponent.releaseEvidence`) | Decorator transparente | Não |

**Evidência:** `release_evidence_integration_audit_test.dart`, `release_evidence_observability_audit_test.dart`

---

## 7. Segurança

| Verificação | Resultado |
|-------------|-----------|
| Nenhuma validação criptográfica implícita | Conforme |
| Assinatura ausente/unverified tratada estruturalmente | Conforme |
| Authority/issuer validados estruturalmente | Conforme |
| Sentinel strings ausentes em bundle/report/fingerprint | Conforme |
| Telemetry sanitizer redige atributos secretos | Conforme |
| Referências externas por fingerprint, não payload | Conforme |

**Evidência:** `release_evidence_security_test.dart`, `release_evidence_engine_audit_test.dart`

**Limitação explícita:** `authorityNotCryptographicallyVerified`.

---

## 8. Desempenho

| Operação | Threshold (CI) | Observação |
|----------|----------------|------------|
| `evaluate` | < 3s | Baseline generoso |
| `publish` + `load` | < 3s | In-memory |
| `query` | < 1s | Após publish |
| Replay 10× evaluate | < 5s | Determinismo |
| Bundle 1000 evidence | < 5s | Stress test |

**Evidência:** `release_evidence_performance_test.dart`, `release_evidence_stress_test.dart`

---

## 9. Testes

| Métrica | Valor |
|---------|-------|
| Testes Release Evidence | **186** |
| Suite total | **1018** |
| `dart analyze lib` | Limpo |
| Golden snapshots | 3 aprovados |
| Mutation cases | 4 bundle + 1 policy + 1 identity |
| Property-based seeds | 20 shuffles + 10 serializer |

---

## 10. Riscos

| Risco | Severidade | Mitigação |
|-------|------------|-----------|
| Confusão verification vs autorização | Média | Semantics test + documentação |
| Store in-memory em produção | Alta | Documentar limitação; store persistente futuro |
| Políticas candidate | Média | AR de promoção antes de active |
| Sem crypto em attestations | Média | Limitação explícita ADR-029 |
| Evidence duplicada de RG snapshot | Baixa | Collector dedup (corrigido Part 2) |

---

## 11. Documentação

| Documento | Status |
|-----------|--------|
| `docs/release_evidence/README.md` | Completo |
| ADR-029 | Completo |
| AR-015 | Este documento |
| Release checklist | Completo |

---

## 12. Condições para GO pleno

1. Promover políticas candidate → active após validação operacional
2. Implementar store persistente
3. Documentar contrato verification para consumidores externos
4. Avaliar verificação criptográfica de attestations (roadmap)

---

## 13. Decisão Final

| Critério | Status |
|----------|--------|
| Arquitetura aprovada mantida | ✅ |
| Contratos públicos inalterados | ✅ |
| Replay determinístico | ✅ |
| Hardening completo | ✅ |
| Testes verdes (1018) | ✅ |
| Documentação | ✅ |

**Conclusão: GO WITH CONDITIONS — Release 4.2 Beta**

A fundação Release Evidence está pronta para consumo interno beta, sujeita às condições listadas. Promoção a produção requer store persistente e revisão de políticas candidate.
