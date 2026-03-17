# Relatório de Correções – Escalabilidade e Segurança

**Data:** 12/02/2026  
**Base:** Análise Completa de Escalabilidade – 12/02/2026

---

## 1. CORREÇÕES APLICADAS

### 1.1 Firestore Rules – Vendedores (validação)

- **estoque_produtos:** `isSellerOfStore(lojaId)` mantido
- **estoque_vendas:** `isSellerOfStore(lojaId)` mantido
- **estoque_clientes:** `isSellerOfStore(lojaId)` mantido
- **status:** vendedores continuam conseguindo baixar estoque, sincronizar vendas e clientes

### 1.2 Clientes – Regras Públicas

- **clientes:** `update` restrito a `isAdminOrSystem()` OU auto-atualização (mesmo email e size ≤ 25)
- **clientes_catalogo:** nova regra para `clientes_catalogo/{email}/cupons/{cupomId}` (roleta web)
- **status:** checkout público preservado; update público limitado

### 1.3 Temp Orders / Pedidos – Proteção

- **pedido_temp:** `create` limitado a doc com até 35 campos
- **pedidos_temp** (lojas): `create` com size ≤ 35 e presença de `lojaId`
- **pedidos_temp** (raiz): `create` com size ≤ 35
- **status:** limita tamanho de docs e reduz risco de abuso

### 1.4 Cupons de Clientes

- **cupons_clientes:** mantido `create: if true` (roleta do catálogo)
- **risco:** create público; mitigar futuramente com Cloud Function ou rate limit
- **status:** comportamento preservado para checkout público

### 1.5 Escalabilidade de Queries

- **produtos:** `syncFirestoreToHive` usa `limit(1000)`
- **clientes:** `syncFirestoreToHive` usa `limit(1000)`
- **vendas:** já usa `limit(100)`
- **status:** evita timeout em lojas grandes

### 1.6 Transações Firestore

- **baixarEstoqueTransactionBatch:** limite de 150 itens
- **motivo:** limite de ~500 operações por transação no Firestore
- **status:** venda com muitos itens retorna erro orientando divisão

### 1.7 Listeners em Tempo Real

- **FirestoreCriticalListenerService:** chama `cancelProdutosListener()` antes de iniciar
- **status:** sem listeners duplicados por loja

### 1.8 Sessão e Multi-tenant

- **SessionSanity:** valida `fixIfNoFirebaseUser` e `clearAllStoreCache`
- **StoreResolverService:** invalida cache com `_cachedUid`
- **status:** fluxo de sessão e invalidação correto

---

## 2. ARQUIVOS ALTERADOS

| Arquivo | Alteração |
|---------|-----------|
| `firestore.rules` | clientes (update), clientes_catalogo, pedidos_temp (validação) |
| `lib/services/produtos_firestore_service.dart` | limit(1000) em syncFirestoreToHive |
| `lib/services/clientes_firestore_service.dart` | limit(1000) em syncFirestoreToHive |
| `lib/services/estoque_transaction_service.dart` | limite de 150 itens por transação |
| `lib/services/firestore_critical_listener_service.dart` | comentário sobre listener único |

---

## 3. TRECHOS CRÍTICOS

### 3.1 Firestore Rules – Clientes

```javascript
allow update: if isAdminOrSystem()
  || (resource.data.email is string
      && request.resource.data.email == resource.data.email
      && request.resource.data.size() <= 25);
```

### 3.2 Firestore Rules – Pedidos Temp

```javascript
allow create: if request.resource.data.size() <= 35
  && request.resource.data.get('lojaId', '') is string;
```

### 3.3 Estoque Transaction – Limite de Itens

```dart
static const int _maxItensPorTransacao = 150;
if (itens.length > _maxItensPorTransacao) {
  throw Exception('Venda com muitos itens... Divida em vendas menores (máx. 150 itens por venda).');
}
```

---

## 4. RISCOS REMANESCENTES

1. **cupons_clientes create público:** ainda permite abuso; considerar Cloud Function ou rate limit.
2. **produtos/clientes limit(1000):** lojas com mais de 1000 itens precisarão de paginação futura.
3. **Índice estoque_vendas:** `orderBy('createdAt')` pode exigir índice; criar via Console se necessário.
4. **syncTodasVendas:** loop sequencial; possível otimização com batch writes no futuro.

---

## 5. CHECKLIST DE VALIDAÇÃO PÓS-DEPLOY

- [ ] `firebase deploy --only firestore:rules`
- [ ] Testar venda como vendedor (estoque, vendas, clientes)
- [ ] Testar cadastro de cliente no catálogo
- [ ] Testar update de perfil do cliente (mesmo email)
- [ ] Testar criação de pedido temporário (checkout)
- [ ] Testar venda com 100+ itens (deve falhar com limite)
- [ ] Trocar de usuário rapidamente e verificar ausência de dados residuais
- [ ] Conferir console do Firebase para erros de índice

---

*Documento gerado em 12/02/2026.*
