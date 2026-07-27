# ADR-030: Release Supply Chain and Provenance Framework

| Campo | Valor |
|-------|-------|
| **Status** | Accepted (pending formal sign-off in AR-016) |
| **Data** | 2026-07-22 |
| **Sprint** | 05.0 — Release Supply Chain and Provenance Framework |
| **Decisores** | MasterPalm Engineering Governance |
| **Domínio** | `tools/platform` — Release Supply Chain |

---

## Contexto

A MasterPalm Engineering Platform publica decisões normativas em camadas:

- **Quality Gate** (ADR-027) — evidência técnica de qualidade
- **Release Governance** (ADR-028) — autorização de progressão de release
- **Release Evidence** (ADR-029) — consolidação e verificação estrutural de evidências
- **History, Report, Dashboard, Observability** — leitura e diffs sem recálculo

Release exige uma camada que estruture provenance, grafo de supply chain, SBOM, registo de artefatos, distribuição e compliance — **sem** recalcular engines de origem nem substituir Release Governance.

Requisitos:

1. Consumir `QualityGateSnapshot`, `ReleaseDecisionSnapshot` e `ReleaseEvidenceBundle` **publicados**
2. Mesma política + mesmas fontes → mesmo snapshot e fingerprints
3. Provenance, grafo, SBOM e compliance tratados explicitamente
4. Identidade determinística para replay
5. Políticas versionadas com freeze no registry
6. Integrações transparentes com Report, History, Dashboard e Observability

---

## Decisão

Implementamos Release Supply Chain como **pipeline determinístico** sobre **artefatos publicados**, com três políticas candidate:

| Política | ID | Versão |
|----------|-----|--------|
| Supply Chain | `supply-chain-v1` | 1 |
| Distribution | `distribution-v1` | 1 |
| Compliance | `compliance-v1` | 1 |

### Princípios centrais

1. **Consumir, não recalcular**
   `ReleaseSupplyChainSourceResolver` usa `load`/`latest` dos providers de origem. Nunca invoca `evaluate()` em QG, RG ou RE.

2. **Collector com deduplicação**
   `ReleaseSupplyChainCollector` deduplica por `artifactId`. Fingerprints de origem preservados sem recálculo.

3. **Snapshot com ordering canônico**
   Artefatos coletados ordenados por `artifactId`. Fingerprints via `ReleaseSupplyChainCanonicalSerializer` + `ReleaseSupplyChainIdentityBuilder`.

4. **Compliance estrutural**
   `ComplianceEngine` avalia regras estruturais contra artefatos montados. **Nunca** aprova release.

5. **Compliance ≠ autorização**
   `ComplianceResult` é descritivo. Status `compliant` não autoriza release — isso é responsabilidade de Release Governance.

6. **Modos de resolução**
   Precedência: `injected` > `byId` > `latest` (opt-in via `useLatest: true`).

7. **Publicação idempotente**
   `evaluate()` não publica. `evaluateAndPublish()` valida antes de gravar. Store in-memory com overwrite controlado.

8. **Integrações transparentes**
   Report (`ReportType.releaseSupplyChain`), History (`HistoryArtifactType.releaseSupplyChain`), Dashboard (`supplyChain`, `sbom`, `compliance`) e Observability (`TelemetryComponent.releaseSupplyChain`) consomem snapshots sem reexecutar o pipeline.

---

## Arquitetura

```
ReleaseSupplyChainRequest
       │
       ▼
PlatformReleaseSupplyChainProvider
       │
       ├── PolicyRegistry (supply chain / distribution / compliance)
       ├── ReleaseSupplyChainSourceResolver
       ├── ReleaseSupplyChainCollector
       ├── ReleaseSupplyChainSnapshotBuilder
       │        ├── ReleaseProvenanceBuilder
       │        ├── SupplyChainGraphBuilder
       │        ├── SbomBuilder
       │        ├── ArtifactRegistryBuilder
       │        ├── DistributionBuilder
       │        └── ComplianceEngine
       ├── CanonicalSerializer + IdentityBuilder
       └── ReleaseSupplyChainStore
```

---

## Alternativas rejeitadas

| Alternativa | Motivo da rejeição |
|-------------|-------------------|
| Recalcular QG/RG/RE durante supply chain | Viola princípio consume-don't-recalculate; quebra determinismo |
| Compliance como autorização de release | Sobrepõe Release Governance; viola separação de responsabilidades |
| Store persistente nesta sprint | Fora de escopo; in-memory suficiente para fundação |
| Verificação criptográfica de digests | Complexidade prematura; placeholders documentados como limitação |
| Engine monolítica | Impede testes isolados e evolução independente de componentes |

---

## Limitações

- Políticas permanecem **candidate** até Architecture Review de promoção
- Store **in-memory** — sem persistência entre processos
- Digests SHA-256 são **placeholders estruturais** — sem verificação criptográfica
- Compliance **nunca aprova release** — limitação explícita na política
- Sem enforcement CI/CD automático
- Observability desabilitada por default no bootstrap standard

---

## Evolução futura

1. Promoção candidate → active após AR dedicado
2. Store persistente (Firestore ou equivalente)
3. Verificação criptográfica de artefatos (opt-in)
4. Integração CI/CD para bloqueio de pipeline
5. Políticas v1.1 com regras adicionais de provenance e SBOM
6. Cache de snapshots publicados com invalidação explícita

---

## Consequências

### Positivas

- Replay determinístico validado com golden snapshots
- Separação clara entre supply chain, distribuição e compliance
- Integração consistente com padrão QG/RG/RE da plataforma
- Hardening Part 3 com testes dedicados

### Negativas

- Consumidores devem entender que `compliant` ≠ release autorizada
- Dependência de snapshots publicados em QG, RG e RE
- Store in-memory não adequado para produção multi-processo

---

## Referências

- ADR-027 — Quality Gate Foundation
- ADR-028 — Release Governance
- ADR-029 — Release Evidence and Attestation Foundation
- AR-016 — Architecture Review Release Supply Chain Foundation
- `docs/release_supply_chain/README.md`
