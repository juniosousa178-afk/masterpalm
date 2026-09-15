# MASTERPALM — GLOBAL PRODUCT SYNC + CATALOG PUBLISH
# FAILED-PRECONDITION — EMERGENCY LOCAL_GO

```text
TICKET=
  MASTERPALM_GLOBAL_PRODUCT_SYNC_AND_CATALOG_PUBLISH_FAILED_PRECONDITION_EMERGENCY_LOCAL_GO
CLASSIFICATION=
  MASTERPALM_GLOBAL_PRODUCT_SYNC_AND_CATALOG_PUBLISH_FAILED_PRECONDITION_EMERGENCY_LOCAL_GREEN

ENTRY=
  MASTERPALM_GLOBAL_PRODUCT_SYNC_AND_CATALOG_PUBLISH_FAILED_PRECONDITION_ROOT_CAUSE_CONFIRMED
  MASTERPALM_GLOBAL_PRODUCT_SYNC_AND_CATALOG_PUBLISH_FAILED_PRECONDITION_EMERGENCY_RECOVERY_PLAN_GREEN
  MASTERPALM_GLOBAL_SALE_PARTIAL_STATE_FALSE_SUCCESS_EMERGENCY_RELEASE_READINESS_GREEN

RECOVERY_INTEGRATION_STRATEGY=B
ATOMIC_SALE_RELEASE_COMMIT=dc58e38f4223b871a917de1443acf577a83c1578
ATOMIC_SALE_RELEASE_COMMIT_IMMUTABLE=true
ATOMIC_SALE_DEPLOYED=false
SALE_B_REPAIR_AUTHORIZED=false
GRADE_RECOVERY_IMPLEMENTATION_PAUSED=true
GRADE_SELECTOR_INCIDENT_REMAINS_OPEN=true
STOCK_CATALOG_ROLLOUT_FROZEN=true
```

---

## Base / worktree

```text
BASE_COMMIT=dc58e38f4223b871a917de1443acf577a83c1578
BASE_MATCH=true
PARENT_PRESERVED=75851a9856cdd443cf84c8fe480839753697b982
LOCAL_WORKTREE=
  C:\Users\Pichau\AppData\Local\Temp\masterpalm-product-publish-inactive-compat-emergency-local
BRANCH=stock-catalog/emergency-product-publish-inactive-compat
HEAD_BEFORE=dc58e38f4223b871a917de1443acf577a83c1578
HEAD_AFTER=dc58e38f4223b871a917de1443acf577a83c1578
WORKTREE_CLEAN_BEFORE=true
HISTORICAL_WIP_UNTOUCHED=true
```

---

## Root cause (confirmed vs plan)

```text
PRIMARY_ROOT_CAUSE=C
LABEL=BOTH_PRODUCT_AND_PUBLISH_MISSING_INACTIVE_COMPAT
ROOT_CAUSE_MATCHES_RECOVERY_PLAN=true
```

### Pre-mutation trace (base dc58e38)

| OPERATION | FUNCTION | HANDLER | AUTHORIZER | NO_CONTROL | INACTIVE | ACTIVE | THROW_SITE |
|---|---|---|---|---|---|---|---|
| create | stockCatalogCommand | executeStockCommandInTransaction | authorizeInactiveLegacySale allowlist | failed-precondition | failed-precondition | grant path | stockCatalogAccess authorizeInactiveLegacySale kind |
| replace | stockCatalogCommand | same | sale allowlist | failed-precondition | failed-precondition | grant+CAS | same |
| editorial | stockCatalogCommand | same | sale allowlist | failed-precondition | failed-precondition | grant | same |
| delete | stockCatalogCommand | same | sale allowlist | failed-precondition | failed-precondition | grant | same |
| catalogPublishOne | catalogPublishOne | publishStockProduct | authorizeStockTransaction | failed-precondition | failed-precondition | grant publish | authorizeStockTransaction migration/grant |
| catalogPublishAll | catalogPublishAll | publishStockCatalog | authorizeStockTransaction | failed-precondition | failed-precondition | grant publish | same |

---

## Authorization design

```text
SALE_AUTH_REUSED_FOR_PRODUCT=false
SALE_AUTH_REUSED_FOR_PUBLISH=false
PRODUCT_COMPAT_AUTH_SEPARATE=true
PUBLISH_COMPAT_AUTH_SEPARATE=true

PRODUCT_AUTHORIZER=authorizeInactiveLegacyProductMutation
PUBLISH_AUTHORIZER=authorizeInactiveLegacyPublish
SHARED_MEMBERSHIP_HELPER=authorizeInactiveOwnerAdminOrCadastro
  (owner/admin/members owner|admin OR seller estoque|produtos|cadastro)
  (vendas-only sellers DENY for product/publish)

INACTIVE_PRODUCT_REQUIRES_ACTIVE=false
INACTIVE_PRODUCT_REQUIRES_MIGRATION=false
INACTIVE_PRODUCT_REQUIRES_GRANT=false
INACTIVE_PRODUCT_REQUIRES_OWNER_OR_ADMIN=true

INACTIVE_PUBLISH_REQUIRES_ACTIVE=false
INACTIVE_PUBLISH_REQUIRES_MIGRATION=false
INACTIVE_PUBLISH_REQUIRES_ROLLOUT_GRANT=false

ACTIVE_PRODUCT_AUTH_CHANGED=false
ACTIVE_PRODUCT_MIGRATION_REQUIREMENT_CHANGED=false
ACTIVE_PRODUCT_GRANT_REQUIREMENT_CHANGED=false
ACTIVE_PRODUCT_CAS_CHANGED=false
ACTIVE_PUBLISH_AUTH_CHANGED=false
```

