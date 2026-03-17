# Auditoria completa do sistema MasterPalm

**Tipo:** Análise detalhada, minuciosa e completa de todo o fluxo — auditoria de confiabilidade para produção.  
**Escopo:** Nenhuma implementação ou alteração de arquivos; apenas leitura e classificação com evidência.

---

## 1. VISÃO GERAL DA ARQUITETURA REAL

- **Stack:** Flutter (Web + APK), Firebase (Auth, Firestore, Storage), Hive (persistência local). Multi-tenant por **lojaId** (store_id).
- **Fonte de verdade remota:** Firestore sob `lojas/{lojaId}/` com subcoleções:
  - **estoque_produtos** — produtos/estoque (admin)
  - **estoque_clientes** — clientes admin (sync, stream, CRUD)
  - **estoque_vendas** — vendas (sync, import, delete)
  - **produtos** — catálogo público (espelho de estoque quando publicado)
  - **clientes** — clientes do catálogo/portal (ClienteAuthService, pré-pedido)
  - **clientes_catalogo**, **pre_pedidos**, **estoque_baixa_pagamento**, etc.
- **Fonte de verdade local (por loja):** Hive boxes nomeadas por `HiveBoxNames.*(lojaId)` — `produtos_$lojaId`, `clientes_$lojaId`, `vendas_$lojaId`, `fornecedores_$lojaId`. Boxes genéricas: `sessao`, `config`, `licenca`, `temp_orders`, `notificacoes_centro`, e no bootstrap também abertas com nomes fixos: `clientes`, `vendas`, `produtos`, `estoque`, `fornecedores`, `catalogo`, `config_catalogo`, `usuarios`, `fechamentos_mensais`.
- **Resolução de loja:** Ordem típica: Firestore `users/{uid}.store_id` / `usuarios/{email}.store_id` → Hive `sessao` (store_id, lojaId) → Hive `config` (last_loja_id, store_id). Bootstrap e router aplicam fallbacks (loja_uid_$uid, loja_email_$slug, last_loja_id para root).
- **Autenticação:** Dois fluxos distintos: (1) Admin/dono: Firebase Auth (email/senha, Google), sessão em Hive `sessao` (usuario_logado, tipo_usuario, store_id). (2) Cliente do catálogo: ClienteAuthService (sem Firebase Auth), leitura/escrita em `lojas/{lojaId}/clientes` e `clientes_catalogo`.

---

## 2. MAPA DOS ARQUIVOS CRÍTICOS DO SISTEMA

| Domínio | Arquivos críticos |
|---------|--------------------|
| **Auth / sessão** | `auth_service.dart`, `auth_session.dart`, `session_sanity.dart`, `login_screen.dart`, `cliente_auth_service.dart` |
| **Loja / multi-tenant** | `loja_id_service.dart`, `store_resolver_service.dart`, `store_resolver_facade.dart`, `store_context.dart`, `main.dart` (_ensureStoreIdOnBootstrap), `app_start_router.dart` (_bindActiveStore) |
| **Bootstrap / init** | `main.dart` (_bootstrapSafe, openTyped, openDynamic, resetHiveIfSchemaChanged) |
| **Produtos / cadastro** | `produtos_firestore_service.dart`, `produto_form_screen.dart`, `cadastro_produto_screen.dart`, `estoque_screen.dart`, `estoque_screen_v2.dart`, `catalogo_sync_service.dart` |
| **Estoque** | `estoque_transaction_service.dart`, `estoque_service.dart`, `pos_pagamento_service.dart`, `movimentacao_estoque_service.dart` |
| **Vendas** | `vendas_service.dart`, `vendas_firestore_service.dart`, `importar_vendas_firestore_service.dart`, `vendas_screen.dart`, `reconciliacao_vendas_clientes_service.dart` |
| **Clientes** | `clientes_firestore_service.dart`, `clientes_screen.dart`, `cliente_auth_service.dart`, `models/cliente.dart` |
| **Catálogo / pedidos** | `catalogo_venda_service.dart`, `pre_pedido_service.dart`, `pos_pagamento_service.dart`, `pre_pedidos_screen.dart`, `public_catalog_screen.dart`, `order_review_screen.dart`, `pedido_repository.dart` |
| **Sync** | `full_sync_service.dart`, `sync_queue_service.dart`, `auto_sync_service.dart`, `firestore_critical_listener_service.dart`, `produto_auto_sync_service.dart` |
| **Hive / boxes** | `core/hive_box_names.dart`, `hive_multi_store.dart`, `main.dart` (openTyped/openDynamic) |
| **Relatórios / leituras** | `relatorios_screen.dart`, `relatorio_financeiro_screen.dart`, `relatorio_ranking_clientes_screen.dart`, `historico_clientes_screen.dart` |
| **Legado / risco** | `excel_import_service.dart`, `admin_painel_web_screen.dart`, `utils/migrar_para_estoque.dart`, `utils/limpar_firestore.dart`, `services/firestore_cleanup_script.dart` |

