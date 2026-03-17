# Plano de melhorias sem quebrar nada

Objetivo: resolver os quatro pontos que puxam a nota do app para baixo (**código gigante**, **poucos testes**, **arquitetura dispersa**, **custo Firestore**) de forma **incremental e segura**, sem refatorar tudo de uma vez.

---

## 1. Código: reduzir arquivos gigantes

### 1.1 `main.dart` (~1.500 linhas)

**Problema:** Bootstrap, rotas, widgets de boot e MyApp no mesmo arquivo; difícil manter e testar.

**Abordagem:** Extrair em **etapas**, uma por vez, rodando o app após cada mudança.

| Passo | Ação | Resultado |
|-------|------|-----------|
| 1 | Criar `lib/app_routes.dart`: mover só a função `onGenerateRoute` (e o mapa de rotas que ela usa) de `main.dart` para esse arquivo. Em `main.dart` importar e chamar `AppRoutes.onGenerateRoute`. | main.dart perde ~200–400 linhas; rotas ficam em um lugar só. |
| 2 | Criar `lib/bootstrap_app.dart` (ou `lib/startup/bootstrap.dart`): mover `_bootstrapSafe`, `_ensureStoreIdOnBootstrap`, `_fixPedidoLinkBase` e funções auxiliares de init (ex.: `initFirebaseAppCheck`, `initFirebaseMonitoring`) para esse arquivo. `main()` continua em main.dart mas chama `BootstrapApp.run()`. | main.dart fica com main(), init core, e MyApp; ~500–800 linhas a menos. |
| 3 | Opcional: mover `CatalogWebRoot`, `MpOAuthResultPage`, `_BootApp`, `_BootError` para `lib/screens/` ou `lib/startup/` com nomes claros. | main.dart enxuto (< 300 linhas). |

**Regra:** Não mudar lógica; só cortar e colar em novos arquivos e ajustar imports. Testar: login, abrir uma rota do app, abrir catálogo web.

---

### 1.2 `loja_config_screen.dart` (~5.400 linhas)

**Problema:** Uma tela com muitos panes (identidade, mídias, tema, layout, menu, rodapé, financeiro, publicar); tudo no mesmo State, difícil de navegar e testar.

**Abordagem:** Extrair **um pane por vez** como widget em arquivo separado. O State de `LojaConfigScreen` continua dono dos dados; os novos widgets recebem callbacks e valores.

| Passo | Ação | Resultado |
|-------|------|-----------|
| 1 | Criar `lib/screens/loja_config/loja_config_pane_identidade.dart`: extrair o conteúdo de `_paneIdentidade()` para um widget `LojaConfigPaneIdentidade` que recebe os controllers, `lojaId`, callbacks (ex.: onSave, onSlugChanged). O State chama `LojaConfigPaneIdentidade(...)` no switch de panes. | ~400–800 linhas saem de loja_config_screen. |
| 2 | Repetir para os outros panes: `LojaConfigPaneMidias`, `LojaConfigPaneTema`, `LojaConfigPaneLayout`, `LojaConfigPaneMenu`, `LojaConfigPaneRodape`, `LojaConfigPaneFinanceiro`, `LojaConfigPanePublicar`. Um arquivo por pane, um pane por vez. | Cada pane vira um arquivo de 200–600 linhas; loja_config_screen fica com estado, navegação e composição (~800–1.200 linhas). |
| 3 | Manter enums e dados compartilhados: pode ficar em `loja_config_screen.dart` ou em `lib/screens/loja_config/loja_config_shared.dart` (ex.: `_Pane`, cores, textos comuns). | Sem quebrar comportamento. |

**Regra:** Não alterar fluxo de salvamento nem validação; só mover UI e passar dados por parâmetro/callback. Após cada pane extraído: abrir a tela, editar cada aba e salvar para garantir que nada quebrou.

---

## 2. Testes: aumentar cobertura de forma incremental

**Problema:** Apenas 4 arquivos de teste; lógica crítica (sync, planos, limites) quase sem amparo.

**Regra geral:** Não escrever testes para “tudo”. **Só para código que você for mexer** ou para **funções críticas puras** (fáceis de testar e estáveis).

