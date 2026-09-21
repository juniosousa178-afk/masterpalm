# NATHY — True remote stock inconsistencies (NO REPAIR)

`PRODUCTION_DATA_REPAIR=false` — evidence only.

All four have **normalized** cell sum ≠ remote aggregate. History/sales deep RO was limited (Firestore query `read_time` clock skew on MCP); classification uses document fields + catalog sale counters.

---

## A) Anel Verde Glow

- id: `nathy-pratas-e-folheados-anel-verde-glow`
- remote `quantidade=5`, `stockRevision=1`, `stockOperationId=bc125879-dbf6-458f-9582-6b50c3a269f1`
- `stockKind`: **null/absent** (legacy)
- normalized cells (all `*|verde=1`): 14,15,16,17,20,21 → **sum=6**
- Hive was qty=1 / incomplete grade

**CLASSIFICATION:** `PHYSICAL_COUNT_REQUIRED`  
Reason: aggregate vs six positive cells conflict; revision=1 insufficient to prove which side is truth.

---

## B) Colar Veneziana Cruz 50cm

- id: `nathy-pratas-e-folheados-colar-veneziana-cruz-50cm`
- remote `quantidade=0`, cells `50cm|prata=1`, `estoquePorTamanho.50cm=1`
- `stockRevision=1`, `stockOperationId=b28ffd0d-1838-42a1-9d84-8b553aa6c421`
- `vendasCatalogoTotal=1` (suggests one catalog sale; cell may not have been cleared)

**CLASSIFICATION:** `MANUAL_REVIEW_REQUIRED`  
Candidate for later `SAFE_DATA_REPAIR` (zero cell to match qty=0) **only after** sale/consignment ledger proof — not in this execution.

---

## C) Piercing Argolinha Clara

- id: `nathy-pratas-e-folheados-piercing-argolinha-clara`
- remote `quantidade=0`, cells `10mm|prata=1`
- `stockRevision=1`, `stockOperationId=cb968c83-d606-4b93-9570-0e775e087fb8`
- `vendasCatalogoTotal=1`, `lastWriteOrigin=produto_form.save`

**CLASSIFICATION:** `MANUAL_REVIEW_REQUIRED`  
Same pattern as B — do not auto-zero without ledger.

---

## D) Pingente Rosto Filhos

- id: `nathy-pratas-e-folheados-pingente-rosto-filhos`
- remote `quantidade=4`
- cells: `menina|prata=4` + `menino|prata=2` → **sum=6**
- `stockRevision=1`, `stockOperationId=ece964c8-ea1a-4355-866b-2247cb4602aa`
- `stockKind` absent; `lastWriteOrigin=sync_queue.upsert_produto`

**CLASSIFICATION:** `PHYSICAL_COUNT_REQUIRED`  
Aggregate understates cells by 2; cannot safely choose qty=4 vs 6 without count.

---

## Summary

| Product | Remote qty | Norm cell sum | Class |
|---|---:|---:|---|
| Verde Glow | 5 | 6 | PHYSICAL_COUNT_REQUIRED |
| Veneziana Cruz 50cm | 0 | 1 | MANUAL_REVIEW_REQUIRED |
| Argolinha Clara | 0 | 1 | MANUAL_REVIEW_REQUIRED |
| Rosto Filhos | 4 | 6 | PHYSICAL_COUNT_REQUIRED |

`TRUE_REMOTE_INCONSISTENCY_COUNT=4`  
`PHYSICAL_COUNT_REQUIRED_COUNT=2`  
`DATA_REPAIR_REQUIRED=true` (future, after review — **not** executed now)
