# Assinatura recorrente (Mercado Pago) — planos do app

Domínio **somente** do MasterPalm (usuários do app). **Não** confundir com `mpWebhook` / pedidos / catálogo da loja.

## Flags

| Camada | Chave | Efeito |
|--------|--------|--------|
| Backend (Cloud Functions / `.env`) | `USE_RECURRING_PLAN_BILLING=true` | Habilita callables `createPlanSubscription`, webhooks de preapproval, extras em `activatePlanForUser` quando há `preapproval_id` no pagamento. |
| Cliente (Firebase Remote Config) | `use_recurring_plan_billing` (bool) | Se `true`, `CheckoutService` tenta `createPlanSubscription` antes do legado. Default `false`. |
| Cliente (Remote Config) | `recurring_plan_billing_allowlist` (string) | Lista opcional `uid1,uid2,email@test.com` (vírgula). Com global `false`, só esses usuários entram no fluxo v2 no app. Backend ainda precisa da env acima. |

O cliente pode ter RC `true` e o backend `false`: o callable retorna `failed-precondition` `RECURRING_PLAN_BILLING_DISABLED` e o app faz **fallback** para `planCreatePreference`.

## Fluxo v2 — quando cada campo é gravado (diagnóstico)

| Momento | `billingVersion` | `billingSource` | `providerSubscriptionId` | `currentPeriodEnd` |
|--------|------------------|-----------------|---------------------------|---------------------|
| `createPlanSubscription` (sucesso MP) | `2` | `mp_preapproval_pending` | id do preapproval | *(não definido ainda; usuário ainda não autorizou)* |
| Webhook preapproval / `syncPlanSubscription` | `2` | `mp_preapproval_pending` → `mp_subscription` (autorizado) ou `mp_subscription_cancelled` | id | `inferPeriodEndFromPreapproval` (MP) ou mantido |
| Webhook `payment` aprovado com `preapproval_id` e backend ligado | `2` (via extras) | `mp_subscription_payment` | id | `activatePlanForUser` (renovação calculada a partir do plano, como legado pago) |

**Confiabilidade:** após `createPlanSubscription`, o doc já traz `billingVersion`, `billingSource` e `providerSubscriptionId`, então o app **não** cai no legado por falta de metadados nesse caminho. Estados intermediários podem não ter `currentPeriodEnd` até autorização/sync — esperado.

## Logs estruturados (Cloud Logging)

Eventos JSON (campo `evt`): `plan_v2_create_preapproval`, `plan_v2_preapproval_webhook`, `plan_v2_payment_webhook`, `plan_v2_sync_subscription`, `plan_v2_cancel_subscription`, `plan_v2_reactivate_subscription`; falhas de pause/MP: `plan_v2_cancel_mp_pause_failed`, `plan_v2_reactivate_mp_failed`. Incluem `uid`, `preapprovalId` ou `providerSubscriptionId` quando aplicável.

## Piloto real — checklist executável (ordem sugerida)

1. [ ] **Definir grupo:** listar UID ou e-mail de cada piloto (fora do app: planilha interna).
2. [ ] **Backend:** `USE_RECURRING_PLAN_BILLING=true` no ambiente (deploy/secret já validado).
3. [ ] **Remote Config:** `recurring_plan_billing_allowlist` com os pilotos **ou** `use_recurring_plan_billing=true` (global); publicar RC e forçar fetch no app (abrir app / aguardar intervalo mínimo).
4. [ ] **Conta piloto:** login no app → **Planos** → expandir **Piloto billing v2**:
   - Subtítulo: `efetivo=sim` e `via=allowlist` ou `RC global` conforme esperado.
   - Título do card: sufixo **doc v2** ou **doc legado** (estado canônico em `users/{uid}` para cancel/reativar).