---

## 3. FLUXO REAL DE AUTENTICAÇÃO E CONTEXTO DE LOJA

- **Quem é o usuário atual (admin):** Firebase Auth `currentUser`; Hive `sessao` guarda `usuario_logado`, `tipo_usuario`, `store_id`. AuthService (Provider) expõe usuário; login_screen após login grava em sessão e pode gravar store_id vindo de Firestore ou fallback loja_uid_$uid.
- **Vínculo usuário → loja:** StoreResolverService lê `users/{uid}.store_id` ou `usuarios/{email}.store_id`; persiste em Hive (sessao, config) e em StoreContext. LojaIdService.get() usa StoreResolverFacade → sessao → config.
- **Onde pode falhar:** (1) Timeout no resolve (Web 6s, router) → fallback sessão/config; se sessão tiver store_id de outro usuário (troca de conta no mesmo dispositivo), esse valor pode ser reutilizado. (2) LojaIdService: vários `catch (_) {}` (loja_id_service.dart L65, 75, 85, 102, 110, 118, 177, 184) — falha ao abrir box ou ao resolver vira null silenciosamente. (3) Bootstrap sem usuário: SessionSanity.fixIfNoFirebaseUser() limpa store_id/usuario_logado; _ensureStoreIdOnBootstrap usa fallback loja_uid_$uid se resolve retornar null.
- **Fallback perigoso:** Router usa sessao.get('store_id') e config.get('last_loja_id') sem validar se pertencem ao currentUser — **CONFIRMADO** risco de reutilizar loja de outro usuário em troca de conta + timeout.
- **Estado inconsistente auth vs store_id:** Se o usuário deslogar em outra aba e a atual não for atualizada, sessão local pode manter store_id até próximo carregamento ou logout local. SessionSanity.clearAllStoreCache() e AuthSession.signOutAndGoToLogin limpam sessao/config ao sair.

**Classificação:** Vínculo usuário–loja **CONFIRMADO** via Firestore + Hive; fallback de sessão no router **CONFIRMADO** como risco residual (store_id de outro usuário). LojaIdService retornar null por catch silencioso **CONFIRMADO**.

---

## 4. FLUXO REAL DE PRODUTOS E CADASTRO

- **Cadastro/edição:** produto_form_screen / cadastro_produto_screen / estoque_screen montam ou editam `Produto`; salvam no Hive na box `HiveBoxNames.produtos(lojaId)`; em seguida chamam ProdutosFirestoreService.syncProduto(p, lojaId) que grava em `lojas/{lojaId}/estoque_produtos` e, se publicado, atualiza `lojas/{lojaId}/produtos`.
- **Onde grava local:** Hive box `produtos_$lojaId` via `produto.save()` (HiveObject).
- **Onde grava remoto:** ProdutosFirestoreService: `estoque_produtos` (set completo); opcionalmente `produtos` (update de quantidade/variacoes quando publicado).
- **Fonte autoritativa:** Comentários e uso em estoque_transaction_service e full_sync indicam **estoque_produtos** como fonte de estoque; **produtos** é catálogo (espelho).
- **Duplicidade de escrita:** EstoqueService._sincronizarComFirestore (após FASE 3) não chama mais syncProduto em duplicata; apenas update em estoque_produtos e produtos. ProdutosFirestoreService.syncProduto ainda faz set em estoque_produtos + update em produtos quando publicado — uma escrita por destino por chamada.
- **Risco de sobrescrever produto correto:** Resolução por slug/id é estável; por nome já foi endurecida (falha se múltiplos). Cadastro usa lojaId do contexto (StoreContext/LojaIdService); se lojaId estiver errado, grava na loja errada — **CONFIRMADO** dependência do contexto de loja.

