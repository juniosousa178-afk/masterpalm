# Webhook Mercado Pago – Arquitetura e Garantias

## Objetivo

- **Idempotência**: Reenvios do MP não duplicam processamento
- **Token por loja**: Multi-tenant – cada loja usa seu token (OAuth ou legado)
- **Sem duplicar baixa de estoque**: Transação atômica no Firestore

---

## Fluxo

```
MP envia POST → mpWebhook
  ├─ 1. Extrai paymentId do body/query
  ├─ 2. processMpWebhook(paymentId, globalToken)
  │    ├─ 2a. resolveLojaAndPayment: tenta global token, depois itera lojas
  │    ├─ 2b. Early check: _mp_webhook_processed/{paymentId} existe? → return 200
  │    ├─ 2c. Registra status em payments (auditoria)
  │    └─ 2d. Se approved: transação atômica
  │         ├─ Read _mp_webhook_processed → se existe, abort
  │         ├─ Read order → se paidAt, marca processado e abort
  │         ├─ Create _mp_webhook_processed
  │         ├─ Update order (paidAt, status)
  │         └─ Batch decrement estoque
  └─ 3. Sempre retorna 200 OK (MP exige isso para parar retries)
```

---

## 1. Idempotência por paymentId

| Camada | Mecanismo |
|--------|-----------|
| Early check | `_mp_webhook_processed/{paymentId}` antes da transação |
| Transação | Read do doc dentro da transação; se existe, não executa |
| Pedido já pago | Se `order.paidAt` existe, apenas marca processado (app ou outro webhook) |

O MP reenvia o webhook em caso de timeout ou erro. Com a idempotência:
- Primeira entrega: processa normalmente
- Reenvios: retornam 200 sem reprocessar

---

## 2. Token por lojaId

| Ordem | Fonte | Uso |
|-------|-------|-----|
| 1 | Token global (S_MP_ACCESS_TOKEN) | Fallback para lojas sem OAuth |
| 2 | Token da loja (mp.access_token ou mp_access_token) | Iteração em todas as lojas |

**Resolução**: `resolveLojaAndPayment(paymentId, globalToken)` tenta o token global. Se falhar (401), itera as lojas e tenta cada token até encontrar o payment.

**Estrutura em Firestore**:
```
/lojas/{lojaId}/config/payments
  mp: { access_token, token, ... }     ← OAuth
  mp_access_token: "..."               ← legado
```

---

## 3. Reenvio seguro

- Sempre retornamos **200 OK**; o MP interrompe retries em 2xx
- Erros internos também retornam 200 para evitar loops infinitos
- Logs em `console.error` para debugging

---

## 4. Baixa de estoque (uma única vez)

A transação Firestore garante:

1. **Read** `_mp_webhook_processed` e `order`
2. Se `_mp_webhook_processed` existe → outra requisição já processou → abort
3. Se `order.paidAt` existe → app ou outro caminho já pagou → marca processado e abort
4. Caso contrário: cria doc processado + atualiza pedido + decrementa estoque em batch

Todos os writes ficam na mesma transação; em caso de conflito, a transação é retentada.

---

## 5. Coleções Firestore

| Coleção | Uso | Acesso |
|---------|-----|--------|
| `_mp_webhook_processed` | Idempotência por paymentId | Apenas Cloud Functions |
| `lojas/{id}/payments` | Auditoria de pagamentos | Admin |
| `lojas/{id}/pedidos` | Status do pedido | Admin |

---

## 6. Arquivos

```
functions/
  index.js              → mpWebhook (entry point)
  src/
    mpWebhookHandler.js → processMpWebhook, resolveLojaAndPayment, getLojaMpToken
```

---

## 7. Escalabilidade

- **Busca por loja**: Iteração em lojas é O(n). Para muitas lojas, considerar índice `paymentId → lojaId` no momento da criação da preferência.
- **Transação**: Limite de 500 operações por transação no Firestore.
- **Cold start**: Handler em módulo separado; funções compartilham o mesmo runtime.
