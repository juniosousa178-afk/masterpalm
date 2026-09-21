# NATHY — Variation hydration fix

`COMMIT=false` `PUSH=false` `DEPLOY=false` `PRODUCTION_DATA_REPAIR=false`  
`REMOTE_PRODUCT_WRITES=0` `REMOTE_STOCK_WRITES=0` `SALE_WRITES=0` `CONSIGNMENT_WRITES=0`

## Code changes (local only)

1. **`lib/core/produto_effective_stock.dart`**
   - `effectiveStockKindFromRemote` / `FromProduto`
   - `normalizeSemCorAliasCells` (sem-cor aliases do not double-count)
   - `applyAuthoritativeRemoteStockToProduto` (cache only; skips REAL pending)
   - `captureLocalStockSnapshot` (immutable diagnostic snapshot)
   - `saleOptionsFromNormalizedCells`

2. **`lib/services/venda_produto_stock_hydrate_service.dart`**
   - Sale-time RO read of `estoque_produtos` → apply to Hive product when no pending
   - `requiresVariationPicker` from effective kind + normalized cells

3. **`lib/screens/nova_venda_modal.dart`**
   - `_hydrateProdutoParaVenda` before picker / barcode / chip paths
   - Search dropdown always routes to `onProductNeedsVariation` (hydrate then decide)

4. **`lib/core/produto_sale_variation_picker.dart`**
   - Options from normalized canonical cells only (`qty > 0`)
   - `tamanhos[]` alone is **not** variation identity (`LEGACY_SIZE_METADATA_ONLY`)

5. **`lib/services/produtos_firestore_service.dart`**
   - When `preserveLocalEdits` but **no** pending stock: still apply remote variation metadata (`updateQuantity: false`)

## Rules enforced

- Remote stock metadata **>** Hive when no legitimate pending
- Legacy `stockKind=null` + canonical cells → `EFFECTIVE_STOCK_KIND=variation` (no remote write)
- Do not promote to variation from `tamanhos[]` alone

## Canaries covered in tests

- Anel Lacinho Encanto (stale simple → picker 15/22)
- sem-cor alias normalization
- Anel Ondinha cache stale qty 1→3 / options 14,18,21
- Pending safety (no overwrite)
