# MASTERPALM — P0 FIX — edição de venda atômica (legado + ACTIVE)

Branch `fix/atomic-sale-edit-stock` (base `31e2db0`). Sem deploy, sem tag, sem edição sintética em produção, sem alteração de dados de produção.

## Causa raiz (confirmada)

O cliente antigo divide uma edição mista em dois comandos independentes: `editstock_<venda>_<hash>_sale` (baixa) e depois `…_restock` (devolução). Em lojas NO_CONTROL, `restock` é proibido. A baixa é commitada e a devolução é rejeitada, o que deixa uma mutação parcial. Depois o erro genérico `failed-precondition` é rotulado como "Os dados de estoque deste produto foram atualizados". A venda 4373805c prova o caso historicamente (ver `SALE_4373805C_FORENSICS.md`).

## §0/§16 Contenção do cliente antigo

- O sufixo `_sale` em `editstock_…_<sha256>_sale` é gerado **apenas** por `reconciliarEdicaoEstoqueTransactionBatch` quando a edição é mista (commit 46422a3). Vendas novas usam UUID v4 (`newStockOperationId` / `idFirebaseReservado`), e edição de direção única usa `editstock_<venda>_<hash>` sem sufixo. A identificação é por regex estrita de formato, sem substring.
- Guarda no servidor: `legacyCompat && kind=sale && /^editstock_(.+)_[0-9a-f]{64}_sale$/`, rejeitada com `failed-precondition` + `LEGACY_PROTOCOL_BLOCKED/LEGACY_SPLIT_EDIT_SALE_HALF` **antes** de qualquer leitura de operação ou escrita. Resultado: OLD_CLIENT_MIXED_EDIT_PARTIAL_WRITE_COUNT = 0 (teste com snapshot do banco).
- Continuam permitidas: venda nova (UUID) e edição antiga só de aumento (`editstock_…` sem sufixo, uma única operação, já atômica).
- `restock` em NO_CONTROL continua bloqueado (`INACTIVE_COMPAT_ALLOWED_KINDS` inalterado).
- Residual: em lojas ACTIVE (hoje só `brisa-do-sol-pratas`, 0 vendas), cliente antigo em cache ainda faz `sale` + `restock` não atômicos, porque `restock` é permitido com concessão. Isso se resolve com a publicação do cliente novo.

## §2 Sequência da edição e classificação

| Passo | Classe | Falha antes (antigo) | Agora |
|---|---|---|---|
| Validações de fiado / valor recebido / remoção de CR | UI_ONLY (pré-mutação) | sem efeito | igual |
| Delta de estoque (`sale` e depois `restock`) | AUTHORITATIVE | **parcial** entre os 2 comandos | 1 comando `saleEdit`, 1 transação |
| Documento `estoque_vendas` (itens, total, pagamentos, fiado) | AUTHORITATIVE / FINANCIAL | `syncVenda` assíncrono, depois do estoque | mesmo commit do estoque |
| `currentItems` da operação de venda | DERIVED (servidor) | inexistente, então um restore posterior devolvia as linhas originais | mesmo commit |
| Hive venda / produto | DERIVED (projeção local) | gravado após o estoque | gravado após o commit; `syncVenda` não sobrescreve linhas do servidor |
| Contas a receber | DERIVED / RECONCILÁVEL | local-first + remoto best-effort | igual (republicação existente) |
| Histórico do cliente, movimentações, catálogo web | DERIVED | best-effort | best-effort |

## §3–§11 Comando `saleEdit`

- O cliente envia `lojaId`, `saleId`, `operationId=saleedit_<sha256>`, `expectedOriginalLinesHash` e os campos editáveis da venda (allowlist; `id`/`createdAt`/`stockOperationId` nunca são aceitos).
- O servidor lê `estoque_vendas/{saleId}` dentro da transação e confere loja, status (cancelada/estornada/excluída) e CAS do hash das linhas. Calcula o delta **por célula exata** (productId, tamanho, cor, extra; sem fallback agregado). Devoluções só existem para células da venda salva e nunca excedem o consumido.
- Estoque + documento da venda + `currentItems` da operação de venda são gravados no mesmo commit. Edição sem mudança de estoque gera 0 gravações de estoque.
- Idempotência: replay do mesmo id e payload retorna `alreadyApplied` sem escrita. Mesmo id com payload diferente dá `OPERATION_PAYLOAD_CONFLICT`. Edição concorrente dá `SALE_EDIT_CONFLICT` (CAS).
- Concorrência: o estoque é relido na transação, e revisão divergente gera `STOCK_CHANGED`.
- Autorização: `permission sale`. Em NO_CONTROL, membro com permissão de venda. Em ACTIVE, concessão `sale`. Venda de outra loja dá `SALE_NOT_FOUND`/`SALE_STORE_MISMATCH`; produto de outra loja dá `PRODUCT_NOT_FOUND`.
- Combos: qualquer mudança de linha de combo ou da seleção de componentes falha fechada (`COMBO_EDIT_NOT_SUPPORTED`), porque o servidor não pode verificar a receita local.
- Linha alterada sem `productId` (vendas legadas): falha fechada (`LINE_PRODUCT_ID_REQUIRED`), sem resolução por nome.

