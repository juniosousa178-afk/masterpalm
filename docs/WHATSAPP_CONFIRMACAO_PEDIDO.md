# WhatsApp – Confirmação de pedido (tipo DELIGELI)

Este documento descreve a estrutura e o fluxo da mensagem de confirmação de pedido via WhatsApp, no formato usado por lojas como DELIGELI SORVETES.

---

## O que a mensagem contém

- Saudação com nome do cliente
- Nome da loja (“atendente virtual da LOJA”)
- Status: pedido realizado com sucesso e em preparo
- **Nº do pedido**
- **Itens** (quantidade e nome de cada produto)
- **Forma de pagamento**
- **Tempo de entrega** (ex.: 45–60 min)
- **Local de entrega** (endereço completo)
- **Total do pedido**
- (Opcional) Número da sorte e cupom da roleta, quando houver campanha

---

## Onde está implementado

### 1. Cloud Function `sendWhatsAppOrderConfirmation`

- **Arquivo:** `functions/index.js`
- **URL:** `POST https://southamerica-east1-{projectId}.cloudfunctions.net/sendWhatsAppOrderConfirmation`
- **Body:** `{ lojaId, phone, message }`
- **Função:** Usa as credenciais da loja em `lojas/{lojaId}/canais/whatsapp` (WhatsApp Cloud API: `phone_number_id`, `access_token`) e envia o texto em `message`.

**Requisitos:** A loja deve ter o canal WhatsApp configurado em **Configurações → Canais Meta** (phone_number_id e access_token).

### 2. App Flutter (PosPagamentoService)

- **Arquivo:** `lib/services/pos_pagamento_service.dart`
- **Fluxo:** Quando `processarConfirmacaoPagamento` é chamado (ex.: pós-pagamento no app), o serviço:
  1. Busca o pedido em `lojas/{lojaId}/pedidos` com `vendaId` igual ao da venda.
  2. Se encontrar, monta a mensagem completa (confirmação + número da sorte/cupom).
  3. Se não encontrar, envia só a mensagem de número da sorte/cupom (comportamento anterior).
- **Envio:** Chama a Cloud Function `sendWhatsAppOrderConfirmation` com `lojaId`, `phone` e `message`.

### 3. Webhook Mercado Pago (mpWebhookHandler)

- **Arquivo:** `functions/src/mpWebhookHandler.js`
- **Fluxo:** Após aprovação do pagamento (status `approved`), o webhook:
  1. Atualiza o pedido e baixa estoque (como já fazia).
  2. Monta a mensagem de confirmação com dados do pedido (cliente, itens, total, endereço, forma de pagamento).
  3. Chama a mesma Cloud Function `sendWhatsAppOrderConfirmation` para enviar ao telefone do cliente.

Assim, o cliente recebe a confirmação tanto quando o pagamento é confirmado pelo **webhook** (fluxo catálogo/web) quanto quando o **app** chama `processarConfirmacaoPagamento`.

---

## Checklist de configuração

| Item | Onde | Verificação |
|------|------|-------------|
| Canal WhatsApp da loja | App → Configurações → Canais Meta | Preencher *Phone number ID* e *Access token* e salvar |
| Número do cliente | Pedido / cliente | Campo `telefone` (ou `cliente.telefone`) preenchido |
| Pedido no Firestore | `lojas/{lojaId}/pedidos` | Documento com `vendaId`, `cliente`, `itens`, `total`, `pagamento` |

---

## Melhorias sugeridas (futuro)

1. **Tempo de entrega configurável**  
   Hoje está fixo em “45 - 60min”. Pode ser movido para algo como `lojas/{lojaId}/config/delivery` (ex.: `tempoMin`, `tempoMax` em minutos) e usado na montagem da mensagem no app e no webhook.

2. **Atualizações de status**  
   A mensagem diz que “vou enviar as atualizações do status do seu pedido por aqui”. Para cumprir isso, é preciso:
   - Definir status (ex.: em preparo, saiu para entrega, entregue).
   - Ter um ponto (ex.: Cloud Function ou app admin) que, ao atualizar o status do pedido, chame `sendWhatsAppOrderConfirmation` com uma mensagem curta de atualização.

3. **Idioma**  
   Se a loja for atender em outro idioma, a mensagem pode ser montada com base em um campo de idioma da loja ou do cliente.

4. **Log e retry**  
   Registrar em Firestore ou em log quando o envio falhar (ex.: 4xx/5xx da API WhatsApp) e, se desejado, implementar retry com backoff.

5. **Duplicidade**  
   No fluxo catálogo, o webhook e o app podem ambos rodar. Hoje apenas o webhook envia WhatsApp nesse fluxo; se no futuro o app também enviar ao finalizar pedido, considerar um flag no pedido (ex.: `whatsappEnviadoEm`) para evitar enviar duas vezes a mesma confirmação.

---

## Resumo

- A estrutura do APK está preparada para esse tipo de função: mensagem de confirmação com número do pedido, itens, pagamento, tempo de entrega, endereço e total.
- Foi implementada a Cloud Function `sendWhatsAppOrderConfirmation` (antes inexistente) e o envio da mensagem completa no app (quando há pedido no Firestore) e no webhook do Mercado Pago.
- Para funcionar em produção, basta configurar o canal WhatsApp da loja em Canais Meta e garantir telefone do cliente no pedido.
