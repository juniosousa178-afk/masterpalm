# MasterPalm — Rotação do segredo SMTP + cutover 1.0.134+148

Release alvo: `APP_VERSION=1.0.134+148`, `BUILD_ID=nathy-variation-raffle-email-security-1.0.134`.
Live no momento da preparação: `1.0.133+147`, web `e92edd4`.

Este documento **não contém** nenhum valor de credencial. A senha de app Gmail que esteve
compilada em `lib/services/email_service.dart` (APK + JS web) é tratada como **comprometida**.

## 1. Estado de produção (read-only, 2026-10-09)

Funções com `SMTP_EMAIL`/`SMTP_PASSWORD` vinculados (todas fixadas na **versão 3** do Secret Manager):

| Função | Revisão atual |
|---|---|
| mpWebhook | mpwebhook-00154-bos |
| onPrePedidoCreated | onprepedidocreated-00098-raf |
| onPedidoPendenteCreated | onpedidopendentecreated-00077-mug |
| onPrePedidoClienteEmail | onprepedidoclienteemail-00007-jay |
| sendEmail | sendemail-00002-bed |
| solicitarRedefinicaoSenhaCatalogo | solicitarredefinicaosenhacatalogo-00089-yut |
| enviarEmailVerificacao | enviaremailverificacao-00052-muz |

`SMTP_PASSWORD` tem as versões 1, 2 e 3 em estado `ENABLED`.

Consequência: criar uma versão nova **não** muda nada sozinho — cada função precisa de nova
revisão apontando para a versão nova. Fonte: `mp-130/fn-secrets-ro.mjs` (só metadados).

## 2. Ordem do cutover

### A — Functions (somente as 4 do escopo)

```
firebase deploy --project masterpalm-58c46 --only functions:mpWebhook,functions:gerarCupomNumeroSorte,functions:sendEmail,functions:sendWhatsAppOrderConfirmation
```

- **Não** incluir `mpCatalogPayment` (patch PIX só em produção; ver `artifacts/raffle_hardening/FUNCTION_SOURCE_DRIFT.json`).
- Nenhuma Rule, nenhuma outra função.
- Verificar: as 4 `ACTIVE`, 100% do tráfego na nova revisão, 0 erros novos nos logs (15 min).
- Smoke do `sendEmail` novo (sem enviar a cliente real):
  - `POST` sem `Authorization` e sem `emailType` → `400 EMAIL_TYPE_REQUIRED`;
  - `POST` com `subject`/`html` de sorteio antigo → `200 {sent:false, code:RAFFLE_NOT_ACTIVE}`;
  - `POST` com `emailType` e sem token → `401 UNAUTHENTICATED`.

A partir deste ponto o relay aberto está fechado no servidor.

### B — Hosting web 1.0.134+148

Build limpo do commit final, `CATALOG_BUILD_ID=nathy-variation-raffle-email-security-1.0.134`.
Antes de publicar: scan do `build/web` com `mp-130/smtp-secret-scan.mjs` = 0 ocorrências.

### C — Rotação da senha de app (feita pelo dono da conta Google)

1. O dono entra na conta Google do remetente (`SMTP_EMAIL`) → Segurança → Senhas de app →
   cria uma nova (ex.: `masterpalm-functions-2026-10`). **Não colar a senha no chat**, em
   ficheiros, Dart, JS ou `.env` versionado.
2. No terminal do dono (prompt oculto):
   ```
   npx -y firebase-tools@latest functions:secrets:set SMTP_PASSWORD --project masterpalm-58c46
   ```
   Cria a versão 4. Quando o CLI perguntar se deve fazer redeploy das funções que usam o
   segredo, responder **NÃO** (redeploy a partir do repo traria drift nas 5 funções fora do escopo).
3. Religar as 7 funções à versão 4 **sem mudar código** (nova revisão Cloud Run com a mesma imagem):
   ```
   foreach ($s in 'mpwebhook','onprepedidocreated','onpedidopendentecreated','onprepedidoclienteemail','sendemail','solicitarredefinicaosenhacatalogo','enviaremailverificacao') {
     gcloud run services update $s --region=southamerica-east1 --project=masterpalm-58c46 --update-secrets=SMTP_PASSWORD=SMTP_PASSWORD:4
   }
   ```
   Confirmar com `node mp-130/fn-secrets-ro.mjs <7 funções>` que todas mostram `version: "4"`.
4. Envio de verificação seguro: um `solicitarRedefinicaoSenhaCatalogo` (ou `order_confirmation`
   de um pedido da loja de teste) para uma caixa controlada pelo dono. Logs sem `EAUTH`.
5. **Revogar** a senha de app antiga na conta Google (revogar todas as senhas de app que não
   sejam a nova, se não houver outro sistema que dependa delas).
6. Desativar versões antigas: `gcloud secrets versions disable 1 2 3 --secret=SMTP_PASSWORD --project=masterpalm-58c46`
   (só depois do passo 3 confirmado — uma função ainda em v3 deixaria de arrancar).

Janela entre os passos 1 e 5: o mínimo possível (alvo < 30 min). Ambas as credenciais não
devem ficar válidas além do necessário.

Se a versão 3 for a mesma senha comprometida, revogar antes do passo 3 derrubaria todo o
e-mail do servidor — por isso a ordem é religar → verificar → revogar.

### D — APK 1.0.134+148

Build release com o mesmo `CATALOG_BUILD_ID`; scan do APK = 0 ocorrências antes de distribuir.

## 3. Clientes antigos depois do cutover

| Cliente antigo (≤ 1.0.133) | Antes da rotação (C) | Depois da rotação (C) |
|---|---|---|
| CampaignEngine — e-mail de sorteio cru | `200 RAFFLE_NOT_ACTIVE`, sem envio, sem fallback SMTP local | igual |
| PosPagamento — confirmação de pedido crua | `400 EMAIL_TYPE_REQUIRED` → sem e-mail | igual |
| Carrinho abandonado — e-mail cru | `400` → app antigo cai no SMTP embutido (ainda funciona) | SMTP embutido falha (`EAUTH`) → sem e-mail |
| Redefinição de senha no APK antigo | SMTP embutido | falha; app novo usa o callable `solicitarRedefinicaoSenhaCatalogo` |

`OLD_APK_HAS_NO_VALID_SMTP_CREDENTIAL_AFTER_ROTATION=true` depois do passo C.5.

## 4. Riscos residuais (fora deste release)

- `sendWhatsAppOrderConfirmation` continua sem autenticação (relay WhatsApp pelo número Meta da loja). Follow-up.
- `onPrePedidoCreated` pode ser disparado por escrita pública de `pre_pedidos` (template fixo, sem conteúdo livre).
- `enviarEmailVerificacao` sem entrada em `RATE_LIMITS`.
- App Check não aplicado.
- O segredo antigo continua no histórico git (commit de origem `e40ee83`). Não foi reescrito; a rotação torna-o inútil.
- `mpCatalogPayment`: reconciliação do patch PIX só-produção é tarefa separada (`MP_CATALOG_PAYMENT_DEPLOYS=0`).
