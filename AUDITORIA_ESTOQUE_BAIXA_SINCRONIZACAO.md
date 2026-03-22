# AUDITORIA COMPLETA: ESTOQUE / BAIXA / SINCRONIZAÇÃO — MasterPalm

**Data:** 22/03/2025  
**Objetivo:** Validar o fluxo pós-venda: baixa de estoque, sincronização e consistência entre catálogos, pedidos e operação.

---

## 1. RESUMO EXECUTIVO

| Aspecto | Status | Risco |
|---------|--------|-------|
| Baixa depende de pagamento aprovado | Parcial | Médio |
| Dupla baixa em fluxo admin | **SIM** | Crítico |
| Sincronização catálogo web vs Firestore | Inconsistente | Alto |
| Cancelamento devolve estoque | Sim (Hive→Firestore) | Médio |
| Transação atômica na baixa | Sim (Flutter/JS) | — |
| Idempotência MP webhook | Sim | — |

**Principais achados:**
- Dupla baixa confirmada no fluxo de confirmação manual (admin confirma pre_pedido): `registrarVendaCatalogo` e `PosPagamentoService` ambos fazem baixa.
- Estoque em `produtos` (catálogo web) não é atualizado quando a baixa vem do app — apenas `estoque_produtos` é alterado.
- mpWebhookHandler e EstoqueTransactionService usam coleções e formatos ligeiramente diferentes.

---

## 2. FLUXO COMPLETO DA BAIXA E SINCRONIZAÇÃO

### 2.1 Canais de Baixa

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ CANAL A: Catálogo Web + Mercado Pago (PIX/Cartão)                           │
├─────────────────────────────────────────────────────────────────────────────┤
│ 1. Cliente finaliza checkout → PrePedidoService.criarPrePedido()            │
│    → pre_pedidos (SEM baixa)                                                │
│ 2. MP processa pagamento → webhook → mpWebhook (functions/index.js)         │
│ 3. processMpWebhook(paymentId) → status=approved                            │
│ 4. Transação atômica:                                                        │
│    - _mp_webhook_processed/{paymentId} (idempotência)                        │
│    - pedido status → paid                                                   │
│    - produtos + estoque_produtos: quantidade - qty                           │
│ 5. Cria venda em estoque_vendas (sync APK)                                  │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ CANAL B: Admin confirma pre_pedido manualmente (app)                        │
├─────────────────────────────────────────────────────────────────────────────┤
│ 1. Admin clica "Confirmar" em pre_pedidos_screen                            │
│ 2. CatalogoVendaService.registrarVendaCatalogo()                            │
│    → EstoqueTransactionService.baixarEstoqueTransactionBatch()  [BAIXA 1]   │
│    → cria venda Hive, pedido, sync Firestore                                │
│ 3. PosPagamentoService.processarConfirmacaoPagamento()                      │
│    → _baixarEstoque() via EstoqueTransactionService             [BAIXA 2] ❌ │
│    → estoque_baixa_pagamento/{vendaId} (idempotência)                       │
│    → status pago, número sorte, notificações                                │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ CANAL C: Nova venda no APK (VendasService)                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│ 1. NovaVendaModal → VendasService.registrarVendaMulti()                     │
│ 2. EstoqueTransactionService.baixarEstoqueTransactionBatch()                │
│ 3. Cria venda Hive, sync Firestore                                          │
│ 4. SEM chamada a PosPagamentoService (venda já paga na hora)                │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│ CANAL D: finalizarPedidoComPagamento (pedidos_pendentes)                    │
├─────────────────────────────────────────────────────────────────────────────┤
│ 1. CatalogoVendaService.finalizarPedidoComPagamento(pedidoId)               │
│ 2. EstoqueTransactionService.baixarEstoqueTransactionBatch()                │
│ 3. Cria venda, sync, marca vendaRegistrada no pedido                        │
│ 4. NÃO chama PosPagamentoService                                            │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Coleções Envolvidas

