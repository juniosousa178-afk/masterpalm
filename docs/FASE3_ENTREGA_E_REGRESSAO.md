# FASE 3 — Estado persistido da conversa (entrega e regressão preventiva)

## 1. ARQUIVOS CRIADOS

| Arquivo | Descrição |
|---------|-----------|
| `functions/src/whatsapp_agent/conversationStateStore.js` | Store de estado por `lojaId` + `from`: `loadState(getDb, lojaId, from)` retorna estado ou `null` (expirado/erro); `saveState(getDb, lojaId, from, state)` grava sem lançar. TTL 24h. Coleção `lojas/{lojaId}/whatsapp_conversations/{docId}`. |
| `docs/FASE3_ENTREGA_E_REGRESSAO.md` | Este documento. |

---

## 2. ARQUIVOS ALTERADOS

| Arquivo | Alteração |
|---------|-----------|
| `functions/canaisMetaWebhooks.js` | Import do store; constante `PRODUCT_INTENTS`; no handler WhatsApp: carregar estado antes de `classifyIntent`, merge de query quando há estado e intent de produto, salvar estado após envio (sem bloquear resposta). |

---

## 3. EXPLICAÇÃO CIRÚRGICA DO QUE MUDOU

### 3.1 `functions/src/whatsapp_agent/conversationStateStore.js` (novo)

- **loadState(getDb, lojaId, from):** Lê doc `lojas/{lojaId}/whatsapp_conversations/{docId}` com `docId = docIdFrom(from)` (sanitizado). Se não existir, dados inválidos ou `lastUpdatedAt` &gt; 24h, retorna `null`. Em exceção, faz log e retorna `null`.
- **saveState(getDb, lojaId, from, state):** Faz `set` com merge em `lastIntent`, `lastQuery` (máx. 120 chars), `lastUpdatedAt: FieldValue.serverTimestamp()`. Em exceção, apenas log (não lança).
- **TTL:** 24h; estado mais antigo é considerado expirado na leitura (sem job de limpeza).

### 3.2 `functions/canaisMetaWebhooks.js`

- **Import:** `loadState`, `saveState` de `conversationStateStore.js`.
- **Constante:** `PRODUCT_INTENTS` = Set com os 6 intents de produto (PRODUCT_PRICE, PRODUCT_STOCK, PRODUCT_SIZE, PRODUCT_COLOR, PRODUCT_PHOTO, PRODUCT_DESCRIPTION).
- **Fluxo WhatsApp (POST), por mensagem válida:**
  1. **Carregar estado:** `state = await loadState(getDb, lojaId, from)` em try/catch; em falha `state = null`.
  2. **Intent:** `intent = classifyIntent(messageText)` (inalterado).
  3. **Merge de query (FASE 3):** Se `state?.lastQuery` e intent em `PRODUCT_INTENTS` e `intent.query` existir, `mergedQuery = (state.lastQuery + " " + intent.query.trim()).trim().slice(0, 120)` e `intent = { ...intent, query: mergedQuery }`. Ex.: "camisa" no estado + "tem preta?" → query "camisa preta".
  4. **Resto inalterado:** `buildMinimalFactualContext`, `composeResponse`, `sendWhatsAppMessage`.
  5. **Salvar estado:** Após envio, se `from` existir, `saveState(getDb, lojaId, from, { lastIntent, lastQuery })`. `lastQuery` só preenchido para intents de produto com query; senão `null`.
- GET verify, validações Lote 1, dedup, resolução de loja, logs e respostas textuais permanecem iguais.

---

## 4. DIFFS (RESUMO)

- **conversationStateStore.js:** Novo arquivo; ~85 linhas.
- **canaisMetaWebhooks.js:** +1 import; +8 linhas (constante `PRODUCT_INTENTS`); no loop da mensagem WhatsApp: +~25 linhas (load state, merge query, save state). Nenhuma alteração em `classifyIntent`, `composeResponse`, `sendWhatsAppMessage`, GET, validações ou dedup.
- **firestore.rules / firestore.indexes.json:** Não alterados. A coleção `whatsapp_conversations` não tem regra explícita; acesso client continua negado por padrão; backend usa Admin SDK.

---

## 5. RELATÓRIO DE REGRESSÃO PREVENTIVA DA FASE 3

### O que foi preservado

