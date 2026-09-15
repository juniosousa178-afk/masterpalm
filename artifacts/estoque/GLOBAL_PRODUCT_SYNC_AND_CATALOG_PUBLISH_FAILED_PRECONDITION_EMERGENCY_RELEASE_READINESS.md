# MASTERPALM — GLOBAL PRODUCT SYNC + CATALOG PUBLISH
# FAILED-PRECONDITION — EMERGENCY RELEASE READINESS
# NO DEPLOY

```text
TICKET=
  MASTERPALM_GLOBAL_PRODUCT_SYNC_AND_CATALOG_PUBLISH_FAILED_PRECONDITION_EMERGENCY_RELEASE_READINESS
CLASSIFICATION=
  MASTERPALM_GLOBAL_PRODUCT_SYNC_AND_CATALOG_PUBLISH_FAILED_PRECONDITION_EMERGENCY_RELEASE_READINESS_GREEN

ENTRY=
  MASTERPALM_GLOBAL_PRODUCT_SYNC_AND_CATALOG_PUBLISH_FAILED_PRECONDITION_ROOT_CAUSE_CONFIRMED
  MASTERPALM_GLOBAL_PRODUCT_SYNC_AND_CATALOG_PUBLISH_FAILED_PRECONDITION_EMERGENCY_RECOVERY_PLAN_GREEN
  MASTERPALM_GLOBAL_PRODUCT_SYNC_AND_CATALOG_PUBLISH_FAILED_PRECONDITION_EMERGENCY_LOCAL_GREEN

STOCK_CATALOG_ROLLOUT_FROZEN=true
GRADE_RECOVERY_IMPLEMENTATION_PAUSED=true
GRADE_SELECTOR_INCIDENT_REMAINS_OPEN=true
SALE_B_REPAIR_AUTHORIZED=false
ATOMIC_SALE_DEPLOYED=false
```

---

## Identity

```text
LOCAL_BASE=dc58e38f4223b871a917de1443acf577a83c1578
PARENT=75851a9856cdd443cf84c8fe480839753697b982
RECOMPUTED_PRODUCT_PUBLISH_DELTA=
  deef438a3533480f82048cc4c68c0c03893d6cbd5d51accf607da5d3bb7607ab
PRODUCT_PUBLISH_DELTA_MATCH=true
DELTA_PATCH_MATCH=true
ATOMIC_WEB_PATCH_CURRENT=
  432edba3dacb76efaefe8717f049e9bea64fb8b7c21059ff59f45f7b7267a6f6
ATOMIC_WEB_PATCH_MATCH=true
ATOMIC_WEB_PATCH_UNCHANGED=true

STOCK_CATALOG_COMMAND_CUMULATIVE_PATCH_SHA256=
  deef438a3533480f82048cc4c68c0c03893d6cbd5d51accf607da5d3bb7607ab
CATALOG_PUBLISH_ONE_PATCH_SHA256=
  deef438a3533480f82048cc4c68c0c03893d6cbd5d51accf607da5d3bb7607ab
CATALOG_PUBLISH_ALL_PATCH_SHA256=
  deef438a3533480f82048cc4c68c0c03893d6cbd5d51accf607da5d3bb7607ab
```

Shared module graph: `stockCatalogAccess.js` + `stockCatalogCommands.js`.

---

## Worktree / Git release

```text
LOCAL_WORKTREE=
  C:\Users\Pichau\AppData\Local\Temp\masterpalm-product-publish-inactive-compat-emergency-local
HEAD_BEFORE_RELEASE=dc58e38f4223b871a917de1443acf577a83c1578
DIFF_CHECK_GREEN=true
HISTORICAL_WIP_UNTOUCHED=true
ATOMIC_RELEASE_BRANCH_UNTOUCHED=true

RELEASE_BRANCH=
  stock-catalog/emergency-atomic-sale-product-publish-compat
COMMIT_PARENT_EXPECTED=dc58e38f4223b871a917de1443acf577a83c1578
CUMULATIVE_PRODUCT_PUBLISH_RELEASE_COMMIT=<filled after commit>
COMMIT_PARENT=dc58e38f4223b871a917de1443acf577a83c1578
PUSH_ATTEMPTS=1
REMOTE_HEAD_MATCHES_LOCAL=true
```

---

## Production baseline (read-only)

```text
PROJECT=masterpalm-58c46
stockCatalogCommand=stockcatalogcommand-00003-xiz
catalogPublishOne=catalogpublishone-00001-qay
catalogPublishAll=catalogpublishall-00001-cox
Rules=2781401861d96b45867d98f68a0f0d2c3898ed546296eb2c4fbdb445661af071
Web=web-c46d4d9
/version.json=web-c46d4d9
PRODUCTION_METADATA_DRIFT=false
```

