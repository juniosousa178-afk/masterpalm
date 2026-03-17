# Fluxo de Sincronização (Hive ↔ Firestore)

Este documento descreve o fluxo de sincronização offline-first do app: armazenamento local (Hive) e nuvem (Firestore), fila de envio e casos de conflito.

## Visão geral

- **Hive**: dados locais por loja em boxes nomeadas `produtos_<lojaId>`, `clientes_<lojaId>`, `vendas_<lojaId>`, `fornecedores_<lojaId>`.
- **Firestore**: coleções por loja em `lojas/<lojaId>/estoque_produtos`, `estoque_clientes`, etc.
- **SyncQueueService**: fila persistida no Hive que envia alterações locais para o Firestore (com retry e backoff).
- **FullSyncService**: sincronização completa Firestore → Hive no login (download).

## Sentido dos fluxos

| Momento            | Direção        | Fonte da verdade |
|--------------------|----------------|-------------------|
| Uso normal (CRUD)  | App → Hive     | Usuário           |
| Envio para nuvem   | Hive → Firestore | Local (fila)    |
| Login / sync inicial | Firestore → Hive | Firestore      |

## SyncQueueService (Hive → Firestore)

1. **Enfileiramento**: Após gravar uma entidade no Hive (produto, cliente, venda, fornecedor), o código chama `SyncQueueService.enqueue()` com tipo, `lojaId`, nome da box e chave da entidade.
2. **Persistência**: Os itens ficam na box `sync_queue` no Hive (sobrevivem a fechamento do app).
3. **Processamento**: 
   - Disparado por debounce (~800 ms) após enqueue e quando a conectividade volta (listener `Connectivity().onConnectivityChanged`).
   - Para cada item: abre a box correspondente, lê a entidade pela chave e chama o serviço Firestore (ex.: `ProdutosFirestoreService.syncProduto`, `VendasFirestoreService.syncVenda`).
4. **Retry**: Até 5 tentativas com backoff exponencial (500 ms base, máx. 30 s). Após o máximo, o item é removido da fila e contabilizado como falha.
5. **Entidade deletada**: Se a chave não existir mais na box (ex.: produto/cliente removido localmente), o item é removido da fila sem erro (não tenta enviar).

**Conflito neste fluxo**: O que está no Hive é enviado e sobrescreve o Firestore (estrategia “local wins” na subida).

## FullSyncService (Firestore → Hive no login)

1. **Quando**: Chamado após login bem-sucedido (`syncInicialCompleto()`).
2. **Resolver loja**: Obtém `lojaId` via `StoreResolverService.resolve()`.
3. **Cache de outra loja**: Se existir `last_synced_loja_id` diferente do atual, limpa as boxes locais da loja antiga (`produtos_<id>`, `clientes_<id>`) e atualiza `last_synced_loja_id` e `last_sync_timestamp` na box `sessao`.
4. **Produtos**: Busca todos em `lojas/<lojaId>/estoque_produtos` (paginado, 500 por página). Para cada documento:
   - Se já existe no Hive (por `idFirebase` ou `slug`), **atualiza** o registro existente com os dados do Firestore.
   - Caso contrário, adiciona novo com `idFirebase` preenchido.
5. **Clientes**: Busca todos em `lojas/<lojaId>/estoque_clientes`. Só adiciona se não existir duplicata por telefone ou e-mail (evita duplicar no Hive).

**Conflito neste fluxo**: No sync inicial, **Firestore vence**: os dados baixados sobrescrevem o que estiver no Hive para a mesma entidade (produto identificado por idFirebase/slug; cliente por telefone/email).

## Casos de conflito resumidos

| Cenário | Comportamento |
|--------|----------------|
| Usuário edita offline e depois faz login / full sync | Firestore sobrescreve o Hive no download; alterações locais não enviadas antes podem ser perdidas se não estiverem na fila. |
| Fila envia alteração local para Firestore | Firestore é atualizado com o valor do Hive (local wins na subida). |
| Dois dispositivos editam o mesmo produto | Quem fizer o full sync por último ou quem enviar pela fila por último “vence”; não há merge automático de campos. |
| Produto com mesmo nome/categoria mas códigos diferentes | `ProdutoUpsertService.hasConflito` detecta; a lógica de negócio pode manter separado ou exibir aviso (ver `produto_upsert_service.dart`). |

## Boas práticas

1. **Sempre enfileirar** após criar/atualizar no Hive entidades que devem ir para o Firestore (produto, cliente, venda, fornecedor), para não perder dados offline.
2. **Evitar trocar de loja** sem concluir o processamento da fila quando possível; ao trocar, o FullSync da nova loja pode sobrescrever boxes que ainda tinham itens pendentes de envio da loja anterior se as boxes forem as mesmas (por lojaId o fluxo já isola por loja).
3. **Conflitos de produto**: Em cadastro/importação, tratar o aviso de `hasConflito` (nome/categoria iguais, códigos diferentes) conforme regra de negócio (ex.: unificar ou manter separado com outro código).
4. **Monitorar falhas**: Usar `SyncQueueService.pendingCount()` e os resultados de `processPending()` para identificar itens que falharam após o máximo de tentativas e eventualmente reenfileirar ou corrigir dados.

## Referência rápida de serviços

- **SyncQueueService** (`lib/services/sync_queue_service.dart`): fila Hive → Firestore, retry, conectividade.
- **FullSyncService** (`lib/services/full_sync_service.dart`): sync completo Firestore → Hive no login.
- **ProdutoUpsertService** (`lib/services/produto_upsert_service.dart`): detecção de conflito nome/categoria vs código.
- **StoreResolverService** (`lib/services/store_resolver_service.dart`): resolução de loja do usuário (sessão/config).
