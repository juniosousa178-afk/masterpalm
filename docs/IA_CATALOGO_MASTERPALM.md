# IA do Catálogo Online — Especificação do Módulo MasterPalm

Sistema de IA no catálogo público que ajuda o **cliente final** a encontrar produtos, tirar dúvidas e aumentar a conversão da loja.

**Importante:** Este módulo é **separado** do Motor de Crescimento IA. O Motor de Crescimento ajuda o **lojista**. A IA do catálogo ajuda o **cliente**.

---

## 1. ARQUITETURA DO MÓDULO

### 1.1 Visão geral

O módulo é uma **camada opcional** em cima do catálogo público existente. Não altera regras de negócio, sync, Store Resolver, permissões ou núcleo transacional.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     CATÁLOGO PÚBLICO (existente)                              │
│  PublicCatalogScreen │ CatalogCacheService │ config + produtos │ checkout    │
└─────────────────────────────────────────────────────────────────────────────┘
                                        │
                    ┌───────────────────┴───────────────────┐
                    │  FALLBACK SEM IA (sempre disponível)   │
                    │  Busca por texto + lista de produtos   │
                    └───────────────────┴───────────────────┘
                                        │
┌─────────────────────────────────────────────────────────────────────────────┐
│                     MÓDULO IA CATÁLOGO (novo, opcional)                       │
│  ┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐  │
│  │  Dados do catálogo  │  │  Serviço de IA      │  │  UI Chat / sugestões │  │
│  │  (somente leitura)  │  │  (busca + respostas) │  │  (widget no catálogo)│  │
│  └─────────────────────┘  └─────────────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Princípios

- **Somente leitura sobre o catálogo:** A IA consome produtos e config já carregados (ex.: via `CatalogCacheService` ou lista em memória). Não escreve em Firestore/Hive do núcleo.
- **Modular:** Um pacote dedicado (`lib/ia_catalogo/` ou `lib/screens/public_catalog/ia/`) com serviços e widgets isolados.
- **Fallback obrigatório:** Se a IA estiver desligada ou falhar, o catálogo continua funcionando com busca simples (filtro por nome/categoria) e sem chat.
- **Reuso:** Usar `CatalogCacheService`, config da loja (WhatsApp, cupons, fretes), lista de produtos já processada pelo `PublicCatalogScreen`, e helpers existentes (`catalog_helpers`, `PrePedidoService` para mensagem WhatsApp).

### 1.3 O que NÃO é alterado

| Área | Motivo |
|------|--------|
| Sync (Hive ↔ Firestore) | Núcleo; a IA só lê dados já expostos no catálogo. |
| Store Resolver / slug → lojaId | Resolução de loja permanece igual. |
| Auth / permissões | Cliente do catálogo pode ser anônimo; auth só no checkout se exigido. |
| CatalogoVendaService / pedidos | Criação de pedido e checkout inalterados. |
| Motor de Crescimento IA | Módulo distinto (lojista); nenhuma dependência cruzada. |

### 1.4 Pacote sugerido

```
lib/
  screens/
    public_catalog/
      ia/
        catalog_ia_service.dart           # Busca + respostas (Etapa 1–3)
        catalog_ia_search.dart            # Busca por nome, categoria, descrição, preço, estoque
        catalog_ia_suggestions.dart      # Sugestões combos/promo (Etapa 2)
        catalog_ia_whatsapp.dart          # Link WhatsApp + mensagem pronta (Etapa 3)
        catalog_chat_widget.dart          # UI do chat (flutuante ou seção)
        catalog_chat_message.dart         # Modelo de mensagem (user / bot / produtos)
        catalog_ia_fallback.dart          # Fallback quando IA desligada ou erro
```

Config da loja pode expor um flag opcional, por exemplo `config.catalogo_ia_habilitado`, para ativar/desativar o chat sem deploy.

---

## 2. SERVIÇOS NECESSÁRIOS

