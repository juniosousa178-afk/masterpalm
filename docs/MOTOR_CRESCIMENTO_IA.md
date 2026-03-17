# Motor de Crescimento IA — Especificação do Módulo

Sistema de inteligência que analisa dados da loja, detecta oportunidades e sugere (e executa) campanhas para ajudar lojistas a vender mais automaticamente.

---

## 1. Arquitetura do Módulo

### 1.1 Visão geral

O módulo é organizado em **camadas** que reutilizam dados e serviços existentes do MasterPalm:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        PAINEL DO LOJISTA (UI)                            │
│  MotorCrescimentoScreen │ OportunidadeDetailScreen │ CampanhaCriadaScreen │
└─────────────────────────────────────────────────────────────────────────┘
                                      │
┌─────────────────────────────────────────────────────────────────────────┐
│                     CAMADA DE ORQUESTRAÇÃO                                │
│  MotorCrescimentoOrchestrator (agrega detecção + sugestões + ações)       │
└─────────────────────────────────────────────────────────────────────────┘
                                      │
        ┌─────────────────────────────┼─────────────────────────────┐
        ▼                             ▼                             ▼
┌───────────────┐           ┌─────────────────┐           ┌─────────────────┐
│  DETECÇÃO     │           │  SUGESTÕES       │           │  EXECUÇÃO       │
│  Oportunidades│           │  Campanhas       │           │  Campanhas      │
│  (Etapa 1–2)  │           │  (Etapa 2–3)     │           │  (Etapa 4)      │
└───────────────┘           └─────────────────┘           └─────────────────┘
        │                             │                             │
        ▼                             ▼                             ▼
┌───────────────┐           ┌─────────────────┐           ┌─────────────────┐
│  MotorCrescimento│         │  MotorCrescimento│           │  MotorCrescimento│
│  DetectorService │         │  SugestorService  │           │  ExecutorService │
└───────────────┘           └─────────────────┘           └─────────────────┘
        │                             │                             │
        └─────────────────────────────┼─────────────────────────────┘
                                      ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  DADOS EXISTENTES (Hive + Firestore)                                      │
│  Vendas, Produtos, Clientes, Cupons, DashboardInsights, AiLojaService     │
└─────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Princípios

- **Reuso:** Usar `DashboardInsightsService` para produto parado/estoque baixo; `AiLojaService` para textos; `CupomDescontoService` para cupons; Hive boxes `vendas_*`, `produtos_*`, `clientes_*`.
- **Incremental:** Implementação em 4 etapas (detecção → sugestão → textos → execução).
- **Consentimento:** Campanhas automáticas só são executadas após confirmação do lojista (ou regra explícita de “executar automaticamente”).
- **Rastreabilidade:** Todas as oportunidades e campanhas geradas ficam em Firestore para histórico e métricas.

### 1.3 Pacote sugerido

```
lib/
  motor_crescimento/
    models/
      oportunidade_crescimento.dart   # Oportunidade detectada
      sugestao_campanha.dart         # Sugestão de campanha (promoção, combo, etc.)
      campanha_motor.dart            # Campanha criada/executada pelo motor
    services/
      motor_crescimento_detector_service.dart   # Etapa 1–2: detecção
      motor_crescimento_sugestor_service.dart   # Etapa 2–3: sugestões + textos
      motor_crescimento_executor_service.dart   # Etapa 4: executar campanha
      motor_crescimento_orchestrator.dart      # Orquestrador único para a tela
    screens/
      motor_crescimento_screen.dart            # Painel principal
      oportunidade_detail_screen.dart          # Detalhe + "Criar campanha?"
      campanha_motor_result_screen.dart       # Resultado (cupom criado, link, etc.)
```

---

## 2. Serviços necessários

### 2.1 MotorCrescimentoDetectorService (Etapa 1 e base da 2)

**Responsabilidade:** Ler Hive/Firestore e produzir lista de **oportunidades** (eventos acionáveis).

