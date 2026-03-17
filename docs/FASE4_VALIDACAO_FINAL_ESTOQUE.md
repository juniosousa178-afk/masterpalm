# FASE 4 — Validação final e caça de regressões do estoque

**Objetivo:** Validar o que foi implementado na FASE 3, identificar riscos residuais e regressões, sem refatorar.

---

## 1. VALIDAÇÃO GERAL DA FASE 3

### 1.1 Pós-pagamento (`pos_pagamento_service.dart`)

| Verificação | Evidência no código | Resultado |
|-------------|---------------------|-----------|
| Baixa acontece antes da atualização de status | L66-68: `if (baixaJaAplicada)` → else → `await _baixarEstoque(lojaId, items)` (L81); L98-99: `_atualizarStatusVenda` só é chamado **depois** do bloco if/else (após baixa ou após detectar idempotência) | ✅ Ordem correta |
| Falha na baixa impede marcação de "pago" | Se `_baixarEstoque` lançar, a exceção propaga; o catch em L140-145 retorna false e **não** executa _atualizarStatusVenda (que está após o await da baixa) | ✅ Correto |
| Idempotência consultada antes da baixa | L60-68: `baixaRef.get()` e `baixaJaAplicada` antes de qualquer baixa; se true, pula o else inteiro (não chama _baixarEstoque) | ✅ OK |
| Idempotência gravada apenas após baixa bem-sucedida | L83-91: `baixaRef.set({ baixaAplicada: true, ... })` só é executado **dentro** do else, **após** `await _baixarEstoque(lojaId, items)` sem exceção | ✅ OK |
| Retorno false chega ao caller | Assinatura `Future<bool>`; em catch retorna `false` (L145); único caller é pre_pedidos_screen que guarda em `posPagamentoOk` e trata (L2406, L2424-2432) | ✅ OK |
| Efeitos colaterais só após a baixa | L98-136: _atualizarStatusVenda, número da sorte, campanha, roleta, notificações — todos vêm **depois** do bloco if/else da baixa; se baixa lançar, nenhum deles executa | ✅ OK |

**Risco encontrado durante validação:** Quando `_baixarEstoque` encontra zero itens válidos (ex.: todos sem productId), fazia apenas `return` (L220-225 antigo). O fluxo continuava, gravava o marcador e marcava "pago" sem ter debitado estoque. **Correção aplicada:** substituído `return` por `throw Exception(...)` para que o processamento falhe e retorne false; o marcador não é gravado e o status não é atualizado.

### 1.2 Resolução de produto (`estoque_transaction_service.dart`)

| Verificação | Evidência no código | Resultado |
|-------------|---------------------|-----------|
| Busca por nome ambíguo falha | L266-276: `limit(2)`; se `nomeSnap.docs.length > 1` → log [ESTOQUE_VARIACAO] e `throw Exception(...)` com mensagem orientando id/slug | ✅ Falha explícita |
| Não existe fallback silencioso que escolha produto errado | Ordem: produtoId → slug → nome; por nome só retorna ref se `docs.length == 1`; se 0, retorna null (quem chama recebe e pode lançar "produto não encontrado") | ✅ Nenhum fallback perigoso |
| Comportamento id/slug/nome coerente | produtoId: doc direto e exists; slug: limit(1); nome: limit(2) e falha se >1 | ✅ OK |

### 1.3 Estoque Service (`estoque_service.dart`)

| Verificação | Evidência no código | Resultado |
|-------------|---------------------|-----------|
| Sync manual deixou de duplicar escrita | L546-574: apenas `update` em estoque_produtos e, se publicado, em produtos; **não** há chamada a `ProdutosFirestoreService.syncProduto` (removida na FASE 3) | ✅ Uma escrita por coleção |
| Não há outro ponto repetindo sync redundante neste fluxo | _sincronizarComFirestore é chamado a partir de fluxos de ajuste (ex.: entrada de estoque); nenhum outro trecho no mesmo método chama syncProduto | ✅ OK |
| Comentário coerente com o comportamento | L531-533: "Fonte autoritativa ... Baixas de venda devem passar por EstoqueTransactionService; este método é voltado a ajustes manuais." | ✅ OK |

### 1.4 Caller / UI (`pre_pedidos_screen.dart`)

