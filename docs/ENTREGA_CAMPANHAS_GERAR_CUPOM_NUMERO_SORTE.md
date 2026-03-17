# Entrega: Alinhamento gerarCupomNumeroSorte → campanhas_sorteio

**Data:** 2025-03-06  
**Escopo:** Corrigir risco de cupom/número da sorte ser registrado na coleção errada (`campanhas` em vez de `campanhas_sorteio`).  
**Restrições:** Sem refatorar o sistema; não quebrar promoções ativas; não mexer em fluxos de pedido estáveis.

---

## 1. Diagnóstico resumido

- **Problema:** A Cloud Function `gerarCupomNumeroSorte` (e a implementação equivalente em `index.js`) lia e escrevia em `lojas/{lojaId}/campanhas`. O restante do sistema (app Flutter, posPagamento, campanhas_sorteio_service, numero_sorte_service, etc.) usa **`lojas/{lojaId}/campanhas_sorteio`** e a subcoleção `participantes`. Com isso, o número da sorte era registrado numa coleção que não é a usada nas telas de campanhas/sorteio, e a participação não aparecia na campanha correta.
- **Caminho canônico:** **`lojas/{lojaId}/campanhas_sorteio`** (e dentro de cada campanha, `participantes`). Confirmado por: campanhas_sorteio_service, numero_sorte_service, campaign_engine_service, posPagamento.js, loja_config_screen, campanhas_sorteio_list_screen, firestore_cleanup_script, etc.
- **Onde `gerarCupomNumeroSorte` lê e escreve:**
  - **Lê:** `lojas/{lojaId}/campanhas` (antes) → passou a ler `lojas/{lojaId}/campanhas_sorteio` com filtros ativa + dataInicio/dataFim.
  - **Escreve:** `lojas/{lojaId}/clientes/{clienteId}` (update em cupons/pedidos) — inalterado; e `campanhaDoc.ref.collection('participantes').add(...)` — antes em um doc de `campanhas`, agora em um doc de `campanhas_sorteio`.
- **Onde o sistema usa `campanhas`:** Apenas nas duas implementações de gerarCupomNumeroSorte (arquivo standalone e index.js). Nenhum outro fluxo de negócio usa a coleção `campanhas` para sorteio.
- **Onde o sistema usa `campanhas_sorteio`:** Todo o fluxo de campanhas de sorteio (listagem, formulário, participantes, números da sorte, posPagamento, banner, relatórios, etc.).

---

## 2. Lista exata dos arquivos alterados

| Arquivo | Alteração |
|--------|-----------|
| `functions/gerarCupomNumeroSorte.js` | Leitura e escrita de campanha: `campanhas` → `campanhas_sorteio`; filtro de período (dataInicio/dataFim) adicionado. |
| `functions/index.js` | Mesma alteração na implementação exportada `gerarCupomNumeroSorte`: coleção `campanhas_sorteio` e filtro por dataInicio/dataFim. |
| `firestore.indexes.json` | Índice composto para `campanhas_sorteio`: (ativa, dataInicio, dataFim) para a query com os três filtros. |
| `docs/ENTREGA_CAMPANHAS_GERAR_CUPOM_NUMERO_SORTE.md` | Este documento. |

---

## 3. Código das alterações

### functions/gerarCupomNumeroSorte.js

- **Antes:**  
  `collection('campanhas').where('ativa', '==', true).limit(1)`
- **Depois:**  
  `collection('campanhas_sorteio').where('ativa', '==', true).where('dataInicio', '<=', agora).where('dataFim', '>=', agora).limit(1)`  
  com `const agora = new Date();` antes da query.

O registro em `participantes` continua em `campanhaDoc.ref.collection('participantes').add(...)`; como `campanhaDoc` passa a ser um documento de `campanhas_sorteio`, a escrita fica em `lojas/{lojaId}/campanhas_sorteio/{campanhaId}/participantes`.

### functions/index.js

- **Antes:**  
  `collection(COLLECTION_LOJAS).doc(lojaId).collection('campanhas').where('ativa', '==', true).limit(1)`
