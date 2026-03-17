# Auditoria: Fluxo "Nova Venda" — APK Android vs App Web (MasterPalm)

**Objetivo:** Causa raiz das divergências entre APK e Web (vendas/clientes sumindo no Web; catálogo/fornecedores permanecendo visíveis).

---

## 1. Resumo executivo do problema

- **Sintomas:** Vendas feitas no Web não aparecem corretamente no catálogo/histórico; em alguns momentos somem todas as vendas e clientes no app Web, permanecendo apenas catálogo e fornecedores.
- **Hipótese central:** Não é diferença de código entre APK e Web na tela Nova Venda em si, e sim **contexto de loja (lojaId)** e **origem dos dados (Firestore vs Hive)** que podem divergir no Web, além de **uma coleção errada para clientes** em parte do `ClientesFirestoreService`.
- **Causas raiz mais prováveis:**
  1. **lojaId resolvido diferente no Web** (ex.: `loja_uid_XXX` ou timeout → sessão vazia) fazendo sync Firestore→Hive buscar em `lojas/<id_errado>/estoque_vendas` e `estoque_clientes` (vazio).
  2. **ClientesFirestoreService** grava em `estoque_clientes` mas **lê** em `clientes` em `streamClientes`, `getCliente` e `searchClientes` → qualquer fluxo que use esses métodos não vê clientes da Nova Venda.
  3. **Bootstrap** no `main.dart` pode definir `store_id` como `loja_uid_$uid` quando sessão está vazia, enquanto o Firestore (e o APK após sync) usa slug (`nathy-pratas-e-folheados`); no Web, timeout ou cache pode manter o id errado.
  4. **Sync em background** sem feedback: falhas são só logadas; usuário vê lista vazia sem mensagem de erro.

---

## 2. Mapeamento completo do fluxo da tela Nova Venda

### 2.1 Arquivos principais

| Arquivo | Função |
|--------|--------|
| `lib/screens/vendas_screen.dart` | Lista vendas, totais, filtros, abre `NovaVendaModal`, resolve `lojaId` e abre boxes por loja |
| `lib/screens/nova_venda_modal.dart` | UI da Nova Venda; recebe `produtosBox`, `clientesBox`, `vendasBox`, `lojaId`; chama `VendasService.registrarVendaMulti` |
| `lib/services/vendas_service.dart` | Regra de negócio: cliente, estoque (Firestore), venda Hive, sync cliente/venda Firestore |
| `lib/services/vendas_firestore_service.dart` | Sync venda → `lojas/{lojaId}/estoque_vendas`; import Firestore→Hive |
| `lib/services/importar_vendas_firestore_service.dart` | Importação Firestore→Hive sem duplicar (idFirebase + fallback cliente+data+total) |
| `lib/services/clientes_firestore_service.dart` | Sync cliente → `estoque_clientes`; sync Firestore→Hive de `estoque_clientes`; **stream/get/search usam coleção `clientes`** |
| `lib/core/hive_box_names.dart` | `vendas(lojaId)` → `vendas_$lojaId`, `clientes(lojaId)` → `clientes_$lojaId`, `produtos(lojaId)` → `produtos_$lojaId` |

### 2.2 Fluxo de gravação (Nova Venda)

1. Usuário preenche e confirma na `NovaVendaModal`.
2. `VendasService.registrarVendaMulti`:
   - Valida `lojaId` (obrigatório).
   - Expande combos, baixa estoque via `EstoqueTransactionService` (Firestore, transação).
   - Atualiza Hive de produtos após transação.
   - Obtém/cria cliente na **clientesBox** (Hive), adiciona venda na **vendasBox** (Hive).
   - `ClientesFirestoreService.syncCliente` → `lojas/{lojaId}/estoque_clientes`.
   - `VendasFirestoreService.syncVenda` → `lojas/{lojaId}/estoque_vendas`.
3. Nova Venda **não** usa `kIsWeb` nem branch por plataforma; mesmo código em APK e Web.

### 2.3 Fluxo de leitura (vendas e clientes na tela)

- **VendasScreen:** Obtém `lojaId` com `LojaIdService.getWithTimeout(10s)`; abre `HiveBoxNames.vendas(lojaId)`, `clientes(lojaId)`, `produtos(lojaId)`; lista = `vendasBox.values.where((v) => v.lojaId == lojaId)`.
- **Sync em background:** `ImportarVendasFirestoreService.importar`, `ClientesFirestoreService.syncFirestoreToHive`, `ReconciliacaoVendasClientesService`, `MigracaoVendasItensService`, `DeduplicacaoClientesService`, `ProdutosFirestoreService.syncFirestoreToHive`, `FirestoreCriticalListenerService.startProdutosListener`.
- Se `lojaId` estiver errado ou vazio, as boxes abertas são `vendas_<id_errado>` e `clientes_<id_errado>`; o sync busca em `lojas/<id_errado>/estoque_vendas` e `estoque_clientes` (podem estar vazios).