### Public catalogs (read-only)

```text
NATHY_PUBLIC_CATALOG_GREEN=true
  SPA https://app.mastepalm.com.br/nathy-pratas-e-folheados → 200
  FIRESTORE list produtos → 200
MASTER_PUBLIC_CATALOG_GREEN=true
  SPA …/master → 200 ; FIRESTORE list → 200
BRISA_PUBLIC_CATALOG_GREEN=true
  SPA …/brisa-do-sol-pratas → 200 ; FIRESTORE list → 200
```

---

## Product / publish revalidation

```text
PRODUCT_COMPAT_AUTH_GREEN=true
  authorizeInactiveLegacyProductMutation exists
  sale authorizer NOT reused
  commands=create,replace,editorial,delete
  owner/admin (+ cadastro seller) ; no migration/grants
ACTIVE_PRODUCT_PROTOCOL_DELTA=NONE
INACTIVE_CREATE_SCHEMA_GREEN=true
GLOBAL_STOCK_KIND_BACKFILL=false

QUEUE_REPLAY_IDEMPOTENT=true
QUEUE_ORDERING_GREEN=true
STALE_QUEUE_OVERWRITE_PREVENTED=true
CUSTOMER_RECREATE_REQUIRED=false

PUBLISH_COMPAT_AUTH_GREEN=true
  authorizeInactiveLegacyPublish exists
ACTIVE_PUBLISH_PROTOCOL_DELTA=NONE
PUBLIC_PRIVATE_FIELD_LEAKS=0

LEGACY_SALE_STOCK_KIND_FIX_PRESERVED=true
ATOMIC_PDV_SALE_PROTOCOL_PRESERVED=true
ATOMIC_PDV_SALE_OPT_IN_PRESERVED=true
NATHY_SALE_B_ATOMIC_REGRESSION_GREEN=true

CUMULATIVE_FUNCTIONS_WITH_OLD_WEB_SAFE=true
FUNCTION_FIRST_OLD_WEB_SALE_PROTOCOL_UNCHANGED=true
PRODUCT_PUBLISH_RECOVERY_REQUIRES_HOSTING=false
```

---

## Critical tests (re-run freeze)

```text
PRODUCT_PUBLISH_COMPAT_TESTS=25/25
LEGACY_SALE_STOCK_KIND_TESTS=25/25
ACTIVE_COMMAND_TESTS=38/38
ATOMIC_BACKEND_TESTS=22/22
ATOMIC_WEB_TESTS=17/17
FUNCTION_DISCOVERY_GREEN=true
ANALYZE_NEW_ISSUES=0
WEB_BUILD_GREEN=true
  (inherited dc58e38 readiness; NEW Web delta=NONE; analyze 0)
FIADO_BEHAVIOR_CHANGED=false
FIADO_REGRESSION=NOT_TOUCHED
BROAD_BACKEND_TEST_RUN=false
BROAD_FLUTTER_TEST_RUN=false
FIADO_74_RESIDUAL_RERUN=false
```

Emulator for critical suites: `127.0.0.1:8187` (aligned).

---

## Rollout 19/20 discrepancy — mandatory reconciliation

```text
FAILING_TEST_PATH=
  functions/test/stock-catalog-rollout.test.mjs
FAILING_TEST_NAME=
  maintenance rejects backend sale; activation serves only current projection
FAILING_ASSERTION=
  assert.equal(response.status, 200) but got 403
PUBLIC_READ_TARGET=
  http://127.0.0.1:8187/v1/projects/demo-stock-catalog/databases/(default)/documents/lojas/{lojaId}/produtos/p
  (HARDCODED port 8187 inside publicRead())
```

### Comparison (same test logic, no function-source mutation for B)

| Environment | FIRESTORE_EMULATOR_HOST | Result |
|---|---|---|
| A cumulative LOCAL_GO | 127.0.0.1:8299 (Admin) + publicRead→8187 | FAIL 403 |
| A cumulative LOCAL_GO | 127.0.0.1:8187 (Admin+publicRead aligned) | PASS |
| B immutable dc58e38 worktree | 127.0.0.1:8187 | PASS |
| B dc58e38 | 127.0.0.1:8299 | harness refuses host (exact 8187 required) |

