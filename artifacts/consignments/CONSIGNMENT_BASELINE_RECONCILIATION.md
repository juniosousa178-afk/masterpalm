# CONSIGNMENT BASELINE RECONCILIATION

## Goal

Merge-forward a single Hosting-ready baseline that restores customer-facing consignments on `app.mastepalm.com.br` **without** rolling back stock fixes.

## Inputs

| Piece | Source | Keep |
|---|---|---|
| Settlement UI + settle client | HEAD `bc2189c` + WT details/settle screens | YES |
| addItems / picker / code search / reports | Working tree (previously uncommitted) | YES |
| Grade + multi-product errors | `6725eac` | YES |
| Editorial draft gate fix | `d284595` | YES |
| stockCatalogCommand atomicPdvSale allowlist | `bc2189c` → live `00012-liv` | YES (do not redeploy unless dirty) |
| Hosting wrong artifact | live `masterpalm-58c46` = `web-485369a` | REPLACE via Hosting deploy |
| Hosting good twin | `mastepalm.web.app` = `1.0.84+100` | Align to consolidated build |

## Explicit non-goals

- No `git reset --hard` to `485369a`
- No global rollback of Functions
- No stockCatalogCommand redeploy unless its tree changes
- No Firestore / stock / consignment production writes during restore

## Strategy

1. Branch from `bc2189c` (stock fix + committed consignments core).
2. Commit forward-port of addItems/picker/reports/eligibility and matching function deltas.
3. Stamp `web/version.json` + `pubspec` with new build identity including git SHA.
4. Hosting deploy to **masterpalm-58c46** (custom domain) and **mastepalm** (parity).
5. Redeploy `consignmentCommand` only if committed function delta is not already live on `00009-poy`.

## Conflict policy

Shared files (`consignmentCommand`, eligibility, details screen): prefer **newer consignments UX** while preserving stock/legacyCompat semantics already on live Functions where possible.
