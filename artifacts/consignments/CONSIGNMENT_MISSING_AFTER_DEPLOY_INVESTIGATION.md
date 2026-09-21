# CONSIGNMENT MISSING AFTER DEPLOY — INVESTIGATION

## Verdict

**ROOT_CAUSE=HOSTING_SITE_MASTERPALM_58C46_SERVES_PRE_CONSIGNMENT_BUILD_web-485369a**

Customers on `https://app.mastepalm.com.br` load Hosting site **masterpalm-58c46**, whose live release (2026-09-20 22:12:34 local / Last-Modified 2026-09-21 01:12:34Z) still ships **web-485369a** (`gitCommit=485369a`).

That commit is **not** on the consignments lineage and contains **zero** `lib/features/consignments/**` files.

Meanwhile `https://mastepalm.web.app` still serves **1.0.84+100** / `grade-multi-error-1.0.84`, whose `main.dart.js` **does** contain `Fazer acerto`, `addItems`, `consignmentCommand`, `SETTLED`.

## Presence matrix (repo HEAD vs live app domain)

| Surface | HEAD workspace | Live app.mastepalm.com.br (485369a) | Live mastepalm.web.app (1.0.84) | Live Functions |
|---|---|---|---|---|
| Settlement UI (`Fazer acerto`) | PRESENT | ABSENT | PRESENT | n/a |
| Settlement route/screen | PRESENT | ABSENT | PRESENT | n/a |
| Settlement client (`ConsignmentService.settle`) | PRESENT | ABSENT | PRESENT | n/a |
| Settlement backend (`operation: settle`) | PRESENT | n/a | n/a | PRESENT (`consignmentcommand-00009-poy`) |
| Settlement report PDF | PRESENT (WT + mastepalm) | ABSENT | PRESENT | n/a |

**Classification of disappearance:** **A/C for the customer-facing domain** — client/hosting for `app.mastepalm.com.br` lost the whole consignments module (not only a button). Backend SETTLE remains.

```
CONSIGNMENT_SETTLEMENT_UI_PRESENT=true   # in HEAD / mastepalm.web.app
CONSIGNMENT_SETTLEMENT_ROUTE_PRESENT=true
CONSIGNMENT_SETTLEMENT_CONTROLLER_PRESENT=true
CONSIGNMENT_SETTLEMENT_BACKEND_PRESENT=true
CONSIGNMENT_SETTLEMENT_REPORT_PRESENT=true  # HEAD WT + mastepalm; false on app domain
```

Customer symptom on **app.mastepalm.com.br**: entire consignments client missing → looks like “venda/acerto sumiu”.

## Git / deploy identity

```
CURRENT_HEAD=bc2189c (release/p0-sale-protected-command-field)
CURRENT_BRANCH=release/p0-sale-protected-command-field
LAST_DEPLOYED_HOSTING_COMMIT(app domain)=485369a
LAST_KNOWN_GOOD_CONSIGNMENT_HOSTING=1.0.84+100 on mastepalm.web.app (from 6725eac lineage)
STOCK_FIX_COMMIT=bc2189c (atomicPdvSale allowlist; stockCatalogCommand 00012-liv)
SALE_SETTLEMENT_COMMIT=35998c5 (MVP) + screens in HEAD; settle UI gate = isIssued
ADD_ITEMS / REPORTS=present in working tree (uncommitted) and in mastepalm 1.0.84 bundle strings
```

`485369a` is **not** an ancestor of HEAD consignments history (`merge-base --is-ancestor 485369a HEAD` = false). Hosting for masterpalm-58c46 was published from a **different/older baseline**.

## Explicit answers

```
WAS_HOSTING_DEPLOYED_FROM_OLDER_BASELINE=true
WAS_WRONG_BRANCH_DEPLOYED=true   # wrong lineage/site content on masterpalm-58c46
WAS_FEATURE_COMMIT_MISSING=true  # relative to live app domain build
WAS_MERGE/CHERRY_PICK_INCOMPLETE=false  # not the primary cause; wrong hosting artifact
WAS_FEATURE_FLAG_DISABLED=false  # module still flag-gated per store; 1.0.84 still shows UI when enabled
WAS_ROUTE_REMOVED=false          # removed only because whole module absent from 485369a bundle
WAS_UI_HIDDEN_BY_STATUS_LOGIC=false
```

## Diff signal (485369a vs HEAD consignments)

```
FILES_REMOVED_FROM_LIVE_APP_DOMAIN=all lib/features/consignments/** (0 files at 485369a, 12+ at HEAD)
ROUTES/BUTTONS_REMOVED=ConsignmentSettleScreen + "Fazer acerto" (absent from app domain main.dart.js)
COMMANDS_REMOVED_FROM_CLIENT=consignmentCommand callable usage absent in app domain JS
BACKEND_COMMANDS_NOT_REMOVED=createDraft,cancelDraft,issue,settle,addItems still in consignmentCommand 00009-poy
```

## Backend ops supported (live)

```
CREATE_SUPPORTED=true   # createDraft
ISSUE_SUPPORTED=true
ADD_ITEMS_SUPPORTED=true
SETTLE_SUPPORTED=true
CANCEL_SUPPORTED=true   # cancelDraft
```

## Firestore

MCP Firestore reads failed with `read_time cannot be in the future` (tooling clock skew). Prior MIRJOIAS settlement proof artifacts show real SETTLED docs existed; **no evidence data was deleted**. Treat as: **data likely intact; client on app domain cannot render module**.

## What NOT to do

- Do not `reset --hard` to 485369a or to an old consignment-only commit.
- Do not redeploy stockCatalogCommand unless its source changes.
- Do not assume mastepalm.web.app == customer app (custom domain points at masterpalm-58c46).
