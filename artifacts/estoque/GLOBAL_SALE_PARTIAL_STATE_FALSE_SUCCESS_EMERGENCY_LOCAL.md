# GLOBAL SALE PARTIAL STATE / FALSE SUCCESS — EMERGENCY LOCAL

Classification: **MASTERPALM_GLOBAL_SALE_PARTIAL_STATE_FALSE_SUCCESS_EMERGENCY_LOCAL_GREEN**

## Entry / freeze

| Key | Value |
|-----|-------|
| BASE_COMMIT | `75851a9856cdd443cf84c8fe480839753697b982` |
| LOCAL_WORKTREE | `C:\Users\Pichau\AppData\Local\Temp\masterpalm-sale-stock-atomicity-emergency-local` |
| HEAD_BEFORE | `75851a9856cdd443cf84c8fe480839753697b982` |
| WORKTREE_CLEAN_BEFORE | true |
| HISTORICAL_WIP_UNTOUCHED | true |
| RECOMMENDED_RECOVERY_STRATEGY | B |
| STOCK_KIND_FIX_ROLLBACK_REQUIRED | false |
| SALE_B_REPAIR_REQUIRED | true |
| SALE_B_REPAIR_AUTHORIZED | false |
| SALE_FLOW_SAFE_FOR_GENERAL_USE | false |
| CUSTOMER_CONTROLLED_TEST_SALES_ALLOWED | false |
| STOCK_CATALOG_ROLLOUT_FROZEN | true |
| GRADE_RECOVERY_IMPLEMENTATION_PAUSED | true |

## Confirmed incident (frozen)

- stock applied
- remote `estoque_vendas` absent
- local/UI success shown
- SALE_AND_STOCK_CURRENTLY_ATOMIC (pre-fix) = false
- UI_SUCCESS_BEFORE_REMOTE_SALE_COMMIT (pre-fix) = true

## Current split flow (mapped before edit)

| Stage | Path |
|-------|------|
| CURRENT_FINALIZE_SOURCE | `lib/screens/nova_venda_modal.dart` → `lib/services/vendas_service.dart` `_registrarVendaMultiCorpo` |
| CURRENT_STOCK_CALL_SOURCE | `lib/services/estoque_transaction_service.dart` `baixarEstoqueTransactionBatchIdempotente` → `StockCatalogBackendService.command` |
| CURRENT_SYNC_VENDA_SOURCE | `lib/services/vendas_firestore_service.dart` `syncVenda` |
| CURRENT_HIVE_SAVE_SOURCE | `lib/services/vendas_service.dart` Hive `vendasBox.add` |
| CURRENT_SUCCESS_MODAL_SOURCE | `lib/screens/nova_venda_modal.dart` `_mostrarSucessoVenda` via `onLocalPersistUiReady` |
| CURRENT_INTENT_COMPLETION_SOURCE | `lib/services/vendas_service.dart` `_coordinatedSaleIntentAdvance(... completed)` |
| CURRENT_STOCK_TRANSACTION_SOURCE | `functions/src/stockCatalogCommands.js` `executeStockCommandInTransaction` |
| CURRENT_TRANSACTION_WRITES_ESTOQUE_VENDAS (pre-fix) | false |

## Canonical sale schema (reused)

| Key | Value |
|-----|-------|
| CANONICAL_SALE_SERIALIZER | `VendasFirestoreService.syncVenda` + backend `buildCanonicalEstoqueVendaDoc` (`functions/src/stockCatalogPdvSale.js`) |
| CANONICAL_SALE_COLLECTION | `lojas/{lojaId}/estoque_vendas/{saleId}` |
| CANONICAL_DOCUMENT_ID_RULE | `saleId == operationId` (frozen PDV operation identity) |
| CANONICAL_SERVER_TIMESTAMP_FIELDS | `data`, `createdAt`, `updatedAt` |

## Sale identity

| Key | Design |
|-----|--------|
| CANONICAL_SALE_ID | `operationId` |
| CANONICAL_OPERATION_ID | journal/sale-intent reserved `operationId` |
| SALE_AND_OPERATION_ID_LINK | same string; retry → same op → same sale doc |

