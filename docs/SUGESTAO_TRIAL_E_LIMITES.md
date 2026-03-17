# Trial de 3 meses e limites (implementado)

**Status:** Implementado. Trial e plano pago passaram a ter limites conforme abaixo.

### Valores aplicados

- **Trial (3 meses):** 80 produtos, 150 clientes, 50 vendas/mês, 3 fotos por produto, 6 banners.
- **Plano pago:** 6 fotos por produto, 6 banners; produtos/clientes/vendas ilimitados.
- **Free limitado:** mantido (10 produtos, 20 clientes, 10 vendas/mês, 1 foto, 1 banner).

---

## Resumo da sugestão

- **Não precisa** tirar os 3 meses nem deixar o trial “minúsculo”.
- **Vale a pena** colocar **limites brandos durante o trial** (ex.: teto de produtos, clientes e vendas/mês). Assim você:
  - controla custo e abuso (Firebase + uso pesado),
  - mantém trial longo e generoso para loja real testar,
  - evita “uso infinito” só no free.

Ou seja: **3 meses continua; durante esse período, limites altos mas existentes.**

---

## Por que limitar algo no trial (em vez de 100% ilimitado)

| Motivo | Explicação |
|--------|------------|
| **Custo Firebase** | Trial ilimitado = loja pode cadastrar centenas de produtos, clientes e vendas. Cada um gera leituras/escritas e, no catálogo, listener em muitos docs. Vários trials “pesados” sobem a conta. |
| **Abuso** | Uma pessoa pode abrir várias contas, encher de dados e nunca pagar. Limite por loja reduz esse jogo. |
| **Conversão** | Quem realmente usa (ex.: 50 produtos, 30 vendas/mês) já validou o app. Quem precisa de 500 produtos em 3 meses sem pagar é sinal para virar plano pago. |
| **Expectativa** | Deixar claro “trial com X produtos / Y vendas por mês” é transparente e evita surpresa quando, depois, existir free_limited com limites menores. |

---

## O que você já tem hoje

- **free_trial_90d:** 3 meses **sem** limites (LimitsGuard não aplica para esse plano).
- **free_limited:** após o trial, limites fortes (10 produtos, 1 foto/produto, 10 vendas/mês, 20 clientes).

Ou seja: hoje o trial é realmente “tudo liberado” por 90 dias.

---

## Opção recomendada: limites “generosos” no trial

Manter **3 meses de trial**, mas tratar **free_trial_90d** como plano com **limites altos** (não ilimitado). Exemplo de tetos só para o trial:

| Recurso | Sugestão no trial | Motivo |
|---------|-------------------|--------|
| **Produtos** | 80–100 | Loja pequena testa bem; evita 500+ produtos em uma conta trial. |
| **Clientes** | 150–200 | Idem. |
| **Vendas/mês** | 50–80 | Uso real de teste; evita milhares de vendas só no free. |
| **Fotos por produto** | 3–5 | Catálogo bonito sem abusar de Storage. |

Números são ajustáveis; o importante é: **ter teto no trial**, mas alto o suficiente para não atrapalhar quem realmente testa.

Vantagens:
- Custo por conta trial fica previsível (ex.: até ~100 produtos + ~50 vendas/mês).
- Quem precisa de mais já tem motivo claro para assinar (pro_monthly / pro_yearly).
- Você continua oferecendo “3 meses para experimentar” sem soar restritivo demais.

---

## Opção alternativa: encurtar trial “full”

Se preferir **não** mexer em limites e só reduzir custo pelo tempo:

- **1 mês “full”** + depois **2 meses em free_limited** (já com 10 produtos, 10 vendas/mês, etc.).

Assim você reduz a janela de uso ilimitado, mas perde um pouco o discurso “3 meses completos”. Por isso a opção principal sugerida é **manter 3 meses com limites brandos**.

---

## Onde está implementado

- **SubscriptionService** (`lib/services/subscription_service.dart`): `trialLimits`, `paidLimits`; `freeLimitedLimits` e `freeLimits` com `maxBanners`.
- **LimitsGuard** (`lib/services/limits_guard.dart`): planos `free_trial_90d`, `pro_monthly`, `pro_yearly`, `lifetime` usam os novos limites; `canAddBanner` e `maxBanners(planId)`.
- **LojaConfigScreen** (`lib/screens/loja_config_screen.dart`): ao adicionar banners, verifica `canAddBanner` e limita quantidade ao `maxBanners` do plano.
- Produto (fotos) e cliente/venda já usam `canAddProduto`, `canAddCliente`, `canAddVenda` e `maxImagesPerProduct`; passam a respeitar trial (80, 150, 50, 3) e pago (6 fotos).

---

## Conclusão

- **3 meses gratuitos:** não é exagerado como período; é um bom diferencial.
- **Recomendação:** manter os 3 meses e **limitar durante o trial** (produtos, clientes, vendas/mês, fotos por produto) com tetos generosos. Isso controla custo e abuso sem tirar a sensação de “testar de verdade”.
- **Evitar:** trial 100% ilimitado por 3 meses se você se preocupa com custo Firebase e com abuso; um meio-termo com limites altos é mais sustentável.

Se quiser, na próxima etapa podemos definir os números exatos (ex.: 100 produtos, 60 vendas/mês) e onde encaixar no `PlanosService` / `LimitsGuard` sem quebrar o que já existe.