| Prioridade | O quê | Onde | Casos sugeridos |
|------------|-------|------|------------------|
| 1 | Limites por plano (já é lógica pura) | `test/limits_guard_test.dart` ou `test/subscription_limits_test.dart` | Para um `planId` (ex.: free_limited), verificar que `_limitsForPlan` retorna maxProducts=10, maxClients=20, vendasMes=10, maxImagesPerProduct=1, maxBanners=1; trial 80/150/50/3/6; paid altos. |
| 2 | SubscriptionService (constantes de limites) | `test/subscription_service_test.dart` | Testar que `trialLimits`, `freeLimitedLimits`, `paidLimits` têm as chaves esperadas e valores numéricos corretos. |
| 3 | PlanosService – migração trial → free_limited | `test/planos_service_test.dart` | Mock Firestore; quando trial expirado, `migrateTrialToFreeLimited` atualiza users/{uid} com planId free_limited e campos esperados. |
| 4 | SyncQueueService (opcional, mais complexo) | Manter ou adicionar 1–2 testes | Ex.: enfileirar uma operação e verificar que o tipo e o payload estão corretos; não precisa testar Firestore. |

**Quando adicionar testes:**  
- Ao criar **novo** serviço que faz contas ou validações (ex.: novo cálculo de comissão, novo limite), criar `test/nome_servico_test.dart` com 3–5 casos.  
- Ao **alterar** LimitsGuard, PlanosService ou SubscriptionService, adicionar ou ajustar o teste correspondente.

**O que não fazer:** Reescrever o app para testar; não testar telas inteiras por enquanto; não exigir 80% de cobertura de uma vez.

---

## 3. Arquitetura: unificar “loja” e manter licença documentada

### 3.1 Várias fontes de “loja” (sessão, config, StoreResolver)

**Problema:** Vários lugares leem `sessao.get('store_id')`, `config`, ou chamam StoreResolver; risco de loja errada ou inconsistência.

**Abordagem:** Não reescrever tudo. **Definir uma única fonte da verdade** e ir migrando **um arquivo por vez**.

| Passo | Ação | Resultado |
|-------|------|-----------|
| 1 | Documentar em `docs/PONTOS_SENSIVEIS.md`: “Fonte da verdade para lojaId do usuário logado: `StoreResolverService.resolve()` (ou o método que retorna loja atual). Ao precisar de lojaId em tela ou serviço, preferir esse método em vez de ler Hive/sessão direto.” | Todos (e você no futuro) sabem onde buscar loja. |
| 2 | Listar em um doc (ou seção em PONTOS_SENSIVEIS) os arquivos que ainda leem `sessao.get('store_id')` ou `config.get('store_id')` para decidir fluxo. Ex.: `grep -r "sessao.get.*store" lib --include="*.dart"`. | Lista concreta para migrar. |
| 3 | Por vez: escolher **uma** tela ou serviço da lista, trocar a leitura direta de sessão/config por uma chamada a `StoreResolverService` (ou LojaIdService se for o que o app usar). Testar login, troca de loja (se houver), e essa tela. | Redução gradual de fontes de loja. |
| 4 | Não remover fallbacks de uma vez; onde ainda precisar de “última loja conhecida” offline, manter Hive como cache mas preencher esse cache a partir do StoreResolver quando online. | Evita quebra em offline. |

**Regra:** Uma migração por PR/sessão; sempre testar fluxo de login e a tela alterada.

### 3.2 Dois caminhos de licença (legado + novo)

**Abordagem:** Não unificar agora. Manter os dois caminhos e **documentar** para não quebrar ao mexer.

| Ação | Onde |
|------|------|
| Manter `docs/PLANOS_E_LICENCA.md` atualizado com: (1) plano novo = Firestore users/{uid}, subscriptions, PlanosService; (2) legado = Hive `licenca`, LicenseManager; (3) ordem de decisão (ex.: hasValidAccessFallbackLegacy). | PLANOS_E_LICENCA.md |
| Ao alterar tela de “plano” ou “licença”, consultar esse doc e testar ambos os fluxos (usuário com plano Firestore e usuário com código legado, se ainda existir). | Processo |

Remover legado só quando não houver mais ninguém usando (ex.: após migração em produção e aviso aos usuários).

---

## 4. Custo Firestore: limits e “carregar mais”

**Problema:** Listeners e queries sem `.limit()` ou com limite alto demais aumentam leituras; custo sobe com escala.

