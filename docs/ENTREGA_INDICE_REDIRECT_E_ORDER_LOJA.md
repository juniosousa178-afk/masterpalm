# Entrega: Índices redirectCatalogo e findLojaIdByOrderId (escalabilidade)

**Data:** 2025-03-06  
**Objetivo:** Eliminar (ou reduzir drasticamente) a iteração por todas as lojas em `redirectCatalogo` e `findLojaIdByOrderId`, mantendo compatibilidade com links e pedidos antigos.

---

## 1. Diagnóstico resumido do problema atual

- **redirectCatalogo** (Cloud Function, `functions/index.js`):  
  Rota: GET `/c/:short` (rewrite no Hosting). Faz `db.collection('lojas').get()` e percorre **todas** as lojas comparando `linkCurto` e `slug` com `short`. Uma leitura por loja em memória; N leituras (1 da coleção lojas) + latência proporcional ao número de lojas. Com muitas lojas: custo de leitura alto, latência e risco de timeout.

- **findLojaIdByOrderId** (em `functions/index.js` e `functions/src/mpWebhookHandler.js`):  
  Usado quando o webhook MP não traz `metadata.lojaId`. Faz `lojas.get()` e, para **cada** loja, lê `lojas/{id}/pedidos/{orderId}` e, no handler do webhook, também `lojas/{id}/pre_pedidos/{orderId}`. Até 2×N leituras (N = número de lojas). Custo e latência crescem com N.

- **Coleções/caminhos consultados hoje:**
  - redirectCatalogo: `lojas` (get completo).
  - findLojaIdByOrderId: `lojas` (select) e, por loja, `lojas/{id}/pedidos/{orderId}` e `lojas/{id}/pre_pedidos/{orderId}`.

- **Links/rotas que dependem:**  
  Hosting rewrite `/c/**` → `redirectCatalogo`. Qualquer link curto tipo `https://app.../c/meuslug` ou `/c/linkcurto` depende dessa resolução.

- **Fluxos que usam:**  
  (1) Usuário abre link curto (email, WhatsApp, etc.) → redirectCatalogo.  
  (2) Webhook MP sem metadata.lojaId → findLojaIdByOrderId para achar a loja do pedido.

---

## 2. Solução escolhida e por quê

Foi adotada **solução com duas coleções índice** (opção A do escopo):

- **catalog_redirect_index**  
  Doc ID = short normalizado (lowercase). Campos: `lojaId`, `slug`.  
  Uma leitura por short; redirectCatalogo usa o índice primeiro e, se não achar, faz o fallback (iterar lojas) e grava no índice para as próximas vezes.

- **order_loja_index**  
  Doc ID = orderId. Campos: `lojaId`, `origem` (`pedidos` ou `pre_pedidos`), `criadoEm`.  
  Uma leitura por orderId; findLojaIdByOrderId usa o índice primeiro e, se não achar, varre pedidos e pre_pedidos (fallback) e grava no índice ao encontrar.

**Por quê:**  
- Menor risco de regressão: fallback igual ao comportamento atual; links e webhooks antigos continuam funcionando.  
- Menor custo: após índice populado, 1 leitura por request em vez de N.  
- Compatível com pedidos/links antigos: fallback cobre o que ainda não está no índice.  
- Escalável: custo O(1) por resolução quando o índice está populado.  
- Incremental: novos pedidos/lojas alimentam o índice; backfill opcional para histórico.

Alternativas descartadas: (B) pedido_status_publico não cobre todos os pedidos e não existe para pre_pedidos antes do pagamento; (C) híbrido seria mais complexo sem ganho claro frente a um índice único por orderId.

---

## 3. Lista exata dos arquivos impactados

