# AUDITORIA TÉCNICA COMPLETA - MasterPalm
## Fluxo: Catálogo Web → Cadastro/Login → Checkout → Venda → Notificações

**Data:** 21/03/2025  
**Escopo:** Fluxo end-to-end do cliente no catálogo até conclusão da venda

---

## 1. RESUMO EXECUTIVO

### Como o fluxo funciona hoje

O MasterPalm possui um **catálogo web público** acessível via `/loja/{slug}` ou `app.mastepalm.com.br/loja/{slug}`. O cliente navega pelos produtos, adiciona ao carrinho, faz login/cadastro obrigatório (ClienteAuthService → `lojas/{lojaId}/clientes`), preenche dados de entrega e finaliza por **WhatsApp** ou **Mercado Pago/PIX**.

O pedido é criado como **pré-pedido** em `lojas/{lojaId}/pre_pedidos` pelo `PrePedidoService`. Uma Cloud Function (`onPrePedidoCreated`) cria notificação em `notificacoes`, envia email ao admin e push FCM. Outra CF (`syncPedidoStatusPublico`) espelha em `pedido_status_publico` e em `clientes_portal/{portalToken}/pedidos` para o cliente ver "Meus Pedidos".

O status é atualizado no painel admin e espelhado via `syncPedidoStatusPublico` (onDocumentWritten em `pre_pedidos`). O cliente visualiza o status em `PedidoPublicoScreen` (link público) ou na aba "Meus Pedidos" do perfil (via `clientes_portal`).

### Riscos principais

1. **Falha silenciosa em "Meus Pedidos"**: Se `_resolvePortalTokenForPedido` não encontrar cliente em `clientes` (por email ou clienteId), `clientes_portal` não é preenchido e o pedido **não aparece** no perfil do cliente, mesmo tendo sido criado com sucesso.
2. **Modelagem fragmentada de cliente**: 5 coleções diferentes (clientes, clientes_web, clientes_portal, clientes_catalogo, estoque_clientes) com lógicas e chaves distintas.
3. **PrePedidoService grava em coleção errada**: `_salvarOuAtualizarCliente` e `_adicionarPedidoAoHistoricoCliente` usam `estoque_clientes` (chave = telefone), enquanto o perfil do catálogo usa `clientes` (chave = clienteId gerado). São históricos desconectados.
4. **posPagamento.js multi-tenant quebrado**: Loja hardcoded como `'masterpalm'`; usa `collectionGroup('pedidos')` em vez de `pre_pedidos`.
5. **Mensagem de sucesso prematura no WhatsApp**: O sheet fecha e o WhatsApp abre **antes** de confirmar que o pré-pedido foi persistido com sucesso (o create é síncrono, mas não há validação pós-write).

### Pontos mais críticos

- **clientes_portal vazio** quando cliente não está em `clientes` com portalToken
- **estoque_clientes** usado para "histórico" mas não conectado ao perfil do catálogo
- **posPagamento.js** inutilizável em multi-loja
- **ClienteWebService** vs **ClienteAuthService**: dois fluxos de auth, apenas ClienteAuthService é usado no catálogo atual

---

## 2. MAPA COMPLETO DO FLUXO END-TO-END

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 1. ENTRADA NO CATÁLOGO                                                           │
├─────────────────────────────────────────────────────────────────────────────────┤
│ main.dart: _isPublicCatalogUrl() → _lojaSlugOrIdFromUrl() → _resolveSlugToStoreId│
│ → CatalogWebRoot(lojaId) → PublicCatalogScreen(lojaId)                           │
│ Arquivos: main.dart (linhas 674-723, 986-1006), public_catalog_screen.dart       │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 2. CADASTRO / LOGIN DO CLIENTE                                                   │
├─────────────────────────────────────────────────────────────────────────────────┤
│ PublicCatalogScreen → LoginScreenCliente / CadastroScreenCliente                 │
│ ClienteAuthService.cadastrar() | login() | loginComGoogle()                      │
│ Firestore: lojas/{lojaId}/clientes (doc id = clienteId ou googleUid)             │
│ Sessão: SharedPreferences cliente_logado, cliente_loja_id                        │
│ Arquivos: login_screen_cliente.dart, cadastro_screen_cliente.dart,               │
│           cliente_auth_service.dart (linhas 41-174, 550-610)                     │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 3. CARRINHO E CHECKOUT                                                           │
├─────────────────────────────────────────────────────────────────────────────────┤
│ PublicCatalogScreen._cart (estado local) → CarrinhoSheetWeb                      │
│ Login obrigatório: ClienteAuthService.getClienteLogado() antes de finalizar      │
│ Arquivos: public_catalog_screen.dart, carrinho_sheet_web.dart (linhas 3359-3398) │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                        ┌───────────────┴───────────────┐
                        ▼                               ▼