| Método | Descrição | Dados usados |
|--------|-----------|--------------|
| `detectarOportunidades(lojaId)` | Retorna `List<OportunidadeCrescimento>` | Vendas, Produtos, (Clientes Firestore se houver) |
| `_produtosParados(lojaId, dias)` | Produtos sem venda em X dias | `DashboardInsightsService` + produtos Hive |
| `_estoqueBaixo(lojaId)` | Produtos com quantidade ≤ mínimo | Produtos Hive `isEstoqueBaixo` |
| `_quedaVendas(lojaId, periodoAtual, periodoAnterior)` | Queda % entre dois períodos | Vendas Hive agregadas por mês/semana |
| `_altoGiro(lojaId, topN)` | Top N produtos por quantidade vendida | Vendas Hive (mês atual) |
| `_clientesInativos(lojaId, dias)` | Clientes sem compra em X dias | Vendas Hive por `clienteNome`/`clienteId` + última data |
| `_ticketMedio(lojaId, periodo)` | Ticket médio do período | Vendas Hive |

**Saída:** Objetos `OportunidadeCrescimento` com: tipo (estoqueParado, estoqueBaixo, quedaVendas, altoGiro, clienteInativo), entidade (produto/cliente), métricas (dias, quantidade, %), prioridade sugerida.

### 2.2 MotorCrescimentoSugestorService (Etapa 2 e 3)

**Responsabilidade:** A partir de uma oportunidade, sugerir **tipo de campanha** e depois **textos** (promoção, WhatsApp, Instagram, cupom).

| Método | Descrição | Dados usados |
|--------|-----------|--------------|
| `sugerirCampanhaPara(oportunidade)` | Retorna `SugestaoCampanha` (tipo: promocao, combo, desconto, sazonal) | Oportunidade + regras fixas |
| `gerarTextoPromocao(produtoNome, tipoCampanha)` | Texto curto para banner/catálogo | `AiLojaService` (nova call ou `sugerirMensagemWhatsApp(tipo: 'promocao')`) |
| `gerarLegendaInstagram(produtoNome, contexto)` | Legenda para post | `AiLojaService.sugerirLegendaInstagram` |
| `gerarMensagemWhatsApp(produtoNome, tipo)` | Mensagem para envio | `AiLojaService.sugerirMensagemWhatsApp(tipo: 'promocao', contexto: produtoNome)` |
| `gerarCodigoCupomSugerido(lojaId)` | Código único sugerido (ex: PARADO15) | CupomDescontoService / verificação de código |

**Limites IA:** Usar `IaUsoLimiteService` para não exceder cotas por loja.

### 2.3 MotorCrescimentoExecutorService (Etapa 4)

**Responsabilidade:** Executar a campanha após aprovação do lojista: criar cupom, gerar link, (futuro) enviar WhatsApp / postar no catálogo.

| Método | Descrição | Dados usados |
|--------|-----------|--------------|
| `criarCupomParaCampanha(lojaId, sugestao, produtoIds?)` | Cria cupom no Firestore | `CupomDescontoService.criarCupom` |
| `gerarLinkPromocao(lojaId, slugLoja, codigoCupom)` | Link catálogo + cupom (query) | `AppUrls.appWebBase` + `/loja/{slug}?cupom=XXX` |
| `abrirWhatsAppComMensagem(telefone, mensagem)` | Abre wa.me com texto (igual carrinho abandonado) | `url_launcher` |
| `marcarProdutoEmPromocao(lojaId, produtoId/slug, percentual, dataFim)` | Atualiza produto em promoção | Produto Hive + Firestore (emPromocao, percentualPromo, dataFimPromo) |
| `registrarCampanhaExecutada(lojaId, campanha)` | Salva em `motor_campanhas` para histórico | Firestore |

### 2.4 MotorCrescimentoOrchestrator

**Responsabilidade:** API única para a tela: carregar oportunidades, ao clicar em uma oportunidade obter sugestão + textos, ao confirmar executar e retornar resultado.

| Método | Descrição |
|--------|-----------|
| `carregarPainel(lojaId)` | Lista oportunidades + resumo (ticket médio, total parados, etc.) |
| `obterSugestaoPara(oportunidade)` | Retorna sugestão de campanha + textos gerados (com cache opcional) |
| `executarCampanha(lojaId, sugestao, opcoes)` | Cria cupom / link / marca promoção e retorna `CampanhaMotorResult` |

