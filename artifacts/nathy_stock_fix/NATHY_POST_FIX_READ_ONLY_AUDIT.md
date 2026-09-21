# NATHY — Post-fix read-only audit

STORE=`nathy-pratas-e-folheados`  
Source: client diagnostic `20260921_185253Z` + live RO masked reads (2026-09-21)  
Code fix applied locally; **no** production data repair; **no** deploy.

## Counters

| Metric | Value |
|---|---|
| TOTAL_PRODUCTS | 615 |
| REMOTE_VARIABLE_PRODUCTS | ≥271 (270 Hive `variation` + Lacinho remote-proven; full cell sweep limited by MCP `nullValue` schema) |
| LOCAL_STALE_STOCK_KIND_COUNT | 1 (Anel Lacinho Encanto) |
| LOCAL_STALE_VARIATION_METADATA_COUNT | 5 (Anel Fé, Fé Zircônias, Solitário Elegante Cristal, Solitário Oval Belle, Conjunto Gota Lilás Luxo) |
| REMOTE_LEGACY_STOCK_KIND_NULL_WITH_CELLS_COUNT | ≥4 (Verde Glow, Veneziana Cruz 50cm, Argolinha Clara, Rosto Filhos) |
| SALE_VARIATION_OPTIONS_MISSING_BEFORE | 6 (Lacinho + 5 incomplete metadata) |
| SALE_VARIATION_OPTIONS_MISSING_AFTER | 0 (structure; hydration path) |
| LEGACY_SIZE_METADATA_ONLY_COUNT | 118 identities (of 136 tamanhos orphans) |
| RAW_AGGREGATE_MISMATCH_COUNT | 193 |
| NORMALIZED_AGGREGATE_MISMATCH_COUNT | 9 |
| NORMALIZED_REMOTE_AGGREGATE_MISMATCH_COUNT | 4 |
| LOCAL_REMOTE_QTY_DELTA (pre-hydrate snapshot) | -5 |
| LOCAL_REMOTE_QTY_DELTA_AFTER_HYDRATION | 0 for qty totals vs remote aggregates (pending-free cache refresh); **4** remote cell/aggregate conflicts remain |

## Canary remotes (RO)

| Product | Remote kind | Cells / qty |
|---|---|---|
| Lacinho | variation | 15=1,22=1 / qty=2 |
| Anel Fé | variation | 16,17,18,22 ×1 / qty=4 |
| Fé Zircônias | variation | 5 cells / qty=5 |
| Solitário Elegante | variation | 14+18 / qty=2 |
| Solitário Oval Belle | variation | 17/18=1 / qty=1 |
| Gota Lilás Luxo | variation | 45cm|sem-cor=1 / qty=1 |
| Ondinha | variation | 14,18,21=1;15=0 / qty=3 |

## Delta −5 (confirmed)

Ondinha −2 + Solitário Elegante −1 + Verde Glow −4 + Veneziana +1 + Argolinha +1 = **−5**

## Diagnostic exporter (post-fix tests)

`DIAGNOSTIC_SNAPSHOT_MUTATION=false`  
`DELTA_ACCOUNTING_PASS=true` (unit)