## Atomic protocol negotiation (critical)

| Key | Value |
|-----|-------|
| ATOMIC_PROTOCOL_NEGOTIATION_REQUIRED | true |
| NEW_WEB_ATOMIC_SIGNAL | `atomicPdvSale=true` + `sale` envelope |
| OLD_WEB_COMPATIBILITY_STRATEGY | omit flag → stock-only (unchanged) + client `syncVenda` |
| FUNCTION_FIRST_WITH_OLD_WEB_SAFE | true |
| WEB_RELEASE_REQUIRED | true |
| REQUIRED_FUNCTION_DEPLOY_TARGETS | `stockCatalogCommand` only |

### Mixed-version matrix

| CLIENT | FUNCTION | SALE_OWNER | STOCK_OWNER | SAFE? |
|--------|----------|------------|-------------|-------|
| old Web | old Fn | client syncVenda | stockCatalogCommand | previous (unsafe partial possible) |
| old Web | new Fn | client syncVenda | stockCatalogCommand | SAFE (no backend sale) |
| new Web | old Fn | n/a (reject unknown fields) | n/a | SAFE fail-closed |
| new Web | new Fn | backend atomic | backend atomic | SAFE target |

## Implementation summary

- Backend: opt-in `atomicPdvSale` commits stock + `estoque_vendas` + operation in **one** Firestore transaction.
- Preserves `resolveLegacyCompatStockKind` (no backfill).
- Auth unchanged (auth / membership / ACTIVE / legacyCompat).
- Web PDV final sale: builds sale payload **before** stock call; awaits authoritative response; Hive mirror; **skips** `syncVenda`; success gate requires `authoritativeRemoteSaleCommitted`.
- `stockCatalogOrderSale` **not** substituted.
- Fiado shared paths lightly guarded (no stock reverse after atomic commit); happy-path Fiado behavior preserved.
- Rules: **no change**.
- Grade selector: **not** touched.
- SALE B production repair: **not** done.

## Results

| Gate | Result |
|------|--------|
| SALE_AND_STOCK_SINGLE_TRANSACTION | true |
| ATOMIC_FAILURE_STATE | NO_SALE_NO_STOCK_CHANGE |
| LEGACY_STOCK_KIND_FIX_PRESERVED | true |
| STOCK_KIND_BACKFILL | false |
| RETRY_AFTER_COMMIT_RETURNS_EXISTING_RESULT | true |
| DOUBLE_STOCK_DECREMENT | false |
| DUPLICATE_SALE | false |
| NATHY_SALE_B_PARTIAL_STATE_IMPOSSIBLE_POST_FIX | true |
| CLIENT_REMOTE_SYNC_VENDA_AFTER_ATOMIC_COMMIT | false |
| HIVE_ROLE | MIRROR |
| SUCCESS_MODAL_BEFORE_BACKEND_ATOMIC_COMMIT | false |
| INTENT_COMPLETED_BEFORE_ATOMIC_COMMIT | false |
| OFFLINE_SUCCESS_MODAL | false |
| HISTORY_AUTHORITY | FIRESTORE |
| ATOMIC_SALE_SCOPE | ACTIVE + legacyCompat / no-control final PDV |
| ACTIVE_SALE_ATOMICITY_IMPLEMENTED | true |
| INACTIVE_SALE_ATOMICITY_IMPLEMENTED | true |
| PDV_COMBO_REACHABLE | true (PDV supports combo selection; expansion via existing protocol; no dedicated combo atomic case added beyond stock expansion) |
| FIADO_SHARED_CODE_TOUCHED | true (guard only) |
| FIADO_BEHAVIOR_CHANGED | false |
| RULES_CHANGE_REQUIRED | false |
| RESTORE_CHANGE_REQUIRED | false |
| CANCEL_CHANGE_REQUIRED | false |
| DELETE_CHANGE_REQUIRED | false |
| AUTHENTICATION_CHANGED | false |
| STORE_MEMBERSHIP_CHANGED | false |
| ACTIVE_AUTHORIZATION_CHANGED | false |
| LEGACY_COMPAT_AUTHORIZATION_CHANGED | false |
| ATOMIC_SALE_IN_FLIGHT_PROTECTED_FROM_RELOAD | true |
| ANALYZE_NEW_ISSUES | 0 |
| WEB_BUILD_GREEN | true |
| FUNCTIONS_DISCOVERY | stockCatalogCommand load OK |
| BROAD_BACKEND_TEST_RUN | false |
| BROAD_FLUTTER_TEST_RUN | false |
| PRODUCTION_READS | 0 |
| PRODUCTION_WRITES | 0 |
| FUNCTION_DEPLOYS | 0 |
| RULES_DEPLOYS | 0 |
| HOSTING_DEPLOYS | 0 |
| GIT_STAGES | 0 |
| GIT_COMMITS | 0 |
| GIT_PUSHES | 0 |
| SALE_B_REMOTE_SALE_INSERTED | false |
| SALE_B_STOCK_CORRECTED | false |