┌──────────────────────────────┐    ┌──────────────────────────────────────────────┐
│ 4a. CHECKOUT WHATSAPP        │    │ 4b. CHECKOUT MERCADO PAGO / PIX               │
├──────────────────────────────┤    ├──────────────────────────────────────────────┤
│ PrePedidoService.criarPreP.. │    │ PrePedidoService.criarPrePedido()             │
│ → pre_pedidos (Firestore)    │    │ → CF criarPagamentoMercadoPago / createPix    │
│ → Abre WhatsApp com msg      │    │ → Redirect MP / abre QrCode PIX               │
│ → onSuccess() fecha sheet    │    │ → Redirect: /pagamento/sucesso?loja=          │
│ Arquivos: public_catalog_    │    │ Arquivos: public_catalog_screen.dart 2057-    │
│ screen.dart 1849-2035        │    │ 2180, functions/index.js (criarPagamento...)  │
└──────────────────────────────┘    └──────────────────────────────────────────────┘
                        │                               │
                        └───────────────┬───────────────┘
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 5. CRIAÇÃO DO PRÉ-PEDIDO (PrePedidoService.criarPrePedido)                       │
├─────────────────────────────────────────────────────────────────────────────────┤
│ Firestore: lojas/{lojaId}/pre_pedidos/{docRef.id}                                │
│ Campos: lojaId, tipo, status=pendente, cliente, itens, frete, total, pagamento,  │
│         vendedorRef, indicacaoClienteId, dataCriacao, origemCheckout             │
│ Em paralelo:                                                                     │
│   • _salvarOuAtualizarCliente → estoque_clientes (telefone como chave) ⚠️        │
│   • _adicionarPedidoAoHistoricoCliente → estoque_clientes ⚠️                     │
│   • _saveClientePortalPedidoResumo → clientes_portal/{portalToken}/pedidos ✅    │
│   • Email cliente (PedidoClienteEmailService.enviarPedidoRecebido)               │
│   • Email admin (PedidoClienteEmailService.enviarNovoPedidoParaAdmin)            │
│ Arquivos: pre_pedido_service.dart (linhas 154-434)                               │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 6. CLOUD FUNCTIONS (onCreate / onWrite)                                          │
├─────────────────────────────────────────────────────────────────────────────────┤
│ onPrePedidoCreated: notificacoes, email admin, push FCM (users/{adminUid})       │
│ syncPedidoStatusPublico: pre_pedidos → pedido_status_publico + clientes_portal   │
│ syncClientePortalProfile: clientes → clientes_portal (perfil)                    │
│ Arquivos: functions/index.js (1695-1881)                                         │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 7. VISUALIZAÇÃO PELO CLIENTE                                                     │
├─────────────────────────────────────────────────────────────────────────────────┤
│ • Link público: /c/{lojaId}?pedido= → PedidoPublicoScreen → pedido_status_publico│
│ • Perfil: PerfilClienteScreenNovo → ClienteAuthService.getPedidosDoCliente       │
│   → MeusPedidosRepository → clientes_portal/{portalToken}/pedidos                │
│ Arquivos: pedido_publico_screen.dart, perfil_cliente_screen_novo.dart,           │
│           meus_pedidos_repository.dart, cliente_portal_repository.dart           │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│ 8. NOTIFICAÇÃO ADMIN (APK / Web)                                                 │
├─────────────────────────────────────────────────────────────────────────────────┤
│ APK: FCM push (fcm_pedido_service.dart) + NotificacaoPedidoListener (stream)     │
│ Web: NotificacaoPedidoListener (stream notificacoes) + SnackBar + badge          │
│ Stream: NotificacaoVendasService().streamNotificacoes(uid, storeId)              │
│ Firestore: lojas/{lojaId}/notificacoes (destinatarioUid, tipo=novaVenda)         │
│ Arquivos: notificacao_pedido_listener.dart, notificacao_vendas_service.dart,     │
│           fcm_pedido_service.dart                                                │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. CADASTRO E PERFIL DO CLIENTE

