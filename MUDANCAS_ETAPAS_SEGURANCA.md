# Melhorias técnicas e de segurança — arquivos alterados e resumo

**Validação:** `flutter analyze` (64 infos, 0 erros), `flutter build web` ✓, `flutter build apk --debug` ✓.

---

## ETAPA 0 — Baseline (sem alteração de código)

- **flutter analyze:** 66 issues (info), 0 erros.
- **flutter build web:** ✓ Built build\web
- **flutter build apk --debug:** ✓ Built app-debug.apk

---

## ETAPA 1 — Keystore (senha removida do código)

### Arquivos criados
- **android/key.properties.example** — Template com `storePassword`, `keyPassword`, `keyAlias`, `storeFile=release.keystore`. O desenvolvedor copia para `key.properties` (já ignorado pelo .gitignore) e preenche as senhas.

### Arquivos alterados
- **android/app/build.gradle.kts**
  - Removida a variável `bundledKeystore`.
  - Comentário atualizado: assinatura release só com `key.properties`.
  - Em `signingConfigs.create("release")`: removido o bloco `else if (bundledKeystore.exists())` que definia `keyPassword`, `storePassword`, `keyAlias`, `storeFile` com valores fixos (senha hardcoded).
  - Em `buildTypes.release.signingConfig`: uso de release apenas quando `keystorePropertiesFile.exists()`; caso contrário, usa `debug` (sem senha no código).

### O que NÃO mudou
- `applicationId`, `versionCode`, `versionName`, `minSdk`, `targetSdk`, tarefas Gradle, ProGuard.
- **android/.gitignore** já continha `key.properties` e `**/*.keystore` — nenhuma alteração.

---

## ETAPA 2 — Logger (só em debug)

### Arquivos criados
- **lib/core/logger.dart** — Funções `logD`, `logI`, `logW`, `logE`; todas só imprimem quando `kDebugMode == true`. Sem dependências externas.

### Arquivos alterados
- **lib/screens/home_screen.dart** — Import `../core/logger.dart`; todas as chamadas `debugPrint(` trocadas por `logD(`.
- **lib/screens/public_catalog_screen.dart** — Import `../core/logger.dart`; todas as chamadas `debugPrint(` trocadas por `logD(`.
- **lib/screens/loja_config_screen.dart** — Import `../core/logger.dart`; todas as chamadas `debugPrint(` trocadas por `logD(`.
- **lib/screens/config_pagamentos_simples_screen.dart** — Nenhuma troca (não havia debugPrint/print); import adicionado e depois removido para evitar unused_import.

---

## ETAPA 3 — Safe cast (evitar crash em leituras Firestore)

### Arquivos alterados
- **lib/core/safe_cast.dart**
  - Novos helpers: `safeString`, `safeInt`, `safeDouble`, `safeBool`, `safeMap`, `safeList<T>` (com fallbacks).
  - Substituição de `debugPrint` por `logW(..., tag: 'SAFE_CAST')` e remoção do import de `foundation` (apenas `logger.dart`).
- **lib/screens/public_catalog/widgets/carrinho_sheet_web.dart**
  - `emb['tamanho'] as int` → `safeInt(emb['tamanho'])`.
  - `(embalagemMaior?['peso'] as num?)?.toDouble() ?? 50.0` (e altura, largura, comprimento) → `safeDouble(embalagemMaior?['peso'], fallback: 50.0)` etc.

### O que NÃO mudou
- Estrutura de dados, paths Firestore, nomes de campos, queries, streams. Apenas leituras pontuais protegidas com fallback.

---

## ETAPA 4 — Extração de widgets (apenas UI, sem mudar lógica)

### Arquivos criados
- **lib/screens/home/widgets/web_landing_plan_card.dart** — Widget `WebLandingPlanCard` com os mesmos parâmetros que `_buildWebLandingPlanCard` (incluindo `cardColor`, `surfaceColor`). Mesmo layout, cores, textos e comportamento.

### Arquivos alterados
- **lib/screens/home_screen.dart** — Import `home/widgets/web_landing_plan_card.dart`; `_buildWebLandingPlanCard` passou a retornar `WebLandingPlanCard(...)` com os mesmos argumentos e `cardColor: _cardColor`, `surfaceColor: _surfaceColor`. Nenhuma alteração de rota, estado ou lógica.

### O que NÃO mudou
- **public_catalog_screen.dart** — Nenhuma extração (já possui widgets em `public_catalog/widgets/`). Evitou-se alteração em massa no arquivo de ~4500 linhas.
- Rotas, URLs, parâmetros de navegação, state, Firestore ou streams.

---

## ETAPA 5 — Ignores perigosos (context após async)

### Arquivos alterados
- **lib/screens/clientes_screen.dart** — Após `await guard.canAddCliente(lojaId)` inserido `if (!mounted) return;` antes de usar `ScaffoldMessenger.of(context)`. Após `ClientesFirestoreService.syncCliente(...)` inserido `if (!mounted) return;` antes de limpar controllers e mostrar SnackBar.

### O que NÃO mudou
- Nenhum `// ignore` removido em massa. Outros avisos `use_build_context_synchronously` em outros arquivos não foram alterados para manter o escopo pequeno e reversível.

---

## ETAPA A — Extração de widgets base (public_catalog_screen.dart)

### Objetivo
Reduzir tamanho do arquivo extraindo widgets de loading/empty/skeleton para arquivos separados. Apenas UI, sem alterar Firestore, rotas, streams ou lógica.

### Arquivos criados
- **lib/screens/public_catalog/widgets/catalog_loading_state.dart** — `CatalogLoadingState(themeData)` — UI de carregamento inicial do catálogo (lojaId).
- **lib/screens/public_catalog/widgets/catalog_error_loja_state.dart** — `CatalogErrorLojaState(themeData)` — UI quando a loja não pôde ser carregada.
- **lib/screens/public_catalog/widgets/catalog_config_loading_state.dart** — `CatalogConfigLoadingState` — Loading enquanto aguarda config do StreamBuilder.
- **lib/screens/public_catalog/widgets/catalog_config_error_state.dart** — `CatalogConfigErrorState` — Erro quando config da loja não foi encontrada.
- **lib/screens/public_catalog/widgets/catalog_empty_products_state.dart** — `CatalogEmptyProductsState` — Sliver exibido quando não há produtos.
- **lib/screens/public_catalog/widgets/catalog_skeleton_grid.dart** — `CatalogSkeletonGrid` — Sliver skeleton durante loading da lista de produtos.

### Arquivos alterados
- **lib/screens/public_catalog_screen.dart**
  - Imports adicionados para os novos widgets.
  - `if (_loadingLojaId)` → `return CatalogLoadingState(themeData: themeData)`.
  - `if (_resolvedLojaId == null ...)` → `return CatalogErrorLojaState(themeData: themeData)`.
  - `ConnectionState.waiting` do config → `return const CatalogConfigLoadingState()`.
  - `!cfgSnap.hasData` → `return const CatalogConfigErrorState()`.
  - `_buildSkeletonGrid()` → `const CatalogSkeletonGrid()` (método removido).
  - `SliverFillRemaining(... 'Nenhum produto disponível.')` → `const CatalogEmptyProductsState()`.

### O que NÃO mudou
- Rotas, URLs, queries Firestore, streams, paginação, filtros, modelos, campos do banco, textos, layout, paddings, tamanhos, cores ou ordem de execução.
- Header/AppBar do catálogo **não** foi extraído nesta etapa (complexidade alta, muitos callbacks).

### Validação Etapa A
- **dart analyze:** 17 issues (info), 0 erros nos arquivos alterados.
- **flutter build web:** ✓ Built build\web
- **flutter build apk --debug:** ✓ Built build\app\outputs\flutter-apk\app-debug.apk

---

## ETAPA B — Barra de busca e filtros (UI ONLY)

### Objetivo
Extrair barra de busca, chips de categoria/subcategoria, ordenação, filtros e paginação para widget(s) externos. Apenas UI, sem alterar Firestore, rotas, lógica de filtros ou paginação.

### Arquivos criados
- **lib/screens/public_catalog/widgets/catalog_search_filters_bar.dart**
  - `CatalogSearchBar` — TextField de busca com controller, cores e callbacks (onChanged, onClear).
  - `CatalogCategorySubcategoryFilters` — Chips de categoria + subcategoria (Todos, categorias, subcategorias).
  - `CatalogSortFiltersSection` — Chips de ordenação (Nome, Novidade, Menor/Maior preço) + Em estoque + Preço + paginação (kIsWeb).
  - `CatalogPaginacaoRow` — Linha Anterior | Página X de Y | Próxima.

### Arquivos alterados
- **lib/screens/public_catalog_screen.dart**
  - Import `catalog_search_filters_bar.dart`.
  - Bloco da barra de pesquisa (TextField + ValueListenableBuilder) → `CatalogSearchBar(...)` com controller, cores, onChanged, onClear.
  - Bloco de categorias/subcategorias (FilterChip, ChoiceChip, ListView.builder, Builder) → `CatalogCategorySubcategoryFilters(...)` com callbacks onCategorySelectedNull, onCategorySelected, onSubcategorySelectedNull, onSubcategorySelected.
  - Bloco de ordenação/filtros/paginação (SliverToBoxAdapter com _buildSortChip, _buildFilterEmEstoqueChip, _buildFilterPrecoChip, _buildPaginacaoRow) → `CatalogSortFiltersSection(...)` com callbacks onSortChanged, onFilterEmEstoqueToggled, onFilterPrecoTap, onPageChanged.
  - Segundo uso de paginação (web layout) → `CatalogPaginacaoRow(...)` com onPagePrev/onPageNext.
  - Removidos: `_buildSortChip`, `_buildFilterEmEstoqueChip`, `_buildFilterPrecoChip`, `_buildPaginacaoRow`.
  - Mantido: `_mostrarDialogoFiltroPreco` (chamado via callback onFilterPrecoTap).

### O que NÃO mudou
- Firestore (queries, streams, paths), paginação (_currentPageNotifier), filtros (_ordenacaoProdutos, _apenasEmEstoque, _precoMin, _precoMax, _selectedCategory, _selectedSubcategory), rotas, URLs, layout, cores, textos, paddings, tamanhos ou ordem de execução.

### Validação Etapa B
- **dart analyze:** 7 issues (info), 0 erros nos arquivos alterados.
- **flutter build web:** ✓ Built build\web
- **flutter build apk --debug:** ✓ Built build\app\outputs\flutter-apk\app-debug.apk

---

## ETAPA C — ProductCard (UI ONLY)

### Objetivo
Extrair o widget repetido do item de produto (card do grid/list) para arquivo separado. O mapeamento Map→CatalogProductCard fica centralizado em PublicCatalogProductCard, reduzindo código duplicado.

### Arquivos criados
- **lib/screens/public_catalog/widgets/product_card.dart**
  - `PublicCatalogProductCard` — StatelessWidget que recebe `Map<String, dynamic> produto`, `lojaId` e callbacks/flags; internamente mapeia para `CatalogProductCard` (já existente em catalog_product_card.dart).
  - Helper `_mapToMapStringInt` (mesmo logic do removido em public_catalog_screen.dart).