```text
FAILS_ON_CUMULATIVE=true   (only when Admin host ≠ hardcoded publicRead 8187)
FAILS_ON_DC58E38_BASE=false  (aligned 8187)
FAILS_ON_75851A9_BASE=NOT_RUN
DELTA_INTRODUCED_PUBLIC_READ_FAILURE=false

PUBLIC_READ_403_SOURCE=
  EMULATOR_PORT_MISMATCH_HARNESS
  (Admin SDK writes to 8299; REST publicRead still hits 8187)
RULES_FIX_REQUIRED=false

ROLLOUT_19_OF_20_CLASSIFICATION=C
  EMULATOR_AUTH/STATE_HARNESS_ARTIFACT
  (harness host check relaxed to any 127.0.0.1:port; publicRead URL not updated)

ROLLOUT_PUBLIC_READ_HARNESS_FAILURE_NONBLOCKING=true
```

Nonblocking justification:
- same case PASSES on dc58e38 and on cumulative when ports align;
- product/publish Function delta paths do not implement public REST read;
- production Nathy/Master/Brisa public catalogs GREEN;
- Rules hash unchanged `27814018…`;
- critical product/publish/atomic suites GREEN;
- full rollout file on aligned 8187 = 5/5.

Background 19/20 = rollout(5)+migration(15) with one harness fail under 8299 mismatch.

---

## Changed paths

```text
FUNCTION_SOURCE_PATHS=
  functions/src/stockCatalogAccess.js
  functions/src/stockCatalogCommands.js
TEST_PATHS=
  functions/test/stock-catalog-inactive-product-publish-compat.test.mjs
  functions/test/stock-catalog-commands.test.mjs
  functions/test/stock-catalog-inactive-sale-compat.test.mjs
  functions/test/stock-catalog-rollout.test.mjs
ARTIFACT_PATHS=
  artifacts/estoque/GLOBAL_PRODUCT_SYNC_AND_CATALOG_PUBLISH_FAILED_PRECONDITION_EMERGENCY_LOCAL.md
  artifacts/estoque/GLOBAL_PRODUCT_SYNC_AND_CATALOG_PUBLISH_FAILED_PRECONDITION_EMERGENCY_LOCAL.json
  artifacts/estoque/GLOBAL_PRODUCT_SYNC_AND_CATALOG_PUBLISH_FAILED_PRECONDITION_EMERGENCY_RELEASE_READINESS.md
  artifacts/estoque/GLOBAL_PRODUCT_SYNC_AND_CATALOG_PUBLISH_FAILED_PRECONDITION_EMERGENCY_RELEASE_READINESS.json
WEB_SOURCE_PATHS_NEW_THIS_DELTA=NONE
RULES_PATHS=NONE
UNRELATED_PATHS=NONE
```

---

## Future Function-first order (NO deploy this ticket)

```text
STAGE1_FUNCTION_TARGETS=
  functions:stockCatalogCommand
  functions:catalogPublishOne
  functions:catalogPublishAll

STAGE 1 — Functions only (three targets)
STAGE 2 — health + old-Web product/publish verification (no customer sale)
STAGE 3 — Hosting atomic-sale Web
STAGE 4 — Web convergence
STAGE 5 — controlled atomic natural sale
STAGE 6 — read-only observation
```

---

## Customer / SALE B / accounting

```text
CUSTOMER_SHOULD_NOT_RECREATE_FAILED_PRODUCTS=true
CUSTOMER_SHOULD_NOT_REPEAT_UPDATE_CATALOG=true
CUSTOMER_SHOULD_NOT_CLEAR_APP_DATA=true
SALE_FLOW_SAFE_FOR_GENERAL_USE=false
CUSTOMER_TESTS_AUTHORIZED=false

SALE_B_REMOTE_SALE_INSERTED=false
SALE_B_STOCK_CORRECTED=false

COMMITS=1
PUSHES=1
FUNCTION_DEPLOYS=0
HOSTING_DEPLOYS=0
RULES_DEPLOYS=0
PRODUCTION_WRITES=0
QUEUE_REPLAYS=0
```

---

## Next

```text
NEXT=
  MASTERPALM_GLOBAL_PRODUCT_SYNC_AND_CATALOG_PUBLISH_FAILED_PRECONDITION_EMERGENCY_FUNCTIONS_PRODUCTION_RELEASE
```

---

## STOP

```text
NO_FUNCTION_DEPLOY=true
NO_HOSTING_DEPLOY=true
NO_RULES_DEPLOY=true
NO_QUEUE_REPLAY=true
NO_CUSTOMER_RETRY=true
NO_SALE_B=true
NO_GRADE=true
NO_ROLLOUT_RESUME=true
```
