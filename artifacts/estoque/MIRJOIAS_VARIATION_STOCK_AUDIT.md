# MIRJOIAS — Variation Stock Audit (read-only)

STORE_ID=mirjoias  
FAST_TRACK_MODE=true  
COMMIT=false · PUSH=false · DEPLOY=false  

## Contadores

| Métrica | Valor |
|--------|------:|
| ACTIVE_PRODUCTS | 539 |
| VARIABLE_PRODUCTS | 61 |
| VARIATION_GREEN (A) | 54 |
| VARIATION_IDENTITIES_WITH_MISSING_QTY (B) | 7 |
| VARIATION_AGGREGATE_GT_0_CELLS_ZERO (C) | 0 |
| VARIATION_AGGREGATE_MISMATCH (E) | 0 |
| SALE_VARIATION_NO_OPTIONS | 7 |
| PHYSICAL_COUNT_REQUIRED | 7 |
| SAFE_AUTO_REPAIR | 0 |

## Classificação

```
{
  "I_SIMPLE_OK": 478,
  "A_VARIATION_GREEN": 54,
  "B_VARIATION_IDENTITIES_WITH_MISSING_QTY": 7
}
```

JSON completo: `artifacts/estoque/MIRJOIAS_VARIATION_STOCK_AUDIT.json`

## Root causes

- **ROOT_CAUSE_VARIATION_NOT_SHOWN_IN_SALE**: o seletor de venda só lista células com **qty > 0**. Produtos com identidades (P/M/G, cores, tamanhos) e todas as células em 0 ficam sem opções.
- **ROOT_CAUSE_VARIATION_QTY_MISSING**: legado com identidades preenchidas e qty zero; sem evidência inequívoca para auto-repair → contagem física.

## Produto da evidência (imagens)

O anel **"Anel Coração Vazado Delica..."** com tamanhos 13–19 **não** está em MIRJOIAS (0 hits nos 539 ativos). O mesmo padrão (tamanhos cadastrados, qty vazia) foi identificado historicamente em **NATHY**.

Para MIRJOIAS, os 7 produtos classe B estão em `MIRJOIAS_VARIATION_PHYSICAL_COUNT_REQUIRED.md`.

## Política

- Não distribuir aggregate entre tamanhos.
- Não inventar qty.
- BATCH_A_SAFE_AUTO_REPAIR = 0
- BATCH_B_PHYSICAL_COUNT_REQUIRED = 7