### Onde acontece

- **Cadastro**: `CadastroScreenCliente` → `ClienteAuthService.cadastrar()`
- **Login**: `LoginScreenCliente` → `ClienteAuthService.login()` ou `loginComGoogle()`

### Como acontece

- Cadastro cria doc em `lojas/{lojaId}/clientes` com `gerarClienteId()`, `hashSenha(senha)`, `portalToken`, `dataCadastro`.
- Login busca por `email`, valida `senhaHash`, garante `portalToken` via `_ensurePortalToken` (CF `getClienteCatalog` se faltar).
- Sessão: `SharedPreferences` (`cliente_logado` JSON com clienteId, nome, email, telefone, portalToken; `cliente_loja_id`).

### Onde salva

- **clientes**: `lojas/{lojaId}/clientes/{clienteId}`
- **clientes_portal**: CF `syncClientePortalProfile` (onWrite em `clientes`) e `upsertClientePortalFromPedido` em `syncPedidoStatusPublico`.

### Como vincula ao pedido

- `pre_pedidos` tem `cliente.id` = clienteId quando logado.
- `_saveClientePortalPedidoResumo` usa `_resolvePortalTokenForPedido`: busca cliente por `cliente.id` ou `cliente.email` em `clientes`, obtém `portalToken`, grava em `clientes_portal/{portalToken}/pedidos/{pedidoId}`.

### Falhas encontradas

| # | Descrição |
|---|-----------|
| 1 | **ClienteWebService** usa `clientes_web` e `getPedidos` em `pre_pedidos` por `cliente.id`. O catálogo atual usa ClienteAuthService (`clientes`). ClienteWebService parece legado ou fluxo alternativo não integrado. |
| 2 | **Duplicidade por email**: Cadastro verifica `clientes` por email; login também. Cliente com mesmo email em `clientes_web` pode existir em paralelo (risco de duplicidade conceitual). |
| 3 | **portalToken nulo**: Se CF `getClienteCatalog` falhar ou cliente for criado antes da CF, `portalToken` pode estar vazio. `_saveClientePortalPedidoResumo` retorna sem gravar e "Meus Pedidos" fica vazio. |
| 4 | **Cliente sem login**: Checkout exige login. Não há fluxo visitante → login → reaproveitamento explícito de carrinho (carrinho é local por lojaId). |

---

## 4. CHECKOUT E CRIAÇÃO DA VENDA

### Fluxo real

1. Usuário preenche dados no `CarrinhoSheetWeb`, clica em "Finalizar por WhatsApp" ou "Pagar com PIX/Mercado Pago".
2. `ClienteAuthService.getClienteLogado()` é chamado; se null, exibe dialog de login.
3. `PrePedidoService.criarPrePedido()` é chamado com customer, itens, entrega, pagamento, clienteId.
4. Totais calculados no front (subtotal, frete, desconto PIX). O backend **aceita** esses valores sem recálculo.
5. Doc criado em `pre_pedidos` via `PedidoRepository.createPedido()`.
6. Em background: emails, atualização de endereço em `clientes`, `_saveClientePortalPedidoResumo`, criação na plataforma de frete (Melhor Envio, etc.).

### Funções reais

- `PrePedidoService.criarPrePedido()` — `pre_pedido_service.dart` linhas 154-434  
- `PedidoRepository.createPedido()` — `pedido_repository.dart`  
- Coleção: `lojas/{lojaId}/pre_pedidos`

### Banco real

- **pre_pedidos**: lojaId, tipo, status, cliente, itens, frete, total, pagamento, vendedorRef, dataCriacao, etc.
- **pedido_status_publico**: espelho sanitizado (CF syncPedidoStatusPublico).
- **clientes_portal/{portalToken}/pedidos/{pedidoId}**: resumo para "Meus Pedidos".

### Falhas encontradas

| # | Descrição |
|---|-----------|
| 1 | **Total aceito do frontend**: Não há validação server-side do total. Cliente malicioso poderia alterar valores. |
| 2 | **Clique duplo**: `_processandoCheckout` desabilita botão, mas entre o click e o setState há `Future.delayed(Duration.zero)`. Janela mínima para duplo clique existe. |
| 3 | **Mensagem de sucesso WhatsApp**: Sheet fecha e WhatsApp abre logo após `criarPrePedido` retornar. Se o write falhar após retorno (improvável com Firestore), usuário acreditaria que deu certo. |
| 4 | **Transação**: Não há transação Firestore. Vários writes (pre_pedido, estoque_clientes, clientes_portal, etc.) são independentes. Falha em um não reverte os outros. |