---

## 5. FLUXO REAL DE ESTOQUE

- **Saldo autoritativo:** Firestore `lojas/{lojaId}/estoque_produtos` (quantidade, variacoes, estoquePorTamanho). Hive é cache por loja; atualizado após transação via EstoqueTransactionService.atualizarHiveAposTransacao.
- **Quem baixa:** (1) VendasService.salvarVenda — baixarEstoqueTransactionBatch antes de criar venda no Hive. (2) CatalogoVendaService — baixarEstoqueTransactionBatch antes de criar venda e sync. (3) PosPagamentoService._baixarEstoque — antes de marcar "pago"; idempotência por estoque_baixa_pagamento/{vendaId}. (4) EstoqueService (ajuste manual) — _sincronizarComFirestore atualiza estoque_produtos a partir do Produto local.
- **Confirmar sem baixar:** Pós-pagamento foi corrigido (baixa antes de status; falha propaga). Caso "nenhum item válido" agora lança exceção (FASE 4). **CONFIRMADO** que não há fluxo que marque conclusão de venda/pagamento sem baixa quando há itens válidos.
- **Dupla baixa:** Idempotência no pós-pagamento por marcador; venda manual e catálogo não reprocessam a mesma venda. **CONFIRMADO** mitigado.
- **Overwrite:** Sync manual (EstoqueService) reflete estado local; se local estiver desatualizado (ex.: venda em outra aba), pode sobrescrever — **MITIGADO** por documentação, não por bloqueio.
- **Web e APK:** Mesma lógica de baixa (EstoqueTransactionService, PosPagamentoService); sem branch por plataforma no fluxo de estoque.

---

## 6. FLUXO REAL DE VENDAS

- **Ordem real (venda manual):** VendasService: monta itens → baixarEstoqueTransactionBatch (Firestore) → atualizarHiveAposTransacao → MovimentacaoEstoqueService.registrar → cria Venda → vendasBox.add(venda) → sync cliente → VendasFirestoreService.syncVenda → estoque_vendas. Venda só é adicionada ao Hive **após** baixa bem-sucedida.
- **Venda salvar sem estoque consistente:** Não no fluxo manual: se a transação de estoque falhar, Exception impede add(venda). **CONFIRMADO**.
- **Venda no Hive mas não no Firestore:** Possível: syncVenda pode falhar (rede, permissão); erro é logado e enfileirado (SyncQueueService). Usuário pode ver venda local sem ver no outro dispositivo até sync.
- **Venda no Firestore mas não no Hive:** Possível se outro dispositivo/canal gravou em estoque_vendas e o local ainda não rodou syncFirestoreToHive. ImportarVendasFirestoreService / syncFirestoreToHive puxam de estoque_vendas.
- **Duplicação:** syncVenda usa merge por vendaId; idFirebase reutilizado em edição (idFirebaseToReuse). Sem idempotência por operação de sync — retentativas podem reenviar a mesma venda (merge atenua).

**Escrita de vendas:** VendasFirestoreService grava em `lojas/{storeId}/estoque_vendas` (L86-92). admin_painel_web_screen lê de `lojas/{lojaId}/vendas` — **CONFIRMADO** divergência: painel Web usa coleção **vendas** (antiga), não estoque_vendas.

---

## 7. FLUXO REAL DE CLIENTES

