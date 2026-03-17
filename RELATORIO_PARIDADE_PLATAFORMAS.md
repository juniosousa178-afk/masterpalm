# Conferência de Paridade – Web, APK e demais plataformas (MasterPalm)

## 1. Visão geral da paridade entre plataformas

- **Fluxo principal (ProdutoFormScreen, VendasService, ClientesScreen, EstoqueScreen)** usa os mesmos serviços, mesmas coleções Firestore e mesmas boxes Hive (`HiveBoxNames.*(lojaId)`). Não há branch por `kIsWeb` que altere destino de gravação ou leitura para esses fluxos.
- **Resolução de loja no admin**: `StoreResolverFacade.resolveForAdminApp()` → `StoreResolverService.resolve()`, que usa apenas Firebase Auth (UID) e Firestore (`users/{uid}`, `usuarios/{email}`). **Não depende de plataforma**; Web e APK com o mesmo usuário obtêm o mesmo `lojaId`.
- **Riscos concentrados em**: (1) fluxo alternativo de cadastro que grava só em `draft_produtos`; (2) uso de boxes legadas sem `lojaId` em importação Excel; (3) bootstrap que abre boxes genéricas; (4) dependência de sync/refresh para ver alterações feitas em outro dispositivo.

---

## 2. Fluxos com paridade confirmada

| Fluxo | Evidência no código | Coleção/Box | Classificação |
|-------|---------------------|-------------|---------------|
| **Vendas (nova venda)** | `VendasService` grava em Hive `HiveBoxNames.vendas(lojaId)`; `VendasFirestoreService.syncVenda` grava em `lojas/{storeId}/estoque_vendas`. Mesmo payload e mesmo `storeId` via `StoreResolverFacade.resolveForAdminApp()`. | `estoque_vendas`, `HiveBoxNames.vendas(lojaId)` | **CONFIRMADO** |
| **Vendas (leitura/sync)** | `VendasFirestoreService.syncFirestoreToHive` lê `estoque_vendas` e preenche a mesma box por loja. `AutoSyncService` chama FullSync + sync vendas; acionado no login e na reconexão (sem guard `kIsWeb`). | idem | **CONFIRMADO** |
| **Produtos (form estoque)** | `ProdutoFormScreen` persiste em Hive; `ProdutosFirestoreService.syncProduto` grava em `lojas/{storeId}/estoque_produtos` e, se publicado, em `produtos`. `FirestoreCriticalListenerService` escuta `estoque_produtos` e chama `syncFirestoreToHive` (sem branch Web/APK). | `estoque_produtos`, `produtos`, `HiveBoxNames.produtos(lojaId)` | **CONFIRMADO** |
| **Clientes (admin)** | `ClientesFirestoreService` usa `lojas/{storeId}/estoque_clientes`. Telas usam `HiveBoxNames.clientes(lojaId)`. FullSync e AutoSync sincronizam `estoque_clientes` → Hive. | `estoque_clientes`, `HiveBoxNames.clientes(lojaId)` | **CONFIRMADO** |
| **Estoque (baixa transacional)** | `EstoqueTransactionService` usa `lojas/{lojaId}/estoque_produtos` e, quando aplicável, `produtos`/`draft_produtos`. Sem branch por plataforma. | `estoque_produtos` | **CONFIRMADO** |
| **Catálogo / pedido (registro de venda)** | `CatalogoVendaService` usa `HiveBoxNames.produtos(lojaId)`, `estoque_produtos` e `produtos` para resolução e baixa; grava venda via mesmo fluxo de sync. | mesmo que vendas/produtos | **CONFIRMADO** |
| **Loja ativa no admin** | `StoreResolverService.resolve()` usa apenas UID e Firestore; mesmo resultado em Web e APK para o mesmo usuário. | N/A | **CONFIRMADO** |

---

## 3. Fluxos com paridade parcial