### 2.4 Onde a tela resolve o lojaId

- **VendasScreen / ClientesScreen:** `LojaIdService.getWithTimeout(10s)`.
- **LojaIdService.get:** 1) `StoreResolverFacade.resolveForAdminApp()` (= `StoreResolverService.resolve()`); 2) Hive `sessao` (store_id, lojaId, storeId); 3) Hive `config`.
- **StoreResolverService.resolve():** 1) Cache (por UID); 2) Firestore `users/{uid}.store_id`; 3) mapa legado `_uidToLoja`; 4) Firestore `usuarios/{email}.store_id`; 5) Hive sessão (offline); 6) slug a partir do email.

---

## 3. Comparação exata entre APK Android e App Web

- **Nova Venda / VendasService / VendasFirestoreService / ImportarVendasFirestoreService:** Nenhuma condicional `kIsWeb` ou `Platform.is*` no fluxo de criar/listar/importar venda. Comportamento é o mesmo.
- **Diferenças que afetam o contexto (não o código da venda):**
  - **main.dart:** No Web, Hive usa `Hive.initFlutter()` sem path; no mobile, `getAppDocsDirPath()`. Bootstrap abre as mesmas boxes **genéricas** (`clientes`, `vendas`, `produtos`, `fornecedores`) em ambos; as telas de vendas/clientes abrem boxes **por loja** (`vendas_$lojaId`, etc.).
  - **App Check / FCM / Crashlytics:** Web tem branches (ex.: sem FCM, App Check com fallback). Não alteram fluxo de vendas.
  - **StoreResolverService:** Mesma lógica; no Web, Firestore pode ter cold start maior → mais timeouts; `LojaIdService.getWithTimeout(10s)` e router com 3s podem deixar sessão sem `store_id` ou com valor de fallback (`loja_uid_XXX`).
  - **Router (_bindActiveStore):** Timeout 3s para `resolveForRouter`. Se der timeout, não grava loja; usuário pode chegar na home sem `store_id`. Ao abrir Vendas/Clientes, `getWithTimeout(10s)` tenta de novo.

Conclusão: a diferença não é “APK grava em um lugar e Web em outro”, e sim **qual lojaId é usado no Web** (e se as boxes/sync usam esse mesmo id).

---

## 4. Onde a sincronização pode quebrar

| Ponto | Risco |
|-------|--------|
| **lojaId null ou errado no Web** | VendasScreen abre `vendas_$lojaId` / `clientes_$lojaId`; sync lê `lojas/$lojaId/estoque_vendas` e `estoque_clientes`. Se lojaId = `loja_uid_XXX` e dados reais estão em `nathy-pratas-e-folheados`, Firestore retorna vazio → boxes continuam vazias. |
| **Bootstrap _ensureStoreIdOnBootstrap** | Se sessão/config sem `store_id`, preenche com `loja_uid_$uid` (ou `loja_email_xxx`). StoreResolver depois pode resolver para slug; mas se resolver() falhar/timeout, sessão pode ficar com `loja_uid_XXX` e nunca ser atualizada para o slug. |
| **Router timeout 3s** | _bindActiveStore não grava loja; depois LojaIdService.get() pode ainda obter do Firestore (até 10s). Se ambos falharem, lojaId null → tela de erro. |
| **ClientesFirestoreService: coleção errada** | sync/syncFirestoreToHive/hasDataToImport/delete usam `estoque_clientes`; streamClientes, getCliente, searchClientes usam **`clientes`**. Quem depender de stream/get/search não vê clientes da Nova Venda (gravados em estoque_clientes). |
| **Sync em background sem retry visível** | Falhas em _syncEmBackground só log; usuário vê lista vazia. |
| **pos_pagamento_service** | Usa `Hive.openBox<Venda>('vendas')` (box **sem** sufixo de loja). Inconsistente com o resto do app; risco de ler/escrever em box errada. |

---

## 5. Coleções / boxes / serviços por plataforma