### 2.1 CatalogIaSearchService (Etapa 1 – base)

**Responsabilidade:** Busca sobre a lista de produtos **já carregada** no catálogo (em memória), usando nome, categoria, descrição, preço e estoque.

- **Entrada:** `query` (texto do usuário), `produtos` (lista `List<Map<String, dynamic>>` no mesmo formato do `PublicCatalogScreen`).
- **Saída:** Lista de produtos que batem com a query (ranking por relevância simples: nome/categoria/descrição, depois filtros numéricos).
- **Implementação:** Sem LLM externo na Etapa 1. Filtro e scoring local:
  - Normalizar texto (lowercase, acentos opcionais).
  - Match em `nome`, `categoria`, `subcategoria`, `descricao`.
  - Opcional: interpretar “até R$ X” / “acima de R$ Y” para filtrar por `preco` / `priceMin` / `priceMax`.
  - Opcional: “tem em estoque” / “disponível” → filtrar `quantidade > 0`.
- **Reuso:** Usar a mesma lista que o `PublicCatalogScreen` já obtém (ex.: `_allProducts` após `_processDocsToProducts`). Não abrir Firestore novamente; evitar duplicar lógica de produtos publicados/ativo.

### 2.2 CatalogIaService (orquestrador – Etapa 1–3)

**Responsabilidade:** Orquestrar pergunta do usuário e devolver uma resposta estruturada (texto + lista de produtos sugeridos + ações opcionais).

- **Etapa 1:**
  - Recebe mensagem do usuário.
  - Chama `CatalogIaSearchService.search(produtos, query)`.
  - Formata resposta: “Encontrei X produtos…” + lista (nome, preço, link para o produto no catálogo).
- **Etapa 2:** Além da busca, chamar `CatalogIaSuggestionsService` para combos e promoções (ver abaixo).
- **Etapa 3:** Se a intenção for “falar com alguém” / “WhatsApp”, chamar `CatalogIaWhatsAppService` e retornar link + mensagem pronta.

**Interface sugerida:**

```dart
class CatalogIaResponse {
  final String text;
  final List<Map<String, dynamic>> products;
  final CatalogIaAction? action; // ex: openWhatsApp, captureLead
}

class CatalogIaService {
  Future<CatalogIaResponse> respond({
    required String userMessage,
    required List<Map<String, dynamic>> products,
    required Map<String, dynamic> config,
    String? lojaId,
  });
}
```

### 2.3 CatalogIaSuggestionsService (Etapa 2)

**Responsabilidade:** Sugestões inteligentes de produtos, combos e promoções ativas.

- **Entrada:** Lista de produtos (com `emPromocao`, `itensCombo`, `preco`, `priceMin`, etc.) e config (cupons ativos, se houver).
- **Saída:** Listas sugeridas, por exemplo:
  - “Produtos em promoção”: filtro `emPromocao == true` e data dentro do período.
  - “Combos”: filtro `tipoProduto == 'combo'` ou `itensCombo != null`.
  - “Sugestões para você”: pode usar histórico do chat (ex.: última categoria buscada) ou simplesmente “destaques” (ex.: novos, promoção).
- **Regra:** Apenas leitura; nenhuma escrita em Firestore. Dados vêm da lista já carregada e do config (cupons já parseados pelo `catalog_config_service`).

### 2.4 CatalogIaWhatsAppService (Etapa 3)

**Responsabilidade:** Montar link do WhatsApp com mensagem pronta e, se aplicável, texto para carrinho abandonado ou lead.

- **Entrada:** Config da loja (já tem `whatsapp_vendedor` / `rodape.whatsapp`), contexto opcional (ex.: “quero saber sobre X”, itens do carrinho).
- **Saída:** URL `https://wa.me/{numero}?text={mensagem codificada}` e texto da mensagem.
- **Reuso:** Usar o mesmo número que o catálogo já usa (`atendimentoWhatsapp` / `whatsappVendedor`) e, quando for pedido, reutilizar `PrePedidoService.formatarParaWhatsApp` para não duplicar lógica. Para “dúvida geral”, mensagem simples: “Olá, vim pelo catálogo e gostaria de mais informações.”

