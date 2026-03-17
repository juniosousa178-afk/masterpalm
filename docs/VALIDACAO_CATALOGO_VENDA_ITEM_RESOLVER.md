# Validação – `CatalogoVendaItemResolver` (Etapa 2)

Checklist manual para garantir que a extração de `_expandirItemsParaEstoque` para `catalogo_venda_item_resolver.dart` **não alterou comportamento**.

---

## 1. Cenários de teste mínimos

### Cenário 1 – Produto simples resolvido por `productId`

- **Entrada:**
  - `items`: uma lista com 1 item:
    - `{ 'productId': 'P1', 'nome': 'Anel', 'quantidade': 2, 'tamanho': '', 'cor': '' }`
  - `produtosBox`: contém um `Produto` com:
    - `lojaId = lojaId`, `idFirebase = 'P1'`, `nome = 'Anel'`, `slug` qualquer, `ehCombo = false`.
- **Comportamento esperado:**
  - Resolução direta por `idFirebase == productId` (sem fallback por slug/nome).
- **Resultado esperado (lista normalizada):**
  - 1 elemento:
    - `{ 'nome': 'Anel', 'slug': <slug do produto>, 'productId': 'P1', 'quantidade': 2, 'tamanho': '', 'cor': '' }`

---

### Cenário 2 – Produto simples resolvido por `slug`

- **Entrada:**
  - `items`: 1 item:
    - `{ 'slug': 'anel-prata', 'name': 'Anel', 'qty': 1 }`
  - `produtosBox`: contém `Produto` com:
    - `lojaId = lojaId`, `slug = 'anel-prata'`, `idFirebase` não vazio, `ehCombo = false`.
- **Comportamento esperado:**
  - `productId` vazio, `slug` preenchido → resolução por `slug`.
  - Log: `logW('[CATALOGO_ITEM] Resolução por slug (expandirEstoque) ...', tag: 'PRODUTO_FALLBACK')`.
- **Resultado esperado:**
  - `{ 'nome': produto.nome, 'slug': 'anel-prata', 'productId': produto.idFirebase, 'quantidade': 1, 'tamanho': '', 'cor': '' }`

---

### Cenário 3 – Produto simples resolvido por `nome`

- **Entrada:**
  - `items`: 1 item:
    - `{ 'nome': 'Anel Prata 925', 'quantidade': 3 }`
  - `produtosBox`: contém `Produto` com:
    - `lojaId = lojaId`, `nome = 'Anel Prata 925'`, `idFirebase` não vazio, `ehCombo = false`.
- **Comportamento esperado:**
  - `productId` e `slug` vazios → resolução por nome (match único, case-insensitive).
  - Logs:
    - `logW('[CATALOGO_ITEM] Resolução por nome (expandirEstoque) ...', tag: 'PRODUTO_FALLBACK')`
    - `reportProductResolvedByName(fluxo: 'expandirEstoque_item', nome: 'Anel Prata 925', ...)`.
- **Resultado esperado:**
  - `{ 'nome': 'Anel Prata 925', 'slug': produto.slug, 'productId': produto.idFirebase, 'quantidade': 3, 'tamanho': '', 'cor': '' }`

---

### Cenário 4 – Combo com `itensComboComSelecao`

- **Entrada:**
  - `items`: 1 item combo:
    - `{ 'nome': 'Kit Brincos', 'quantidade': 2, 'itensComboComSelecao': [ { 'id': 'C1', 'nome': 'Brinco A', 'quantidade': 1, 'tamanho': 'P', 'cor': 'Rosa' }, { 'productId': 'C2', 'nome': 'Brinco B', 'quantidade': 2, 'tamanho': 'M', 'cor': 'Azul' } ] }`
  - `produtosBox`: contém:
    - Combo `Produto` (não é usado diretamente na expansão além de `ehCombo = true`).
    - Produtos componentes com:
      - `idFirebase = 'C1'` (Brinco A), `idFirebase = 'C2'` (Brinco B), `lojaId = lojaId`.
- **Comportamento esperado:**
  - Para cada item combo:
    - Resolução por `id`/`productId`/`slug`/`nome` conforme ordem.
    - Cálculo de `qtdTotal = quantidadeCombo (2) * quantidadeItemCombo`.
  - Logs de combo:
    - `[COMBO_ID] [COMBO_ITEM] ...` quando resolve por `id/productId`.
