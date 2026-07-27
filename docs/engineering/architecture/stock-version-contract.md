# Contrato de versão de estoque (R8/R8.1/R8.2/R8.3)

## Campos Firestore (`estoque_produtos`)

| Campo | Tipo | Significado |
|-------|------|-------------|
| `stockRevision` | int monotônico | Ordenação autoritativa da grade (default 0) |
| `stockOperationId` | string UUID | Última mutação autoritativa |
| `stockUpdatedAt` | serverTimestamp | Diagnóstico / readback — **não** ordena merge |

## Campos Hive (`Produto`)

| HiveField | Campo | Significado |
|-----------|-------|-------------|
| 48 | `stockUpdatedAt` | Espelho diagnóstico |
| 49 | `stockUpdatedAtServer` | Último serverTimestamp confirmado |
| 50 | `stockRevision` | Revisão confirmada localmente |
| 51 | `confirmedStockOperationId` | Operação confirmada |
| 52 | `pendingStockOperationId` | Mutação local pendente |
| 53 | `pendingStockBaseRevision` | Revisão base ao iniciar pendência |
| 54 | `stockSyncState` | `conflict` persistido; demais estados derivados |

## Estado pendente e conflito (R8.3/R8.4)

- **Pendência:** `pendingStockOperationId != null` — nunca inferir por `DateTime.now()` vs `stockUpdatedAtServer`.
- **Confirmação:** remoto devolve o mesmo `stockOperationId` e `stockRevision > pendingStockBaseRevision`.
- **Conflito (R8.4):** `stockSyncState=conflict` quando remoto avança com `operationId` diferente durante pendência; pull preserva grade; push automático bloqueado.

## Enforcement servidor (R8.4)

Firestore Rules em `estoque_produtos` — ver [stock-revision-server-enforcement.md](./stock-revision-server-enforcement.md).

Classificação emulator: `STOCK_REVISION_SERVER_ENFORCEMENT_VALIDATED`.

Cliente: `enforceStockRevisionWriteContract` + `kMinStockRevisionClientVersion`.

## Merge pull (`evaluatePullStockMergeByRevision`)

1. `remoteRevision < localRevision` → preservar local (remoto regressivo).
2. Pendência + mesmo `operationId` remoto → aceitar remoto.
3. Pendência + `operationId` diferente → preservar local.
4. `remoteRevision > localRevision` → aceitar remoto.
5. Mesma revisão + grade remota maior em qualquer célula → preservar local (snapshot stale).
6. Legado sem `stockRevision` + `localRevision > 0` → conservador.

## Push (`evaluatePushStockSkipByRevision`)

- Pendência local → nunca ignorar push.
- `remoteRevision > localRevision` → ignorar push stale.
- Mesma revisão + grade local domina remoto → ignorar push stale.

## Escritores autoritativos

Toda mutação de grade via `buildEstoqueUpdateDataComDeletes` deve incluir `stockRevision+1` e `stockOperationId`.

Hive pós-transação: `markPendingStockMutation` + `stockRevision` otimista da transação.

## Compatibilidade legado

**Política:** `LEGACY_COEXISTENCE_REQUIRES_FORCED_UPDATE` (app antigo não grava `stockRevision` e pode sobrescrever grade sem versão).

Matriz resumida:

| Escritor | Leitor | Risco |
|----------|--------|-------|
| antigo | novo | pull conservador; revisão 0 + grade maior → preserva local |
| novo | antigo | antigo ignora `stockRevision`; coexistência temporária apenas com atualização forçada |

## Produção

Classificação permanente até deploy validado: `ERRO_COMPLETO_NOT_RESOLVED`.
