# Etapa 1 – Refatoração Segura de Services (MasterPalm)

Documento de diagnóstico da **primeira onda de refatoração segura** na camada de services. Não altera runtime.

---

## 1. Services já refatorados na Etapa 1

### 1.1 ClienteAuthService

- **Arquivo original:** `lib/services/cliente_auth_service.dart`
- **Arquivo helper:** `lib/services/cliente_auth_helpers.dart`
- **Helpers extraídos (puros):**
  - `hashSenha(String senha)` – hash SHA256 de senha.
  - `gerarClienteId()` – ID único baseado em timestamp atual.
  - `gerarPortalToken()` – token aleatório URL-safe.
  - `formatarTimestamp(dynamic ts)` – formata Timestamp/DateTime em `dd/MM/yyyy`.
- **No service continuam:**
  - Cadastro, login, login Google, logout, sessão (`SharedPreferences`).
  - Fluxos de redefinição/alteração de senha.
  - Favoritos, carrinho, pedidos, cupons, números da sorte, chamadas a Cloud Functions e Firestore.
- **Risco atual:** **Alto**, mas com helpers de baixo nível isolados. Próximas refatorações devem focar em testes e separar, com cuidado, fluxos de redefinição de senha e sessão.

### 1.2 CatalogoVendaService

- **Arquivo original:** `lib/services/catalogo_venda_service.dart`
- **Arquivo helper:** `lib/services/catalogo_venda_helpers.dart`
- **Helpers extraídos (puros):**
  - `gerarDescricaoProdutos(List<Map<String, dynamic>> items)` – descrição para `produtosDescricao` a partir dos itens do catálogo.
  - `determinarTipoPremio(String? descricao, String? codigo, double? desconto)` – tipo de prêmio da roleta (`brinde`, `frete_gratis`, `desconto`, `nenhum`).
  - `gerarDescricaoProdutosFromItens(List<Map<String, dynamic>> itens)` – descrição a partir dos itens já normalizados da venda.
- **No service continuam:**
  - Criação de pedido pendente (catálogo).
  - Registro de venda do catálogo.
  - Confirmação/cancelamento de pagamento.
  - Baixa de estoque, sync com Firestore, integração com campanhas e notificações.
- **Risco atual:** **Alto**, mas com a parte de formatação de texto delegada a helpers. O core de orquestração continua intocado.

### 1.3 PrePedidoService

- **Arquivo original:** `lib/services/pre_pedido_service.dart`
- **Arquivo helper:** `lib/services/pre_pedido_helpers.dart`
- **Helpers extraídos (puros):**
  - `determinarStatusPagamento(String metodoPagamento)` – mapeia método (`mercadopago`, `pix`, `cartao` etc.) para status interno (`pendente` / `aprovado`).
  - `formatarValor(double valor)` – formatação monetária `99,99`.
  - `determinarTipoPremio(String? descricao, String? codigo, double? desconto)` – mesmo critério de tipo de prêmio da roleta usado em catálogo.
- **No service continuam:**
  - `criarPrePedido`, `confirmarPrePedido`, `cancelarPrePedido`, `excluirPrePedido`, `atualizarStatus`, streams.
  - Resolução de `portalToken`, escrita em `clientes_portal`/`pre_pedidos`/`pedido_status_publico`.
  - Notificações, email, cupons, histórico de cliente.
  - `formatarParaWhatsApp(...)` (texto, mas dependente de estrutura de `prePedido`).
- **Risco atual:** **Alto**, porém regras de status/valor/tipo de prêmio agora centralizadas em helpers puros.

### 1.4 FreteService

- **Arquivo original:** `lib/services/frete_service.dart`
- **Arquivo helper:** `lib/services/frete_helpers.dart`
- **Helpers extraídos (puros):**
  - `freteValidarCep(String cep)` – valida CEP (8 dígitos).
  - `freteFormatarCep(String cep)` – formata `12345678` como `12345-678`.
