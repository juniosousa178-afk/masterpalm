# FASE 1 — AUDITORIA FORENSE: Nova Venda / Vendas / Clientes / Loja (MasterPalm)

**Modo:** Forense de produção — apenas evidência no código. Nenhuma alteração implementada.

---

## 1. MAPA DOS ARQUIVOS CRÍTICOS

### A. VENDAS

| Arquivo | Evidência no código |
|---------|---------------------|
| `lib/screens/vendas_screen.dart` | Resolve `lojaId` com `LojaIdService.getWithTimeout(10s)` (L106); se null/vazio seta `_erroResolucaoLoja = true` (L108-115); abre `HiveBoxNames.vendas(lojaId)`, `clientes(lojaId)`, `produtos(lojaId)` (L122-128); lista = `vendasBox.values.where((v) => v.lojaId == lojaId)`; sync em background chama `ImportarVendasFirestoreService.importar`, `ClientesFirestoreService.syncFirestoreToHive`, etc. (L158-201). |
| `lib/screens/nova_venda_modal.dart` | Recebe `produtosBox`, `clientesBox`, `vendasBox`, `lojaId` do caller; chama `VendasService.registrarVendaMulti`; não usa `kIsWeb`. |
| `lib/services/vendas_service.dart` | `registrarVendaMulti` exige `lojaId` (L254-256); grava Hive `vendasBox.add(venda)`; chama `VendasFirestoreService.syncVenda(venda, lojaId)` e `ClientesFirestoreService.syncCliente(cliente, lojaId)`. |
| `lib/services/vendas_firestore_service.dart` | `syncVenda`: grava em `lojas/{storeId}/estoque_vendas` (L86-91). `syncFirestoreToHive`: lê de `lojas/{lojaId}/estoque_vendas` (L169-174). `streamVendas`: lê de `estoque_vendas` (L271). Único caminho Firestore para vendas = `estoque_vendas`. |
| `lib/services/importar_vendas_firestore_service.dart` | Lê de `lojas/{lojaId}/estoque_vendas` (L61-64); importa para a `Box<Venda>` passada (por loja). |

### B. CLIENTES

| Arquivo | Evidência no código |
|---------|---------------------|
| `lib/services/clientes_firestore_service.dart` | **Escrita:** `syncCliente` e `syncFirestoreToHive` e `deleteCliente` usam `estoque_clientes` (L44, 97, 169, 234, 292). **Leitura:** `streamClientes` usa `collection('clientes')` (L256); `getCliente` usa `collection('clientes')` (L272); `searchClientes` usa `collection('clientes')` (L317, 327). Comentário em L283: "Deleta um cliente do Firestore (estoque_clientes = mesma coleção usada pelo sync)". |
| `lib/screens/clientes_screen.dart` | Abre `HiveBoxNames.clientes(lojaId)`, `vendas(lojaId)` (L142-143); lista vem do Hive; sync chama `ClientesFirestoreService.syncFirestoreToHive` (estoque_clientes) e `VendasFirestoreService.syncFirestoreToHive`. Não chama `streamClientes`, `getCliente` nem `searchClientes`. |
| Uso de getCliente/searchClientes | Grep: **nenhum** `.getCliente(` ou `.searchClientes(` em todo o `lib`. Ou seja: hoje a lista de clientes no admin não depende desses métodos; depende de Hive + syncFirestoreToHive(estoque_clientes). A divergência de coleção é **latente** (risco futuro ou outros fluxos). |

### C. LOJA / MULTI-TENANT / CONTEXTO

| Arquivo | Evidência no código |
|---------|---------------------|
| `lib/main.dart` | `_ensureStoreIdOnBootstrap`: se sessao/config não têm `store_id`, define `lojaId = 'loja_uid_$uid'` (L737) ou `loja_email_${_safeSlug(u)}` (L743-745); grava em sessao e config (L757-759). **Não** chama `StoreResolverService.resolve()`; usa apenas uid/email. Ordem: openDynamic('sessao','config') → openTyped('clientes','vendas','produtos','fornecedores') → _ensureStoreIdOnBootstrap (L1322-1329, L1417-1436). |
| `lib/screens/app_start_router.dart` | `_bindActiveStore`: chama `StoreResolverFacade.resolveForRouter(baseUri).timeout(Duration(seconds: 3), onTimeout: () => null)` (L514-518). Se `loja == null`: só root usa `config.get('last_loja_id')`; senão **return sem gravar** (L527-530). Se loja != null: `sessao.put('store_id', loja)` etc (L534-540); depois `StoreResolverService.set(loja).timeout(2s)` (L544-547). |
| `lib/services/store_resolver_service.dart` | `resolve()`: 1) cache por UID; 2) Firestore `users/{uid}.store_id`; 3) mapa `_uidToLoja`; 4) Firestore `usuarios/{email}.store_id`; 5) Hive sessão; 6) `_makeSlugFromEmail`. `set(storeId)`: **bloqueado** — só chama `resolve()` (L236-246). `_persist(lojaFixa)`: grava em sessao e config (L305-314). |
| `lib/services/loja_id_service.dart` | `get()`: 1) `StoreResolverFacade.resolveForAdminApp()`; 2) Hive sessao (store_id, lojaId, storeId); 3) Hive config. `getWithTimeout(10s)`: mesmo fluxo com timeout; em timeout retorna null e depois tenta Hive sessao/config. |

