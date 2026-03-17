# Correções dos 3 Riscos Críticos — MasterPalm

**Data:** 06/03/2025  
**Base:** AUDITORIA_FINAL_PRODUCAO_MASTERPALM.md

---

## 1. Diagnóstico Resumido por Prioridade

### Prioridade 1 — Storage Rules
**Problema:** Qualquer usuário autenticado podia escrever em Storage de qualquer loja.  
**Causa:** `allow write: if request.auth != null` sem checagem de lojaId.  
**Solução:** Função `belongsToStore(lojaId)` usando Firestore para validar:
- `users/{uid}.store_id == lojaId`
- `lojas/{lojaId}.ownerUid` ou `adminUid == uid`
- `lojas/{lojaId}/members/{uid}` existe
- `lojas/{lojaId}/vendedores/{uid}` existe e `ativo == true`
- Admin raiz (emails fixos)

### Prioridade 2 — OrderReviewScreen / Hive Multi-Loja
**Problema:** Uso de `Hive.box('produtos')` sem lojaId.  
**Causa:** Telas antigas com single-store usavam boxes globais.  
**Solução:**
- Carregar o pedido antes de abrir boxes.
- Resolver lojaId: `widget.lojaId ?? order['lojaId'] ?? LojaIdService.getWithTimeout()`
- Usar `HiveBoxNames.produtos(lojaId)` quando lojaId existe.
- Fallback legado: `'produtos'`, `'clientes'`, `'vendas'` se lojaId for null (compatibilidade).

### Prioridade 3 — Divergência de Coleções de Produtos
**Problema:** `FirestoreCatalogProductSource` usava `produtos_live`/`produtos_draft`; o resto do sistema usa `produtos`/`draft_produtos`.  
**Padrão canônico:** `produtos` e `draft_produtos` (firestore.rules, catalog_helpers, produtos_service, publishLojaDraft).  
**Solução:** Ajuste de constantes em `firestore_catalog_impl.dart` para usar `produtos` e `draft_produtos`.

---

## 2. Arquivos Alterados

| Arquivo | Alteração |
|---------|-----------|
| `storage.rules` | Função `belongsToStore(lojaId)` e regras de write condicionadas por ela |
| `lib/screens/order_review_screen.dart` | Import HiveBoxNames, _load refatorado (carrega pedido → resolve lojaId → abre boxes corretas) |
| `lib/catalog/data/firestore_catalog_impl.dart` | `_kLiveProdutosCol` = `'produtos'`, `_kDraftProdutosCol` = `'draft_produtos'` |

---

## 3. Código das Alterações

### storage.rules
- Adicionada função `isRootAdmin()` (alinhada ao firestore.rules).
- Adicionada função `belongsToStore(lojaId)` com checagem via Firestore.
- Regras de write em `logos`, `banners`, `produtos`, `midias` alteradas de `request.auth != null` para `belongsToStore(lojaId)`.
- Catch-all mantido: `allow read, write: if request.auth != null` (ex.: `_healthcheck`).

### lib/screens/order_review_screen.dart
- Import de `HiveBoxNames`.
- Ordem de `_load`: 1) carregar pedido (TempOrderService / pedidoRepository), 2) resolver lojaId, 3) abrir boxes com HiveBoxNames ou fallback legado.
- Nomes das boxes:
  - Com lojaId: `HiveBoxNames.produtos(lojaId)`, `clientes(lojaId)`, `vendas(lojaId)`.
  - Sem lojaId: `'produtos'`, `'clientes'`, `'vendas'`.

### lib/catalog/data/firestore_catalog_impl.dart
```dart
// Antes
const String _kLiveProdutosCol = 'produtos_live';
const String _kDraftProdutosCol = 'produtos_draft';

// Depois
const String _kLiveProdutosCol = 'produtos';
const String _kDraftProdutosCol = 'draft_produtos';
```

---

## 4. Compatibilidade Preservada

| Aspecto | Preservação |
|---------|-------------|
| **Upload de imagem** | Continua funcionando; regras só restringem quem pode gravar. Usuários com `store_id`, owner/admin, member ou vendedor da loja continuam podendo subir arquivos. |
| **Catálogo público** | Leitura permanece `allow read: if true` em logos, banners, produtos e midias. Sem alteração. |
| **Multi-loja** | OrderReviewScreen passa a usar boxes corretas; fallback para boxes legadas quando lojaId é null (single-store / legado). |
| **Legado** | Fallback para `'produtos'`, `'clientes'`, `'vendas'` quando lojaId não for resolvido. |
| **FirestoreCatalogProductSource** | Passa a ler as mesmas coleções que o resto do app (`produtos`, `draft_produtos`). |

---

## 5. Checklist de Testes Manuais

### Storage Rules
- [ ] Usuário com `users/{uid}.store_id == lojaId` faz upload em `lojas/{lojaId}/produtos/...` → sucesso
- [ ] Usuário sem vínculo com a loja faz upload em `lojas/{lojaId}/produtos/...` → 403
- [ ] Vendedor ativo da loja faz upload → sucesso
- [ ] Admin raiz (emails fixos) faz upload em qualquer loja → sucesso
- [ ] Leitura pública de imagens de produtos no catálogo → continua funcionando

### OrderReviewScreen
- [ ] Deep link `/pedido/{id}?loja=xxx` → usa `produtos_xxx`, `clientes_xxx`, `vendas_xxx`
- [ ] Pedido com `lojaId` no documento → usa boxes corretas
- [ ] Usuário logado, pedido sem lojaId → usa LojaIdService (boxes da loja do usuário)
- [ ] Single-store antigo (sem lojaId) → fallback para `produtos`, `clientes`, `vendas`
- [ ] Finalizar venda → VendasService.registrarVendaMulti com boxes corretas → sucesso

### FirestoreCatalogProductSource
- [ ] Se for injetado em PublicCatalogScreen, catálogo exibe produtos de `produtos` / `draft_produtos`
- [ ] Catálogo público continua exibindo produtos normalmente (usa Firestore direto)

---

## 6. Riscos Residuais

| Risco | Mitigação |
|-------|-----------|
| Storage rules com `firestore.get()` em projeto sem Firestore habilitado ou path incorreto | Validar deploy em staging; se houver erro, conferir configuração do projeto. |
| Loja sem `ownerUid`/`adminUid` ou `users/{uid}.store_id` | Garantir onboarding que preencha esses campos; admins raiz continuam funcionando. |
| OrderReviewScreen com lojaId null e LojaIdService falhando | Fallback para boxes legadas; em multi-loja, pode haver box incorreta se lojaId não for resolvido. |
| PublicCatalogScreen ainda não usa FirestoreCatalogProductSource | Sem impacto; a correção prepara o uso futuro. |

---

**Fim do documento.**