---

## 5. SALVAMENTO NO PERFIL / HISTÓRICO DO CLIENTE

### Como está funcionando hoje

- **Meus Pedidos** (perfil): `ClienteAuthService.getPedidosDoCliente` → `MeusPedidosRepository.getPedidosDoCliente` → `ClientePortalRepository.getPedidosDoCliente` → `clientes_portal/{portalToken}/pedidos`.
- **PrePedidoService** também chama:
  - `_salvarOuAtualizarCliente` → `estoque_clientes` (chave = telefone)
  - `_adicionarPedidoAoHistoricoCliente` → `estoque_clientes` (historicoCompras, totalCompras, quantidadeCompras)

### Onde atualiza

- `clientes_portal`: via `_saveClientePortalPedidoResumo` (PrePedidoService) e CF `syncPedidoStatusPublico` (upsertClientePortalFromPedido).
- `estoque_clientes`: via `_salvarOuAtualizarCliente` e `_adicionarPedidoAoHistoricoCliente`.

### Como o catálogo lê

- Perfil lê de `clientes_portal` via `portalToken` da sessão (cliente em `clientes`).
- `estoque_clientes` é usado pelo admin (histórico de clientes, sync Hive). O perfil do catálogo **não** usa estoque_clientes.

### Onde quebra

| # | Descrição |
|---|-----------|
| 1 | **clientes vs estoque_clientes**: Cliente em `clientes` tem id gerado (ex: `abc123`). `estoque_clientes` usa telefone como doc id. Um compra feita por cliente logado atualiza `estoque_clientes` por telefone, mas o perfil do catálogo lê `clientes_portal` por portalToken. Se `_resolvePortalTokenForPedido` falhar, `clientes_portal` não recebe o pedido e "Meus Pedidos" fica vazio. |
| 2 | **Cliente novo sem doc em clientes**: Checkout com dados preenchidos mas sem login cria pre_pedido com `cliente.id` vazio. `_resolvePortalTokenForPedido` tenta por email em `clientes`; se não achar, não grava em clientes_portal. |
| 3 | **Campo cliente.id**: PrePedidoService só preenche `cliente.id` quando `clienteId != null` (logado). Para visitante, `cliente.id` vazio e resolução depende apenas de email em `clientes` — mas checkout exige login, então em tese sempre há clienteId. |

---

## 6. STATUS DO PEDIDO

### Como nasce

- Status inicial: `pendente` (PrePedidoService, linha 218).
- Determinado por `determinarStatusPagamento(pagamento)` para `statusPagamento`.

### Como atualiza

- Admin: `PrePedidoService.atualizarStatus()` ou confirmação/cancelamento no painel.
- CF `syncPedidoStatusPublico` (onDocumentWritten em `pre_pedidos`) espelha para `pedido_status_publico` e `clientes_portal`.

### Onde é salvo

- **pre_pedidos**: status, dataAtualizacao.
- **pedido_status_publico**: status, total, itensResumo, codigoRastreio, freteNome.
- **clientes_portal/{token}/pedidos/{pedidoId}**: mesmo resumo.

### Onde aparece

- Cliente: `PedidoPublicoScreen` (link /c/{lojaId}?pedido=) lê `pedido_status_publico`.
- Perfil: "Meus Pedidos" lê `clientes_portal`.
- Admin: `PrePedidosScreen` lê `pre_pedidos`.

### Inconsistências

| # | Descrição |
|---|-----------|
| 1 | **Nomenclatura**: `status` vs `statusPagamento`. Em `pre_pedidos` existem ambos. Em `pedido_status_publico` só `status`. |
| 2 | **Cancelamento**: `cancelarPrePedido` deleta o doc em `pre_pedidos` e tenta atualizar `pedido_status_publico` e `clientes_portal` para 'cancelado' antes. Se a atualização falhar, o doc privado some mas o público pode manter status antigo. |
| 3 | **syncPedidoStatusPublico** no delete: quando `after?.exists` é false, deleta `pedido_status_publico`. Para cancelamento, `cancelarPrePedido` chama `_saveClientePortalPedidoResumo` com overrideStatus 'cancelado' antes de deletar; a CF não recebe o doc nesse fluxo, pois o delete é feito pelo app. A CF só vê o delete e remove o espelho. O `clientes_portal` é atualizado pelo app antes do delete. |

