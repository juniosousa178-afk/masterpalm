# 🔐 Correção: Validação de Propriedade de Loja

## ❌ Problema Identificado (Novo)

Mesmo com a correção anterior do cache por UID, o usuário `masterpalm@gmail.com` ainda estava acessando `joao-stores`.

### Análise do Log:

```
I/flutter: ✅ Usuário previamente logado: masterpalm@gmail.com
I/flutter: sessao["store_id"] → joao-stores
I/flutter: ✅ [STORE-RESOLVER] Firestore users/{uid}.store_id: joao-stores
```

**Causa Raiz**: Os **dados salvos estavam corrompidos**:
- Hive tinha `store_id: joao-stores`
- Firestore `users/vd0X6xXlq4be0cKhmIOiDtXTvKb2` tinha `store_id: joao-stores`
- MAS `masterpalm@gmail.com` **NÃO é o dono** de `joao-stores`!

Isso aconteceu porque:
1. Algum momento houve compartilhamento de loja entre usuários
2. Os dados ficaram salvos mesmo após logout
3. A validação apenas checava existência, não propriedade

---

## ✅ Solução Implementada

### Validação de Propriedade em TODAS as Fontes

Adicionado validação dupla que verifica:
1. ✅ `store_id` existe?
2. ✅ `lojas/{store_id}.ownerUid` == UID do usuário atual?

Se a loja não pertencer ao usuário → **Limpa dados corrompidos** e busca/cria loja própria.

---

## 🔧 Mudanças no Código

### 1. Validação no Hive (Passo 2)

```dart
// 2️⃣ Hive sessao["store_id"] (com validação de propriedade)
try {
  final sessao = await _openBox('sessao');
  final storeId = (sessao.get('store_id') ?? '').toString().trim();

  if (storeId.isNotEmpty) {
    // ⚠️ VALIDAR SE A LOJA REALMENTE PERTENCE A ESTE USUÁRIO
    if (currentUid != null) {
      try {
        final lojaDoc = await FirebaseFirestore.instance
            .collection('lojas')
            .doc(storeId)
            .get();

        if (lojaDoc.exists) {
          final lojaData = lojaDoc.data() ?? {};
          final ownerUid = (lojaData['ownerUid'] ?? '').toString();

          if (ownerUid == currentUid) {
            // ✅ Loja pertence ao usuário, tudo ok
            debugPrint('✅ [STORE-RESOLVER] Hive sessao["store_id"]: $storeId (verificado)');
            _cache = storeId;
            _cachedUid = currentUid;
            return storeId;
          } else {
            // ❌ Loja NÃO pertence ao usuário! Dados corrompidos
            debugPrint('🚨 [STORE-RESOLVER] Hive store_id ($storeId) NÃO pertence ao usuário');
            debugPrint('   Owner: $ownerUid, Atual: $currentUid');
            debugPrint('🧹 [STORE-RESOLVER] Limpando Hive corrompido...');
            await clear(); // Limpa Hive
            // Continuar para próxima etapa
          }
        } else {
          debugPrint('⚠️ [STORE-RESOLVER] Loja $storeId não existe mais, limpando...');
          await clear();
        }
      } catch (e) {
        debugPrint('⚠️ [STORE-RESOLVER] Erro ao validar loja: $e');
      }
    }
  }
}
```

### 2. Validação no Firestore users (Passo 3)

```dart
// 3️⃣ Firestore users/{uid}.store_id (com validação de propriedade)
final user = FirebaseAuth.instance.currentUser;
if (user != null) {
  try {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (userDoc.exists) {
      final data = userDoc.data() ?? {};
      final storeId = (data['store_id'] ?? '').toString().trim();

      if (storeId.isNotEmpty) {
        // ⚠️ VALIDAR SE A LOJA REALMENTE PERTENCE A ESTE USUÁRIO
        final lojaDoc = await FirebaseFirestore.instance
            .collection('lojas')
            .doc(storeId)
            .get();

        if (lojaDoc.exists) {
          final lojaData = lojaDoc.data() ?? {};
          final ownerUid = (lojaData['ownerUid'] ?? '').toString();

          if (ownerUid == user.uid) {
            // ✅ Loja pertence ao usuário, tudo ok
            debugPrint('✅ [STORE-RESOLVER] Firestore store_id: $storeId (verificado)');
            await _persist(storeId);
            _cache = storeId;
            _cachedUid = currentUid;
            return storeId;
          } else {
            // ❌ Loja NÃO pertence ao usuário! Dados corrompidos
            debugPrint('🚨 [STORE-RESOLVER] Firestore store_id ($storeId) NÃO pertence ao usuário');
            debugPrint('   Owner: $ownerUid, Atual: ${user.uid}');
            debugPrint('🧹 [STORE-RESOLVER] Limpando dados corrompidos...');

            // Limpar Hive
            await clear();

            // Limpar Firestore users/{uid}.store_id
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .update({'store_id': FieldValue.delete()});

            // Continuar para próxima etapa (criar/buscar loja própria)
          }
        } else {
          debugPrint('⚠️ [STORE-RESOLVER] Loja $storeId não existe mais');
        }
      }
    }
  } catch (e) {
    debugPrint('⚠️ [STORE-RESOLVER] Erro ao ler Firestore users: $e');
  }

  // 4️⃣ Firestore lojas WHERE ownerUid == uid (busca loja própria)
  // ... código continua buscando loja do usuário
}
```