## §8 Classificação financeira

Campos da venda (total, pagamentos, saldo/parcelas/vencimento do fiado) são MUST_BE_ATOMIC e são gravados pelo servidor no commit. Quando o saldo é ≤ 0,01, os campos de fiado são removidos. Contas a receber continuam DERIVED (fluxo local-first existente + republicação). Não há comissão no caminho de edição. Sem redesenho financeiro.

## §14/§15 Códigos e mensagens

`STOCK_CHANGED`, `INSUFFICIENT_STOCK`, `LEGACY_PROTOCOL_BLOCKED`, `GRADE_SELECTION_REQUIRED`, `SALE_EDIT_CONFLICT`, `INVALID_SALE_EDIT` (+ `reason`), `OPERATION_PAYLOAD_CONFLICT` em `HttpsError.details.code`. O cliente mapeia por código. Um `failed-precondition` genérico **não** vira mais "foram atualizados"; só `STOCK_CHANGED` ou uma mensagem de revisão de estoque. Produto simples sem saldo agora reporta `INSUFFICIENT_STOCK`, e não mais `GRADE_SELECTION_REQUIRED`.

## §19 Log de rejeição

`stock_command_rejected` (WARNING, JSON de uma linha) com `storeId`, `kind`, `operationType` (saleEdit / legacyEditSplitSale / legacyEditSplitRestock / legacyEditSingle / kind), `saleRef` (sha256 truncado do id), `reasonCode`, `reason`, `httpCode`, `errorMessage` (≤120) e `clientBuild`. Sem nomes, telefones, valores ou linhas.

## §21 Orçamento de gravações (medido no teste)

| Linhas na venda | Produtos alterados | NO_CONTROL (writes / unidades) | ACTIVE (writes / unidades) |
|---|---|---|---|
| 50 | 25 | 27 / 55 | 77 / 155 |
| 100 | 25 | 27 / 55 | 77 / 155 |
| 150 | 25 | 27 / 55 | 77 / 155 |
| qualquer | 26 | rejeitado antes de gravar | rejeitado antes de gravar |

MAX_SAFE_ATOMIC_EDIT_LINES = 200 linhas por venda, com no máximo 25 produtos distintos alterados por edição (limite interno `MAX_PRODUCTS=25` e orçamento de 100 gravações, ambos inalterados). Mir Joias: maior venda tem 98 linhas.

## Cliente

- `editarVendaMulti`: quando as linhas mudam, monta um rascunho desanexado e faz a pré-verificação da nuvem. Se a nuvem já tem edição autoritativa diferente, hidrata o local e pede para refazer. Se a venda nunca foi sincronizada ou está com linhas legadas, publica a base local antes. Depois chama `saleEdit`, projeta o resultado no Hive e só então salva a venda local. Se o servidor rejeitar, a venda e o estoque locais ficam intactos.
- `operationId` = sha256(loja | venda | sessão de edição | hash original | payload). Reenvio na mesma sessão é idempotente; nova sessão gera outro id.
- `syncVenda` não sobrescreve um documento com `saleEditRevision` cujas linhas divergem do local; nesse caso hidrata o local.
- O caminho antigo (`reconciliarEdicaoEstoqueTransactionBatch`) fica apenas para testes com Firestore falso.

## Dados de produção (somente leitura)

94 lojas: 93 NO_CONTROL e 1 ACTIVE (`brisa-do-sol-pratas`, 0 vendas). Linhas sem `productId`: Mir 0/606; Nathy 231/796 (168 vendas); Lavile 45/132 (34 vendas). Nessas vendas legadas, alterar a quantidade de uma linha sem vínculo falha fechada com mensagem clara. As demais linhas da venda continuam editáveis.

## Plano de release (§24)

1. Deploy **somente** `functions:stockCatalogCommand` (comando `saleEdit` + guarda do cliente antigo + códigos + log). Sem Rules, Hosting, mpCatalogPayment, SMTP ou consignação.
2. Verificar: logs `stock_command_rejected` com `legacyEditSplitSale` (esperado: rejeição sem escrita); vendas novas e edições de aumento seguem OK.
3. Build web/APK do cliente com `saleEdit` (APP_VERSION/CATALOG_BUILD_ID carimbados).
4. Verificar o build (identidade do bundle, smoke de venda nova).
5. Validação natural: aguardar edições reais; conferir `saleEditRevision`/`lastSaleEditOperationId` nas vendas editadas e a ausência de `legacyEditSplitSale` aplicado.

Tag somente após a validação.
