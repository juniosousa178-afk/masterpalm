# NATHY — Root cause: variation hydration

STORE=`nathy-pratas-e-folheados`  
Evidence=`NATHY_CLIENT_STOCK_DIAGNOSTIC_20260921_185253Z.json`  
Canary=`Anel Lacinho Encanto` (`nathy-pratas-e-folheados-anel-lacinho-encanto`)

## Verdict

`ROOT_CAUSE_VARIATION_NOT_PULLED=SALE_USES_STALE_HIVE_VARIATION_METADATA`

`LOCAL_PRODUCT_STRUCTURE_STALE=true`  
`REMOTE_PRODUCT_STRUCTURE_VALID=true`

## Flow map

| Stage | Source | Lacinho before fix |
|---|---|---|
| `SALE_SEARCH_SOURCE` | Hive / in-memory `Produto` list | `stockKind=simple`, `usaVariacoes=false`, `variations=null`, `tamanhos=[15,22]` |
| `SALE_HYDRATION_FUNCTION` | *(missing)* — no remote stock hydrate before picker | — |
| `PICKER_DECISION_SOURCE` | Local `usaVariacoes` / `estoquePorTamanho` / `tamanhos` heuristics | Treated as **simple** → cart without size |
| `ROOT_CAUSE_VARIATION_METADATA_LOST_AT` | Between search result and variation picker gate | Remote never applied to sale path |

## Authoritative remote (RO 2026-09-21)

- `stockKind=variation`, `qty=2`, `stockRevision=8`
- cells: `15|sem-cor=1`, `22|sem-cor=1`

## Hive snapshot (diagnostic)

- `stockKind=simple`, `qty=2`, `stockRevision=8`
- `usaVariacoes=false`, `variations=null`, `estoquePorTamanho={}`

## Contributing pull bug

On Firestore pull with `preserveLocalEdits=true`, variation grade apply was skipped even when there was **no** real pending stock mutation — leaving Hive structure stale while qty/revision could already match remote.

## Expected sale after fix

- `PICKER_REQUIRED=true`
- options: `15 (1)`, `22 (1)`
- cart keys: `15|sem-cor`, `22|sem-cor`