---

## 🔄 Fluxo Corrigido

### Cenário: masterpalm@gmail.com com Dados Corrompidos

```
1. App inicia, usuário já logado: masterpalm@gmail.com
   UID: vd0X6xXlq4be0cKhmIOiDtXTvKb2
   ↓

2. resolve() chamado
   ↓

3. Verifica Hive: store_id = "joao-stores"
   ↓

4. Valida propriedade:
   GET /lojas/joao-stores
   lojaData.ownerUid = "WyQfWovmdXh5H1bVhWtO1lLdHFJ3" (jj12@gmail.com)
   ↓

5. ❌ ownerUid != currentUid
   🚨 DADOS CORROMPIDOS DETECTADOS!
   ↓

6. Limpa Hive:
   - sessao.delete('store_id')
   - config.delete('store_id')
   ↓

7. Verifica Firestore users/{uid}:
   GET /users/vd0X6xXlq4be0cKhmIOiDtXTvKb2
   store_id = "joao-stores"
   ↓

8. Valida propriedade:
   GET /lojas/joao-stores
   lojaData.ownerUid = "WyQfWovmdXh5H1bVhWtO1lLdHFJ3"
   ↓

9. ❌ ownerUid != currentUid
   🚨 DADOS CORROMPIDOS NO FIRESTORE!
   ↓

10. Limpa Firestore:
    UPDATE /users/vd0X6xXlq4be0cKhmIOiDtXTvKb2
    SET store_id = DELETE
    ↓

11. Busca loja própria:
    GET /lojas WHERE ownerUid == vd0X6xXlq4be0cKhmIOiDtXTvKb2
    ↓

12. ✅ Encontra: loja_uid_vd0X6xXlq4be0cKhmIOiDtXTvKb2
    ↓

13. Salva em Hive e Firestore:
    - Hive: store_id = "loja_uid_vd0X6xXlq4be0cKhmIOiDtXTvKb2"
    - Firestore users: store_id = "loja_uid_vd0X6xXlq4be0cKhmIOiDtXTvKb2"
    - Cache: _cache + _cachedUid
    ↓

14. ✅ Usuário acessa SUA PRÓPRIA loja
```

---

## 📊 Logs Esperados

### Antes (Dados Corrompidos):

```
I/flutter: ✅ Usuário previamente logado: masterpalm@gmail.com
I/flutter: sessao["store_id"] → joao-stores
I/flutter: ✅ [STORE-RESOLVER] Hive sessao["store_id"]: joao-stores
I/flutter: ✅ [CATÁLOGO] lojaId do StoreContext: joao-stores  ← ❌ ERRADO!
```

### Depois (Com Validação):

```
I/flutter: ✅ Usuário previamente logado: masterpalm@gmail.com
I/flutter: sessao["store_id"] → joao-stores
I/flutter: 🚨 [STORE-RESOLVER] Hive store_id (joao-stores) NÃO pertence ao usuário
I/flutter:    Owner: WyQfWovmdXh5H1bVhWtO1lLdHFJ3, Atual: vd0X6xXlq4be0cKhmIOiDtXTvKb2
I/flutter: 🧹 [STORE-RESOLVER] Limpando Hive corrompido...
I/flutter: 🗑️ [STORE-RESOLVER] Limpando store_id...
I/flutter: ✅ [STORE-RESOLVER] store_id limpo

I/flutter: 🚨 [STORE-RESOLVER] Firestore store_id (joao-stores) NÃO pertence ao usuário
I/flutter:    Owner: WyQfWovmdXh5H1bVhWtO1lLdHFJ3, Atual: vd0X6xXlq4be0cKhmIOiDtXTvKb2
I/flutter: 🧹 [STORE-RESOLVER] Limpando dados corrompidos...

I/flutter: ✅ [STORE-RESOLVER] Firestore lojas WHERE ownerUid: loja_uid_vd0X6xXlq4be0cKhmIOiDtXTvKb2
I/flutter: ✅ [CATÁLOGO] lojaId: loja_uid_vd0X6xXlq4be0cKhmIOiDtXTvKb2  ← ✅ CORRETO!
```