---

## 7. E-MAIL E NOTIFICAÇÕES

### Cliente

- **Pedido recebido**: `PedidoClienteEmailService.enviarPedidoRecebido` (PrePedidoService, unawaited).
- **Atualização de status**: `PedidoClienteEmailService.enviarAtualizacaoStatus` em `atualizarStatus` e `confirmarPrePedido`/`cancelarPrePedido`.
- **Proteção duplicata**: Não há flag `emailEnviado` ou idempotência. Múltiplas chamadas a `atualizarStatus` geram múltiplos emails.
- **Falha**: Try-catch com log; não bloqueia o fluxo.

### Admin

- **Novo pedido**: CF `onPrePedidoCreated` envia email (nodemailer) ao `ownerEmail`/`adminEmail`.
- **Push FCM**: CF lê `users/{adminUid}.fcmToken` e envia.
- **Notificação Firestore**: CF cria doc em `lojas/{lojaId}/notificacoes` (tipo novaVenda).
- **Remetente**: "MasterPalm" no email da CF. Branding da loja não é usado.

### Android

- FCM: `FcmPedidoService` salva token em `users/{uid}`. CF envia para `adminUid`. Funciona para loja cujo dono é o usuário logado.
- `NotificacaoPedidoListener` escuta `notificacoes` por `destinatarioUid` e `storeId`, exibe SnackBar e notificação local.

### Web

- FCM não disponível. `NotificacaoPedidoListener` usa stream de `notificacoes` e exibe SnackBar. Sem push com app minimizado.

### Falhas

| # | Descrição |
|---|-----------|
| 1 | Admin sem `ownerUid`/`adminEmail`: CF não envia email nem push. |
| 2 | `users` pode ter vários donos de lojas; FCM token é por uid. Se um uid for dono de várias lojas, recebe notificações de todas. Correto. Se loja tiver `ownerUid` incorreto, notificação vai para usuário errado. |
| 3 | Email do admin usa remetente "MasterPalm", não nome da loja. |
| 4 | Sem idempotência no envio de email de status; risco de duplicidade. |

---

## 8. MENSAGEM PÓS-COMPRA

### Fluxo WhatsApp

- Após `criarPrePedido` retornar, chama `onSuccess(prePedidoId)`.
- `onSuccess`: `Navigator.pop(context)` (fecha sheet), registra cupom se houver, marca cupom roleta usado.
- Não há dialog "Pedido realizado com sucesso". O sucesso é implícito (WhatsApp abre com a mensagem).

### Fluxo Mercado Pago / PIX

- Redirect para `https://app.mastepalm.com.br/pagamento/sucesso?loja=`.
- `PagamentoResultadoScreen` exibe "Pagamento confirmado!" e "Obrigado pela sua compra! ... Acompanhe seu pedido na aba 'Meus Pedidos' do seu perfil."

### Riscos

| # | Descrição |
|---|-----------|
| 1 | WhatsApp: Se `criarPrePedido` retornar `null` por exceção, `showErr` é chamado e sheet não fecha. Se retornar dados mas o write falhar (raro), usuário vê WhatsApp aberto e pode achar que deu certo. |
| 2 | Mercado Pago: Redirect de sucesso pode ocorrer antes do webhook processar. A mensagem fala em "confirmação por e-mail ou WhatsApp", o que está correto. |
| 3 | Não há número do pedido na mensagem WhatsApp in-app; o número vai na mensagem do WhatsApp. |

---

## 9. PROBLEMAS ENCONTRADOS

### Críticos

