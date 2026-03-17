# FASE 4 — Validação final e caça de regressões

**Objetivo:** Validar o que foi implementado na FASE 3, identificar riscos residuais e regressões, sem refatorar.

---

## 1. VALIDAÇÃO GERAL DA FASE 3

### 1.1 ROUTER (`app_start_router.dart`)

| Verificação | Evidência no código | Resultado |
|-------------|---------------------|-----------|
| Timeout Web 6s | L514: `final timeoutSeconds = kIsWeb ? 6 : 3;` e uso em `.timeout(Duration(seconds: timeoutSeconds), ...)` | ✅ Aplicado |
| Fallback sessão/config grava contexto | L532-543: quando `loja == null`, lê `fromSessao` e `fromConfig`; se não vazio, atribui a `loja` e loga; só retorna sem gravar em L545-548 quando `loja` continua null | ✅ Grava quando há fallback |
| Não retorna cedo indevidamente | O `return` em L546 só ocorre após tentar root (last_loja_id) e fallback sessão/config; se qualquer um preencher `loja`, segue para L551-558 e grava | ✅ Correto |
| Logs coerentes | `[ROUTER_GUARD]`, `[STORE_RESOLVE]`, `[STORE_SESSION]` presentes (L510, 516, 520, 537-540, 546, 549) | ✅ OK |

### 1.2 BOOTSTRAP (`main.dart`)

| Verificação | Evidência no código | Resultado |
|-------------|---------------------|-----------|
| resolveForAdminApp().timeout(5s) antes de fallback | L733-748: quando `existing == null`, bloco `if (firebaseOk)` chama `StoreResolverFacade.resolveForAdminApp().timeout(Duration(seconds: 5), ...)` e só então preenche `lojaId`; fallback em L751-771 só roda quando `lojaId` continua null/vazio | ✅ Ordem correta |
| Fallback só quando resolve falha/null | L751: `if (lojaId == null || lojaId.isEmpty)` — fallback loja_uid_$uid e loja_email_ só nesse caso | ✅ OK |
| Logs | `[WEB_BOOTSTRAP]` (L726, 758, 766, 774), `[STORE_SESSION]` (L786) | ✅ OK |

### 1.3 TELAS VENDAS E CLIENTES

| Verificação | Evidência | Resultado |
|-------------|-----------|-----------|
| _syncFalhou não mascara carregamento | VendasScreen: `_carregando` controla "Carregando vendas..."; `_syncFalhou` só aparece no body da tela principal (após _carregando = false). ClientesScreen: idem | ✅ Separados |
| Banner não esconde lista | VendasScreen: banner é primeiro filho da Column (L621-649), depois _buildStatisticsHeader e lista; lista permanece visível. ClientesScreen: banner em Positioned(top) e conteúdo em Center/TabBarView abaixo | ✅ OK |
| "Tentar novamente" reexecuta sync | VendasScreen L629-642: onPressed chama `setState(() => _syncFalhou = false)` e `_syncEmBackground()`. ClientesScreen L2910-2914: idem com `_syncClientesEmBackground()` | ✅ OK |
| Regressão visual/funcional | Sem alteração na ordem de exibição (erro loja → carregando → conteúdo); RefreshIndicator continua com onRefresh: _init | ✅ Nenhuma óbvia |

### 1.4 CLIENTES (admin unificado em estoque_clientes)

| Verificação | Evidência | Resultado |
|-------------|-----------|-----------|
| streamClientes, getCliente, searchClientes | `clientes_firestore_service.dart` L255, 274, 319, 328: todos usam `.collection('estoque_clientes')`; comentários FASE 3 presentes | ✅ Consistente |
| Nenhum ponto do admin usando 'clientes' por engano | Admin (VendasScreen, ClientesScreen, Nova Venda) usa Hive + syncFirestoreToHive(estoque_clientes); getCliente/streamClientes/searchClientes não são chamados no projeto (grep FASE 1); quem usa Firestore clientes é portal/auth (ver mapa residual) | ✅ Admin consistente |

### 1.5 POS PAGAMENTO

| Verificação | Evidência | Resultado |
|-------------|-----------|-----------|
| Box por loja usa lojaId do contexto | `_atualizarStatusVenda(String lojaId, String vendaId)` — lojaId é parâmetro; L141: `Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId))` | ✅ OK |
| Chamador passa lojaId | `pre_pedidos_screen.dart` L2406-2407: `processarConfirmacaoPagamento(lojaId: widget.lojaId, ...)` — lojaId vem do widget (tela de pré-pedidos por loja) | ✅ Não nulo no fluxo atual |