## Tests

Backend (`functions/test/stock-catalog-atomic-pdv-sale.test.mjs`): **22/22 pass** (emulator).

Web (`test/atomic_pdv_sale_web_contract_test.dart` + `m39_sprint4_r4_venda_perf_test.dart`): **17/17 pass**.

## Patch identities

| Key | Value |
|-----|-------|
| ATOMIC_SALE_FUNCTION_PATCH_SHA256 | `8f9a587ffd7dac90292af9979821239e770afbe6497c53c203409a0a31bd431d` |
| ATOMIC_SALE_WEB_PATCH_SHA256 | `432edba3dacb76efaefe8717f049e9bea64fb8b7c21059ff59f45f7b7267a6f6` |
| ATOMIC_SALE_COMBINED_PATCH_SHA256 | `9babdaebfff4fdfeb9d1d64fbd58707bd45b59b95da6ecead34074865f6ec833` |

## Changed paths

### FUNCTION_SOURCE_PATHS
- `functions/src/stockCatalogCommands.js`
- `functions/src/stockCatalogPdvSale.js`

### WEB_SOURCE_PATHS
- `lib/services/vendas_service.dart`
- `lib/services/estoque_transaction_service.dart`
- `lib/services/stock_catalog_backend_service.dart`
- `lib/services/atomic_pdv_sale_payload.dart`
- `lib/core/nova_venda_ui_release_policy.dart`

### TEST_PATHS
- `functions/test/stock-catalog-atomic-pdv-sale.test.mjs`
- `test/atomic_pdv_sale_web_contract_test.dart`

### ARTIFACT_PATHS
- `artifacts/estoque/GLOBAL_SALE_PARTIAL_STATE_FALSE_SUCCESS_EMERGENCY_LOCAL.md`
- `artifacts/estoque/GLOBAL_SALE_PARTIAL_STATE_FALSE_SUCCESS_EMERGENCY_LOCAL.json`

### RULES_PATHS
- NONE

### UNRELATED_PATHS
- NONE

## syncVenda callsite map

| CALLSITE | PURPOSE | FINAL_PDV_SALE? | STILL_REQUIRED? | ACTION |
|----------|---------|-----------------|-----------------|--------|
| `vendas_service._registrarVendaMultiCorpo` | PDV final sale remote write | yes | no (when atomic) | bypass after atomic |
| `vendas_service` edit path | edit sale sync | no | yes | preserve |
| `vendas_firestore_service.syncTodasVendas` / queue | retry/backfill | no | yes | preserve |
| `catalogo_venda_service` | catalog/order sales | no | yes | preserve |
| `soft_delete_service` | restore sale | no | yes | preserve |
| `sync_queue_service` / `full_sync` / `sync_firestore_script` | ops sync | no | yes | preserve |
| `catalogo_venda_side_effects_secundarios_service` | side effects | no | yes | preserve |

## Next (STOP)

**MASTERPALM_GLOBAL_SALE_PARTIAL_STATE_FALSE_SUCCESS_EMERGENCY_RELEASE_READINESS**

Do not deploy / commit / push / repair SALE B / migrate / activate / resume grade or rollout.