### 2.5 Fallback (sem IA)

- Se `catalogo_ia_habilitado == false` ou serviço não configurado: não exibir chat ou exibir apenas busca simples.
- Se a busca “IA” falhar (ex.: timeout, erro): usar apenas `CatalogIaSearchService` com filtro local e mensagem tipo “Encontrei estes produtos conforme sua busca.”

---

## 3. TELAS / COMPONENTES NECESSÁRIOS

### 3.1 CatalogChatWidget (Etapa 1)

- **Onde:** Dentro do `PublicCatalogScreen` ou como overlay (botão flutuante “Dúvidas? Fale com a IA”).
- **Comportamento:** Lista de mensagens (user / bot). Campo de texto para enviar. Bot envia a mensagem para `CatalogIaService.respond()` e exibe a resposta (texto + cards de produtos com link para o produto no catálogo).
- **Estado:** Carregar lista de produtos e config uma vez (mesmos streams/dados que o catálogo já usa). Não manter estado de pedido ou carrinho na IA; apenas links para a página do produto ou para o carrinho existente.

### 3.2 CatalogChatMessage (apresentação)

- Mensagem do usuário: alinhada à direita, estilo “balão”.
- Mensagem do bot: texto + opcionalmente lista de `CatalogProductCard` compactos (nome, preço, botão “Ver” / “Adicionar”). Clicar leva ao produto no catálogo ou abre o sheet de detalhe já existente.

### 3.3 Botão / link “Falar no WhatsApp” (Etapa 3)

- Pode ser um botão dentro do chat (“Prefere falar com um atendente? Abrir WhatsApp”) ou na resposta da IA quando detectar intenção de handover.
- Usa `CatalogIaWhatsAppService` para gerar o link e `url_launcher` (mesmo padrão de `_openWhatsappSimple` do `PublicCatalogScreen`).

### 3.4 Captura de lead (Etapa 3 – opcional)

- Modal ou campo no chat: “Deixe seu nome e WhatsApp que entramos em contato.”
- Salvar em coleção separada, por exemplo `lojas/{lojaId}/leads_catalogo`, sem alterar fluxo de cliente/auth existente. Não reutilizar coleção de pedidos nem de clientes do núcleo.

---

## 4. DADOS NECESSÁRIOS DO CATÁLOGO

Todos os dados abaixo **já existem** no fluxo atual do catálogo; a IA apenas os consome em leitura.

### 4.1 Por produto (lista já processada pelo catálogo)

| Campo | Uso na IA |
|-------|-----------|
| `id`, `nome`, `slug` | Identificação e link para o produto. |
| `descricao` | Busca por texto (Etapa 1). |
| `categoria`, `subcategoria` | Busca e sugestões por categoria. |
| `preco`, `priceMin`, `priceMax` | Respostas de preço e filtros “até R$ X”. |
| `quantidade`, `estoquePorTamanho`, `variacoes` | Respostas “tem em estoque?”. |
| `emPromocao`, `percentualPromo`, `valorPromo`, `dataInicioPromo`, `dataFimPromo` | Sugestões de promoções (Etapa 2). |
| `tipoProduto`, `itensCombo` | Sugestões de combos (Etapa 2). |
| `imageUrl`, `imagens` | Exibição nos cards do chat. |

Fonte: mesma lista que o `PublicCatalogScreen` monta com `_processDocsToProducts` (ou equivalente via `CatalogCacheService.getProdutosStream` + processamento existente). Não definir nova coleção nem novo contrato de produto; usar o mapa já existente.

### 4.2 Config da loja (já disponível no catálogo)

