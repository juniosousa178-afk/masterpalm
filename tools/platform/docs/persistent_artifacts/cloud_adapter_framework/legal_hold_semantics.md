# Legal Hold Semantics

**Status:** draft

## Definição

Legal hold impede exclusão/overwrite independentemente de retention timer.

## Mapeamento PA

- Operações de delete/copy com hold ativo → `blocked` / `permissionDenied`.
- Nenhum force delete que ignore hold.

## Fornecedores

| Provider | Feature | Confiança |
|----------|---------|-----------|
| S3 | Object Lock legal hold | reviewRequired |
| GCS | Retention/hold policies | reviewRequired |
| Azure | Immutable storage | reviewRequired |

`legalHoldSemanticsApproved` permanece `false`.
