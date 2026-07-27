# Architecture Review #020 — Secure Filesystem Reference Adapter

## Escopo
Implementação do adapter físico local de referência (Sprint 05.3.1 Parte 1) para os contratos de Persistent Artifact Infrastructure, isolado e opt-in.

## Arquitetura
```
Persistent Artifact Provider
        ↓
Backend Registry (vazio por padrão)
        ↓
Persistent Artifact Backend Contracts
        ↓
Secure Filesystem Reference Adapter (registro manual)
```

## Contratos implementados
- `PersistentArtifactContentStore` — put/get/exists via writeContent/readContent/deleteContent
- `PersistentArtifactManifestStore` — save/load + latest/query/list/invalidate
- `PersistentArtifactLocationResolver` — resolveLocations + resolveLocationReference
- `PersistentArtifactContentReader` / `PersistentArtifactContentWriter`
- `PersistentArtifactPhysicalDeletionProvider` — quarentena (não secure erase)

## Threat model
- Path traversal (`..`, UNC, drive prefix, percent-encoding)
- Symlink escape (fail-closed)
- Oversized content (maximumContentSizeBytes)
- Digest mismatch (SHA-256)
- Concorrência (idempotência vs conflito)

## Evidências
| Métrica | Baseline | Final |
|---------|----------|-------|
| Testes adapter | 0 | **124** |
| Testes PA | 566 | **690** (+124) |
| Suíte total | 2595 | **2719** (+124) |
| Guardian | 43 | 43 |
| Arquivos Guardian | 692 | **703** (+11) |
| Unresolved | 0 | 0 |

## Guardian
Fingerprint estável em 5 execuções: `a331862bb96c205e3509e8f25b3c920fa51e597bbf035772543d0408aa623adc`

## Riscos
- Symlink TOCTOU não totalmente eliminável em Dart puro
- Filesystem local sem replicação/HA/durabilidade distribuída
- Performance de scan em diretórios muito grandes

## Technical debt
- Parte 2: integração controlada com provider/registry
- Cloud adapters futuros com ADR dedicado

## Decisão proposta

**GO WITH CONDITIONS — Local Reference Backend / Not Distributed Storage**

Condições:
1. Registro manual obrigatório; bootstrap padrão inalterado
2. Não promover como storage distribuído ou durável
3. Quarentena ≠ secure erase
4. Escrita concluída não autoriza release
