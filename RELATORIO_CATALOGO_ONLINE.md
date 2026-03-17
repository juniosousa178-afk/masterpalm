# Relatório de Análise – Catálogo Online MasterPalm

## Problemas identificados e status

### Corrigidos

| # | Falha | Onde | Risco | Correção |
|---|-------|-----|-------|----------|
| 1 | **Null safety em prodSnap.data** | `public_catalog_screen.dart` – StreamBuilder de produtos | Crash se `hasData` true mas `data` null | Uso de `prodSnap.data != null ? prodSnap.data!.docs : []` |
| 2 | **Cupons sem validação de data** | Lista de cupons (`cfg['cupons']`) e `_aplicarCupom` | Cupons expirados aceitos | Checagem de `dataFim`, `validade`, `dataValidade` na montagem da lista e ao aplicar |
| 3 | **Total negativo** | Cálculo do total do checkout | Preço negativo em caso de desconto acima do subtotal | `.clamp(0.0, double.infinity)` no total |
| 4 | **Cupons sem valor mínimo** | `_aplicarCupom` | Desconto aplicado abaixo do valor mínimo | Validação de `valorMinimo` antes de aplicar |
| 5 | **Falta de sincronização cupons** | Config (`config/config`) vs collection (`cupons`) | Cupons de FretesCuponsScreenV2 não aparecem no catálogo | Fallback: carregar da collection quando `config.cupons` estiver vazio |
| 6 | **Cupom sem campos completos** | Objeto do cupom no config | Perda de regras (valor mínimo, validade) | Inclusão de `valorMinimo`, `dataFim`, `validade`, `dataValidade` no mapa do cupom |

### Documentados (sem mudança de código)

| # | Falha | Onde | Risco |
|---|-------|-----|-------|
| 7 | **Stream de produtos em permission-denied** | `_produtosStream` – `onError` sem emitir snapshot | Loading infinito se o usuário não tiver permissão. Exige `QuerySnapshot` vazio, que não é fácil de criar no SDK. |
| 8 | **Payments vazio** | `paymentsFromRodape` – se `rodape.payments` não for List | Checkout pode ficar sem opções de pagamento. Garantir que LojaConfig salve `rodape.payments` corretamente. |
| 9 | **Config vs draft_config** | Modo preview usa `draft_config` | Em preview, cupons/fretes vêm do rascunho; ao publicar, deve sincronizar para `config`. |

---

## Arquivos alterados

- **`lib/screens/public_catalog_screen.dart`**
  - Null safety em `prodSnap.data`
  - Validação de data de validade em cupons (na montagem e em `_aplicarCupom`)
  - Validação de valor mínimo em `_aplicarCupom`
  - Clamp no total do checkout
  - Fallback para carregar cupons da collection `cupons` quando `config.cupons` estiver vazio
  - Inclusão de `valorMinimo`, `dataFim`, `validade`, `dataValidade` no mapa do cupom

---

## Como testar

1. **Compilação:**
   ```powershell
   cd c:\Users\Pichau\apk_nathy\temp_naty
   flutter pub get
   flutter analyze
   ```

2. **Catálogo Web:**
   - Acesse o catálogo público (Web ou app).
   - Verifique produtos, carrinho e checkout.
   - Teste cupom aplicado e sem cupom.

3. **Cupons:**
   - Crie cupom em FretesCuponsScreenV2 com `dataFim` e `valorMinimo`.
   - Confirme que cupons da collection aparecem no catálogo quando `config.cupons` está vazio.
   - Tente aplicar cupom expirado → mensagem de erro.
   - Tente aplicar cupom abaixo do valor mínimo → mensagem de erro.

4. **Total:**
   - Aplique cupom com desconto maior que o subtotal → total deve ficar em 0, não negativo.

---

## Análise de Sincronização (Catálogo Online / Rascunho)

### Telas e fluxos mapeados

| Tela | Fonte de dados | Uso |
|------|----------------|-----|
| **public_catalog_screen** | Firestore `draft_produtos` / `produtos` | Catálogo público (preview=true → rascunho, preview=false → live) |
| **cadastro_catalogo_screen** | Hive `catalogo_$lojaId` | Cadastro de produtos no catálogo |
| **catalago_screen** | Hive `catalogo` (sem lojaId) | Tela antiga – possível inconsistência multi-loja |

### Serviços de sincronização

| Serviço | Função |
|---------|--------|
| **CatalogoSyncService** | Hive → Firestore (draft_produtos / produtos) |
| **CatalogPublishService** | Promove draft → live (produtos + config) |
| **ProdutoAutoSyncService** | Auto-sync ao alterar produtos (usa removeProdutoFromFirestore) |

### Fluxo de sync

- **produto_form_screen**: `upsertFromProduto` → draft + live
- **estoque_screen**: `removeBySlug` / `syncProduto` → draft + live
- **loja_config_screen**: `pushAllToLive` ao publicar
- **ProdutoAutoSyncService**: `removeProdutoFromFirestore` quando produto não deve existir no catálogo

### Bug corrigido (esta sessão)

| # | Falha | Onde | Correção |
|---|-------|------|----------|
| 10 | **DocId incorreto em removeProdutoFromFirestore** | `catalogo_sync_service.dart` | Usava `lojaId-slug` como docId, mas Firestore armazena apenas `slug`. Produtos removidos via ProdutoAutoSyncService nunca eram deletados. Corrigido para usar o mesmo docId de `syncProduto`. |

### Consistência docId

- **syncProduto** e **removeBySlug**: docId = `slug` (ou `slugify(nome)`)
- **removeProdutoFromFirestore** (antes): docId = `lojaId-slug` ❌
- **removeProdutoFromFirestore** (depois): docId = `slug` ✅

### Melhorias implementadas (sessão atual)

1. **public_catalog_screen**: Retry em erro de carregamento, pull-to-refresh, indicador offline, feedback de erro com botão "Tentar novamente".
2. **catalago_screen**: Multi-loja – usa `catalogo_$lojaId` e `store_id` (fallback `loja_id`).
3. **estoque_screen**: Feedback de sync – SnackBar quando removeBySlug falha.
4. **cadastro_catalogo_screen**: Validação de quantidade e preço (não negativos). **Sync com Firestore** – chama `CatalogoSyncService.upsertFromProduto` e `ProdutosFirestoreService.syncProduto` após salvar; produto criado com `publicadoNoCatalogo=true`, slug, imagens e lojaId para aparecer no catálogo público.
5. **loja_config_screen**: Indicador de progresso (LinearProgressIndicator) ao publicar.