- GET verify (mesmo token e challenge).
- Validação POST (body, value, message) e resposta 200 para inválidos.
- Resolução por `resolveWhatsAppStoreByPhoneNumberId` + fallback `findLojaByChannel`.
- Dedup por `message.id` (`isAlreadyProcessed`).
- `classifyIntent(messageText)` inalterado.
- `composeResponse(lojaId, intent, messageText)` inalterado (apenas o `intent` pode ter `query` enriquecida pelo estado).
- `sendWhatsAppMessage` inalterado.
- Texto das respostas: mesmas strings por intent; a única diferença é o resultado de `searchProducts` quando a query é mergeada (ex.: "camisa preta" em vez de "preta").
- Logs sanitizados (sem `req.body`).
- Webhooks Instagram e Messenger inalterados.
- Transacional e UI não tocados.

### O que pode ter risco

- **Leitura/escrita do estado:** Falhas são tratadas com `state = null` e `saveState` sem throw; resposta não depende do estado. Risco baixo.
- **Merge de query:** Se `state.lastQuery` estiver desatualizado ou incorreto, a busca pode retornar resultados diferentes (ex.: "camisa" + "azul" → "camisa azul"). Comportamento esperado; em caso de estado expirado (24h) não há merge.
- **Doc id do estado:** `docIdFrom(from)` sanitiza `from`; caracteres não alfanuméricos viram `_`. Números Meta costumam ser numéricos; risco baixo.

### O que precisa ser testado manualmente

- Conversa nova (sem estado): primeira mensagem "quanto custa camisa" → resposta igual ao Lote 1.
- Multi-turn: "quanto custa camisa" → "tem preta?" → resposta com produtos camisa preta; "e qual tamanho?" → resposta com tamanhos da camisa (query mergeada).
- Estado expirado: após 24h sem mensagem, próxima mensagem tratada como sem estado.
- Estado ausente: apagar doc em `whatsapp_conversations` e enviar "tem preta?" → resposta pedindo produto (sem merge).
- Falha no write do estado: resposta já foi enviada; apenas log no backend.
- Regressão Lote 1: GET verify, POST válido, dedup, payload inválido, equivalência para mensagens sem uso de estado.

---

## 6. CHECKLIST DE TESTES MANUAIS DA FASE 3

| # | Cenário | Passos | Resultado esperado |
|---|---------|--------|--------------------|
| 1 | Conversa nova sem estado | Enviar "quanto custa camisa" (número que nunca conversou ou estado apagado). | Resposta com produtos da loja para "camisa"; texto compatível com Lote 1. |
| 2 | Contexto em 2–3 turnos | 1) "quanto custa camisa" 2) "tem preta?" 3) "e qual tamanho?" | 1) Lista de camisas. 2) Lista/filtro camisa preta. 3) Tamanhos da camisa (query mergeada). |
| 3 | Estado expirado | Esperar 24h ou alterar TTL em dev; enviar "tem preta?" sem estado recente. | Resposta como sem contexto (ex.: pedir produto ou buscar só "preta"). |
| 4 | Estado ausente | Apagar doc `lojas/{lojaId}/whatsapp_conversations/{from}`; enviar "tem preta?". | Resposta sem merge (equivalente a primeira mensagem). |
| 5 | Estado “corrompido” | Doc com formato inválido (ex.: sem lastUpdatedAt ou tipo errado). | `loadState` retorna `null`; fluxo segue sem estado; resposta enviada. |
| 6 | Falha no write do estado | Simular falha (ex.: regras/offline) após envio. | Resposta já recebida no WhatsApp; log de aviso no backend; sem 500. |
| 7 | Regressão Lote 1 | Repetir: GET verify, POST válido, dedup (mesmo message.id), payload inválido. | Comportamento idêntico ao piloto aprovado do Lote 1. |
| 8 | Intent não-produto não usa estado | Enviar "oi" depois de "quanto custa camisa". | Saudação padrão; estado pode ter lastIntent=GREETING, lastQuery=null. |
| 9 | Múltiplas lojas | Dois números/lojas diferentes; cada um com sua conversa. | Estado isolado por loja+from; sem vazamento entre lojas. |

---

*FASE 3 — Estado persistido da conversa. Lote 1 preservado; sem IA no loop, sem handover operacional, sem observabilidade persistente.*