| # | Título | Descrição | Arquivo(s) | Função(ões) | Causa | Impacto | Correção recomendada |
|---|--------|-----------|------------|-------------|-------|---------|----------------------|
| 1 | clientes_portal vazio para cliente sem match | Se `_resolvePortalTokenForPedido` não achar cliente em `clientes` (por id ou email), `_saveClientePortalPedidoResumo` retorna sem gravar. "Meus Pedidos" fica vazio. | pre_pedido_service.dart | _resolvePortalTokenForPedido, _saveClientePortalPedidoResumo | Cliente não em clientes ou portalToken ausente | Cliente não vê pedido no perfil | Criar doc em clientes ao criar pre_pedido quando email não existir; garantir portalToken antes de salvar em clientes_portal |
| 2 | posPagamento lojaId hardcoded | `const lojaId = 'masterpalm'` quebra multi-tenant | functions/src/posPagamento.js | processarPosPagamento, buscarPagamentoMercadoPago | Código legado mono-loja | Pós-pagamento MP não funciona para outras lojas | Extrair lojaId do external_reference ou payment metadata |
| 3 | estoque_clientes vs clientes | PrePedidoService grava histórico em estoque_clientes (telefone); perfil usa clientes (clienteId) e clientes_portal | pre_pedido_service.dart | _salvarOuAtualizarCliente, _adicionarPedidoAoHistoricoCliente | Duas modelagens de cliente | Histórico fragmentado; confusão entre admin e catálogo | Unificar: usar clientes como fonte para catálogo; estoque_clientes apenas para sync admin ou migrar |
| 4 | posPagamento usa collection errada | Busca em `collectionGroup('pedidos')`; fluxo catálogo usa `pre_pedidos` | functions/src/posPagamento.js | processarPosPagamento | Schema antigo | Webhook MP não encontra pedido do catálogo | Ajustar para pre_pedidos ou fluxo correto conforme tipo de checkout |

### Altos

| # | Título | Descrição | Arquivo(s) | Causa | Impacto | Correção |
|---|--------|-----------|------------|-------|---------|----------|
| 5 | Total não validado no backend | Total vem do front; não há recálculo server-side | PrePedidoService, carrinho_sheet | Aceita dados do cliente | Risco de fraude de valor | Recalcular total no backend a partir dos itens |
| 6 | portalToken vazio em clientes legados | getDadosCompletos pode retornar null se CF falhar | cliente_auth_service.dart | CF getClienteCatalog indisponível | getPedidosDoCliente retorna vazio, precisaReconectar=true | Backfill portalToken; fallback local para gerar token e persistir |
| 7 | Email admin com remetente fixo | "MasterPalm" em vez do nome da loja | functions/index.js onPrePedidoCreated | Nodemailer from fixo | Branding incorreto | Usar lojaData.nome como remetente |
| 8 | ClienteWebService não integrado | clientes_web e getPedidos em pre_pedidos; catálogo usa ClienteAuthService | cliente_web_service.dart, catalago_screen | Dois sistemas paralelos | Duplicidade, manutenção confusa | Deprecar ClienteWebService ou unificar com ClienteAuthService |

### Médios

| # | Título | Descrição | Impacto | Correção |
|---|--------|-----------|---------|----------|
| 9 | Clique duplo no checkout | Janela entre click e setState | Possível pedido duplicado | Debounce mais rígido; idempotency key no create |
| 10 | Sem transação Firestore | Vários writes independentes | Falha parcial (ex: pre_pedido OK, clientes_portal falha) | Usar batch writes ou transação onde fizer sentido |
| 11 | Email status sem idempotência | Várias chamadas a atualizarStatus | Emails duplicados ao cliente | Flag emailEnviadoPorStatus ou dedup por (pedidoId, status) |
| 12 | Web sem push | Apenas stream de notificacoes | Admin web não recebe alerta com aba minimizada | Web Push (service worker) ou polling mais agressivo |

### Baixos

| # | Título | Descrição | Correção |
|---|--------|-----------|----------|
| 13 | status vs statusPedido | Campos com nomes diferentes em modelos | Padronizar nomenclatura |
| 14 | storeId vs lojaId | Uso misto em notificações e FCM | Padronizar para lojaId |
| 15 | _salvarOuAtualizarCliente exige telefone | Se telefone vazio, não salva em estoque_clientes | Permitir fallback por email ou tornar opcional |

---

## 10. INCONSISTÊNCIAS DE MODELAGEM

| Tipo | Detalhe |
|------|---------|
| Coleções de cliente | `clientes`, `clientes_web`, `clientes_portal`, `clientes_catalogo`, `estoque_clientes` com propósitos e chaves diferentes |
| Chaves de cliente | clienteId (gerado), doc id em clientes_web, portalToken, telefone (estoque_clientes) |
| Status | `status`, `statusPagamento` em pre_pedidos; só `status` em pedido_status_publico |
| Loja | `storeId`, `lojaId`, `store_id` em diferentes contextos |
| Cliente no pedido | `cliente.id`, `clienteId`; objeto `cliente` com `email`, `nome`, etc. |

---

