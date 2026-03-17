# 🔧 Problemas Pendentes - Lista Completa

**Data:** 22/12/2024
**Status:** Identificados e priorizados

---

## 🚨 CRÍTICO - Firestore Permissions

### Problema: Pre-Pedidos com PERMISSION_DENIED

**Log:**
```
W/Firestore: Write failed at lojas/masterpalm_gmail_com/pre_pedidos/...
I/flutter: ❌ Erro ao criar pré-pedido: [cloud_firestore/permission-denied]
```

**Causa:** Firestore Security Rules não permite escrita em `/lojas/{lojaId}/pre_pedidos/`

**Solução:**
```javascript
// firestore.rules
match /lojas/{lojaId}/pre_pedidos/{pedidoId} {
  // Leitura pública (para página pública funcionar)
  allow read: if true;

  // Escrita: qualquer usuário autenticado pode criar
  allow create: if request.auth != null;

  // Update/Delete: apenas o dono da loja
  allow update, delete: if request.auth != null &&
    get(/databases/$(database)/documents/lojas/$(lojaId)).data.ownerUid == request.auth.uid;
}
```

**Deploy:**
```bash
firebase deploy --only firestore:rules
```

---

## 📋 Problemas Reportados pelo Usuário

### 1. ❌ Vendas não aparecem no Relatório Financeiro

**Problema:** Vendas criadas na tela "Nova Venda" não aparecem no relatório financeiro

**Possíveis Causas:**
- [ ] Vendas não estão sendo sincronizadas com Firestore
- [ ] Filtro por `lojaId` incorreto no relatório
- [ ] Relatório lendo de fonte errada (Hive vs Firestore)

**Arquivos a investigar:**
- `lib/screens/vendas_screen.dart` - Criação de vendas
- `lib/screens/relatorio_financeiro_screen.dart` - Exibição
- `lib/services/vendas_firestore_service.dart` - Sincronização

**Debug:**
```dart
// Adicionar logs em vendas_screen.dart ao salvar venda
print('📊 Venda criada: ${venda.key}');
print('📊 LojaId: ${venda.lojaId}');
print('📊 Total: ${venda.total}');

// Adicionar logs em relatorio_financeiro_screen.dart
print('🔍 Buscando vendas para loja: $lojaId');
print('🔍 Vendas encontradas: ${vendas.length}');
```

---

### 2. ❌ Clientes do Catálogo não aparecem em Cadastro de Clientes

**Problema:** Clientes cadastrados via catálogo web não aparecem na tela "Clientes" e não salvam histórico

**Log encontrado:**
```
I/flutter: ✅ Venda do catálogo registrada com sucesso: 0
```

**Causa Provável:**
- `CatalogoVendaService` está criando vendas mas pode não estar salvando clientes corretamente
- Clientes podem estar sendo salvos em Hive mas não sincronizados com Firestore
- Filtro por `lojaId` pode estar errado

**Arquivos a verificar:**
- `lib/services/catalogo_venda_service.dart:60-145` - Criação de cliente
- `lib/screens/clientes_screen.dart` - Listagem de clientes
- `lib/services/clientes_firestore_service.dart` - Sincronização

**Correção Necessária:**
```dart
// catalogo_venda_service.dart - Verificar se cliente está sendo salvo
final clientesBox = await Hive.openBox<Cliente>('clientes');

// Buscar ou criar cliente
Cliente? cliente = clientesBox.values.firstWhereOrNull(
  (c) => c.telefone == customer['telefone'] && c.lojaId == lojaId,
);

if (cliente == null) {
  cliente = Cliente(
    nome: customer['nome'] ?? '',
    telefone: customer['telefone'] ?? '',
    // ... outros campos
    lojaId: lojaId, // ✅ IMPORTANTE
  );
  await clientesBox.add(cliente);

  // ✅ SINCRONIZAR COM FIRESTORE
  await ClientesFirestoreService.syncCliente(cliente, lojaId: lojaId);
}
```

---

### 3. ❌ Produtos Precificados não vão para Estoque

**Problema:** Produtos criados e precificados não aparecem na tela "Estoque"