- **Depois:**  
  `collection(COLLECTION_LOJAS).doc(lojaId).collection('campanhas_sorteio').where('ativa', '==', true).where('dataInicio', '<=', agora).where('dataFim', '>=', agora).limit(1)`  
  com `const agora = new Date();` antes do bloco try da campanha.

### firestore.indexes.json

- Novo índice em `campanhas_sorteio` com campos: `ativa` (ASC), `dataInicio` (ASC), `dataFim` (ASC), para suportar a query com os três filtros.

---

## 4. Compatibilidade preservada

- **Cliente (cupons/pedidos):** Continua sendo atualizado em `lojas/{lojaId}/clientes/{clienteId}`; formato de cupom e de entrada em `pedidos` inalterado.
- **Resposta da CF:** Mesmo JSON (success, cupom, numeroSorte, clienteEmail, clienteTelefone, message); o app que chama a CF não precisa de mudança.
- **Campanhas ativas:** Só são consideradas campanhas com `ativa == true` e dentro do período (dataInicio ≤ agora ≤ dataFim), alinhado a `CampanhasSorteioService.listarCampanhasAtivas` e a `posPagamento.registrarParticipacaoCampanha`. Com isso, o número da sorte passa a ser registrado na mesma campanha que o restante do sistema considera ativa.
- **Participantes:** O formato do documento em `participantes` (clienteId, numeroSorte, pedidoId, clienteNome, clienteEmail, data) segue o que o app e outras funções esperam; apenas o pai do documento passa a ser um doc de `campanhas_sorteio` em vez de `campanhas`.
- **Legado:** Se existir dados antigos em `lojas/{lojaId}/campanhas`, eles deixam de ser usados por esta CF; não foram alterados nem removidos. Qualquer uso legado dessa coleção fora desta CF permanece como está.

---

## 5. Checklist de testes manuais

- [ ] **Deploy:** Fazer deploy das Cloud Functions (gerarCupomNumeroSorte e, se usado, a de index.js) e do índice Firestore (`firebase deploy --only firestore:indexes` ou deploy completo). Aguardar o índice ficar “Enabled” no console.
- [ ] **Pedido no catálogo:** Finalizar um pedido (fluxo que chama gerarCupomNumeroSorte, ex.: public_catalog_screen). Verificar que a resposta da CF retorna success e numeroSorte.
- [ ] **Cliente:** No documento do cliente em `lojas/{lojaId}/clientes/{clienteId}`, conferir que o cupom foi adicionado em `cupons` e que em `pedidos` há a entrada com o numeroSorte do pedido.
- [ ] **Campanha ativa:** Ter ao menos uma campanha em `campanhas_sorteio` com ativa=true e dataInicio/dataFim cobrindo a data do teste. Verificar em `campanhas_sorteio/{campanhaId}/participantes` que foi criado um documento com o clienteId, numeroSorte e pedidoId do pedido recém-finalizado.
- [ ] **Telas de campanha:** Na tela de campanhas/sorteio (participantes, histórico), confirmar que o novo participante/número aparece na campanha correta.
- [ ] **Sem campanha ativa:** Com nenhuma campanha ativa no período, finalizar outro pedido; a CF deve retornar success e atualizar cliente (cupom/pedidos), sem falhar e sem escrever em participantes (comportamento esperado).

---

## 6. Riscos residuais

- **Dupla implementação:** Existem duas implementações (gerarCupomNumeroSorte.js standalone e index.js). O projeto pode estar expondo apenas uma delas. Garantir que a que estiver em produção seja a que foi alterada (e fazer redeploy após a mudança).
- **Índice:** Se o índice composto (ativa, dataInicio, dataFim) ainda não existir no projeto, a primeira execução da query pode falhar com erro de índice ausente até o deploy dos indexes concluir. Em caso de erro, conferir no console do Firestore a criação do índice e aguardar conclusão.
- **Coleção `campanhas` antiga:** Se em algum lugar (outro script ou integração) ainda for usado `lojas/{lojaId}/campanhas` para sorteio, esse fluxo não passará a gravar em `campanhas_sorteio` automaticamente; essa entrega não altera outros códigos além do citado.
