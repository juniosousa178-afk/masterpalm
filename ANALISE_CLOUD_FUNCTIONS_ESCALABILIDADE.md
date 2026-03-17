# Análise: Cloud Functions — Cold Start, Timeouts e Confiabilidade

**Data:** 12/02/2026  
**Projeto:** MasterPalm

---

## 1. MAPEAMENTO DAS FUNÇÕES HTTP

| Função | Tipo | Chamadas externas | Timeout padrão |
|--------|------|-------------------|----------------|
| createPreference | onRequest | MP API, Firestore | 60s |
| mpWebhook | onRequest | MP API, Firestore | 60s |
| calcularCorreios | onCall | Correios (HTTP) | 60s |
| calcularMelhorEnvio | onCall | Melhor Envio API | 60s |
| calcularFrenet | onCall | Frenet API | 60s |
| planCreatePreference | onRequest | MP API | 60s |
| planWebhook | onRequest | MP API | 60s |
| webhookWhatsApp/Instagram/Messenger | onRequest | Meta API, Firestore | 60s |
| provisionSubdomain | onRequest | Firestore, vários | 60s |
| publishLojaDraft | onDocumentWritten | Firestore batch | 60s |

---

## 2. CAUSAS DE COLD START

1. **Imports pesados no top-level:** `parseStringPromise` (xml2js) carregado mesmo quando só calcularCorreios usa
2. **firebase-admin:** Inicializado no boot (necessário)
3. **google-auth-library:** Usado em provisionSubdomain
4. **Múltiplas funções no mesmo arquivo:** Todas compartilham o mesmo processo ao "acordar"

---

## 3. OTIMIZAÇÕES APLICADAS

### 3.1 Lazy load xml2js

`parseStringPromise` só é carregado quando `calcularCorreios` é invocado.

### 3.2 Timeouts por função

| Função | timeoutSeconds | Motivo |
|--------|----------------|--------|
| createPreference | 45 | MP + Firestore; checkout crítico |
| mpWebhook | 30 | MP + Firestore; webhook deve ser rápido |
| calcularCorreios | 25 | Correios pode demorar |
| calcularMelhorEnvio | 25 | Melhor Envio externo |
| calcularFrenet | 25 | Frenet externo |
| planCreatePreference | 45 | MP API |
| planWebhook | 30 | MP |
| webhooks Meta | 30 | Meta API |
| provisionSubdomain | 60 | Operação longa |
| publishLojaDraft | 120 | Batch em Firestore |

### 3.3 Timeout em fetch()

Todas as chamadas `fetch()` recebem `AbortController` com timeout para evitar espera infinita.

### 3.4 Retry

- **Não aplicado** em createPreference (pode duplicar preferência).
- **Cálculo de frete:** idempotente; retry pode ser adicionado futuramente com `fetchWithRetry`.

### 3.5 minInstances (sugestão)

Para `createPreference` (checkout): `minInstances: 1` em horário de pico reduz cold start, mas aumenta custo. Avaliar por região/horário.

---

## 4. QUANDO USAR CLOUD TASKS (FILA)

| Operação | Usar fila? | Motivo |
|----------|------------|--------|
| createPreference | ❌ Não | Usuário precisa de init_point imediatamente |
| mpWebhook | ❌ Não | MP retenta; resposta 200 rápida obrigatória |
| calcularCorreios/MelhorEnvio/Frenet | ❌ Não | Usuário aguarda resultado no checkout |
| publishLojaDraft | ✅ Sim (futuro) | Batch pesado; pode ser assíncrono |
| findLojaIdByOrderId | ⚠️ Otimizar | Scan em lojas; considerar índice ou cache |
| Envio de email/WhatsApp pós-venda | ✅ Sim | Não bloqueia resposta ao usuário |

---

## 5. ARQUITETURA FINAL

```
┌─────────────────────────────────────────────────────────────┐
│  FUNÇÕES SÍNCRONAS (resposta imediata)                       │
│  • createPreference, calcularFrete* — timeout 25–45s          │
│  • fetch com AbortController                                 │
│  • Retry 1x em 5xx/rede                                      │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│  WEBHOOKS (responder 200 rápido)                             │
│  • mpWebhook, planWebhook — processar em background           │
│  • timeout 30s                                               │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│  CANDIDATOS A CLOUD TASKS (fase 2)                           │
│  • publishLojaDraft → enfileirar batch                       │
│  • Notificações pós-venda                                    │
└─────────────────────────────────────────────────────────────┘
```

---

*Documento gerado em 12/02/2026.*
