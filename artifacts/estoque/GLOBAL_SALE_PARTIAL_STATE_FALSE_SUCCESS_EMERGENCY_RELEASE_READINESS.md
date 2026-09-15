# GLOBAL SALE PARTIAL STATE / FALSE SUCCESS — EMERGENCY RELEASE READINESS

Classification: **MASTERPALM_GLOBAL_SALE_PARTIAL_STATE_FALSE_SUCCESS_EMERGENCY_RELEASE_READINESS_GREEN**

## Entry

| Key | Value |
|-----|-------|
| LOCAL_GREEN | MASTERPALM_GLOBAL_SALE_PARTIAL_STATE_FALSE_SUCCESS_EMERGENCY_LOCAL_GREEN |
| LOCAL_BASE | `75851a9856cdd443cf84c8fe480839753697b982` |
| LOCAL_WORKTREE | `C:\Users\Pichau\AppData\Local\Temp\masterpalm-sale-stock-atomicity-emergency-local` |
| HEAD_BEFORE_RELEASE | `75851a9856cdd443cf84c8fe480839753697b982` |
| DIFF_CHECK_GREEN | true |
| HISTORICAL_WIP_UNTOUCHED | true |
| SALE_FLOW_SAFE_FOR_GENERAL_USE | false |
| CUSTOMER_CONTROLLED_TEST_SALES_ALLOWED | false |
| SALE_B_REPAIR_REQUIRED | true |
| SALE_B_REPAIR_AUTHORIZED | false |
| STOCK_CATALOG_ROLLOUT_FROZEN | true |
| GRADE_RECOVERY_IMPLEMENTATION_PAUSED | true |
| GRADE_SELECTOR_INCIDENT_REMAINS_OPEN | true |

## Patch identity freeze

| Key | Value |
|-----|-------|
| RECOMPUTED_FUNCTION_PATCH_SHA256 | `8f9a587ffd7dac90292af9979821239e770afbe6497c53c203409a0a31bd431d` |
| RECOMPUTED_WEB_PATCH_SHA256 | `432edba3dacb76efaefe8717f049e9bea64fb8b7c21059ff59f45f7b7267a6f6` |
| RECOMPUTED_COMBINED_PATCH_SHA256 | `9babdaebfff4fdfeb9d1d64fbd58707bd45b59b95da6ecead34074865f6ec833` |
| FUNCTION_PATCH_MATCH | true |
| WEB_PATCH_MATCH | true |
| COMBINED_PATCH_MATCH | true |

## Production baseline (read-only)

| Key | Value |
|-----|-------|
| PROJECT | masterpalm-58c46 |
| FUNCTION | stockCatalogCommand |
| LIVE_REVISION | stockcatalogcommand-00003-xiz |
| RULES | 2781401861d96b45867d98f68a0f0d2c3898ed546296eb2c4fbdb445661af071 |
| WEB /version.json | web-c46d4d9 |
| PRODUCTION_BASELINE_EXACT | true |
| PRODUCTION_METADATA_DRIFT | false |

## Atomic protocol

| Key | Value |
|-----|-------|
| ATOMIC_PROTOCOL_OPT_IN | true |
| ATOMIC_PROTOCOL_FLAG | `atomicPdvSale=true` |
| OLD_PROTOCOL_BEHAVIOR_PRESERVED | true |
| NEW_PROTOCOL_ATOMIC | true |
| FUNCTION_FIRST_WITH_OLD_WEB_SAFE | true |
| FUNCTION_FIRST_TRANSITION_SAFE | true |
| OLD_WEB_GENERAL_SALE_SAFETY | false |
| NEW_WEB_WITH_OLD_FUNCTION_ALLOWED | false |
| HOSTING_FIRST_ALLOWED | false |
| HOSTING_RELEASE_REQUIRED | true |
| RELEASE_ORDER_FROZEN | true |
| RELEASE_COMMIT_STRATEGY | ONE_COMMIT_TARGETED_STAGED_DEPLOYS |

### Mixed-version matrix

| CLIENT | FUNCTION | ATOMIC_FLAG | SALE_OWNER | STOCK_OWNER | SAFE_FOR_RELEASE_TRANSITION |
|--------|----------|-------------|------------|-------------|-----------------------------|
| OLD | 00003/old | absent | client syncVenda | stockCatalogCommand | false (historical split) |
| OLD | NEW atomic | absent | client syncVenda | stockCatalogCommand | true (no backend sale) |
| NEW | NEW atomic | true | backend atomic | backend atomic | true (target) |
| NEW | OLD | n/a reject | n/a | n/a | false (forbidden by order) |

## Invariants revalidated