## 11. RISCOS DE DUPLICIDADE / RACE CONDITION / DADOS ÓRFÃOS

| Risco | Onde | Mitigação sugerida |
|-------|------|--------------------|
| Duplicidade por clique duplo | Botão checkout | Idempotency key (ex: hash de itens+cliente+timestamp) ou debounce 500ms+ |
| pre_pedido sem clientes_portal | _resolvePortalTokenForPedido falha | Criar cliente em clientes quando não existir; garantir portalToken |
| Cancelamento: pre_pedido deletado mas espelho antigo | syncPedidoStatusPublico no delete | App já atualiza clientes_portal antes de deletar; CF limpa pedido_status_publico. Ordem pode causar janela de inconsistência |
| Dois clientes mesmo email | clientes e clientes_web | Unificar cadastro ou constraint único por (lojaId, email) |
| Pedido órfão em clientes_portal | Exclusão de pre_pedido sem passar por cancelarPrePedido | CF syncPedidoStatusPublico no delete limpa pedido_status_publico; clientes_portal precisa de trigger equivalente ou job de limpeza |

---

## 12. VEREDITO FINAL

### Confiabilidade do fluxo

- **Criação do pedido**: Relativamente confiável. O write em `pre_pedidos` é direto e a CF de notificação é acionada.
- **"Meus Pedidos"**: **Não confiável** quando o cliente não está corretamente em `clientes` com `portalToken` ou quando a resolução por email falha.
- **Notificação admin**: Confiável se `ownerUid` e `adminEmail` estiverem corretos na loja.
- **Status público**: Confiável via `syncPedidoStatusPublico`, com risco na janela de cancelamento.
- **Pós-pagamento MP**: **Quebrado** para multi-loja (lojaId fixo) e possivelmente schema errado (pedidos vs pre_pedidos).

### Partes sólidas

- Roteamento do catálogo (slug, lojaId).
- ClienteAuthService (cadastro/login) com senha e Google.
- PrePedidoService (criação do pré-pedido e estrutura de dados).
- CF onPrePedidoCreated (notificação, email, FCM).
- CF syncPedidoStatusPublico (espelho para cliente).
- PedidoPublicoScreen (visualização por link).
- NotificacaoPedidoListener (stream em tempo real no app).

### Correções urgentes

1. Garantir preenchimento de `clientes_portal` para todos os pedidos (criar cliente em `clientes` se necessário, garantir portalToken).
2. Corrigir `posPagamento.js` para multi-tenant e coleção correta.
3. Revisar uso de `estoque_clientes` vs `clientes` no fluxo do catálogo.
4. Validar total no backend.
5. Adicionar idempotência no checkout.

---

## 13. PLANO DE CORREÇÃO PRIORIZADO

### Etapa 1: Correções críticas (1–2 sprints)

1. Ajustar `_resolvePortalTokenForPedido` para criar cliente em `clientes` quando email não existir e gerar portalToken.
2. Corrigir `posPagamento.js`: extrair lojaId do external_reference; usar pre_pedidos ou fluxo correto.
3. Garantir `_saveClientePortalPedidoResumo` sempre que houver email (criar doc em clientes com portalToken se preciso).

### Etapa 2: Consistência (1 sprint)

4. Unificar ou documentar clientes vs clientes_web vs estoque_clientes.
5. Padronizar nomenclatura (status, lojaId, clienteId).
6. Recálculo de total no backend.

### Etapa 3: Melhorias estruturais (1–2 sprints)

7. Batch/transação para create de pre_pedido + clientes_portal.
8. Idempotency key no checkout.
9. Deduplicação de emails de status.
10. Remetente de email com nome da loja.

### Etapa 4: Hardening e observabilidade (contínuo)

11. Logs estruturados em CFs (pedidoId, lojaId, clienteId).
12. Métricas de falha em clientes_portal (alertas).
13. Testes automatizados para fluxo crítico.
14. Documentação de arquitetura de clientes e pedidos.

---

## A. TABELA RESUMO DOS PRINCIPAIS ARQUIVOS