| Campo | Uso na IA |
|-------|-----------|
| `whatsapp_vendedor`, `rodape.whatsapp` | Link WhatsApp (Etapa 3). |
| `cupons` (lista parseada) | Sugestões de cupons ativos (Etapa 2, opcional). |
| `catalogo_ia_habilitado` (novo, opcional) | Liga/desliga o chat no catálogo. |

Fonte: `CatalogCacheService.getConfigStream` ou o config já exposto no `StreamBuilder` do `PublicCatalogScreen`. Não alterar estrutura de sync do config; apenas ler.

### 4.3 O que a IA não acessa

- Hive do app (vendas, clientes, estoque interno do lojista).
- Store Resolver (a tela já tem `lojaId` resolvido).
- Auth do cliente (opcional no catálogo; lead é armazenado separado se necessário).

---

## 5. FLUXO DE FUNCIONAMENTO

### 5.1 Etapa 1 (chat simples + busca)

1. Cliente abre o catálogo (slug na URL → `lojaId` resolvido pelo fluxo atual).
2. Catálogo carrega config e produtos como hoje (`CatalogCacheService` / streams existentes).
3. Se `catalogo_ia_habilitado == true`, exibe o botão/área do chat.
4. Cliente envia mensagem (ex.: “tem tênis azul?”).
5. `CatalogIaService.respond()` chama `CatalogIaSearchService.search(produtos, "tênis azul")`.
6. Resposta: texto (“Encontrei X produtos”) + lista de produtos com link para a página/detalhe no catálogo.
7. Em caso de erro ou IA desabilitada: fallback com busca local e mensagem neutra.

### 5.2 Etapa 2 (sugestões e promoções)

1. Além da busca, o orquestrador pode chamar `CatalogIaSuggestionsService` para:
   - “Quais promoções?” → produtos com `emPromocao` e período válido.
   - “Tem combos?” → produtos com `itensCombo` / `tipoProduto == 'combo'`.
2. Resposta do chat pode misturar: texto + produtos em promo + combos sugeridos.

### 5.3 Etapa 3 (WhatsApp, lead, carrinho abandonado)

1. Cliente pede “quero falar com alguém” ou “atendente”.
2. `CatalogIaService` detecta intenção (regex ou regras simples) e chama `CatalogIaWhatsAppService.getLink(contexto)`.
3. Bot retorna mensagem com botão “Abrir WhatsApp” com texto pronto (ex.: “Olá, vim pelo catálogo e gostaria de mais informações.”).
4. **Captura de lead:** Se a loja optar por “entrar em contato”, exibir formulário (nome, WhatsApp), salvar em `leads_catalogo` e confirmar “Em breve entramos em contato.”
5. **Carrinho abandonado:** Na mensagem do WhatsApp, opcionalmente incluir resumo dos itens que o cliente tinha no carrinho (usar apenas dados já disponíveis na sessão do catálogo; não integrar com núcleo de pedidos). Implementação mínima: link para o catálogo + mensagem genérica.

---

## 6. IMPLEMENTAÇÃO EM ETAPAS

### Etapa 1

| Item | Descrição |
|------|-----------|
| **Chat simples** | Widget de chat (flutuante ou seção) no catálogo. |
| **Busca por produtos reais** | `CatalogIaSearchService`: filtro por nome, categoria, descrição, preço e estoque sobre a lista já carregada. |
| **Respostas** | Texto + lista de produtos (cards com link para o produto no catálogo). |
| **Fallback** | Se IA desligada ou erro, busca local apenas; sem quebrar o catálogo. |
| **Config** | Flag opcional no config da loja para habilitar/desabilitar o chat. |

### Etapa 2

| Item | Descrição |
|------|-----------|
| **Sugestões inteligentes** | `CatalogIaSuggestionsService`: “produtos em promoção”, “combos”, “destaques”. |
| **Sugestão de combos** | Filtrar produtos com `itensCombo` / tipo combo e exibir no chat. |
| **Sugestão de promoções ativas** | Filtrar `emPromocao` e período válido; opcionalmente citar cupons do config. |

