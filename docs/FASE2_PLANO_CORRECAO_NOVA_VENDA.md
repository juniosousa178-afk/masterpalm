# FASE 2 — PLANO DE CORREÇÃO (Nova Venda / Vendas / Clientes / Loja)

**Base:** Achados confirmados da FASE 1 (C1–C6) e fortemente suspeitos (S1–S4).  
**Objetivo:** Plano seguro, priorizado e executável na FASE 3, sem implementação nesta etapa.

---

## 1. PRIORIZAÇÃO DAS CAUSAS

| Causa | Classificação | Justificativa |
|-------|----------------|---------------|
| **C3** — Router timeout 3s não grava loja na sessão | **CRÍTICO IMEDIATO** | No Web, cold start (S2) pode estourar 3s; sessão fica com loja_uid_XXX do bootstrap ou vazia; todas as telas dependentes (vendas, clientes) usam lojaId errado ou null. Impacto direto em “vendas/clientes somem”. |
| **C2** — Bootstrap grava loja_uid_$uid sem StoreResolver | **CRÍTICO IMEDIATO** | Define store_id antes do router; se o router der timeout, esse valor permanece; sync e boxes usam loja_uid_XXX em vez do slug real do Firestore. |
| **C1** — Duas coleções em ClientesFirestoreService | **ALTO** | Inconsistência real no código (escrita em estoque_clientes, leitura em clientes em 3 métodos). Hoje sem chamadores no admin; risco futuro e possível uso em portal/outros fluxos. Unificar evita bugs ao reutilizar esses métodos. |
| **C5** — Sync em background falha silenciosamente | **ALTO** | Usuário vê lista vazia sem distinguir “vazio real” vs “erro de sync” vs “loja não resolvida”. Agrava percepção de “dados sumiram” e dificulta diagnóstico. |
| **C4** — pos_pagamento_service usa box 'vendas' genérica | **MÉDIO** | Único ponto que usa box sem lojaId; pode gravar/ler em contexto errado em multi-tenant. Impacto restrito ao fluxo de pós-pagamento (catálogo/checkout). |
| **C6** — StoreResolverService.set(loja) não persiste argumento | **MÉDIO** | Comportamento intencional (loja fixa por usuário). O problema não é set() em si, e sim o router depender de resolve() dentro de set() após já ter escrito na sessão. Ajuste é no router/bootstrap, não no set(). |
| **S1** — Refresh Web perde sessão | **MÉDIO** | Mitigação: garantir que, após resolve(), sessão seja persistida de forma estável; não “corrigir” refresh diretamente sem evidência. |
| **S2** — Cold start > 3s no Web | **ALTO (já coberto por C3)** | Tratado ao aumentar tempo e/ou garantir fallback seguro no router. |
| **S3** — Catálogo/fornecedores outra fonte | **BAIXO** | Explicação plausível do sintoma; não exige correção de código, apenas não depender de que “tudo use o mesmo lojaId” para diagnóstico. |
| **S4** — Sobrescrever cache com vazio | **MÉDIO** | Investigação na FASE 3 antes de mudar lógica de sync (ver se há clear + add ou merge). |

---

## 2. ORDEM IDEAL DE CORREÇÃO

1. **Router + persistência de loja (C3, C6 em parte)**  
   Garantir que, após login, a sessão receba um store_id válido mesmo com delay do Firestore: aumentar timeout e/ou gravar last_loja_id quando resolve() demorar, e não sair sem gravar quando já existir valor em sessão/config.

2. **Bootstrap (C2)**  
   Evitar fixar loja_uid_$uid quando for possível obter store_id do Firestore (ex.: tentar resolve() ou leitura mínima users/{uid}.store_id) antes de escrever na sessão; ou não preencher store_id no bootstrap e deixar só o router/telas fazerem o resolve.

3. **Feedback de sync (C5)**  
   Diferenciar na UI: carregando / vazio real / erro de sync / loja não resolvida. Evita “tela vazia sem explicação” e melhora diagnóstico.

