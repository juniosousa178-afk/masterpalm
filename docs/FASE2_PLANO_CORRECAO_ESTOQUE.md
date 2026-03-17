# FASE 2 — Plano de correção do estoque

**Objetivo:** Priorizar causas da FASE 1 e definir plano seguro de correção, sem implementar ainda. Foco em evitar baixa perdida, dupla baixa, overwrite de estoque correto, baixa em produto/variação errada e divergência entre catálogo, pedido, Hive e Firestore.

---

## 1. PRIORIZAÇÃO DAS CAUSAS

| Causa | Classificação | Justificativa (FASE 1) |
|-------|----------------|------------------------|
| **PosPagamentoService:** confirmação de pagamento antes da baixa; status "pago" gravado antes de `_baixarEstoque`; `_baixarEstoque` com catch que não relança → pedido pode ficar "pago" com estoque intacto | **CRÍTICO IMEDIATO** | Comportamento confirmado no código: ordem atual é (1) _atualizarStatusVenda, (2) _baixarEstoque; falha na baixa não propaga e o método pode retornar true |
| **PosPagamentoService:** risco de dupla baixa se o mesmo pedido for reprocessado (ex.: retry do gateway) sem idempotência | **CRÍTICO IMEDIATO** | Não há hoje verificação de "já baixado" por vendaId/pedidoId antes de chamar baixarEstoqueTransactionBatch |
| **Resolução de produto (id/slug/nome):** busca por nome pode retornar produto errado se houver homonímia na mesma loja | **ALTO** | _resolverProdutoRef usa nome como fallback; primeiro match por nome é usado |
| **EstoqueService._sincronizarComFirestore:** atualiza estoque_produtos/produtos a partir do Produto local e ainda chama syncProduto → risco de overwrite de saldo já corrigido por transação de venda | **ALTO** | Qualquer ajuste manual que altere quantidade local e depois chame esse fluxo pode sobrescrever o Firestore; dupla escrita (update + syncProduto) é redundante e aumenta risco |
| **Ajustes manuais de estoque:** fluxos que alteram Produto.quantidade (ou variações) localmente e sincronizam sem passar por transação | **ALTO** | Podem sobrescrever saldo que já foi debitado por venda/catálogo em outro dispositivo ou sessão |
| **Relação estoque_produtos vs produtos (catálogo):** atraso ou falha ao espelhar quantidade/variacoes no catálogo após baixa ou sync | **MÉDIO** | Já existe removerDoCatalogoSeEstoqueZerado e syncProduto atualiza produtos se publicado; falhas silenciosas no update do catálogo podem deixar disponibilidade errada |
| **Produto com variações:** falta documentação explícita de que quantidade é derivada (soma) e que escritas fora da transação devem manter consistência | **MÉDIO** | Código já recalcula quantidade na transação; risco é fluxos paralelos escrevendo só quantidade ou só variacoes |
| **ExcelImportService / boxes genéricas:** uso de 'estoque', 'vendas', 'clientes' sem lojaId; possível uso em produção | **BAIXO** | FASE 1 indicou uso provável apenas em migração; impacto no estoque atual é indireto |
| **MovimentacaoEstoqueService.registrar** falhando em silêncio (catch só log) | **BAIXO** | Não altera saldo; só histórico; aceitável como não bloqueante, mas pode ser logado de forma rastreável |

---

## 2. ORDEM IDEAL DE CORREÇÃO

1. **PosPagamentoService (baixa antes de status + falha visível)**  
   - Garante que nenhum pedido seja marcado "pago" sem baixa efetiva.  
   - Reduz risco de dupla baixa ao permitir, em seguida, idempotência por vendaId.

2. **Idempotência da baixa no pós-pagamento**  
   - Evita dupla baixa em retentativas (gateway, usuário).  
   - Depende de um critério estável (ex.: vendaId + flag ou registro de "baixa já feita").

3. **EstoqueService._sincronizarComFirestore e ajustes manuais**  
   - Definir quando é seguro escrever em estoque_produtos a partir do local (ex.: apenas em telas de ajuste explícito, com confirmação).  
   - Evitar que sync "cego" sobrescreva saldo correto após vendas.