**Causa Provável:**
- Produtos estão sendo salvos em box errado
- Existe `produtos` e `estoque` - podem estar separados
- Filtro por `lojaId` incorreto

**Arquivos a investigar:**
- `lib/screens/precificacao_universal_screen.dart` - Onde produtos são precificados
- `lib/screens/estoque_screen.dart` - Listagem de estoque
- `lib/services/produto_auto_sync_service.dart` - Auto-sync

**Log encontrado:**
```
I/flutter: 📝 [AUTO-SYNC] Produto modificado: colar (key: 0)
I/flutter: ✅ [PRODUTO SYNC] Salvando em Firestore: lojas/masterpalm_gmail_com/draft_produtos/...
```

**Possível Solução:**
```dart
// Verificar se produto está indo para box correto
final produtosBox = await Hive.openBox<Produto>('produtos');
final estoqueBox = await Hive.openBox<Produto>('estoque');

// Produto deve estar em AMBOS ou produto deve ser copiado para estoque
```

---

### 4. ❌ Produtos Excluídos/Zerados não saem do Catálogo

**Problema:** Produtos excluídos do estoque, com estoque zerado, ou com "Publicar no Catálogo" desativado não saem do catálogo rascunho ao clicar "Sincronizar"

**Regra de Negócio:**
```
Produto deve ser REMOVIDO do catálogo se:
- Produto foi excluído do estoque OU
- Estoque (quantidade) == 0 OU
- publicarNoCatalogo == false
```

**Log encontrado:**
```
I/flutter: Target: SyncTarget.draft (DRAFT)
I/flutter: Publicado: true
I/flutter: Quantidade: 10
I/flutter: EstoqueOk: true
I/flutter: DeveExistir: true
```

**Arquivo a modificar:**
`lib/services/produto_auto_sync_service.dart`

**Correção:**
```dart
// produto_auto_sync_service.dart
Future<void> syncProduto(Produto produto) async {
  final lojaId = await StoreResolverService.resolve();

  // ✅ VERIFICAR SE DEVE EXISTIR NO CATÁLOGO
  final deveExistir = produto.quantidade > 0 &&
                      (produto.publicarNoCatalogo ?? false) &&
                      !produto.isDeleted; // Adicionar flag isDeleted

  if (!deveExistir) {
    // ❌ REMOVER DO CATÁLOGO SE EXISTE
    await _removerDoCatalogo(produto, lojaId);
    return;
  }

  // ✅ Adicionar/atualizar normalmente
  await _salvarNoCatalogo(produto, lojaId);
}

Future<void> _removerDoCatalogo(Produto produto, String lojaId) async {
  final docId = '${lojaId}-${_slugify(produto.nome)}';

  // Remover de draft
  await FirebaseFirestore.instance
      .collection('lojas')
      .doc(lojaId)
      .collection('draft_produtos')
      .doc(docId)
      .delete();

  // Remover de publicado também
  await FirebaseFirestore.instance
      .collection('lojas')
      .doc(lojaId)
      .collection('produtos')
      .doc(docId)
      .delete();

  print('🗑️ Produto removido do catálogo: ${produto.nome}');
}
```

---

### 5. ❌ Falta Botão Preview na Tela Estoque

**Problema:** Não existe botão "Preview" na aba Estoque para ir direto ao rascunho do catálogo

**Solução:** Adicionar FloatingActionButton ou botão na AppBar

**Arquivo a modificar:**
`lib/screens/estoque_screen.dart`

**Implementação:**
```dart
// estoque_screen.dart
AppBar(
  title: Text('Estoque'),
  actions: [
    IconButton(
      icon: Icon(Icons.preview),
      tooltip: 'Preview do Catálogo (Rascunho)',
      onPressed: () async {
        final lojaId = await StoreResolverService.resolve();
        // Abrir preview do catálogo
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PublicCatalogScreen(
              lojaId: lojaId,
              isPreview: true, // ✅ Modo rascunho
            ),
          ),
        );
      },
    ),
  ],
)
```

---

### 6. ❌ Botão Mercado Pago não funciona

**Problema:** Botão "Mercado Pago" no checkout do catálogo não está funcionando