| Coleção | Path | Uso |
|---------|------|-----|
| `produtos` | `lojas/{lojaId}/produtos` | Catálogo web (live). Lido pelo site. |
| `estoque_produtos` | `lojas/{lojaId}/estoque_produtos` | Fonte de verdade admin/APK. Sync Hive. |
| `draft_produtos` | `lojas/{lojaId}/draft_produtos` | Preview catálogo. |
| `estoque_baixa_pagamento` | `lojas/{lojaId}/estoque_baixa_pagamento/{vendaId}` | Idempotência PosPagamentoService. |
| `_mp_webhook_processed` | `_mp_webhook_processed/{paymentId}` | Idempotência mpWebhook. |
| `estoque_vendas` | `lojas/{lojaId}/estoque_vendas` | Sync vendas APK. |
| `pre_pedidos` | `lojas/{lojaId}/pre_pedidos` | Pedidos catálogo (checkout MP). |
| `pedidos` | `lojas/{lojaId}/pedidos` | Pedidos finalizados. |
| `pedidos_pendentes` | `lojas/{lojaId}/pedidos_pendentes` | Checkout sem pagamento imediato. |

### 2.3 Quem Atualiza O Quê

| Quem | estoque_produtos | produtos |
|------|------------------|----------|
| mpWebhookHandler | ✓ | ✓ |
| EstoqueTransactionService | ✓ | ✗ (apenas remove quando zera) |
| ProdutosFirestoreService.syncProduto | ✓ | ✓ (quando publicado) |
| removerDoCatalogoSeEstoqueZerado | — | Deleta doc se qty=0 |

---

## 3. ARQUIVOS E COLEÇÕES ENVOLVIDOS

### 3.1 Serviços Principais

| Arquivo | Função |
|---------|--------|
| `lib/services/estoque_transaction_service.dart` | Baixa atômica (Firestore transaction). Resolve em estoque_produtos, atualiza estoque_produtos. |
| `lib/services/pos_pagamento_service.dart` | Pós-pagamento: baixa, status pago, número sorte, notificações. Idempotência por estoque_baixa_pagamento. |
| `lib/services/catalogo_venda_service.dart` | registrarVendaCatalogo (baixa + venda), finalizarPedidoComPagamento, criarPedidoPendente. |
| `lib/services/vendas_service.dart` | registrarVendaMulti (baixa + venda APK), desfazerVenda (devolve estoque). |
| `lib/services/estoque_service.dart` | Baixa/devolução manual (usa EstoqueTransactionService para baixa). |
| `functions/src/mpWebhookHandler.js` | Webhook MP: baixa em transação, atualiza produtos + estoque_produtos. |
| `functions/src/posPagamento.js` | **LEGADO** – não usado em produção. |

### 3.2 Telas

| Arquivo | Papel no Fluxo |
|---------|----------------|
| `lib/screens/pre_pedidos_screen.dart` | Chama registrarVendaCatalogo + PosPagamentoService ao confirmar pre_pedido. |
| `lib/screens/public_catalog_screen.dart` | Checkout → PrePedidoService.criarPrePedido (PIX/Cartão). |
| `lib/screens/estoque_screen.dart` | Ajuste manual de estoque. |
| `lib/screens/vendas_screen.dart` | Nova venda, cancelamento. |

### 3.3 Sync / Cache

| Componente | Função |
|------------|--------|
| FirestoreCriticalListenerService | Escuta estoque_produtos → atualiza Hive. |
| CatalogCacheService | Invalida cache ao remover do catálogo. |
| ProdutosFirestoreService | Sync Hive ↔ Firestore (estoque_produtos + produtos). |

---

## 4. PROBLEMAS ENCONTRADOS POR GRAVIDADE

### 4.1 Críticos

| # | Problema | Local | Detalhe |
|---|----------|-------|---------|
| 1 | **Dupla baixa** no fluxo admin confirma pre_pedido | `pre_pedidos_screen.dart` L2279, L2314 | `registrarVendaCatalogo` já baixa; `PosPagamentoService.processarConfirmacaoPagamento` baixa novamente. Estoque é debitado duas vezes. |
| 2 | **produtos (catálogo web) desatualizado** após baixa via app | `estoque_transaction_service.dart` | EstoqueTransactionService atualiza apenas estoque_produtos. Catálogo lê de `produtos`. Usuário pode ver estoque inflado e comprar produto sem estoque. |