### 2.5 Dependências existentes

- `DashboardInsightsService` — produto parado, estoque baixo, mais vendidos.
- `AiLojaService` — sugerirMensagemWhatsApp, sugerirLegendaInstagram, sugerirDescricao/sugerirTitulo (para variações).
- `IaUsoLimiteService` — limites de uso de IA por loja.
- `CupomDescontoService` — criar cupom.
- `HiveBoxNames` + boxes de vendas, produtos (clientes no Hive se existir; senão derivar inativos das vendas).
- `StoreContext` / `StoreResolverFacade` — lojaId atual.

---

## 3. Telas necessárias

### 3.1 MotorCrescimentoScreen (Painel principal)

- **Rota:** `/motor-crescimento` ou acessível pela Home (card “Motor de Crescimento IA”).
- **Conteúdo:**
  - Bloco de **métricas rápidas:** ticket médio (período), nº de produtos parados, nº de clientes inativos, alertas de estoque baixo.
  - Lista de **oportunidades** agrupadas por tipo (Estoque parado, Queda de vendas, Clientes inativos, etc.), cada item com:
    - Título (ex.: “Produto X parado há 30 dias”).
    - Subtitle com métrica (ex.: “5 produtos parados”).
    - Botão “Ver sugestão” / “Criar campanha”.
  - Filtros opcionais: tipo de oportunidade, prioridade.
- **Fluxo:** Toque em uma oportunidade → navega para `OportunidadeDetailScreen` passando a oportunidade.

### 3.2 OportunidadeDetailScreen (Detalhe + “Deseja criar uma campanha?”)

- **Entrada:** `OportunidadeCrescimento` (e lojaId).
- **Conteúdo:**
  - Resumo da oportunidade (produto/cliente, métrica, dias, etc.).
  - **Sugestão de campanha:** tipo (promoção, combo, desconto, sazonal), descrição curta.
  - **Conteúdos gerados (Etapa 3):** texto promoção, legenda Instagram, mensagem WhatsApp (com botão copiar); código de cupom sugerido; valor/percentual sugerido.
  - Ações: “Criar cupom e gerar link”, “Apenas copiar textos”, “Marcar produto em promoção no catálogo”.
  - Checkbox opcional: “Enviar WhatsApp para clientes inativos” (lista de clientes ou segmento) — Etapa 4.
- **Fluxo:** Ao confirmar “Criar campanha” → chama `ExecutorService` → navega para `CampanhaMotorResultScreen` com resultado.

### 3.3 CampanhaMotorResultScreen (Resultado)

- **Entrada:** `CampanhaMotorResult` (cupom criado, link de promoção, textos usados, produto marcado em promoção, etc.).
- **Conteúdo:**
  - Mensagem de sucesso.
  - Código do cupom e link de promoção (compartilhar / copiar).
  - Botão “Abrir WhatsApp com mensagem” (se aplicável).
  - Link para catálogo com `?cupom=XXX`.
- **Navegação:** Voltar ao painel ou à lista de vendas/cupons.

### 3.4 Integração na Home

- Card ou item de menu “Motor de Crescimento IA” que leva a `MotorCrescimentoScreen`, opcionalmente com badge com número de oportunidades ativas.

---

## 4. Estrutura de banco de dados

### 4.1 Firestore (novas coleções)

Todas sob `lojas/{lojaId}/`.

| Coleção | Documento | Campos principais | Uso |
|---------|-----------|-------------------|-----|
| `motor_oportunidades` | `{oportunidadeId}` (auto) | tipo, entidadeTipo, entidadeId, entidadeNome, metricas (dias, qtd, percentual), prioridade, criadoEm, processado (bool), campanhaId (ref) | Cache de oportunidades detectadas (opcional; pode ser só em memória na Etapa 1) |
| `motor_campanhas` | `{campanhaId}` (auto) | oportunidadeId, tipoCampanha, codigoCupom, cupomId, linkPromocao, produtoIds, textoPromocao, mensagemWhatsApp, legendaInstagram, criadoEm, criadoPor (uid), status (rascunho/ativa/enviada) | Histórico de campanhas geradas pelo motor |
| `motor_config` | `config` (fixo) | ativo (bool), diasProdutoParado (int), diasClienteInativo (int), executarWhatsAppAutomatico (bool), notificarOportunidades (bool) | Configuração do módulo por loja |