### Arquivos alterados
- **lib/screens/public_catalog_screen.dart**
  - Import `product_card.dart` adicionado; import `catalog_product_card.dart` removido (agora usado apenas via product_card.dart).
  - Em `_buildRecentSection` itemBuilder: bloco inline `CatalogProductCard` com ~50 parâmetros → `PublicCatalogProductCard(produto: p, lojaId, callbacks...)`.
  - Em SliverChildBuilderDelegate (grid): bloco inline `CatalogProductCard` com ~50 parâmetros → `PublicCatalogProductCard(produto: p, lojaId, callbacks..., imageCacheWidth: 360, imageCacheHeight: 480)`.
  - Removida função `_mapToMapStringInt` (agora em product_card.dart).

### Funções removidas e motivo
- **`_mapToMapStringInt`** — Removida porque não havia mais uso em public_catalog_screen.dart; a lógica foi duplicada em product_card.dart para manter o widget autossuficiente.

### O que NÃO mudou
- Firestore, streams, queries, paginação, rotas, URLs, lógica de dados.
- Layout, paddings, margens, borderRadius, shadows, textos, cores, fit/crop da imagem.
- Hierarquia (SizedBox>Padding>Card no recent; RepaintBoundary>Card no grid).
- Callbacks (onAdd, onProductViewed, onToggleFavorito, onAbrirCarrinho).
- CatalogProductCard continua em catalog_product_card.dart; PublicCatalogProductCard é wrapper.

### Validação Etapa C
- **dart analyze:** 7 issues (info), 0 erros nos arquivos alterados.
- **flutter build web:** ✓ Built build\web
- **flutter build apk --debug:** ✓ Built build\app\outputs\flutter-apk\app-debug.apk

---

## ETAPA D — Grid/List (Slivers) — UI ONLY

### Objetivo
Extrair o bloco do SliverGrid principal e da seção "Vistos recentemente" para widgets separados. Slivers mantidos (SliverPadding + SliverGrid + SliverChildBuilderDelegate; SliverToBoxAdapter). Paginação, scroll listener, streams e lista (listaPaginated) continuam no public_catalog_screen.dart.

### Arquivos criados
- **lib/screens/public_catalog/widgets/catalog_products_grid_sliver.dart**
  - Função `buildCatalogProductsGridSliver(...)` — retorna `SliverPadding` > `SliverGrid` (SliverGridDelegateWithMaxCrossAxisExtent 240, aspectRatio 0.38, spacing 16) > `SliverChildBuilderDelegate` com `RepaintBoundary` > `PublicCatalogProductCard`. Recebe `products`, `lojaId`, callbacks, flags e cores por parâmetro.
- **lib/screens/public_catalog/widgets/catalog_recent_section_sliver.dart**
  - Função `buildCatalogRecentSectionSliver(...)` — retorna `SliverToBoxAdapter` com Column (título "Vistos recentemente" + ListView horizontal de cards). Recebe `recentProducts` (lista já calculada pelo chamador), `lojaId`, callbacks e flags. Algoritmo de recentes (_recentIds, prodMap, take(8)) permanece no chamador.

### Arquivos alterados
- **lib/screens/public_catalog_screen.dart**
  - Imports: `catalog_products_grid_sliver.dart`, `catalog_recent_section_sliver.dart`; removido `product_card.dart` (usado apenas nos slivers).
  - `if (_recentIds.isNotEmpty) _buildRecentSection(...)` substituído por: cálculo de `recentProducts` inline (prodMap + _recentIds.where/take(8)) e `buildCatalogRecentSectionSliver(recentProducts: ..., ...)`.
  - Bloco `SliverPadding` + `SliverGrid` + `SliverChildBuilderDelegate` substituído por `buildCatalogProductsGridSliver(products: listaPaginated, ...)`.
  - Removido método `_buildRecentSection` (lógica de lista recente passou para inline no ponto de chamada; UI para buildCatalogRecentSectionSliver).

### Funções removidas e motivo
- **`_buildRecentSection`** — Removida; a construção da lista de recentes (prodMap, _recentIds, take(8)) foi mantida no chamador em linha; a UI da seção foi extraída para `buildCatalogRecentSectionSliver`.

### O que NÃO mudou
- Firestore, streams, queries, paths, paginação (_currentPageNotifier), scroll listener.
- Rotas, URLs.
- Layout: maxCrossAxisExtent 240, childAspectRatio 0.38, spacings 16, padding 12,0,12,24, RepaintBoundary, addAutomaticKeepAlives/addRepaintBoundaries.
- Ordem dos slivers e itemBuilder (continua usando PublicCatalogProductCard).
- Algoritmo de “recentes” (continua no screen com prodMap + _recentIds).

### Validação Etapa D
- **dart analyze:** 7 issues (info), 0 erros nos arquivos alterados.
- **flutter build web:** ✓ Built build\web
- **flutter build apk --debug:** ✓ Built build\app\outputs\flutter-apk\app-debug.apk

---

## ETAPA E — Dispose/Cancel (baixo risco)

### Objetivo
Garantir que todos os recursos criados no State sejam finalizados no `dispose()`, sem mover criação de listeners nem alterar lógica.

### Verificação em public_catalog_screen.dart
- **TextEditingController:** `_searchController` — já disposto em `dispose()`.
- **ScrollController:** `_catalogScrollController` — `removeListener(_onCatalogScroll)` + `dispose()` já presentes.
- **Timer:** `_searchDebounce` — `_searchDebounce?.cancel()` já em `dispose()` e antes de novo timer.
- **StreamSubscription:** `_connectivitySubscription` — `_connectivitySubscription?.cancel()` já em `dispose()`.
- **ValueNotifier:** `_scrollOffsetNotifier`, `_searchNotifier`, `_currentPageNotifier` — `removeListener` (onde aplicável) e `dispose()` já presentes.

### Resultado
Nenhuma alteração de código necessária: o `dispose()` já realizava a limpeza de todos os controllers, notifiers, timer e subscription. Nenhuma duplicação de dispose/cancel foi introduzida.

### O que NÃO mudou
- Firestore, streams, queries, paginação, rotas, layout, comportamento.

---

## ETAPA 6 — Safe_cast em leituras críticas (baixo risco)

### Objetivo
Reduzir risco de crash por casts diretos em dados vindos de Firestore/JSON, sem alterar nomes de campos, estrutura ou formatação.

### Arquivos alterados
- **lib/screens/public_catalog_screen.dart**
  - Carrinho/subtotal: `(e['preco'] as num?)?.toDouble() ?? 0.0` → `safeDouble(e['preco'])`; `(e['quantidade'] as int?) ?? 1` → `safeInt(e['quantidade'], 1)`.
  - Frete/entrega: `(entrega['valor'] as num?)?.toDouble()` → `safeDouble(entrega['valor'])`.
  - Parcelas: `(e['maxParcelasSemJuros'] as num?)?.toInt() ?? 12` → `safeInt(e['maxParcelasSemJuros'], 12)`.
  - Badge carrinho: `(e['quantidade'] as int? ?? 0)` → `safeInt(e['quantidade'])`.
  - Menu (drawer): `(menuMap['categorias'] ?? true) as bool` (e demais) → `safeBool(menuMap['categorias'], true)` (e equivalentes para entrar, contato, sac, quemSomos).
  - Cupons (config): `(d['valor'] as num?)?.toDouble() ?? 0.0` → `safeDouble(d['valor'])`; `valorMinimo` → `d['valorMinimo'] == null ? null : safeDouble(d['valorMinimo'])`.
  - Config MP: `configDoc.data()!` → `asMapDeep(configDoc.data() ?? {})`.
  - Layout config: `(cfg['cardShowShadow'] as bool?) ?? true` → `safeBool(cfg['cardShowShadow'], true)`; `(cfg['cardBorderRadius'] as num?)?.toDouble() ?? 18.0` → `safeDouble(cfg['cardBorderRadius'], 18.0)`.
  - Filtro produtos: `(p['quantidade'] as int?) ?? 0` → `safeInt(p['quantidade'])`.
  - Ordenação novidade: `a['dataCriacao'] as DateTime?` / `b['dataCriacao'] as DateTime?` → `asDateTime(a['dataCriacao'])` / `asDateTime(b['dataCriacao'])`.
  - Recent section: `p['id'] as String` (chave do map) → `safeStr(p['id'])`.
  - Publicar catálogo: `draftCfgSnap.data()!` / `draftPaySnap.data()!` → `draftCfgSnap.data() ?? {}` / `draftPaySnap.data() ?? {}` (com `asMapDeep` já aplicado).

### O que NÃO mudou
- Nomes de campos, estrutura de Maps, formatação de preço, Firestore, streams, queries, paginação, rotas, layout visível.
- `lib/screens/public_catalog/widgets/carrinho_sheet_web.dart` já tinha safe_cast em pontos (Etapa 3); demais casts diretos podem ser tratados em rodada futura se desejado.

### Validação Etapa E + 6
- **dart analyze:** 7 issues (info), 0 erros novos.
- **flutter build web:** ✓ Built build\web
- **flutter build apk --debug:** ✓ Built build\app\outputs\flutter-apk\app-debug.apk

---

## ETAPA 7 — Remover riscos de BuildContext após async (baixo risco)

### Objetivo
Inserir guardas `mounted` / `context.mounted` após `await` e antes de uso de `context`, sem alterar Firestore, rotas, layout ou UX.

### Arquivos alterados

**lib/screens/public_catalog_screen.dart**
- Após `await CatalogoVendaService.registrarVendaCatalogo` (catch): `if (!ctx.mounted) return;` antes de `showErr`.
- Após `await _launchPaymentUrl(uri)` (dois trechos): `if (!mounted) return;` antes de `ScaffoldMessenger` e `showErr`.
- Após `_saveCarrinho()` no bloco QR Code: `if (!mounted) return;` antes de `ScaffoldMessenger`.
- Bloco PIX: `if (!ctx.mounted) return;` antes de usar `Navigator.of(ctx).context`; 1 ignore mantido onde o analisador não reconhece que `ctx.mounted` protege o uso.

**lib/screens/public_catalog/widgets/carrinho_sheet_web.dart**
- Após `await _recalcularFreteSelecionado()`: `if (!context.mounted) return;` antes de `Theme.of(context)` e `showModalBottomSheet`.
- `onTap` do frete: `if (!ctx.mounted) return;` antes de `Navigator.of(ctx).pop()`.
- Após `await mostrarModalSelecionarCupom()`: `if (!mounted) return;` e `if (!context.mounted) return;` antes de passar `context`.
- Três trechos após `await ClienteAuthService.getClienteLogado()` antes de `showDialog`: `if (!mounted) return;` e `if (!context.mounted) return;`.

### Pontos corrigidos
- **public_catalog_screen.dart:** 5 pontos com guardas `mounted`/`ctx.mounted`.
- **carrinho_sheet_web.dart:** 6 pontos com guardas `mounted`/`context.mounted`/`ctx.mounted`.
- **Total:** 11 pontos com guardas; 1 ignore mantido (caso em que `ctx.mounted` já protege, mas o analisador não reconhece).

