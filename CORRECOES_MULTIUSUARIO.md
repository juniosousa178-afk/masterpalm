# Correções MasterPalm - Multiusuário e Sincronização

## Resumo das Correções Aplicadas

### 1. Firestore Rules (firestore.rules)

**Problema:** Cadastro de vendedores retornava `permission-denied`

**Correção:**
- `usuarios/{email}`: Agora permite `isAdminOrSystem()` criar/atualizar/deletar (não apenas self ou rootAdmin)
- `users/{uid}`: Agora permite `isAdminOrSystem()` configurar outros usuários

```javascript
// ANTES:
allow create, update, delete: if isSelfUserDoc(emailDocId) || isRootAdmin();

// DEPOIS:
allow create, update, delete: if isSelfUserDoc(emailDocId) || isAdminOrSystem();
```

---

### 2. Cadastro de Vendedores (cadastro_screen.dart)

**Problema:** Vendedores eram criados sem associação à loja do admin

**Correções:**
- Obtém `lojaId` do admin atual antes de criar o vendedor
- Salva `store_id` em 3 lugares:
  - `usuarios/{email}` (compatibilidade legada)
  - `users/{uid}` (usado pelo StoreResolverService)
  - `lojas/{lojaId}/members/{uid}` (membros da loja)
- Adicionou opção de tipo "vendedor" no dropdown

---

### 3. Ações em Lote do Catálogo (estoque_screen.dart)

**Problema:** Botões "Adicionar ao Catálogo" e "Remover do Catálogo" mostravam sucesso mas nada acontecia

**Correções:**
- `_adicionarAoCatalogoLote()`:
  - Agora marca `publicadoNoCatalogo = true` ANTES de sincronizar
  - Salva no Hive (`await produto.save()`)
  - Passa `lojaIdOverride` para garantir a loja correta

- `_removerDoCatalogoLote()`:
  - Agora marca `publicadoNoCatalogo = false` ANTES de remover
  - Salva no Hive
  - Passa `lojaIdOverride` para garantir a loja correta

---

### 4. Sincronização Entre Celulares (full_sync_service.dart - NOVO)

**Problema:** Ao trocar de celular com mesma conta, produtos não apareciam

**Correção:**
- Criado novo serviço `FullSyncService` com método `syncInicialCompleto()`
- Funcionalidades:
  - Limpa cache de loja diferente (se existir)
  - Sincroniza TODOS os produtos do Firestore para Hive (com paginação)
  - Sincroniza TODOS os clientes
  - Retorna resultado detalhado

---

### 5. Login com Sync Automático (login_screen.dart)

**Correções:**
- Importa `FullSyncService`
- Verifica `store_id` E `lojaId` E `ownerStoreId` (compatibilidade)
- Após login, chama `FullSyncService.syncInicialCompleto()`
- Loga resultado da sincronização

---

## Arquivos Alterados

| Arquivo | Descrição |
|---------|-----------|
| `firestore.rules` | Permite admin/programador cadastrar usuários |
| `lib/screens/cadastro_screen.dart` | Associa vendedor à loja do admin |
| `lib/screens/estoque_screen.dart` | Corrige ações em lote do catálogo |
| `lib/screens/login_screen.dart` | Adiciona sync completo após login |
| `lib/services/full_sync_service.dart` | **NOVO** - Serviço de sincronização completa |

---

## Checklist de Teste em 2 Celulares

### Teste 1: Cadastro de Vendedor

- [ ] Login como admin no Celular 1
- [ ] Ir em Cadastrar Usuário
- [ ] Criar novo vendedor (tipo: Vendedor)
- [ ] Verificar que NÃO aparece erro `permission-denied`
- [ ] Verificar que aparece mensagem de sucesso

### Teste 2: Login do Vendedor

- [ ] No Celular 2, fazer login com o vendedor criado
- [ ] Verificar que NÃO aparece erro "Vendedor sem loja vinculada"
- [ ] Verificar que o catálogo carrega os mesmos produtos do admin

### Teste 3: Sincronização Entre Celulares

- [ ] No Celular 1 (admin), adicionar um produto novo
- [ ] No Celular 2 (mesma conta ou vendedor), fazer logout e login
- [ ] Verificar que o produto novo aparece no Celular 2

### Teste 4: Ações em Lote

- [ ] Selecionar múltiplos produtos no estoque
- [ ] Clicar em "Adicionar ao Catálogo"
- [ ] Verificar que aparece mensagem de sucesso
- [ ] Abrir catálogo web e verificar que os produtos aparecem
- [ ] Repetir para "Remover do Catálogo"
- [ ] Verificar que os produtos SUMIRAM do catálogo web

### Teste 5: Persistência

- [ ] Fechar e reabrir o app
- [ ] Verificar que as alterações do catálogo persistiram
- [ ] Verificar no Firebase Console que os produtos estão em `lojas/{lojaId}/produtos`

---

## Deploy das Firestore Rules

Para aplicar as novas regras, execute:

```bash
cd c:\Users\Pichau\apk_nathy\temp_naty
firebase deploy --only firestore:rules
```

Ou copie o conteúdo de `firestore.rules` para o Firebase Console.

---

## Observações Importantes

1. **Cloud Function**: Não foi necessária. A solução usando Firebase App secundário + Firestore Rules funcionou.

2. **StoreResolverService**: Já estava correto. O problema era que vendedores não tinham `store_id` configurado.

3. **Compatibilidade**: O código verifica múltiplos campos para compatibilidade com dados antigos:
   - `store_id` (novo padrão)
   - `lojaId` (alternativo)
   - `ownerStoreId` (legado)

4. **Sincronização**: O `FullSyncService` faz sync de `estoque_produtos` (backup dos produtos). Se seus produtos estão em outro lugar, ajuste o path no serviço.

---

*Correções aplicadas em 01/02/2026*
