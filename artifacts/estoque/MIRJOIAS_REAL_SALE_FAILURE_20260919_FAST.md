# MIRJOIAS_REAL_SALE_FAILURE_20260919_FAST

```text
DECISION=B
REAL_FAILURE_ROOT_CAUSE=J
REQUEST_REACHED_BACKEND=true
HTTP_STATUS=400
BACKEND_ERROR_CODE=failed-precondition
BACKEND_ERROR_MESSAGE=Dependency migration required
FRONTEND_ERROR_CLASS=FALSE_NETWORK
PRODUCT_DISPLAY_NAME=Brinco Coração Placa P M G Prata 925
PRODUCT_TECHNICAL_ID=mirjoias-brinco-cora-o-placa-p-m-g-prata-925-2
PRODUCT_SAFETY_CLASS=HISTORICAL_BLOCKED
VARIATION_KEYS_REQUESTED=P|sem-cor, M|sem-cor (G|sem-cor also canonical)
PAYMENT_INCOMPLETE=photo_main_screen_true_save_payload_not_proven_incomplete
PAYMENT_VALIDATION_SHOULD_BLOCK_SAVE=true_if_allocated_lt_total
CANONICAL_STOCK_AVAILABLE=false
REQUESTED_VARIATION_CANONICAL_QTY=P=0 M=0 G=0
GRANT_PRESENT=false
PARTIAL_MUTATION=false
SALE_CREATED=false
STOCK_DECREMENTED=false
STOCK_OPERATION_CREATED=false
FINANCIAL_WRITE=false
STOP_CRITICAL=false
FIX_IMPLEMENTED=true
FOCUSED_SALE_FAILURE_TESTS=14/14
FUNCTION_DEPLOYS=0
HOSTING_DEPLOYS=1
RULES_DEPLOYS=0
NEW_STOCK_FUNCTION_REVISION=stockcatalogcommand-00008-dor
CUSTOMER_VARIATION_PDV_SALE_USE=PRODUCT_SCOPED_ONLY
CUSTOMER_GRADE_PDV_SALE_USE=RESTRICTED
SIMPLE_ATOMIC_SALE_STATUS=AVAILABLE
BROAD_STOCK_PROTOCOL_ACTIVATED=false
MIRJOIAS_3_GRANTED_PRODUCTS_STATUS=INTACT
BLOCKED_PRODUCTS_STATUS=STILL_BLOCKED
CUSTOMER_CAN_RETRY_THIS_EXACT_SALE=false
IF_FALSE_REASON=historical blocked product; canonical qty 0; grant absent; stock_catalog_dependencies missing; do not auto-enable
```

## 1. Real attempt

Window `2026-09-19T23:03:00Z`–`2026-09-19T23:10:00Z`. Store `mirjoias`.

Single customer callable on `stockCatalogCommand` revision `stockcatalogcommand-00008-dor`:

| Field | Value |
|---|---|
| Time | 2026-09-19T23:06:17.569Z |
| HTTP | **400** |
| Latency | 163ms |
| Auth/App | VALID |
| Referer | https://app.mastepalm.com.br/ |
| UA | iPad CriOS (no PII) |
| Trace | `8889bcb7abe03aef2ca7946ba7c288d6` |
| Preceding | OPTIONS 204 CORS preflight |

No `legacyCompat` stdout → failure before product apply / grant check log. Not transport: response completed.

## 2. Primary cause

**J) MULTIPLE_CAUSES**, first backend rejection:

`failed-precondition` / `Dependency migration required`

`lojas/mirjoias/stock_catalog_dependencies/mirjoias-brinco-cora-o-placa-p-m-g-prata-925-2` is ABSENT. Draft exists. Stock exists. Grant ABSENT. Canonical `variacoes` P/M/G `sem-cor` all **0**, `quantidade=0`, `stockRevision=2`, `updateTime=2026-08-27T14:57:33.890347Z` (unchanged in the window).

Even if dependency existed, gate would 403 (`VARIATION_SALE_PRODUCT_NOT_AUTHORIZED`) and stock 0 would still block. Product is hive 194 historical block. **Not granted. Not auto-enabled.**

Photo "Falha de conexão" is a frontend mis-map of HTTP 400. `contains('conex')` treated sanitized/backend text as network.

Photo "Faltam: R$ 6889,00" is the main PDV payment row (allocated 0). Confirmation dialog can complete payment before the callable. The 4.3KB POST is an atomic PDV sale payload, so payment incomplete is **not** the HTTP 400. Frontend now still blocks backend when allocated ≠ total (non-fiado).

## 3. Mutation check

No `kind=sale` `stock_catalog_operations` at 23:06:17Z. Product `updateTime` unchanged. Grants of the 3 safe products unchanged.

```text
SALE_CREATED=false
STOCK_DECREMENTED=false
STOCK_OPERATION_CREATED=false
FINANCIAL_WRITE=false
PARTIAL_MUTATION=false
```

## 4. Fix (frontend only, global)

- Map backend codes to specific PDV messages (stock 0, variation not found, grant missing, grade/unsafe, CAS, dependency/conference, 500, real network).
- "Falha de conexão" only for real transport (`unavailable`, `deadline-exceeded`, socket/fetch/offline).
- Payment guard: no backend call while allocated ≠ total (non-fiado).

No function/rules change. No stock write. No grant write. No mirjoias/product ID in UI.

## 5. Tests

`flutter test test/dart_error_unwrap_salvar_venda_test.dart test/nova_venda_payment_guard_test.dart` → **25/25 GREEN**.

Required 14 cases covered (1–8 direct; 9–14 gate unchanged + fail-closed source + existing grant tests 11/13).

## 6. Release

Branch `release/real-sale-error-fix`. Hosting only after this commit.
