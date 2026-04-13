# Mercado Pago — apenas planos do app (MasterPalm)

## Fonte canônica

- **Checkout de assinatura (planos):** Cloud Functions `planCreatePreference`, `planWebhook`, e (se habilitado) `createPlanSubscription` / fluxo recorrente em `functions/src/mpPlanRecurring.js`.
- **Credencial MP:** segredo `MP_ACCESS_TOKEN` (Firebase Secret Manager) ou `process.env.MP_ACCESS_TOKEN` no deploy. **Não** lê `app_config/master_config`.

## O que não é plano

- **`lojas/{lojaId}/config/payments`:** conta da loja para pedidos do catálogo — domínio separado.
- **`app_config/master_config` (`mercadoPagoAccessToken` / `mercadoPagoPublicKey`):** opcional, tela Master; legado/diagnóstico; **não** alimenta o checkout normal de planos.

## Cliente (Flutter)

- **Web (preferencial):** `httpsCallable('planCreatePreferenceCall')` — o SDK anexa o utilizador autenticado; não depende do header `Authorization` no `fetch`.
- **Mobile / fallback:** `lib/services/checkout_service.dart` faz POST em `planCreatePreference` com **Firebase ID token** (`Authorization: Bearer`). No Web, se o callable não devolver `init_point`, cai-se neste fluxo; `reload` + `getIdToken(true)` e **uma repetição** em 401.

## Callable `ensureUserPlan` e CORS (Web)

- Em `functions/ensureUserPlan.js`, o `onCall` usa `cors: MASTERPALM_APP_WEB_ORIGINS` (origem canônica `https://app.mastepalm.com.br` primeiro, depois compat `https://app.masterpalm.com.br`, localhost, web.app, etc. — ver `docs/DOMAIN_APP_WEB.md`).
- Motivo: domínios customizados do app Web podem falhar no preflight se o Callable v2 não listar a origem.
- Log seguro: `ensureUserPlan_request` com `hasAuthUid` e `origin` truncado (sem token).

## Diagnóstico de 401 (planos)

- **Logs cliente:** prefixo `[PlanosAuthDiag]` (uid parcial, `providers`, `idTokenNonEmpty`, rota).
- **Logs Functions:** `planCreatePreference_auth_diag` (HTTP: tokenLength, aud, iss, adminProjectId, chaves de header com “auth”); `planCreatePreference_verify_fail` se `verifyIdToken` falhar; callable com `transport: "callable"`.
- **Nunca** logar o JWT completo.

## Validação manual

1. Web normal: Planos → assinar → deve usar callable (consola: mensagem de sucesso via callable).
2. Se ainda 401 no HTTP fallback: comparar `aud` / `adminProjectId` nos logs com o projeto no Firebase Console.
3. Janela anónima / sessão velha: após deploy da nova Function, fazer login de novo.

## Operação

- Garantir segredo `MP_ACCESS_TOKEN` configurado no projeto das Functions.
- Webhooks de plano (`planWebhook`) usam o mesmo token para consultar pagamentos na API do MP.