| Fluxo | O que está igual | O que diverge ou falta | Classificação |
|-------|-------------------|-------------------------|----------------|
| **Cadastro de produto (tela alternativa)** | `CadastroProdutoScreen` grava em `lojas/{idLoja}/draft_produtos` com `widget.idLoja`. Se `idLoja` for o mesmo da loja resolvida no admin, a loja está correta. | Produtos criados só em `draft_produtos` **não** entram em `estoque_produtos`. FullSync e listener leem apenas `estoque_produtos`. Ou seja: produto “só rascunho” não aparece na lista de estoque/admin em outras plataformas até ser promovido (ex.: publicação/cópia para estoque). | **PARIDADE PARCIAL** |
| **Combos** | `ProdutoComboFormScreen` usa `HiveBoxNames.produtos(lojaId)` e grava em `draft_produtos`/`produtos` via `CatalogoSyncService`. Fluxo de escrita não tem branch Web/APK. | Combos antigos sem `productId` em itens dependem de fallback (slug/nome); o comportamento é o mesmo em todas as plataformas, mas o risco de ambiguidade permanece. | **PARIDADE PARCIAL** |
| **Order review (pedido público)** | `OrderReviewScreen` usa `HiveBoxNames.produtos(lojaId)`, `clientes(lojaId)`, `vendas(lojaId)` e evita abrir boxes quando `lojaId` é nulo (correção já aplicada). | Em Web, `lojaId` pode vir da URL; em APK, de `LojaIdService.getWithTimeout`. Se a URL não tiver loja e o serviço falhar, a tela não abre boxes (comportamento correto), mas a **origem** do `lojaId` é diferente por contexto (link vs app). | **PARIDADE PARCIAL** |
| **Listener de produtos** | `FirestoreCriticalListenerService.startProdutosListener` é chamado em `VendasScreen` (e usado em home); não há `kIsWeb` impedindo sua ativação. | Listener é ativado ao abrir a tela; se o usuário não abrir a tela de vendas no outro dispositivo, não recebe atualizações em tempo real (depende de full/auto sync ou de abrir a tela). | **PARIDADE PARCIAL** |

---

## 4. Pontos com risco de divergência

| Ponto | Arquivo / método | Coleção/Box | Impacto na paridade | Classificação |
|-------|-------------------|-------------|----------------------|----------------|
| **Importação Excel (legado)** | `ExcelImportService.importarVendas` / `importarClientes` usam `Hive.box<Venda>('vendas')` e `Hive.box<Cliente>('clientes')` **sem sufixo de lojaId**. | `'vendas'`, `'clientes'` (boxes genéricas) | Em multi-loja, importação pode gravar na box “global” e não na box da loja ativa; dados podem não bater com o que a tela de vendas/clientes mostra (que usa `HiveBoxNames.*(lojaId)`). Documentação do serviço já alerta: uso apenas em migrações/ambientes controlados. | **FORTE SUSPEITA** |
| **Bootstrap – boxes legadas** | `main.dart` (bootstrap): `openTyped<Cliente>('clientes')`, `openTyped<Venda>('vendas')`, `openTyped<Produto>('produtos')`. | `'clientes'`, `'vendas'`, `'produtos'` | Qualquer código que leia diretamente dessas boxes sem usar `HiveBoxNames.*(lojaId)` pode ver dados misturados ou da loja errada. O comentário no próprio main.dart diz que o fluxo multi-tenant deve usar `HiveBoxNames.*(lojaId)`. Risco é de uso residual ou futuro incorreto. | **FORTE SUSPEITA** |
| **CadastroProdutoScreen só em draft** | `CadastroProdutoScreen._salvarProduto`: `collection('draft_produtos')`, `docRef.set(data)`. Nenhuma escrita em `estoque_produtos`. | `draft_produtos` | Produto criado só por essa tela não entra no Hive de estoque (FullSync lê só `estoque_produtos`). Em outra plataforma, o usuário só verá o produto se houver um fluxo explícito “publicar rascunho” → `estoque_produtos` (ou equivalente). | **CONFIRMADO** (comportamento atual; risco de expectativa errada do usuário) |
| **Web: fallback de abertura de box** | `main.dart` `openTyped`: em `kIsWeb`, em caso de erro ao abrir box tipada, abre `Hive.openBox(name)` (box dinâmica). | Qualquer box que falhe no Web | Pode mascarar incompatibilidade de tipo (ex.: dados salvos por versão antiga) e exibir/comportar diferente do APK que não usa esse fallback. | **FORTE SUSPEITA** |
| **Resolução de loja na URL (Web)** | `main.dart` `_lojaSlugOrIdFromUrl()`: usado para catálogo Web e rotas; retorna `'minha-loja'` quando `!kIsWeb`. | N/A | Admin usa `StoreResolverFacade.resolveForAdminApp()` (não URL). Impacto na paridade admin é nulo; impacto é apenas no catálogo/rotas Web. | **NÃO CONFIRMADO** como quebra de paridade admin |

---

## 5. Bugs invisíveis possíveis entre Web e APK

