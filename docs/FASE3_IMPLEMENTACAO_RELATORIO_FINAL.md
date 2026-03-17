# FASE 3 — IMPLEMENTAÇÃO CONTROLADA — Relatório final

**Data:** Conforme execução. **Base:** FASE 1 (auditoria) e FASE 2 (plano de correção).

---

## Auditoria rápida S4 (antes de alterar sync)

**Pergunta:** Existe algum fluxo que sobrescreve cache Hive válido com lista vazia/remota sem validação?

**O que foi verificado:**
- `syncFirestoreToHive` (vendas e clientes): **não faz** `box.clear()`; apenas percorre os docs do Firestore e faz `box.add()` para itens que ainda não existem no Hive (checagem por idFirebase ou equivalente). **Não confirmado** que sobrescreva cache com vazio.
- `ImportarVendasFirestoreService.importar`: mesma lógica — só adiciona vendas que não existem; **não** limpa a box.
- `FullSyncService`: em `_clearCacheIfLojaDiferente`, chama `box.clear()` **somente** quando `cachedLojaId != lojaIdAtual` (troca de loja); limpa boxes da **loja antiga** antes de sincronizar a nova. Não é “retorno vazio do Firestore sobrescrevendo cache”; é limpeza intencional ao trocar de loja.
- Outros `clear()` encontrados: `SyncQueueService.clearQueue` (fila de operações), `AuthSession`, `StoreResolverService.clear` (sessão/config), `repair_historico_clientes` (limpa histórico do cliente), etc. Nenhum deles é “sync Firestore → box vazia sobrescrevendo Hive válido”.

**Conclusão S4:** **Não confirmado.** Nenhum fluxo de sync de vendas/clientes sobrescreve cache válido com resultado vazio do Firestore. FullSyncService limpa apenas em troca de loja (outra lojaId). Nenhuma alteração foi feita na lógica de sync por causa de S4.

---

## ETAPA 1 — Alterações implementadas

1. **Router (_bindActiveStore)**  
   - Timeout no Web aumentado de 3s para 6s (`kIsWeb ? 6 : 3`).  
   - Quando `resolve()` retorna null: tenta fallback em `sessao.get('store_id')` e `config.get('last_loja_id')`; se algum tiver valor, usa esse valor e grava em sessao/config (não sai sem gravar).  
   - Logs com tags `[ROUTER_GUARD]`, `[STORE_RESOLVE]`, `[STORE_SESSION]`.

2. **Bootstrap (_ensureStoreIdOnBootstrap)**  
   - Quando não existe `store_id` em sessão/config: chama `StoreResolverFacade.resolveForAdminApp().timeout(5s)` primeiro.  
   - Se retornar valor não vazio: usa esse valor e grava.  
   - Só usa fallback `loja_uid_$uid` / `loja_email_...` se resolve falhar ou retornar null; registra em log quando usa fallback.  
   - Logs `[WEB_BOOTSTRAP]`, `[STORE_SESSION]`.

3. **Proteção de tela dependente**  
   - Mantido comportamento atual: VendasScreen e ClientesScreen só abrem boxes e mostram conteúdo após `lojaId` válido (getWithTimeout); se null/vazio, setam `_erroResolucaoLoja = true` e exibem tela de erro “Não foi possível carregar a loja”. Nenhuma tela fica “pronta” sem lojaId. Comentário explícito em VendasScreen: “telas dependentes só prontas com lojaId válido”.

4. **Feedback de sync**  
   - **VendasScreen:** Variável `_syncFalhou`; no `catch` de `_syncEmBackground` faz `setState(() => _syncFalhou = true)`; em sucesso `_syncFalhou = false`. Banner no topo da lista: “Sincronização falhou. Puxe para atualizar ou tente novamente.” + botão “Tentar novamente” que chama `_syncEmBackground` de novo. Lista local permanece visível.  
   - **ClientesScreen:** Mesmo padrão (`_syncFalhou`, banner laranja no topo, “Tentar novamente”).  
   - Logs `[SYNC]`, `[VENDAS_READ]`, `[CLIENTES_READ]` (em debug) com lojaId e contagens.