4. **Resolução de produto em EstoqueTransactionService**  
   - Priorizar sempre produtoId (idFirebase); slug como segundo critério; nome só quando inevitável e, se possível, com aviso ou confirmação em cenários ambíguos.  
   - Pode ser feita em conjunto com a documentação de fonte autoritativa.

5. **Documentação e regras claras (fonte autoritativa, catálogo, variações)**  
   - Reduz erros futuros e facilita revisões.  
   - Incluir comentários em ProdutosFirestoreService, EstoqueTransactionService e EstoqueService.

6. **Tratamento de erros silenciosos (logs, retry, UI)**  
   - PosPagamentoService já tratado no item 1; outros catches podem ganhar log estruturado e, onde fizer sentido, retry ou feedback ao usuário.

A ordem evita primeiro o cenário "pago sem baixa" e "dupla baixa", depois protege contra overwrite e ambiguidade de produto, e por fim endurece consistência e observabilidade.

---

## 3. ARQUIVOS QUE DEVEM SER ALTERADOS

| Arquivo | Motivo da alteração |
|---------|----------------------|
| **lib/services/pos_pagamento_service.dart** | Reordenar: baixar estoque antes de atualizar status; fazer _baixarEstoque relançar em falha (ou retornar bool e tratar no caller); considerar idempotência por vendaId/pedidoId para evitar dupla baixa. |
| **lib/services/estoque_transaction_service.dart** | Endurecer resolução: preferir produtoId; se usar nome, logar aviso quando houver mais de um produto com mesmo nome na loja; opcionalmente retornar erro se busca por nome retornar múltiplos. Documentar em comentário: estoque_produtos é fonte autoritativa; quantidade/variações/estoquePorTamanho atualizados apenas via transação. |
| **lib/services/estoque_service.dart** | Revisar _sincronizarComFirestore: evitar sobrescrever estoque quando a origem da alteração for "após venda" (ex.: só permitir sync explícito a partir de tela de ajuste/entrada); remover ou condicionar a segunda chamada a syncProduto para não duplicar escrita. Documentar que ajustes manuais devem ser a única fonte quando esse método for usado. |
| **lib/services/produtos_firestore_service.dart** | Comentário no topo ou em syncProduto/syncFirestoreToHive: fonte autoritativa de estoque é estoque_produtos; quantidade e variacoes/estoquePorTamanho devem ser alterados preferencialmente via EstoqueTransactionService; syncProduto reflete estado do Hive no Firestore (usar com cuidado após vendas). |
| **lib/screens/pre_pedidos_screen.dart** (ou ponto de chamada do pós-pagamento) | Tratar retorno false de processarConfirmacaoPagamento: não mostrar sucesso; permitir "Tentar novamente" ou marcar pedido como "pendente de baixa" conforme decisão de produto. |
| **docs/** (novo ou existente) | Documento curto de arquitetura de estoque: fluxos de baixa (manual, catálogo, pós-pagamento), fonte autoritativa, idempotência pós-pagamento, e relação estoque_produtos ↔ produtos (catálogo). |

Nenhum outro arquivo precisa ser alterado para as correções de alta confiança listadas abaixo; ajustes em limites_guard, firestore_critical_listener_service ou catalogo_sync_service ficam para fase posterior se necessário.

---

## 4. CORREÇÕES COM ALTA CONFIANÇA (para a FASE 3)

- **PosPagamentoService — ordem e falha explícita**  
  - Em `processarConfirmacaoPagamento`: executar **primeiro** `_baixarEstoque(lojaId, items)`.  
  - Fazer `_baixarEstoque` **relançar** a exceção em caso de erro (remover o catch que só faz debugPrint e não relança).  
  - Só após sucesso da baixa: chamar `_atualizarStatusVenda`, número da sorte, roleta, notificações.  
  - Se _baixarEstoque lançar, o catch externo de processarConfirmacaoPagamento continua retornando false (já existe).  
  - **Efeito:** pedido não é marcado "pago" se a baixa falhar; chamador pode tratar false e exibir "Tente novamente" ou similar.

- **PosPagamentoService — nenhuma operação após falha de baixa**  
  - Garantir que, em caso de exceção em _baixarEstoque, não se chame _atualizarStatusVenda nem notificações (já garantido ao reordenar e relançar).

- **Resolução de produto — prioridade e aviso**  
  - Em `_resolverProdutoRef`: manter ordem 1) produtoId, 2) slug, 3) nome.  
  - Na busca por nome: se a query retornar mais de um documento, **não** escolher o primeiro; logar e retornar null (ou lançar com mensagem "vários produtos com mesmo nome; use id ou slug").  
  - **Efeito:** reduz risco de baixa em produto errado por homonímia.

- **Documentação em código (fonte autoritativa)**  
  - Em `EstoqueTransactionService`: comentário no topo da classe ou em `baixarEstoqueTransaction`: "Fonte autoritativa de saldo: lojas/{lojaId}/estoque_produtos. quantidade é o total; variacoes e estoquePorTamanho são detalhes por tamanho/cor. Atualizações de baixa devem ser feitas apenas via transação aqui."  
  - Em `ProdutosFirestoreService.syncProduto`: uma linha explicando que grava estado do Hive no Firestore e que não deve ser usado para "corrigir" estoque após venda sem refletir o resultado da transação.

- **pre_pedidos_screen (ou caller) — tratar false**  
  - Onde chama `processarConfirmacaoPagamento`: se retornar false, não exibir mensagem de sucesso; exibir erro e, se possível, botão "Tentar novamente" que reexecuta o processamento.  
  - Garante que o usuário não ache que o pagamento foi confirmado quando a baixa falhou.

---

## 5. CORREÇÕES QUE EXIGEM COMPATIBILIDADE TEMPORÁRIA

- **Idempotência da baixa no pós-pagamento**  
  - **Cenário:** mesmo pedido confirmado duas vezes (retry, duplo clique, reenvio do webhook).  
  - **Proposta:** antes de chamar `baixarEstoqueTransactionBatch` no PosPagamentoService, verificar se já existe registro de "baixa feita" para aquele `lojaId + vendaId` (ex.: campo no doc da venda no Firestore, ou subcoleção `baixas_estoque` com doc vendaId). Se já existir, pular a baixa e continuar o fluxo (status, notificações).  
  - **Compatibilidade:** pedidos antigos não terão o campo; na primeira execução após o deploy, "baixa feita" não existe → executa baixa e grava o marcador. Não exige migração em massa; apenas novos processamentos passam a escrever/ler o marcador.

- **EstoqueService._sincronizarComFirestore**  
  - **Cenário:** hoje é usado em telas de ajuste/entrada de estoque; não deve sobrescrever saldo que veio de uma venda processada em outro lugar.  
  - **Proposta:** não remover a funcionalidade de uma vez. Opções: (a) adicionar parâmetro explícito `origem: 'ajuste_manual'` e só então permitir escrita em estoque_produtos; (b) ou manter o fluxo atual mas documentar que "ajustes manuais devem ser feitos com cuidado e preferencialmente após sync Firestore→Hive".  
  - **Compatibilidade:** não mudar assinaturas de chamadas existentes na FASE 3; apenas comentários e, se possível, uma verificação leve (ex.: só chamar syncProduto uma vez, removendo a chamada duplicada).

- **Relação estoque_produtos ↔ produtos (catálogo)**  
  - **Cenário:** catálogo lê de `produtos` ou cache; estoque real está em `estoque_produtos`; após baixa, ambos devem estar alinhados.  
  - **Proposta:** manter o comportamento atual (transação atualiza estoque_produtos; syncProduto e removerDoCatalogoSeEstoqueZerado atualizam/removem do catálogo). Para FASE 3, apenas garantir que, no PosPagamentoService, após baixa bem-sucedida, `removerDoCatalogoSeEstoqueZerado` e atualização Hive já sejam chamados (já são). Opcional: log estruturado quando o update em `produtos` falhar (já existe try/catch em ProdutosFirestoreService).  
  - **Compatibilidade:** nenhuma mudança de contrato; apenas observabilidade.

- **Produto com variações — consistência pai/variação**  
  - **Cenário:** qualquer escrita fora da transação que altere só `quantidade` ou só `variacoes` pode gerar inconsistência.  
  - **Proposta:** na FASE 3, não alterar a lógica de escrita; documentar que "para produtos com variações, quantidade deve ser a soma das variações; alterações devem preferir EstoqueTransactionService ou, em ajuste manual, atualizar variacoes/estoquePorTamanho e recalcular quantidade (ex.: produto.recalcularQuantidadeTotal()) antes de sync".  
  - **Compatibilidade:** coexistência de ajustes manuais e transacionais; regra clara evita overwrite incorreto em implementações futuras.

---

## 6. RISCOS DE REGRESSÃO POR ALTERAÇÃO

| Correção | O que pode quebrar | Mitigação | Como validar |
|----------|--------------------|-----------|---------------|
| Reordenar PosPagamentoService (baixa antes de status) | Nenhum; apenas ordem lógica muda. Chamador já trata retorno bool. | Deploy em sequência: primeiro reordenar e relançar; depois (se quiser) idempotência. | Testar: simular falha na baixa (produto inexistente ou estoque zero) e confirmar que status não vira "pago" e que retorno é false. |
| _baixarEstoque relançar exceção | Callers que esperavam sempre sucesso e não tratam exceção. Hoje o único caller é processarConfirmacaoPagamento, que tem try/catch e retorna false. | Não há outro caller direto de _baixarEstoque. | Grep por _baixarEstoque e processarConfirmacaoPagamento; teste E2E: pagamento com item inválido deve mostrar erro e não "pago". |
| Resolução por nome: falhar se múltiplos | Vendas ou pedidos que hoje dependem de match por nome quando há dois produtos com mesmo nome podem passar a falhar. | Comportamento mais seguro: falhar e pedir correção (id/slug) é preferível a baixar no produto errado. | Testar com dois produtos mesmo nome na mesma loja: deve falhar com mensagem clara; com id ou slug deve funcionar. |
| EstoqueService: remover segunda chamada a syncProduto em _sincronizarComFirestore | Se a primeira escrita (update em estoque_produtos) falhar e a segunda (syncProduto) fosse a que aplicava, poderia haver diferença. Na prática syncProduto faz set completo; o update já reflete o mesmo estado. | Manter uma única escrita "completa": ou só update de campos de estoque + update catálogo, ou só syncProduto. Preferir syncProduto uma vez para não duplicar lógica. | Após ajuste manual na tela de estoque, verificar no Firestore que estoque_produtos e (se publicado) produtos foram atualizados uma vez e com valor correto. |
| pre_pedidos_screen tratar false | Se hoje em algum caso false não é exibido, usuário pode não ver diferença. | Garantir que em false sempre haja SnackBar ou diálogo de erro e opção de tentar novamente. | Simular falha (rede off ou produto inexistente) e confirmar que a UI mostra erro e não sucesso. |

---

## 7. PLANO DE IMPLEMENTAÇÃO DA FASE 3

- **Passo 1 — PosPagamentoService: ordem e falha explícita**  
  - Em `processarConfirmacaoPagamento`, mover a chamada `_baixarEstoque(lojaId, items)` para **antes** de `_atualizarStatusVenda`.  
  - Em `_baixarEstoque`, remover o catch que engole a exceção (ou no catch relançar com `rethrow`).  
  - Deixar o try/catch externo de `processarConfirmacaoPagamento` retornando false em caso de exceção.  
  - Verificar que nenhum código entre baixa e atualização de status depende de status já estar "pago".

- **Passo 2 — Chamador do pós-pagamento**  
  - No ponto que chama `processarConfirmacaoPagamento` (ex.: pre_pedidos_screen): se retorno for false, exibir mensagem de erro e oferecer "Tentar novamente" (rechamada do mesmo método).  
  - Garantir que mensagem de sucesso só apareça quando retorno for true.

- **Passo 3 — Resolução de produto (EstoqueTransactionService)**  
  - Em `_resolverProdutoRef`, na busca por nome: usar `limit(2)` (ou get e verificar length). Se `docs.length > 1`, logar e retornar null (ou lançar Exception com texto explicativo).  
  - Manter ordem produtoId → slug → nome.

- **Passo 4 — Documentação em código**  
  - Adicionar comentário no topo de `EstoqueTransactionService` (ou no método de baixa): fonte autoritativa é estoque_produtos; quantidade/variações/estoquePorTamanho; baixa apenas via transação.  
  - Adicionar uma linha em `ProdutosFirestoreService.syncProduto`: não usar para sobrescrever estoque após venda sem refletir resultado da transação.

- **Passo 5 — EstoqueService._sincronizarComFirestore**  
  - Remover a segunda chamada a `ProdutosFirestoreService.syncProduto` no final de _sincronizarComFirestore (manter apenas o update em estoque_produtos e em produtos quando publicado).  
  - Ou: manter uma única chamada a syncProduto e remover os updates manuais anteriores, para não duplicar lógica. (Recomendação: manter update direto de estoque + catálogo e remover a chamada extra a syncProduto.)  
  - Adicionar comentário: "Usado para ajustes manuais; não usar para refletir vendas (já feitas via EstoqueTransactionService)."

- **Passo 6 (opcional na FASE 3) — Idempotência pós-pagamento**  
  - Antes de chamar `baixarEstoqueTransactionBatch` em _baixarEstoque, verificar se a venda já teve baixa registrada (ex.: doc em lojas/{lojaId}/vendas_controle/{vendaId} com campo baixaEstoqueEm, ou campo na venda).  
  - Se já registrado, pular baixa e prosseguir com atualização de status e notificações.  
  - Se não, executar baixa e gravar o marcador.  
  - Requer definir onde armazenar o marcador (Firestore ou Hive) e migração suave para vendas antigas (ausência do marcador = executar baixa).

- **Passo 7 — Validação e testes**  
  - Cenário 1: Pre-pedido → confirmar pagamento com item válido → deve marcar pago e baixar estoque; Hive e Firestore alinhados.  
  - Cenário 2: Pre-pedido → falha na baixa (ex.: produto removido) → não deve marcar pago; retorno false; UI mostra erro e "Tentar novamente".  
  - Cenário 3: Dois produtos com mesmo nome → venda/pedido que identifica só por nome deve falhar com mensagem clara (após passo 3).  
  - Cenário 4: Ajuste manual de quantidade na tela de estoque → sync deve atualizar Firestore uma vez, sem overwrite de venda recente (teste manual em dois dispositivos se possível).

---

**Regras finais do plano**

- Manter a regra **"baixa antes de venda/pedido"** em VendasService e CatalogoVendaService; no pós-pagamento, **baixa antes de marcar "pago"**.  
- **PosPagamentoService:** bloquear confirmação (não marcar pago) se a baixa falhar; retorno false e UI com "Tentar novamente"; opcionalmente idempotência por vendaId para evitar dupla baixa.  
- **Dupla baixa:** mitigar com idempotência no pós-pagamento (passo 6); em outros fluxos não há reprocessamento da mesma venda.  
- **Resolução:** endurecer com produtoId > slug > nome e falhar quando nome for ambíguo.  
- **Overwrite:** evitar sync que sobrescreve saldo correto documentando e removendo chamada duplicada em EstoqueService.  
- **Fonte autoritativa:** documentar em código estoque_produtos, quantidade, variacoes, estoquePorTamanho.  
- **Catálogo:** manter atualização após baixa (removerDoCatalogoSeEstoqueZerado + sync quando publicado); sem mudança de contrato.  
- **Web e APK:** mesmos serviços e ordem de operações; sem branch por plataforma nas correções.  
- **Erros:** pós-pagamento deixa de ser silencioso (relançar); caller exibe erro; demais logs podem ser melhorados em fase posterior.

Este plano é técnico, orientado a produção e focado em eliminar risco real de estoque incorreto sem refatoração desnecessária.
