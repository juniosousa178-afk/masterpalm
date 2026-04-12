# Mercado Pago — apenas planos do app (MasterPalm)

## Fonte canônica

- **Checkout de assinatura (planos):** Cloud Functions `planCreatePreference`, `planWebhook`, e (se habilitado) `createPlanSubscription` / fluxo recorrente em `functions/src/mpPlanRecurring.js`.
- **Credencial MP:** segredo `MP_ACCESS_TOKEN` (Firebase Secret Manager) ou `process.env.MP_ACCESS_TOKEN` no deploy. **Não** lê `app_config/master_config`.

## O que não é plano

- **`lojas/{lojaId}/config/payments`:** conta da loja para pedidos do catálogo — domínio separado.
- **`app_config/master_config` (`mercadoPagoAccessToken` / `mercadoPagoPublicKey`):** opcional, tela Master; legado/diagnóstico; **não** alimenta o checkout normal de planos.

## Cliente (Flutter)

- `lib/services/checkout_service.dart` chama o backend com **Firebase ID token** (`Authorization: Bearer`). No Web: `reload` + `getIdToken(true)` e **uma repetição** em 401 antes de mostrar erro de sessão ao usuário.

## Operação

- Garantir segredo `MP_ACCESS_TOKEN` configurado no projeto das Functions.
- Webhooks de plano (`planWebhook`) usam o mesmo token para consultar pagamentos na API do MP.
