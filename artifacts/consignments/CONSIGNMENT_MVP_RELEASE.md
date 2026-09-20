# CONSIGNMENT MVP — Release

DECISION=A (local green; deploy of consignmentCommand + rules + hosting)

- Branch: `feature/consignments-mvp`
- Web version: `1.0.80+96`
- Function: `consignmentCommand` (does not redeploy `stockCatalogCommand`)
- Rules: read-only consignment collections; writes via Admin SDK/Functions only
- Feature flag default: **false**
- Enabled stores: **none**
- GLOBAL_ROLLOUT=false

Enable a canary store (support/console only):

`lojas/{lojaId}/consignment_control/state = { protocolVersion: 1, moduleEnabled: true }`

Do not create customer consignments automatically after deploy.
