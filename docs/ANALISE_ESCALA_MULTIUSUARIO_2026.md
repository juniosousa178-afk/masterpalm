# Análise de Escala – Múltiplos Admins e Vendedores Simultâneos

**Data:** 12/02/2026  
**Objetivo:** Erros atuais e riscos futuros com APK em grande escala.

---

## 1. RESUMO EXECUTIVO

| Severidade | Quantidade | Descrição |
|------------|------------|-----------|
| 🔴 CRÍTICO | 0 | ✅ Corrigidos: webhook atualiza estoque_produtos e trata variações |
| 🟠 ALTO | 5 | Cache, limites, paginação, campos de estoque |
| 🟡 MÉDIO | 6 | Sessão, listeners, índices, rate limits |
| 🟢 BAIXO | 4 | Documentados |

---

## 2. ERROS CRÍTICOS

### 2.1 ✅ Webhook MP: estoque_produtos (CORRIGIDO)

**Status:** O webhook agora atualiza ambas as coleções: produtos (catálogo web) e estoque_produtos (app admin/vendedor). Correção em 12/02/2026.

**Impacto:** Admin/vendedor vê estoque desatualizado no app. Risco de vender produto “sem estoque” (já vendido pelo catálogo).

**Solução:** O webhook deve atualizar **ambas** as coleções:
- `produtos` (catálogo web)
- `estoque_produtos` (app admin/vendedor)

E para produtos com variações (tamanho/cor), decrementar `variacoes` ou `estoquePorTamanho` conforme os itens do pedido.

---

### 2.2 ✅ Produtos com variações (CORRIGIDO)

**Status:** O webhook agora trata `variacoes` (tamanho+cor) e `estoquePorTamanho`. Se item tem tamanho+cor → decrementa `variacoes[tamanho][cor]`. Se apenas tamanho → `estoquePorTamanho[tamanho]`. Caso contrário → decremento simples.

---

## 3. RISCOS ALTOS

### 3.1 Cache do catálogo (3–5 min) sem invalidação

**Problema:** `CatalogCacheService` usa TTL de 3–5 min. Venda via app não invalida o cache do catálogo. Cliente pode ver produto “disponível” após ter sido vendido.

**Solução:** Invalidar cache ao baixar estoque (webhook ou app). Ex.: Cloud Function que chama `CatalogCacheService.invalidate(lojaId)` – atualmente não existe no backend.

---

### 3.2 produtos vs estoque_produtos: campos diferentes

**Status:** ✅ Webhook agora atualiza ambas as coleções com `quantidade`, `estoque`, `variacoes` e `estoquePorTamanho` conforme o item do pedido.

---

### 3.3 Paginação em coleções grandes

**Problema:** `produtos_firestore_service` e `clientes_firestore_service` fazem `.get()` sem `limit` em lojas com muitos documentos.

**Solução:** Usar `limit()` + `startAfterDocument()` para paginação.

---

### 3.4 Limite de 500 ops por transação

**Problema:** Firestore limita 500 writes por transação. `baixarEstoqueTransactionBatch` usa `_maxItensPorTransacao = 150`. Cada item pode gerar 2–3 writes (produto + estoque_produtos). ~150 itens ainda é seguro.

**Solução:** Manter limite; documentar que vendas com 150+ itens exigem outro fluxo.

---

### 3.5 findLojaIdByOrderId em O(n) lojas

**Problema:** No webhook, se `metadata.lojaId` não vier, itera **todas** as lojas para achar o pedido.

**Impacto:** Com muitas lojas, fica lento.

**Solução:** Índice ou coleção auxiliar `orderId → lojaId` criada na criação do pedido.

---

## 4. RISCOS MÉDIOS

### 4.1 Sessão multi-tenant

**Problema:** Troca rápida de usuário pode deixar cache de StoreResolver/StoreContext.

**Solução:** `SessionSanity.clearAllStoreCache()` existe; garantir que seja chamado no logout.

---

### 4.2 Listeners duplicados

**Problema:** Navegação rápida pode criar múltiplos listeners em `FirestoreCriticalListenerService`.

**Solução:** Serviço já faz `cancelProdutosListener` antes de iniciar novo; manter e revisar outros listeners.

---

### 4.3 Índices Firestore

**Problema:** `firestore.indexes.json` tem índices para `products` e `categoria`, mas o app usa `produtos` e `estoque_produtos`.

**Solução:** Conferir no Console do Firebase se há erros de índice e adicionar índices para `produtos` e `estoque_produtos` conforme as queries usadas.

---

### 4.4 CatalogCacheService: Map estático sem limite

**Problema:** `_configCache` e `_produtosCache` são `Map` em memória. Muitas lojas abertas = crescimento indefinido.

**Solução:** LRU ou TTL com limite de entradas (ex.: 20 lojas).

---

### 4.5 Rate limit em Cloud Functions

**Problema:** Em pico de uso, `checkRateLimit` pode rejeitar usuários legítimos.

**Solução:** Limites atuais são altos; monitorar 429 e aumentar se necessário.

---

### 4.6 temp_orders / pedidos_temp públicos

**Problema:** Regras permitem criação anônima. Possível abuso (criar muitos documentos).

**Solução:** Avaliar rate limit ou autenticação mínima.

---

## 5. PONTOS JÁ PROTEGIDOS

| Item | Status |
|------|--------|
| Baixa de estoque no app | ✅ Transação atômica (EstoqueTransactionService) |
| Roleta | ✅ Transação atômica |
| Webhook MP idempotência | ✅ paymentId em _mp_webhook_processed |
| Webhook MP token por loja | ✅ Resolve loja antes de buscar payment |
| Cupom (colisão) | ✅ UUID |
| Vendedores acesso estoque | ✅ isSellerOfStore nas regras |
| LimitsGuard | ✅ Coleções lojas/estoque_* |

---

## 6. AÇÕES RECOMENDADAS (prioridade)

1. ~~**Crítico:** Ajustar webhook para atualizar `estoque_produtos` além de `produtos`.~~ ✅ Feito
2. ~~**Crítico:** Garantir baixa correta para produtos com variações (tamanho/cor).~~ ✅ Feito
3. **Alto:** Invalidar cache do catálogo após baixa de estoque (via função ou trigger).
4. **Alto:** Implementar paginação em `estoque_produtos` e `estoque_clientes`.
5. **Médio:** Limitar tamanho do cache em `CatalogCacheService`.
6. **Médio:** Criar índice `orderId → lojaId` para acelerar o webhook.

---

## 7. TESTES DE CARGA SUGERIDOS

- 50+ vendedores vendendo o mesmo produto ao mesmo tempo.
- 100+ usuários girando a roleta simultaneamente.
- Venda via catálogo (MP) + venda via app no mesmo produto.
- Sync de 1000+ vendas ao abrir a tela.
- Múltiplas lojas abertas no catálogo (cache).

---

*Documento gerado em 12/02/2026.*
