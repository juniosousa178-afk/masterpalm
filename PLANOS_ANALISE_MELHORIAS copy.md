# Análise da Tela de Planos e Integração Mercado Pago

## 1. Como funciona hoje

### Tela de Planos (`planos_screen.dart`)
- **Planos exibidos**: Grátis 90 dias, Mensal (R$ 25,90), Anual (R$ 299,90)
- **Fluxo Grátis**: Chama `PlanosService.activateFreeTrial90d` → grava em `users/{uid}` e `subscriptions`
- **Fluxo Pago**: Chama `CheckoutService.abrirCheckoutPlano` → cria preferência no MP → abre URL externa (`init_point`)

### CheckoutService
- Usa **Master Config** (`app_config/master_config`) para Access Token do MP
- Apenas root (masterpalm@gmail.com) pode configurar em Configurações Master
- Cria preferência com `external_reference: plano_mensal_123456` ou `plano_anual_123456`
- **URLs de retorno**: hardcoded `https://masterpalm-58c46.web.app` (Firebase Hosting antigo)
- Salva em `checkout_planos` para auditoria

### Webhook Mercado Pago
- **mpWebhookHandler.js**: processa apenas **pedidos de loja** (external_reference = orderId)
- **NÃO processa pagamentos de planos** – o external_reference dos planos é `plano_mensal_xxx`
- O webhook busca pedido em `lojas/{lojaId}/pedidos/{orderId}` – inexistente para planos

---

## 2. Problemas identificados

| Problema | Impacto |
|----------|---------|
| **URL base errada** | `masterpalm-58c46.web.app` – domínio antigo. O app usa `app.mastepalm.com.br` |
| **Webhook não ativa plano** | Pagamento aprovado no MP não ativa o plano automaticamente |
| **MP só via Master Config** | Usuário comum não consegue assinar – depende de root configurar |
| **Checkout em janela externa** | Mobile: abre navegador, usuário sai do app. Ao voltar, não há feedback |
| **Preços fixos no código** | R$ 25,90 e R$ 299,90 – difícil alterar sem deploy |
| **Sem verificação de MP** | Erro genérico "MP não configurado" – usuário não sabe o que fazer |
| **Duas estruturas de plano** | PlanosService usa `users` + `subscriptions`; ensureUserPlan usa `users` com campos diferentes |

---

## 3. Melhorias sugeridas

### 3.1 Integração Mercado Pago (prioridade alta)

1. **Corrigir URL base**  
   Usar `https://app.mastepalm.com.br` em vez de `masterpalm-58c46.web.app`.

2. **Webhook para planos**  
   Criar handler que:
   - Detecte `external_reference` começando com `plano_`
   - Extraia `planoId` e `user_email` do metadata
   - Chame `PlanosService.markPaidActive` ou equivalente
   - Grave em `users/{uid}` com `plan`, `plan_renewsAt`, etc.

3. **Fallback de token**  
   Se Master Config não tiver token, tentar token global (Secret Manager) para não bloquear.

4. **Link para configurar MP**  
   Se root: botão "Configurar Mercado Pago" levando à Master Config.

### 3.2 UX da tela de planos

1. **Indicador de MP configurado**  
   Badge "Mercado Pago pronto" ou "Configure o MP" conforme estado.

2. **Mensagem clara quando MP não configurado**  
   Ex.: "Para assinar, o administrador precisa configurar o Mercado Pago em Configurações Master."

3. **Em Web: checkout no app**  
   Usar SDK do MP em modal/iframe em vez de `launchUrl` externo.

4. **Polling pós-checkout**  
   Após abrir checkout, fazer polling em `checkout_planos` ou `users/{uid}` para detectar ativação.

### 3.3 Preços e configuração

1. **Preços no Remote Config**  
   Chaves `plano_mensal_preco`, `plano_anual_preco` para alterar sem deploy.

2. **Preços no Firestore**  
   Doc `app_config/planos` com preços e benefícios.

### 3.4 Unificar estruturas de plano

- Alinhar `PlanosService` (Flutter) com `ensureUserPlan` (Cloud Function).
- Garantir que ambos leiam/escrevam os mesmos campos em `users/{uid}`.

---

## 4. Implementações realizadas (esta sessão)

- [x] Corrigir URL base no CheckoutService para `app.mastepalm.com.br`
- [x] Verificação de MP configurado ao carregar a tela
- [x] Banner "Mercado Pago não configurado" quando aplicável
- [x] Botões de assinatura desabilitados com mensagem clara quando MP não configurado
- [x] Dialog explicativo ao clicar em "Assinar" sem MP configurado
- [x] Link direto para Master Login (se root) para configurar o MP

---

## 5. Implementações concluídas (próximos passos)

### ✅ Webhook para planos
- `planWebhook` estendido para aceitar formato do CheckoutService Flutter (`plano_mensal_123`, metadata com `user_email`)
- Busca `uid` via `admin.auth().getUserByEmail(user_email)`
- `activatePlanForUser` atualizado com campos compatíveis ao PlanosService (`currentPlanId`, `currentPeriodEnd`)

### ✅ Notification URL
- CheckoutService usa `planWebhook` diretamente (Cloud Functions)

### ✅ Páginas de retorno
- Rotas `/checkout/success`, `/checkout/failure`, `/checkout/pending` no `main.dart`
- `PagamentoResultadoScreen` com suporte a `planoId` e mensagens específicas para planos

### ✅ Preços dinâmicos
- Remote Config: `plano_mensal_preco`, `plano_anual_preco`
- `planos_screen.dart` usa `RemoteConfigService.planoMensalPreco` e `planoAnualPreco`

### Configuração no Mercado Pago
- O webhook é enviado automaticamente na preferência (`notification_url`)
- Não é necessário configurar URL manualmente no painel do MP