- **Produto “criado no Web” não aparece no APK**: Se o usuário usar **apenas** `CadastroProdutoScreen` (rascunho) no Web e esperar ver o produto no estoque do APK, não verá, pois o rascunho fica só em `draft_produtos` e o sync principal lê `estoque_produtos`. Não é bug de sync, é desenho: dois fluxos (rascunho vs estoque) com coleções diferentes.
- **Importação Excel em multi-loja**: Se alguém usar `ExcelImportService.importarVendas`/`importarClientes` com mais de uma loja, os dados vão para as boxes `'vendas'`/`'clientes'`. As telas de vendas/clientes leem `HiveBoxNames.vendas(lojaId)` / `HiveBoxNames.clientes(lojaId)`. Pode parecer que “sumiram” vendas/clientes ou que “não sincronizaram”, quando na verdade foram parar na box genérica.
- **Dado “atrasado” em uma plataforma**: Sem listener ativo (ex.: usuário não abriu a tela de vendas), a outra plataforma só atualiza quando rodar full/auto sync (login, reconexão ou botão de sync). Não é bug, mas pode ser percebido como “não refletiu”.
- **OrderReview com lojaId nulo**: Já mitigado (não abre boxes); antes havia risco de abrir boxes genéricas e mostrar dados errados em multi-tenant.

---

## 6. O que depende de sync / refresh / cache

- **Ver alterações feitas em outro dispositivo**  
  - Produtos: FullSync (login, reconexão), AutoSync (login, reconexão, callback da SyncQueue), ou **listener** (ao abrir tela que chama `FirestoreCriticalListenerService.startProdutosListener`).  
  - Vendas: AutoSync (sync Firestore → Hive).  
  - Clientes: FullSync + AutoSync.  
  - Sem novo login/reconexão e sem abrir tela que dispara listener, pode ser necessário **acionar sync manual** (ex.: botão na tela) para ver o que o outro dispositivo gravou.
- **Web**  
  - IndexedDB (Hive) pode persistir entre abas; ao reabrir o app Web, o bootstrap e o sync (se disparado) atualizam. Não há branch que desative AutoSync/FullSync no Web.
- **APK**  
  - Mesmo fluxo de sync; backup automático é apenas no APK (`!kIsWeb`), não afeta paridade de dados de negócio.

---

## 7. Plano curto de correção para garantir paridade total

1. **CadastroProdutoScreen (draft_produtos)**  
   - Deixar explícito na UI que o produto foi salvo como **rascunho** e que, para aparecer no estoque/admin em todas as plataformas, precisa ser “publicado” ou “enviado para estoque” (se existir esse fluxo).  
   - Ou: implementar um passo opcional “também gravar em estoque_produtos” (ou chamar serviço que promova draft → estoque) para que o mesmo produto apareça no FullSync/listener.

2. **ExcelImportService**  
   - Em ambiente multi-tenant: não usar para vendas/clientes em produção sem revisão.  
   - Opcional: refatorar para usar `HiveBoxNames.vendas(lojaId)` e `HiveBoxNames.clientes(lojaId)` com `lojaId` resolvido (ex.: `StoreResolverFacade.resolveForAdminApp()`) e documentar que o import é por loja.

3. **Bootstrap (boxes legadas)**  
   - Manter comentário no main.dart alertando que o fluxo multi-tenant deve usar apenas `HiveBoxNames.*(lojaId)`.  
   - Fazer busca por usos diretos de `'vendas'`, `'clientes'`, `'produtos'` (string) como nome de box e substituir por `HiveBoxNames` quando for fluxo por loja.

4. **Web – fallback de box dinâmica**  
   - Manter fallback se for intencional para compatibilidade; senão, remover ou restringir a um conjunto de boxes conhecidas e logar claramente quando cair no fallback para facilitar diagnóstico.

5. **Observabilidade**  
   - Já existem logs em sync (FullSync, AutoSync, VendasFirestoreService, ProdutosFirestoreService). Manter e, se útil, adicionar um log único quando a escrita for para `estoque_vendas` / `estoque_produtos` / `estoque_clientes` com `lojaId` (para auditoria de paridade).

---

## 8. Veredito final

- **Paridade dos fluxos principais (vendas, produtos via form de estoque, clientes admin, estoque transacional, catálogo/pedido, loja do admin)** está **confirmada** no código: mesma loja (`StoreResolverFacade`), mesmas coleções Firestore e mesmas boxes Hive por loja; sem branch por plataforma que mude destino de leitura/gravação.
- **Paridade parcial** existe em: (1) cadastro de produto que só grava em `draft_produtos`; (2) listener ativo apenas quando a tela é aberta; (3) Order Review com origem de `lojaId` diferente (URL vs LojaIdService), mas com comportamento seguro quando `lojaId` é nulo.
- **Riscos residuais** estão em: (1) uso de boxes legadas na importação Excel em multi-loja; (2) bootstrap que abre boxes genéricas (risco de uso incorreto futuro); (3) expectativa do usuário de que “rascunho” de produto apareça em todas as plataformas sem passo de publicação.

Com as correções sugeridas no plano curto (especialmente esclarecer ou unificar o fluxo draft vs estoque e alinhar Excel à multi-loja), a paridade entre Web, APK e demais plataformas fica sólida para os fluxos que o sistema hoje desenha como “iguais” em todas as plataformas.