| Verificação | Evidência no código | Resultado |
|-------------|---------------------|-----------|
| Tela trata retorno false | L2406: `final posPagamentoOk = await PosPagamentoService.processarConfirmacaoPagamento(...)`; L2424-2432: `if (posPagamentoOk)` sucesso, `else` _showModernSnackBar(..., isError: true) | ✅ OK |
| Mensagem não induz ao erro | Texto em false: "Pagamento confirmado, mas houve falha ao processar o pós-pagamento (baixa de estoque ou notificações). Tente novamente." — deixa claro que algo falhou e sugere retry | ✅ OK |
| Outro caller ignorando retorno | Grep: único uso de processarConfirmacaoPagamento é em pre_pedidos_screen | ✅ Nenhum outro caller |

---

## 2. O QUE FOI REALMENTE RESOLVIDO

| Item | Arquivo / bloco | Classificação | Evidência |
|------|------------------|----------------|-----------|
| Confirmação de pagamento sem baixa de estoque | pos_pagamento_service.dart L79-99 | **RESOLVIDO** | Baixa é executada antes de _atualizarStatusVenda; falha na baixa propaga e retorna false; marcador só gravado após baixa bem-sucedida |
| Dupla baixa no pós-pagamento (retry) | pos_pagamento_service.dart L60-68, L83-91 | **RESOLVIDO** | Coleção estoque_baixa_pagamento/{vendaId}; se baixaAplicada==true, nova baixa não é executada |
| Baixa no produto errado por nome duplicado | estoque_transaction_service.dart L266-276 | **RESOLVIDO** | Mais de um doc com mesmo nome → Exception; não escolhe o primeiro |
| Overwrite por sync manual redundante | estoque_service.dart _sincronizarComFirestore | **RESOLVIDO** | Removida segunda escrita via syncProduto; uma única atualização em estoque_produtos e produtos |
| Caller não tratar falha do pós-pagamento | pre_pedidos_screen.dart L2424-2432 | **RESOLVIDO** | posPagamentoOk false → SnackBar de erro com isError: true |
| Caso "nenhum item válido" ainda marcar pago | pos_pagamento_service.dart _baixarEstoque | **RESOLVIDO** (na FASE 4) | txItems.isEmpty agora lança Exception em vez de return; processo falha e não marca pago |

---

## 3. O QUE FOI APENAS MITIGADO

| Item | Motivo | Classificação |
|------|--------|----------------|
| Ajuste manual sobrescrevendo saldo pós-venda | _sincronizarComFirestore ainda aplica estado do Produto local ao Firestore; se o local estiver desatualizado (ex.: outra aba fez venda), o ajuste pode sobrescrever o saldo correto. Comportamento documentado; não há bloqueio por "última origem" | **MITIGADO** |
| Idempotência cobre só a baixa; status/notificações reexecutam no retry | No retry com marcador já existente, _atualizarStatusVenda, número da sorte, roleta e notificações são chamados de novo. Evita dupla baixa; pode gerar segundo número da sorte ou segundo envio de notificação | **MITIGADO** (aceitável: dupla baixa era o risco crítico) |
| Catálogo (produtos) após baixa | removerDoCatalogoSeEstoqueZerado + atualizarHiveAposTransacao mantêm coerência; atualização explícita em produtos (catálogo) ocorre na transação/sync. Janela de inconsistência é apenas o tempo até a próxima leitura do catálogo | **MITIGADO** |

---

## 4. O QUE AINDA ESTÁ ABERTO

| Item | Evidência / contexto | Classificação |
|------|----------------------|---------------|
| Fluxos que identificam produto só por nome em produção | Se existirem pedidos/vendas antigos ou integrações que enviam apenas nome, passarão a falhar após endurecimento da resolução (mais de um produto com mesmo nome). Não há varredura de todos os callers de baixa para garantir que sempre há productId/slug | **AINDA ABERTO** (risco operacional se houver homonímia real) |
| Web: Hive atrasado após refresh | No Web, Hive (IndexedDB) pode não ter sido atualizado após uma venda em outra aba; a próxima operação que use apenas dados locais pode ver estado antigo. Firestore permanece correto; sync Firestore→Hive e atualizarHiveAposTransacao reduzem o risco | **NÃO CONFIRMADO** (sem evidência de bug em produção) |

---

## 5. RISCOS DE REGRESSÃO ENCONTRADOS