4. **Unificação de coleção de clientes (C1)**  
   Fazer streamClientes, getCliente e searchClientes usarem estoque_clientes (ou leitura híbrida temporária se houver dependentes na coleção “clientes”). Exige checagem de quem usa esses métodos (portal, auth cliente).

5. **Box genérica de vendas (C4)**  
   Em pos_pagamento_service usar HiveBoxNames.vendas(lojaId) e obter lojaId do contexto da chamada (parâmetro ou resolução explícita).

6. **Logs temporários**  
   Incluir tags [STORE_RESOLVE], [STORE_SESSION], [VENDAS_READ], [CLIENTES_READ], [SYNC], etc., com lojaId, plataforma, contagens, para validar em produção/homologação.

7. **Investigação S4**  
   Revisar SyncQueueService / AutoSyncService para ver se há sobrescrita de cache válido com vazio; só então propor mudança de comportamento.

Ordem: primeiro **contexto de loja (router + bootstrap)**, depois **visibilidade de falhas (sync)** e **consistência de dados (clientes, box vendas)**, por último **logs e investigação**.

---

## 3. ARQUIVOS QUE DEVEM SER ALTERADOS

| Arquivo | Motivo da alteração |
|---------|---------------------|
| **lib/screens/app_start_router.dart** | (C3) Aumentar timeout do resolve no _bindActiveStore; quando resolve() retornar null, não sair sem gravar: usar last_loja_id da config (não só para root) ou valor já presente na sessão, e gravar na sessão; garantir que “nenhuma loja encontrada” só ocorra quando realmente não houver valor persistido. |
| **lib/main.dart** | (C2) Em _ensureStoreIdOnBootstrap, quando existing for null: em vez de fixar loja_uid_$uid de imediato, tentar obter store_id via StoreResolverFacade.resolveForAdminApp() com timeout curto (ex. 5s); só se falhar ou retornar null usar fallback loja_uid_$uid / loja_email_ e gravar. Assim o bootstrap não “fixa” loja errada quando o Firestore já tiver o store_id. |
| **lib/screens/vendas_screen.dart** | (C5) Em _init, distinguir estado _erroResolucaoLoja vs “loja ok mas sync falhou”; em _syncEmBackground, em catch setar um estado tipo _syncFalhou e exibir indicador ou snackbar (“Falha ao sincronizar; tente puxar para atualizar” ou “Sem conexão”). Não bloquear exibição da lista local. |
| **lib/screens/clientes_screen.dart** | (C5) Mesmo padrão: estado de erro de sync e feedback (snackbar ou indicador), sem esconder lista local. |
| **lib/services/clientes_firestore_service.dart** | (C1) Fazer streamClientes, getCliente e searchClientes lerem da coleção **estoque_clientes** (mesma do sync). Se houver dependentes da coleção “clientes” (ex. ClienteAuthService, portal), planejar compatibilidade temporária (leitura híbrida ou migração) e documentar. |
| **lib/services/pos_pagamento_service.dart** | (C4) Onde hoje usa Hive.openBox<Venda>('vendas'), passar a usar HiveBoxNames.vendas(lojaId) e obter lojaId do parâmetro da função ou do contexto (ex. já recebido no fluxo de atualização de status). Ver assinaturas das funções que usam essa box. |
| **lib/core/logger.dart** ou pontos de log existentes | Estratégia de logs temporários: em StoreResolverService.resolve(), _bindActiveStore, LojaIdService.get, VendasScreen._init, ClientesScreen._init, syncFirestoreToHive (vendas e clientes), registrar com tags [STORE_RESOLVE], [STORE_SESSION], [WEB_BOOTSTRAP], [ROUTER_GUARD], [VENDAS_READ], [CLIENTES_READ], [SYNC], incluindo quando possível: plataforma (kIsWeb), uid, lojaId, coleção/box, quantidade de registros, origem (local/remota), motivo de erro. |

Nenhum outro arquivo deve ser alterado na primeira leva de correções, exceto se a investigação de S4 ou de consumidores de getCliente/searchClientes exigir.

---