- **Admin:** ClientesFirestoreService — streamClientes, getCliente, searchClientes, syncCliente, syncFirestoreToHive, deleteCliente usam **estoque_clientes**. Hive: box `clientes_$lojaId`. Sync e escrita unificados em estoque_clientes (pós FASE 3 Nova Venda).
- **Portal/catálogo:** ClienteAuthService e pre_pedido_service usam `clientes` e `clientes_catalogo` em vários pontos. Cadastro de cliente no catálogo, login de cliente, cupons — coleção **clientes** sob lojas/{lojaId}.
- **Fonte única:** Não. Admin = estoque_clientes (Hive clientes_$lojaId + Firestore estoque_clientes). Portal = clientes / clientes_catalogo. Coexistência intencional; risco é criar cliente em um e esperar no outro sem migração.
- **Sumiço/inconsistência:** Se uma tela admin antiga ou script ler de `clientes` em vez de estoque_clientes, veria dados diferentes. ClientesFirestoreService está unificado em estoque_clientes; ClienteAuthService e pre_pedido_service continuam em clientes — **CONFIRMADO** arquitetura dupla documentada.

---

## 8. FLUXO REAL DE CATÁLOGO / PEDIDOS / PRÉ-PEDIDOS

- **Pedido vira venda:** Em pre_pedidos_screen, ao confirmar pedido: chama CatalogoVendaService (ou fluxo equivalente) que cria Venda no Hive (vendas_$lojaId), sync em estoque_vendas, e em seguida PosPagamentoService.processarConfirmacaoPagamento (baixa, status "pago", notificações). A venda já existe no Hive antes do pós-pagamento; o pós-pagamento baixa estoque (idempotente), marca pago e dispara efeitos.
- **Quando a baixa acontece:** No pós-pagamento: primeiro checa idempotência, depois _baixarEstoque (transação), grava marcador, depois _atualizarStatusVenda. Em fluxo de catálogo direto (CatalogoVendaService.registrarVendaCatalogo): baixa antes de criar venda no Hive.
- **Falha silenciosa:** PosPagamentoService hoje propaga falha de baixa (return false); caller exibe erro. Outros efeitos (notificação, número da sorte) podem falhar em catch sem rethrow — falha não bloqueia o fluxo principal.
- **Divergência catálogo vs admin:** Vendas do catálogo vão para a mesma box vendas_$lojaId e estoque_vendas; admin (vendas_screen) lê a mesma box. Catálogo e admin compartilham lojaId; diferença é só origem do pedido (carrinho web vs venda manual).

---

## 9. FLUXO REAL DE PÓS-PAGAMENTO

- **Ordem:** (1) Consulta estoque_baixa_pagamento/{vendaId}. (2) Se baixa não aplicada: _baixarEstoque (pode lançar) → grava marcador baixaAplicada: true. (3) _atualizarStatusVenda. (4) Número da sorte, campanha, roleta, notificações.
- **Segurança:** Baixa antes de status; falha na baixa impede marcação "pago" e retorno false. **CONFIRMADO**.
- **Idempotência:** Apenas a baixa: marcador evita segunda baixa. Status, número da sorte e notificações **são reexecutados** em retry — **CONFIRMADO**; aceitável (evita dupla baixa).
- **Efeito colateral duplicável:** Número da sorte e notificações podem ser gerados/enviados de novo em retry. Não há idempotência por vendaId para esses efeitos.
- **Inconsistência residual:** Se _atualizarStatusVenda falhar após baixa bem-sucedida, pedido fica com estoque baixado mas status não "pago" no Firestore/Hive — cenário raro; não há rollback de estoque nesse caso.

---

## 10. FLUXO REAL DE SINCRONIZAÇÃO

- **Local → remoto:** ProdutosFirestoreService.syncProduto / syncTodosProdutos; ClientesFirestoreService.syncCliente; VendasFirestoreService.syncVenda; SyncQueueService (retry com enqueue).
- **Remoto → local:** ProdutosFirestoreService.syncFirestoreToHive; ClientesFirestoreService.syncFirestoreToHive; VendasFirestoreService.syncFirestoreToHive; ImportarVendasFirestoreService.importar; FullSyncService (produtos + clientes de estoque_*); FirestoreCriticalListenerService (listener estoque_produtos → sync Hive).
- **FullSyncService:** Ao trocar de loja (cachedLojaId != lojaIdAtual), limpa e fecha apenas as boxes **produtos** e **clientes** da loja antiga (L80); **não** limpa vendas_$cachedLojaId. Atualiza sessao last_synced_loja_id e last_sync_timestamp.
- **Apagar dado válido:** FullSyncService.clear() nas boxes antigas pode apagar dados locais da loja anterior ao trocar de loja — comportamento intencional para evitar mistura. Não há clear genérico que apague "tudo" sem critério de loja.
- **Manter dado velho:** Se sync Firestore→Hive falhar (rede, catch silencioso), Hive fica desatualizado. firestore_critical_listener_service em catch só faz debugPrint — **CONFIRMADO** erro de sync não propagado.
- **Sobrescrita perigosa:** EstoqueService._sincronizarComFirestore escreve em estoque_produtos a partir do Produto local; se local estiver desatualizado, sobrescreve. Sync de vendas/clientes (Firestore→Hive) faz merge/put por doc; não há putAll de lista vazia no fluxo auditado que apague vendas/clientes válidos (conforme auditoria FASE 3/4 Nova Venda).

