# mpCatalogPayment — backlog conhecido

Comportamentos do live (`mpcatalogpayment-00100-red`) mantidos de propósito na reconciliação com o repositório.
Corrigir cada um em mudança própria, com teste e decisão de deploy separados.

## A. `back_urls` enviadas pelo cliente sem validação no servidor

- `type: "preference"` usa `body.backUrls` como `back_urls` da preferência, sem checar origem, host ou caminho.
- Sem `backUrls`, o servidor usa `${WEB_BASE}/pagamento/{sucesso|falha|pendente}?loja=<lojaId>`.
- Desde a 1.0.149 o catálogo envia `/loja/{loja}?pagamento=...`; a correção não pode quebrar esse contrato.
- Não afeta a autoridade do pagamento (o webhook confirma), mas permite redirecionar o comprador para qualquer URL após o checkout.

## B. `unit_price` da preferência sem normalização em centavos

- `unit_price = total / quantidade`, com `quantidade` vinda do cliente; não passa por `normalizeBrlTransactionAmountForMpPix`.
- Ex.: total 100 e `quantidade: 3` → `unit_price` 33.333333333333336.
- O total do pedido continua vindo do servidor; o risco é recusa ou arredondamento divergente no Mercado Pago.