## 4. CORREÇÕES COM ALTA CONFIANÇA (seguras para FASE 3)

- **Router: não sair sem gravar quando já existir loja em sessão/config**  
  Se resolve() der timeout (null), antes de `return` verificar sessao.get('store_id') e config.get('last_loja_id'); se algum tiver valor, usar esse valor e gravar em sessao/config (e logar [ROUTER_GUARD] fallback). Assim não se “perde” o store_id em refresh ou após timeout. Alteração local em _bindActiveStore, sem mudar contrato do resolve().

- **Router: aumentar timeout de 3s para 5s ou 6s no Web**  
  Reduz chance de timeout em cold start; sem mudar lógica, só constante. Pode ser condicional: `kIsWeb ? Duration(seconds: 6) : Duration(seconds: 3)`.

- **Bootstrap: tentar resolve antes de fallback**  
  Em _ensureStoreIdOnBootstrap, quando existing for null, chamar StoreResolverFacade.resolveForAdminApp().timeout(5s). Se retornar valor não vazio, usar esse valor e gravar; só então usar loja_uid_$uid / loja_email_ como fallback. Mantém compatibilidade para quando Firestore não responder (offline, primeiro acesso).

- **Feedback de sync em VendasScreen e ClientesScreen**  
  Adicionar variável de estado _syncFalhou (bool ou enum: ok / falhou / nunca rodou). No catch de _syncEmBackground, setar _syncFalhou = true e setState. Na UI, se _syncFalhou mostrar snackbar ou texto discreto (“Sincronização falhou. Puxe para atualizar.”) sem esconder a lista. Não alterar ordem de carregamento nem bloquear tela.

- **pos_pagamento_service: usar box por loja**  
  Verificar assinatura de _atualizarStatusVenda e chamadores: se já recebem lojaId, passar lojaId para a abertura da box (HiveBoxNames.vendas(lojaId)). Se não recebem, adicionar parâmetro lojaId na função que atualiza o Hive. Não alterar lógica de negócio, só origem da box.

- **Logs temporários com tags**  
  Inserir logD/logW com as tags acordadas nos pontos listados (resolve, _bindActiveStore, get, _init das telas, sync), com dados não sensíveis (lojaId, contagem, plataforma). Pode ser guardado por flag kDebugMode ou remote config para desligar em produção depois.

Todas as acima atacam causa raiz ou sintoma confirmado e têm escopo limitado, com baixo risco de quebrar fluxos existentes se testadas em dev/homologação.

---

## 5. CORREÇÕES QUE EXIGEM COMPATIBILIDADE TEMPORÁRIA

- **Unificação da coleção de clientes (C1)**  
  - **Cenário:** ClienteAuthService e outros (portal, cadastro cliente) podem usar a coleção **clientes** (auth do cliente final). Clientes do **admin** (Nova Venda, ClientesScreen) usam **estoque_clientes**.  
  - **Estratégia:**  
    1) Confirmar quem lê **clientes** no projeto (grep e leitura de chamadas).  
    2) Se só admin usar getCliente/streamClientes/searchClientes: trocar para **estoque_clientes** e encerrar.  
    3) Se portal/auth usarem **clientes**: manter **clientes** para esse fluxo e fazer os 3 métodos do **admin** usarem **estoque_clientes** (ex. métodos internos _streamClientesAdmin, _getClienteAdmin, _searchClientesAdmin que leem estoque_clientes), ou adicionar parâmetro opcional `useEstoqueClientes` (default true para admin). Assim evita quebrar portal e unifica o uso admin.  
  - **Compatibilidade temporária:** Se no Firestore ainda existir dado só em “clientes” e não em “estoque_clientes”, não apagar “clientes”; migração de dados em script separado, se necessário.

- **Bootstrap e primeiro acesso**  
  Se no primeiro acesso (sem sessão) o resolve() falhar ou demorar, manter fallback loja_uid_$uid para não travar o app; mas logar [WEB_BOOTSTRAP] fallback usado. Assim mantém compatibilidade com usuário novo ou offline.