5. [ ] **Checkout:** iniciar assinatura paga → deve abrir MP (preapproval) se rollout efetivo estiver ligado.
6. [ ] **Confirmar create:** Cloud Logging `evt=plan_v2_create_preapproval` com `uid` correto; Firestore `billingVersion: 2`, `billingSource: mp_preapproval_pending`, `providerSubscriptionId` preenchido.
7. [ ] **Webhook:** após autorizar no MP, `plan_v2_preapproval_webhook` ou `plan_v2_payment_webhook` (conforme caminho); doc com `billingSource` coerente e, quando aplicável, `currentPeriodEnd`.
8. [ ] **Snapshot canônico:** no card, “Dump canônico” alinhado ao console Firestore do mesmo `uid`.
9. [ ] **Sync manual:** botão ativo só com `providerSubscriptionId` no doc; tocar sync → snackbar com `synced` / `reason`; log `plan_v2_sync_subscription`.
10. [ ] **Cancelar renovação:** na UI normal; log `plan_v2_cancel_subscription` ou fluxo legado conforme linha “Doc canônico” do card.
11. [ ] **Reativar:** idem; log `plan_v2_reactivate_subscription` ou legado.
12. [ ] **Acesso até `currentPeriodEnd`:** conferir data no card/header e no Firestore após cancel (não corte imediato de acesso).
13. [ ] **Ampliar allowlist:** só após critérios na secção abaixo.
14. [ ] **Rollback:** se necessário, secção “Desligar piloto e voltar ao legado”.

## Monitoramento objetivo (piloto)

| O quê | Onde |
|--------|------|
| Criação preapproval | Log `evt=plan_v2_create_preapproval` |
| Webhook preapproval/pagamento | `plan_v2_preapproval_webhook`, `plan_v2_payment_webhook` |
| Sync | `plan_v2_sync_subscription` (`synced`, `phase`, `reason`) |
| Cancel / reativar | `plan_v2_cancel_subscription`, `plan_v2_reactivate_subscription` |
| Fallback checkout | Cliente: `[PlanosPilot] fallback checkout legado…` (backend off) |
| Erros MP | `plan_v2_cancel_mp_pause_failed`, `plan_v2_reactivate_mp_failed` |

Filtro único sugerido no Cloud Logging: texto `plan_v2_` **ou** (no dispositivo) `PlanosPilot`.

## Suporte e fallback (sem Firestore aberto o tempo todo)

| Sintoma | Como saber | Passo seguro |
|---------|------------|--------------|
| Checkout sempre abre preferência legada (não preapproval) | Card: `efetivo=não` **ou** log `[PlanosPilot] fallback…` ao tentar v2 | Ajustar RC (global/allowlist) **e** backend ligado; usuário pode concluir compra pelo legado. |
| Fallback por **backend** off | Log `RECURRING_PLAN_BILLING_DISABLED` / fallback `[PlanosPilot]` | Ligar `USE_RECURRING_PLAN_BILLING` ou aceitar legado até deploy. |
| Fallback por **RC/allowlist** | Card: `via=—`, `efetivo=não` | Colocar UID/e-mail na allowlist ou ligar RC global. |
| Doc v2 **incompleto** (sem `providerSubscriptionId`) | Card: linha “ausente”; sync desabilitado | Aguardar webhook ou usar **sync manual** depois que o id existir; se persistir, ver MP + `plan_recurring_intents`. |
| Cancel/reativar “errado” | Card: “Doc canônico: legado” mas usuário deveria ser v2 (ou o inverso) | Conferir `users/{uid}`; rodar **sync manual** se já houver id; não forçar callable v2 se doc for legado. |
| Quando **usar sync manual** | Webhook atrasado ou doc desatualizado face ao MP | Só com `providerSubscriptionId` presente (botão habilitado no card). |
| Quando **não insistir no v2** | Backend instável, MP com erro recorrente, piloto encerrado | Desligar allowlist/global RC; usuários seguem no **legado**; nenhuma migração forçada de doc. |

## Desligar piloto e voltar ao legado (rollback conservador)