### D. FIRESTORE — CAMINHOS REAIS

| Uso | Coleção/caminho | Arquivo:linha |
|-----|------------------|---------------|
| Gravar venda | `lojas/{storeId}/estoque_vendas` | vendas_firestore_service.dart:86-91 |
| Ler vendas (sync → Hive) | `lojas/{lojaId}/estoque_vendas` | vendas_firestore_service.dart:169-174, importar_vendas_firestore_service.dart:61-64 |
| Gravar cliente (sync) | `lojas/{storeId}/estoque_clientes` | clientes_firestore_service.dart:94-98, 169 |
| Ler clientes (sync → Hive) | `lojas/{lojaId}/estoque_clientes` | clientes_firestore_service.dart:167-172 |
| Ler clientes (stream/get/search) | `lojas/{storeId}/clientes` | clientes_firestore_service.dart:256, 272, 317, 327 |
| Deletar cliente | `lojas/{storeId}/estoque_clientes` | clientes_firestore_service.dart:288-293 |

### E. HIVE / BOXES

| Box | Uso | Evidência |
|-----|-----|-----------|
| `vendas_$lojaId` | VendasScreen, ImportarVendas, sync, relatórios, etc. | HiveBoxNames.vendas(lojaId) em vendas_screen (L122-126), clientes_screen, historico_clientes_screen, catalogo_venda_service, auto_sync_service, etc. |
| `clientes_$lojaId` | ClientesScreen, Nova Venda, sync | HiveBoxNames.clientes(lojaId) nos mesmos fluxos. |
| `produtos_$lojaId` | Nova Venda, estoque, sync | HiveBoxNames.produtos(lojaId). |
| `vendas` (sem sufixo) | **Apenas pos_pagamento_service** | `Hive.openBox<Venda>('vendas')` em pos_pagamento_service.dart:141. |
| `clientes`, `vendas`, `produtos`, `fornecedores` (genéricas) | Abertas no bootstrap main.dart | openTyped('clientes'), openTyped('vendas'), ... (L1322-1328). Nenhuma tela de vendas/clientes usa essas; usam as por loja. |

### F. DIFERENÇAS DE PLATAFORMA

| Arquivo | Evidência |
|---------|-----------|
| Fluxo Nova Venda / VendasService / VendasFirestoreService / ImportarVendasFirestoreService | Nenhum `kIsWeb` nem `Platform.is*` no fluxo de criar/listar/importar venda. |
| main.dart | Web: `Hive.initFlutter()` sem path (L1272); mobile: `getAppDocsDirPath()` (L1271). Web: fallback de openTyped para box dinâmica em erro (L1364-1368). |
| app_start_router | Sem branch kIsWeb no _bindActiveStore ou resolução de loja. |
| StoreResolverService | Sem branch por plataforma. |

### G. ERROS SILENCIOSOS

| Local | Evidência |
|-------|-----------|
| vendas_screen.dart L104 | `catch (_) {}` após timeout de _verificarPermissao — sem log. |
| vendas_screen.dart L154-155 | `catch (_) { setState(() => _temVendasParaImportar = false); }` — sem log. |
| vendas_screen.dart L184-185 | `catch (e, st) { logE(...) }` em _syncEmBackground — sem snackbar/feedback ao usuário. |
| clientes_screen.dart L171-182, 180-181, 193-194, 204-205 | `catch (_) {}` ou `catch (e) { logW(...) }` — sem feedback na UI. |
| app_start_router.dart L515-518 | Timeout 3s retorna null; L527-530: se loja null e não root, **return** sem gravar — usuário não é informado. |
| main.dart L720, 755 | `catch (_) {}` em LojaIdService.set e em bloco try/catch — erro de persistência engolido. |
| clientes_firestore_service / vendas_firestore_service | Vários `catch (e, st) { logE(...); return 0 ou return; }` — sem snackbar. |

---