### 4.2 Reuso de estruturas existentes

- **Cupons:** `lojas/{lojaId}/cupons` — criados por `CupomDescontoService`; o motor apenas chama `criarCupom` com os parâmetros da sugestão.
- **Produtos (promoção):** Campos já existentes em `Produto`: `emPromocao`, `percentualPromo`, `valorPromo`, `dataInicioPromo`, `dataFimPromo`. Atualização via Hive + sync Firestore (produtos publicados).
- **Vendas/Produtos/Clientes:** Apenas leitura; boxes Hive e coleções Firestore já existentes.

### 4.3 Modelos Dart (novos)

- **OportunidadeCrescimento:** tipo (enum), entidadeTipo (produto/cliente/loja), entidadeId, entidadeNome, metricas (Map), prioridade (int ou enum), dadosExtras (Map).
- **SugestaoCampanha:** tipo (promocao, combo, desconto, sazonal), titulo, descricao, codigoCupomSugerido, valorDesconto ou percentual, textoPromocao, mensagemWhatsApp, legendaInstagram, produtoIds (opcional), validadeDias.
- **CampanhaMotor:** id, lojaId, oportunidadeId, sugestao, cupomId, codigoCupom, linkPromocao, status, criadoEm, criadoPor.
- **CampanhaMotorResult:** sucesso, codigoCupom, linkPromocao, mensagemWhatsApp, produtoMarcadoEmPromocao (bool), erro (String?).

---

## 5. Fluxo de funcionamento

### 5.1 Fluxo geral (todas as etapas)

1. Lojista abre **Motor de Crescimento IA** (painel).
2. **Orchestrator** chama **Detector**: lê Hive (vendas, produtos) e opcionalmente Firestore (clientes); gera lista de **OportunidadeCrescimento** (estoque parado, estoque baixo, queda vendas, alto giro, clientes inativos).
3. Painel exibe oportunidades agrupadas; opcionalmente usa `motor_oportunidades` para cache/histórico.
4. Lojista toca em uma oportunidade (ex.: “Produto X parado há 30 dias”).
5. **Sugestor** gera **SugestaoCampanha** (tipo promoção/desconto) e, com **AiLojaService**, gera textos (promoção, WhatsApp, Instagram) e código de cupom sugerido.
6. Tela de detalhe mostra: “O sistema detectou que o produto X está parado há 30 dias. Deseja criar uma campanha?” + sugestão + textos.
7. Lojista confirma (e pode editar textos/cupom).
8. **Executor** cria cupom (`CupomDescontoService`), gera link (`/loja/{slug}?cupom=XXX`), opcionalmente marca produto em promoção no catálogo; salva em `motor_campanhas`; (futuro) envia WhatsApp.
9. Tela de resultado mostra link, cupom e opção “Abrir WhatsApp com mensagem”.

### 5.2 Fluxo por etapa de implementação

**Etapa 1 — Detecção de estoque parado (e estoque baixo)**  
- Detector usa lógica análoga a `DashboardInsightsService`: produtos da loja que não aparecem em vendas dos últimos N dias; produtos com `isEstoqueBaixo`.  
- Painel lista apenas “Produtos parados” e “Estoque baixo” com contagem e primeiro item; ao tocar, detalhe mostra lista de produtos (sem sugestão de campanha ainda, se quiser entregar só Etapa 1).

**Etapa 2 — Sugestão de promoções**  
- Para cada oportunidade (ex.: produto parado), Sugestor define tipo (promoção com X% de desconto) e parâmetros (código cupom, validade).  
- Detalhe mostra: “Deseja criar uma campanha? Sugestão: desconto de 15% com cupom PARADO15.”

**Etapa 3 — Geração automática de textos**  
- Sugestor chama AiLojaService para: texto de promoção, mensagem WhatsApp, legenda Instagram; exibe na tela de detalhe com “Copiar”.