**Log encontrado:**
```
I/flutter: [PUBLIC] gateway = mp  | pixKey = 106.550.106-45
I/flutter: [PUBLIC] checkoutCfg = {
  mp: {
    public_key: APP_USR-eb2c30a6-a8f3-4c81-a525-f2183e59daaa,
    publicKey: null,
    token: null
  },
  gateway_default: mercadopago
}
```

**Observação:** Configuração existe, mas falta `access_token`

**Causas Possíveis:**
- [ ] `mp_access_token` está `null`
- [ ] Cloud Function não está configurada
- [ ] Integração com Mercado Pago incompleta
- [ ] Botão não está chamando função correta

**Arquivos a investigar:**
- `lib/screens/public_catalog_screen.dart` - Botão checkout MP
- `functions/index.js` - Cloud Function para MP
- `lib/services/config_pagamentos_screen.dart` - Configuração

**Debug:**
```dart
// public_catalog_screen.dart - no onPressed do botão MP
print('🔵 Checkout Mercado Pago iniciado');
print('🔵 Gateway: $gateway');
print('🔵 Public Key: ${checkoutCfg['mp']?['public_key']}');
print('🔵 Access Token: ${checkoutCfg['mp_access_token']}');

// Verificar se está chamando Cloud Function
```

---

## 🎯 Prioridade de Correção

### P0 - URGENTE (Bloqueadores)
1. ✅ **Firestore Permission Denied** - Pre-pedidos não funcionam
2. ❌ **Vendas não aparecem em Relatórios** - Core do negócio
3. ❌ **Clientes do catálogo não salvam** - Perda de dados

### P1 - ALTA (Funcionalidades Importantes)
4. ❌ **Produtos não vão para estoque** - Confusão no fluxo
5. ❌ **Produtos não saem do catálogo** - Sincronização quebrada
6. ❌ **Mercado Pago não funciona** - Método de pagamento principal

### P2 - MÉDIA (UX/Melhorias)
7. ❌ **Falta botão Preview no Estoque** - Produtividade
8. ⚠️ **Layout overflow** - Problema visual

---

## 📝 Checklist de Debug

### Para Vendas
- [ ] Adicionar logs em vendas_screen.dart ao criar venda
- [ ] Verificar se venda tem lojaId correto
- [ ] Verificar sincronização com Firestore
- [ ] Verificar query do relatório financeiro
- [ ] Testar criar venda e verificar em Firestore console

### Para Clientes
- [ ] Adicionar logs em catalogo_venda_service.dart ao criar cliente
- [ ] Verificar se cliente está indo para Hive
- [ ] Verificar sincronização com Firestore
- [ ] Verificar filtro por lojaId em clientes_screen.dart
- [ ] Verificar se histórico está sendo vinculado

### Para Produtos/Estoque
- [ ] Verificar diferença entre box 'produtos' e 'estoque'
- [ ] Adicionar logs em produto_auto_sync_service.dart
- [ ] Verificar lógica de DeveExistir no catálogo
- [ ] Implementar remoção de produtos do catálogo
- [ ] Adicionar botão Preview no estoque

### Para Mercado Pago
- [ ] Verificar se access_token está configurado
- [ ] Verificar se Cloud Function existe e está deployed
- [ ] Adicionar logs no botão de checkout
- [ ] Testar fluxo completo de pagamento

---

## 🔧 Próximos Passos Sugeridos

1. **Atualizar Firestore Rules** (imediato)
   ```bash
   firebase deploy --only firestore:rules
   ```

2. **Adicionar Logs de Debug** (investigação)
   - Vendas screen
   - Clientes service
   - Produto sync service
   - Checkout MP

3. **Corrigir Sincronizações** (correção)
   - Vendas → Relatórios
   - Clientes → Catálogo
   - Produtos → Estoque

4. **Implementar Remoção de Produtos** (nova feature)
   - Lógica de deve/não deve existir
   - Sincronização de deleção

5. **Configurar Mercado Pago** (integração)
   - Cloud Functions
   - Access Token
   - Webhook

---

**Autor:** Claude Sonnet 4.5
**Sessão:** Correção de Bugs - MasterPalm
**Última Atualização:** 22/12/2024 18:30