- **No service continuam:**
  - `calcularFrete` (orquestração de Melhor Envios, Frenet, Correios, SuperFrete, fretes manuais).
  - `_buscarConfigFrete`, `_calcularMelhorEnvio`, `_calcularFrenet`, `_calcularCorreios`, `_calcularManual`, `_fretePadrao`, parsers das respostas.
  - Criação de pré-pedido na plataforma de frete.
- **Risco atual:** **Médio**, com validação/formatação de CEP isoladas e reutilizáveis.

---

## 2. Resumo dos helpers extraídos por arquivo

- **`cliente_auth_helpers.dart`**
  - `hashSenha`, `gerarClienteId`, `gerarPortalToken`, `formatarTimestamp`.
- **`catalogo_venda_helpers.dart`**
  - `gerarDescricaoProdutos`, `determinarTipoPremio`, `gerarDescricaoProdutosFromItens`.
- **`pre_pedido_helpers.dart`**
  - `determinarStatusPagamento`, `formatarValor`, `determinarTipoPremio`.
- **`frete_helpers.dart`**
  - `freteValidarCep`, `freteFormatarCep`.

Todas as funções são **sem efeitos colaterais** e não chamam Firestore, Hive, HTTP, Cloud Functions ou outros serviços.

---

## 3. Services críticos que devem permanecer intactos por enquanto

Estes serviços continuam com papel central e **não devem ser refatorados estruturalmente** sem testes e plano dedicado:

- `vendas_service.dart` – fluxo de Nova Venda + sync + baixa de estoque.
- `estoque_service.dart` / `estoque_transaction_service.dart` – regras de estoque e transações atômicas.
- `pre_pedido_service.dart` – apesar dos helpers extraídos, o fluxo completo de pré-pedido é crítico (clientes_portal, pedido_status_publico).
- `catalogo_venda_service.dart` – orquestração de vendas do catálogo, integração com estoque e campanhas.
- `pos_pagamento_service.dart` – fluxo pós-pagamento e idempotência.
- `sync_queue_service.dart` – fila offline-first (Hive ↔ Firestore).
- `full_sync_service.dart` – sync inicial após login.
- `clientes_firestore_service.dart`, `produtos_firestore_service.dart`, `vendas_firestore_service.dart` – camada de acesso a dados consolidada.
- `marketplace_service.dart` – integrações com vários marketplaces no mesmo serviço.

---

## 4. Próximos candidatos para uma Etapa 2

Sem alterar nada agora, os candidatos naturais para uma **Etapa 2** (com mais preparo e possivelmente testes) são:

- **ClienteAuthService**
  - Separar com cuidado: fluxo de redefinição de senha (solicitar/redefinir/alterar) do núcleo de login/cadastro/sessão.
- **CatalogoVendaService**
  - Considerar extrair módulo de “resolução/expansão de itens/combos” (apenas lógica de mapeamento de itens → produtos/combos), mantendo I/O no service.
- **PrePedidoService**
  - Em uma etapa futura, avaliar extração da parte de formatação WhatsApp para helper e, mais adiante, isolar resolução de cliente/portalToken em pequeno módulo dedicado.
- **FreteService**
  - Possível extração de parsers por provedor (MelhorEnvio/Frenet) em helpers adicionais, mantendo as chamadas HTTP e a orquestração no service.
- **VendasService**
  - Consolidar resolução de produto (id/slug/nome) em módulo compartilhado com `strict_product_resolution`, sem mexer no fluxo de gravação/sync.

Todas essas mudanças devem ser planejadas **por serviço**, com mudanças pequenas e reversíveis.

---

## 5. Observações gerais

- A Etapa 1 focou exclusivamente em **helpers puros** para:
  - Reduzir ruído dentro dos services grandes.
  - Facilitar leitura e testes futuros.
  - Não introduzir novos pontos de I/O nem alterar contratos públicos.
- Não houve:
  - Mudança em assinaturas públicas.
  - Alteração de paths Firestore/Hive.
  - Modificação de fluxos principais (venda, pré-pedido, pós-pagamento, frete).