---

## 🔒 Camadas de Segurança

### Camada 1: Cache com UID
- Cache só válido se UID não mudou
- Limpa automaticamente ao trocar usuário

### Camada 2: Validação de Propriedade no Hive
- Antes de usar `store_id` do Hive
- Verifica `lojas/{id}.ownerUid == currentUid`
- Limpa se não pertencer

### Camada 3: Validação de Propriedade no Firestore
- Antes de usar `users/{uid}.store_id`
- Verifica `lojas/{id}.ownerUid == currentUid`
- Limpa Hive E Firestore se não pertencer

### Camada 4: Busca Garantida por ownerUid
- Query: `lojas WHERE ownerUid == uid`
- **Sempre** retorna loja(s) do usuário
- Impossível retornar loja de outro usuário

---

## ✅ Garantias Fornecidas

1. **Isolamento Total**: Usuário NUNCA acessa loja de outro
2. **Auto-Correção**: Dados corrompidos são automaticamente limpos
3. **Persistência Correta**: Sempre salva loja do próprio usuário
4. **Multi-Dispositivo**: Sincronização via Firestore após limpeza
5. **Sem Intervenção Manual**: Correção automática na primeira execução

---

## 🧪 Casos de Teste

### Teste 1: Dados Corrompidos no Hive

- [ ] Manualmente setar Hive `store_id` de outra loja
- [ ] Abrir app
- [ ] ✅ Verificar que detecta corrupção
- [ ] ✅ Verificar que limpa Hive
- [ ] ✅ Verificar que acessa loja própria

### Teste 2: Dados Corrompidos no Firestore

- [ ] Manualmente setar Firestore `users/{uid}.store_id` de outra loja
- [ ] Abrir app
- [ ] ✅ Verificar que detecta corrupção
- [ ] ✅ Verificar que limpa Firestore e Hive
- [ ] ✅ Verificar que acessa loja própria

### Teste 3: Loja Inexistente

- [ ] Setar `store_id` de loja que não existe
- [ ] Abrir app
- [ ] ✅ Verificar que limpa dados
- [ ] ✅ Verificar que busca/cria loja própria

### Teste 4: Usuário com Loja Válida

- [ ] Usuário com `store_id` correto
- [ ] Abrir app
- [ ] ✅ Verificar que validação passa
- [ ] ✅ Verificar que acessa normalmente (sem limpeza)

---

## 📁 Arquivo Modificado

### `lib/services/store_resolver_service.dart`

**Mudanças:**

1. ✅ Passo 2 (Hive): Adicionada validação de propriedade
   - Busca loja no Firestore
   - Compara `ownerUid` com `currentUid`
   - Limpa se não pertencer

2. ✅ Passo 3 (Firestore users): Adicionada validação de propriedade
   - Busca loja no Firestore
   - Compara `ownerUid` com `currentUid`
   - Limpa Hive E Firestore se não pertencer

3. ✅ Limpeza automática de dados corrompidos
4. ✅ Continuação para próxima etapa após limpeza

**Linhas modificadas:**
- Linha 50-92: Validação no Hive
- Linha 94-152: Validação no Firestore users

---

## 🎯 Resultado Esperado

Agora quando `masterpalm@gmail.com` logar:

```
✅ Detecta que joao-stores não pertence a ele
✅ Limpa Hive automaticamente
✅ Limpa Firestore users/{uid} automaticamente
✅ Busca loja própria: loja_uid_vd0X6xXlq4be0cKhmIOiDtXTvKb2
✅ Salva loja correta em Hive e Firestore
✅ Próximos logins usam loja correta
```

---

**Data:** 22/12/2024
**Versão:** 3.0 - Validação de Propriedade de Loja
**Status:** ✅ Implementado
**Arquivo:** `lib/services/store_resolver_service.dart`
**Correção:** Dados corrompidos são automaticamente detectados e limpos
