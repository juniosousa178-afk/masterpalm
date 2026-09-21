# Track B — RO review of 4 true remote inconsistencies

`PRODUCTION_DATA_REPAIR=false` — no writes.

## Shared notes

- Sales ledger: `estoque_vendas` items use nested `itens[].productId` (no indexed query available via MCP for product filter).
- Consignments: not retrieved in this pass (no product-indexed RO path used).
- Evidence used: product document fields + timestamps + `vendasCatalogoTotal` where present.

---

## 1) Anel Verde Glow — PHYSICAL_COUNT_REQUIRED

| Field | Value |
|---|---|
| PRODUCT_ID | `nathy-pratas-e-folheados-anel-verde-glow` |
| PRODUCT_CODE | *(null/absent)* |
| REMOTE_AGGREGATE | 5 |
| NORMALIZED_CELLS | 14\|verde=1, 15\|verde=1, 16\|verde=1, 17\|verde=1, 20\|verde=1, 21\|verde=1 |
| CELL_SUM | 6 |
| STOCK_REVISION | 1 |
| STOCK_OPERATION_ID | `bc125879-dbf6-458f-9582-6b50c3a269f1` |
| stockUpdatedAt | 2026-07-27T23:17:31.124Z |
| updatedAt / lastWrite | 2026-09-02 / `produto_form.save` |
| LAST_STOCK_MOVEMENTS | NOT_INDEXED_IN_THIS_PASS |
| RELEVANT_SALES | NOT_INDEXED_IN_THIS_PASS |
| RELEVANT_CONSIGNMENTS | NOT_INDEXED_IN_THIS_PASS |
| LAST_KNOWN_CONSISTENT_STATE | unknown (rev=1; qty vs 6 cells never reconciled in doc) |

**CLASSIFICATION:** `PHYSICAL_COUNT_REQUIRED` (unchanged)

---

## 2) Pingente Rosto Filhos — PHYSICAL_COUNT_REQUIRED

| Field | Value |
|---|---|
| PRODUCT_ID | `nathy-pratas-e-folheados-pingente-rosto-filhos` |
| REMOTE_AGGREGATE | 4 |
| NORMALIZED_CELLS | menina\|prata=4, menino\|prata=2 |
| CELL_SUM | 6 |
| STOCK_REVISION | 1 |
| STOCK_OPERATION_ID | `ece964c8-ea1a-4355-866b-2247cb4602aa` |
| stockUpdatedAt | 2026-07-27T23:18:31.654Z |
| lastWriteOrigin | `sync_queue.upsert_produto` (2026-08-07) |
| LAST_KNOWN_CONSISTENT_STATE | unknown |

**CLASSIFICATION:** `PHYSICAL_COUNT_REQUIRED` (unchanged)

---

## 3) Colar Veneziana Cruz 50cm — LEGACY_ORPHAN_CELL

| Field | Value |
|---|---|
| PRODUCT_ID | `nathy-pratas-e-folheados-colar-veneziana-cruz-50cm` |
| REMOTE_AGGREGATE | 0 |
| NORMALIZED_CELLS | 50cm\|prata=1 |
| CELL_SUM | 1 |
| STOCK_REVISION | 1 |
| STOCK_OPERATION_ID | `b28ffd0d-1838-42a1-9d84-8b553aa6c421` |
| vendasCatalogoTotal | 1 |
| stockUpdatedAt | 2026-08-13T11:05:30.189Z |
| updatedAt / lastWrite | 2026-08-17 / (client bump; no origin field in mask) |

Interpretation: aggregate already 0 with catalog sale counter=1; leftover cell likely post-sale orphan / form rewrite — **not** proven as physical unit on shelf.  
Not SAFE_DATA_REPAIR without sale line proof.

**CLASSIFICATION:** `LEGACY_ORPHAN_CELL`  
**REPAIR:** `NO_DATA_REPAIR` this execution

---

## 4) Piercing Argolinha Clara — LEGACY_ORPHAN_CELL

| Field | Value |
|---|---|
| PRODUCT_ID | `nathy-pratas-e-folheados-piercing-argolinha-clara` |
| REMOTE_AGGREGATE | 0 |
| NORMALIZED_CELLS | 10mm\|prata=1 |
| CELL_SUM | 1 |
| STOCK_REVISION | 1 |
| STOCK_OPERATION_ID | `cb968c83-d606-4b93-9570-0e775e087fb8` |
| vendasCatalogoTotal | 1 |
| stockUpdatedAt | 2026-08-13T11:05:03.526Z |
| lastWriteOrigin | `produto_form.save` (2026-08-17) |

Same pattern as Veneziana.

**CLASSIFICATION:** `LEGACY_ORPHAN_CELL`  
**REPAIR:** `NO_DATA_REPAIR` this execution

---

## Counts after Track B

```
TRUE_REMOTE_INCONSISTENCY_COUNT=4
SAFE_DATA_REPAIR_COUNT=0
PHYSICAL_COUNT_REQUIRED_COUNT=2
MANUAL_REVIEW_REQUIRED_COUNT=0
LEGACY_ORPHAN_CELL_COUNT=2
```