1. Remote Config: `use_recurring_plan_billing=false` e **esvaziar** `recurring_plan_billing_allowlist` (ou remover pilotos).
2. Opcional: manter backend `USE_RECURRING_PLAN_BILLING` ligado para contas que já têm preapproval (cancel/sync continuam); só **novos checkouts** passam a ser legado no app.
3. Rollback “duro”: além do RC, planejar comunicação a usuários com assinatura v2 ativa (não coberto automaticamente pelo app).

### Ampliar a allowlist (critérios)

1. Piloto atual sem erros recorrentes em `plan_v2_cancel_*` / `plan_v2_reactivate_*` / webhooks.
2. Docs `users/{uid}` dos pilotos com `billingVersion: 2` estável após sync.
3. Aumentar em lote pequeno (ex.: +5 contas) e monitorar 24h.

## Piloto controlado — checklist (resumo)

- [ ] **Flags:** combinação escolhida na tabela abaixo documentada para o ambiente.
- [ ] **Allowlist:** só UIDs/e-mails de confiança; ampliar só após 48–72h sem incidente nos logs `plan_v2_*`.
- [ ] **Firestore:** após primeiro checkout v2, conferir `users/{uid}` (`billingVersion`, `providerSubscriptionId`, `billingSource`).
- [ ] **Logs:** filtrar `plan_v2_` no Cloud Logging durante o piloto.
- [ ] **App (root/programador):** em Planos → **Piloto billing v2** — resumo operacional + dump canônico + sync (se id presente).
- [ ] **Cancelar / reativar:** fluxo MP vs legado conforme linhas “Doc canônico” do card.

### Combinações de flags (referência)

| Backend `USE_RECURRING_PLAN_BILLING` | RC `use_recurring_plan_billing` | RC allowlist | Comportamento esperado no app |
|-------------------------------------:|----------------------------------|--------------|-------------------------------|
| off | off | vazia | Sempre checkout **legado** (`planCreatePreference`). |
| off | on | qualquer | Tenta v2 → **fallback** legado (log `[PlanosPilot] fallback…`). |
| on | off | **com** UIDs/e-mails piloto | Só piloto usa **createPlanSubscription**; demais legado. |
| on | on | vazia ou complemento | Todos elegíveis a v2 (ainda sujeito a erros MP). |

## Validação manual (rollout)

1. **RC off / backend off:** checkout deve usar `planCreatePreference`; sem erros.
2. **RC on / backend off:** tentativa `createPlanSubscription` → fallback automático para legado (log `[PlanosPilot] fallback checkout legado…`).
3. **Backend on / RC off / allowlist on:** só contas na lista veem checkout v2; outras legado.
4. **RC on / backend on:** checkout abre MP preapproval; após retorno, `users/{uid}` com `billingVersion: 2` e `providerSubscriptionId`.
5. **Webhook preapproval:** logs `plan_v2_preapproval_webhook`; doc com `billingSource` coerente com status MP.
6. **Pagamento com preapproval:** log `plan_v2_payment_webhook`; extras de billing no `activatePlanForUser`.
7. **Cancelar renovação:** log `plan_v2_cancel_subscription`; `cancelAtPeriodEnd: true`.
8. **Reativar:** log `plan_v2_reactivate_subscription`; `cancelAtPeriodEnd: false`.
9. **`syncPlanSubscription`:** log `plan_v2_sync_subscription` com `phase` ou `reason: no_provider_subscription`; no app, snackbar com `synced` true/false.
10. **Acesso até fim do período:** inalterado — backend mantém `currentPeriodEnd` e pausa no MP conforme implementação atual.

## Inspeção no app (root/programador)

- `PlanCanonicalBillingSnapshot` / `PlanosService.fetchCanonicalBillingSnapshot` espelham o mesmo estado que `fetchCurrentPlan` (fonte `users/{uid}`).
- `PilotBillingOperationHints` agrega rótulos operacionais (doc v2 vs legado, checkout RC global vs allowlist, `providerSubscriptionId`, disponibilidade de sync) — ver código em `planos_service.dart`.
- Na tela Planos, o bloco **Piloto billing v2** mostra: título com sufixo **doc v2** / **doc legado**, subtítulo `via=RC global` ou `allowlist`, resumo em teal, dump canônico e botão sync (habilitado só com `providerSubscriptionId`).