- **Resultado esperado:**
  - 2 elementos:
    - Brinco A: `{ 'nome': 'Brinco A', 'slug': <slug A>, 'productId': 'C1', 'quantidade': 2 * 1 = 2, 'tamanho': 'P', 'cor': 'Rosa' }`
    - Brinco B: `{ 'nome': 'Brinco B', 'slug': <slug B>, 'productId': 'C2', 'quantidade': 2 * 2 = 4, 'tamanho': 'M', 'cor': 'Azul' }`

---

### Cenário 5 – Combo usando `prod.itensCombo` (sem `itensComboComSelecao`)

- **Entrada:**
  - `items`: 1 item combo:
    - `{ 'nome': 'Kit Anéis', 'quantidade': 1 }`
  - `produtosBox`:
    - Combo `Produto` com `ehCombo = true` e `itensCombo = [ { 'id': 'K1', 'nome': 'Anel A', 'quantidade': 1 }, { 'id': 'K2', 'nome': 'Anel B', 'quantidade': 2 } ]`.
    - Produtos componentes `K1`, `K2` presentes.
- **Comportamento esperado:**
  - `listaCombo` vem de `prod.itensCombo`.
  - Resolução e logs equivalentes ao cenário 4.
- **Resultado esperado:**
  - 2 elementos com quantidades corretas (1×1, 1×2) e nomes/ids/cores/tamanhos vindos dos itens de combo.

---

### Cenário 6 – Multiplicação de quantidade em combo

- **Entrada:** similar aos cenários 4/5, mas com `quantidade` do combo > 1 e `quantidade` dos itens de combo > 1.
- **Comportamento esperado:**
  - `qtdTotal = qtdCombo * qtdItemCombo`, respeitando o `clamp(1, 9999)`.
- **Resultado esperado:**
  - Para um item de combo com `quantidade = 3` e combo com `quantidade = 2`, `quantidade` normalizada deve ser `6`.

---

### Cenário 7 – Item com/sem `idFirebase`

- **Entrada:**
  - Produto simples/combos onde:
    - Um produto tem `idFirebase` preenchido.
    - Outro produto tem `idFirebase` vazio.
- **Comportamento esperado:**
  - Quando `idFirebase` **não** está vazio → presença de `'productId'` no map final.
  - Quando `idFirebase` vazio → ausência da chave `'productId'` no map (mantendo apenas `nome`, `slug`, etc.).

---

### Cenário 8 – Confirmação de logs e fallbacks

- **Entrada:**
  - Casos onde:
    - Resolução por slug (sem productId).
    - Resolução por nome (sem productId nem slug).
    - Itens de combo resolvidos por id, slug e nome.
- **Comportamento esperado:**
  - Logs idênticos aos da versão anterior:
    - `[CATALOGO_ITEM] Resolução por slug (expandirEstoque) ...`
    - `[CATALOGO_ITEM] Resolução por nome (expandirEstoque) ...`
    - `[COMBO_ID] [COMBO_ITEM] ...`
    - `[COMBO_FALLBACK] [COMBO_ITEM] ...` com as mesmas tags (`PRODUTO_FALLBACK`, `COMBO_FALLBACK`).
  - Chamadas a `reportProductResolvedByName` com os mesmos parâmetros (`fluxo`, `nome`, `slug`, `productIdRecebido`).

---

## 2. Resultados esperados (gerais)

Para todos os cenários acima:

- A **lista normalizada** retornada por `_expandirItemsParaEstoque` (via `CatalogoVendaService`) deve ser igual à versão anterior à extração:
  - Mesma quantidade de elementos.
  - Mesmas chaves e valores (`nome`, `slug`, `productId` quando existir, `quantidade`, `tamanho`, `cor`).
- Logs e chamadas de observabilidade (`logW`, `logD`, `reportProductResolvedByName`) devem aparecer com os mesmos textos e tags.

---

## 3. Observações

- Esta validação é **manual** e destinada a garantir que a extração para `catalogo_venda_item_resolver.dart` foi puramente mecânica.
- Não foram alteradas:
  - Regras de cálculo de totais.
  - Baixa de estoque.
  - Fluxos de registro de venda, campanhas ou notificações.

