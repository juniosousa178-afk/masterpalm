# Relatório de Análise – Tela Public Catalog e Ecossistema

**Escopo:** `PublicCatalogScreen`, sub-telas, widgets, serviços e arquivos ligados ao catálogo público.  
**Objetivo:** Listar e classificar erros (sem correção).  
**Classificação:** Crítico | Alto | Médio | Baixo | Silencioso.

---

## 1. Resumo da Estrutura Analisada

### 1.1 Tela principal
- **Arquivo:** `lib/screens/public_catalog_screen.dart` (~4900 linhas)
- **Roteamento:** `app_routes.dart`, `main.dart`, `catalog_web.dart`, `estoque_screen.dart`, `home_screen.dart`, `loja_config_screen.dart`, `home_intelligent_section.dart`

### 1.2 Sub-telas e páginas internas
- `CatalogDicasScreen` (`public_catalog/catalog_dicas_screen.dart`)
- Login/Cadastro cliente: `LoginScreenCliente`, `CadastroScreenCliente`, `PerfilClienteScreenNovo`
- Carrinho/Checkout: `CarrinhoSheetWeb` (bottom sheet)

### 1.3 Widgets do catálogo (`lib/screens/public_catalog/`)
- `catalog_banner_carousel.dart`, `catalog_config_loading_state.dart`, `catalog_config_error_state.dart`
- `catalog_empty_products_state.dart`, `catalog_error_loja_state.dart`, `catalog_loading_state.dart`
- `catalog_footer.dart`, `catalog_search_filters_bar.dart`, `catalog_products_grid_sliver.dart`
- `catalog_recent_section_sliver.dart`, `catalog_premium_section_sliver.dart`, `catalog_premium_categories_section.dart`
- `catalog_premium_cta_whatsapp.dart`, `catalog_skeleton_grid.dart`, `catalog_product_card.dart`
- `catalog_product_details_sheet.dart`, `catalog_product_selection_sheet.dart`, `catalog_combo_variation_sheet.dart`
- `catalog_gallery_view.dart`, `catalog_section_title.dart`, `catalog_image_placeholder.dart`
- `product_card.dart` (wrapper para `CatalogProductCard`), `carrinho_sheet_web.dart`

### 1.4 Serviços e helpers
- `catalog_cache_service.dart`, `catalog_cache_disk_store.dart`, `catalog_publish_service.dart`
- `catalogo_sync_service.dart`, `catalogo_config_service.dart`, `catalogo_venda_service.dart`
- `catalogo_venda_helpers.dart`, `catalogo_venda_item_resolver.dart`
- `catalog_recent_service.dart`, `catalog_share_service.dart`, `catalog_visitas_service.dart`
- `catalog_thumbnail_service.dart`, `store_resolver_facade.dart`, `store_resolver_service.dart`, `store_resolver_unified.dart`
- `cliente_auth_service.dart`, `pre_pedido_service.dart`, `mercadopago_service.dart`
- `carrinho_abandonado_service.dart`
- `public_catalog/catalog_config_service.dart`, `public_catalog/catalog_helpers.dart`, `public_catalog/catalog_theme_extension.dart`, `public_catalog/catalog_theme.dart`

### 1.5 Modelos e dados
- `produto_catalogo`, `catalogo_config`, `catalogo_config_firestore.dart`
- Uso de `Map<String, dynamic>` para produtos no catálogo (processados em `_processDocsToProducts`)

---

## 2. Erros Reportados pelo Linter / Analyzer

