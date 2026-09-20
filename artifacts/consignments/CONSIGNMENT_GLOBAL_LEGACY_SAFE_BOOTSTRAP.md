# CONSIGNMENT_GLOBAL_LEGACY_SAFE_BOOTSTRAP

**DECISION=B PARTIAL_BOOTSTRAP_UNSAFE_PRODUCTS_REMAIN**

## Scope

- All globally enabled stores except `mirjoias`
- `STORES_SCANNED=89` / `ENABLED_STORE_COUNT=90`
- No feature-flag changes
- No broad `stock_catalog_control` activation
- No quantity / price / name / identity mutations
- No sales / finance / receivables / consignments created

## Mechanism

Isolated helper (no function deploy):

- `functions/src/consignmentLegacyBootstrap.js`
- executor `functions/scripts/global_consignment_legacy_safe_bootstrap.mjs`
- focused tests `functions/test/consignment-legacy-bootstrap.test.mjs` → **20/20**

Official metadata only:

- `stockKind` (`simple` | `variation`)
- `stockRevision` initialized to `0` when missing (preserved when already valid)
- `stock_catalog_dependencies/{productId} = { comboIds: [] }`

## Pre-mutation inventory

| Class | Count |
|------|------:|
| ALREADY_SAFE | 3 |
| LEGACY_SIMPLE_BOOTSTRAPPABLE | 1188 |
| LEGACY_VARIATION_BOOTSTRAPPABLE | 39 |
| GRADE skipped | 447 |
| COMBO skipped | 11 |
| AMBIGUOUS skipped | 47 |
| OTHER_UNSUPPORTED | 469 |
| Active products | 2205 |

## Execution

`PRODUCTION_SAFE_METADATA_BOOTSTRAP_AUTHORIZED=true`

- `BOOTSTRAPPED_PRODUCT_COUNT=1227`
- `STOCK_QTY_MUTATIONS=0`
- `PRODUCT_ID_MUTATIONS=0`
- `PRODUCT_NAME_MUTATIONS=0`
- `PRICE_MUTATIONS=0`
- `GRADE_BOOTSTRAPPED_COUNT=0`
- `COMBO_BOOTSTRAPPED_COUNT=0`
- `MIRJOIAS_*_WRITES=0`
- `FUNCTION_DEPLOYS=0` `HOSTING_DEPLOYS=0` `RULES_DEPLOYS=0`

Idempotent re-scan after apply: `LEGACY_*_BOOTSTRAPPABLE_COUNT=0` (NO-OP).

## Picker effect

| Metric | Before | After |
|--------|-------:|------:|
| Stores with eligible products | 2 | 29 |
| Stores still with zero eligible | — | 60 |

Zero-eligible stores are not an incident when remaining SKUs are grade/combo/ambiguous/missing draft/other unsupported.

Fail-closed picker filter preserved. Public catalog membership still not required.

## Proof sample (`master`)

`master-anel-2-folhas-t-18-prata-925`:

- `stockKind=simple`
- `stockRevision=0`
- `quantidade=1` unchanged
- dependency `{comboIds:[]}` present
- draft present → picker-eligible

Mirjoias sample still lacks consignment dependency writes; updateTimes predate bootstrap.

## Next

`NEXT_TRACK=PASSIVE_OBSERVABILITY_AFTER_BOOTSTRAP`