```text
INACTIVE_PRODUCT_COMPAT_COMMANDS=create,replace,editorial,delete
```

---

## New inactive product schema

```text
NEW_INACTIVE_PRODUCT_STOCK_KIND_PERSISTED=true
NEW_INACTIVE_PRODUCT_STOCK_REVISION=0
NEW_INACTIVE_PRODUCT_DRAFT_CREATED=true
inferStockKind reused (no new algorithm)
EXISTING_PRODUCTS_BACKFILLED=0
GLOBAL_STOCK_KIND_BACKFILL=false
EXISTING_LEGACY_PRODUCT_MUTATED_ONLY_IF_COMMAND_TARGETS_IT=true
INACTIVE_COMBO_CREATE_REACHABLE=true
```

---

## Queue / delete / fail-closed

```text
QUEUE_STABLE_PRODUCT_ID=true
QUEUE_IDEMPOTENCY_MODEL=operationId marker → alreadyApplied; create-if-exists → already-exists; expectedRevision CAS on replace/delete
DUPLICATE_CREATE_COUNT=1
QUEUE_CREATE_UPDATE_FINAL_STATE_CORRECT=true
NEWER_UPDATE_LOST=false
STALE_QUEUE_OVERWRITE_PREVENTED=true
INACTIVE_DELETE_COMPAT_GREEN=true
STALE_QUEUE_CAN_RESURRECT_DELETED_PRODUCT=false
STALE_REPLAY_RESURRECTION=false
PRE_FIX_QUEUE_FORMAT_SUPPORTED=true
CUSTOMER_RECREATE_REQUIRED=false
CORRUPT_PRODUCT_FAIL_CLOSED=true
CORRUPT_DATA_FAIL_CLOSED=true
SECURITY_FAIL_CLOSED=true
```

---

## Publish

```text
INACTIVE_CATALOG_STOCK_SEMANTICS=
  projectCatalog from estoque_produtos + draft/editorial;
  availability via existing projection rules;
  resolveLegacyCompatStockKind for legacy missing metadata
PUBLIC_PRIVATE_FIELD_LEAKS=0
PUBLISH_ONE_IDEMPOTENT=true
PUBLISH_ALL_IDEMPOTENT=true
VALID_INACTIVE_PRODUCT_MIGRATION_ERRORS=0
VALID_INACTIVE_PUBLISH_MIGRATION_ERRORS=0
```

---

## ACTIVE / Rules / atomic inheritance

```text
RULES_SOURCE_CHANGED=false
RULES_CHANGE_REQUIRED=false
DIRECT_CLIENT_PROTECTED_WRITE_REMAINS_DENY=true

LEGACY_SALE_STOCK_KIND_FIX_PRESERVED=true
ATOMIC_SALE_FUNCTIONAL_DELTA_FROM_PRODUCT_FIX=NONE
NATHY_SALE_B_ATOMIC_REGRESSION_STILL_GREEN=true
NEW_PRODUCT_COMPAT_WEB_DELTA=NONE
NEW_PUBLISH_COMPAT_WEB_DELTA=NONE
ATOMIC_WEB_PATCH_UNCHANGED=true
ATOMIC_WEB_PATCH_IDENTITY_INHERITED=
  432edba3dacb76efaefe8717f049e9bea64fb8b7c21059ff59f45f7b7267a6f6
```

---

## Mixed-version / Function-first

```text
CUMULATIVE_FUNCTIONS_WITH_OLD_WEB_SAFE=true
FUNCTION_FIRST_CAN_RESTORE_PRODUCT_AND_PUBLISH=true
FUNCTION_FIRST_OLD_WEB_SALE_PROTOCOL_UNCHANGED=true
REQUIRED_FUNCTION_DEPLOY_TARGETS=
  stockCatalogCommand,catalogPublishOne,catalogPublishAll
DEPLOY_SCOPE_BLOCK=false
```

Old Web (web-c46d4d9) lacks atomicPdvSale flag → sales stay non-atomic; product queue + publish gain inactive compatibility via Functions only.

---

## Tests