### O que NÃO mudou
- Firestore, streams, queries, paginação, rotas, URLs.
- Layout, UX, comportamento visível.
- Nenhuma dependência nova.
- Sem reestruturação de funções grandes.

### Validação Etapa 7
- **dart analyze:** 0 erros novos.
- **flutter build web:** ✓ Sucesso.
- **flutter build apk --debug:** ✓ Sucesso.
- **Garantia:** Sem alteração de Firestore, rotas ou layout.

---

## ETAPA 8 — Padronizar logs com lib/core/logger.dart

### Objetivo
Substituir `print`/`debugPrint` por `logD`/`logW`/`logE` nos arquivos definidos, mantendo as mensagens idênticas. Em release não imprime nada (kDebugMode).

### Arquivos alterados

**lib/screens/public_catalog_screen.dart** — já usa `logD` (Etapa 2). Nenhuma alteração.

**lib/screens/public_catalog/widgets/carrinho_sheet_web.dart**
- Import de `logger.dart` adicionado.
- ~58 substituições: `debugPrint` → `logD` (logs comuns).
- 5 warnings: `logD` → `logW` (mensagens com ⚠️ ou ATENÇÃO).
- 6 blocos catch: `logD` → `logE(..., error: e, st: st)`.
- Total aproximado: 69 pontos ajustados.

**lib/screens/home_screen.dart** — já usa `logD` (Etapa 2). Nenhuma alteração.

**lib/screens/loja_config_screen.dart** — já usa `logD` (Etapa 2). Nenhuma alteração.

### Exemplos de substituições

| Antes | Depois |
|-------|--------|
| `debugPrint('🛒 [CARRINHO] initState - Fretes recebidos: ${widget.fretes.length}')` | `logD('🛒 [CARRINHO] initState - Fretes recebidos: ${widget.fretes.length}')` |
| `debugPrint('⚠️ Nenhuma campanha ativa encontrada')` | `logW('⚠️ Nenhuma campanha ativa encontrada')` |
| `} catch (e) { debugPrint('❌ Erro ao preencher dados do cliente: $e');` | `} catch (e, st) { logE('❌ Erro ao preencher dados do cliente: $e', error: e, st: st);` |

### O que NÃO mudou
- Firestore, streams, queries, paginação, rotas, URLs.
- Layout, UX, lógica de negócio.
- Mensagens dos logs (idênticas).
- Nenhuma dependência nova.

### Validação Etapa 8
- **dart analyze:** 0 erros novos.
- **flutter build web:** ✓ Sucesso.
- **flutter build apk --debug:** ✓ Sucesso.
- **Garantia:** Sem alteração de Firestore, rotas ou layout.

---

## ETAPA 10 — Padronizar debugPrint em lib/ para logger (Lote 3: services)

