# Catálogo multi-loja: escalar sem travamentos e bugs

Este documento reúne boas práticas para que o catálogo funcione 100% para várias lojas e clientes, com lojas **totalmente separadas por ID**, sem travamentos, tela cinza ou dados misturados.

---

## 1. Isolamento por loja (ID)

- **Uma URL = uma loja.** O identificador da loja vem da rota (ex.: `/loja/nathy-pratas-e-folheados`). O `lojaId` resolvido (slug → ID) é a **única fonte de verdade** para config, produtos, carrinho e favoritos naquela tela.
- **Nunca misturar dados entre lojas:** carrinho, favoritos, pedidos e config devem sempre usar o `lojaId` da loja atual. No código:
  - `PublicCatalogScreen` já limpa `_lastProdutos` e os **streams em cache** quando `lojaId` muda (`didUpdateWidget`), para não reutilizar stream da loja anterior.
  - Carrinho e checkout já são escopados por loja nos serviços (ex.: chave por `lojaId`).
- **Cache sempre por loja:** `CatalogCacheService`, `_staticConfigCache` e `_staticProdutosCache` usam `lojaId` (ou `lojaId_preview`) na chave. Ao abrir outra loja, os dados da anterior continuam em cache mas **não são exibidos**; a nova loja usa apenas seus próprios streams e cache.

---

## 2. Evitar travamentos e tela cinza

- **Streams em cache:** Config e produtos usam streams cacheados por `(lojaId, preview, refreshCounter)`. Rebuilds não criam novo stream, evitando “waiting” desnecessário.
- **Cache de último valor:** Quando o stream está em `ConnectionState.waiting` (reconexão, etc.), a tela usa:
  - **Config:** `_staticConfigCache[lojaId]` em vez de mostrar “Carregando configuração…” e apagar o corpo.
  - **Produtos:** `_lastProdutos` ou `_staticProdutosCache[lojaId]` em vez de skeleton cinza.
- **Regra de ouro:** Se `produtos.isNotEmpty` (ou há cache com itens), **nunca** mostrar tela cheia de loading nem placeholder cinza; no máximo loader no rodapé em cenário de “carregar mais”.
- **Broadcast streams:** Os streams do catálogo são `.asBroadcastStream()` para evitar “Stream has already been listened to” em múltiplos listeners/rebuilds.

---

## 3. Escala e memória (muitas lojas / muitos usuários)

- **Limite de cache estático na tela:** Em `PublicCatalogScreen` há um limite de **30 lojas** em `_staticConfigCache` e `_staticProdutosCache`. Ao ultrapassar, a loja mais antiga (ordem de inserção) é removida. Assim o app não cresce indefinidamente na memória quando o usuário visita muitas lojas.
- **Cache de serviço (CatalogCacheService):** Config e produtos têm TTL (ex.: 10 min config, 5 min produtos). O cache é por `lojaId`; invalidação também é por loja (`invalidate(lojaId)`).
- **Firestore:** Queries de config e produtos são sempre filtradas por loja (ex.: `lojas/{lojaId}/...`). Em escala, use índices compostos se precisar de filtros/ordenacao e monitore leituras.

---

## 4. Resiliência e erros

- **Erro no stream de produtos:** A tela mostra mensagem de erro e botão “Tentar novamente”, sem apagar a lista já carregada se houver cache.
- **Erro na resolução do lojaId (init):** Mensagem amigável e SnackBar; não fica em “Carregando catálogo…” para sempre (há timeout e tratamento em `_resolveLojaId`).
- **Logs:** Os prints `[CATALOGO]` (init start/end, stream data count, cache, error) ajudam a diagnosticar em desenvolvimento; em produção podem ser enviados para Crashlytics/analytics para detectar falhas por loja.

---

## 5. Checklist para não ter problema de catálogo “fora do ar”

- [ ] **URL/rota:** Sempre resolver slug → `lojaId` uma vez e usar esse ID em toda a tela (config, produtos, carrinho, checkout).
- [ ] **Troca de loja:** Ao navegar para outra loja (novo link), o widget recebe novo `lojaId`; `didUpdateWidget` limpa estado da loja anterior (lista + streams em cache).
- [ ] **Cache:** Config e produtos usam cache por loja; em `waiting` usa último valor em cache para não mostrar tela cinza.
- [ ] **Nunca limpar lista ao “carregar mais”:** Se no futuro houver paginação por scroll, manter a lista atual e só adicionar itens ou mostrar loader no rodapé.
- [ ] **Carrinho e pedidos:** Sempre associados ao `lojaId` da loja onde o cliente está comprando.
- [ ] **Testes manuais:** Abrir loja A → rolar → abrir link da loja B → conferir que vê apenas dados da B; voltar para A e conferir que não há mistura.

---

## 6. O que já está implementado no código

| Item | Onde |
|------|------|
| Limpeza de streams ao trocar de loja | `didUpdateWidget` em `public_catalog_screen.dart` |
| Cache estático de config por lojaId | `_staticConfigCache` + uso quando config em waiting |
| Cache estático de produtos por lojaId | `_staticProdutosCache` + uso quando produtos em waiting |
| Limite de 30 lojas no cache estático | `_evictStaticCacheIfNeeded` em `public_catalog_screen.dart` |
| Cache de config/produtos com TTL por loja | `CatalogCacheService` (chave com lojaId) |
| Isolamento de dados por loja no Firestore | Queries em `lojas/{lojaId}/...` |

Seguindo essas práticas, o catálogo tende a permanecer estável ao escalar para vários usuários e várias lojas, com cada loja funcionando de forma isolada e sem travamentos ou tela cinza por causa de rebuild ou reconexão.