## 2. FLUXO REAL DE VENDAS

1. **Abrir tela:** VendasScreen._init() → LojaIdService.getWithTimeout(10s). Se null/vazio → _erroResolucaoLoja = true e return (não abre boxes).
2. **Boxes:** Abre `vendas_$lojaId`, `clientes_$lojaId`, `produtos_$lojaId` (HiveBoxNames).
3. **Listagem:** `vendasFiltradas` = `vendasBox.values.where((v) => v.lojaId == lojaId)` + filtros de busca/ordenacao. Fonte = só Hive.
4. **Sync em background:** SyncQueueService.processPending → ClientesFirestoreService.syncFirestoreToHive(lojaId, clientesBox) → ImportarVendasFirestoreService.importar(lojaId, vendasBox) → Reconciliacao, Migracao, Deduplicacao, ProdutosFirestoreService.syncFirestoreToHive, FirestoreCriticalListenerService. Qualquer falha só gera log; UI não mostra "sync falhou".
5. **Nova venda:** NovaVendaModal recebe as três boxes e lojaId; ao confirmar, VendasService.registrarVendaMulti(..., lojaId: lojaEfetiva) → baixa estoque (Firestore) → vendasBox.add(venda) → syncCliente(cliente) → syncVenda(venda). Gravação Firestore: `lojas/{lojaId}/estoque_vendas` e `estoque_clientes`.
6. **Importar (botão):** ImportarVendasFirestoreService.importar(lojaId, vendasBox) lê de `lojas/{lojaId}/estoque_vendas` e adiciona ao Hive apenas itens ainda não presentes.

Conclusão: **Um único caminho de leitura e gravação para vendas:** Firestore `estoque_vendas`; lista na tela = Hive preenchido por import/sync com esse mesmo lojaId.

---

## 3. FLUXO REAL DE CLIENTES

1. **ClientesScreen:** Igual ao de vendas: lojaId por getWithTimeout; abre clientes_$lojaId e vendas_$lojaId; lista = Hive; sync = syncFirestoreToHive(estoque_clientes) + sync vendas + Reconciliacao + Deduplicacao.
2. **Nova Venda (autocomplete):** widget.clientesBox.values filtrados por lojaId (nova_venda_modal.dart L1270-1277). clientesBox = mesma box por loja, preenchida por syncFirestoreToHive(estoque_clientes).
3. **ClientesFirestoreService:**  
   - **Escrita/sync/delete:** sempre `estoque_clientes`.  
   - **Leitura em streamClientes, getCliente, searchClientes:** `clientes`.  
   - Nenhum chamador de getCliente/searchClientes/streamClientes encontrado no projeto; portanto a lista de clientes do admin **hoje** não depende desses métodos.

Conclusão: **Fluxo atual** de listagem de clientes usa apenas Hive + sync de `estoque_clientes`. A **divergência de coleção** (leitura em `clientes` em 3 métodos) está presente no código e é inconsistente com o resto; impacto atual é **latente** (novos usos ou outros módulos).

---

## 4. FLUXO DE RESOLUÇÃO DE LOJA NO WEB

1. **main():** Firebase init → Hive.initFlutter() (Web sem path) → openDynamic('sessao','config') → openTyped('clientes','vendas',...) → **_ensureStoreIdOnBootstrap(firebaseOk)**.
2. **_ensureStoreIdOnBootstrap:** Se sessao/config já têm `store_id` → LojaIdService.set(existing) e reescreve sessao/config (mantém valor). **Se não têm:** se firebaseOk e currentUser != null → `lojaId = 'loja_uid_$uid'`; senão `lojaId = 'loja_email_${_safeSlug(usuario_logado)}'` se houver; depois LojaIdService.set(lojaId) e sessao.put/cfg.put('store_id', lojaId). **Não** consulta Firestore users/{uid}.store_id aqui.
3. **MyApp / AppStartRouter:** Só é exibido se não for catálogo público (Web com /loja na URL vai para CatalogWebRoot). No router, após login: _bindActiveStore(sessao, config, isRoot).
4. **_bindActiveStore:** resolveForRouter().timeout(3s). Se **timeout** → retorna null. Se null: só root usa last_loja_id; **senão return sem gravar** (sessao não é atualizada). Se loja != null: sessao.put('store_id', loja) etc.; depois StoreResolverService.invalidate() e set(loja).timeout(2s). StoreResolverService.set(loja) **não** persiste o argumento; chama resolve() (bloqueado).
5. **StoreResolverService.resolve():** 1) users/{uid}.store_id; 2) _uidToLoja; 3) usuarios/{email}.store_id; 4) Hive sessão; 5) _makeSlugFromEmail. Ao final chama _persist(lojaFixa) (sessao e config). No Web, passos 1 e 3 podem demorar (cold start) e ultrapassar 3s → timeout no router → null → para não-root **não** se grava nada em _bindActiveStore; sessao continua com o que estava (ex.: loja_uid_XXX do bootstrap).
6. **VendasScreen/ClientesScreen:** LojaIdService.getWithTimeout(10s). Primeira fonte = resolveForAdminApp() (mesmo resolve()). Se resolver retornar em até 10s, retorna store_id do Firestore (ou Hive). Se timeout, get() tenta Hive sessao/config (podem ter loja_uid_XXX do bootstrap).

