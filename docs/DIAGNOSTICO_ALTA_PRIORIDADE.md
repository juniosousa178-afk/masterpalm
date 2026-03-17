# Relatório de Diagnóstico – Problemas ALTA Prioridade
**Projeto:** MasterPalm | **Versão:** 1.0.28+38 | **Data:** 08/03/2025

---

## 1. Diagnóstico resumido dos 6 itens ALTA

### [ALTO 1] Uso misto de lojaId, store_id e storeId

| Onde | Uso | Observação |
|------|-----|------------|
| **Firestore (users, usuarios)** | `store_id` | Campo canônico no Firestore |
| **Hive (sessao, config)** | `store_id` e `storeId` | Leitura tolerante a ambos |
| **StoreResolverService** | Lê `store_id` do Firestore e Hive | Retorna `String?` (lojaId) |
| **LojaIdService** | Usa `lojaId` internamente, grava `store_id` | Interface unificada |
| **user_profile_keys.dart** | `kStoreId`, `kStoreIdCamel`, `kLojaId` | Constantes para legado |
| **Código Dart** | `lojaId` predominante em params/vars | Padrão dominante |
| **Cloud Functions** | `storeId`, `lojaId`, `resolvedLojaId` | JavaScript usa camelCase |

**Padrão dominante:** `lojaId` no código Dart; `store_id` no Firestore/Hive.

---

### [ALTO 2] Timeout e fallback para 'padrao'

| Arquivo | Linha | Contexto |
|---------|-------|----------|
| `vendas_screen.dart` | 111, 114, 117, 148 | Timeout → `lojaId = 'padrao'` |
| `clientes_screen.dart` | 77, 133, 135, 138, 152 | Idem |
| `main.dart` | 1635, 1646, 1657, 1668 | `lojaId.isEmpty ? 'padrao' : lojaId` (para rotas) |
| `historico_clientes_screen.dart` | 42, 70, 72 | Idem |
| `fornecedor_screen.dart` | 76, 78 | Idem |
| `contas_receber_screen.dart` | 41, 45 | Idem |
| `relatorio_ranking_clientes_screen.dart` | 63, 65 | Idem |
| `notas_fiscais_screen.dart` | 29, 61, 63 | Idem |
| `admin_painel_web_screen.dart` | 18, 38, 43 | Idem |

**Risco:** `'padrao'` pode não existir em `lojas/{lojaId}`. HiveBoxNames usa `vendas_padrao`, `clientes_padrao` etc. Se a loja não existe no Firestore, sync falha ou retorna vazio.

**Observação:** `StoreResolverService` **nunca** retorna `'padrao'`. Retorna `null` ou lojaId real. O fallback é feito pelos **chamadores**.

---

### [ALTO 3] Coleções distintas: pre_pedidos, pedidos_pendentes, pedidos_catalogo

| Coleção | Path | Responsabilidade | Usado por |
|---------|------|------------------|-----------|
| `pre_pedidos` | `lojas/{lojaId}/pre_pedidos` | Pré-pedido do catálogo (checkout com MP/confirmar admin) | PrePedidoService, PedidoPublicoScreen, mpWebhookHandler |
| `pedidos_pendentes` | `lojas/{lojaId}/pedidos_pendentes` | Checkout com pagamento pendente (PIX/dinheiro) | CatalogoVendaService.criarPedidoPendente, finalizarPedidoComPagamento |
| `pedidos_catalogo` | `lojas/{lojaId}/pedidos_catalogo` | Rules existem; uso limitado | limpar_firestore, possivelmente legado |
| `pedidos` | `lojas/{lojaId}/pedidos` | Histórico de pedidos do catálogo | CatalogoVendaService (após venda) |
| `pedidos` (root) | `/pedidos` | Histórico global? | OrderReviewScreen (add) |

**Fluxos:**
- **pre_pedidos:** Cliente finaliza no catálogo → cria pre_pedido → admin confirma → CatalogoVendaService.registrarVendaCatalogo → Hive + estoque_vendas
- **pedidos_pendentes:** Cliente escolhe PIX/dinheiro → cria pedidos_pendentes → Pagamento confirmado → finalizarPedidoComPagamento → venda + estoque_vendas

---

### [ALTO 4] Regras diferentes por coleção de pedido

| Coleção | create | read | update | delete |
|---------|--------|------|--------|--------|
| pre_pedidos | isValidPrePedidoCreate() | resource != null | isAdminOrSystem | isAdminOrSystem |
| pedidos_catalogo | isValidPrePedidoCreate() | resource != null | isAdminOrSystem | isAdminOrSystem |
| pedidos_pendentes | isValidPedidoPendenteCreate() | resource != null | isAdminOrSystem \|\| isSignedIn | isAdminOrSystem |
| pedidos (lojas) | isValidPedidoCreate() | belongsToStore | belongsToStore | belongsToStore |

**Inconsistência:** `pedidos_pendentes` permite update para qualquer usuário autenticado; as outras exigem admin.

---

### [ALTO 5] Resolução de loja – ordem atual

1. Cache (StoreResolverService)
2. Firestore users/{uid}.store_id
3. Mapeamento _uidToLoja (hardcoded)
4. Firestore usuarios/{email}.store_id
5. Hive sessao (store_id, lojaId)
6. Novo slug baseado em email