- **Firestore (comum):**
  - Vendas: `lojas/{lojaId}/estoque_vendas` (escrita e leitura em sync/import).
  - Clientes: `lojas/{lojaId}/estoque_clientes` (sync e syncFirestoreToHive); **`clientes`** usada só em streamClientes, getCliente, searchClientes (erro de design).
- **Hive (por loja):**
  - Boxes: `vendas_$lojaId`, `clientes_$lojaId`, `produtos_$lojaId`, `fornecedores_$lojaId` (abertas pelas telas com `HiveBoxNames.*(lojaId)`).
- **Hive (bootstrap main.dart):**
  - Boxes genéricas: `clientes`, `vendas`, `produtos`, `fornecedores` (sem sufixo). Não são usadas pela VendasScreen/ClientesScreen; usadas por outros fluxos (ex.: pos_pagamento_service usa `'vendas'`).

---

## 6. Erros silenciosos encontrados

- **VendasScreen _init:** `catch (_) {}` após _verificarPermissao timeout (linha ~104).
- **VendasService:** `catch (e) { debugPrint(...); onSyncError?.call(...); }` para sync cliente e venda — usuário pode ver snackbar se onSyncError for passado; em outros pontos só debugPrint.
- **VendasFirestoreService / ClientesFirestoreService:** Vários `catch (e, st) { logE(...); return 0 ou return; }` — sem snackbar; sync falha e lista fica vazia.
- **ClientesScreen _syncClientesEmBackground:** `catch (e) { logW(...) }` — sem feedback.
- **Router _bindActiveStore:** Timeout 3s retorna null e não grava loja; não há mensagem ao usuário.
- **main openTyped (Web):** Em erro, fallback para box dinâmica; pode mascarar incompatibilidade de tipo e dados “estranhos” na UI.

---

## 7. Possíveis causas raiz do desaparecimento de vendas e clientes no Web

1. **lojaId inconsistente (mais provável):** No Web, resolve() pode retornar `loja_uid_XXX` (bootstrap ou Hive) enquanto os dados estão em `lojas/<slug>/estoque_vendas` e `estoque_clientes`. Sync busca no id errado → listas vazias. Catálogo/fornecedores podem usar outro fluxo (ex.: slug da URL, config ou cache) e por isso continuar visíveis.
2. **Timeout no router:** _bindActiveStore com 3s não grava loja; em seguida, se LojaIdService.get() também falhar (rede), lojaId null → tela de erro. Se get() retornar um fallback (ex. da sessão antiga) errado, mesmo cenário do item 1.
3. **Clientes “sumindo” em telas que usam Firestore:** Se alguma tela ou fluxo usar `streamClientes`/`getCliente`/`searchClientes`, lê da coleção `clientes`, que não é onde a Nova Venda grava (`estoque_clientes`) → lista vazia ou cliente não encontrado.
4. **Sync Firestore→Hive falhando sem aviso:** Rede, permissão ou índice; usuário vê Hive vazio.
5. **Hive Web (IndexedDB):** Limpeza de dados ou modo anônimo pode zerar sessão/config; na próxima abertura, lojaId pode vir só do Firestore (com atraso) ou ficar null.

---

## 8. Riscos de filtro / lojaId incorreto

- **VendasScreen / ClientesScreen:** Filtram por `v.lojaId == lojaId` e `c.lojaId == lojaId`. Se lojaId for errado, a box já é a errada (`vendas_$lojaId`), então o filtro em si não “esconde” dados — o problema é a box estar vazia porque o sync usou o mesmo lojaId errado.
- **StoreResolverService:** Cache por UID; se usuário trocar de conta sem logout limpo, cache pode servir loja antiga.
- **Bootstrap:** `loja_uid_$uid` vs slug no Firestore; primeiro acesso ou sessão limpa pode fixar o id errado na sessão se resolve() não rodar a tempo.

---

## 9. Riscos de Hive / cache / box errada

- **Bootstrap** abre `clientes`, `vendas`, `produtos`, `fornecedores` (sem loja). VendasScreen não usa essas; usa `vendas_$lojaId` etc. Risco: outros serviços (ex. pos_pagamento_service) usarem `'vendas'` e escreverem/lerem fora do modelo por loja.
- **HiveMultiStore:** Não é usado pela VendasScreen; usa-se abertura direta com `HiveBoxNames`. HiveMultiStore.inicializar(lojaId) não é chamado no main nem no router; quem usar os getters de HiveMultiStore pode dar StateError se não tiver sido inicializado.
- **Web openTyped fallback:** Box dinâmica em caso de erro pode misturar tipos e gerar listas vazias ou quebras em runtime.