### Etapa 3

| Item | Descrição |
|------|-----------|
| **Link WhatsApp** | Botão/link “Falar no WhatsApp” com mensagem pronta; reuso de número do config e de `PrePedidoService` quando for pedido. |
| **Captura de lead** | Formulário nome/WhatsApp; gravar em `lojas/{lojaId}/leads_catalogo`. |
| **Carrinho abandonado** | Mensagem opcional no WhatsApp com resumo do carrinho da sessão (dados em memória/localStorage do catálogo apenas). |

---

## 7. RISCOS E CUIDADOS

### 7.1 Segurança e privacidade

- **Dados do catálogo:** A IA só lê dados já públicos no catálogo (produtos publicados, config). Não expor dados internos (custos, margens, relatórios do lojista).
- **Lead:** Armazenar apenas o necessário (nome, WhatsApp, data, lojaId). Documentar na política de privacidade e uso pela loja.
- **Firestore:** Se criar coleção `leads_catalogo`, definir regras de segurança: escrita apenas para o próprio cliente (ou via Cloud Function) e leitura apenas para a loja dona do `lojaId`.

### 7.2 Performance

- **Sem chamadas extras ao Firestore** para listar produtos na IA: usar a mesma lista que o catálogo já carregou. Evitar `getProdutosStream` duplicado; passar a lista em memória para o serviço de IA.
- **Cache:** O catálogo já usa TTL (ex.: 5 min produtos, 10 min config). A IA segue o mesmo ciclo; não reduzir TTL por causa da IA.

### 7.3 UX e expectativas

- Deixar claro que é um **assistente do catálogo** (“Encontre produtos e tire dúvidas”), não um atendente humano. Na Etapa 3, o botão “Falar no WhatsApp” deve indicar que o cliente será atendido por humano.
- Respostas devem ser **curtas e acionáveis** (links para produtos, botão WhatsApp). Evitar textos longos sem ação.

### 7.4 Manutenção e evolução

- **Sem LLM na Etapa 1:** Reduz custo e complexidade; permite lançamento rápido. Em versões futuras, um backend opcional (ex.: Cloud Function com LLM) pode receber a mesma interface `CatalogIaResponse` para respostas mais naturais, mantendo o fallback local.
- **Motor de Crescimento:** Manter documentação e código separados. Nenhum import do `motor_crescimento` no módulo de IA do catálogo e vice-versa, exceto serviços compartilhados já existentes (ex.: config, produtos).

### 7.5 Testes

- Testar com `catalogo_ia_habilitado == false`: catálogo deve funcionar normalmente sem o chat.
- Testar com lista vazia ou config sem WhatsApp: não quebrar; mensagens adequadas (“Nenhum produto encontrado”, “WhatsApp não configurado”).
- Testar fallback quando o serviço de IA falhar (ex.: timeout): exibir apenas busca local.

---

## Resumo

| Aspecto | Decisão |
|--------|--------|
| **Arquitetura** | Módulo opcional em cima do catálogo; dados somente leitura; fallback sem IA. |
| **Serviços** | CatalogIaSearchService, CatalogIaService (orquestrador), CatalogIaSuggestionsService (Etapa 2), CatalogIaWhatsAppService (Etapa 3). |
| **UI** | CatalogChatWidget, mensagens user/bot, cards de produto com link, botão WhatsApp. |
| **Dados** | Reuso da lista de produtos e config já carregados pelo catálogo; nenhuma nova coleção de produtos. |
| **Implementação** | Etapa 1 (chat + busca) → Etapa 2 (sugestões/combos/promo) → Etapa 3 (WhatsApp, lead, carrinho abandonado). |
| **Riscos** | Evitar Firestore extra; não tocar em sync/Store Resolver/auth; documentar lead e regras Firestore. |

Este documento serve como especificação para implementação futura, sem alterar o comportamento atual do catálogo até que o módulo seja desenvolvido e ativado por config.
