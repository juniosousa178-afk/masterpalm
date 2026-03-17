# Arquitetura Offline-First - MasterPalm

## 1. Fonte de verdade (Source of Truth)

| Entidade | Fonte de verdade | Direção | Motivo |
|----------|------------------|----------|--------|
| **Produtos** | Hive (local) | Hive → Firestore | App é o criador; catálogo lê do Firestore |
| **Clientes** | Hive (local) | Hive → Firestore | Cadastro no app; estoque_clientes no Firestore |
| **Vendas** | Hive (local) | Hive → Firestore | Venda registrada offline primeiro |
| **Catálogo (draft/live)** | Firestore | Hive → Firestore | Publicação acontece no Firestore |
| **Config da loja** | Hive (local) | Hive → Firestore | Config editada no app |
| **Produtos/Clientes (estoque)** | Firestore | Firestore → Hive | FullSync ao login; espelho para relatórios |

**Regra geral:**
- **Leitura offline**: Hive é a fonte para o app (lista, busca, venda).
- **Escrita**: App grava em Hive primeiro; sincronização envia para Firestore.
- **Firestore**: Espelho remoto + fonte para catálogo web e multi-dispositivo.

---

## 2. Fila de sincronização com retry

### Fluxo

```
[App] → grava em Hive → enfileira operação → SyncQueue processa
                              ↓
                    [Hive: sync_queue] (persistido)
                              ↓
              Retry com backoff → Firestore (sucesso)
                              ↓
                    Remove da fila ou marca falha
```

### Características

- **Persistência**: Operações pendentes em Hive (`sync_queue`).
- **Retry**: Tentativas com backoff exponencial (500ms, 1s, 2s, 4s...).
- **Reconexão**: Ao detectar rede, processa fila automaticamente.
- **Deduplicação**: `operationId` evita duplicar a mesma operação.

---

## 3. Idempotência

Cada operação tem um **operationId** único e estável:

| Tipo | OperationId | Comportamento no Firestore |
|------|-------------|----------------------------|
| upsert_produto | `produto_${lojaId}_${slug}` | `set(merge: true)` |
| upsert_cliente | `cliente_${lojaId}_${idFirebase\|telefone}` | `set(merge: true)` |
| upsert_venda | `venda_${lojaId}_${idFirebase\|key}` | `set(merge: true)` |
| delete_produto | `delete_produto_${lojaId}_${slug}` | `delete()` |

**Por que é idempotente:**
- Reexecutar a mesma operação produz o mesmo resultado.
- `set(merge: true)` sobrescreve com os dados atuais.
- Retry não cria duplicatas.

---

## 4. Tratamento de falhas e reconexão

### Falhas temporárias (rede, timeout)

1. Operação falha → permanece na fila.
2. Retry com backoff exponencial (ex.: até 5 tentativas).
3. Após limite, operação vai para fila de "falha permanente".
4. Usuário pode reprocessar manualmente na tela de sync.

### Falhas permanentes (403, validação)

1. Marca operação como `failed`.
2. Não reprocessa automaticamente.
3. Log para debug; usuário pode editar e tentar novamente.

### Reconexão

1. **connectivity_plus** ou **Firebase.remoteConfig** para detectar rede.
2. `SyncQueueService.processPending()` chamado ao voltar online.
3. Processa fila em ordem (FIFO).
4. Evita concorrência com lock/mutex.

### Conflitos

- **Last-write-wins**: Firestore usa `updatedAt` / `serverTimestamp`.
- Operações locais têm prioridade; Firestore é destino, não origem de conflito para dados editados no app.

---

## 5. Integração com serviços existentes

- **ClientesFirestoreService**, **VendasFirestoreService**, **ProdutosFirestoreService**: Continuam com a lógica de serialização.
- **SyncQueueService**: Enfileira operações e chama esses serviços no processamento.
- **FullSyncService**: Mantido para pull inicial (Firestore → Hive) no login.
- **ProdutoAutoSyncService**: Pode passar a usar a fila em vez de sync direto.

---

## 6. Diagrama de sequência

```
[VendasService]     [Hive]    [SyncQueue]     [Firestore]
      |               |            |               |
      |-- registrar --|            |               |
      |               |-- put ---->|               |
      |               |            |-- enqueue ---->| (persist)
      |               |            |               |
      |               |     [rede volta]           |
      |               |            |-- process --->|
      |               |            |               |-- set -------->|
      |               |            |<-- success ----|               |
      |               |            |-- remove from queue           |
```

---

## 7. Chamadas NÃO alteradas

Os serviços existentes (`VendasService`, `ClientesFirestoreService`, etc.) **não** mudaram as assinaturas. O `SyncQueueService` é uma camada adicional:

1. **VendasFirestoreService**, **ClientesFirestoreService**, **ProdutosFirestoreService**: ao falhar após retries, enfileiram automaticamente via `SyncQueueService.enqueue()`.
2. O processamento usa os mesmos serviços para efetuar o write no Firestore.
3. Nenhuma chamada de negócio foi alterada.

## 8. Inicialização

No `main.dart` (bootstrap):

```dart
await SyncQueueService.init();
if (!kIsWeb) SyncQueueService.startConnectivityListener();
```

O listener de conectividade chama `processPending()` quando a rede volta.
