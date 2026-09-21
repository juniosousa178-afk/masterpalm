# NATHY — Diagnostic snapshot + auditor fix

## Bug confirmed

`DELTA_ACCOUNTING_PASS=false` on client export  
`HIVE_TOTAL_QTY=809` vs `REMOTE_TOTAL_QTY=814` (`DELTA=-5`)  
but `LOCAL_REMOTE_QTY_DELTA_PRODUCTS` listed only **1** row (`DELTA_SUM=1`).

### Hypothesis (confirmed by accounting)

During export, in-memory `Produto` instances were already partially mutated (session hydrate/sync), so:

- early sum used raw Hive qty (809)
- per-product delta used post-mutation qty ≈ remote → most deltas vanished

Independent reconstruction from **immutable** hive rows in the same JSON:

| Product | Hive qty | Remote qty | Delta |
|---|---:|---:|---:|
| Anel Ondinha | 1 | 3 | -2 |
| Anel Solitário Elegante Cristal | 1 | 2 | -1 |
| Anel Verde Glow | 1 | 5 | -4 |
| Colar Veneziana Cruz 50cm | 1 | 0 | +1 |
| Piercing Argolinha Clara | 1 | 0 | +1 |
| **SUM** | | | **-5** |

## Aggregate auditor bug

`AGGREGATE_MISMATCHES=193` counted `cor` + `sem-cor` aliases as independent stock.  
~186/193 showed `RAW_CELL_SUM ≈ AGGREGATE * 2`.

After `normalizeSemCorAliasCells`:

- `RAW_AGGREGATE_MISMATCH_COUNT=193`
- `NORMALIZED_REMOTE_AGGREGATE_MISMATCH_COUNT=4`
- `NORMALIZED_AGGREGATE_MISMATCH_COUNT=9` (includes local incomplete grades vs local aggregate)

## Orphan variations reclass

136 rows with `SOURCE_FIELD=tamanhos`, `QTY=0`, no pending:

- **118** → `LEGACY_SIZE_METADATA_ONLY` (no local/remote canonical cell)
- **18** → size exists remotely (not pure legacy orphan)

## Fix in exporter

`lib/services/mirjoias_client_stock_diagnostic_export.dart`:

1. `captureLocalStockSnapshot` **before** any remote read  
2. Never use mutated live fields for hive totals / deltas  
3. Normalize cells before aggregate compare  
4. Emit `DIAGNOSTIC_SNAPSHOT_MUTATION=false`, `LEGACY_SIZE_METADATA_ONLY*`, raw/normalized mismatch counters  

Unit tests: `test/mirjoias_client_stock_diagnostic_export_test.dart`  
→ `DELTA_ACCOUNTING_PASS=true`, alias case → normalized mismatch 0.
