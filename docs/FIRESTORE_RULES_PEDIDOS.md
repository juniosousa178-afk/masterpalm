# Firestore Rules de Pedidos

## Visão geral

O projeto MasterPalm possui mais de um fluxo de pedido ativo e legado. Nesta etapa, a meta não foi unificar coleções nem migrar documentos, e sim:

- centralizar os caminhos usados pelo app;
- reduzir strings espalhadas;
- endurecer regras críticas sem quebrar checkout, catálogo, vendas e deep links;
- documentar claramente quais coleções são públicas por necessidade e quais são internas.

## Caminhos de pedidos existentes

### `lojas/{lojaId}/pre_pedidos`

Função:
- entrada principal do checkout/catálogo;
- pedido operacional do catálogo;
- continua sendo usado após a confirmação para rastreio de status (`pendente`, `confirmado`, `embalando`, `enviado`, `entregue`, `cancelado`).

Quem lê (ETAPA 9):
- somente admin/programador ou vendedor da loja (`belongsToStore(lojaId)`).
- leitura pública removida; status público vem de `pedido_status_publico`.

Quem escreve:
- `create`: público, com validação de payload (checkout/catálogo);
- `update/delete`: admin/programador.

Regra endurecida na ETAPA 9:
- `read`: de `resource != null` para `belongsToStore(lojaId)`.

### `lojas/{lojaId}/pedidos`

Função:
- histórico final por loja;
- recebe gravações de múltiplos pontos (`CatalogoVendaService`, `OrderReviewScreen`, `TempOrderService`, `FirestoreCatalogOrderSink`).

Quem lê:
- admin/programador ou vendedor da loja (`belongsToStore(lojaId)`).

Quem escreve:
- `create`: ainda pode ser público, para preservar fluxos atuais;
- `read/update/delete`: `belongsToStore(lojaId)`.

Diferença intencional:
- o `create` público não foi fechado nesta etapa porque ainda há pontos de entrada que podem depender disso.
- o endurecimento aqui foi incremental: agora a regra valida coerência de `lojaId` com o path quando o campo existe no payload.

Regra endurecida nesta etapa:
- `create` exige `requestLojaIdMatchesPathIfPresent(lojaId)`.

### `lojas/{lojaId}/pedidos_pendentes`

Função:
- staging de pedidos aguardando confirmação de pagamento;
- usado em `CatalogoVendaService`;
- mantém flags como `vendaRegistrada` e `estoqueBaixado`.

Quem lê:
- leitura pública preservada nesta etapa.

Quem escreve:
- `create`: público com validação;
- `update`: agora somente `belongsToStore(lojaId)`;
- `delete`: admin/programador.

Diferença intencional:
- a leitura pública foi preservada temporariamente para não quebrar integrações e retorno de pagamento.
- o `update` era o ponto mais perigoso e foi fechado primeiro.

Regra endurecida nesta etapa:
- `update` deixou de aceitar qualquer autenticado;
- `create/update` agora validam coerência de `lojaId` com o path quando o campo existe.

### `lojas/{lojaId}/pedidos_temp`

Função:
- fluxo temporário/deep-link;
- usado por `TempOrderService` e `OrderReviewScreen`.

Quem lê:
- leitura pública preservada.

Quem escreve:
- `create/update/delete`: públicas nesta etapa, para manter compatibilidade com o fluxo legado.

Diferença intencional:
- este fluxo ainda depende de acessos públicos e compatibilidade com deep link.
- não foi fechado agora para evitar regressão em `OrderReviewScreen` e espelhos antigos.

Regra endurecida nesta etapa:
- `create/update` agora validam `lojaId` contra o path quando o campo estiver presente.

### `lojas/{lojaId}/pedido_temp`

Função:
- legado do fluxo temporário, mantido para leitura/remoção tolerante.

Quem lê/escreve:
- mesma política temporária de `pedidos_temp`.

Diferença intencional:
- mantido apenas por compatibilidade com documentos antigos.

Regra endurecida nesta etapa:
- mesma coerência de `lojaId` do `pedidos_temp`.

### `lojas/{lojaId}/temp_orders`

Função:
- caminho obsoleto/legado.

Quem lê/escreve:
- mesma política temporária de `pedidos_temp`.

Diferença intencional:
- mantido para compatibilidade e limpeza gradual.

Regra endurecida nesta etapa:
- mesma coerência de `lojaId` do `pedidos_temp`.