- **Router: root vs não-root**  
  Manter comportamento atual para root (last_loja_id); para não-root, ao dar timeout, usar last_loja_id **apenas se** o usuário for da mesma loja (ex. vendedor já vinculado). Caso contrário, não preencher com loja de outro usuário; apenas logar e deixar sessão com o que já estava (evitando sobrescrever com null).

---

## 6. RISCOS DE REGRESSÃO POR ALTERAÇÃO

| Correção | O que pode quebrar | Como evitar | Como validar |
|----------|--------------------|------------|--------------|
| Router: usar sessão/config quando resolve() null | Root com múltiplas lojas poderia ficar com loja “antiga” após timeout. | Aplicar fallback de sessão/last_loja_id apenas quando resolve() retornar null; root já usa last_loja_id hoje. Não mudar lógica do root. | Testar Web: simular timeout (ex. throttle Firestore) e ver se sessão mantém store_id; testar troca de loja (root). |
| Router: aumentar timeout 3s → 6s no Web | Tela “Preparando loja...” pode ficar mais tempo visível. | 6s ainda aceitável; opcionalmente mostrar “Ainda resolvendo…” após 3s. | Testar login Web e medir tempo até home. |
| Bootstrap: tentar resolve antes de fallback | Bootstrap mais lento no primeiro acesso se Firestore demorar. | Timeout curto (5s); em falha, cair no fallback atual (loja_uid_$uid). | Testar primeiro acesso (sessão vazia) com rede lenta e com rede ok. |
| Feedback de sync (estado _syncFalhou) | Snackbar pode ser intrusivo se sync falhar com frequência (ex. usuário offline). | Uma snackbar por sessão de tela ou “Puxe para atualizar” sem auto-repetir. | Testar com rede desligada e com rede instável. |
| ClientesFirestoreService: estoque_clientes em stream/get/search | Qualquer código que dependa de “clientes” (portal, auth) pode deixar de ver dados. | Antes: grep e análise de chamadores. Se houver: método separado ou parâmetro useEstoqueClientes; senão, trocar direto. | Após alteração: smoke test admin (lista clientes, Nova Venda, busca) e smoke test login/cadastro cliente se existir. |
| pos_pagamento_service: box vendas_lojaId | Se lojaId não for passado corretamente, box pode não existir ou ser de outra loja. | Garantir que a função que chama _atualizarStatusVenda (ou equivalente) já tenha lojaId e o repasse. | Testar fluxo de pagamento concluído (catálogo → pagamento → atualização de status) em uma loja específica. |
| Logs com tags | Volume de log em produção. | Usar logD (debug) ou condição kDebugMode / feature flag para não logar em release. | Verificar que em release os logs não aparecem ou são filtrados. |

---

## 7. PLANO DE IMPLEMENTAÇÃO DA FASE 3

**Passo 1 — Router (_bindActiveStore)**  
- Aumentar timeout do resolve no Web (ex. 6s).  
- Quando resolve() retornar null: ler sessao.get('store_id') e config.get('last_loja_id'); se algum tiver valor não vazio, gravar esse valor em sessao e config e logar [ROUTER_GUARD] fallback; só então return se continuar null (ex. primeiro acesso sem nenhum valor).  
- Adicionar logs [ROUTER_GUARD] e [STORE_RESOLVE] com lojaId (quando houver), plataforma, e se entrou em fallback.

**Passo 2 — Bootstrap (_ensureStoreIdOnBootstrap)**  
- Quando existing for null: chamar StoreResolverFacade.resolveForAdminApp().timeout(Duration(seconds: 5)).  
- Se retornar string não vazia: usar como lojaId e gravar em sessao/config (e LojaIdService.set).  
- Se timeout ou null: manter lógica atual (loja_uid_$uid ou loja_email_...) e gravar; logar [WEB_BOOTSTRAP] fallback.  
- Logar [WEB_BOOTSTRAP] com resultado (resolvido vs fallback).

