# Mapeamento UI — Web E2E R8.4.38

Auditoria inicial das telas para automação Playwright (base `3e0e947`).

| Tela | Rota | Ação | Elemento | Seletor possível | Estável? | Alteração |
|------|------|------|----------|------------------|----------|-----------|
| Login | `/login` | preencher e-mail | campo e-mail | `login-email` (Semantics QA) | Sim | Adicionado R8438 |
| Login | `/login` | preencher senha | campo senha | `login-password` | Sim | Adicionado R8438 |
| Login | `/login` | entrar | botão Entrar | `login-submit` | Sim | Adicionado R8438 |
| Home | `/home` | abrir estoque | menu Estoque | `nav-estoque` | Sim | Adicionado R8438 |
| Home | `/home` | abrir vendas | menu Vendas | `nav-vendas` | Sim | Adicionado R8438 |
| Home | `/home` | abrir fornecedores | menu Fornecedores | `nav-fornecedores` | Sim | Adicionado R8438 |
| Estoque | `/estoque` | ver quantidade | chip Qtd | `product-stock-<id>` | Sim | Adicionado R8438 |
| Vendas | `/vendas` | nova venda | FAB | `nav-new-sale` | Sim | Adicionado R8438 |
| Nova venda | modal | finalizar | botão | `sale-complete` | Sim | Adicionado R8438 |
| Nova venda | modal | selecionar produto | dropdown | texto `Produto Simples QA` | Parcial | Existente |
| Vendas | `/vendas` | excluir venda | diálogo | texto `Excluir Venda?` | Parcial | Existente |
| Compra revenda | push | tipo revenda | radio | texto revenda detalhar | Parcial | Existente |
| Compra revenda | push | adicionar item | botão | `Adicionar item` | Parcial | Existente |
| Compra revenda | push | salvar | botão | `Confirmar compra` | Parcial | Existente |

**Nota:** Semantics QA ativos somente com `MP_ENVIRONMENT=qa`. Playwright usa `getByLabel` após `SemanticsBinding.ensureSemantics()`.