**Etapa 4 — Automação de campanhas**  
- Executor implementa: criar cupom, gerar link, marcar produto em promoção, registrar campanha; opção “Abrir WhatsApp com mensagem”.  
- (Futuro) Envio automático via API WhatsApp para lista de clientes inativos ou que compraram a categoria.

---

## 6. Lista de funcionalidades

### 6.1 Detecção (Etapa 1)

| Funcionalidade | Descrição | Prioridade |
|----------------|-----------|------------|
| Produtos parados | Listar produtos sem venda nos últimos N dias (ex.: 25) | P0 |
| Estoque baixo | Listar produtos com quantidade ≤ estoque mínimo | P0 |
| Queda de vendas | Comparar período atual vs anterior; sinalizar queda % | P1 |
| Produtos alto giro | Top N produtos mais vendidos no período | P1 |
| Clientes inativos | Clientes sem compra em N dias (derivado de vendas) | P1 |
| Ticket médio | Cálculo e exibição no painel | P1 |

### 6.2 Sugestões (Etapa 2)

| Funcionalidade | Descrição | Prioridade |
|----------------|-----------|------------|
| Sugestão para produto parado | Campanha de desconto (ex.: 10–20%) ou combo | P0 |
| Sugestão para estoque baixo | Alerta de recompra (não necessariamente campanha de venda) | P1 |
| Sugestão para clientes inativos | Campanha “sentimos sua falta” + cupom | P1 |
| Sugestão sazonal | Datas fixas (Black Friday, Natal) ou por configuração | P2 |
| Combos sugeridos | Produto parado + produto alto giro (combo kit) | P2 |

### 6.3 Conteúdo automático (Etapa 3)

| Funcionalidade | Descrição | Prioridade |
|----------------|-----------|------------|
| Texto de promoção | Frase curta para banner/catálogo (IA) | P0 |
| Mensagem WhatsApp | Texto para envio com link da promoção (IA) | P0 |
| Legenda Instagram | Legenda para post (IA) | P1 |
| Código de cupom sugerido | Gerar código único (ex.: PARADO15, VOLTE10) | P0 |

### 6.4 Execução (Etapa 4)

| Funcionalidade | Descrição | Prioridade |
|----------------|-----------|------------|
| Criar cupom | Chamar CupomDescontoService com parâmetros da sugestão | P0 |
| Gerar link de promoção | URL catálogo + query cupom | P0 |
| Marcar produto em promoção | Atualizar produto (emPromocao, percentual, data fim) | P1 |
| Abrir WhatsApp com mensagem | wa.me com texto pré-preenchido | P0 |
| Registrar campanha executada | Salvar em `motor_campanhas` | P0 |
| (Futuro) Enviar WhatsApp em massa | API WhatsApp para segmento (clientes inativos) | P2 |
| (Futuro) Destaque no catálogo | Banner ou tag “Promoção” na home do catálogo | P2 |

### 6.5 Painel e UX

| Funcionalidade | Descrição | Prioridade |
|----------------|-----------|------------|
| Painel de oportunidades | Lista agrupada por tipo com métricas | P0 |
| Detalhe da oportunidade | Tela “Deseja criar uma campanha?” com sugestão | P0 |
| Resultado da campanha | Tela com cupom, link e compartilhar | P0 |
| Card na Home | Acesso ao Motor de Crescimento + badge de oportunidades | P1 |
| Configuração do motor | Dias para “parado”, “inativo”, ativar/desativar notificações | P2 |

---

## 7. Resumo das etapas de implementação

| Etapa | Foco | Entregas |
|-------|------|----------|
| **1** | Detecção de estoque parado | Detector (produtos parados + estoque baixo), painel listando oportunidades, tela de detalhe só informativa |
| **2** | Sugestão de promoções | Sugestor (tipo de campanha + parâmetros), exibir sugestão na tela “Deseja criar uma campanha?” |
| **3** | Geração automática de textos | Chamadas AiLojaService (promoção, WhatsApp, Instagram), exibir e copiar na tela de detalhe |
| **4** | Automação de campanhas | Executor (criar cupom, link, marcar promoção, registrar), tela de resultado, “Abrir WhatsApp” |

Este documento serve como referência para implementação incremental do módulo **Motor de Crescimento IA** dentro do MasterPalm.
