# Lote 1 — Entrega e Relatório de Regressão Preventiva

## 1. Arquivos criados

| Arquivo | Descrição |
|---------|-----------|
| `functions/src/whatsapp_agent/webhookSecurityValidator.js` | Validação mínima do POST (body, change.value, message text). Sem log de corpo. |
| `functions/src/whatsapp_agent/channelResolverIndex.js` | Resolução `lojaId` + config por `phone_number_id` via collectionGroup `canais`, sem varredura. |
| `functions/src/whatsapp_agent/minimalFactualContextBuilder.js` | Monta contexto factual mínimo (lojaId, intent, messageText, query) para auditoria; sem nova leitura. |
| `functions/src/whatsapp_agent/messageDeduper.js` | Dedup in-memory por `message.id` com TTL 60s para evitar envio duplicado em replay. |
| `functions/src/whatsapp_agent/requestSafeLogger.js` | Logs seguros (método, phone_number_id, from, message_id, intent, event); sem `req.body`. |

---

## 2. Arquivos alterados

| Arquivo | Tipo de alteração |
|---------|-------------------|
| `functions/canaisMetaWebhooks.js` | Imports novos, correção de bug (`db` → `getDb()`), POST do WhatsApp endurecido, resolução com fallback, dedup, logs seguros, contexto mínimo. |
| `firestore.indexes.json` | Novo índice composite para collection group `canais`: `phone_number_id` (ASC), `enabled` (ASC). |

---

## 3. O que mudou em cada arquivo (cirúrgico)

### 3.1 `functions/canaisMetaWebhooks.js`

- **Imports:** Inclusão de 5 módulos do Lote 1 (webhookSecurityValidator, channelResolverIndex, minimalFactualContextBuilder, messageDeduper, requestSafeLogger).
- **Bugfix (comportamento existente):** Em `searchProducts`, `productsRef` passou a usar `getDb()` em vez de `db` (não definido no arquivo). Em `findLojaByChannel`, a leitura do doc do canal passou a usar `getDb()` em vez de `db`. Isso corrige referência indefinida e não altera o texto das respostas.
- **GET verify:** Inalterado (mesmo `hub.mode`, `hub.verify_token`, `hub.challenge`).
- **Log inicial do handler:** Substituído `console.log("📥 WhatsApp Webhook:", req.method, req.query, req.body)` por `logWhatsAppWebhook(req.method)` — sem expor `req.body`.
- **POST – validação:** Antes de processar, chama `validateWhatsAppPostBody(body)`. Se `valid === false`, responde 200 e não processa. Se `reason === "no entries"`, responde 200.
- **POST – bloco messages:** Para cada `change.value`, chama `validateWhatsAppChangeValue(value)`; se inválido, faz `continue`. Usa `phoneNumberId` do retorno validado.
- **POST – resolução de loja:** Primeiro chama `resolveWhatsAppStoreByPhoneNumberId(getDb, phoneNumberId)`. Se retornar `null`, chama `findLojaByChannel("whatsapp", phoneNumberId)` (fallback). Comportamento “loja não encontrada” mantido (`continue` + log).
- **POST – por mensagem:** Valida com `validateTextMessage(message)`; se inválido ou não for `text`, faz `continue`. Extrai `from`, `messageText`, `messageId`. Se `messageId` presente e `isAlreadyProcessed(messageId)`, faz `continue` e loga `skipped_duplicate`.
- **POST – fluxo de resposta:** Continua igual: `classifyIntent(messageText)` → `buildMinimalFactualContext(lojaId, intent, messageText)` (apenas chamado; resultado não altera resposta) → `composeResponse(lojaId, intent, messageText)` → `sendWhatsAppMessage(...)`. Nenhuma alteração em `classifyIntent`, `composeResponse` ou `sendWhatsAppMessage`.
- **POST – log de sucesso:** Substituído `console.log("✅ Resposta enviada para", from)` e log de mensagem/intent por `logWhatsAppWebhook("POST", { phoneNumberId, from, messageId, intentType, event: "processed" })`.

### 3.2 `firestore.indexes.json`

- Adicionado um índice para collection group `canais`, queryScope `COLLECTION_GROUP`, campos `phone_number_id` (ASC) e `enabled` (ASC), para permitir a resolução em `channelResolverIndex.js` sem varredura. Sem esse índice, a query falha e o código usa o fallback `findLojaByChannel`.

---

## 4. Diffs relevantes (resumo)

### `functions/canaisMetaWebhooks.js`

- **Topo:** +10 linhas de imports dos módulos Lote 1.
- **searchProducts:** `db` → `getDb()` (1 ocorrência).
- **findLojaByChannel:** `db` → `getDb()` (1 ocorrência).
- **webhookWhatsApp:**
  - Primeira linha do handler: `console.log("📥 ...", req.body)` removido; adicionado `logWhatsAppWebhook(req.method)`.
  - POST: bloco inteiro reescrito com validação (post + value + message), dedup, resolução (resolver + fallback), `buildMinimalFactualContext`, mesmo fluxo `classifyIntent` → `composeResponse` → `sendWhatsAppMessage`, e logs via `logWhatsAppWebhook`.