### Consulta de **outra** conta (somente root, leitura)

- Callable `getPlanBillingSnapshotForSupport` (região `southamerica-east1`): **somente** se o e-mail do token JWT estiver em `ROOT_ACCOUNT_EMAILS` (mesma lista que `functions/src/rootAccounts.js` / `RoleUtils` no app).
- Corpo: exatamente um campo — `targetUid` **ou** `targetEmail`. Por e-mail: `admin.auth().getUserByEmail` (sem varredura de coleção). Por UID: leitura de `users/{uid}` após validar que o UID existe no Authentication.
- **Sem escrita**; sem cancelar/reativar/sync de terceiros. Log JSON: `evt: plan_support_snapshot_read` (e `plan_support_snapshot_denied` se não for root).
- No app: Planos → bloco piloto → campo **UID ou e-mail** → **Consultar**. O texto exibido replica campos do doc + `interpretationLabels` (ex.: `doc_v2_mp`, `cancel_renew_path_legado`, `sem_doc_users`).
- **Limites:** não substitui auditoria completa no Console; e-mail deve ser o cadastrado no Firebase Auth. Rate limit: 40/min por identificador (abuso).
- **Quando usar em vez do Firestore:** triagem rápida de billing de um cliente sem abrir o console; para edições continue usando o Console ou fluxos administrativos existentes.

## Callables (região `southamerica-east1`)

- `createPlanSubscription` — cria preapproval MP (`POST /preapproval`), grava `plan_recurring_intents/{id}` e estado pendente em `users/{uid}`.
- `cancelPlanSubscription` — `cancelAtPeriodEnd` + tentativa `PUT` pausar preapproval no MP.
- `reactivatePlanSubscription` — limpa cancelamento + `PUT` reautorizar preapproval.
- `syncPlanSubscription` — `GET /preapproval/{id}` e reconcilia `users/{uid}`.

## Webhook `planWebhook`

- `topic=payment` (padrão): fluxo atual (`/v1/payments/{id}`).
- `topic=subscription` ou contendo `preapproval`: processa preapproval (`GET /preapproval/{id}`), dedupe em `processed_plan_events/{preapproval_*}`.

Configure no painel MP o mesmo segredo (`MP_WEBHOOK_SECRET`) e a URL da função `planWebhook`.

## Cliente (cancelar / reativar renovação)

- `PlanosService.cancelCurrentPlanRenewal` / `reactivateCurrentPlanRenewal` leem o plano em `users/{uid}` e escolhem:
  - `billingVersion == 2` (ou `billingSource` prefixo `mp_` + `providerSubscriptionId` preenchido, se `billingVersion` ausente) → callables `cancelPlanSubscription` / `reactivatePlanSubscription`;
  - caso contrário → fluxo legado `cancelPlanRenewalAtPeriodEnd` / `reactivatePlanRenewal`.
- A tela de planos chama apenas esses métodos; não duplica a regra.

## Firestore

- `users/{uid}`: campos opcionais `provider`, `billingVersion`, `billingSource`, `providerSubscriptionId`, `providerPreapprovalPlanId`, `planLastSyncedAt`.
- `plan_recurring_intents/{preapprovalId}`: auditoria (só backend).
- `processed_plan_events/*`: dedupe (só backend; rules bloqueiam cliente).

## Limites

- Contrato exato do JSON `POST /preapproval` pode exigir ajuste conforme conta/rede MP (testes em sandbox).
- Cancelamento “só no fim do período” no MP pode exigir modelo `paused` vs `cancelled` — hoje: pausa + `cancelAtPeriodEnd` no Firestore, alinhado ao fluxo manual existente.