5. **Clientes (unificação de coleção)**  
   - Em `ClientesFirestoreService`: `streamClientes`, `getCliente` e `searchClientes` passaram a usar a coleção **`estoque_clientes`** (mesma do sync e da escrita). Comentários no código indicam “FASE 3: Unificado”.  
   - Grep prévio: nenhum chamador de `getCliente`/`searchClientes`/`streamClientes` no projeto; alteração considerada segura.

6. **pos_pagamento_service**  
   - Substituído `Hive.openBox<Venda>('vendas')` por `Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId))`; `lojaId` já é parâmetro de `_atualizarStatusVenda(lojaId, vendaId)`.  
   - Busca da venda: `int.tryParse(vendaId)` para usar como key Hive quando for numérico; fallback `get(vendaId)`.  
   - Log em debug `[HIVE_BOX] pos_pagamento vendasBox lojaId=...`.

7. **Logs temporários**  
   - Tags usadas: `[ROUTER_GUARD]`, `[STORE_RESOLVE]`, `[STORE_SESSION]`, `[WEB_BOOTSTRAP]`, `[VENDAS_READ]`, `[CLIENTES_READ]`, `[SYNC]`, `[HIVE_BOX]`.  
   - Logs via `logD`/`logW` (core/logger), que já só emitem em `kDebugMode`.

---

## ETAPA 2 — Arquivos modificados

| Arquivo | Alteração |
|---------|-----------|
| `lib/screens/app_start_router.dart` | Timeout Web 6s; fallback sessão/config quando resolve null; logs [ROUTER_GUARD], [STORE_RESOLVE], [STORE_SESSION]; import kDebugMode. |
| `lib/main.dart` | Import store_resolver_facade; _ensureStoreIdOnBootstrap tenta resolve().timeout(5s) antes de fallback; logs [WEB_BOOTSTRAP], [STORE_SESSION]. |
| `lib/screens/vendas_screen.dart` | Import kDebugMode; _syncFalhou; log [VENDAS_READ] após abrir boxes; em _syncEmBackground catch seta _syncFalhou e log [SYNC]; banner “Sincronização falhou” + “Tentar novamente”. |
| `lib/screens/clientes_screen.dart` | Import kDebugMode; _syncFalhou; log [CLIENTES_READ]; _syncClientesEmBackground seta _syncFalhou em qualquer catch e log [SYNC]; banner laranja no topo + “Tentar novamente”. |
| `lib/services/clientes_firestore_service.dart` | streamClientes, getCliente e searchClientes passam a usar coleção `estoque_clientes` (com comentários FASE 3). |
| `lib/services/pos_pagamento_service.dart` | Box de vendas via HiveBoxNames.vendas(lojaId); busca por key int ou fallback; log [HIVE_BOX]. |
| `lib/services/store_resolver_service.dart` | Log adicional `[STORE_RESOLVE] resolved=...` ao final de resolve(). |

---

## ETAPA 3 — Diff / resumo por arquivo

- **app_start_router.dart:** Timeout 3→6 no Web; bloco “se loja null” estendido com fallback sessão/config e gravação; logs com tags.  
- **main.dart:** Novo import; bloco “existing == null” reescrito: primeiro resolve(5s), depois fallback loja_uid/loja_email com log.  
- **vendas_screen.dart:** Nova variável _syncFalhou; log após abrir boxes; catch do sync seta _syncFalhou e chama setState; corpo da tela com `if (_syncFalhou)` exibindo Material/banner e botão “Tentar novamente”.  
- **clientes_screen.dart:** Idem _syncFalhou e logs; _syncClientesEmBackground acumula falha em bool e setState; Stack com Positioned banner quando _syncFalhou.  
- **clientes_firestore_service.dart:** Três métodos trocam `collection('clientes')` por `collection('estoque_clientes')` e ganham comentário de unificação.  
- **pos_pagamento_service.dart:** Abertura da box com HiveBoxNames.vendas(lojaId); obtenção da venda com int.tryParse(vendaId) + fallback; log [HIVE_BOX].  
- **store_resolver_service.dart:** Uma linha logD com tag [STORE_RESOLVE] ao retornar loja.