| Arquivo | Alteração |
|--------|-----------|
| `functions/src/orderLojaIndex.js` | **Novo.** Resolução orderId → lojaId com índice + fallback; `writeOrderLojaIndex`, `readOrderLojaIndex`, `resolveLojaIdByOrderId`. |
| `functions/src/catalogRedirectIndex.js` | **Novo.** Resolução short → loja/slug; `getRedirectTarget`, `syncCatalogRedirectIndex`. |
| `functions/index.js` | `findLojaIdByOrderId` passa a usar `resolveLojaIdByOrderId`. `redirectCatalogo` usa `getRedirectTarget` primeiro e fallback com `syncCatalogRedirectIndex`. Novo trigger `onLojaWrittenSyncCatalogRedirect` em `lojas/{lojaId}`. |
| `functions/src/mpWebhookHandler.js` | `findLojaIdByOrderId` passa a usar `resolveLojaIdByOrderId` de `orderLojaIndex.js`. |
| `firestore.rules` | Regras para `order_loja_index` e `catalog_redirect_index` (read/write: false; só Admin SDK). |
| `functions/backfill_catalog_redirect_index.js` | **Novo.** Backfill do índice de link curto a partir das lojas. |
| `functions/backfill_order_loja_index.js` | **Novo.** Backfill do índice pedido→loja a partir de pedidos/pre_pedidos. |
| `docs/ENTREGA_INDICE_REDIRECT_E_ORDER_LOJA.md` | Este documento. |

---

## 4. Código das alterações (resumo)

- **orderLojaIndex.js:**  
  - `writeOrderLojaIndex(db, orderId, lojaId, origem)` grava em `order_loja_index/{orderId}`.  
  - `readOrderLojaIndex(db, orderId)` lê e retorna `lojaId` ou null.  
  - `resolveLojaIdByOrderId(db, orderId)`: lê índice; se não achar, percorre lojas → pedidos, depois lojas → pre_pedidos; ao achar, grava no índice e retorna lojaId.

- **catalogRedirectIndex.js:**  
  - `getRedirectTarget(db, short)` lê `catalog_redirect_index/{normalize(short)}` e retorna `{ lojaId, slug }` ou null.  
  - `syncCatalogRedirectIndex(db, lojaId, lojaData)` escreve entradas para `linkCurto` e `slug` (ambos como doc ID normalizado) com `{ lojaId, slug }`.

- **index.js:**  
  - `redirectCatalogo`: chama `getRedirectTarget(db, short)`; se existir target com slug, redirect; senão loop em lojas (fallback), ao achar chama `syncCatalogRedirectIndex` e faz redirect.  
  - `findLojaIdByOrderId(orderId)`: delega para `resolveLojaIdByOrderId(db, orderId)`.  
  - `onLojaWrittenSyncCatalogRedirect`: onDocumentWritten em `lojas/{lojaId}`; lê data e chama `syncCatalogRedirectIndex(db, lojaId, data)`.

- **mpWebhookHandler.js:**  
  - `findLojaIdByOrderId(orderId)` passa a chamar `resolveLojaIdByOrderId(getDb(), orderId)`.

- **firestore.rules:**  
  - `match /order_loja_index/{orderId}` e `match /catalog_redirect_index/{short}` com `allow read, write: if false;` (acesso apenas via Admin SDK).

---

## 5. Estratégia de compatibilidade preservada

- **Links antigos:**  
  Se o short ainda não estiver em `catalog_redirect_index`, redirectCatalogo usa o mesmo loop em lojas de antes, redireciona corretamente e ainda chama `syncCatalogRedirectIndex` para essa loja, alimentando o índice para as próximas requisições.

- **Pedidos antigos:**  
  Se o orderId não estiver em `order_loja_index`, `resolveLojaIdByOrderId` faz a varredura em pedidos e pre_pedidos como hoje; ao achar, grava no índice e retorna o mesmo lojaId. Comportamento idêntico ao atual.

- **Semântica dos links:**  
  Continua sendo `/c/:short` → redirect 302 para `/loja/:slug`. Nenhuma mudança de URL ou contrato.

- **Separação por lojaId:**  
  Índices só guardam mapeamento (short→loja/slug, orderId→loja). Todas as leituras/escritas de pedidos e dados continuam em `lojas/{lojaId}/...`.

- **Nada destrutivo:**  
  Não há migração que apague ou altere dados existentes; apenas escrita em novas coleções e leitura com fallback.

---

## 6. Estratégia de backfill

- **catalog_redirect_index:**  
  Script `backfill_catalog_redirect_index.js`: lê até N lojas (default 500), para cada uma chama `syncCatalogRedirectIndex`.  
  Uso: `node ./backfill_catalog_redirect_index.js [--dry-run] [--limit N]`.  
  Recomendação: rodar primeiro com `--dry-run` e depois sem para popular o índice. Novas lojas e atualizações em `lojas/{lojaId}` passam a ser refletidas pelo trigger `onLojaWrittenSyncCatalogRedirect`.

