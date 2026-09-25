# Nathy Stabilization — Phase A (READ_ONLY) + Code Fix Plan

STORE_ID=nathy-pratas-e-folheados
MODE=READ_ONLY for pending data
TIMESTAMP=2026-09-25

## Pending 12 audit

PENDING_COUNT_BEFORE=12
PENDING_APPLIED_STALE_COUNT=12
PENDING_SAFE_RETRY_COUNT=0
PENDING_REVISION_CONFLICT_COUNT=0
PENDING_DUPLICATE_COUNT=0
PENDING_FAILED_COUNT=0
PENDING_UNKNOWN_COUNT=0

All 12 are `pendingSoftDelete=true` on estoque_produtos with exclusao_produto `p:true` tombstones.
Classification: APPLIED_BUT_PENDING_MARKER_STALE
REPAIR_ACTION: CLEAR_STALE_PENDING_MARKER (plan only — NOT executed)

PENDING_REPAIR_SAFE=true (deterministic stale markers)
PENDING_REPAIR_PLAN=clear pendingSoftDelete fields only after explicit Phase B authorization

PENDING_AFFECTED_ACTIVE_PRODUCT_COUNT=12 (sale/consignment/physical recon blocked; edit not blocked)

## Historical 13 deletes

DATA_REPAIR=false
HISTORICAL_13_DELETES_RESTORED=false

## Code fixes shipped (1.0.111)

- Stale stock edit never queued; conflict UI + grade refresh
- Editorial-only save independent of stock revision
- Colar Letra EXTRA_TYPE=LETRA hydration + destroy guard
- Catalog publish chunked/resumable + progress UI
- Notification server lida/lidaEm/lidaPor
- Pre-delete stock audit snapshot + positive qty confirmation