---

## 2. O QUE FOI REALMENTE RESOLVIDO

| Item | Arquivo / bloco | Classificação | Evidência |
|------|------------------|----------------|-----------|
| Router não gravar loja quando resolve() null mas sessão tinha valor | app_start_router.dart L532-543 | **RESOLVIDO** | Fallback sessão/config implementado; só return quando ambos null/vazios |
| Bootstrap fixar loja_uid_$uid sem tentar Firestore | main.dart L731-748 | **RESOLVIDO** | resolveForAdminApp().timeout(5s) é a primeira tentativa; fallback só após null |
| Timeout router 3s no Web insuficiente | app_start_router.dart L514 | **RESOLVIDO** | kIsWeb ? 6 : 3 aplicado |
| Duas coleções em ClientesFirestoreService (admin) | clientes_firestore_service.dart streamClientes, getCliente, searchClientes | **RESOLVIDO** | Todos passaram a usar estoque_clientes |
| Box genérica 'vendas' em pos_pagamento | pos_pagamento_service.dart L140-141 | **RESOLVIDO** | HiveBoxNames.vendas(lojaId) e lojaId do parâmetro |
| Falha de sync sem feedback | vendas_screen.dart, clientes_screen.dart | **RESOLVIDO** | _syncFalhou + banner + "Tentar novamente" |

---

## 3. O QUE FOI APENAS MITIGADO

| Item | Motivo | Classificação |
|------|--------|----------------|
| Perda de loja no Web (refresh/sessão) | Router e bootstrap reduzem a chance (fallback + resolve antes de fallback); se IndexedDB/sessão for limpa no refresh, ainda depende de resolve() ou de novo login | **MITIGADO** |
| Cold start Firestore > 3s no Web | Timeout 6s no router e 5s no bootstrap reduzem a probabilidade; em rede muito lenta ainda pode dar null e aí depende do fallback (sessão/config ou loja_uid) | **MITIGADO** |
| Fallback loja_uid_$uid com loja “errada” | Ainda usado quando resolve() falha (primeiro acesso, offline, timeout); dados podem estar em slug no Firestore e o app usar loja_uid_XXX até próxima resolução bem-sucedida | **MITIGADO** (comportamento explícito e logado) |

---

## 4. O QUE AINDA ESTÁ ABERTO

| Item | Evidência / contexto | Classificação |
|------|----------------------|----------------|
| Fallback de sessão com store_id de outro usuário | Router usa sessao.get('store_id') sem validar se pertence ao currentUser; em troca de conta no mesmo dispositivo, se resolve() der timeout, o valor antigo pode ser reutilizado | **AINDA ABERTO** (risco baixo: depende de timeout + troca de usuário no mesmo dispositivo) |
| Primeiro acesso Web sem sessão e resolve() falhando | Nesse caso não há fallback (sessão vazia); usuário vê “Não foi possível carregar a loja” nas telas dependentes até conseguir loja (ex. após retry ou rede melhor) | **AINDA ABERTO** (comportamento esperado; não é regressão) |
| Índice Firestore para estoque_clientes | searchClientes usa where nome + orderBy; se não houver índice composto, a query pode falhar em runtime (não auditado) | **NÃO CONFIRMADO** (sem evidência de índice faltando) |

---

## 5. RISCOS DE REGRESSÃO ENCONTRADOS

| Risco | Verificação | Resultado |
|-------|-------------|-----------|
| Bootstrap travar sem usuário | resolve() retorna null quando currentUser == null (store_resolver_service.dart L44-47); bootstrap então cai no fallback; se não houver uid nem usuario_logado, lojaId fica null e não grava — sem loop, sem bloqueio | ✅ Nenhuma regressão |
| Snackbar/banner em loop | Banner aparece quando _syncFalhou == true; “Tentar novamente” zera _syncFalhou e chama sync; não há timer nem auto-repeat; próximo sync que falhar seta de novo | ✅ Nenhuma regressão |
| Loja errada persistir | Fallback sessão pode ser loja antiga em troca de usuário (ver “Ainda aberto”); não introduzido pela FASE 3 — já existia uso de sessão | ⚠️ Risco residual conhecido |
| pos_pagamento com lojaId ausente | Assinatura exige lojaId; único chamador (pre_pedidos_screen) passa widget.lojaId | ✅ Nenhuma regressão |

---

