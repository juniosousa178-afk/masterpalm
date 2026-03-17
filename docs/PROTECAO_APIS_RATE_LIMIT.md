# Proteção de APIs MasterPalm

## Objetivo

- **Impedir abuso** – limites por usuário/IP
- **Evitar loops acidentais** – retries não duplicam operações
- **Controlar custos** – Firestore, Cloud Functions, APIs externas
- **NÃO bloquear uso legítimo** – limites generosos

---

## 1. Rate Limiting

### Comportamento

- Cada endpoint tem um limite **por minuto** por identificador (IP ou UID).
- Identificador: `X-Forwarded-For` > `X-Real-IP` > IP da conexão.
- Para Callable: `request.auth.uid` quando disponível.
- Contadores armazenados em Firestore (`_rate_limits`).

### Limites Padrão (por minuto)

| Endpoint | Limite | Motivo |
|----------|--------|--------|
| calcularCorreios / MelhorEnvio / Frenet | 30 | Usuário pode testar vários CEPs |
| createPreference | 10 | Checkout normal: 1–2 por sessão |
| planCreatePreference | 5 | Assinatura é rara |
| gerarCupomNumeroSorte | 20 | 1 por pedido; múltiplos clientes |
| mpOAuthInit / Callback | 15 | Fluxo humano |
| provisionSubdomain | 5 | Operação administrativa |
| webhookWhatsApp/Instagram/Messenger | 120 | Bursts legítimos |
| ensureUserPlan | 30 | Verificação periódica |

### Uso

```javascript
// Em onRequest (createPreference, gerarCupomNumeroSorte, etc.)
import { checkRateLimit, getClientIdentifier } from './src/rateLimiter.js';

export const createPreference = onRequest(
  { cors: true, secrets: [S_MP_ACCESS_TOKEN, S_WEB_BASE_URL] },
  corsWrap(async (req, res) => {
    try {
      if (req.method !== "POST") return res.status(405).send("Method not allowed");

      const identifier = getClientIdentifier(req);
      await checkRateLimit("createPreference", identifier);

      // ... lógica existente ...
    } catch (e) {
      if (e.code === "resource-exhausted") {
        return res.status(429).json({ error: e.message, retryAfter: 60 });
      }
      throw e;
    }
  })
);
```

```javascript
// Em onCall (calcularCorreios, calcularMelhorEnvio, etc.)
import { checkRateLimit, getCallableIdentifier } from './src/rateLimiter.js';

export const calcularCorreios = onCall(
  { timeoutSeconds: 25, memory: "256MiB" },
  async (request) => {
    const identifier = getCallableIdentifier(request);
    await checkRateLimit("calcularCorreios", identifier);

    const { cepOrigem, cepDestino, peso, ... } = request.data || {};
    // ... lógica existente ...
  }
);
```

---

## 2. Idempotência

### Endpoints Críticos

| Endpoint | Chave idempotente | Motivo |
|----------|-------------------|--------|
| createPreference | `lojaId:orderId` | Evitar múltiplas preferências MP |
| planCreatePreference | `uid:plan` | Evitar duplicar assinatura |
| gerarCupomNumeroSorte | `lojaId:pedidoId:clienteId` | Retry pós-pagamento não duplica cupom |

### Uso

```javascript
import { checkIdempotency, saveIdempotency } from './src/rateLimiter.js';

export const createPreference = onRequest(
  { cors: true },
  corsWrap(async (req, res) => {
    const { lojaId, orderId, idempotencyKey } = req.body || {};
    const key = idempotencyKey || `${lojaId}:${orderId}`;

    const { hit, result } = await checkIdempotency("createPreference", key);
    if (hit) {
      return res.json(result);
    }

    // ... criar preferência ...

    await saveIdempotency("createPreference", key, { init_point, id, ... });
    return res.json({ init_point, id, ... });
  })
);
```

```javascript
// gerarCupomNumeroSorte
const { lojaId, clienteId, pedidoId } = req.body || {};
const key = `${lojaId}:${pedidoId}:${clienteId}`;

const { hit, result } = await checkIdempotency("gerarCupomNumeroSorte", key);
if (hit) {
  return res.status(200).json(result);
}

// ... gerar cupom e número ...

await saveIdempotency("gerarCupomNumeroSorte", key, {
  success: true,
  cupom,
  numeroSorte,
  ...
});
return res.status(200).json({ success: true, cupom, numeroSorte, ... });
```

---

## 3. Firestore – Regras de Segurança

As coleções `_rate_limits` e `_idempotency` são **internas** (Cloud Functions Admin SDK). Bloqueie acesso do cliente:

```javascript
// firestore.rules

match /_rate_limits/{doc} {
  allow read, write: if false;  // Apenas Admin SDK (Cloud Functions)
}

match /_idempotency/{doc} {
  allow read, write: if false;
}
```

---

## 4. Limpeza Periódica (opcional)

Crie um Cloud Scheduler para limpar documentos antigos:

```javascript
// functions/index.js
export const cleanupRateLimits = onSchedule(
  { schedule: "0 * * * *", region: "southamerica-east1" },  // A cada hora
  async () => {
    const col = db.collection("_rate_limits");
    const cutoff = Date.now() - 24 * 60 * 60 * 1000;  // 24h
    const snap = await col.where("updatedAt", "<", cutoff).limit(500).get();
    const batch = db.batch();
    snap.docs.forEach(d => batch.delete(d.ref));
    await batch.commit();
    console.log(`[cleanup] Removidos ${snap.size} registros de rate limit`);
  }
);
```

---

## 5. Resposta HTTP 429

Quando o rate limit for atingido:

- **Status**: 429 (Too Many Requests)
- **Header**: `Retry-After: 60`
- **Body**: `{ "error": "Muitas requisições. Tente novamente em alguns minutos.", "retryAfter": 60 }`

O cliente Flutter pode tratar retry com backoff exponencial.

---

## 6. Checklist de Implementação

- [ ] Adicionar `checkRateLimit` em todos os endpoints HTTP e Callable
- [ ] Adicionar idempotência em `createPreference`, `planCreatePreference`, `gerarCupomNumeroSorte`
- [ ] Registrar `_rate_limits` e `_idempotency` no Firestore rules
- [ ] (Opcional) Agendar `cleanupRateLimits`
- [ ] Testar com limites reais
