# CONSIGNMENT MVP — Release

DECISION=A
MVP_IMPLEMENTED_TESTED_RELEASED_CANARY_READY

- Branch: `feature/consignments-mvp`
- Implementation commit: `35998c53bcc7f77e22c238d0eaeb4625995a3a23`
- Web version: `1.0.80+96`
- Build id: `consignments-mvp-1.0.80`
- Function: `consignmentCommand` southamerica-east1 revision `consignmentcommand-00001-jof`
- `stockCatalogCommand` **not** redeployed
- Rules: consignment collections read `belongsToStore`; writes via Functions/Admin only
- Feature flag default: **false**
- Enabled stores: **none**
- GLOBAL_ROLLOUT=false

## Deploys

- FUNCTION_DEPLOYS=1 (`functions:default:consignmentCommand`)
- RULES_DEPLOYS=1 (`firestore:rules`)
- HOSTING_DEPLOYS=2 (`hosting:mastepalm` then customer `hosting:masterpalm-58c46`)

Customer URL: https://app.mastepalm.com.br/version.json → `consignments-mvp-1.0.80`

## Canary (no customer consignment created)

- Route `/consignados` loads SPA shell
- Function healthy (`consignmentcommand-00001-jof` Ready)
- Unauthenticated callable is denied (auth gate)
- Feature flag default false; no store `consignment_control/state.moduleEnabled`

## Enable a canary store (support/console only)

`lojas/{lojaId}/consignment_control/state = { protocolVersion: 1, moduleEnabled: true }`

Do not enable globally. Do not create customer consignments automatically.
