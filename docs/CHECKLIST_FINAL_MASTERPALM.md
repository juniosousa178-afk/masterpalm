# Checklist final — Estabilização MasterPalm

Checklist prático de testes manuais antes de **build release** e publicação. Foco em validação dos módulos recentes e fluxos críticos, **sem adicionar funcionalidades**.

Complementa: [CHECKLIST_RELEASE.md](CHECKLIST_RELEASE.md) e [VALIDACAO_MOTOR_E_CATALOGO_IA.md](VALIDACAO_MOTOR_E_CATALOGO_IA.md).

---

## 1. Fluxos principais para teste

| Fluxo | Descrição | Rota / Acesso |
|-------|-----------|----------------|
| **Login e loja** | Autenticação, resolução de loja, troca de loja | Login → Home (loja resolvida) |
| **Sync inicial** | FullSync após login (produtos, clientes, vendas, fornecedores) | Automático após login |
| **Motor de Crescimento IA** | Painel de oportunidades (parados, estoque baixo), detalhe, sugestão | Menu → Motor de Crescimento IA |
| **Campanhas sugeridas** | Lista de sugestões de campanha, barra de progresso, ativar campanha | Menu → Campanhas sugeridas |
| **Catálogo público** | Loja pública (produtos, carrinho, checkout), link por slug/lojaId | `/loja`, link público `/loja/{slug}` |
| **IA do catálogo** | Chat no catálogo (se habilitado), perguntas, chips de produtos | FAB no catálogo quando `catalogo_ia_habilitado: true` |
| **Links públicos** | Link do catálogo, link de recuperação `?cart=`, deep link | Configurações → link da loja; WhatsApp com link |
| **Carrinho abandonado (catálogo)** | Lista catálogo, mensagem IA, cupom sugerido, WhatsApp, métricas | Fretes e cupons → Ver carrinhos abandonados |
| **Checkout catálogo** | Carrinho → checkout → pedido (PIX/MP), status recuperado | Catálogo → Carrinho → Finalizar |
| **Vendas (PDV)** | Nova venda, itens, pagamento, sync | Menu → Vendas |
| **Config e loja** | Configuração da loja, pagamentos, link público | Configurações, Fretes e cupons |

---

## 2. Checklist por módulo

### 2.1 Motor de Crescimento IA

- [ ] Abrir tela com loja válida: carrega sem travar.
- [ ] Barra/mensagem de carregamento visível na primeira carga (“Carregando primeiras 30 oportunidades…”).
- [ ] Se houver “carregando mais”: barra e texto “Carregando mais oportunidades…”.
- [ ] Métricas (ticket médio, parados, estoque baixo) coerentes.
- [ ] Lista de oportunidades (parados / estoque baixo) exibida corretamente.
- [ ] “Ver sugestão” abre detalhe; sugestão (textos/cupom) carrega ou fallback aparece.
- [ ] Pull-to-refresh recarrega o painel.
- [ ] Loja vazia ou sem loja: mensagem clara (ex.: “Nenhuma loja ativa”).

### 2.2 Campanhas sugeridas

- [ ] Tela abre e mostra barra de progresso (itens ou %).
- [ ] Mensagem “Pode levar até 1 minuto” visível durante carregamento.
- [ ] Lista de sugestões carrega (ou estado vazio “Tudo em ordem por enquanto”).
- [ ] Ativar campanha: fluxo até resultado (tela de resultado ou erro tratado).
- [ ] Botão atualizar recarrega sugestões.
- [ ] Sem loja: mensagem “Nenhuma loja ativa”.

### 2.3 IA do catálogo

- [ ] Com `catalogo_ia_habilitado: false`: nenhum FAB de chat.
- [ ] Com `catalogo_ia_habilitado: true`: FAB de chat visível no catálogo.
- [ ] Abrir chat: painel abre, mensagem inicial e exemplos.
- [ ] Pergunta (ex.: “mais barato”, “tem X”): resposta com produtos ou mensagem de “não encontrei”.
- [ ] Catálogo vazio: resposta adequada (ex.: “Não encontrei produtos…”).

### 2.4 Loja pública / catálogo

- [ ] Abrir catálogo por link público (`/loja/{slug}` ou lojaId): produtos da loja correta.
- [ ] Lista de produtos, categorias e busca (se houver) funcionam.
- [ ] Adicionar ao carrinho: item entra; carrinho persiste (ex.: ao reabrir com `?cart=ID`).
- [ ] Carrinho abandonado é persistido (Firestore `carrinhos_abandonados`) sem PERMISSION_DENIED.
- [ ] Checkout: fluxo até pedido (PIX/MP conforme config); após sucesso, carrinho limpo e status “recuperado” quando veio de link de recuperação.