**Abordagem:** Adicionar `.limit(N)` onde fizer sentido e, em listas longas, implementar “carregar mais” (próxima página) para não quebrar UX. Fazer **um ponto por vez** e testar.

| Onde | Ação sugerida | Cuidado |
|------|----------------|---------|
| **Catálogo público** – listener de produtos | Reduzir de 1000 para ex.: 200 ou 300; implementar “Carregar mais produtos” (próxima página com startAfterDocument). | Garantir que a lista não “corta” no meio sem opção de carregar mais. |
| **Catálogo público** – cupons fallback | Adicionar `.limit(50)` na query `collection('cupons').where('ativo', true).get()`. | 50 cupons ativos por loja costuma ser suficiente. |
| **FirestoreCriticalListenerService** – estoque_produtos | Aqui é delicado: esse listener sincroniza **toda** a coleção para Hive. Opções: (A) Adicionar `.limit(500)` e documentar que lojas com >500 produtos terão só os 500 primeiros em tempo real (e o resto no FullSync); (B) Deixar como está mas garantir que o listener só inicia quando a tela de vendas/estoque abre e é cancelado no dispose (evitar listener 24/7). Preferir (B) se já for o caso; senão, implementar cancel no dispose. | Não quebrar sync para lojas grandes. |
| **Campanha participantes** | Adicionar `.limit(100)` (ou 200) no stream de participantes e “Carregar mais” na tela. | Listagem de participantes não some. |
| **Tela Plano (admin)** – `collection('usuarios').get()` | Adicionar `.limit(500)` e “Carregar mais” ou paginação. | Admin consegue ver lista de usuários. |
| **Pedido público** – fallback produtos | Quando buscar produtos por fallback, usar `.limit(200)` ou buscar por IDs específicos quando possível. | Não travar tela de pedido. |

**Ordem sugerida:**  
1) Cupons (limit 50) – rápido.  
2) Catálogo público produtos (limit 200 + carregar mais).  
3) Campanha participantes (limit 100 + carregar mais).  
4) Tela plano admin (limit 500 + carregar mais).  
5) Pedido público fallback (limit 200).  
6) CriticalListener: apenas garantir cancel no dispose; limit opcional depois.

Documentar em `docs/CUSTO_FIREBASE.md` cada alteração feita (ex.: “Catálogo público produtos: limit 200 + carregar mais em DD/MM/AAAA”).

---

## Ordem geral sugerida (sem quebrar nada)

| Ordem | Área | Ação | Esforço | Status |
|-------|------|------|---------|--------|
| 1 | Custo | Cupons catálogo: `.limit(50)` em `public_catalog_screen.dart` | Baixo | ✅ Feito |
| 2 | Testes | Criar `test/subscription_service_test.dart` (limites trial, free_limited, paid) | Baixo | ✅ Feito |
| 3 | Código | Extrair `onGenerateRoute` para `lib/app_routes.dart` | Baixo | ✅ Feito |
| 4 | Arquitetura | Atualizar PONTOS_SENSIVEIS com “fonte da verdade = StoreResolver” e lista de arquivos que leem sessão/store_id | Baixo |
| 5 | Custo | Catálogo público produtos: limit 200 + carregar mais | Médio |
| 6 | Código | Extrair bootstrap para `bootstrap_app.dart` | Médio |
| 7 | Código | Extrair primeiro pane de loja_config (identidade) para `LojaConfigPaneIdentidade` | Médio |
| 8 | Testes | PlanosService: teste de migração trial → free_limited | Médio |
| 9 | Custo | Campanha participantes e tela plano admin: limit + carregar mais | Médio |
| 10 | Arquitetura | Migrar 1–2 telas/serviços para usar só StoreResolver para lojaId | Contínuo |

---

## Resumo

- **Código:** Extrair rotas e bootstrap do main; quebrar loja_config por pane em widgets em arquivos separados. Sem mudar lógica.
- **Testes:** Incrementais: limites (Subscription/LimitsGuard), PlanosService (migração), e ao tocar em serviço crítico.
- **Arquitetura:** Fonte da verdade = StoreResolver; migrar leituras de loja um arquivo por vez; licença em dois caminhos documentados, sem remover legado.
- **Custo:** Limits em queries e listeners; “carregar mais” onde a lista for longa; CriticalListener só ativo quando a tela precisar e cancel no dispose.

Tudo pode ser feito **sem quebrar nada**, em passos pequenos e testáveis.