| Key | Value |
|-----|-------|
| SALE_AND_STOCK_SINGLE_TRANSACTION | true |
| STOCK_ONLY_SUCCESS_POSSIBLE | false |
| SALE_ONLY_SUCCESS_POSSIBLE | false |
| LEGACY_STOCK_KIND_FIX_PRESERVED | true |
| STOCK_KIND_BACKFILL | false |
| NATHY_SALE_B_REGRESSION_PRESENT | true |
| NATHY_SALE_B_PARTIAL_STATE_IMPOSSIBLE_POST_FIX | true |
| RETRY_AFTER_COMMIT_RETURNS_EXISTING_RESULT | true |
| DUPLICATE_SALE | false |
| DOUBLE_STOCK_DECREMENT | false |
| OPERATION_ID_SEMANTICS_PRESERVED | true |
| SIMPLE_ATOMIC_GREEN | true |
| VARIATION_ATOMIC_GREEN | true |
| SELECTED_SIZE_ONLY_DECREMENTED | true |
| OTHER_SIZES_UNCHANGED | true |
| COMBO_ATOMIC_RESULT | GREEN (PDV reachable; expansion via existing sale protocol) |
| ACTIVE_ATOMIC_SALE_GREEN | true |
| ACTIVE_STOCK_REVISION_CAS_PRESERVED | true |
| ACTIVE_STALE_REVISION | NO_SALE_NO_STOCK_CHANGE |
| ACTIVE_AUTHORIZATION_CHANGED | false |
| NO_CONTROL_ATOMIC_SALE_GREEN | true |
| INACTIVE_ATOMIC_SALE_GREEN | true |
| MIGRATION_REQUIRED | false |
| ACTIVATION_REQUIRED | false |
| GRANT_REQUIRED | false |
| FAILURE_MATRIX_GREEN | true |
| CANONICAL_SALE_SCHEMA_REUSED | true |
| PARALLEL_SALE_SCHEMA_CREATED | false |
| HISTORY_COMPATIBLE | true |
| CLIENT_SYNC_VENDA_AFTER_ATOMIC_SUCCESS | false |
| UNRELATED_SYNC_VENDA_CALLS_PRESERVED | true |
| HIVE_ROLE | MIRROR |
| HIVE_UPDATED_AFTER_AUTHORITATIVE_COMMIT | true |
| HIVE_FAILURE_CANNOT_TRIGGER_SECOND_REMOTE_SALE | true |
| HIVE_LOCAL_SUCCESS_CANNOT_PRECEDE_REMOTE_COMMIT | true |
| SUCCESS_MODAL_BEFORE_ATOMIC_COMMIT | false |
| INTENT_COMPLETED_BEFORE_ATOMIC_COMMIT | false |
| OFFLINE_SUCCESS_MODAL | false |
| OFFLINE_FINAL_SALE_SEMANTICS | blocked_error_no_success |
| PDV_MUTATION_GATE_PRESERVED | true |
| ATOMIC_SALE_IN_FLIGHT_PROTECTED_FROM_RELOAD | true |
| RULES_CHANGE_REQUIRED | false |

## Tests / gates

| Key | Value |
|-----|-------|
| BACKEND_TEST_MANIFEST | `functions/test/stock-catalog-atomic-pdv-sale.test.mjs` |
| BACKEND_TESTS | 22/22 |
| WEB_TEST_MANIFEST | `test/atomic_pdv_sale_web_contract_test.dart`, `test/m39_sprint4_r4_venda_perf_test.dart` |
| WEB_TESTS | 17/17 |
| ANALYZE_NEW_ISSUES | 0 |
| WEB_BUILD_GREEN | true |
| LOCAL_WEB_RELEASE | build/web GREEN (version.json template not rewritten in this ticket) |
| FUNCTION_DISCOVERY_GREEN | true |
| STOCK_CATALOG_COMMAND_EXPORT_GREEN | true |
| EMULATOR_8187_PORT_CONFLICT | NON_BLOCKING_LOCAL_HARNESS_ISSUE |
| BACKEND_TEST_VALIDATION | VALID_ON_8199 |
| BROAD_BACKEND_TEST_RUN | false |
| BROAD_FLUTTER_TEST_RUN | false |
| FIADO_74_RESIDUAL_RERUN | false |
| FIADO_SHARED_CODE_TOUCHED | true |
| FIADO_REGRESSION | GREEN (pre-existing fail on clean 75851a9 for `contas_receber_upsert_apos_venda_fiada_test`; not attributable to atomic patch) |

## Stage plans (NOT executed)

| Stage | Scope | Notes |
|-------|-------|-------|
| 1 | `functions:stockCatalogCommand` | STAGE1_DEPLOY_ATTEMPTS_MAX=1; old-Web compat required |
| 2 | Function health + old-Web | no Hosting |
| 3 | `hosting:masterpalm-58c46` | only after Stage 1 GREEN |
| 4 | /version.json + convergence | |
| 5 | controlled natural atomic-sale auth gate | separate ticket |
| 6 | read-only first atomic sale observation | |

STAGE1_PLANNED_SCOPE=`functions:stockCatalogCommand`  
HOSTING_DEPLOY_BEFORE_FUNCTION_GREEN=false  
FUNCTION_DEPLOYS=0 · HOSTING_DEPLOYS=0 · RULES_DEPLOYS=0

## Release git

| Key | Value |
|-----|-------|
| RELEASE_BRANCH | `stock-catalog/emergency-atomic-pdv-sale` |
| REMOTE_BRANCH_EXISTS (pre-push) | false |
| ATOMIC_SALE_RELEASE_COMMIT | _(filled after commit)_ |
| COMMIT_PARENT | `75851a9856cdd443cf84c8fe480839753697b982` |
| PUSH_ATTEMPTS | 1 |
| COMMITS | 1 |
| PUSHES | 1 |

## SALE B / policy

SALE_B_* untouched = true · PRODUCTION_WRITES=0 · no customer sales

## Next

**MASTERPALM_GLOBAL_SALE_PARTIAL_STATE_FALSE_SUCCESS_EMERGENCY_FUNCTION_PRODUCTION_RELEASE**

STOP — no deploy in this ticket.
