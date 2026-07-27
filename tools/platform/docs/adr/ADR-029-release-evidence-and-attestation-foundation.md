# ADR-029: Release Evidence and Attestation Foundation

| Campo | Valor |
|-------|-------|
| **Status** | Accepted (pending formal sign-off in AR-015) |
| **Data** | 2026-07-22 |
| **Sprint** | 04.3 — Release Evidence and Attestation Foundation |
| **Decisores** | MasterPalm Engineering Governance |
| **Domínio** | `tools/platform` — Release Evidence |

---

## Contexto

A MasterPalm Engineering Platform publica decisões normativas em camadas:

- **Quality Gate** (ADR-027) — evidência técnica de qualidade
- **Release Governance** (ADR-028) — autorização de progressão de release
- **History, Report, Dashboard, Observability** — leitura e diffs sem recálculo

Release exige uma camada que consolide evidências publicadas, valide attestations estruturalmente e produza verificação auditável — **sem** recalcular engines de origem nem substituir Release Governance.

Requisitos:

1. Consumir `QualityGateSnapshot` e `ReleaseDecisionSnapshot` **publicados**
2. Mesma política + mesmas fontes → mesmo bundle, fingerprints e verificação
3. Attestations e provenance tratados explicitamente
4. Identidade determinística para replay
5. Políticas versionadas com freeze no registry
6. Integrações transparentes com Report, History, Dashboard e Observability

---

## Decisão

Implementamos Release Evidence como **pipeline determinístico** sobre **artefatos publicados**, com três políticas candidate:

| Política | ID | Versão |
|----------|-----|--------|
| Evidence | `release-evidence-v1` | 1 |
| Attestation | `release-attestation-v1` | 1 |
| Verification | `release-verification-v1` | 1 |

### Princípios centrais

1. **Consumir, não recalcular**
   `ReleaseEvidenceSourceResolver` usa `load`/`latest` dos providers de origem. Nunca invoca `evaluate()` em QG, RG ou engines upstream.

2. **Collector com deduplicação**
   `ReleaseEvidenceCollector` deduplica por `artifactId`. Payloads nunca duplicados no bundle.

3. **Bundle com ordering canônico**
   Evidence ordenada por `artifactId`. Fingerprints via `ReleaseEvidenceCanonicalSerializer` + `ReleaseEvidenceIdentityBuilder`.

4. **Attestation estrutural**
   `ReleaseAttestationEngine` valida issuer, authority, predicates e expiração estruturalmente. **Sem** verificação criptográfica de assinatura.

5. **Verification ≠ autorização**
   `ReleaseVerificationEngine` produz `ReleaseVerificationResult` descritivo. Status `verified` não autoriza release — isso é responsabilidade de Release Governance.

6. **Modos de resolução**
   Precedência: `injected` > `byId` > `latest` (opt-in via `useLatest: true`).

7. **Publicação idempotente**
   `evaluate()` não publica. `evaluateAndPublish()` valida antes de gravar. Store in-memory com overwrite controlado.

8. **Integrações transparentes**
   Report (`ReportType.releaseEvidence`), History (`HistoryArtifactType.releaseEvidence`), Dashboard (`DashboardSectionType.releaseEvidence`) e Observability (`TelemetryComponent.releaseEvidence`) consomem snapshots sem reexecutar o pipeline.

---

## Arquitetura

```
ReleaseEvidenceRequest
       │
       ▼
PlatformReleaseEvidenceProvider
       │
       ├── ReleaseEvidencePolicyRegistry (3 políticas)
       ├── ReleaseEvidenceSourceResolver
       ├── ReleaseEvidenceCollector
       ├── ReleaseEvidenceBundleBuilder
       ├── ReleaseAttestationEngine
       ├── ReleaseVerificationEngine
       ├── CanonicalSerializer + IdentityBuilder
       └── ReleaseEvidenceStore
```

---

## Alternativas rejeitadas

| Alternativa | Motivo da rejeição |
|-------------|-------------------|
| Recalcular QG/RG durante evidence | Viola princípio consume-don't-recalculate; quebra determinismo de snapshots |
| Verification como autorização de release | Sobrepõe Release Governance; viola separação de responsabilidades |
| Store persistente nesta sprint | Fora de escopo; in-memory suficiente para fundação |
| Assinatura criptográfica obrigatória | Complexidade prematura; validação estrutural documentada como limitação |
| Engine monolítica | Impede testes isolados e evolução independente de attestation vs verification |

---

## Limitações

- Políticas permanecem **candidate** até Architecture Review de promoção
- Store **in-memory** — sem persistência entre processos
- Assinaturas **não verificadas criptograficamente**
- `authorityNotCryptographicallyVerified` em attestations
- Sem enforcement CI/CD automático
- Observability desabilitada por default no bootstrap standard

---

## Evolução futura

1. Promoção candidate → active após AR dedicado
2. Store persistente (Firestore ou equivalente)
3. Verificação criptográfica de attestations (opt-in)
4. Integração CI/CD para bloqueio de pipeline
5. Políticas v1.1 com regras adicionais de provenance
6. Cache de bundles publicados com invalidação explícita

---

## Consequências

### Positivas

- Replay determinístico validado com golden snapshots
- Separação clara entre evidência, attestation e verificação
- Integração consistente com padrão QG/RG da plataforma
- 186 testes dedicados + hardening Part 3

### Negativas

- Consumidores devem entender que `verified` ≠ release autorizada
- Dependência de snapshots publicados em QG e RG
- Store in-memory não adequado para produção multi-processo

---

## Referências

- ADR-027 — Quality Gate Foundation
- ADR-028 — Release Governance
- AR-015 — Architecture Review Release Evidence Foundation
- `docs/release_evidence/README.md`