### Objetivo
Substituir `debugPrint` por `logD`/`logW`/`logE` em **lib/services/** e **lib/core/** (exceto logger.dart), mantendo mensagens idênticas. Em release não imprime nada (kDebugMode).

### Escopo
- **Lote 1** (lib/screens/public_catalog/**): já convertido na Etapa 8. Nenhuma alteração.
- **Lote 2** (home_screen, loja_config_screen): já usam logD (Etapa 2). Nenhuma alteração.
- **Lote 3** (lib/services/**): ~170 substituições em 11 arquivos.

### Arquivos alterados (Lote 3)

| Arquivo | logD | logW | logE |
|---------|------|------|------|
| cliente_auth_service.dart | 6 | 6 | 9 |
| produtos_firestore_service.dart | 18 | 1 | 9 |
| fornecedores_firestore_service.dart | 11 | 0 | 9 |
| clientes_firestore_service.dart | 18 | 0 | 10 |
| vendas_firestore_service.dart | 8 | 0 | 8 |
| catalog_cache_service.dart | 4 | 6 | 0 |
| full_sync_service.dart | 11 | 4 | 3 |
| store_resolver_unified.dart | 12 | 8 | 0 |
| notificacao_vendas_service.dart | 2 | 7 | 3 |
| pre_pedido_service.dart | 15 | 8 | 12 |
| **Total aproximado** | **~105** | **~40** | **~63** |

- Removido import não usado `package:flutter/foundation.dart` dos arquivos que deixaram de usar `debugPrint`.

### Exemplos de substituições

| Antes | Depois |
|-------|--------|
| `debugPrint('✅ [PRODUTOS-SYNC] Produto ${produto.nome} sincronizado')` | `logD('✅ [PRODUTOS-SYNC] Produto ${produto.nome} sincronizado')` |
| `debugPrint('⚠️ [CACHE] Refresh config: $e')` | `logW('⚠️ [CACHE] Refresh config: $e')` |
| `} catch (e) { debugPrint('❌ Erro ao sincronizar produto: $e');` | `} catch (e, st) { logE('❌ Erro ao sincronizar produto: $e', error: e, st: st);` |

### O que NÃO mudou
- Firestore, streams, queries, paginação, rotas, URLs.
- Layout, UX, lógica de negócio.
- Mensagens dos logs (idênticas).
- Nenhuma dependência nova.

### Validação Etapa 10
- **dart analyze:** 0 erros, 0 warnings novos.
- **flutter build web:** ✓ Sucesso.
- **flutter build apk --debug:** ✓ Sucesso.
- **Garantia:** Sem alteração de Firestore, rotas ou layout.

---

## ETAPA 11 — Padronizar debugPrint remanescentes em lib/ (exceto lib/services/**)

### Objetivo
Padronizar todos os `debugPrint` restantes em `lib/` (exceto `lib/services/**`, tratado em parte na Etapa 10) para `logD`/`logW`/`logE`.

### Escopo
- **lib/services/** — excluído (Etapa 10 tratou 11 arquivos; permanecem com debugPrint: cupom_desconto_service, canais_service, limits_guard, campaign_engine_service, catalogo_venda_service, globo_sorte_service, remote_config_service, sync_queue_service, store_resolver_service — possíveis Etapas futuras).
- **lib/screens/**, **lib/widgets/**, **lib/utils/**, **lib/core/**, **lib/main.dart**, **lib/debug/** — tratados na Etapa 11.

### Lotes executados

**Lote A (router/navegação)**
- **lib/screens/app_start_router.dart** — import `logger.dart`, `debugPrint` → `logD`/`logW`/`logE`, blocos catch com `st`.
- **lib/app_routes.dart** — import `logger.dart`, 1 `debugPrint` → `logD`.

**Lote B (widgets)**
- **lib/widgets/roleta_web_widget_v3.dart** — import `logger.dart`, `debugPrint` → `logD`/`logW`/`logE`, blocos catch com `st`.
- **lib/widgets/campanha_banner_widget.dart** — idem.

**Lote C (screens)**
- **lib/screens/clientes_screen.dart**, **fornecedor_screen.dart**, **vendas_screen.dart**, **pre_pedidos_screen.dart**, **estoque_screen.dart**, **nova_venda_modal.dart**, **globo_sorteio_screen.dart**, **estoque_screen_v2.dart** — import `logger.dart`, `debugPrint` → `logD`/`logW`/`logE`, blocos catch com `logE(..., error: e, st: st)`.

**Lote D (utils/core/main/debug)**
- **lib/debug/global_error_hook.dart** — `debugPrint` → `logD`/`logE`.
- **lib/main.dart** — import ajustado, `debugPrint` → `logD`/`logW`/`logE` (função `_debugPrintAppCheckDiagnostics` já usa `logD`).
- **lib/utils/store_access_guard.dart** — import `logger.dart`, `debugPrint` → `logD`.

### Ajuste adicional
- **lib/screens/nova_venda_modal.dart** — bloco catch em `_registrarNumeroSorte` (linha ~643): `catch (e)` → `catch (e, st)` e adicionado `logE('❌ [VENDA] Erro ao registrar número do sorteio: $e', error: e, st: st)`.

### Exemplos de substituições

| Antes | Depois |
|-------|--------|
| `debugPrint('⚠️ [ROUTER] Erro ao resolver loja: $e')` | `logW('⚠️ [ROUTER] Erro ao resolver loja: $e')` |
| `} catch (e) { debugPrint('❌ Erro: $e');` | `} catch (e, st) { logE('❌ Erro: $e', error: e, st: st);` |
| `debugPrint('✅ [STORE-GUARD] Acesso ok')` | `logD('✅ [STORE-GUARD] Acesso ok')` |

### debugPrint restantes em lib/ (fora do escopo Etapa 11)
- **lib/services/** — os 9 arquivos listados foram tratados na Etapa 11.1. Demais services (~60+ arquivos) ainda contêm debugPrint.
- **lib/utils/store_access_guard.dart** — comentário de documentação apenas.
- **lib/main.dart** — `_debugPrintAppCheckDiagnostics` é nome de função; corpo já usa `logD`.

### O que NÃO mudou
- Firestore, streams, queries, paginação, rotas, URLs.
- Layout, UX, lógica de negócio.
- Nenhuma dependência nova.

### Validação Etapa 11
- **dart analyze:** 0 erros, 0 warnings novos.
- **flutter build web:** ✓ Sucesso.
- **flutter build apk --debug:** ✓ Sucesso.
- **Garantia:** Sem alteração de Firestore, rotas ou layout.

---

## ETAPA 11.1 — Padronizar debugPrint nos services listados (Etapa 11)

### Objetivo
Padronizar `debugPrint` por `logD`/`logW`/`logE` nos 9 arquivos de services citados no relatório da Etapa 11.

### Arquivos alterados
- **lib/services/cupom_desconto_service.dart** — ~16 substituições (logD/logW/logE), catch (e, st) + logE
- **lib/services/canais_service.dart** — ~16 substituições, catch (e, st) + logE
- **lib/services/limits_guard.dart** — ~5 substituições, catch (e, st) + logE
- **lib/services/campaign_engine_service.dart** — ~50 substituições, catch (e, st) + logE
- **lib/services/catalogo_venda_service.dart** — ~37 substituições, catch (e, st) + logE
- **lib/services/globo_sorte_service.dart** — ~18 substituições, catch (e, st) + logE
- **lib/services/remote_config_service.dart** — ~2 substituições, catch (e, st) + logE
- **lib/services/sync_queue_service.dart** — ~10 substituições, catch (e, st) + logE
- **lib/services/store_resolver_service.dart** — ~40 substituições (logD/logW/logE), catch (e, st) + logE

**Total aproximado:** ~194 substituições nos 9 arquivos.

### Exemplos de substituições

| Antes | Depois |
|-------|--------|
| `debugPrint('✅ Cupom criado: ${docRef.id} - $codigo')` | `logD('✅ Cupom criado: ${docRef.id} - $codigo')` |
| `debugPrint('⚠️ [CupomService] Sem permissão para criar cupom')` | `logW('⚠️ [CupomService] Sem permissão para criar cupom')` |
| `} catch (e) { debugPrint('❌ Erro ao buscar cupom: $e');` | `} catch (e, st) { logE('❌ Erro ao buscar cupom: $e', error: e, st: st);` |

### O que NÃO mudou
- Firestore, streams, queries, paths, paginação, rotas, URLs.
- Layout, UX, lógica de negócio.
- Nenhuma dependência nova.

### Validação Etapa 11.1
- **dart analyze:** 0 erros, 0 warnings novos.
- **flutter build web:** ✓ Sucesso.
- **flutter build apk --debug:** ✓ Sucesso (validar ao rodar).
- **Garantia:** Sem alteração de Firestore, rotas, layout ou lógica.

---

## ETAPA 12 — Integrar CatalogoVendaService em FirestoreCatalogOrderSink (opt-in)

### Objetivo
Resolver TODO em `firestore_catalog_impl.dart`: integrar CatalogoVendaService para notificações do admin ao gravar pedido, sem alterar comportamento atual por padrão.

### Implementação

**TODO original:**
```dart
// TODO: integrar com CatalogoVendaService/PrePedidoService para
// notificações, comissão, etc., ou chamar um service do MasterPalm.
```

**Solução:** Integração opt-in via feature flag (default OFF). Quando flag ON, após gravar pedido em Firestore, chama `NotificacaoVendasService().notificarAdminNovaVenda()` (usado pelo CatalogoVendaService).

### Arquivos criados
- **lib/core/feature_flags.dart** — `const bool kEnableCatalogoVendaService = false;`

### Arquivos alterados
- **lib/catalog/data/firestore_catalog_impl.dart**
  - Imports: `feature_flags.dart`, `logger.dart`, `notificacao_vendas_service.dart`
  - `submitOrder`: captura `docRef` do add(); se `kEnableCatalogoVendaService == true`, chama `notificarAdminNovaVenda` com dados extraídos do payload (clienteNome, valorTotal, vendedorNome, pagamentoConfirmado)
  - Helpers: `_extractClienteNome`, `_extractValorTotal`, `_extractVendedorNome` para extração defensiva
  - try/catch com logE em caso de erro; fallback imediato para fluxo atual (pedido já gravado)

### Feature flag
- **Arquivo:** `lib/core/feature_flags.dart`
- **Flag:** `kEnableCatalogoVendaService` (default `false`)
- **Como habilitar:** Alterar para `true` em `lib/core/feature_flags.dart`

### O que NÃO mudou
- Firestore: paths, coleções, nomes de campos, estrutura de dados (pedidos continua igual)
- Rotas/URLs do catálogo web
- Comportamento com flag OFF: 100% idêntico ao anterior (apenas grava em pedidos, nada mais)
- Sem dependências novas
- Sem novos fluxos de UI (dialogs/snackbars)

### Validação Etapa 12
- **dart analyze:** 0 erros novos (4 infos pré-existentes em firestore_catalog_impl.dart).
- **flutter build web:** ✓ Sucesso.
- **flutter build apk --debug:** ✓ Sucesso.
- **Garantia:** Com flag OFF (default), comportamento 100% igual ao anterior.

---

## Lista completa de arquivos criados

1. `android/key.properties.example`
2. `lib/core/logger.dart`
3. `lib/screens/home/widgets/web_landing_plan_card.dart`
4. `lib/screens/public_catalog/widgets/catalog_loading_state.dart`
5. `lib/screens/public_catalog/widgets/catalog_error_loja_state.dart`
6. `lib/screens/public_catalog/widgets/catalog_config_loading_state.dart`
7. `lib/screens/public_catalog/widgets/catalog_config_error_state.dart`
8. `lib/screens/public_catalog/widgets/catalog_empty_products_state.dart`
9. `lib/screens/public_catalog/widgets/catalog_skeleton_grid.dart`
10. `lib/screens/public_catalog/widgets/catalog_search_filters_bar.dart`
11. `lib/screens/public_catalog/widgets/product_card.dart`
12. `lib/screens/public_catalog/widgets/catalog_products_grid_sliver.dart`
13. `lib/screens/public_catalog/widgets/catalog_recent_section_sliver.dart`
14. `lib/core/feature_flags.dart`
15. `lib/services/store_resolver_facade.dart` (ETAPA 15A)

---

## Lista completa de arquivos alterados

1. `android/app/build.gradle.kts`
2. `lib/core/safe_cast.dart`
3. `lib/screens/home_screen.dart`
4. `lib/screens/public_catalog_screen.dart`
5. `lib/screens/loja_config_screen.dart`
6. `lib/screens/public_catalog/widgets/carrinho_sheet_web.dart`
7. `lib/screens/clientes_screen.dart`
8. `lib/services/cliente_auth_service.dart`
9. `lib/services/produtos_firestore_service.dart`
10. `lib/services/fornecedores_firestore_service.dart`
11. `lib/services/clientes_firestore_service.dart`
12. `lib/services/vendas_firestore_service.dart`
13. `lib/services/catalog_cache_service.dart`
14. `lib/services/full_sync_service.dart`
15. `lib/services/store_resolver_unified.dart`
16. `lib/services/notificacao_vendas_service.dart`
17. `lib/services/pre_pedido_service.dart`
18. `lib/screens/app_start_router.dart`
19. `lib/app_routes.dart`
20. `lib/widgets/roleta_web_widget_v3.dart`
21. `lib/widgets/campanha_banner_widget.dart`
22. `lib/screens/fornecedor_screen.dart`
23. `lib/screens/vendas_screen.dart`
24. `lib/screens/pre_pedidos_screen.dart`
25. `lib/screens/estoque_screen.dart`
26. `lib/screens/nova_venda_modal.dart`
27. `lib/screens/globo_sorteio_screen.dart`
28. `lib/screens/estoque_screen_v2.dart`
29. `lib/debug/global_error_hook.dart`
30. `lib/main.dart`
31. `lib/utils/store_access_guard.dart`
32. `lib/services/cupom_desconto_service.dart`
33. `lib/services/canais_service.dart`
34. `lib/services/limits_guard.dart`
35. `lib/services/campaign_engine_service.dart`
36. `lib/services/catalogo_venda_service.dart`
37. `lib/services/globo_sorte_service.dart`
38. `lib/services/remote_config_service.dart`
39. `lib/services/sync_queue_service.dart`
40. `lib/services/store_resolver_service.dart`
41. `lib/catalog/data/firestore_catalog_impl.dart`
42. `firestore.rules` (ETAPA 14B)

---

## Validação pós-implantação

- **dart analyze:** 7 issues (info), 0 erros nos arquivos do catálogo.
- **flutter build web:** ✓ Built build\web
- **flutter build apk --debug:** ✓ Built build\app\outputs\flutter-apk\app-debug.apk

**Declaração explícita:** Sem alteração de regras, rotas, queries Firestore, streams, paginação, scroll listener, lógica de filtros, modelos ou comportamento visível. Etapa E: dispose/cancel já estavam corretos; nenhuma alteração. Etapa 6: safe_cast/safe_parse aplicados em leituras críticas de carrinho, config, menu, cupons, produtos e publicar catálogo em `public_catalog_screen.dart`; nomes de campos e layout inalterados.

---

## ETAPA 13 — LimitsGuard: fail-closed em erro

### Objetivo
Garantir que em caso de exceção o LimitsGuard **bloqueie** (retorne `false`) em vez de liberar (retornar `true`), seguindo princípio fail-closed para guardas de limite.

### Arquivo alterado
- **lib/services/limits_guard.dart**

### Métodos ajustados
| Método | Antes (catch) | Depois (catch) |
|--------|---------------|----------------|
| `canAddProduto` | `return true` | `return false` |
| `canAddImagemProduto` | `return true` | `return false` |
| `canAddBanner` | `return true` | `return false` |
| `canAddCliente` | `return true` | `return false` |
| `canAddVenda` | `return true` | `return false` |

### Exemplo antes/depois

**Antes:**
```dart
} catch (e, st) {
  logE('[LimitsGuard] canAddProduto erro: $e', error: e, st: st);
  return true;  // ❌ liberava em erro
}
```

**Depois:**
```dart
} catch (e, st) {
  logE('[LimitsGuard] canAddProduto erro: $e', error: e, st: st);
  return false;  // ✅ bloqueia em erro (fail-closed)
}
```

### O que NÃO mudou
- Firestore, streams, queries, paths, coleções
- Rotas, URLs, UI
- Comportamento quando não há exceção (fluxo OK permanece idêntico)
- Nenhuma dependência nova
- Logs já usavam `logE` via `logger.dart`; mantidos sem alteração

### Garantia
- **Fail-closed:** somente em exceção o retorno mudou de `true` → `false`
- Chamadas que eram permitidas em condições normais continuam permitidas
- Métodos Legacy (`canAddProdutoLegacy`, `canAddClienteLegacy`, `canAddVendaLegacy`) não têm try/catch próprio; delegam aos métodos principais já ajustados

### Validação ETAPA 13
- **dart analyze:** 0 erros novos
- **flutter build web:** ✓ Sucesso
- **flutter build apk --debug:** ✓ Sucesso

---

## ETAPA 14B — Firestore rules: restringir notas_fiscais por loja

### Objetivo
Corrigir a regra de segurança da subcoleção `notas_fiscais` para que apenas admin/programador ou vendedores da loja possam ler/escrever, eliminando o acesso indevido de qualquer usuário autenticado a notas de outras lojas.

### Arquivo alterado
- **firestore.rules**

### Trecho antes/depois

**Antes:**
```javascript
      // ---- NOTAS FISCAIS (NOVO) ----
      match /notas_fiscais/{notaId} {
        // Permite leitura/escrita para: admin, programador ou qualquer usuário autenticado da loja
        allow read, write: if isSignedIn();
      }
```

**Depois:**
```javascript
      // ---- NOTAS FISCAIS ----
      // Path real: lojas/{lojaId}/notas_fiscais/{notaId}. Apenas admin ou vendedor da loja.
      match /notas_fiscais/{notaId} {
        allow read, write: if belongsToStore(lojaId);
      }
```

### Risco corrigido
- **Antes:** `isSignedIn()` permitia que qualquer usuário autenticado lesse e escrevesse em `lojas/{qualquerLoja}/notas_fiscais/*`, incluindo lojas de outros usuários.
- **Depois:** Apenas quem pertence à loja (`belongsToStore(lojaId)` = admin/programador ou vendedor da loja) pode ler/escrever nas notas fiscais daquela loja. Usuário da loja A não consegue acessar `lojas/lojaB/notas_fiscais/*`.

### O que NÃO mudou
- Código Flutter, modelos, serviços ou paths no app (app continua usando `lojas/{lojaId}/notas_fiscais`).
- Schema ou novas coleções.
- Path do sequencial: `lojas/{lojaId}/config/nota_fiscal_sequencial` permanece regido pela rule existente de `config/`.
- Nenhuma outra rule do arquivo foi alterada.

### Garantia
- App continua usando o mesmo path: `lojas/{lojaId}/notas_fiscais` (NotaFiscalFirestoreService).
- Mesmo padrão de outras subcoleções em `lojas/{lojaId}/` (ex.: estoque_vendas, pedidos).

### Validação ETAPA 14B
- **dart analyze:** 0 erros (nenhuma alteração em código).
- **flutter build web:** ✓ Sucesso
- **flutter build apk --debug:** ✓ Sucesso
- **Teste de regras (manual):** usuário da loja A acessa apenas `lojas/lojaA/notas_fiscais/*`; não acessa `lojas/lojaB/notas_fiscais/*`; não existe path top-level `/notas_fiscais` nas rules (match está dentro de `lojas/{lojaId}`).

---

## ETAPA 15A — StoreResolverFacade (ponto único, sem mudar comportamento)

### Objetivo
Criar um facade como ponto único de entrada para resolução de loja, delegando aos serviços existentes (StoreResolverService e StoreResolverUnified), sem alterar ordem de fallback, cache ou validações.

### Arquivo criado
- **lib/services/store_resolver_facade.dart**

### Conteúdo do facade
- **StoreResolverFacade** (classe com métodos estáticos):
  - **resolveForAdminApp()** → delega a `StoreResolverService.resolve()` (loja do usuário para app admin/dashboard).
  - **resolveForPublicCatalog({required String? lojaIdFromUrl})** → delega a `StoreResolverUnified.resolve(context: publicCatalog, urlStoreId: lojaIdFromUrl)`.
  - **resolveForRouter({required Uri baseUri})** → delega a `StoreResolverService.resolve()`; `baseUri` disponível para uso futuro (hoje não altera a resolução).
- Export de **StoreResolveResult** para quem usar apenas o facade no catálogo.
- Logs mínimos via **logger** (logD com tag `STORE-FACADE`) apenas na entrada de cada método.

### O que NÃO mudou
- Nenhum arquivo existente foi alterado (somente criado o novo facade).
- Firestore, streams, queries, paths, coleções.
- Rotas, URLs, deeplinks.
- Lógica de resolução: mesma ordem, cache e validações (apenas encapsulamento/delegação).
- Sem dependências novas.

### Garantia
- Sem mudança de comportamento; apenas facade. Uso do facade em etapas futuras (migração de call sites) será opcional.

### Validação ETAPA 15A
- **dart analyze:** 0 erros novos
- **flutter build web:** ✓ Sucesso
- **flutter build apk --debug:** ✓ Sucesso

---

## ETAPA 15B — Lote 1: Migrar call sites em lib/services/** para StoreResolverFacade

### Objetivo
Migrar usos de `StoreResolverService.resolve()` em **lib/services/** para `StoreResolverFacade.resolveForAdminApp()`, mantendo tipo e comportamento (delegação).

### Arquivos alterados (15)
- **lib/services/fornecedores_firestore_service.dart** — 6 substituições
- **lib/services/produtos_firestore_service.dart** — 3
- **lib/services/vendas_firestore_service.dart** — 6
- **lib/services/full_sync_service.dart** — 1
- **lib/services/clientes_firestore_service.dart** — 6
- **lib/services/migrate_collections_service.dart** — 1
- **lib/services/catalogo_sync_service.dart** — 1
- **lib/services/nota_fiscal_firestore_service.dart** — 3
- **lib/services/tracking_service.dart** — 1
- **lib/services/sync_firestore_script.dart** — 3
- **lib/services/produto_auto_sync_service.dart** — 3
- **lib/services/catalog_publish_service.dart** — 5
- **lib/services/loja_id_service.dart** — 1
- **lib/services/cloud_sync_service.dart** — 2
- **lib/services/catalogo_config_service.dart** — 2

**Total aproximado:** 44 substituições. Em cada arquivo: import de `store_resolver_service.dart` trocado por `store_resolver_facade.dart`; chamadas `StoreResolverService.resolve()` trocadas por `StoreResolverFacade.resolveForAdminApp()`.

### Exemplos antes/depois

**Antes:**
```dart
import 'store_resolver_service.dart';
// ...
final storeId = lojaId ?? await StoreResolverService.resolve();
```

**Depois:**
```dart
import 'store_resolver_facade.dart';
// ...
final storeId = lojaId ?? await StoreResolverFacade.resolveForAdminApp();
```

**Antes:**
```dart
final lojaId = await StoreResolverService.resolve();
if (lojaId == null || lojaId.isEmpty) { ... }
```

**Depois:**
```dart
final lojaId = await StoreResolverFacade.resolveForAdminApp();
if (lojaId == null || lojaId.isEmpty) { ... }
```

### O que NÃO mudou
- Firestore, streams, queries, paths, coleções.
- Rotas, URLs, deeplinks.
- Lógica, fallback, cache, validações ou mensagens; tipo continua `String?`.
- **Não alterados (fora do lote):** main.dart, app_start_router.dart, public_catalog_screen.dart, store_resolver_service.dart, store_resolver_unified.dart. auth_service.dart continua usando `StoreResolverUnified.clearAllCaches()` (não é resolve).

### Garantia
- Sem alteração de comportamento; apenas delegação via facade (resolveForAdminApp() chama StoreResolverService.resolve() internamente).

### Validação ETAPA 15B
- **dart analyze:** 0 erros novos
- **flutter build web:** ✓ Sucesso
- **flutter build apk --debug:** ✓ Sucesso

---

## ETAPA 15C — Lote 2: Migrar call sites em lib/screens/** (admin/app logado) para StoreResolverFacade

### Objetivo
Migrar usos de `StoreResolverService.resolve()` em **lib/screens/** (contexto admin/app logado) para `StoreResolverFacade.resolveForAdminApp()`, mantendo tipo e comportamento.

### Arquivos alterados (24)
- **lib/screens/login_screen.dart** — 2 (mantido import de store_resolver_service para .debug())
- **lib/screens/estoque_screen_v2.dart** — 3
- **lib/screens/estoque_screen.dart** — 14
- **lib/screens/fornecedor_screen.dart** — 1
- **lib/screens/loja_config_screen.dart** — 3
- **lib/screens/clientes_screen.dart** — 1
- **lib/screens/home_screen.dart** — 2
- **lib/screens/vendas_screen.dart** — 1
- **lib/screens/redefinir_senha_cliente_loja_screen.dart** — 1
- **lib/screens/diagnostico_app_screen.dart** — 1
- **lib/screens/fretes_cupons_screen_v2.dart** — 2
- **lib/screens/marketplaces_screen.dart** — 1
- **lib/screens/relatorios_financeiros_screen.dart** — 1
- **lib/screens/metas_comissoes_screen.dart** — 1
- **lib/screens/precificacao_universal_screen.dart** — 1
- **lib/screens/historico_clientes_screen.dart** — 1
- **lib/screens/produto_form_screen.dart** — 1
- **lib/screens/fretes_cupons_screen.dart** — 4
- **lib/screens/notas_fiscais_screen.dart** — 1
- **lib/screens/subcategorias_screen.dart** — 1
- **lib/screens/cadastro_screen.dart** — 1
- **lib/screens/admin_sync_screen.dart** — 3
- **lib/screens/splash_screen.dart** — 1 (mantido import de store_resolver_service para .set()/.clear()/.debug())
- **lib/screens/admin_painel_web_screen.dart** — 1

**Total aproximado:** 48 substituições. Chamadas `StoreResolverService.resolve()` trocadas por `StoreResolverFacade.resolveForAdminApp()`; import de `store_resolver_facade.dart` adicionado. Em **login_screen** e **splash_screen** o import de `store_resolver_service.dart` foi mantido para uso de `.set()`, `.clear()` e `.debug()`.

### Exemplos antes/depois

**Antes:**
```dart
import '../services/store_resolver_service.dart';
// ...
final lojaId = await StoreResolverService.resolve();
```

**Depois:**
```dart
import '../services/store_resolver_facade.dart';
// ...
final lojaId = await StoreResolverFacade.resolveForAdminApp();
```

**Antes:**
```dart
_lojaId = (await StoreResolverService.resolve()) ?? '';
```

**Depois:**
```dart
_lojaId = (await StoreResolverFacade.resolveForAdminApp()) ?? '';
```

### O que NÃO mudou
- Firestore, streams, queries, paths, rotas, URLs, deeplinks, UI/layout.
- Lógica, fallback, cache, validações; tipo continua `String?`.
- **Não alterados:** public_catalog_screen.dart, lib/screens/public_catalog/**, lib/screens/auth/**, main.dart, app_start_router.dart, store_resolver_service.dart, store_resolver_unified.dart.

### Garantia
- Delegação: resolveForAdminApp() chama StoreResolverService.resolve() internamente; sem mudança de comportamento.

### Validação ETAPA 15C
- **dart analyze:** 0 erros novos
- **flutter build web:** ✓ Sucesso
- **flutter build apk --debug:** ✓ Sucesso

---

## ETAPA 15D — Lote Catálogo: migrar resolução de loja pública para StoreResolverFacade

### Objetivo
Migrar a resolução de loja **pública** (contexto catálogo) em `public_catalog_screen.dart` de `StoreResolverUnified.resolve(context: publicCatalog, ...)` para `StoreResolverFacade.resolveForPublicCatalog(lojaIdFromUrl: ...)`, sem alterar streams, queries, paginação ou UI.

### Arquivos alterados (1)
- **lib/screens/public_catalog_screen.dart** — 1 substituição (apenas o bloco que usa contexto publicCatalog).

**Total:** 1 substituição. O ramo que usa `StoreResolveContext.adminDashboard` (preview no app mobile) permanece chamando `StoreResolverUnified.resolve(...)`; import de `store_resolver_unified.dart` mantido para esse uso e para `StoreResolveContext`.

### Exemplos antes/depois

**Antes:**
```dart
import '../services/store_resolver_unified.dart';
// ...
final result = await StoreResolverUnified.resolve(
  context: StoreResolveContext.publicCatalog,
  urlStoreId: widgetId,
)
.timeout(const Duration(seconds: 12), ...);
```

**Depois:**
```dart
import '../services/store_resolver_facade.dart';
import '../services/store_resolver_unified.dart';
// ...
final result = await StoreResolverFacade.resolveForPublicCatalog(lojaIdFromUrl: widgetId)
    .timeout(const Duration(seconds: 12), ...);
```

**Uso do resultado (inalterado):**
```dart
if (!result.success) { ... }
_resolvedLojaId = result.canonicalStoreId;
_loadMostrarEstoqueNoCatalogo(result.canonicalStoreId ?? result.storeId ?? widget.lojaId);
```

### O que NÃO mudou
- Firestore, streams, queries, paginação, cache, filtros.
- Rotas, URLs, deeplinks.
- Layout/UI do catálogo (slivers, cards, widgets).
- Tipo e uso do retorno: continua `StoreResolveResult` (result.success, result.canonicalStoreId, result.storeId, result.redirectTo, result.errorMessage).
- **Não alterados:** main.dart, app_start_router.dart, store_resolver_service.dart, store_resolver_unified.dart. Nenhum arquivo em lib/screens/public_catalog/** (não havia uso de StoreResolverUnified nessa pasta).

### Garantia
- Nenhum impacto em streams, queries, paginação ou UI; apenas delegação (resolveForPublicCatalog chama StoreResolverUnified.resolve(publicCatalog) internamente).

### Validação ETAPA 15D
- **dart analyze:** 0 erros novos
- **flutter build web:** ✓ Sucesso
- **flutter build apk --debug:** ✓ Sucesso

---

## ETAPA 15E.1 — Migrar AppStartRouter para StoreResolverFacade

### Objetivo
Migrar as chamadas de resolução de loja do usuário logado em **lib/screens/app_start_router.dart** de `StoreResolverService.resolve()` para `StoreResolverFacade.resolveForRouter(baseUri: Uri.base)`, sem alterar fluxo, rotas, validação de plano/role nem mensagens.

### Arquivo alterado
- **lib/screens/app_start_router.dart**

### Quantidade de substituições
- **4** substituições de `StoreResolverService.resolve()` por `StoreResolverFacade.resolveForRouter(baseUri: Uri.base)`.
- **Mantidos** (não migrados): `StoreResolverService.invalidate()` e `StoreResolverService.set(loja)` em `_bindActiveStore` (métodos utilitários).
- **Import:** adicionado `store_resolver_facade.dart`; mantido `store_resolver_service.dart` (uso de .invalidate() e .set()).

### Exemplos antes/depois

**Antes (fallback role):**
```dart
final resolved = await StoreResolverService.resolve();
if (resolved != null && resolved.isNotEmpty) {
  vendedorStoreId = resolved;
  ...
}
```

**Depois:**
```dart
final resolved = await StoreResolverFacade.resolveForRouter(baseUri: Uri.base);
if (resolved != null && resolved.isNotEmpty) {
  vendedorStoreId = resolved;
  ...
}
```

**Antes (_bindActiveStore):**
```dart
String? loja = await StoreResolverService.resolve()
    .timeout(const Duration(seconds: 3), onTimeout: () { ... });
// ...
StoreResolverService.invalidate();
await StoreResolverService.set(loja).timeout(...);
```

**Depois:**
```dart
String? loja = await StoreResolverFacade.resolveForRouter(baseUri: Uri.base)
    .timeout(const Duration(seconds: 3), onTimeout: () { ... });
// ...
StoreResolverService.invalidate();
await StoreResolverService.set(loja).timeout(...);
```

### O que NÃO mudou
- Rotas, URLs, deeplinks, lógica de redirecionamento.
- Validação de plano, role, permissões, mensagens.
- Firestore, streams, queries, paths.
- Ordem de fallbacks/guards; tipo continua `String?`.
- store_resolver_service.dart e store_resolver_unified.dart não alterados.

### Garantia
- Fluxo do router inalterado; apenas delegação (resolveForRouter delega a StoreResolverService.resolve() internamente).

### Validação ETAPA 15E.1
- **dart analyze:** 0 erros novos
- **flutter build web:** ✓ Sucesso
- **flutter build apk --debug:** ✓ Sucesso

---

## ETAPA 15E.2 — Migrar main.dart para StoreResolverFacade (bootstrap)

### Verificação realizada
Em **lib/main.dart** foi feita busca por:
- `StoreResolverService.resolve()`
- `StoreResolverUnified.resolve(...)`
- `import ... store_resolver_service` / `store_resolver_unified`

**Resultado:** Nenhuma ocorrência encontrada. O bootstrap em main.dart **não chama** StoreResolverService nem StoreResolverUnified.

### Como o bootstrap obtém store/loja hoje
- **LojaIdService.get()** e **LojaIdService.set()** — usados em bootstrap, rotas e diagnóstico.
- **_ensureStoreIdOnBootstrap()** — lê `store_id` de Hive (sessao/config) ou deriva de `uid` (`loja_uid_$uid`) / `usuario_logado`; não usa StoreResolver.
- Rotas de catálogo público usam lojaId da URL (path/fragment) ou LojaIdService.get() no app.

### Conclusão
- **Nenhuma alteração de código** em main.dart foi necessária para a ETAPA 15E.2.
- **Arquivo alterado:** nenhum (main.dart permanece inalterado).
- **Substituições:** 0.

### Garantias
- Bootstrap, ordem de init (Firebase → RemoteConfig → AppCheck → Auth → Hive → Router) inalterados.
- Rotas, URLs, deeplinks e _isPublicCatalogUrl() inalterados.
- Firestore/streams/queries/paths inalterados.
- store_resolver_service.dart e store_resolver_unified.dart não alterados.

### Validação ETAPA 15E.2
- **dart analyze:** 0 erros (nenhuma mudança em main.dart).
- **flutter build web:** ✓ Sucesso
- **flutter build apk --debug:** ✓ Sucesso
- **Teste manual sugerido:** Web /home logado; Web /loja/<storeId>; Android debug home e LojaIdService.get() — comportamento permanece o mesmo.

---

## ETAPA 15F — Auditoria final: remover uso direto de resolve() fora do Facade

### Objetivo
Garantir que não reste uso direto de `StoreResolverService.resolve()` nem de `StoreResolverUnified.resolve(publicCatalog/...)` em lib/, exceto dentro do próprio facade e do store_resolver_unified (implementação interna).

### Busca global realizada
- **A) StoreResolverService.resolve(** — Encontrado em:
  - `lib/services/store_resolver_facade.dart` — delegação interna (não alterar).
  - `lib/services/store_resolver_unified.dart` — chamada interna em _resolveAdminDashboard (não alterar).
  - **lib/scripts/deploy_catalog_live.dart** — 1 ocorrência → migrado.
- **B) StoreResolverUnified.resolve(** — Encontrado em:
  - `lib/services/store_resolver_facade.dart` — delegação interna (não alterar).
  - **lib/screens/public_catalog_screen.dart** — 1 ocorrência (context: adminDashboard) → migrado.

### Alterações realizadas (2 arquivos)

| Arquivo | O que foi alterado |
|---------|--------------------|
| **lib/scripts/deploy_catalog_live.dart** | `StoreResolverService.resolve()` → `StoreResolverFacade.resolveForAdminApp()`; import `store_resolver_service` → `store_resolver_facade`. |
| **lib/screens/public_catalog_screen.dart** | Ramo admin/preview: `StoreResolverUnified.resolve(adminDashboard)` → `StoreResolverFacade.resolveForAdminApp()`; uso de `String? lojaId` no lugar de `StoreResolveResult`; removido import `store_resolver_unified.dart` (StoreResolveResult já vem do facade). |

### Quantidade
- **2** arquivos alterados.
- **2** substituições de chamadas de resolve (1 Service, 1 Unified adminDashboard).
- Chamadas utilitárias **não** alteradas: `StoreResolverService.invalidate()`, `.set()`, `.debug()`, `StoreResolverUnified.clearAllCaches()` permanecem onde estavam.

### Exemplos antes/depois

**deploy_catalog_live.dart — Antes:**
```dart
import '../services/store_resolver_service.dart';
// ...
final lojaId = await StoreResolverService.resolve();
```

**Depois:**
```dart
import '../services/store_resolver_facade.dart';
// ...
final lojaId = await StoreResolverFacade.resolveForAdminApp();
```

**public_catalog_screen.dart (ramo admin) — Antes:**
```dart
final result = await StoreResolverUnified.resolve(
  context: StoreResolveContext.adminDashboard,
);
if (!result.success) throw StateError(...);
setState(() { _resolvedLojaId = result.storeId; ... });
_loadMostrarEstoqueNoCatalogo(result.storeId ?? widget.lojaId);
```

**Depois:**
```dart
final lojaId = await StoreResolverFacade.resolveForAdminApp();
if (lojaId == null || lojaId.trim().isEmpty) throw StateError('Nenhuma loja configurada');
setState(() { _resolvedLojaId = lojaId; ... });
_loadMostrarEstoqueNoCatalogo(lojaId);
```

### O que NÃO mudou
- Firestore, streams, queries, paths, coleções.
- Rotas, URLs, deeplinks.
- Layout/UI.
- Comportamento: mesma resolução (delegação via facade); ramo admin do catálogo continua usando loja do usuário logado.

### Garantia
- Comportamento inalterado (delegação). Nenhum uso direto de `resolve()` para “loja do app logado” ou “catálogo público” permanece fora do facade, exceto nas implementações em store_resolver_service e store_resolver_unified.

### Validação ETAPA 15F
- **dart analyze:** 0 erros novos
- **flutter build web:** ✓ Sucesso
- **flutter build apk --debug:** ✓ Sucesso

---

## ETAPA 15F.1 — Hotfix: restaurar comportamento do ramo adminDashboard no catálogo

### Problema
Na ETAPA 15F o ramo admin/preview foi migrado para `resolveForAdminApp()` (retorna `String?`), perdendo o uso de `StoreResolveResult` (redirects, canonicalStoreId, needsRedirect, errorMessage) e alterando o fluxo.

### Solução
- **Facade:** novo método `resolveForAdminDashboard(lojaIdFromUrl)` que delega a `StoreResolverUnified.resolve(context: adminDashboard, urlStoreId: lojaIdFromUrl)` e retorna `StoreResolveResult`.
- **Screen:** ramo admin volta a usar `StoreResolveResult` (result.success, result.errorMessage, result.canonicalStoreId, result.storeId, result.needsRedirect, result.redirectTo) com timeout 12s, sem importar Unified no screen.

### Arquivos alterados (2)
- **lib/services/store_resolver_facade.dart** — Adicionado `resolveForAdminDashboard({required String? lojaIdFromUrl})` com logD e delegação a `StoreResolverUnified.resolve(adminDashboard, urlStoreId)`.
- **lib/screens/public_catalog_screen.dart** — Ramo admin: `resolveForAdminApp()` + StateError substituído por `resolveForAdminDashboard(lojaIdFromUrl: widgetId)` + uso de `result.success`, `result.errorMessage`, `result.canonicalStoreId`, `result.storeId`, `result.needsRedirect`, `result.redirectTo` e timeout 12s; mantido apenas import do facade.

### Garantia
- Comportamento do adminDashboard restaurado (StoreResolveResult, redirects, mensagens); Facade continua sendo ponto único (screen não importa store_resolver_unified).

### Validação ETAPA 15F.1
- **dart analyze:** 0 erros novos
- **flutter build web:** ✓ Sucesso
- **flutter build apk --debug:** ✓ Sucesso

---

## ETAPA 16 — Externalizar hardcoding sensível (root admins + hosts AppCheck Web) via Remote Config com fallback total (flag OFF)

### Regras respeitadas
- NÃO alterar Firestore/streams/queries/paths/coleções.
- NÃO alterar rotas/URLs/deeplinks.
- NÃO alterar UI/layout.
- Sem dependências novas.
- Fail-safe: se Remote Config falhar, vier vazio ou inválido, usa exatamente o hardcoded atual.
- Flags OFF por padrão; com flag OFF o comportamento é idêntico ao atual.

### Arquivos criados
- **lib/core/remote_config_keys.dart** — Chaves RC: `rc_root_admin_emails_json`, `rc_appcheck_allowed_hosts_json`, `rc_enable_dynamic_root_admins` (default false), `rc_enable_dynamic_appcheck_hosts` (default false).
- **lib/services/remote_config_safe_service.dart** — Funções seguras: `isFlagOn(key, fallback)`, `getStringListFromJson(key, fallback)`; captura exceções (logW/logE e retorna fallback); sanitiza (trim, lowercase, remove vazios e duplicados); aceita JSON array `["a@b.com"]` ou string CSV `"a@b.com,b@c.com"`. Não altera inicialização do Remote Config.

### Arquivos alterados
- **lib/screens/app_start_router.dart** — Lista hardcoded de root admins substituída por `_getRootAdminEmails()`: com flag `rc_enable_dynamic_root_admins` OFF usa set hardcoded (`masterpalm26@gmail.com`, `masterpalm@gmail.com`, `admin@masterpalm.com`); com flag ON lê `rc_root_admin_emails_json` do RC e, se lista vazia, usa fallback hardcoded. Todos os pontos que checam root admin por e-mail passam a usar `_getRootAdminEmails()`.
- **lib/config/app_check_config.dart** — Nova função `isHostAllowed(host)`: com flag `rc_enable_dynamic_appcheck_hosts` OFF usa `kAppCheckWebAllowedHosts`; com flag ON lê lista do RC e, se vazia, fallback na lista hardcoded. Host comparado em lowercase.
- **lib/main.dart** — Verificação de host para App Check Web: de `kAppCheckWebAllowedHosts.contains(host)` para `isHostAllowed(host)`.

### Comportamento com flag OFF (padrão)
- Idêntico ao anterior: root admins = lista hardcoded em app_start_router; hosts App Check = `kAppCheckWebAllowedHosts` em app_check_config.

### Comportamento com flag ON
- **Root admins:** lista lida de `rc_root_admin_emails_json`; se RC falhar ou lista vazia → fallback na lista hardcoded.
- **Hosts App Check Web:** lista lida de `rc_appcheck_allowed_hosts_json`; se RC falhar ou lista vazia → fallback em `kAppCheckWebAllowedHosts`.

### Garantias
- Firestore, rotas, UI inalterados. Apenas fonte da lista de root admins (cliente) e da lista de hosts App Check passível de vir do RC, com fallback total.

### Validação ETAPA 16
- **dart analyze lib/:** 0 erros novos
- **flutter build web:** sucesso
- **flutter build apk --debug:** sucesso

---

## ETAPA 17 — Unificar "usuarios" vs "users" com migração gradual e fail-safe

### Regras respeitadas
- NÃO alterar Firestore rules.
- NÃO alterar paths/coleções usadas pelo app (nenhuma troca forçada).
- NÃO alterar rotas/URLs/deeplinks.
- NÃO alterar UI/layout.
- Sem dependências novas.
- Compatível: só usuarios/{email}, só users/{uid} ou ambos (preferência determinística; logW em duplicidade).
- Em erro/timeout: fallback para o comportamento atual.

### Arquivos criados
- **lib/core/user_profile_keys.dart** — Constantes dos campos de perfil (role, tipo, tipo_usuario, store_id, storeId, ownerStoreId, loja_id, lojaId) usados no app.
- **lib/models/user_profile.dart** — Classe imutável UserProfile (uid, email, role, storeId, isRoot, sourceCollection, raw); factory fromMap com mesma ordem de fallback do app; modelo adicional, não altera modelos existentes.
- **lib/services/user_profile_resolver.dart** — UserProfileResolver.resolveCurrentUserProfile(isRoot): lê users/{uid} e/ou usuarios/{email}; timeout 10s; se ambos existirem prefere users e logW; em erro/timeout logE e retorna null.

### Arquivos alterados
- **lib/core/feature_flags.dart** — kEnableUnifiedUserProfileResolver = false (padrão OFF).
- **lib/screens/app_start_router.dart** — _resolveUserProfile(isRootEmail) que chama o resolver. Se kEnableUnifiedUserProfileResolver == false: fluxo atual (fetchRoleAndStore) sem mudanças. Se true: tenta resolver; se perfil != null usa role/storeId do perfil; se null ou erro usa fetchRoleAndStore (fallback). Lógica de redirecionamento, plano, guards e rotas inalterada.

### Comportamento com flag OFF (padrão)
- Idêntico ao anterior: router usa fetchRoleAndStore (users + usuarios em paralelo, merge como hoje). Nenhuma chamada ao UserProfileResolver.

### Comportamento com flag ON
- Router chama UserProfileResolver.resolveCurrentUserProfile(isRoot: isRootEmail).
- Se retornar perfil: userRole e vendedorStoreId vêm do perfil (sourceCollection = 'users' ou 'usuarios'); logD 1x com fonte usada.
- Se retornar null (nenhum doc, timeout ou exceção): fallback para fetchRoleAndStore.
- Se existirem users e usuarios para o usuário: preferência users, logW com mensagem clara.

### Logs
- logD 1x: fonte usada (users ou usuarios) quando flag ON.
- logW quando ambas coleções existem (duplicidade).
- logE em exceções (com error e st). Sem tokens nem dados sensíveis.

### Garantias
- Nenhuma alteração de rules, rotas, UI, paths Firestore existentes. Apenas um ponto central (router) usa o resolver quando a flag está ON; outros services que leem usuarios/users não foram migrados nesta etapa.

### Validação ETAPA 17
- **dart analyze lib/:** 0 erros novos
- **flutter build web:** sucesso
- **flutter build apk --debug:** sucesso

---

## ETAPA 17.1 — UserProfileResolver: não aceitar perfil incompleto (fail-safe)

### Motivo
Migração parcial ou documento Firestore incompleto pode fazer o resolver retornar perfil com role ou storeId vazios. Não usar esse perfil para decidir rota/permissão; fazer fallback para fetchRoleAndStore.

### Regras
- NÃO mudar rules, UI, rotas, paths.
- Sem dependências. Alteração pequena e reversível.

### Arquivos alterados (2)
- **lib/models/user_profile.dart** — Getters: `hasValidRole` (role trim não vazio), `hasValidStoreId` (storeId não null e trim não vazio), `isComplete` (ambos válidos).
- **lib/screens/app_start_router.dart** — No ramo flag ON: se `profile != null` e `!profile.isComplete`, logW com sourceCollection e role/storeId e não usar o perfil (gotProfileFromResolver permanece false → executa fetchRoleAndStore). Só usa profile quando `profile.isComplete`.

### Garantias
- Sem alteração de rules, rotas, UI, paths. Logs sem email completo (apenas sourceCollection e role/storeId).

### Validação ETAPA 17.1
- **dart analyze lib/:** 0 erros novos
- **flutter build web:** sucesso
- **flutter build apk --debug:** sucesso

---

## ETAPA 18 — Globo Sorteio: remover lojaId/campanhaId hardcoded com resolução segura + fallback

### Regras respeitadas
- NÃO alterar Firestore rules.
- NÃO alterar schema/paths/coleções (somente leitura em lojas/{lojaId}/campanhas_sorteio).
- NÃO alterar UI/layout da tela de sorteio (apenas wrapper com loading/erro quando necessário).
- NÃO alterar rotas existentes (path `/globo_sorteio` mantido).
- Sem dependências novas.
- Em falha/erro/timeout: fallback em debug (placeholders + logW); em release mensagem amigável sem crash.

### Problema
Rota e menu usavam placeholders fixos: lojaId `'masterpalm'` / `_lojaSlug` e campanhaId `'xxx'` / `'ID_DA_CAMPANHA_ATUAL'`, podendo gravar/ler do lugar errado.

### Arquivos criados
- **lib/services/globo_sorteio_params_resolver.dart** — `GloboSorteioParams` (lojaId, campanhaId, source); `GloboSorteioParamsResolver.resolve(uri, isWeb)`: extrai lojaId/campanhaId da URL (query e fragment; aliases `store`/`campaign`); se lojaId faltando usa `LojaIdService.get()` e depois `StoreResolverFacade.resolveForAdminApp()`; se campanhaId faltando busca campanha ativa em `lojas/{lojaId}/campanhas_sorteio` (critério ativa/status e dataInicio/dataFim, limit 50, timeout 10s). logD com source; logW quando busca contexto/campanha; logE em erro e retorna null.

### Arquivos alterados
- **lib/screens/globo_sorteio_screen.dart** — Novo widget `GloboSorteioScreenWrapper`: chama o resolver com `Uri.base`; se params != null abre `GloboSorteioScreen(lojaId, campanhaId)`; se null e kDebugMode usa placeholders e logW (fallback debug-only); se null e release mostra tela com mensagem "Sorteio indisponível. Contate o suporte." (sem crash).
- **lib/main.dart** — Rota `/globo_sorteio` passa a usar `GloboSorteioScreenWrapper()` em vez de `GloboSorteioScreen(lojaId: 'masterpalm', campanhaId: 'xxx')`.
- **lib/screens/home_screen.dart** — Menu "Globo de Sorteio" passa a usar `pushWidget: const GloboSorteioScreenWrapper()` em vez de `GloboSorteioScreen(lojaId: _lojaSlug, campanhaId: 'ID_DA_CAMPANHA_ATUAL')`.

### De onde vêm os params
- **Prioridade 1:** URL — query ou fragment: `lojaId`/`loja_id`/`store`/`storeId` e `campanhaId`/`campanha_id`/`campaign`/`campanha`.
- **Prioridade 2 (lojaId):** `LojaIdService.get()`, depois `StoreResolverFacade.resolveForAdminApp()`.
- **CampanhaId:** se não veio da URL, query em `lojas/{lojaId}/campanhas_sorteio` (ativa/status + período), primeira ativa retornada.

### Comportamento fallback
- **Debug:** Resolver retorna null → logW "fallback debug-only" e abre tela com placeholders (masterpalm/xxx).
- **Release:** Resolver retorna null → tela com "Sorteio indisponível. Contate o suporte." (ação bloqueada, sem crash).

### Garantias
- Sem alteração de rules, schema, paths de coleções, rotas (path/nome). Apenas remoção de placeholders fixos e resolução dinâmica com fallback seguro.

### Validação ETAPA 18
- **dart analyze lib/:** 0 erros novos
- **flutter build web:** sucesso
- **flutter build apk --debug:** sucesso

---

## ETAPA 19 — CatalogCacheService.getConfigStream: remover while(true) e garantir cancelamento

### Regras respeitadas
- NÃO alterar Firestore paths/queries/streams usados fora do método.
- NÃO alterar UI/layout/rotas.
- Nenhuma dependência nova.
- Comportamento funcional mantido: stream continua entregando config com cache/fallback e TTL 10 min.
- Ao cancelar o listener (dispose), o stream para 100% (Timer cancelado em onCancel).

### Arquivo alterado
- **lib/services/catalog_cache_service.dart** — Método `getConfigStream` / `_configStreamWithBackgroundRefresh`.

### Antes
- `async*` com dois `while (true)`: um ao servir do cache (delay TTL → _fetchConfig → yield), outro após o primeiro fetch (delay TTL → _fetchConfig → yield). Em erro apenas logW, sem reemitir. O loop nunca parava ao cancelar a subscrição.

### Depois
- Stream via `StreamController<Map<String, dynamic>>.broadcast()`.
- **onListen:** se cache válido e !forceRefresh → emite cache e inicia `Timer.periodic(_configTtlSeconds, tick)`; senão → executa um fetch inicial (com timeout 10s e fallback cache/{}), emite e inicia o mesmo Timer.
- **tick():** chama `_fetchConfig` com timeout 10s; atualiza cache; emite só se o config for distinto do último (comparação com jsonEncode); em timeout/erro logW e não emite.
- **onCancel:** `timer?.cancel()`, timer = null. Nenhum loop continua rodando após cancelamento.

### Lógica original documentada no código
- Fonte: Firestore (lojas/{lojaId}/config ou draft_config + payments + cupons via _fetchConfig).
- TTL: 10 min (_configTtlSeconds).
- Tratamento de erro: logW; no loop não reemitia; no primeiro fetch usava fallback do cache ou {}.

### Garantias
- Firestore paths, queries e uso em outros pontos inalterados. Rotas e UI inalterados. Semântica do stream preservada (cache primeiro quando válido, refetch após TTL, fallback em erro).

### Validação ETAPA 19
- **dart analyze lib/:** 0 erros novos
- **flutter build web:** sucesso
- **flutter build apk --debug:** sucesso

---

## ETAPA 20 — Web App Check soft-fail para não quebrar login Google

### Regras respeitadas
- NÃO alterar Firestore/streams/queries/paginação/rotas/URLs.
- NÃO mudar layout/UI.
- Nenhuma dependência nova.
- Android inalterado: Play Integrity continua obrigatório no release.
- No Web: se App Check falhar (400/throttle/storage blocked), o app continua e permite login Google normalmente.

### Objetivo
Evitar que falhas de App Check no Web (reCAPTCHA v3 token 400 / throttled / tracking prevention) bloqueiem Auth e login Google.

### Arquivo alterado
- **lib/main.dart** — Bootstrap e initFirebaseAppCheck.

### Antes
- Web: ativação em try/catch único; falhas já não bloqueavam o bootstrap (catch no chamador com "[AppCheck] (ignorado)").
- Logs de falha em logD.

### Depois
- **Web:** ramo kIsWeb envolvido em try/catch interno: em qualquer exceção ou retorno false de _activateAppCheckWeb, logW uma vez (tag APP-CHECK), flag _appCheckWebOk = false, _appCheckActivatedOnce = true, return sem rethrow. Bootstrap segue normalmente.
- **FirebaseException/catch genérico:** no Web seta _appCheckWebOk = false e usa logW com mensagem única; no mobile mantém lógica anterior (backoff, logD).
- **_activateAppCheckWeb:** falhas logadas com logW (tag APP-CHECK), mensagens indicando que o login continua.
- **Bootstrap:** catch de initFirebaseAppCheck mantém texto "(ignorado)" e usa logW; não rethrow — Auth e login Google não são bloqueados.
- **Flag _appCheckWebOk:** exposta em getAppCheckDiagnostics() para diagnóstico (Web ativado com sucesso ou não).
- Uma única tentativa no Web: ao falhar, _appCheckActivatedOnce = true e backoff quando aplicável; não há loop de retry.

### Garantias
- Android: comportamento de App Check (Play Integrity / DEBUG) inalterado.
- Web: soft-fail — falha de App Check não interrompe bootstrap nem Auth; login Google funciona mesmo com tracking prevention ou 400/throttle.
- Sem crash nem popup extra em release no Web.

### Validação ETAPA 20
- **dart analyze lib/:** 0 erros novos
- **flutter build web:** sucesso
- **flutter build apk --debug:** sucesso

---

## ETAPA 21 (ZERO RISCO) — Persistir APENAS o CONFIG do catálogo em disco (Hive)

### Regras respeitadas
- NÃO alterar Firestore/streams/queries/paginação/rotas/URLs.
- NÃO mudar layout/UI.
- Nenhuma dependência nova (Hive já existente).
- NÃO mudar schema/paths do Firestore.
- Nesta etapa: somente CONFIG em disco; produtos não são cacheados em disco.

### Escopo
- **lib/services/catalog_cache_disk_store.dart** (novo)
- **lib/services/catalog_cache_service.dart** (alterado)
- Sem alteração em screens, models ou rules.

### Objetivo
Guardar em Hive o último config do catálogo por (lojaId, preview), com o mesmo TTL do serviço (10 min), para que ao reiniciar o app/web o stream emita o config do disco imediatamente quando ainda válido, sem alterar o restante do fluxo (fetch Firestore em background pelo timer).

### Arquivos criados
- **lib/services/catalog_cache_disk_store.dart** — `CatalogCacheDiskStore` singleton; box `catalog_cache_disk`; chaves `cfg:lojaId_preview` e `meta:lojaId_preview`; `writeConfig(lojaId, cfg, updatedAtMs, {preview})` (tipos json-safe, meta com updatedAtMs e schemaVersion: 1); `readConfig(lojaId, {preview})` retorna cfg e updatedAtMs ou nulls; `clear(lojaId, {preview})` opcional. Try/catch em read/write com logW (tag CACHE-DISK), fallback neutro. Conversão para json-safe: Timestamp/DateTime → millis (int).

### Arquivos alterados
- **lib/services/catalog_cache_service.dart** — Import do disk store; `_disk = CatalogCacheDiskStore.instance`. No **onListen** do getConfigStream: antes do primeiro fetch, tenta `_disk.readConfig(lojaId, preview)`; valida TTL com o mesmo _configTtlSeconds (nowMs - updatedAtMs <= 10min); se válido e cache em memória não melhor, preenche cache em memória, emite `controller.add(disk.cfg)` e inicia o timer (return). Log adicionado: `logD('📦 [CACHE] Config servido do disco ($lojaId)')`. Após cada _fetchConfig com sucesso (tick e fetch inicial): chama `_disk.writeConfig(lojaId, cfg, updatedAtMs, preview)`. Falha de write apenas logW no disk store.

### Logs (máximo 2)
- `logD('📦 [CACHE] Config servido do disco ($lojaId)')` — quando o config é emitido a partir do disco (TTL válido).
- `logW('[CACHE-DISK] readConfig falhou: ...'` ou `writeConfig falhou: ...'` — apenas em erro de leitura/escrita (tag CACHE-DISK).

### Garantias
- Firestore, streams, queries, paginação e UI inalterados. TTL (10 min), timeout (10s) e Timer.periodic inalterados. Distinct (jsonEncode) inalterado. Config expirado no disco não é emitido como válido; o fluxo segue para o fetch no Firestore como antes.

### Validação ETAPA 21
- **dart analyze lib/:** 0 erros novos
- **flutter build web:** sucesso
- **flutter build apk --debug:** sucesso

---

## ETAPA 22A (ZERO RISCO) — Observabilidade segura do cache em disco do catálogo

### Objetivo
Adicionar observabilidade segura para o cache em disco do catálogo (apenas logs em debug) e uma função de auditoria opcional, **sem alterar comportamento do app**.

### Regras respeitadas
- NÃO alterar Firestore/streams/queries/paginação/rotas/URLs.
- NÃO alterar lógica nem layout (nenhuma tela/UX).
- NÃO adicionar dependências.
- NÃO mudar outputs do stream nem estrutura do cfg em memória.
- Tudo NO-OP em release (logger já respeita kDebugMode).
- Novidades atrás de flag OFF por padrão.
- Não imprimir dados sensíveis (apenas contagens/booleans; nunca tokens/keys/emails/ids completos).

### Arquivos criados
- **lib/services/catalog_cache_disk_auditor.dart** — Classe `CatalogCacheDiskAuditor` com método estático `auditLoja(String lojaId, {bool preview = false})`. Lê do `CatalogCacheDiskStore.readConfig`; se não existir cache: `logW` tag CACHE-DISK "Sem cache em disco"; se existir: `logD` com updatedAtMs, ageSeconds, cfgTopKeysCount (nunca imprime cfg). Utilitário apenas; não usado pelo app nesta etapa.

### Arquivos alterados
- **lib/core/feature_flags.dart** — Adicionada `kEnableCatalogDiskCacheAuditLogs = false`.
- **lib/services/catalog_cache_disk_store.dart** — Em `readConfig()`: quando `kEnableCatalogDiskCacheAuditLogs == true`, `logD` tag CACHE-DISK com lojaId, preview, temCfg, updatedAtMs (se existir), cfg.keys.length (top-level) quando cfg != null; não loga valores do cfg. Em `writeConfig()`: quando flag ON, `logD` com lojaId, preview, updatedAtMs e cfg.keys.length; se `kEnableCatalogDiskCacheSanitize == true` e houver chaves removidas, `logD` com quantidade de chaves removidas (apenas número). Nenhum call-site alterado; catalog_cache_service.dart não modificado.

### Flags adicionadas (OFF por padrão)
- **kEnableCatalogDiskCacheAuditLogs** (lib/core/feature_flags.dart) — `false`. Quando `true`, habilita logs seguros de leitura/escrita no disk store (apenas em debug).

### Garantias
- Comportamento do app inalterado. Logs só em kDebugMode e somente com flag ON. Auditoria é utilitário opcional, não chamado pelo fluxo do app. Nenhum dado sensível impresso (apenas contagens, booleans, updatedAtMs).

### Validação ETAPA 22A
- **dart analyze lib/:** 0 erros novos
- **flutter build web:** sucesso
- **flutter build apk --debug:** sucesso

---

## ETAPA 22B (log safety + docs) — PROIBIDO alterar dados

### Regra crítica
Nenhum dado foi apagado, limpo, migrado ou reescrito (nem disco, nem Hive, nem Firestore). Apenas mensagens de log, comentários e documentação.

### Objetivo
Remover identificadores de loja dos logs do DiskStore; endurecer logs de exceção (sem imprimir exceção completa); documentar exemplo de uso do auditor.

### Arquivos alterados
- **lib/services/catalog_cache_disk_store.dart**
  - **Remoção de lojaId dos logs:** Em todos os `logD` de auditoria (read/write), removido `lojaId=$lojaId`. Logs passam a usar apenas metadados seguros: `preview`, `updatedAtMs`, `topKeys` (cfgTopKeysCount), e action: `write_ok`, `read_ok`, `read miss`. Nenhum identificador de loja em logs.
  - **Hardening de exceções:** Em `writeConfig`, `readConfig` e `clear`, os `logW` que imprimiam `$e` foram trocados por mensagem genérica com apenas o tipo: `(type=${e.runtimeType})`. Não se imprime mais exceção completa, stack trace nem paths.
- **lib/services/catalog_cache_disk_auditor.dart**
  - Comentário no topo com exemplo de uso em debug: `if (kEnableCatalogDiskCacheAuditLogs) { await CatalogCacheDiskAuditor.auditLoja(lojaId, preview: false); }`. Nenhum call-site criado no app.
- **MUDANCAS_ETAPAS_SEGURANCA.md**
  - Esta seção ETAPA 22B.

### Garantias
- Sem alteração de dados: nenhuma operação de delete/clear/migrate foi adicionada ou acionada.
- Nenhum call-site alterado; flags OFF mantêm comportamento idêntico.
- Logs apenas em debug e, quando aplicável, com flag `kEnableCatalogDiskCacheAuditLogs` ON.
- Auditor continua sem imprimir lojaId (apenas preview, updatedAtMs, ageSeconds, cfgTopKeysCount).