## 6. MAPA RESIDUAL DE RISCOS

### A. Proteção de tela dependente

- **VendasScreen:** L110-118: se `lojaId == null || lojaId.trim().isEmpty`, seta `_erroResolucaoLoja = true` e **return** — não abre boxes nem chama sync. Boxes abertas só em L122-130, após lojaId válido.
- **ClientesScreen:** L132-140: mesma lógica.
- **Conclusão:** Telas não abrem box nem disparam sync antes de lojaId; não entram em “vazio real” como “resolvendo loja” (estado de erro é explícito).

### B. Fallback loja_uid_$uid

- **Onde:** main.dart L751-760 (bootstrap) quando resolve() retorna null; StoreResolverService L106-118 (Hive sessão) quando Firestore não retorna.
- **Risco:** Primeiro acesso com rede lenta ou offline pode gravar loja_uid_XXX; dados reais podem estar em lojas/<slug>. Refresh no Web: se sessão persistir (IndexedDB), fallback do router usa esse valor — pode ser slug ou loja_uid conforme última escrita.
- **Classificação:** **MITIGADO** (resolve tentado antes; fallback registrado em log).

### C. Root / multi-loja

- **Router:** Quando resolve() é null, root usa config.get('last_loja_id') (L525-527); não-root usa sessão e config (L532-543). Se last_loja_id for de outra loja (root com múltiplas lojas), root pode ficar com “última loja” após timeout.
- **Classificação:** Comportamento aceitável para root; risco **baixo** e não novo.

### D. Clientes — uso restante de collection('clientes')

| Arquivo | Uso | Contexto | Risco |
|---------|-----|----------|--------|
| cliente_auth_service.dart | Várias leituras/escritas em 'clientes' | Auth/cliente final (portal, login cliente) | **Baixo** — fluxo de cliente, não admin |
| pre_pedido_service.dart | collection('clientes') | Pré-pedidos / pedidos | **Médio** — se pré-pedido criar cliente, pode gravar em 'clientes' enquanto admin usa estoque_clientes; dados do admin (Nova Venda) ficam em estoque_clientes |
| migrar_para_estoque.dart | Leitura 'clientes', escrita estoque_clientes | Script de migração | **Baixo** — utilitário |
| sync_firestore_script.dart | 'clientes' | Script sync | **Baixo** — script |
| carrinho_abandonado_service.dart | 'clientes' | Carrinho abandonado | **Baixo** — provável contexto catálogo/portal |
| perfil_cliente_screen.dart | 'clientes' | Perfil do cliente (portal) | **Baixo** |
| cadastro_screen.dart | 'clientes' | Cadastro (auth) | **Baixo** |

**Resumo:** Admin (VendasScreen, ClientesScreen, Nova Venda, ClientesFirestoreService sync/get/stream/search) está em **estoque_clientes**. Uso restante de **clientes** é **portal / auth / scripts**; risco de divergência é entre “cliente do catálogo/pré-pedido” (clientes) e “cliente do admin” (estoque_clientes) — documentado, sem alteração na FASE 4.

### E. Regressões

- Nenhuma regressão funcional ou de travamento identificada nos pontos alterados (router, bootstrap, vendas_screen, clientes_screen, clientes_firestore_service, pos_pagamento_service).

### F. Cenários lógicos (resultado esperado — ETAPA 4)

| Cenário | Fluxo no código | Resultado esperado |
|---------|------------------|--------------------|
| **1. Web rede normal: login → vendas → salvar venda → refresh → clientes** | Router resolve() retorna store_id; sessão gravada; VendasScreen abre com lojaId; venda em estoque_vendas + Hive; refresh: bootstrap pode ter existing = store_id (sessão persistida); ou router de novo com resolve() ou fallback sessão; ClientesScreen com mesmo lojaId | Lista de vendas e clientes permanecem após refresh |
| **2. Web rede lenta: resolve demora → router fallback → vendas/clientes** | resolve() timeout 6s → null; router L532-543: fromSessao ou fromConfig preenchido (ex. sessão anterior) → loja = esse valor; grava L551-558. Telas usam LojaIdService.getWithTimeout(10s) que pode vir da sessão | Telas abrem com loja da sessão/config; sem tela em branco por “nenhuma loja” |
| **3. Web sem rede após abrir tela: sync falha → lista local → banner → tentar novamente** | _syncEmBackground() em catch seta _syncFalhou = true (vendas_screen L193-194, clientes_screen L222); banner exibido; “Tentar novamente” chama _syncEmBackground() de novo; sem rede, falha de novo e _syncFalhou = true de novo | Lista local visível; banner reaparece; sem loop infinito de snackbar |
| **4. Android normal: login → vendas → criar venda → listar clientes** | Sem branch por plataforma no fluxo de venda; lojaId do LojaIdService; boxes por loja; sync igual | Comportamento igual ao atual; sem regressão |
| **5. Root / multi-loja: timeout resolve → last_loja_id existe → troca de loja** | Root: L525-527 usa last_loja_id quando loja null; esse valor é gravado em sessao/config. Se root trocou de loja antes e last_loja_id foi atualizado, reflete última. Se não trocou, mantém antiga até próximo resolve() bem-sucedido | Risco aceitável; não corrigido na FASE 3 |

