# MASTERPALM — Grade + multi-product error P0

DECISION=A
GRADE_AND_ACTIONABLE_ERRORS_GLOBAL_LIVE

## Gates (local)

- GRADE_SALE_SAFE=true
- GRADE_CONSIGNMENT_SAFE=true
- MULTI_PRODUCT_ERROR_CONTRACT_GREEN=true
- ATOMIC_FAILURE_ZERO_WRITES_GREEN=true
- NORMAL_VARIATION_REGRESSION_GREEN=true
- SIMPLE_REGRESSION_GREEN=true
- GRADE_AND_MULTI_ERROR_TESTS=17/17
- CONSIGNMENT_COMMAND_TESTS=51/51 (updated)
- MASTER_SAFE_ELIGIBILITY_TESTS=7/7
- TOTAL_FOCUSED=75/75

## Runtime contract

- TRUE GRADE = size×color matrix / both non-technical lists / size+extra
- Extra-only (`sem-tamanho` + `variacoesExtraTipo`) = NORMAL VARIATION (not true grade)
- `PRODUCT_VALIDATION_FAILED` + `issues[]` with PT-BR `userMessage`
- Sale/restock and consignment draft prevalidate all lines before any write

## False grades (17)

- No quantity invent / no forced Mirjoias repair
- Runtime reclassify only: `FALSE_GRADE_NORMALIZED_COUNT=0` (no stock rewrite)
- `FALSE_GRADE_AMBIGUOUS_COUNT=17` left for later 1D-proven normalize if needed
- `SAFE_GRADE_BOOTSTRAPPED_COUNT=0` / `STOCK_QTY_MUTATIONS=0`

## Scope

- Backend: `consignmentCommand`, `stockCatalogCommand`, shared `productValidationErrors`
- Frontend: consignados picker/errors; PDV surfaces issues via `StockCatalogBackendService` when used