### `firestore.indexes.json`

- Inclusão de um objeto em `indexes`: collectionGroup `"canais"`, queryScope `"COLLECTION_GROUP"`, fields `phone_number_id` (ASC), `enabled` (ASC).

### Novos arquivos (sem diff anterior)

- Conteúdo conforme descrito na seção 1 e nos arquivos em `functions/src/whatsapp_agent/`.

---

## 5. Relatório de regressão preventiva

### 5.1 O que foi preservado

- **GET verify:** Condição e resposta idênticas (`hub.mode === "subscribe"`, `hub.verify_token === VERIFY_TOKEN`, retorno de `hub.challenge`).
- **classifyIntent:** Não foi alterado (mesmas regex e retornos).
- **composeResponse:** Não foi alterado (mesmo switch, mesmas strings por intent, mesmas chamadas a `searchProducts`).
- **sendWhatsAppMessage:** Não foi alterado (mesmo endpoint Graph e payload).
- **findLojaByChannel:** Mantido e usado como fallback quando o resolver retorna `null`.
- **Webhooks Instagram e Messenger:** Nenhuma alteração (só o handler WhatsApp foi endurecido).
- **Fluxo transacional:** `sendWhatsAppOrderConfirmation` e `mpWebhookHandler` não foram tocados.
- **UI Flutter:** Nenhum arquivo em `lib/` foi alterado.

### 5.2 O que pode ter risco

- **Índice Firestore:** Se o índice do collection group `canais` ainda não estiver ativo no projeto, a primeira resolução por `resolveWhatsAppStoreByPhoneNumberId` falhará e o código usará `findLojaByChannel`. Até o índice estar verde, o path crítico continua sendo a varredura no fallback. **Ação:** rodar `firebase deploy --only firestore:indexes` (ou equivalente) e aguardar o índice ficar “Enabled”.
- **Dedup in-memory:** Por instância e com TTL 60s. Em múltiplas instâncias ou após cold start, a mesma mensagem pode ser processada mais de uma vez. Não há estado persistido (conforme escopo do Lote 1). Risco aceitável para replay simples na mesma instância.
- **Validação mais rígida:** Payloads que antes passavam (ex.: estrutura marginalmente diferente do Meta) podem passar a ser ignorados (resposta 200 sem processar). Se houver relatos de “não responde”, verificar logs com `event=rejected` ou `reason=...`.

### 5.3 O que deve ser testado manualmente imediatamente

1. **GET verify**
   - Chamar o webhook com `GET ?hub.mode=subscribe&hub.verify_token=masterpalm_verify_2026&hub.challenge=abc`.
   - Esperado: 200 e corpo `abc`. Nenhum 403 com token correto.

2. **POST válido (text)**
   - Enviar um POST com `object: "whatsapp_business_account"`, uma entry com change `field: "messages"`, `value.metadata.phone_number_id` válido (de uma loja existente em `lojas/{id}/canais/whatsapp` com `enabled: true`), e uma message `type: "text"` com `text.body` e `id`.
   - Esperado: 200; uma mensagem enviada via Graph; log com `event=processed` (e sem `req.body` nos logs).

3. **Resolução de loja**
   - Com o índice deployado: mesmo `phone_number_id` deve resolver para o mesmo `lojaId` (e resposta rule-based daquela loja).
   - Com o índice em build ou inexistente: fallback deve resolver via `findLojaByChannel` e a resposta deve ser a mesma.

4. **Dedup**
   - Reenviar o mesmo POST (mesmo `message.id`) em curto intervalo.
   - Esperado: primeira vez processa e envia; segunda vez log com `event=skipped_duplicate` e nenhum segundo envio.

5. **Payload inválido**
   - POST com `body.object` diferente de `whatsapp_business_account`, ou sem `metadata.phone_number_id`, ou message sem `text.body`.
   - Esperado: 200 sem processar; nenhuma chamada ao Graph; log com `event=rejected` ou `reason=...` quando aplicável.

6. **Regressão de texto**
   - Para uma mesma mensagem de teste (ex.: “oi”, “quanto custa camisa”), comparar a resposta recebida no WhatsApp com a resposta anterior ao Lote 1 (ou com o texto esperado do rule-based). Devem ser idênticos.

---

## 6. Sinalização: alteração de comportamento textual

- Nenhuma alteração foi feita em `classifyIntent`, `composeResponse` ou na formatação das respostas. O texto final do rule-based permanece o mesmo.
- A única correção funcional foi o uso de `getDb()` no lugar de `db` (que não existia no arquivo). Isso evita erro em tempo de execução e **não** muda o conteúdo das respostas.

---

*Documento gerado como parte da entrega do Lote 1 (FASE 1 + FASE 2) do agente de IA WhatsApp — MasterPalm.*
