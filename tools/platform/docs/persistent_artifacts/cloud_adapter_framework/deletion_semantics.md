# Deletion Semantics

**Status:** draft

## Tipos

| Tipo | Descrição | PA status esperado |
|------|-----------|-------------------|
| Soft delete | Delete marker / versão lógica | success simulado ≠ remoção física |
| Hard delete | Remoção permanente | requer gates adicionais |
| Version delete | Remove versão específica | `versionConflict` se pré-condição falhar |

## Regras

- Delete offline fake **não** prova exclusão remota.
- Delete não cria tombstone normativo PA automaticamente.
- Retention evaluator não invoca delete.