| # | Arquivo | Linha | Descrição | Classificação | Impacto |
|---|---------|--------|-----------|----------------|---------|
| 1 | `public_catalog_screen.dart` | 36 | **Target of URI doesn't exist:** `../widgets/pix_qr_dialog.dart`. O arquivo existe em `lib/widgets/pix_qr_dialog.dart`; o analyzer pode estar falhando por path ou cache. | **Médio** | Se o import realmente falhar em algum ambiente (ex.: build), a tela não compila: **checkout PIX não abre** (QR Code não é exibido). |
| 2 | `public_catalog_screen.dart` | 48 | **Target of URI doesn't exist:** `public_catalog/widgets/catalog_footer.dart`. O arquivo existe em `lib/screens/public_catalog/widgets/catalog_footer.dart`. | **Médio** | Se o import falhar, o build quebra e o **rodapé do catálogo não é renderizado** (erro de compilação no widget `CatalogFooter`). |
| 3 | `public_catalog_screen.dart` | 1721 | **The method 'showPixQrDialog' isn't defined for the type '_PublicCatalogScreenState'.** | **Crítico** | Consequência do erro 1: sem o import de `pix_qr_dialog.dart`, a função global `showPixQrDialog` não está no escopo. **Pagamento PIX no checkout não mostra o dialog do QR Code.** |
| 4 | `public_catalog_screen.dart` | 2315 | **The method 'showPixQrDialog' isn't defined for the type '_PublicCatalogScreenState'.** | **Crítico** | Mesmo que o erro 3: segunda chamada a `showPixQrDialog` (fluxo Mercado Pago / PIX). **Dialog PIX não abre nesse fluxo.** |
| 5 | `public_catalog_screen.dart` | 4668 | **The method 'CatalogFooter' isn't defined for the type '_PublicCatalogScreenState'.** | **Crítico** | Consequência do erro 2: sem o import do widget `CatalogFooter`, o rodapé é tratado como “método não definido”. **Rodapé do catálogo não compila/renderiza.** |

**Resumo linter:** 2 erros de URI (import) e 3 erros em cascata (método/widget não definido). Em ambiente onde o analyzer considera os URIs inválidos, **checkout PIX e rodapé ficam quebrados** até correção dos imports.

---

## 3. Erros de Lógica e Riscos (Análise Estática)

### 3.1 Getter `lojaId` que lança `StateError`

| # | Local | Descrição | Classificação | Impacto |
|---|--------|-----------|----------------|---------|
| 6 | `public_catalog_screen.dart` ~1105 | Getter `lojaId` lança `StateError('lojaId ainda não foi resolvido')` se `_resolvedLojaId` for null ou vazio. | **Médio** | O `build()` já faz guarda (`_loadingLojaId` / `_resolvedLojaId == null || isEmpty`) antes de usar `lojaId`, então hoje o getter não é chamado nesse estado. **Risco:** em refatorações, qualquer uso de `lojaId` fora dessa árvore (ex.: callback assíncrono antes da guarda) pode lançar e derrubar a tela. |

### 3.2 Uso de `lojaId` em streams e callbacks

| # | Local | Descrição | Classificação | Impacto |
|---|--------|-----------|----------------|---------|
| 7 | `public_catalog_screen.dart` ~2480, 2976–2977, 3005, 4004, etc. | Vários pontos usam o getter `lojaId` dentro do `StreamBuilder` / `RefreshIndicator` (após a guarda de build). | **Baixo** | Se a guarda do build for mantida, comportamento é correto. Se alguém alterar a ordem (ex.: usar `lojaId` antes da guarda ou em outro widget sem acesso ao state), **StateError** pode aparecer em runtime. |

### 3.3 Parsing e tipos (Firestore / Map)

| # | Local | Descrição | Classificação | Impacto |
|---|--------|-----------|----------------|---------|
| 8 | `_processDocsToProducts` (~101–400) | Try/catch por documento: falha em um produto só descarta esse item e segue (com log em debug). Campos como `estoque`, `preco`, `variacoes` têm vários fallbacks. | **Baixo** | Dados malformados ou inesperados no Firestore podem **ocultar produtos** sem feedback ao usuário (comportamento silencioso). |
| 9 | `catalog_config_service.dart` | Uso de `asMap`, `asDateTime` e parsing numérico em config (fretes, cupons, mídia). Campos ausentes ou tipos errados geram fallbacks (ex.: listas vazias, 0.0). | **Silencioso** | Config pode ficar **parcial ou padrão** sem mensagem de erro (ex.: fretes vazios, cupons ignorados, banner height padrão). |
| 10 | `CatalogFooter` – `links` | Widget espera `List<Map<String, String>>`. Na tela principal, `footerLinks` vem do config (Firestore). Se algum valor não for `String`, pode haver cast implícito ou erro em runtime dependendo do uso. | **Baixo/Silencioso** | Em dados bem formados, ok. Se o config tiver tipos diferentes (ex.: número em `url`), pode **quebrar em runtime** ou exibir valores estranhos. |

