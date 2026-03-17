# Análise: Webhook Mercado Pago — Padronização products → produtos

**Data:** 12/02/2026  
**Projeto:** MasterPalm

---

## 1. MAPEAMENTO DE USO

### 1.1 Coleção `products`

| Local | Caminho | Uso |
|-------|---------|-----|
| `functions/index.js` (mpWebhook) | `lojas/{lojaId}/products/{prodId}` | Baixa estoque após pagamento aprovado |
| `functions/index.js` (publishLojaDraft) | `lojas/{lojaId}/products/{prodId}` | Cópia de draft ao publicar (legado) |
| `firestore.rules` | `stores/{storeId}/products/{prodId}` | Regra legada (stores ≠ lojas) |

### 1.2 Coleção `produtos`

| Local | Caminho | Uso |
|-------|---------|-----|
| `lib/screens/public_catalog_screen.dart` | `lojas/{lojaId}/produtos` | Catálogo público (kLiveProdutosCol) |
| `lib/services/produtos_firestore_service.dart` | `lojas/{lojaId}/produtos` | Sync do app → catálogo público |
| `lib/services/produtos_firestore_service.dart` | `lojas/{lojaId}/estoque_produtos` | Fonte única de estoque (app) |
| `functions/index.js` (publishLojaDraft) | `lojas/{lojaId}/produtos/{prodId}` | Publicação de drafts |
| `functions/src/posPagamento.js` | `lojas/{lojaId}/produtos/{prodId}` | Baixa estoque (já usa produtos) |
| `functions/canaisMetaWebhooks.js` | `lojas/{lojaId}/produtos` | Busca de produtos |
| `firestore.rules` | `lojas/{lojaId}/produtos/{prodId}` | Regra principal |

### 1.3 Coleção `estoque_produtos`

| Local | Uso |
|-------|-----|
| App (EstoqueTransactionService, ProdutosFirestoreService) | Fonte única de estoque — **NÃO ALTERAR** |
| Sync Hive ↔ Firestore | Produtos do app |

---

## 2. PADRÃO ESCOLHIDO: `produtos`

### Motivos

1. **Consistência com o projeto:** O app, catálogo web, posPagamento e canaisMeta já usam `produtos`.
2. **Idioma:** Projeto em português (`lojas`, `estoque_produtos`, `estoque_vendas`, etc.).
3. **Evitar duplicação:** Hoje `publishLojaDraft` escreve em `produtos` e `products`; manter apenas `produtos`.
4. **Compatibilidade:** `posPagamento.js` já usa `produtos`; `mpWebhook` em index.js estava desalinhado.
5. **Firestore rules:** Regra principal é `lojas/{lojaId}/produtos`; `stores/products` é legado separado.

---

## 3. ALTERAÇÕES NECESSÁRIAS

### 3.1 Webhook mpWebhook (index.js)

**Antes:** `collection("products")`  
**Depois:** `collection("produtos")`

O fluxo de baixa (campo `estoque`, `FieldValue.increment`) permanece igual; apenas a coleção é alterada.

### 3.2 publishLojaDraft (index.js)

**Antes:** Escreve em `produtos` e `products`  
**Depois:** Escreve apenas em `produtos`

Remove a duplicação legada.

### 3.3 Firestore rules

Manter `stores/{storeId}/products` como legado (outro contexto).  
Não há regra explícita para `lojas/*/products`; funções usam Admin SDK e ignoram rules.

---

## 4. GARANTIAS

- **Baixa de estoque no app:** Continua via `EstoqueTransactionService` e `estoque_produtos`. Sem alterações.
- **Webhook:** Passa a atualizar `produtos`, alinhado ao catálogo e ao `posPagamento.js`.
- **Catálogo web:** Continua lendo `produtos`.
- **Compatibilidade:** Itens do pedido usam `productId` ou `produtosId`; o webhook já trata ambos.

---

## 5. DIFF DAS CORREÇÕES

### 5.1 functions/index.js — mpWebhook (linhas ~899–916)

```diff
         for (const it of items) {
-          const pId = it.productId || it.produtosId;
+          const pId = it.productId || it.produtosId || it.id;
           if (!pId) continue;

+          const qty = Number(it.qty ?? it.quantidade ?? 0);
+          if (qty <= 0) continue;
+
           const pRef = db
             .collection(COLLECTION_LOJAS)
             .doc(lojaId)
-            .collection("products")
+            .collection("produtos")
             .doc(String(pId));

           batch.set(
             pRef,
-            { estoque: FieldValue.increment(-Number(it.qty || 0)) },
+            { estoque: FieldValue.increment(-qty) },
             { merge: true }
           );
         }
```

### 5.2 functions/index.js — publishLojaDraft (linhas ~1275–1290)

```diff
     draftSnap.forEach((doc) => {
       const prodId = doc.id;
       const data = doc.data() || {};

       const baseData = {
         ...data,
         id: data.id || prodId,
         updatedAt: nowTs,
       };

-      const prodRef1 = lojaRef.collection("produtos").doc(prodId);
-      const prodRef2 = lojaRef.collection("products").doc(prodId);
-
-      batch.set(prodRef1, baseData, { merge: true });
-      batch.set(prodRef2, baseData, { merge: true });
+      const prodRef = lojaRef.collection("produtos").doc(prodId);
+      batch.set(prodRef, baseData, { merge: true });
     });
```

### 5.3 Observações adicionais

- **produtosId / quantidade:** O webhook passa a aceitar `it.id` e `it.quantidade` para compatibilidade com o carrinho do catálogo (`produtosId`, `quantidade`).
- **posPagamento.js:** Já usa `produtos`; nenhuma alteração necessária.
- **canaisMetaWebhooks.js:** Já usa `produtos`; nenhuma alteração necessária.