**Passo 3 — Feedback de sync (VendasScreen)**  
- Adicionar _syncFalhou (bool). Em _syncEmBackground, no catch: setState(() => _syncFalhou = true). Na árvore da tela, se _syncFalhou mostrar SnackBar ou texto “Sincronização falhou. Puxe para atualizar.” (uma vez por abertura ou com botão “Tentar de novo”).  
- Opcional: botão “Tentar sincronizar” que chama _syncEmBackground e zera _syncFalhou.

**Passo 4 — Feedback de sync (ClientesScreen)**  
- Mesmo padrão do Passo 3 para _syncClientesEmBackground.

**Passo 5 — ClientesFirestoreService (unificação de coleção)**  
- Grep por getCliente, searchClientes, streamClientes. Se não houver chamadores fora do admin (ou não houver chamadores): alterar streamClientes, getCliente e searchClientes para usar collection('estoque_clientes').  
- Se houver chamadores que dependem de “clientes”: implementar compatibilidade (métodos separados ou parâmetro) conforme item 5 do plano.  
- Adicionar log [CLIENTES_READ] com coleção usada e lojaId.

**Passo 6 — pos_pagamento_service (box por loja)**  
- Localizar chamadas a _atualizarStatusVenda (ou função que abre box 'vendas'). Incluir lojaId no parâmetro se não existir.  
- Substituir Hive.openBox<Venda>('vendas') por Hive.openBox<Venda>(HiveBoxNames.vendas(lojaId)).  
- Validar fluxo de pós-pagamento em uma loja.

**Passo 7 — Logs temporários**  
- Em StoreResolverService.resolve(): log [STORE_RESOLVE] com lojaId resolvido, fonte (cache, users, usuarios, hive, slug), e se é Web.  
- Em LojaIdService.get/getWithTimeout: log [STORE_SESSION] com lojaId retornado e se veio de resolve ou Hive.  
- Em VendasScreen._init após abrir boxes: log [VENDAS_READ] com lojaId e vendasBox.length.  
- Em ClientesScreen._init: log [CLIENTES_READ] com lojaId e clientesBox.length.  
- Em syncFirestoreToHive (vendas e clientes): log [SYNC] com lojaId, quantidade importada, e em falha o motivo.  
- Condicionar logs a kDebugMode ou a flag para não poluir produção.

**Passo 8 — Testes manuais e revisão**  
- Android: login → Vendas → Nova Venda → ver venda na lista; refresh ou reabrir app e conferir lojaId e lista.  
- Web: mesmo fluxo; refresh e conferir se store_id permanece e lista não some.  
- Web: simular rede lenta (DevTools) e conferir se router usa fallback de sessão e se aparece feedback de sync ao falhar.  
- Conferir que catálogo e fornecedores continuam funcionando na mesma loja.

**Passo 9 (opcional) — Investigação S4**  
- Abrir SyncQueueService e AutoSyncService; ver se em algum momento há clear() da box antes de preencher com dados do Firestore; se sim, documentar e propor regra “não limpar se Firestore retornar vazio e já houver dados locais” em fase posterior.

---

## Resumo executivo do plano

- **Crítico imediato:** C3 (router) e C2 (bootstrap). Corrigir primeiro: router não sair sem gravar quando já houver loja em sessão/config; bootstrap tentar resolve() antes de fixar loja_uid_$uid.  
- **Alto:** C1 (unificar coleção clientes) e C5 (feedback de sync). C1 com checagem de chamadores e compatibilidade se houver uso de “clientes”; C5 com estado de erro e snackbar sem bloquear lista.  
- **Médio:** C4 (box vendas em pos_pagamento) e C6 (tratado indiretamente pelo router). Logs temporários em todos os pontos sensíveis.  
- **Não alterar agora:** Lógica do StoreResolverService.resolve() (ordem de fontes), regras de “um usuário = uma loja”, e fluxo completo de Nova Venda/estoque.  
- **Investigar antes de mudar:** Quem usa getCliente/searchClientes/streamClientes; se SyncQueue/AutoSync sobrescrevem cache com vazio (S4).

Este documento é a entrega da FASE 2. Nenhum arquivo foi alterado.