LojaIdService.get() usa: StoreResolver → sessao.store_id → config.store_id → null.

---

### [ALTO 6] Garantia de não quebra

- Qualquer alteração em lojaId/store_id deve manter leitura retroativa.
- Fallback 'padrao' não deve ser usado quando loja não existe; tratar como erro explícito.
- Coleções de pedido: não unificar fisicamente sem migração; criar camada de acesso primeiro.

---

## 2. Plano de correção por etapas

| Etapa | Risco | Escopo |
|-------|-------|--------|
| **2** | Baixo | Criar LojaIdAdapter com leitura tolerante; escrita em store_id |
| **3** | Médio | Remover fallback 'padrao' em timeout; retornar null + UI de retry |
| **4** | Alto | Apenas documentar; não unificar coleções agora |
| **5** | Médio | Revisar rules; manter comportamento atual |

---

## 3. Lista exata de arquivos a alterar (ETAPA 2 + 3)

### ETAPA 2
- `lib/core/loja_id_adapter.dart` (NOVO)
- `lib/services/store_resolver_service.dart` (usar adapter na leitura)
- Nenhuma alteração destrutiva em dados

### ETAPA 3
- `lib/screens/vendas_screen.dart` – timeout: não usar 'padrao', tratar erro
- `lib/screens/clientes_screen.dart` – idem
- `lib/services/auto_sync_service.dart` – já usa sessao fallback; garantir que não use 'padrao' quando null

---

## 4. Validação sem quebrar

1. Login com loja válida → deve continuar funcionando.
2. Timeout de resolução → exibir mensagem de erro + botão "Tentar novamente", sem redirecionar para loja inexistente.
3. Dados antigos no Hive/Firestore com store_id → devem ser lidos normalmente.
4. Catálogo, checkout, pré-pedido → fluxo inalterado.

---

## 5. IMPLEMENTAÇÃO REALIZADA (ETAPA 2 + 3)

### ETAPA 2 – Padronização lojaId/store_id

**Arquivos criados:**
- `lib/core/loja_id_adapter.dart` – Helper com `normalizeFromMap()`, `normalizeFromBox()` para leitura tolerante

**Arquivos alterados:**
- `lib/services/store_resolver_service.dart` – Usa `normalizeFromMap` (Firestore) e `normalizeFromBox` (Hive)
- `lib/services/loja_id_service.dart` – Usa `normalizeFromBox` e novo método `getWithTimeout()` para resolução com timeout

### ETAPA 3 – Remover fallback perigoso para 'padrao'

**Arquivos alterados:**
- `lib/screens/clientes_screen.dart` – Usa `LojaIdService.getWithTimeout()`; quando null, exibe erro + retry
- `lib/screens/vendas_screen.dart` – Idem
- `lib/main.dart` – Rotas de relatórios usam `_lojaIdRoute()`; quando loja vazia, exibe erro em vez de 'padrao'

### Preservado

- **tipoEmbalagem / tipo frete 'padrao'** – Não alterado (valor semântico válido)
- **Dados legados** – Leitura continua aceitando `store_id`, `lojaId`, `storeId`
- **Escrita** – Mantém `store_id` em Hive/Firestore

---

## 6. CHECKLIST DE TESTES MANUAIS

### Autenticação / Resolução de loja
- [ ] Login com usuário que tem loja válida → app carrega normalmente
- [ ] Timeout de resolução (simular rede lenta) → exibe "Não foi possível carregar a loja" + botão "Tentar novamente"
- [ ] Retry após timeout → tenta resolver novamente
- [ ] Modo offline com sessão anterior → usa Hive sessao.store_id

### Clientes / Vendas
- [ ] Abrir tela Clientes → carrega normalmente
- [ ] Abrir tela Vendas → carrega normalmente
- [ ] Timeout ao abrir Clientes → exibe erro + retry
- [ ] Timeout ao abrir Vendas → exibe erro + retry

### Relatórios
- [ ] Abrir Relatório Mais Vendidos (com loja ok) → carrega
- [ ] Abrir Relatório Mais Vendidos (sem loja) → exibe erro "Ir para Início"

### Catálogo / Checkout
- [ ] Fluxo catálogo → sem alterações esperadas

---

## 7. RISCOS RESIDUAIS

1. **Outras telas com fallback 'padrao'** – contas_receber_screen, fornecedor_screen, historico_clientes_screen, notas_fiscais_screen, admin_painel_web_screen, etc. ainda usam `id ?? 'padrao'`. Recomenda-se aplicar o mesmo padrão (getWithTimeout + erro explícito) nessas telas posteriormente.
2. **ETAPA 4–6 não implementadas** – Unificação de coleções de pedido, regras Firestore e validação completa ficam para entregas futuras.

---

## 8. SUGESTÕES FUTURAS (após validação dos ALTA)

- Aplicar o mesmo tratamento de fallback nas demais telas que usam 'padrao' como lojaId
- Implementar camada unificada de acesso para pre_pedidos / pedidos_pendentes / pedidos_catalogo (ETAPA 4)
- Revisar regras Firestore para pedidos (ETAPA 5)