---

## 11. ONDE WEB E APK USAM O MESMO FLUXO

- Serviços de negócio: ProdutosFirestoreService, ClientesFirestoreService, VendasFirestoreService, EstoqueTransactionService, VendasService, CatalogoVendaService, PosPagamentoService, LojaIdService, StoreResolverService (lógica de resolução). Sem branch por plataforma na regra de estoque, vendas ou clientes.
- Coleções e boxes: Mesmas coleções Firestore (estoque_*); mesmas HiveBoxNames.*(lojaId). Telas principais (vendas_screen, clientes_screen, estoque_screen, pre_pedidos_screen) usam os mesmos serviços e boxes.

---

## 12. ONDE WEB E APK DIVERGEM

- **main.dart:** kIsWeb para URL strategy, App Check (Web soft-fail), Crashlytics não-Web, FCM/NotificacaoService não-Web, Hive init (sem dirPath no Web), rota catálogo por path. Bootstrap: _ensureStoreIdOnBootstrap e _lojaSlugOrIdFromUrl só relevantes no Web para catálogo.
- **app_start_router:** timeout 6s (Web) vs 3s (não-Web) para resolver loja.
- **Persistência:** Web usa IndexedDB (Hive); APK usa filesystem. Comportamento de abertura/fechamento de boxes é o mesmo; recuperação após refresh no Web depende de IndexedDB e de sessão (store_id) ter sido gravada antes.
- **Riscos exclusivos Web:** Cold start Firestore mais lento → mais chance de timeout no resolve → uso de fallback sessão/config (podendo ser loja antiga). Refresh pode limpar estado em memória mas sessão/config persistem em IndexedDB — se store_id estiver errado, permanece até novo login ou correção.

---

## 13. CAUSAS RAIZ CONFIRMADAS

| Causa | Arquivo / método | Evidência | Impacto |
|-------|------------------|-----------|---------|
| Box genérica **'vendas'** em relatórios | relatorios_screen.dart L46 | `final vendasBox = Hive.box<Venda>('vendas');` | Lista vendas da box global, não por loja; multi-tenant incorreto. **CONFIRMADO** |
| Fallback para box **'vendas'** em erro | relatorio_financeiro_screen.dart L99-101 | `catch (e) { vendasBox = Hive.box<Venda>('vendas'); }` | Se abrir vendas_$lojaId falhar, usa box genérica; dados podem ser de outra loja ou misturados. **CONFIRMADO** |
| Cliente usa box **'vendas'** quando lojaId vazio | models/cliente.dart L63-67, 71-72 | `_vendasBoxName` retorna `'vendas'` se lojaId e boxName vazios; `adicionarHistorico` usa essa box | Histórico de cliente pode ser gravado na box global. **CONFIRMADO** |
| Admin painel Web lê coleção **vendas** (antiga) | admin_painel_web_screen.dart L49-52, L76-79 | `.collection('vendas').get()` sob lojas/{lojaId} | Vendas do admin estão em estoque_vendas; painel não mostra vendas sincronizadas. **CONFIRMADO** |
| LojaIdService falha em silêncio | loja_id_service.dart L65, 75, 85, 102, 110, 118, 177, 184 | `catch (_) {}` em get(), getWithTimeout(), set(), clear() | Retorno null ou falha de persistência sem feedback. **CONFIRMADO** |
| Router pode reutilizar store_id de outro usuário | app_start_router.dart L532-543 | Fallback sessao.get('store_id') / config.get('last_loja_id') sem validar currentUser | Em troca de conta + timeout, loja antiga pode ser usada. **CONFIRMADO** |
| Listener crítico de produtos não propaga erro | firestore_critical_listener_service.dart ~L60-62 | catch (e) { debugPrint(...) } em _syncProdutosOnChange | Sync Firestore→Hive de produtos pode falhar sem UI ou retry visível. **CONFIRMADO** |
| ExcelImportService usa boxes sem loja | excel_import_service.dart L20, 50, 87 | Hive.box<EstoqueItem>('estoque'), Hive.box<Venda>('vendas'), Hive.box<Cliente>('clientes') | Conflito com modelo multi-loja; importação grava em box global. **CONFIRMADO** |