---

## 7. AJUSTES PEQUENOS E SEGUROS (OPCIONAIS)

Apenas ajustes de reforço, sem mudar comportamento:

1. **Router — guard de consistência (opcional):** Ao usar fallback de sessão/config (L536 ou L540), logar também o UID atual (se disponível) para facilitar diagnóstico de “store_id de outro usuário”. Ex.: `logD('🔄 [ROUTER_GUARD] Fallback sessão → store_id=$loja | uid=${FirebaseAuth.instance.currentUser?.uid}')`. **Risco:** nenhum. **Benefício:** debug em troca de usuário.

2. **VendasScreen / ClientesScreen — comentário de estado:** Junto a `_syncFalhou`, comentar explicitamente: “Não confundir com lista vazia: lista pode estar vazia por falta de dados; _syncFalhou indica falha de rede/sync.” **Risco:** nenhum.

3. **pos_pagamento_service — guard lojaId vazio:** No início de `_atualizarStatusVenda`, se `lojaId.trim().isEmpty`, logar e return early para não abrir box `vendas_` (nome degenerado). **Risco:** baixo (chamador já passa widget.lojaId). **Benefício:** proteção defensiva.

4. **Bootstrap — log quando não há usuário:** Dentro do try de resolve (L734), quando `lojaId == null` após o await, em kDebugMode logar “StoreResolver retornou null (usuário não logado?)” para distinguir null por timeout de null por sem usuário. **Risco:** nenhum.

5. **Clientes — documentação:** No topo de `clientes_firestore_service.dart`, comentar em uma linha: “Admin: leitura e escrita em estoque_clientes; portal/auth podem usar coleção 'clientes' em outros serviços.” **Risco:** nenhum.

Nenhum desses é obrigatório para considerar a FASE 3 válida.

---

## 8. VEREDITO FINAL

### O problema principal pode ser considerado resolvido?

**Sim, com ressalvas.**

- **Resolvido no código:**
  - Router não deixa de gravar loja quando há valor em sessão/config (fallback).
  - Bootstrap tenta StoreResolver antes de fixar loja_uid_$uid.
  - Timeout maior no Web (6s no router, 5s no bootstrap) reduz cold start como causa.
  - Admin de clientes unificado em estoque_clientes (leitura e escrita).
  - Box de vendas no pós-pagamento por loja.
  - Feedback claro quando o sync falha (banner + “Tentar novamente”).

- **Mitigado, mas não eliminado:**
  - Se no Web a sessão for limpa (ex.: refresh em modo anônimo ou limpeza de dados), o app depende de resolve() ou de novo login; não há “recuperação mágica”.
  - Fallback loja_uid_$uid ainda existe para primeiro acesso/offline; se os dados estiverem só em lojas/<slug>, até o próximo resolve() bem-sucedido o app pode usar loja_uid_XXX.

- **Ainda aberto (risco residual):**
  - Fallback de sessão no router não valida se store_id pertence ao currentUser (cenário: troca de usuário no mesmo dispositivo + timeout no resolve).

**Conclusão:** Para o cenário típico (usuário já logado, sessão persistida, rede razoável), o problema de “vendas e clientes sumindo no Web” e “divergência APK/Web” está **resolvido ou fortemente mitigado** pelas mudanças da FASE 3. Causas raiz atacadas (C2, C3, C1, C4, C5) estão tratadas no código. Riscos residuais são edge cases (primeiro acesso sem rede, troca de usuário com timeout, sessão limpa) e não indicam regressão da FASE 3.

**Recomendação:** Considerar o problema principal **resolvido** para efeito de release, com monitoramento (logs com tags) e, se necessário, aplicação dos ajustes pequenos da seção 8 em um MR separado.