### 4.2 Altos

| # | Problema | Local | Detalhe |
|---|----------|-------|---------|
| 3 | **Devolução sem transação** no cancelamento | `vendas_service.dart` L791-833 | `devolverEstoqueCancelamento` atualiza Hive e chama syncProduto; não usa transação. Risco de concorrência. |
| 4 | **mpWebhook vs EstoqueTransaction** usam coleções diferentes | mpWebhookHandler L261-266, estoque_transaction L282 | mpWebhook atualiza `produtos` e `estoque_produtos`; EstoqueTransaction resolve e grava só em `estoque_produtos`. Se produtos e estoque_produtos divergirem (ex.: doc só em um), comportamento inconsistente. |
| 5 | **posPagamento.js legado** ainda no repositório | `functions/src/posPagamento.js` | Baixa sem transação, sem variações completas. Não usado, mas confunde manutenção. |

### 4.3 Médios

| # | Problema | Local | Detalhe |
|---|----------|-------|---------|
| 6 | **Resolução por nome ambígua** | `estoque_transaction_service.dart` L310-328 | Se dois produtos tiverem mesmo nome, lança exceção. Pode bloquear venda. |
| 7 | **Estoque negativo evitado com Math.max(0)** no mpWebhook | `mpWebhookHandler.js` L329, L302 | Permite deduzir até zero; não bloqueia venda com estoque insuficiente (só zera). |
| 8 | **estoque_produtos pode não existir** | `estoque_transaction_service.dart` L454 | try/catch ignora falha ao atualizar estoque_produtos; pode ficar dessincronizado. |

---

## 5. RISCOS OPERACIONAIS

| Risco | Probabilidade | Impacto | Mitigação Atual |
|-------|---------------|---------|-----------------|
| Dupla baixa em pre_pedido confirmado manualmente | Alta | Estoque negativo, itens “fantasma” | Nenhuma |
| Catálogo web mostra estoque maior que o real | Média | Vendas de itens sem estoque | Nenhuma (exceto quando zera e remove) |
| Cancelamento com estoque inconsistente | Baixa | Diferença Hive vs Firestore | syncProduto após devolução |
| Webhook MP duplicado (retry) | Baixa | Dupla baixa | Idempotência por paymentId |
| Produto com variações sem productId no item | Média | Baixa perdida ou erro | Fallback slug/nome |

---

## 6. PLANO DE CORREÇÃO PRIORIZADO

### Fase 1 — Crítico (Imediato)

1. **Eliminar dupla baixa no fluxo admin**
   - Em `pre_pedidos_screen.dart`, ao confirmar pre_pedido:
     - **Opção A:** Remover chamada a `PosPagamentoService.processarConfirmacaoPagamento` e manter apenas `registrarVendaCatalogo` (que já baixa). Chamar só efeitos colaterais (número sorte, notificações) via método dedicado.
     - **Opção B:** Remover a baixa de `registrarVendaCatalogo` nesse fluxo e deixar apenas `PosPagamentoService` fazer a baixa (idempotente).
   - **Recomendação:** Opção B — centralizar baixa no PosPagamentoService para manter idempotência e um único ponto de baixa pós-pagamento.

2. **Atualizar produtos (catálogo) na baixa do app**
   - Em `EstoqueTransactionService.baixarEstoqueTransactionBatch`, após atualizar estoque_produtos, executar update em `produtos` com quantidade, variacoes, estoquePorTamanho (merge), ou chamar `CatalogCacheService` + write em produtos.
   - Ou: criar job/trigger que propague estoque_produtos → produtos quando houver mudança.

### Fase 2 — Alto (1–2 sprints)

3. **Devolução com transação**
   - Criar `EstoqueTransactionService.devolverEstoqueTransaction` (incremento atômico) e usar em `VendasService.devolverEstoqueCancelamento` em vez de Hive + syncProduto.

4. **Unificar fonte de verdade**
   - Definir: estoque_produtos = autoritativo. Garantir que mpWebhookHandler e EstoqueTransactionService sempre escrevam em ambos (produtos + estoque_produtos) com mesmos valores.

