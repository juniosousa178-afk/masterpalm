# Architecture Review #019 — Persistent Artifact Infrastructure

## Escopo
Revisão arquitetural da Sprint 05.3 (Domain + Operational + Hardening) para o domínio Persistent Artifact Infrastructure em `tools/platform`.

## Arquitetura
- Domínio normativo em `lib/models/persistent_artifacts/`.
- Camada operacional em `lib/persistent_artifacts/` (policy/backend registries, resolver read-only, collector, builders, evaluators, engine, serializer, identity, store in-memory, provider vendor-neutral).
- Integrações: Platform Core, Bootstrap, Report, History, Dashboard, Observability.
- Sem adapters físicos, sem `dart:io`, sem rede, sem storage de conteúdo.

## Domínio e operação
- 28 modelos normativos, 21 validators estruturais, 4 candidate policies v1.
- Snapshot declarativo com fingerprints canônicos; `PersistentArtifactContentHandle` não serializável.
- Backend registry vazio por padrão; operações físicas retornam `unavailable`.

## Fronteiras
| Conceito | Comportamento |
|----------|---------------|
| Snapshot store | Metadados normativos in-memory, não é content storage |
| publish | Persiste snapshot, não faz upload |
| persisted | Declarativo, não prova durabilidade física |
| retention | Avalia elegibilidade, não exclui |
| deletion evaluation | Não exclui fisicamente |
| tombstone | Registro declarativo, não apaga |
| replication evaluator | Não copia conteúdo |
| availability evaluator | Não faz health check |
| publication | Não autoriza release |

## Evidências (Parte 3)
- Replay: 100 ciclos JSON + 15 cenários.
- 24 goldens normativos em `test/goldens/persistent_artifacts/`.
- Audits por componente (serializer, identity, registries, resolver, collector, builders, 9 evaluators, engine, validator, store, provider, report, history, dashboard, observability).
- Property, mutation, malformed-input, stress (5000 snapshots / 1000 serializer cycles), performance baseline.
- Static security review e dependency review.
- Cross-module audit e Guardian compatibility (692 arquivos, 0 unresolved, fingerprint estável em 5 execuções).

## Testes
| Métrica | Baseline Parte 2 | Final Parte 3 |
|---------|-------------------|---------------|
| Persistent Artifacts | 418 | **566** (+148) |
| Suíte total | 2447 | **2595** (+148) |
| Cryptographic Trust | 603 | 603 (preservados) |
| Guardian | 43 | 43 |

## Segurança e dependências
- Nenhum `dart:io`, `HttpClient`, `Process.run` em `lib/persistent_artifacts` e `lib/models/persistent_artifacts`.
- Nenhuma dependência de storage/cloud/banco/rede adicionada.
- Nenhuma credencial hardcoded; content handles excluídos da serialização.

## Guardian
- 692 arquivos analisados; 0 imports não resolvidos.
- Fingerprint de análise: `f892b75c2f491c255f97ff180c33722c6cdfa12283e15fc1fa12a6bb26375da8` (estável em 5 execuções).

## Riscos residuais
- Adapters físicos ainda não implementados; durabilidade real depende de sprint futura.
- Performance em produção depende de backend externo.
- Goldens exigem atualização consciente e revisão manual.

## Technical debt
- Checklist de integração com adapters reais (fase futura).
- Expansão de observability para cenários multi-backend quando adapters existirem.

## Critérios de aceite
Todos os critérios da Sprint 05.3 Parte 3 foram atendidos (replay, goldens, audits, stress, security, docs, analyze limpo, suites verdes, sem persistência física, sem autorização de release).

## Decisão proposta

**GO WITH CONDITIONS — Declarative Persistence Ready / Physical Storage Absent**

Condições:
1. Não promover a persistência declarativa como durabilidade física.
2. Adapters de storage físico exigem sprint dedicada com ADR próprio.
3. Goldens e fingerprints permanecem sob revisão manual.
4. Release Governance e Cryptographic Trust permanecem inalterados.
