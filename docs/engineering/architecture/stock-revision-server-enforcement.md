# Enforcement servidor — stockRevision (R8.4)

## Estratégia adotada

**Estratégia A — Firestore Rules** em `lojas/{lojaId}/estoque_produtos/{prodId}`.

Callable backend (Estratégia B) não foi necessário: o app já grava via transações cliente com `stockRevision`/`stockOperationId`; as rules rejeitam escritores legados e mutações inválidas.

## Funções (firestore.rules)

| Função | Papel |
|--------|-------|
| `estoqueStockGradeChanged()` | Detecta alteração em `quantidade`, `variacoes`, `estoquePorTamanho`, `estoquePorCor` |
| `isValidEstoqueProdutoStockUpdate()` | E1–E8 no update |
| `isValidEstoqueProdutoStockCreate()` | Create com grade exige `stockRevision` 0–1 + `stockOperationId` |

## Classificação

Validada no Emulator: `STOCK_REVISION_SERVER_ENFORCEMENT_VALIDATED`

Script: `npm run test:rules:stock` (em `functions/`).

## Ordem de deploy futuro

1. Publicar `firestore.rules` com enforcement.
2. Publicar app com `kMinStockRevisionClientVersion`.
3. Bloquear escritores legados (rules + cliente).

Produção permanece: `ERRO_COMPLETO_NOT_RESOLVED` até validação pós-deploy.