5. **Deprecar/remover posPagamento.js**
   - Marcar como deprecated ou mover para pasta `_legacy` com comentário claro.

### Fase 3 — Médio (Backlog)

6. **Resolução por nome**
   - Exigir productId ou slug em itens do catálogo; reduzir dependência de resolução por nome.

7. **Validação estoque no mpWebhook**
   - Antes de deduzir, validar `disponivel >= qty`; se insuficiente, não aprovar e registrar alerta.

8. **Garantir estoque_produtos**
   - Garantir que todo produto em `produtos` tenha doc correspondente em `estoque_produtos` (script de migração ou criação on-demand).

---

## 7. ARQUIVOS IMPACTADOS

### Correções Fase 1

| Arquivo | Alteração |
|---------|-----------|
| `lib/screens/pre_pedidos_screen.dart` | Remover baixa de registrarVendaCatalogo OU remover PosPagamentoService; ajustar fluxo para uma única baixa. |
| `lib/services/catalogo_venda_service.dart` | Se opção B: adicionar parâmetro `skipEstoqueBaixa` em registrarVendaCatalogo quando chamado de pre_pedidos. |
| `lib/services/estoque_transaction_service.dart` | Após transaction, atualizar também `produtos` (merge quantidade/variacoes/estoquePorTamanho). |
| `lib/services/pos_pagamento_service.dart` | Se opção A: extrair método `executarEfeitosPosPagamento` (número sorte, notificações) para chamar sem baixar. |

### Correções Fase 2

| Arquivo | Alteração |
|---------|-----------|
| `lib/services/vendas_service.dart` | Usar devolução atômica em cancelamento. |
| `lib/services/estoque_transaction_service.dart` | Adicionar `devolverEstoqueTransaction`. |
| `functions/src/mpWebhookHandler.js` | Garantir atualização simétrica em produtos e estoque_produtos. |
| `functions/src/posPagamento.js` | Mover para `_legacy/` ou marcar deprecated. |

---

## 8. QUANDO A BAIXA ACONTECE — RESUMO

| Cenário | Momento da baixa | Pagamento exigido? |
|---------|------------------|--------------------|
| PIX/Cartão catálogo web | Webhook MP (status approved) | Sim |
| Admin confirma pre_pedido (dinheiro) | Ao clicar Confirmar | Sim (manual) |
| Nova venda APK | Ao salvar venda | Implícito (dinheiro/PIX na hora) |
| finalizarPedidoComPagamento | Ao finalizar | Sim (gateway ou manual) |
| criarPedidoPendente | Não baixa | Aguarda confirmação |

---

## 9. IMPACTO DE CANCELAMENTO/ESTORNO

- **VendasService.desfazerVenda / devolverEstoqueCancelamento:** Devolve estoque via Hive (`devolverEstoqueVariacao`, `devolverEstoquePorTamanho`, `quantidade +=`) e depois `ProdutosFirestoreService.syncProduto`.
- **Não há fluxo automático de estorno MP** que devolva estoque; seria necessário integração explícita.
- **Risco:** Devolução não é atômica; em concorrência pode haver inconsistência. Recomendado migrar para transação Firestore.

---

*Auditoria baseada no código em 22/03/2025.*

---

## CORREÇÃO FASE 1 APLICADA (22/03/2025)

### FASE 1.1 — Dupla baixa eliminada
- Adicionado parâmetro `baixarEstoque: bool = true` em `registrarVendaCatalogo`.
- Em `pre_pedidos_screen`, chamada com `baixarEstoque: false`.
- Baixa centralizada no `PosPagamentoService.processarConfirmacaoPagamento` (idempotente).

### FASE 1.2 — Propagação estoque_produtos → produtos
- Em `EstoqueTransactionService.baixarEstoqueTransaction` e `baixarEstoqueTransactionBatch`, após atualizar estoque_produtos, aplica o mesmo `updateData` em `produtos` via `transaction.update`.
- Se o doc não existir em produtos (produto não publicado no catálogo), o update falha e é ignorado (try/catch).