- **order_loja_index:**  
  Script `backfill_order_loja_index.js`: para cada loja (até N), lê todos os docs de `pedidos` e `pre_pedidos` e grava em `order_loja_index`.  
  Uso: `node ./backfill_order_loja_index.js [--dry-run] [--limit N] [--skip-existing]`.  
  `--skip-existing` evita sobrescrever orderIds já presentes (útil para rodadas incrementais).  
  Recomendação: rodar com `--dry-run` e depois em lotes (ex.: `--limit 50`), ou com `--skip-existing` em produção para não reprocessar o que já existe. Novos pedidos passam a ser indexados quando o webhook (ou qualquer uso de `resolveLojaIdByOrderId`) encontra o pedido no fallback e grava no índice.

- **Sem migração destrutiva:**  
  Nenhum script altera ou remove dados em lojas, pedidos ou pre_pedidos. Apenas adiciona documentos nas coleções de índice.

---

## 7. Checklist de testes manuais

- [ ] **Deploy:** Fazer deploy das Cloud Functions (incluindo `redirectCatalogo`, `onLojaWrittenSyncCatalogRedirect`) e das regras Firestore. Garantir que as novas coleções existam (criadas na primeira escrita).
- [ ] **Link curto já no índice:** Criar/editar uma loja com slug/linkCurto; abrir `/c/linkcurto` ou `/c/slug` e verificar redirect 302 para `/loja/{slug}`. Conferir uma leitura em `catalog_redirect_index` (logs ou Firestore).
- [ ] **Link curto só no fallback:** Usar um short de uma loja que ainda não passou pelo trigger/backfill; verificar que o redirect continua correto e que, após a requisição, o doc aparece em `catalog_redirect_index`.
- [ ] **Webhook MP com metadata.lojaId:** Garantir que o fluxo segue usando lojaId do metadata (sem chamar findLojaIdByOrderId para esse caso).
- [ ] **Webhook MP sem metadata (orderId novo):** Simular webhook para um pedido que existe em `pedidos` ou `pre_pedidos`; verificar que o processamento encontra a loja (índice ou fallback), que o pedido é atualizado na loja correta e que `order_loja_index` ganha o doc (após fallback).
- [ ] **Webhook MP sem metadata (orderId antigo):** OrderId que já estava no sistema antes do índice; deve ser resolvido pelo fallback e, após isso, o índice deve ficar populado para esse orderId.
- [ ] **Backfill catalog:** Rodar `backfill_catalog_redirect_index.js --dry-run` e depois sem dry-run; conferir docs em `catalog_redirect_index` para as lojas processadas.
- [ ] **Backfill order_loja:** Rodar `backfill_order_loja_index.js --dry-run --limit 5` e depois com limit pequeno; conferir docs em `order_loja_index` e que findLojaIdByOrderId passa a acertar com 1 leitura para esses orderIds.
- [ ] **Sem mistura entre lojas:** Garantir que um orderId de loja A não retorna loja B (índice e fallback devem manter loja correta).

---

## 8. Riscos residuais

- **Trigger onLojaWrittenSyncCatalogRedirect:** Qualquer write em `lojas/{lojaId}` (incluindo campos que não sejam slug/linkCurto) dispara o trigger; é idempotente e só reescreve as entradas do índice para essa loja. Custo adicional por atualização de loja: 1 batch com até 2 writes.
- **Concorrência:** Dois requests simultâneos para o mesmo orderId sem índice podem ambos fazer o fallback e ambos gravar no índice; resultado final é o mesmo (mesmo lojaId).
- **Backfill order_loja em produção:** Rodar com muitos `--limit` ou sem `--skip-existing` pode gerar muitas escritas; preferir lotes e, se necessário, `--skip-existing` após primeira rodada.
- **Dados sensíveis:** Índices guardam apenas orderId, lojaId, short, slug; não guardam dados de pedido ou cliente.

---

## 9. O que fica para a próxima etapa

- Monitorar custo de leitura e latência de redirectCatalogo e do webhook após deploy (ex.: Cloud Monitoring / logs).
- Opcional: remover o fallback de redirectCatalogo (só usar índice) após backfill completo e período de observação; manter fallback de findLojaIdByOrderId por segurança para pedidos antigos ou criados fora do fluxo que escreve o índice.
- Documentar no runbook que novas coleções (`order_loja_index`, `catalog_redirect_index`) são somente backend e não devem ser alteradas pelo app ou por scripts client-side.