### 3.4 Assincronia e contexto

| # | Local | Descrição | Classificação | Impacto |
|---|--------|-----------|----------------|---------|
| 11 | `_resolveLojaId().catchError(...)` (~586–602) | Em erro não tratado, usa `mounted` e `context` no callback. Se o widget for desmontado antes do callback, `ScaffoldMessenger.of(context)` pode falhar. | **Médio** | Em navegação rápida (ex.: usuário sai da tela antes do resolve), **pode ocorrer exceção** ao tentar mostrar SnackBar. |
| 12 | Vários `if (mounted) setState(...)` após awaits | Uso correto de `mounted` antes de `setState` em vários pontos. Alguns callbacks (ex.: `_loadClienteAndFavoritos`, `_loadCarrinho`) usam `mounted` antes de acessar context. | **Baixo** | Risco residual em callbacks aninhados ou em terceiros que chamem métodos do state **após dispose**. |

### 3.5 Cache e streams

| # | Local | Descrição | Classificação | Impacto |
|---|--------|-----------|----------------|---------|
| 13 | `CatalogCacheService` | TTL de config (10 min) e produtos (5 min). Se o Firestore estiver lento ou indisponível, a UI continua com dados em cache mesmo após alterações na loja. | **Baixo** | Usuário pode ver **config ou produtos desatualizados** até expirar TTL ou refresh manual. Comportamento esperado, mas pode confundir em cenários de “atualizei e não mudou”. |
| 14 | `_getConfigStream` / `_getProdutosStream` | Cache de stream por chave (`lojaId_preview_refreshCounter`). Se `_resolvedLojaId` mudar (ex.: redirect), a chave muda e novos streams são criados; antigos podem ficar ativos até cancel. | **Baixo** | Em cenários de redirect ou troca de loja, **pode haver breve duplicidade de listeners** até o rebuild. |

### 3.6 Checkout e pagamento

| # | Local | Descrição | Classificação | Impacto |
|---|--------|-----------|----------------|---------|
| 15 | `CarrinhoSheetWeb` – `onCheckoutPix` | Callback PIX chama `showPixQrDialog` no `PublicCatalogScreen`. Se os erros 1/3/4 persistirem (import/método não definido), **PIX não funciona** em todo o fluxo do carrinho. | **Crítico** | Já coberto pelos itens 1, 3, 4: **pagamento PIX inoperante** até correção do import e uso de `showPixQrDialog`. |
| 16 | Pré-pedido e Mercado Pago | URLs de success/failure/pending e body das requisições usam `lojaId` (getter). Como só são chamados após config e produtos carregados, o getter está seguro no fluxo atual. | **Baixo** | Qualquer uso de `lojaId` em callback de rede **antes** da guarda do build seria risco; hoje não é o caso. |

### 3.7 Dicas e DicaItem

| # | Local | Descrição | Classificação | Impacto |
|---|--------|-----------|----------------|---------|
| 17 | `catalog_dicas_screen.dart` – `DicaItem.fromMap` | Usa `safeInt(m['ordem'], 0)` e `safeBool(m['ativo'], true)`. Em `safe_parse`, `safeInt` e `safeBool` têm segundo parâmetro opcional; assinatura está correta. | **Silencioso** | Dados inválidos viram valores padrão; **nenhum erro**, no máximo conteúdo estranho na UI. |

### 3.8 Serviços externos ao arquivo da tela

| # | Local | Descrição | Classificação | Impacto |
|---|--------|-----------|----------------|---------|
| 18 | `StoreResolverUnified` / `StoreResolverFacade` | Resolução de loja para catálogo e admin. Se retornar `success: false` ou timeout, a tela mostra `CatalogErrorLojaState` e SnackBar. | **Médio** | **Catálogo não abre** para loja inválida ou indisponível; mensagem depende de `result.errorMessage` e do tratamento de timeout. |
| 19 | `ClienteAuthService` (carrinho, favoritos, login) | Falhas são tratadas com SnackBar ou callbacks `onFalhaCarregamento`. Erros de rede ou permissão podem deixar carrinho/favoritos vazios ou desatualizados. | **Médio** | **Carrinho ou favoritos não carregam**; usuário vê mensagem ou estado vazio. |
| 20 | `CatalogoVendaService` / `PrePedidoService` / Mercado Pago | Erros em criar pedido ou preferência são tratados com `showErr` / SnackBar. Exceções não capturadas em algum branch podem propagar. | **Alto** | **Checkout pode falhar** sem mensagem clara ou derrubar o fluxo em cenários de exceção inesperada. |

