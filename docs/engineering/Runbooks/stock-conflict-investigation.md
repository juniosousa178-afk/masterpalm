# Runbook — investigação de conflito de estoque (stockSyncState=conflict)

## Sintoma

Produto com `stockSyncState=conflict` no Hive após duas mutações concorrentes (pendência local + avanço remoto com `operationId` diferente).

## Diagnóstico

1. Verificar `pendingStockOperationId`, `pendingStockBaseRevision`, `stockRevision`, `confirmedStockOperationId`.
2. Ler documento remoto `lojas/{lojaId}/estoque_produtos/{prodId}`: `stockRevision`, `stockOperationId`, grade.
3. Confirmar se pull preservou grade local (`evaluatePullStockMergeByRevision` → `preserveLocalGrade`).

## Causas comuns

- Instância B confirmou venda enquanto instância A tinha push pendente (OFF3).
- Push rejeitado por rules (`permission-denied`) com base revision stale.
- App legado tentou sobrescrever grade (bloqueado em R8.4).

## Resolução operacional

1. Identificar grade autoritativa (remoto vs local) com suporte.
2. Aplicar ajuste manual ou venda de reconciliação com novo `operationId`.
3. Limpar `stockSyncState` após `confirmStockMutation` bem-sucedido.

## Testes de regressão

- `test/m23_r84_stock_enforcement_test.dart` — OFF3, Q1–Q4
- `functions/test/rules-stock-revision-emulator.mjs` — E1–E8