---

## 14. FORTES SUSPEITAS

| Suspeita | Onde | Motivo | Classificação |
|----------|------|--------|----------------|
| Bootstrap abre boxes genéricas que podem ser usadas por engano | main.dart L1446-1454 | openTyped('clientes'), openTyped('vendas'), openTyped('produtos'), openTyped('estoque') — mesmo nome que HiveBoxNames.*(lojaId) gera para outra loja (ex.: produtos_lojaX vs produtos) | **FORTE SUSPEITA** de confusão: código que espera box por loja pode receber box genérica se houver bug de parâmetro |
| syncTodasVendas usa boxName passado pelo caller | admin_sync_screen / outros | Se alguém passar boxName = 'vendas', sync escreveria em estoque_vendas com dados da box global | **FORTE SUSPEITA** — depende de quem chama; VendasFirestoreService.syncVenda usa lojaId e box da venda |
| Relatório financeiro com lojaId vazio | relatorio_financeiro_screen.dart L88-90 | lojaId = LojaIdService.getWithTimeout() ?? sessao.store_id ?? ''; vendasBoxName = HiveBoxNames.vendas(lojaId) → se lojaId vazio, vira 'vendas_' | **FORTE SUSPEITA** — box 'vendas_' pode não existir ou ser vazia; em catch cai em 'vendas' genérica |
| StoreResolverService.set falha em silêncio ao persistir Hive | store_resolver_service.dart L260, 265 | catch (_) {} ao escrever em sessao/config | **FORTE SUSPEITA** — store_id pode não ser persistido e próximo get depender de Firestore |
| Múltiplos pontos usando collection('clientes') no portal | cliente_auth_service, pre_pedido_service, cadastro_screen, etc. | Admin unificado em estoque_clientes; portal continua em clientes — risco de expectativa errada em integrações | **FORTE SUSPEITA** de confusão em novos desenvolvimentos |

---

## 15. NÃO CONFIRMADO

- **IndexedDB no Web perdendo boxes após refresh:** Comportamento depende do Hive/Flutter Web; não há evidência no código de perda sistemática. **NÃO CONFIRMADO**.
- **Race entre router e telas que leem LojaIdService:** Telas usam getWithTimeout(10s); router pode ainda não ter gravado sessão. Possível tela abrir com lojaId null e exibir erro — comportamento esperado; não confirmado como bug de dados. **NÃO CONFIRMADO**.
- **Uso atual de ExcelImportService em produção:** Não há evidência de chamada em telas principais; pode ser script/legado. **NÃO CONFIRMADO**.
- **limpar_firestore ou firestore_cleanup_script apagando estoque_* por engano:** limpar_firestore.dart usa estoque_vendas e vendas; firestore_cleanup_script referencia coleções antigas. Não confirmado se são usados em produção contra projeto errado. **NÃO CONFIRMADO**.

---

## 16. ERROS SILENCIOSOS MAPEADOS

