# AUDITORIA FINAL DE PRODUÇÃO — MasterPalm

**Data:** 06/03/2025  
**Versão:** 1.0.28+38  
**Escopo:** Consistência entre plataformas, segurança, sincronização, estabilidade, escalabilidade

---

## 1. RESUMO EXECUTIVO DO ESTADO GERAL

O MasterPalm é um sistema multi-plataforma (Web, APK, Desktop) com arquitetura centralizada em Firestore e Cloud Functions. A base é sólida: Firestore Rules bem definidas, triggers de sincronização (syncPedidoStatusPublico, syncClientePortalProfile, publishLojaDraft), idempotência no webhook MP e isolamento por `lojaId`.

**Pontos fortes:**
- Firestore Rules consistentes com validações anti-abuso
- Cloud Functions com rate limiting e idempotência
- `PedidoCollectionResolver` centralizado para fluxos de pedido
- Fluxo MP webhook atômico (baixa estoque + marca processado)
- Sincronização `pre_pedidos` ↔ `pedido_status_publico`` e `clientes_portal`
- UX de falha de `getClienteCatalog` já revisada (perfil, carrinho, favoritos)

**Pontos de atenção:**
- Hive/cache usa nomes de box diferentes em alguns pontos (risco de loja errada)
- Storage Rules não validam `lojaId` na escrita (qualquer usuário autenticado pode escrever em qualquer loja)
- `FirestoreCatalogProductSource` usa coleções `produtos_live`/`produtos_draft` em vez de `produtos`/`draft_produtos` (inconsistência)
- Sync offline não roda no Web (connectivity listener + cloud_sync desabilitados)
- Índices Firestore para `produtos`, `estoque_vendas`, `clientes` podem faltar em queries compostas

---

## 2. DIAGNÓSTICO DA SINCRONIZAÇÃO WEB / APP / APK / DESKTOP

### 2.1 Fluxo de dados

| Origem | Destino | Mecanismo | Status |
|--------|---------|-----------|--------|
| Web (admin) | Firestore | Direto | ✅ |
| APK (admin) | Firestore | Direto + Hive | ✅ |
| Desktop (admin) | Firestore | Direto + Hive | ✅ |
| Catálogo Web | pre_pedidos | Firestore direct | ✅ |
| pre_pedidos | pedido_status_publico | CF `syncPedidoStatusPublico` | ✅ |
| pre_pedidos | clientes_portal | CF `upsertClientePortalFromPedido` | ✅ |
| clientes | clientes_portal | CF `syncClientePortalProfile` | ✅ |
| draft_produtos | produtos | CF `publishLojaDraft` | ✅ |
| MP webhook | pedidos + estoque | CF `mpWebhookHandler` (transação atômica) | ✅ |
| Venda APK/Web | estoque_produtos | EstoqueTransactionService + VendasFirestoreService | ✅ |
| Hive | Firestore | SyncQueueService, AutoSyncService | ⚠️ Só mobile/desktop (não Web) |

### 2.2 Gaps de sincronização

1. **Web Admin** não usa Hive da mesma forma; em Web, `withData: kIsWeb` força mais uso do Firestore em algumas telas.
2. **Connectivity listener** não inicia no Web (`sync_queue_service.dart` linha ~173), então fila offline não é acionada.
3. **CloudSyncService** não inicia no Web (`cloud_sync_service.dart` linha ~101).
4. **OrderReviewScreen** usa `Hive.box('produtos')` e `Hive.box('clientes')` sem `lojaId`, enquanto `HiveBoxNames` usa `produtos_$lojaId` — risco de usar box errada em multi-loja.

---

## 3. TOP 20 RISCOS REAIS

| # | Risco | Severidade | Onde | Quando | Plataformas |
|---|-------|------------|------|--------|-------------|
| 1 | Storage Rules: qualquer usuário autenticado pode escrever em qualquer loja | **CRÍTICO** | `storage.rules` | Upload de logo/produto | Web, APK |
| 2 | OrderReviewScreen usa Hive `produtos`/`clientes`/`vendas` sem lojaId | **ALTO** | `order_review_screen.dart` | Deep-link de pedido | APK, Desktop |
| 3 | FirestoreCatalogProductSource usa `produtos_live`/`produtos_draft` em vez de `produtos`/`draft_produtos` | **ALTO** | `firestore_catalog_impl.dart` | Se for usado como fonte do catálogo | Web, APK |
| 4 | Falta validação de lojaId na escrita do Storage | **ALTO** | `storage.rules` | Upload em qualquer loja | Web |
| 5 | Índices para coleções `produtos`, `estoque_vendas` podem faltar em queries compostas | **MÉDIO** | `firestore.indexes.json` | Queries com where+orderBy em produtos | Todas |
| 6 | Webhook MP: fallback itera todas as lojas se metadata não vier | **MÉDIO** | `mpWebhookHandler.js` | Payment sem metadata.lojaId | Backend |
| 7 | clientes: update permite qualquer autenticado se `request.resource.data.email == resource.data.email` | **MÉDIO** | `firestore.rules` | Update de cliente | Web, APK |
| 8 | gerarCupomNumeroSorte: campanhas usa coleção `campanhas` (rules usam `campanhas_sorteio`) | **MÉDIO** | `functions/index.js` | Chamada da CF | Backend |
| 9 | Hive no Web: IndexedDB; persistência diferente de mobile | **MÉDIO** | `main.dart`, Hive init | Offline/reload | Web |
| 10 | catalog_thumbnail_service retorna null no Web | **MÉDIO** | `catalog_thumbnail_service.dart` | Thumbnails no catálogo | Web |
| 11 | FCM não disponível no Web; notificações de pedido não chegam | **BAIXO** | `fcm_pedido_service.dart` | Novo pedido | Web |
| 12 | Sync offline não roda no Web | **BAIXO** | `sync_queue_service`, `cloud_sync_service` | Modo offline | Web |
| 13 | firestore.indexes.json tem `products`, `categoria`, `subcategoria` — app usa `produtos`, `categorias` | **BAIXO** | `firestore.indexes.json` | Queries em produtos | Todas |
| 14 | redirectCatalogo: itera todas as lojas para resolver slug | **BAIXO** | `functions/index.js` | Link curto /c/{short} | Backend |
| 15 | portalToken gerado na CF; enumeração possível por tentativa | **BAIXO** | `getClienteCatalog` | Brute force token | Catálogo |
| 16 | draft_produtos e produtos podem divergir entre publish e edição manual | **BAIXO** | Fluxo publish | Edição após rascunho | Admin |
| 17 | mpWebhook cria venda em estoque_vendas mas APK pode não ter sincronizado Hive | **BAIXO** | `mpWebhookHandler`, `auto_sync_service` | Venda catálogo → APK | APK |
| 18 | Relatórios podem ter custo alto com queries amplas | **BAIXO** | `relatorios_screen`, `vendas_screen` | Dashboards | Todas |
| 19 | planWebhook: uid resolvido por email se formato plano_* | **BAIXO** | `functions/index.js` | Pagamento plano | Backend |
| 20 | Catch vazios: alguns `catch (_) {}` sem log nem feedback | **BAIXO** | Diversos | Erros em edge cases | Todas |

---

## 4. ACHADOS POR CATEGORIA

### 4.1 Produtos
- **OK:** Cadastro em `draft_produtos` e `produtos`, sync via `publishLojaDraft`, EstoqueTransactionService baixa estoque.
- **Risco:** FirestoreCatalogProductSource usa `produtos_live`/`produtos_draft` (coleções não usadas no fluxo principal). Se esse source for injetado no PublicCatalogScreen, catálogo ficaria vazio.
- **Risco:** Índices em firestore.indexes.json referem `products`, não `produtos`.

### 4.2 Fotos
- **OK:** generateProductThumbnail processa `produtos` e `draft_produtos`, Storage público para leitura.
- **Risco:** Storage write com `request.auth != null` — sem checagem de lojaId; usuário de loja A pode escrever em loja B.
- **Risco:** catalog_thumbnail_service retorna null no Web.

### 4.3 Vendas
- **OK:** VendasService baixa estoque via EstoqueTransactionService; VendasFirestoreService sync Hive ↔ Firestore; mpWebhookHandler cria venda em estoque_vendas para pre_pedidos pagos.
- **Risco potencial:** Venda do catálogo (pre_pedido → estoque_vendas) depende de sync Firestore→Hive no APK; se APK não sincronizar, Hive pode ficar desatualizado.

### 4.4 Pedidos
- **OK:** pre_pedidos, pedidos_pendentes, pedido_status_publico, clientes_portal sincronizados via CFs; PedidoCollectionResolver centralizado; temp_orders/pedidos_temp/pedido_temp com validação de lojaId nas rules.
- **Risco:** OrderReviewScreen usa Hive boxes sem lojaId.

### 4.5 Clientes
- **OK:** getClienteCatalog valida email; clientes_portal sincronizado via syncClientePortalProfile; create com isValidClienteCreate.
- **Risco:** update em clientes permite `request.resource.data.email == resource.data.email` sem checagem de que o solicitante é o dono do documento.

### 4.6 Estoque
- **OK:** EstoqueTransactionService com baixa atômica; mpWebhookHandler baixa estoque em transação; removerDoCatalogoSeEstoqueZerado em ambos os lados.
- **Risco potencial:** produto com variações — mpWebhook usa productId/slug; se slug vs id divergir, pode não encontrar produto.

### 4.7 Relatórios
- **OK:** Queries por lojaId; índice pre_pedidos com status e dataCriacao.
- **Risco:** Queries com where+orderBy em estoque_vendas, vendas_screen podem exigir índices não declarados.

### 4.8 Firestore Rules
- **OK:** Isolamento por lojaId; belongsToStore; isValid* para writes públicos; rate limits e idempotency protegidos.
- **Risco:** clientes update pode ser permissivo demais.
- **Risco potencial:** list em clientes com limit<=10 sem belongsToStore — comentário indica login/cadastro; verificar se não vaza dados.

### 4.9 Cloud Functions
- **OK:** Rate limiting, idempotência, secrets via Secret Manager, região southamerica-east1.
- **Risco:** gerarCupomNumeroSorte usa `campanhas` (não `campanhas_sorteio`); pode não encontrar campanha ativa.
- **Risco:** redirectCatalogo itera todas as lojas — custo e latência com muitas lojas.

### 4.10 Hive / Cache
- **OK:** HiveBoxNames centraliza nomes; HiveMultiStore usa lojaId; LojaIdService com fallbacks (sessao, config).
- **Risco:** OrderReviewScreen usa `produtos`, `clientes`, `vendas` em vez de HiveBoxNames.produtos(lojaId) etc.
- **Risco:** catalog_helpers fallback Hive `config` quando !kIsWeb para lojaId — pode retornar loja antiga.

### 4.11 UX / Erros silenciosos
- **OK:** UX de falha getClienteCatalog já tratada (perfil, carrinho, favoritos).
- **Risco:** Catch vazios em `catch (_) {}` em vários pontos (auto_sync, full_sync, etc.); sem log, difícil depurar.

### 4.12 Segurança
- **OK:** getClienteCatalog valida email; portalToken só via CF; PII não exposta em pedido_status_publico.
- **Risco:** Storage write sem validação de lojaId.
- **Risco potencial:** portalToken enumeração por tentativa (mitigado por rate limit).

### 4.13 Performance / Custo
- **OK:** limit em queries; idempotência evita reprocessamento.
- **Risco:** redirectCatalogo e findLojaIdByOrderId iteram lojas; custo escala com número de lojas.
- **Risco:** Queries em produtos/estoque_vendas podem precisar índices compostos.

---

## 5. LISTA DE ARQUIVOS MAIS SENSÍVEIS

| Arquivo | Motivo |
|---------|--------|
| `firestore.rules` | Regras de acesso a dados |
| `storage.rules` | Acesso a uploads |
| `functions/index.js` | Lógica server-side, webhooks, sync |
| `functions/src/mpWebhookHandler.js` | Processamento pagamento MP, baixa estoque |
| `lib/services/cliente_auth_service.dart` | getClienteCatalog, carrinho, favoritos |
| `lib/services/estoque_transaction_service.dart` | Baixa de estoque |
| `lib/services/vendas_service.dart` | Registro de vendas |
| `lib/services/vendas_firestore_service.dart` | Sync vendas Hive↔Firestore |
| `lib/services/loja_id_service.dart` | Resolução de loja ativa |
| `lib/services/hive_multi_store.dart` | Boxes Hive por loja |
| `lib/screens/public_catalog/widgets/carrinho_sheet_web.dart` | Checkout catálogo |
| `lib/screens/order_review_screen.dart` | Revisão de pedido, Hive boxes |
| `lib/repositories/pedido_status_publico_repository.dart` | Meus Pedidos |
| `lib/repositories/cliente_portal_repository.dart` | Portal do cliente |
| `lib/catalog/data/firestore_catalog_impl.dart` | Source de produtos (produtos_live/draft) |
| `lib/screens/public_catalog/catalog_helpers.dart` | kLiveProdutosCol = produtos |

---

## 6. PONTOS ONDE A SINCRONIZAÇÃO PODE FALHAR

1. **Hive box incorreta** (OrderReviewScreen): produtos/clientes/vendas sem lojaId.
2. **FirestoreCatalogProductSource**: coleções produtos_live/produtos_draft inexistentes ou vazias.
3. **Web sem sync offline**: fila e cloud sync não rodam; dados locais desatualizados após reload.
4. **Storage**: write sem lojaId pode gravar em loja errada.
5. **MP webhook sem metadata.lojaId**: fallback itera lojas; latência e custo.
6. **gerarCupomNumeroSorte**: coleção `campanhas` vs `campanhas_sorteio` — campanha ativa não encontrada.
7. **draft_produtos vs produtos**: edição manual em ambos pode divergir antes do publish.

---

## 7. ERROS SILENCIOSOS ENCONTRADOS

- `catch (_) {}` em AutoSyncService, LojaIdService, catalog_helpers — sem log.
- OrderReviewScreen: `catch (e)` com apenas `debugPrint` — usuário não recebe feedback em produção.
- Carrinho: `catch (e)` ao buscar endereço — apenas debugPrint; fluxo continua sem aviso.
- syncPedidoStatusPublico, syncClientePortalProfile: `catch (e)` com console.error — OK para server, mas falhas não são reportadas ao cliente.

---

## 8. BUGS CRÍTICOS ESCONDIDOS

1. **OrderReviewScreen Hive boxes**: usa `produtos`, `clientes`, `vendas`; HiveBoxNames usa `produtos_$lojaId`, etc. Em app multi-loja ou quando há migração, pode carregar dados de loja errada ou box vazia.
2. **FirestoreCatalogProductSource**: usa `produtos_live` e `produtos_draft`; o restante do app usa `produtos` e `draft_produtos`. Se esse source for usado, catálogo não encontra produtos.
3. **gerarCupomNumeroSorte**: busca em `campanhas` com `ativa==true`; firestore.rules e fluxo principal usam `campanhas_sorteio` — pode nunca encontrar campanha.

---

## 9. RISCOS DE PRODUÇÃO

| Risco | Impacto | Mitigação sugerida |
|-------|---------|--------------------|
| Storage write cross-store | Vazamento/sobrescrita de arquivos | Validar path lojaId contra users/{uid}.store_id ou lojas/{lojaId}/members |
| OrderReview Hive wrong box | Pedido com produtos/clientes errados | Usar HiveBoxNames com lojaId do pedido |
| FirestoreCatalogProductSource wrong cols | Catálogo vazio | Trocar para `produtos` e `draft_produtos` ou remover uso |
| gerarCupomNumeroSorte wrong col | Cupom/número da sorte não gerados | Usar `campanhas_sorteio` |
| MP webhook sem lojaId | Falha ou demora | Garantir metadata.lojaId em createPreference |

---

## 10. RISCOS DE ESCALABILIDADE

| Ponto | Problema | Quando |
|-------|----------|--------|
| redirectCatalogo | Iteração em todas as lojas | Cada /c/{short} |
| findLojaIdByOrderId | Iteração em todas as lojas | Webhook MP sem metadata |
| Queries produtos/estoque | Falta de índices | Muitos produtos, ordenação |
| Firestore reads por tela | Sem paginação em listas grandes | Relatórios, produtos, clientes |
| Sync Firestore→Hive | Full sync sem cursor | Muitas vendas/produtos |

---

## 11. CHECKLIST DE CORREÇÕES POR PRIORIDADE

### Prioridade 1 — Crítico (antes de escalar)
- [ ] Storage Rules: adicionar validação de que o path inclui lojaId do usuário (members/owner)
- [ ] OrderReviewScreen: usar HiveBoxNames.produtos(lojaId), etc., com lojaId do pedido

### Prioridade 2 — Alto
- [ ] FirestoreCatalogProductSource: trocar `produtos_live`/`produtos_draft` para `produtos`/`draft_produtos`
- [ ] gerarCupomNumeroSorte: usar coleção `campanhas_sorteio` em vez de `campanhas`
- [ ] clientes update rule: restringir a belongsToStore ou self (portalToken/email)

### Prioridade 3 — Médio
- [ ] Índices Firestore: revisar queries em produtos, estoque_vendas, clientes e adicionar índices faltantes
- [ ] mpWebhookHandler: garantir metadata.lojaId em createPreference
- [ ] redirectCatalogo: considerar índice ou coleção de mapeamento slug→lojaId

### Prioridade 4 — Baixo
- [ ] Catch vazios: adicionar log mínimo (logW) nos pontos críticos
- [ ] catalog_thumbnail_service Web: avaliar alternativa (ex.: URL do Storage)
- [ ] Documentar diferenças Web (sem sync offline, sem FCM)

---

## 12. O QUE NÃO MEXER AGORA (evitar regressão)

- **PedidoCollectionResolver** e fluxos de pedido — estáveis.
- **Firestore Rules** de pedidos, pre_pedidos, temp — bem validadas.
- **mpWebhookHandler** — transação atômica e idempotência ok; só ajustar metadata se necessário.
- **syncPedidoStatusPublico** e **syncClientePortalProfile** — funcionando.
- **publishLojaDraft** — fluxo de publicação ok.
- **getClienteCatalog** e UX de falha — já revisados.
- **Estrutura de Hive** (HiveBoxNames, HiveMultiStore) — não alterar nomes sem migração.
- **StoreResolverService** e **LojaIdService** — lógica de resolução complexa; mudanças com cuidado.

---

**Fim do relatório.**