```text
PRODUCT_COMPAT_TESTS=18/18
PUBLISH_COMPAT_TESTS=14/14
PRODUCT_PUBLISH_FILE=25/25 stock-catalog-inactive-product-publish-compat.test.mjs
LEGACY_STOCK_TESTS=25/25 stock-catalog-inactive-sale-compat.test.mjs
ACTIVE_STOCK_TESTS=38/38 stock-catalog-commands.test.mjs
PROJECTION_TESTS=26/26 catalog-stock-projection.test.mjs
MIGRATION_TESTS=15/15 stock-catalog-migration.test.mjs
ATOMIC_BACKEND_TESTS=22/22 stock-catalog-atomic-pdv-sale.test.mjs
ATOMIC_WEB_TESTS=17/17
  (atomic_pdv_sale_web_contract_test.dart + m39_sprint4_r4_venda_perf_test.dart)

FUNCTION_DISCOVERY_GREEN=true
ANALYZE_NEW_ISSUES=0
WEB_BUILD_GREEN=true
  (inherited dc58e38 release-readiness; no new Web delta this ticket)

EMULATOR_HOST=127.0.0.1:8299
BROAD_BACKEND_TEST_RUN=false
BROAD_FLUTTER_TEST_RUN=false
FIADO_74_RESIDUAL_RERUN=false
FIADO_REGRESSION=NOT_TOUCHED

PII_LOGGING_ADDED=false
```

---

## Patch identities

```text
PRODUCT_PUBLISH_FUNCTION_DELTA_SHA256=
  deef438a3533480f82048cc4c68c0c03893d6cbd5d51accf607da5d3bb7607ab
CUMULATIVE_FUNCTION_PATCH_SHA256=
  deef438a3533480f82048cc4c68c0c03893d6cbd5d51accf607da5d3bb7607ab
  (new product/publish delta ON TOP OF immutable dc58e38)
STOCK_CATALOG_COMMAND_CUMULATIVE_PATCH_SHA256=
  deef438a3533480f82048cc4c68c0c03893d6cbd5d51accf607da5d3bb7607ab
CATALOG_PUBLISH_ONE_PATCH_SHA256=
  deef438a3533480f82048cc4c68c0c03893d6cbd5d51accf607da5d3bb7607ab
CATALOG_PUBLISH_ALL_PATCH_SHA256=
  deef438a3533480f82048cc4c68c0c03893d6cbd5d51accf607da5d3bb7607ab
  (shared module graph: stockCatalogAccess.js + stockCatalogCommands.js)
```

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
WEB_SOURCE_PATHS_NEW_THIS_TICKET=NONE
RULES_PATHS=NONE
UNRELATED_PATHS=NONE
```

Harness-only test edits: allow FIRESTORE_EMULATOR_HOST=127.0.0.1:<any local port> (8299) instead of hard-coded 8187.

---

## Accounting / freezes / customer policy

```text
PRODUCTION_READS=0
PRODUCTION_WRITES=0
QUEUE_REPLAYS=0
CUSTOMER_TESTS=0
SYNTHETIC_PRODUCTION_CALLS=0
FUNCTION_DEPLOYS=0
HOSTING_DEPLOYS=0
RULES_DEPLOYS=0
GIT_STAGES=0
GIT_COMMITS=0
GIT_PUSHES=0
GIT_AMENDS=0

SALE_B_REMOTE_SALE_INSERTED=false
SALE_B_STOCK_CORRECTED=false
SALE_B_OPERATION_CHANGED=false
SALE_B_IDEMPOTENCY_CHANGED=false

CUSTOMER_SHOULD_NOT_RECREATE_FAILED_PRODUCTS=true
CUSTOMER_SHOULD_NOT_REPEAT_UPDATE_CATALOG=true
CUSTOMER_SHOULD_NOT_CLEAR_APP_DATA=true
CUSTOMER_SHOULD_NOT_DELETE_QUEUE=true
SALE_FLOW_SAFE_FOR_GENERAL_USE=false

STOCK_CATALOG_ROLLOUT_FROZEN=true
```

---

## Next

```text
NEXT=
  MASTERPALM_GLOBAL_PRODUCT_SYNC_AND_CATALOG_PUBLISH_FAILED_PRECONDITION_EMERGENCY_RELEASE_READINESS
```

That ticket must freeze cumulative Function patch identities, preserve atomic Web patch, prepare ONE new release commit ON TOP OF dc58e38, Function-first deploy plan for the three targets, NO deploy / queue replay / customer test / SALE B repair yet.

---

## STOP

```text
NO_STAGE=true
NO_COMMIT=true
NO_PUSH=true
NO_DEPLOY=true
NO_QUEUE_REPLAY=true
NO_CUSTOMER_RETRY_AUTH=true
NO_AMEND_DC58E38=true
NO_MIGRATE=true
NO_ACTIVATE=true
NO_GRANTS=true
NO_GRADE=true
NO_ROLLOUT_RESUME=true
```