| Onde | Padrão | Evidência | Impacto |
|------|--------|-----------|---------|
| loja_id_service.dart | catch (_) {} em get, getWithTimeout, set, clear | Vários blocos | lojaId null ou falha de persistência sem mensagem |
| store_resolver_service.dart | catch (_) {} ao persistir em Hive | L260, 265 | store_id não gravado localmente |
| firestore_critical_listener_service.dart | catch (e) { debugPrint } em _syncProdutosOnChange | ~L60-62 | Sync produtos falha sem retry/UI |
| full_sync_service.dart | catch (_) {} ao limpar boxes antigas | L88 | Falha ao limpar cache de loja antiga ignorada |
| auto_sync_service.dart | catch (_) {} ao obter lojaId | L76 | Sync automático pode não rodar sem feedback |
| produtos_firestore_service.dart | catch (_) {} ao buscar existente por slug | L253, 260 | Continua com existente null |
| estoque_transaction_service.dart | catch (_) {} ao atualizar ref estoque_produtos na transação; ao remover do catálogo | L203, 491 | Operação secundária falha em silêncio |
| MovimentacaoEstoqueService.registrar | catch (e) { debugPrint } | Não bloqueia fluxo | Histórico de movimentação pode faltar |
| SessionSanity.clearAllStoreCache | catch (e) { debugPrint } | L74-76 | Falha ao limpar cache no logout |
| VendasService / ClientesFirestoreService sync | try/catch com onSyncError ou log | Callback ou log | Usuário pode não ver que sync falhou |

---

## 17. PONTOS MAIS PERIGOSOS DO SISTEMA HOJE

1. **Relatórios e relatório financeiro usando box 'vendas' (genérica)** — Leitura/escrita de vendas sem isolamento por loja; fallback em catch para 'vendas' piora o risco. **Arquivos:** relatorios_screen.dart, relatorio_financeiro_screen.dart.
2. **Cliente.adicionarHistorico com lojaId/boxName vazios** — Grava em box 'vendas'. **Arquivo:** models/cliente.dart.
3. **Admin painel Web lendo coleção 'vendas'** — Divergência com estoque_vendas; painel desatualizado ou vazio. **Arquivo:** admin_painel_web_screen.dart.
4. **Router fallback sessão/config sem validar usuário** — Loja errada após troca de conta. **Arquivo:** app_start_router.dart.
5. **ExcelImportService gravando em 'estoque', 'vendas', 'clientes'** — Qualquer uso em produção mistura dados de lojas. **Arquivo:** excel_import_service.dart.
6. **Bootstrap abrindo boxes com nomes 'vendas', 'clientes', 'produtos', 'estoque'** — Código que usa HiveBoxNames.*(lojaId) pode, por bug, passar string vazia e acabar em nome inconsistente; além disso existe abertura explícita de boxes genéricas que podem ser usadas por relatórios/legado. **Arquivo:** main.dart.
7. **LojaIdService retornar null silenciosamente** — Telas que dependem de lojaId exibem erro "Não foi possível resolver loja"; mas serviços chamados sem checagem podem operar com null/string vazia. **Arquivo:** loja_id_service.dart.
8. **FullSyncService limpando apenas produtos e clientes ao trocar loja** — Vendas da loja antiga permanecem na box vendas_$cachedLojaId (box pode continuar aberta com dados antigos em memória). Comportamento pode ser intencional; risco é usar vendas de outra loja se lojaId estiver trocada mas box não. **Arquivo:** full_sync_service.dart.

---

## 18. RISCOS DE REGRESSÃO CASO MEXA ERRADO

- **Alterar ordem no router (bindActiveStore):** Colocar _atualizarStatusVenda ou qualquer efeito antes da resolução/gravação de loja pode fazer telas montarem com contexto vazio ou antigo.
- **Remover fallback de sessão no router:** Em Web com timeout, usuário pode ficar sem loja e ver "dados sumiram"; é mitigação, não causa raiz.
- **Unificar clientes em uma única coleção sem migração:** Quebra portal e fluxos que escrevem em `clientes` e `clientes_catalogo`.
- **Trocar estoque_vendas por vendas em todo o app:** admin_painel_web e scripts que ainda usam `vendas` deixariam de bater com o resto; é preciso migrar leituras e depois descontinuar `vendas`.
- **Alterar FullSyncService para limpar também vendas_$cachedLojaId:** Pode apagar vendas locais que ainda não foram sincronizadas (ex.: offline). Avaliar se há flag "já sincronizado" antes de clear.
- **Endurecer LojaIdService.get() para lançar em falha:** Pode quebrar telas que não tratam exceção; preferível retornar null e garantir que todas as telas tratem null (já feito em vendas_screen, clientes_screen).
- **Remover boxes genéricas do bootstrap:** Pode quebrar relatorios_screen, relatorio_financeiro_screen, ExcelImportService e Cliente.vendasBoxName legado até serem migrados para boxes por loja.