| Risco | Verificação | Resultado |
|-------|-------------|-----------|
| Reordenar baixa antes de status quebrar algo | Nenhum código assume que status já está "pago" antes da baixa no mesmo método; chamador não depende dessa ordem | ✅ Nenhuma regressão |
| _baixarEstoque lançar exceção quebra caller | Caller é processarConfirmacaoPagamento (try/catch retorna false); não há outro caller direto de _baixarEstoque | ✅ OK |
| Resolução por nome falhar com 2+ produtos quebra fluxos | Fluxos que enviam productId ou slug continuam funcionando; só quebram quando há homonímia e apenas nome é enviado | ⚠️ Comportamento esperado; pode exigir configuração (slug/id) em lojas com nomes duplicados |
| Remover syncProduto de _sincronizarComFirestore | Ajuste manual continua atualizando estoque_produtos e produtos (catálogo) via update direto; uma única escrita por destino | ✅ Nenhuma regressão |
| Lançar quando txItems.isEmpty | Agora falha de forma visível em vez de marcar pago sem baixa; mensagem orienta o motivo | ✅ Melhoria; sem regressão |

---

## 6. MAPA RESIDUAL DE RISCOS

### A. Idempotência

- **Proteção:** Apenas a **baixa** é protegida: se o marcador existe, _baixarEstoque não é chamado.
- **Retry:** Status da venda, número da sorte, roleta e notificações **são reexecutados** em cada chamada (inclusive quando baixa já estava aplicada).
- **Avaliação:** Evitar dupla baixa era o objetivo; reexecutar notificações/status é aceitável e não introduz risco de estoque incorreto.

### B. Ajuste manual

- **Caminho que pode sobrescrever saldo:** EstoqueService._sincronizarComFirestore lê o Produto do Hive e faz update em estoque_produtos. Se esse Produto estiver desatualizado (ex.: venda em outra sessão já debitou no Firestore), o update sobrescreve com valor antigo.
- **Relevância:** Teórica se o usuário só ajustar na mesma sessão após sync; operacionalmente relevante se houver uso concorrente (duas abas, dois dispositivos) sem novo sync antes do ajuste.

### C. Catálogo

- **Após a baixa:** removerDoCatalogoSeEstoqueZerado remove doc do catálogo quando estoque zera; atualizarHiveAposTransacao atualiza Hive. A transação já atualiza estoque_produtos; não há escrita dupla no catálogo no fluxo de baixa.
- **Janela:** Entre a transação e a próxima leitura do catálogo pelo cliente, a consistência é a mesma de antes; não há nova janela introduzida pela FASE 3.

### D. Web x APK

- **Lógica:** PosPagamentoService, EstoqueTransactionService e EstoqueService não usam kIsWeb/Platform para diferenciar fluxo de estoque; mesma ordem de operações e mesmas coleções.
- **Comportamento:** Web e APK compartilham o mesmo código de baixa, idempotência e resolução; não há divergência conhecida.

### E. Homonímia

- **Falhar por nome duplicado:** Resolve o risco de baixa no produto errado.
- **Fluxos que dependem só de nome:** Vendas manuais e catálogo enviam productId/slug quando disponível; o pós-pagamento usa items com productId (pre_pedidos_screen monta itensParaVenda com id do produto). Se em algum fluxo só o nome for enviado e houver dois produtos com mesmo nome, o sistema falha com mensagem clara — preferível a baixar no errado.

---

## 7. CENÁRIOS LÓGICOS (RESULTADO ESPERADO)

| Cenário | Fluxo no código | Resultado esperado |
|---------|------------------|--------------------|
| **1. Pós-pagamento com sucesso** | baixaJaAplicada false → _baixarEstoque → baixaRef.set(baixaAplicada: true) → _atualizarStatusVenda → número da sorte → roleta → notificações → return true | Baixa aplicada; marcador gravado; status "pago"; efeitos colaterais executados; caller mostra sucesso |
| **2. Pós-pagamento com falha de estoque** | _baixarEstoque lança (ex.: produto não encontrado, estoque insuficiente, nome ambíguo, ou txItems.isEmpty com throw) → catch → return false; _atualizarStatusVenda não é chamado; marcador não é gravado | Caller recebe false; UI mostra SnackBar de erro; status não vira "pago"; estoque não alterado |
| **3. Retry do mesmo vendaId** | baixaSnap.exists e baixaAplicada==true → não entra no else → não chama _baixarEstoque → segue para _atualizarStatusVenda, número da sorte, roleta, notificações → return true | Baixa não reaplicada; status/notificações podem rodar de novo; sem dupla baixa |
| **4. Dois produtos com mesmo nome** | Item com só nome → _resolverProdutoRef por nome → query limit(2) retorna 2 docs → throw Exception | Falha explícita; nenhuma baixa; mensagem orienta uso de id/slug |
| **5. Ajuste manual após venda recente** | Usuário abre tela de estoque (Hive com estado antigo), altera quantidade, chama _sincronizarComFirestore → update(estoque_produtos, updateData do Produto local) | Se o local não foi atualizado (ex.: sem sync após venda em outra aba), o saldo no Firestore pode ser sobrescrito pelo valor antigo — risco residual documentado |
| **6. Web com refresh / sync posterior** | Firestore correto; Hive pode estar atrasado. Próxima abertura de tela ou sync Firestore→Hive (ex.: EstoqueScreen "puxar", VendasScreen _syncEmBackground) atualiza Hive. Baixas seguem sendo feitas na transação no Firestore. | Recuperação sem corromper saldo: fonte autoritativa é Firestore; Hive é atualizado por sync ou por atualizarHiveAposTransacao após cada baixa bem-sucedida |