Cadeia confirmada no código: **Bootstrap pode gravar `loja_uid_$uid`; router com timeout 3s pode não sobrescrever; telas usam getWithTimeout(10s) e, em falha, Hive — que pode conter `loja_uid_XXX`.** Dados reais podem estar em `lojas/<slug>/estoque_vendas` enquanto o app usa `loja_uid_XXX` → sync lê caminho vazio ou errado.

---

## 5. ONDE APK E WEB USAM O MESMO FLUXO

- VendasService.registrarVendaMulti e toda a lógica de venda (estoque, Hive, sync).
- VendasFirestoreService.syncVenda e syncFirestoreToHive (caminho estoque_vendas).
- ImportarVendasFirestoreService.importar.
- ClientesFirestoreService.syncCliente e syncFirestoreToHive (caminho estoque_clientes).
- StoreResolverService.resolve() (ordem de fontes idêntica).
- LojaIdService.get() e getWithTimeout().
- VendasScreen e ClientesScreen: mesma lógica de abertura de boxes por lojaId e mesma lista a partir do Hive.
- NovaVendaModal: mesma UI e mesma chamada a VendasService; sem branch por plataforma.

---

## 6. ONDE APK E WEB DIVERGEM

- **Inicialização Hive:** Web `Hive.initFlutter()` sem path (IndexedDB); mobile com path em disco. Persistência no Web pode ser afetada por limpeza de dados do site/privado.
- **Bootstrap openTyped:** Em erro, Web abre box dinâmica (main.dart L1364-1368); mobile tenta deletar arquivo e reabrir. Pode haver diferença de robustez/erro entre plataformas.
- **Timeout/cold start:** No Web, Firestore cold start é mais frequente; resolve() pode passar de 3s no router e de 10s nas telas com mais facilidade que no APK, aumentando a chance de usar fallback Hive (loja_uid_XXX do bootstrap).
- **FCM / NotificacaoService / Crashlytics:** Não inicializados no Web (main.dart); não alteram fluxo de vendas/clientes/loja.

Nenhuma divergência de **caminho** Firestore ou de **coleção** entre APK e Web no fluxo de vendas/clientes; a divergência é de **ambiente** (persistência, tempo de resposta, timeouts).

---

## 7. CAUSAS RAIZ CONFIRMADAS

| # | Causa raiz | Evidência no código |
|---|------------|----------------------|
| **C1** | **Divergência de coleção em ClientesFirestoreService** | Escrita e sync/delete usam `estoque_clientes` (L44, 97, 169, 234, 292). Leitura em streamClientes, getCliente e searchClientes usam `clientes` (L256, 272, 317, 327). Mesmo arquivo, caminhos diferentes. |
| **C2** | **Bootstrap grava `loja_uid_$uid` sem consultar Firestore** | main.dart L731-746: quando sessao/config não têm store_id, lojaId = 'loja_uid_$uid' (se firebaseOk e currentUser) ou 'loja_email_${_safeSlug(u)}'; não chama StoreResolverService.resolve(). |
| **C3** | **Router com timeout 3s pode deixar sessão sem atualização** | app_start_router.dart L514-518: resolveForRouter().timeout(3s, onTimeout: () => null). L520-530: se loja == null, só root usa last_loja_id; caso contrário **return** sem escrever em sessao. Ou seja: timeout → loja null → sessao não é atualizada com valor do resolve (e pode continuar com loja_uid_XXX do bootstrap). |
| **C4** | **Box Hive genérica `'vendas'` usada em um ponto** | pos_pagamento_service.dart L141: `Hive.openBox<Venda>('vendas')` em vez de HiveBoxNames.vendas(lojaId). Único uso de box de vendas sem sufixo de loja no fluxo de vendas/pagamento. |
| **C5** | **Sync em background sem feedback de erro na UI** | vendas_screen L184-185, clientes_screen L180-181 etc.: catch apenas logE/logW; não setState de erro nem snackbar. Usuário vê lista vazia sem saber se é "vazio real" ou "falha de sync". |
| **C6** | **StoreResolverService.set() não persiste o parâmetro** | store_resolver_service.dart L236-246: set(storeId) apenas chama resolve(); comentário "A loja é FIXA por usuário e não pode ser alterada". Quem persiste é _persist() dentro de resolve(). _bindActiveStore escreve em sessao **antes** de chamar set(loja); então o valor que fica na sessão é o que veio do primeiro resolve() em _bindActiveStore; se esse resolve deu timeout (null), não se chega aos sessao.put. |

