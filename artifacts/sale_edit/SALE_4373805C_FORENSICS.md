# Forense somente leitura — venda 4373805c (Mir Joias)

Sem PII. Nenhuma escrita em produção. Nenhum reparo.

| Campo | Valor |
|---|---|
| SALE_ID | `4373805c-4a50-488a-98ac-9a9112a879db` |
| STORE | `mirjoias` (NO_CONTROL / legacyCompat) |
| EDIT_OPERATION_BASE_ID | `editstock_4373805c-4a50-488a-98ac-9a9112a879db_d2bb677f80077766ae488a05602eec60dafe09d83e1b22c21ae06050dbb7892b` |
| SALE_HALF_EXISTS | true — `kind=sale`, `status=applied`, 2026-09-20T18:41:00Z, 1 item: `mirjoias-anel-solit-rio-cravejado-amtista-t-20-prata-925` qty 1 |
| RESTOCK_HALF_EXISTS | false (bloqueado: `restock` não é permitido em NO_CONTROL) |
| RESTOCK_HALF_PRODUCTS | desconhecidos — o id contém apenas o hash do delta |
| SALE_DOCUMENT_FINAL_STATE | 10 linhas, total 640,50, `updatedAt` 2026-09-20T21:31:22Z, **sem** linha "amtista" |
| EXPECTED_DELTA_FROM_SAVED_SALE (amtista) | 0 |
| ACTUAL_STOCK_DELTA (amtista) | −1 às 18:41Z (metade `sale` da edição dividida) |
| SUPERSEDED_BY | op `replace` `c42ce1e2…` em 2026-09-29T11:24Z (qty=1, rev 3) — reconciliação física posterior |
| Contexto anterior | 13 `restock` aplicados 13:39–14:01Z em 2026-09-20 (ver `artifacts/mirjoias_final_stock/MIRJOIAS_AN13PR_MANUAL_REVIEW.md`) |

## Conclusão

- HISTORICAL_PARTIAL_EDIT_PROVEN = **true**: a metade `_sale` de uma edição mista foi aplicada e a metade `_restock` nunca existiu; a venda salva não contém a linha debitada.
- Verdade física: **não estabelecível** a partir dos dados. O saldo do produto foi depois substituído por uma reconciliação física (`replace`, 2026-09-29), então qualquer correção agora sobrescreveria uma contagem física mais nova.
- HISTORICAL_REPAIR_PERFORMED = false. CURRENT_MIR_FAILED_EDIT_REPAIR_REQUIRED = false (a tentativa atual que falhou não gravou nada; ver diagnóstico anterior).