---

## 4. Resumo por Classificação

- **Crítico:** 3 (itens 3, 4, 5 – todos ligados a imports: PIX e rodapé não definidos).
- **Alto:** 1 (item 20 – falhas não tratadas em checkout/serviços).
- **Médio:** 4 (itens 1, 2, 6, 11, 18, 19 – imports, getter que lança, uso de context após dispose, resolução de loja, auth/carrinho).
- **Baixo:** 6 (itens 7, 8, 10, 12, 13, 14, 16 – uso de `lojaId`, parsing, cache, callbacks).
- **Silencioso:** 3 (itens 9, 10, 17 – config/dados com fallback, links do footer, DicaItem).

---

## 5. Impacto no Funcionamento do Sistema

- **Compilação / build:** Se os URIs de `pix_qr_dialog` e `catalog_footer` forem considerados inválidos no ambiente (ex.: analyzer ou build CI), o projeto **não compila** ou a tela do catálogo quebra nos pontos que usam `showPixQrDialog` e `CatalogFooter`.
- **Checkout PIX:** Sem `showPixQrDialog` no escopo, o **pagamento PIX no catálogo não exibe o QR Code** (nem no fluxo direto nem no Mercado Pago).
- **Rodapé:** Sem o widget `CatalogFooter` no escopo, o **rodapé do catálogo não é construído** (erro de compilação ou widget indefinido).
- **Resolução de loja:** Falha ou timeout em `StoreResolverFacade` resulta em **tela de erro de loja** e catálogo não exibido.
- **Carrinho / favoritos:** Falhas em `ClienteAuthService` podem deixar **carrinho ou favoritos vazios** ou com mensagem de falha.
- **Produtos / config:** Dados Firestore malformados ou inesperados podem **ocultar produtos** ou usar config padrão de forma silenciosa.

---

## 6. Arquivos e Telas Ligados Diretamente (Referência)

- **Telas que abrem o catálogo:** `main.dart`, `app_routes.dart`, `catalog_web.dart`, `estoque_screen.dart`, `home_screen.dart`, `loja_config_screen.dart`, `home_intelligent_section.dart`.
- **Auth cliente (catálogo):** `login_screen_cliente.dart`, `cadastro_screen_cliente.dart`, `perfil_cliente_screen_novo.dart`, `redefinir_senha_cliente_loja_screen.dart`.
- **Serviços de catálogo/venda:** `catalogo_sync_service.dart`, `catalog_publish_service.dart`, `catalog_cache_service.dart`, `catalogo_venda_service.dart`, `catalogo_venda_item_resolver.dart`, `store_resolver_facade.dart`, `store_resolver_unified.dart`, `cliente_auth_service.dart`, `pre_pedido_service.dart`, `carrinho_abandonado_service.dart`.
- **Widgets compartilhados:** `pix_qr_dialog.dart`, `smart_image.dart`, `campanha_banner_widget.dart`, `roleta_web_widget_v3.dart`, `selecionar_cupom_modal.dart`, etc.

---

*Relatório apenas descritivo; nenhuma alteração foi feita no código.*

---

## Atualização pós-correção (correção cirúrgica)

- **Imports:** Mantidos como relativos corretos: `../widgets/pix_qr_dialog.dart` e `public_catalog/widgets/catalog_footer.dart`. Se o analyzer continuar reportando "Target of URI doesn't exist", é provável que seja problema de ambiente (workspace/raiz de análise ou cache). Recomenda-se: `flutter clean`, `flutter pub get`, reabrir o projeto pela raiz e, se necessário, usar imports `package:master_palm/...` após validar que o build resolve o package.
- **Defensivas aplicadas:** (1) `catchError` de `_resolveLojaId`: segundo `if (mounted)` antes de usar `context` no SnackBar; (2) `_snack`: guarda `if (!mounted) return` antes de usar `context`; (3) getter `lojaId`: comentário documentando uso apenas após a guarda do build.