---

## 8. FORTES SUSPEITAS (NÃO CONFIRMADAS)

| # | Suspeita | Motivo |
|---|----------|--------|
| **S1** | No Web, refresh pode limpar IndexedDB/sessão e fazer lojaId vir só do Firestore (com atraso) ou null | Não há evidência no código de quando o IndexedDB é limpo; comportamento do navegador. |
| **S2** | Cold start do Firestore no Web faz resolve() ultrapassar 3s com frequência | Lógica plausível; não há métrica no código. |
| **S3** | Catálogo/fornecedores "continuam visíveis" porque usam outra fonte (ex. slug da URL, config) ou não dependem do mesmo sync | Catálogo público usa lojaId da URL; fornecedores usam HiveBoxNames.fornecedores(lojaId). Se lojaId for o mesmo errado, em tese fornecedores também poderiam estar vazios; pode haver diferença de timing ou de tela (ex. catálogo lido direto do Firestore por slug). Não rastreado até o fim. |
| **S4** | SyncQueueService.processPending ou AutoSyncService podem sobrescrever cache válido com vazio em caso de query vazia | Não foi auditado o conteúdo de SyncQueueService/AutoSyncService em detalhe (se fazem "clear + add" ou "merge"). |

---

## 9. NÃO CONFIRMADO

- Que a **única** causa de "vendas e clientes somem" no Web seja lojaId errado; pode haver rede, regras Firestore, ou índice faltando (não auditado).
- Que getCliente/searchClientes sejam usados em produção por outro módulo (ex. portal/cliente); grep não encontrou chamadas.
- Que Hive no Web perca dados em cenários específicos (refresh, aba fechada, storage eviction) — depende do ambiente.
- Que exista race entre bootstrap e router que sempre deixe sessão com loja_uid_XXX; a sequência depende de timing (auth já restaurado no bootstrap ou não).

---

## 10. RISCOS DE REGRESSÃO CASO MEXA ERRADO

| Área | Risco |
|------|--------|
| **StoreResolverService** | Desbloquear set() ou mudar ordem de resolve() pode quebrar multi-tenant (um usuário = uma loja). Alterar apenas timeouts ou persistência após resolve() é mais seguro. |
| **Bootstrap** | Remover fallback loja_uid_$uid sem garantir que resolve() rode antes de qualquer tela dependente pode deixar sessão sem store_id em primeiro acesso. |
| **ClientesFirestoreService** | Trocar `clientes` por `estoque_clientes` em streamClientes/getCliente/searchClientes pode afetar fluxos que hoje leem da coleção `clientes` (ex. portal, auth cliente) se existirem. Confirmar quem consome essas APIs antes. |
| **Router** | Aumentar timeout ou "nunca retornar sem gravar" sem tratar null do resolve() pode travar a tela de carregamento. |
| **VendasScreen/ClientesScreen** | Bloquear exibição até sync concluir pode piorar UX (demora). Preferível manter dados locais e mostrar estado "sync falhou" em vez de esconder a lista. |
| **pos_pagamento_service** | Trocar para HiveBoxNames.vendas(lojaId) exige obter lojaId no contexto desse serviço (pode vir do parâmetro da função que chama). Ver todas as chamadas antes de alterar. |

---

## 11. RESUMO PARA DECISÃO

- **Confirmado:** (1) Duas coleções para clientes (estoque_clientes vs clientes) no mesmo serviço; (2) bootstrap definindo loja_uid_$uid sem Firestore; (3) router com timeout 3s podendo não gravar loja; (4) box `'vendas'` genérica em pos_pagamento_service; (5) sync em background sem feedback de erro; (6) set() do StoreResolver não persistir o parâmetro.
- **Forte suspeita:** Timeout/cold start no Web e persistência da sessão (refresh/IndexedDB).
- **Não confirmado:** Regras Firestore, índices, uso de getCliente/searchClientes em outros fluxos, e que lojaId seja a única causa dos sintomas.

**Nenhuma alteração foi feita no código.** Este documento é apenas a saída da Fase 1 (Auditoria forense) com evidências citadas por arquivo e linha onde aplicável.
