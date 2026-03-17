# ETAPA 9 — Condições de Go-Live e Revisão do Backfill

## 4. Revisão do Backfill Atual

### Cobertura dos scripts

| Script | O que faz | Priorização por data? |
|--------|-----------|------------------------|
| `backfill_pedido_status_publico.js` | Lê `pre_pedidos` em ordem por `documentId`, cria espelho em `pedido_status_publico` | Não — ordem por ID |
| `backfill_fontes_cliente_pedidos.js` (modo `pedido-status-publico`) | Idem, com modos adicionais | Não |
| `backfill_fontes_cliente_pedidos.js` (modo `clientes-sem-portal-token`) | Gera `portalToken` em clientes que não têm | Não — ordem por ID |
| `backfill_fontes_cliente_pedidos.js` (modo `clientes-portal-perfil`) | Cria/atualiza `clientes_portal` perfil | Não |
| `backfill_fontes_cliente_pedidos.js` (modo `clientes-portal-pedidos`) | Preenche `clientes_portal/{token}/pedidos` | Não |

### Implicação

A paginação é por `documentId`. Em Firestore, IDs gerados pelo cliente tendem a ser mais cronológicos que IDs aleatórios, mas **não há garantia** de que pedidos recentes sejam processados primeiro. Para priorizar pedidos ativos/recentes:

- **Opção 1:** Rodar o backfill até esgotar a coleção, em lotes controlados.
- **Opção 2:** Introduzir um modo `--ordenarPorData` usando `orderBy('dataCriacao', descending: true)` — exige índice composto e altera a estratégia de cursor.
- **Opção 3:** Rodar primeiro backfill completo em staging/loja piloto; só então ativar go-live.

### O que o backfill cobre hoje

- `pedido_status_publico`: todos os `pre_pedidos` (na ordem de `documentId`).
- `clientes_portal` perfil: todos os clientes (geram `portalToken` se faltar).
- `clientes_portal/pedidos`: todos os `pre_pedidos` com cliente resolvível.

### Gaps potenciais

- Pedidos sem `cliente.id` nem `cliente.email` útil não entram em `clientes_portal/pedidos`.
- Clientes sem `portalToken` antes do backfill: o script `clientes-sem-portal-token` resolve; a UI gera `portalToken` on-demand no login/perfil.

---

## 5. Condição Objetiva de Go-Live

A ETAPA 9 pode ir para produção quando **todas** as condições forem atendidas:

| Critério | Objetivo | Como validar |
|----------|----------|--------------|
| **Backfill pedido_status_publico** | ≥ 95% dos pedidos dos últimos 90 dias com espelho | Consulta admin: contar docs em `pedido_status_publico` vs `pre_pedidos` com `dataCriacao` nos últimos 90 dias |
| **Backfill clientes_portal** | ≥ 95% dos clientes com pedido nos últimos 180 dias com `portalToken` | Script ou consulta: clientes em `clientes` com pedidos recentes que possuem `portalToken` |
| **Backfill clientes_portal/pedidos** | Pedidos recentes (últimos 90 dias) com cliente resolvível presentes no índice | Verificar amostra de `clientes_portal/{token}/pedidos` para pedidos recentes |
| **Teste em loja piloto** | Fluxo completo validado | Deep link público, Meus Pedidos, autofill de endereço, telas admin |
| **Mensagens de transição** | Sem “tela em branco” ou erro genérico | Validar PedidoPublicoScreen e Meus Pedidos vazios com as novas mensagens |

### Ordem recomendada de backfill antes do go-live

1. `clientes-sem-portal-token` (para clientes legados)
2. `clientes-portal-perfil` (para `ultimoEndereco` e índice)
3. `clientes-portal-pedidos` (para Meus Pedidos)
4. `pedido-status-publico` (para links públicos)

### Critério mínimo simplificado

Se não for viável medir percentuais exatos:

- Backfill completo executado para todas as lojas em produção (ou lojas piloto definidas).
- Pelo menos 1 ciclo completo (todos os modos) sem erros fatais.
- 2 testes manuais em loja real: deep link público e Meus Pedidos, ambos passando.