### 2.5 Links públicos por loja

- [ ] Link do catálogo (config ou tela) usa slug/lojaId correto; abre no app ou navegador.
- [ ] Link de recuperação `?cart={cartId}`: abre catálogo com carrinho preenchido.
- [ ] Deep link (se aplicável) abre o app na tela esperada.

### 2.6 Carrinho abandonado do catálogo

- [ ] Acesso: Fretes e cupons → Recuperação de carrinho → “Ver carrinhos abandonados”.
- [ ] Seção “Carrinhos do catálogo” lista itens com status (ativo/abandonado).
- [ ] Cupom sugerido exibido; “Copiar cupom” copia para clipboard.
- [ ] “Sugerir com IA”: mensagem sugerida aparece; fallback (mensagem fixa) se IA falhar.
- [ ] “Copiar mensagem” e “WhatsApp” usam a mensagem atual (sugerida ou fixa).
- [ ] Link de recuperação copiado abre catálogo com o carrinho correto.
- [ ] Métricas (Abandonados / Recuperados / Taxa) aparecem quando total > 0 e batem com a lista/status.

### 2.7 Métricas de recuperação

- [ ] Card de métricas (Abandonados: X | Recuperados: Y | Taxa: Z%) visível quando há dados.
- [ ] Números coerentes com os status na coleção (abandonado/recuperado).
- [ ] Atualizar lista (pull/refresh): métricas atualizam após novo carregamento.

### 2.8 Núcleo (regressão rápida)

- [ ] Login e resolução de loja.
- [ ] Sync inicial sem erro (produtos/clientes/vendas).
- [ ] Uma venda completa (PDV): item, pagamento, aparece em vendas.
- [ ] Catálogo público: listar produtos e abrir um produto.
- [ ] Configurações da loja abrem e salvam (ex.: um campo de config).

---

## 3. Riscos e pontos de atenção

| Risco / ponto | Módulo | Mitigação |
|---------------|--------|-----------|
| **App Check 403** (attestation failed) | Firestore / Functions | Em debug: token de debug no Console. Em release: SHA e config corretos. |
| **PERMISSION_DENIED** em `carrinhos_abandonados` | Catálogo | Regras Firestore permitem create/update pelo cliente do catálogo; já ajustado. |
| **Detecção lenta** (40s+) na tela Campanhas | Campanhas sugeridas | Timeout e paralelismo já aplicados; se persistir, verificar Hive/API. |
| **Motor: primeira carga lenta** | Motor | Primeira página limitada (30 itens); resto em background. |
| **IA indisponível** | Motor / Campanhas / Catálogo / Recuperação | Fallbacks locais e mensagens fixas; fluxo não deve quebrar. |
| **Link público com slug errado** | Catálogo | Validar `store_id`/slug na config e Store Resolver; evitar placeholder “minha-loja”. |
| **Métricas de recuperação** | Carrinho abandonado | Contagem por `status`; índice Firestore pode ser necessário (erro no log indica). |
| **Multi-loja** | Geral | Sempre validar `lojaId` em cada tela; não misturar dados entre lojas. |

---

## 4. Ordem ideal de testes

1. **Login e loja** — Garantir sessão e loja correta.
2. **Sync** — Confirmar que dados iniciais carregam.
3. **Catálogo público** — Abertura por link, lista, carrinho e persistência (incl. `?cart=`).
4. **Carrinho abandonado** — Lista, cupom sugerido, mensagem IA, WhatsApp, métricas.
5. **Checkout catálogo** — Pedido completo e, se aplicável, status “recuperado”.
6. **Motor de Crescimento** — Painel, oportunidades, detalhe e sugestão.
7. **Campanhas sugeridas** — Carregamento com progresso, lista e ativar uma campanha.
8. **IA do catálogo** — Se habilitada: chat, perguntas e respostas.
9. **Links públicos** — Copiar link, abrir em outro dispositivo/navegador, link de recuperação.
10. **Vendas (PDV)** — Uma venda de ponta a ponta (regressão).
11. **Config** — Acesso e salvamento de pelo menos uma config.

---

## 5. Antes do build release

- [ ] `flutter analyze` sem erros (ou só avisos conhecidos).
- [ ] Versão e build number no `pubspec.yaml` corretos.
- [ ] Testes críticos acima marcados conforme executados.
- [ ] App Check e Firestore: sem erro novo em uso normal (1–2 min).
- [ ] Referência: [CHECKLIST_RELEASE.md](CHECKLIST_RELEASE.md).

---

*Marque os itens conforme for testando. Corrija falhas antes de publicar. Este documento é apenas para estabilização e validação final; não descreve novas funcionalidades.*
