# Consistency Semantics

**Status:** draft

## Níveis documentados nos contratos PA

- `CloudConsistencyLevel.readAfterWrite`, `strong`, `eventual` — declarativos.
- Adapter mapeia comportamento real sem prometer mais que o provider oferece.

## List consistency

- Listagem pode ser eventual; PA `listObjects` não prova consistência global.
- Ordenação determinística apenas no fake offline.

## Read-after-write

- Regional strong para novos objetos em S3 — **reviewRequired** até medição.

`consistencySemanticsDocumented` → documento existe, critério ainda `reviewRequired` (não `approved`).