---

## 8. AJUSTES PEQUENOS E SEGUROS (aplicados e sugeridos)

**Aplicado na validação (FASE 4):**

1. **pos_pagamento_service.dart — _baixarEstoque quando txItems.isEmpty**  
   - Antes: `return` (fluxo seguia e marcava pago sem baixa).  
   - Depois: `throw Exception('Nenhum item válido para baixa de estoque ...')` para falhar de forma visível e não marcar pago.  
   - **Risco:** Nenhum. **Benefício:** Fecha o caso "todos os itens sem productId".

**Sugeridos (opcionais):**

2. **pos_pagamento_service.dart — log no catch**  
   - No catch de processarConfirmacaoPagamento, logar `e` e `st` (stack trace) em debug para facilitar diagnóstico quando retornar false.

3. **estoque_transaction_service.dart — tag no log de ambiguidade**  
   - Garantir que o log de nome ambíguo use a tag [ESTOQUE_VARIACAO] de forma consistente (já usa no código atual).

4. **estoque_service.dart — comentário sobre concorrência**  
   - Uma linha em _sincronizarComFirestore: "Em uso concorrente (várias abas/dispositivos), faça sync Firestore→Hive antes de ajustar para evitar sobrescrever saldo atual."

5. **pre_pedidos_screen — botão "Tentar novamente"**  
   - Quando posPagamentoOk for false, além do SnackBar, considerar exibir um botão "Tentar novamente" que reexecute o mesmo fluxo de confirmação (já possível se o usuário reabrir a ação). Opcional e pode ser feito em MR separado.

---

## 9. VEREDITO FINAL

### O problema principal do estoque pode ser considerado resolvido?

**Sim.**

- **Pagamento confirmado sem baixa:** Resolvido — baixa é feita antes de marcar "pago"; falha na baixa (incluindo "nenhum item válido") faz o método falhar e retornar false; status não é atualizado.
- **Dupla baixa no pós-pagamento:** Resolvido — idempotência por estoque_baixa_pagamento/{vendaId}; em retry a baixa não é reaplicada.
- **Baixa no produto errado por nome ambíguo:** Resolvido — mais de um produto com mesmo nome gera Exception; não se escolhe mais o primeiro.
- **Overwrite de saldo correto por sync redundante:** Resolvido — remoção da chamada duplicada a syncProduto em _sincronizarComFirestore; ajuste manual continua com um único update por destino; risco de overwrite por estado local desatualizado permanece mitigado por documentação.
- **Divergência Web ↔ APK:** Nenhuma introduzida; mesma lógica em ambas as plataformas.
- **Inconsistência estoque_produtos / produtos / Hive / UI:** Fluxo de baixa mantém transação em estoque_produtos, atualização de Hive e remoção/atualização no catálogo quando aplicável; UI do pós-pagamento reflete falha quando o retorno é false.

**Causas residuais** (homonímia em produção exigindo id/slug, ajuste manual concorrente) são conhecidas e mitigadas ou documentadas; não impedem considerar o problema principal resolvido para release.

**Recomendação:** Considerar o problema principal do estoque **resolvido** para efeito de release; manter monitoramento pelos logs com tags [ESTOQUE_BAIXA], [ESTOQUE_VARIACAO], [ESTOQUE_WRITE], [HIVE_BOX] e aplicar os ajustes opcionais da seção 8 se desejado.