---

## 19. PRIORIDADE DE INVESTIGAÇÃO / CORREÇÃO

| Prioridade | Item | Ação sugerida |
|------------|------|----------------|
| **Crítica** | Relatórios e relatório financeiro usando box 'vendas' | Usar HiveBoxNames.vendas(lojaId) e nunca fallback para 'vendas'; garantir lojaId válido antes de abrir box |
| **Crítica** | admin_painel_web_screen coleção 'vendas' | Migrar leitura para estoque_vendas ou marcar tela como legada e avisar que dados vêm de outra fonte |
| **Alta** | Cliente._vendasBoxName retornar 'vendas' | Evitar chamadas com lojaId/boxName vazios; ou lançar/retornar erro em vez de 'vendas' |
| **Alta** | Router fallback sem validar currentUser | Opcional: ao usar fallback sessão/config, logar uid atual; em troca de conta, considerar limpar sessão (complexo) |
| **Alta** | LojaIdService catch (_) {} | Pelo menos logar falha (warning); manter retorno null para não quebrar callers |
| **Média** | Firestore critical listener não propagar erro | Log estruturado + opcional retry ou flag "última sync falhou" para UI |
| **Média** | ExcelImportService boxes genéricas | Descontinuar ou adaptar para receber lojaId e usar HiveBoxNames.*(lojaId) |
| **Média** | SessionSanity / StoreResolver set em catch | Logar erro ao persistir; não obrigatório relançar se fluxo principal continuar |
| **Baixa** | Bootstrap abrir boxes genéricas | Documentar que são legado; a longo prazo migrar relatórios e remover abertura se nada usar |

---

## 20. VEREDITO FINAL DA SAÚDE TÉCNICA DO SISTEMA

- **Pontos sólidos:** Multi-tenant por lojaId está bem definido na maior parte do código (HiveBoxNames, estoque_*, fluxos de venda, estoque, pós-pagamento). Venda manual e catálogo garantem baixa antes de gravar venda. Pós-pagamento com idempotência e baixa antes de status. Clientes admin unificados em estoque_clientes. Sessão e store_id são limpos no logout (SessionSanity, AuthSession).
- **Riscos confirmados:** Uso de box genérica **'vendas'** em relatórios e fallback no relatório financeiro; modelo Cliente com fallback para box 'vendas'; admin_painel_web lendo coleção **vendas** em vez de estoque_vendas; router reutilizando store_id de sessão sem validar usuário; LojaIdService e outros com catch silencioso; ExcelImportService com boxes sem loja.
- **Riscos mitigados ou residuais:** Fallback de sessão no router é mitigação para Web; troca de usuário pode reutilizar loja (risco aceitável com monitoramento). Dupla coleção clientes vs estoque_clientes é conhecida e documentada. Sync manual de estoque pode sobrescrever (documentado).
- **Conclusão:** O sistema está **utilizável em produção** para o fluxo principal (login → resolução de loja → produtos, estoque, vendas, clientes, catálogo, pós-pagamento) com as correções já feitas nas fases anteriores (Nova Venda e Estoque). A **saúde técnica** sofre com: (1) relatórios e relatório financeiro em modo multi-tenant incorreto (box 'vendas'); (2) painel Web admin desalinhado da coleção oficial de vendas; (3) legado (ExcelImportService, fallback Cliente, boxes genéricas no bootstrap) e (4) erros silenciosos em resolução de loja e em listener de produtos. Recomendação: tratar como **crítico** a migração dos relatórios e do painel Web para o modelo por loja e coleção estoque_vendas; em seguida endurecer LojaIdService e listener com logs e, se possível, feedback de falha; por fim descontinuar ou adaptar ExcelImportService e fallback de Cliente para evitar uso acidental da box 'vendas'.

---

*Auditoria realizada sem alteração de código; todas as conclusões estão baseadas em evidência objetiva (arquivo, método, linha ou trecho descrito).*
