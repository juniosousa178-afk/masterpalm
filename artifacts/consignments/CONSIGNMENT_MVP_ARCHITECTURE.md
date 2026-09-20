# CONSIGNMENT MVP — Architecture

FAST_TRACK isolated consignment module. No PDV sale button reuse. No Hive authority. No changes to `stockCatalogCommand` mutation kinds.

```
PRODUCT_AUTHORITY=lojas/{lojaId}/estoque_produtos + draft_produtos (server)
STOCK_AUTHORITY=canonical variacoes / quantidade via consignmentCommand helpers (normalizeStock + exact cell)
SALE_AUTHORITY=estoque_vendas created only on SETTLEMENT by consignmentCommand
FINANCE_AUTHORITY=lancamentos_financeiros created only on SETTLEMENT (sold items / net amount)
STORE_AUTH_PATTERN=stock_catalog_access.sale + consignment_control.moduleEnabled + store-scoped docs
```

## Collections (server write only)

- `lojas/{lojaId}/consignment_control/state` `{protocolVersion:1, moduleEnabled:false}`
- `lojas/{lojaId}/consignment_resellers/{resellerId}`
- `lojas/{lojaId}/consignments/{consignmentId}`
- `lojas/{lojaId}/consignment_operations/{operationId}`
- `lojas/{lojaId}/consignment_audit/{operationId}`

## Callable

`consignmentCommand` operations: createDraft, updateDraft, issue, settle, cancelDraft, createReseller, updateReseller.

Issue decrements available stock atomically. Settlement restores only `qtyReturned`. Sold items become `origemVenda=consignment` with `stockAlreadyReservedByConsignment=true` (server-set).

## MVP product support

- SIMPLE=true
- NORMAL VARIATION (single-axis canonical `variacoes`)=true
- GRADE (size×color or extra dimension)=false (`CONSIGNMENT_GRADE_NOT_SUPPORTED`)
- COMBO=false

## Feature flag

`consignmentModuleEnabled` default **false**. Enable per store by writing `consignment_control/state.moduleEnabled=true` via Admin/console. No global rollout.