---

## ETAPA 4 — Impacto esperado

- **Web:** Menos perda de contexto de loja ao dar timeout no resolve (fallback sessão/config) e ao iniciar (bootstrap tenta Firestore antes de loja_uid). Timeout maior (6s) reduz chance de null por cold start.  
- **Vendas/clientes “sumindo”:** Se a causa for lojaId errado ou não gravado, bootstrap e router passam a priorizar store_id do Firestore e a manter sessão quando já houver valor conhecido.  
- **Lista vazia sem explicação:** Usuário passa a ver banner “Sincronização falhou” quando o sync em background falhar, em vez de apenas lista vazia.  
- **Clientes:** Leitura (stream/get/search) e escrita/sync passam a usar a mesma coleção `estoque_clientes`, evitando divergência futura.  
- **Pós-pagamento:** Atualização de status da venda no Hive usa a box da loja correta (`vendas_$lojaId`), alinhada ao restante do app.

---

## ETAPA 5 — Riscos remanescentes

- **Root com múltiplas lojas:** Fallback de sessão no router pode manter “última loja” após timeout; comportamento aceitável e alinhado ao uso de last_loja_id para root.  
- **Primeiro acesso sem Firestore:** Bootstrap continua com fallback loja_uid_$uid; se Firestore nunca responder, loja pode ficar como loja_uid_XXX (já existia antes).  
- **ClienteAuthService / portal:** Usam coleção `clientes` em outros arquivos; **não** foram alterados. Apenas os três métodos do ClientesFirestoreService passaram a usar `estoque_clientes`; se no futuro algum fluxo de portal depender de “clientes” no Firestore, isso é separado do admin (Nova Venda / ClientesScreen).  
- **pos_pagamento_service:** Chamadores devem passar `vendaId` compatível com Hive (key numérica como string ou idFirebase conforme uso real); foi mantido fallback `get(vendaId)` para compatibilidade.

---

## ETAPA 6 — Checklist de validação manual

- [ ] **Android:** Login → Vendas → Nova Venda → conferir venda na lista; reabrir app e conferir se loja e lista permanecem.  
- [ ] **Web:** Login → Vendas → Nova Venda → conferir venda na lista; refresh (F5) e conferir se store_id e lista continuam (sem “sumir” vendas/clientes).  
- [ ] **Web rede lenta:** Throttle no DevTools (Slow 3G); login e abertura de Vendas; conferir se após timeout o router usa fallback de sessão e se a tela não fica em branco sem loja.  
- [ ] **Sync falhou:** Desligar rede após abrir Vendas ou Clientes; conferir se aparece banner “Sincronização falhou” e se “Tentar novamente” chama o sync de novo.  
- [ ] **Clientes:** Lista de clientes e autocomplete na Nova Venda continuam funcionando (fonte segue sendo Hive + sync de estoque_clientes).  
- [ ] **Pós-pagamento:** Fluxo de confirmação de pagamento (catálogo/checkout) que chama PosPagamentoService; conferir se a venda é atualizada no Hive na box da loja correta (e log [HIVE_BOX] em debug).  
- [ ] **Catálogo e fornecedores:** Continuam acessíveis e consistentes com a mesma loja (sem regressão).

---

*Implementação controlada conforme FASE 2. Nenhuma alteração fora do escopo aprovado; funcionalidades existentes preservadas; correções mínimas e seguras.*