| Arquivo | Responsabilidade | Etapa do fluxo | Risco |
|---------|------------------|----------------|-------|
| main.dart | Bootstrap, roteamento catálogo vs app | 1. Entrada | Baixo |
| public_catalog_screen.dart | UI do catálogo, carrinho, checkout | 2–4 | Médio (lógica complexa) |
| carrinho_sheet_web.dart | Formulário checkout, botões MP/WhatsApp | 4 | Médio (clique duplo) |
| login_screen_cliente.dart | Login cliente | 2 | Baixo |
| cadastro_screen_cliente.dart | Cadastro cliente | 2 | Baixo |
| cliente_auth_service.dart | Auth e perfil cliente | 2, 5, 7 | Alto (portalToken, getDadosCompletos) |
| pre_pedido_service.dart | Criação pré-pedido, clientes_portal, estoque_clientes | 5 | Crítico (clientes_portal, estoque_clientes) |
| meus_pedidos_repository.dart | Leitura "Meus Pedidos" | 7 | Médio (depende de clientes_portal) |
| cliente_portal_repository.dart | Acesso clientes_portal | 7 | Médio |
| pedido_status_publico_repository.dart | Leitura status público | 7 | Baixo |
| pedido_publico_screen.dart | Tela pública de status | 7 | Baixo |
| perfil_cliente_screen_novo.dart | Perfil e Meus Pedidos | 7 | Médio |
| notificacao_pedido_listener.dart | Notificação em tempo real | 8 | Baixo |
| fcm_pedido_service.dart | FCM para admin | 8 | Baixo |
| notificacao_vendas_service.dart | Stream de notificações | 8 | Baixo |
| functions/index.js | CFs: onPrePedidoCreated, syncPedidoStatusPublico | 6, 8 | Alto |
| functions/src/posPagamento.js | Webhook MP | Pós-pagamento | Crítico (multi-tenant) |

---

## B. LINHA DO TEMPO DO PEDIDO

```
T0  Cliente clica "Finalizar" (WhatsApp ou MP/PIX)
T1  PrePedidoService.criarPrePedido()
T2  Write pre_pedidos (Firestore)
T3  _saveClientePortalPedidoResumo() — clientes_portal (se portalToken OK)
T4  _salvarOuAtualizarCliente(), _adicionarPedidoAoHistoricoCliente() — estoque_clientes
T5  onPrePedidoCreated (CF) — notificacoes, email admin, FCM
T6  syncPedidoStatusPublico (CF) — pedido_status_publico, upsertClientePortalFromPedido
T7  Cliente: WhatsApp abre / Redirect MP
T8  Admin: SnackBar/notificação (stream ou FCM)
T9  Cliente vê em "Meus Pedidos" (clientes_portal) ou link público (pedido_status_publico)
T10 Admin altera status → syncPedidoStatusPublico → espelhos atualizados
T11 Cliente vê novo status no perfil ou link
```

---

## C. OS 20 PIORES PROBLEMAS (ORDEM DE GRAVIDADE)

1. **clientes_portal vazio** — Pedido não aparece em "Meus Pedidos" (CRÍTICO)
2. **posPagamento lojaId hardcoded** — Pós-pagamento MP quebrado em multi-tenant (CRÍTICO)
3. **estoque_clientes separado de clientes** — Histórico fragmentado (CRÍTICO)
4. **posPagamento usa coleção pedidos** — Webhook não encontra pre_pedidos (CRÍTICO)
5. **Total aceito do frontend** — Sem validação server-side (ALTO)
6. **portalToken vazio** — getPedidosDoCliente falha (ALTO)
7. **Email admin remetente fixo** — Branding incorreto (ALTO)
8. **ClienteWebService vs ClienteAuthService** — Dois fluxos paralelos (ALTO)
9. **Clique duplo no checkout** — Possível pedido duplicado (MÉDIO)
10. **Sem transação** — Falha parcial em writes (MÉDIO)
11. **Email status duplicado** — Múltiplos envios (MÉDIO)
12. **Web sem push** — Admin não alertado com aba minimizada (MÉDIO)
13. **Nomenclatura status/statusPedido** — Inconsistência (BAIXO)
14. **storeId vs lojaId** — Uso misto (BAIXO)
15. **Telefone obrigatório para estoque_clientes** — Bloqueia save (BAIXO)
16. **Cancelamento e ordem de writes** — Janela de inconsistência (BAIXO)
17. **Mensagem sucesso WhatsApp implícita** — Sem confirmação explícita (BAIXO)
18. **Admin sem ownerUid** — Sem notificação (BAIXO)
19. **Cliente sem login** — Não há fluxo visitante (BAIXO)
20. **Dados órfãos em clientes_portal** — Exclusão direta de pre_pedido (BAIXO)

---

*Fim do relatório de auditoria.*