---

## 10. Riscos de Firestore / query vazia

- **Índice:** `estoque_vendas` e `estoque_clientes` com orderBy/where podem exigir índice; falha de índice gera exceção, não retorno vazio silencioso (a menos que seja capturada e ignorada).
- **streamVendas (VendasFirestoreService):** limit(100); se houver mais de 100 vendas, parte não aparece no stream (não usado pela VendasScreen que lê do Hive; usado apenas se algum widget usar esse stream).
- **syncFirestoreToHive (clientes):** limit(1000); lojas com mais de 1000 clientes ficam truncadas no Hive.

---

## 11. Riscos de bootstrap / inicialização parcial no Web

- **Ordem:** Firebase → Hive init → openDynamic('sessao','config') → openTyped clientes, vendas, produtos, fornecedores (genéricas) → _ensureStoreIdOnBootstrap → ... Nenhum passo abre explicitamente as boxes por loja; isso só acontece ao abrir VendasScreen/ClientesScreen.
- **Cenário “catálogo e fornecedores ok, vendas/clientes sumindo”:** Catálogo pode vir de Firestore por slug/URL; fornecedores da box `fornecedores_$lojaId` (aberta ao entrar na tela). Se lojaId estiver errado, em tese fornecedores também deveriam estar vazios; a menos que a tela de fornecedores use outro critério ou que a box genérica `fornecedores` seja usada em algum lugar. Mais plausível: **vendas e clientes dependem de sync Firestore→Hive com lojaId correto**; catálogo pode não depender desse sync (leitura direta Firestore ou outro path). Então falha de lojaId ou de sync afeta vendas/clientes primeiro.

---

## 12. Top 10 correções prioritárias

| Prioridade | Correção | Onde |
|------------|----------|------|
| **CRÍTICO 1** | Unificar coleção de clientes: fazer streamClientes, getCliente e searchClientes usarem **estoque_clientes** (mesma do sync), ou documentar que `clientes` é legado e migrar dados. | `lib/services/clientes_firestore_service.dart` |
| **CRÍTICO 2** | Garantir que bootstrap e router usem o **mesmo** identificador de loja que o Firestore (slug/store_id de users/usuarios). Evitar gravar `loja_uid_$uid` em sessão quando Firestore já tiver store_id; após resolve(), sempre persistir o valor resolvido. | `lib/main.dart` (_ensureStoreIdOnBootstrap), `lib/screens/app_start_router.dart` (_bindActiveStore) |
| **CRÍTICO 3** | No Web, aumentar ou diferenciar timeout de resolução de loja no router (ex. 5–7s) e garantir que, em caso de timeout, não se deixe sessão sem store_id quando já houver valor em config (ex. last_loja_id). | `lib/screens/app_start_router.dart` |
| **ALTO 4** | Corrigir pos_pagamento_service: usar `HiveBoxNames.vendas(lojaId)` (e obter lojaId do contexto) em vez de `Hive.openBox<Venda>('vendas')`. | `lib/services/pos_pagamento_service.dart` |
| **ALTO 5** | Em VendasScreen e ClientesScreen, se _syncEmBackground falhar, mostrar indicador ou snackbar (“Falha ao sincronizar; tente puxar para atualizar” ou “Sem conexão”) em vez de apenas lista vazia. | `lib/screens/vendas_screen.dart`, `lib/screens/clientes_screen.dart` |
| **ALTO 6** | Logar claramente o lojaId usado em cada sync (já existe em parte); no Web, logar na abertura da VendasScreen o lojaId resolvido e a contagem de vendas/clientes após sync para facilitar diagnóstico. | `lib/screens/vendas_screen.dart`, `lib/services/vendas_firestore_service.dart`, `lib/services/clientes_firestore_service.dart` |
| **MÉDIO 7** | Revisar _ensureStoreIdOnBootstrap: não definir `loja_uid_$uid` como padrão quando users/{uid} puder ser lido (ex. tentar ler store_id do Firestore antes de preencher sessão com fallback). | `lib/main.dart` |
| **MÉDIO 8** | Considerar chamar HiveMultiStore.inicializar(lojaId) após _bindActiveStore (ou após LojaIdService.get() na primeira tela que precisar), para que getters por loja fiquem consistentes. | `lib/screens/app_start_router.dart` ou ponto único pós-login |
| **MÉDIO 9** | Clientes: avaliar remoção do limit(1000) em syncFirestoreToHive ou paginação para lojas grandes. | `lib/services/clientes_firestore_service.dart` |
| **BAIXO 10** | Revisar usos de `ClientesFirestoreService.getCliente`/`searchClientes`/`streamClientes`; se forem para admin (Nova Venda / lista de clientes), devem usar dados de estoque_clientes (ou o serviço unificado). | Codebase |