### `lojas/{lojaId}/pedidos_catalogo`

Função:
- coleção legada, sem uso ativo confirmado no runtime atual.

Quem lê/escreve agora:
- `read/update/delete`: `belongsToStore(lojaId)`;
- `create`: `belongsToStore(lojaId)` + payload válido + `lojaId` coerente.

Diferença intencional:
- esta coleção foi endurecida porque não há uso ativo público confirmado.
- a mudança reduz superfície exposta sem tocar no fluxo principal do checkout.

### `pedidos_temp` (root)

Função:
- espelho público root para deep link legado.

Quem lê/escreve:
- leitura pública;
- `create/update/delete` públicos, como antes.

Diferença intencional:
- mantido temporariamente para não quebrar o legado de deep link.
- não houve endurecimento estrutural nesta etapa.

### `pedidos` (root)

Função:
- legado administrativo.

Quem lê/escreve:
- admin/programador apenas.

## Ajustes feitos nesta etapa

### 1. Centralização de paths

Novos arquivos:
- `lib/services/pedido_collection_resolver.dart`
- `lib/repositories/pedido_repository.dart`

Objetivo:
- resolver o caminho correto de cada fluxo;
- encapsular leituras/escritas comuns;
- reduzir risco de divergência entre telas e serviços.

### 2. Endurecimento incremental das rules

Mudanças aplicadas em `firestore.rules`:
- criado helper `requestLojaIdMatchesPathIfPresent(lojaId)`;
- `pedidos_pendentes.update` agora exige `belongsToStore(lojaId)`;
- `pedidos_catalogo` deixou de ser público e passou a ser fluxo interno por loja;
- `pre_pedidos.create` agora exige `lojaId` coerente com o path;
- `pedidos`, `pedidos_pendentes`, `pedidos_temp`, `pedido_temp` e `temp_orders` validam coerência de `lojaId` quando o campo existe.

### 3. Escrita canônica de `lojaId`

Os fluxos ativos por loja passaram a gravar `lojaId` de forma explícita também em:
- `pedidos_pendentes`
- `pedidos`
- `FirestoreCatalogOrderSink`

Isso reduz ambiguidades e prepara o terreno para endurecimentos futuros sem migrar documentos antigos.

### `lojas/{lojaId}/pedido_status_publico` (ETAPA 7, fonte pública ETAPA 9)

Função:
- coleção pública sanitizada para status de pedido;
- usada por `PedidoPublicoScreen` (leitura pública).

Quem lê:
- leitura pública (`resource != null`).

Quem escreve:
- `create/update/delete`: admin/programador ou vendedor da loja (`belongsToStore(lojaId)`), com payload validado.

## Compatibilidade preservada (ETAPA 9)

- `PedidoPublicoScreen` usa APENAS `pedido_status_publico`; sem fallback para `pre_pedidos`.
- `MeusPedidosRepository` usa APENAS `clientes_portal`; sem leitura de `pre_pedidos`.
- `pedidos_temp` root e variantes legadas continuam funcionando.
- nenhum documento foi movido, renomeado ou migrado.
- nenhuma coleção existente foi removida.
- o checkout atual não foi trocado de coleção.
- o deep link `/pedido/{id}` continua aceitando os mesmos caminhos e semânticas atuais.

## Diferenças legítimas entre coleções

- `pre_pedidos` não é igual a `pedidos`: o primeiro é pedido operacional do catálogo; o segundo é histórico final.
- `pedidos_pendentes` não é igual a `pre_pedidos`: ele representa o estágio de pagamento pendente, não o rastreio operacional do catálogo.
- `pedidos_temp` não é igual a `pre_pedidos`: ele atende fluxo legado/deep-link temporário.
- `pedidos_catalogo` foi tratado como legado interno, não como fluxo público ativo.

## O que ficou deliberadamente para depois

- fechar leitura pública de `pre_pedidos` — ✅ **FEITO na ETAPA 9**;
- fechar o root `pedidos_temp`;
- consolidar `pedidos_temp`, `pedido_temp` e `temp_orders`;
- unificar `pre_pedidos` e `pedidos_pendentes`;
- fechar `create` público em `lojas/{lojaId}/pedidos`.

Esses passos exigem validação de fluxo público e, potencialmente, ajustes em tela, webhook e deep link. Por isso ficaram fora desta etapa para manter o menor risco possível.
