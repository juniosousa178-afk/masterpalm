# Cloud Functions — runtime e regras de deploy

Documento de referência para qualquer deploy de Cloud Functions do projeto `masterpalm-58c46`.
Prevalece sobre comandos antigos espalhados por outros `.md` e scripts do repositório.

## Runtime

- **Todas as 100 Functions de produção rodam em `nodejs22`** (codebases `default` e `main`), desde 2026-10-23.
- `firebase.json` declara `"runtime": "nodejs22"` nos dois codebases; `functions/package.json` e `main/package.json` declaram `"engines": {"node": "22"}`.
- `nodejs20` é desativado em 2026-10-30. Não voltar a declarar Node 20: um deploy com runtime 20 falha ou rebaixa a Function.
- Depreciação prevista do `nodejs22`: 2027-04-30. Planejar a próxima migração antes disso.

## Proibido

- `firebase deploy` sem `--only`.
- `firebase deploy --only functions` (deploy amplo de todas as Functions).
- `--force` em qualquer deploy de Functions.
- Scripts antigos que fazem deploy amplo (`deploy-tudo.ps1`, `scripts/deploy_full.*`, `scripts/deploy-completo.*`, `scripts/build-e-deploy-tudo.ps1`) e os comandos amplos em `DEPLOY.md`, `docs/COMANDOS*.md` e demais guias antigos.

## Deploy permitido

Somente direcionado, por nome, com o projeto explícito:

```bash
firebase deploy --only "functions:default:<nome1>,functions:default:<nome2>" --project masterpalm-58c46
firebase deploy --only "functions:main:<nome>" --project masterpalm-58c46
```

Antes de cada deploy:

1. Confirmar que a Function **não** está na lista de drift abaixo (ou que o drift foi reconciliado).
2. Confirmar que o código do repositório é o que se quer publicar (comparar com o source live quando houver dúvida).
3. Saber que o CLI vincula secrets na **versão mais recente** (`latest`) e regrava as env vars a partir do repositório. Se a Function está fixada numa versão antiga de secret, o deploy troca essa versão.
4. Ter a revisão atual anotada para rollback.

## Functions com source ou configuração live diferente do repositório

O runtime está igual em produção e no repositório, mas **o código e a configuração não estão**.
As Functions abaixo foram migradas para Node 22 por troca de runtime via API (sem rebuild a partir do repositório).
**Não fazer deploy delas pelo CLI antes de reconciliar o repositório com o live.**

### Código live diferente do repositório

| Function | Situação |
|---|---|
| `planWebhook` | Live publicado a partir de um commit diferente do repositório. |
| `createPreference`, `planCreatePreference`, `planCreatePreferenceCall` | Handlers live diferentes do repositório. |
| `calcularSuperFrete`, `superFreteQuote` | Frete: código live diferente. |
| `catalogPublishCommercialFieldsOnly`, `stockCatalogOrderSale` | Catálogo/venda: código live diferente; `stockCatalogOrderSale` não existe no repositório. |
| `girarRoletaCatalogo` | Roleta: o repositório adiciona rate-limit que o live não tem. |
| `syncPlanSubscription` | Código live diferente. |
| `scheduledMonitorStuckPlanPayments` | Não existe no repositório. |
| `activateUserTrial90d` (us-central1) | Não existe no repositório. Existe também em southamerica-east1; `--only functions:default:activateUserTrial90d` casa as duas regiões e o CLI tentaria apagar a de us-central1. |

### Configuração que o CLI mudaria

- **`WEB_BASE_URL`:** 28 Functions estão fixadas na versão 3 do secret. Um deploy pelo CLI as passaria para a versão mais recente. Só fazer isso com decisão explícita sobre a URL base.
- **`mpCatalogPayment`:** o código do repositório é igual ao live (`mpcatalogpayment-00100-red`: handler e dependências com o mesmo sha256, paridade por fixtures), mas a configuração não. O live está fixado em `WEB_BASE_URL:3` e `MP_ACCESS_TOKEN:27`; o deploy pelo CLI vincularia a versão mais recente de cada secret. Continua protegida: deploy só com decisão explícita e depois de `npm run test:mp-catalog-payment` (em `functions/`) passar.
- **`cancelPlanSubscription`, `reactivatePlanSubscription`:** o deploy acrescentaria `USE_RECURRING_PLAN_BILLING`, que essas Functions leem, e mudaria o comportamento.
- Demais Functions migradas por troca de runtime (frete, domínio de catálogo, triggers de loja/site/portal/pagamentos públicos, thumbnails, OAuth do Mercado Pago, `mpWebhook`, `devCreateOrder`, `gerarCupomNumeroSorte`, `provisionSubdomain`, `sendWhatsAppOrderConfirmation`): revisar o diff de código e de env/secrets contra o live antes do primeiro deploy pelo CLI.

## Rollback

Cada mudança cria uma revisão nova no Cloud Run. Para reverter, direcionar 100% do tráfego do serviço para a revisão anterior (Cloud Run → serviço → revisões → gerenciar tráfego). Não corrigir para frente sob pressão.

## Trocar só o runtime sem rebuild a partir do repositório

Para mudar o runtime de uma Function preservando exatamente o source, env, secrets, IAM e triggers live, usar a API Cloud Functions v2 com máscara restrita:

```
PATCH https://cloudfunctions.googleapis.com/v2/projects/masterpalm-58c46/locations/<região>/functions/<nome>?updateMask=buildConfig.runtime
{"buildConfig": {"runtime": "<runtime>"}}
```

A plataforma recompila a partir do mesmo objeto de source live (MD5 idêntico). Validar depois: runtime, revisão nova com 100% do tráfego, MD5 do source igual, env/secrets/IAM/trigger iguais e logs sem erro.