---

## 13. Lista exata dos arquivos mais críticos

- `lib/services/clientes_firestore_service.dart` — divergência estoque_clientes vs clientes.
- `lib/services/store_resolver_service.dart` — resolução e cache de lojaId.
- `lib/services/loja_id_service.dart` — fonte única de lojaId para as telas.
- `lib/main.dart` — bootstrap, _ensureStoreIdOnBootstrap, abertura de boxes.
- `lib/screens/app_start_router.dart` — _bindActiveStore, timeouts, persistência de loja.
- `lib/screens/vendas_screen.dart` — _init, lojaId, sync em background, abertura de boxes.
- `lib/screens/clientes_screen.dart` — _init, sync em background.
- `lib/services/vendas_firestore_service.dart` — sync e import Firestore↔Hive.
- `lib/services/importar_vendas_firestore_service.dart` — importação sem duplicar.
- `lib/services/pos_pagamento_service.dart` — uso da box `'vendas'` sem lojaId.
- `lib/core/hive_box_names.dart` — nomes das boxes por loja (referência).
- `lib/core/loja_id_adapter.dart` — normalização store_id/lojaId.

---

## 14. O que NÃO mexer agora (para evitar regressão)

- **Lógica de baixa de estoque** (EstoqueTransactionService) e regras dentro de VendasService.registrarVendaMulti (combos, fiado, histórico do cliente no Hive).
- **Estrutura do modelo Venda/Cliente e da coleção estoque_vendas/estoque_clientes** (campos, nomes) até validar a causa em produção (logs de lojaId e contagens).
- **FirestoreCriticalListenerService** e ProdutosFirestoreService sem necessidade clara de mudança.
- **NovaVendaModal** (UI, validações, roleta, fiado) até que sync e lojaId estejam estáveis.
- **StoreResolverService** bloqueio de set (imutabilidade por usuário) — não reativar set arbitrário; apenas garantir que a fonte (Firestore users/usuarios) e a persistência na sessão estejam alinhadas.

---

## 15. Foco especial — checklist de causas

- **Venda do Web grava em lugar diferente do APK?** Não. Ambos usam `lojas/{lojaId}/estoque_vendas` via VendasFirestoreService.syncVenda.
- **Venda do Web não leva lojaId?** Não. lojaId é obrigatório em registrarVendaMulti e passado para syncVenda.
- **Leitura do Web está filtrando errado?** Pode. Se o lojaId resolvido no Web for diferente do do Firestore (ex. loja_uid_XXX vs slug), as boxes e as queries Firestore usam o id errado → listas vazias.
- **Cliente do Web depende de box não inicializada?** As boxes por loja são abertas na própria VendasScreen/ClientesScreen; não há pré-abertura no bootstrap. Se lojaId for null, a tela mostra _erroResolucaoLoja; se lojaId for errado, a box é aberta mas o sync preenche com dados da loja errada (vazio).
- **Venda do Web salva mas não atualiza histórico?** Histórico do cliente é atualizado no Hive (cliente.historico) e syncCliente envia para Firestore; não há branch Web que pule isso.
- **Estoque baixa em uma plataforma e não na outra?** Não; baixa é via EstoqueTransactionService (Firestore), comum a ambas.
- **Nova Venda depende de cache local no Web de forma perigosa?** Sim, no sentido de que a **lista** de vendas e clientes vem do Hive; se o sync Firestore→Hive não rodar ou rodar com lojaId errado, a lista fica vazia. O “perigoso” é o lojaId/sync, não a decisão de usar Hive para exibição.
- **Catálogo e fornecedores carregam por outro serviço/coleção?** Catálogo pode usar Firestore/URL; fornecedores usam `fornecedores_$lojaId`. Se lojaId for o mesmo errado, fornecedores também deveriam estar vazios; a observação “catálogo e fornecedores continuam visíveis” pode ser timing (sync de vendas/clientes falhou) ou uso de outra fonte para catálogo.
- **Código legado no Web e novo no APK?** Não identificado; mesmo código de vendas/clientes/sync.

---

*Documento gerado a partir de análise estática do repositório MasterPalm (temp_naty). Recomenda-se validar em ambiente de homologação com logs de lojaId e contagens de sync antes de aplicar todas as correções em produção.*
