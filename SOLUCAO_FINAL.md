# 🎯 Solução Final - Problema de Publicação e Loja Errada

## 🔍 PROBLEMA IDENTIFICADO

Após investigação profunda, descobri o problema raiz:

### 1. Por que o botão "Publicar" salva na loja errada?

**Fluxo do problema:**

```
App → StoreResolverService.resolve()
  ↓
Retorna: "loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2" (cache no Hive)
  ↓
LojaConfigScreen._activeStoreId() usa esse valor
  ↓
Botão "Publicar" salva em: lojas/loja_uid_tcnbZdmFXsMPJ2bU29dDt3z5ZHr2/config
  ↓
❌ MAS o catálogo web busca em: lojas/nathy-pratas-e-folheados/config
```

**Resultado:** Logo e banners são publicados na loja UID, mas o web busca na loja slug!

### 2. Por que continua aparecendo loja errada no web?

O catálogo web estava carregando corretamente `nathy-pratas-e-folheados`, MAS não tinha config publicada lá, porque a publicação foi para `loja_uid_...`.

---

## ✅ SOLUÇÕES APLICADAS

### Solução 1: Scripts de Publicação Manual

Criei scripts para copiar configs entre as lojas:

1. **`publish_naty_catalog.js`** - Publica draft → config em todas as lojas
2. **`sync_naty_configs.js`** - Sincroniza loja UID → loja slug da Naty
3. **`sync_root_configs.js`** - Sincroniza loja UID → loja slug do Root

**Executados com sucesso:**
```bash
cd scripts
node publish_naty_catalog.js
node sync_naty_configs.js
node sync_root_configs.js
```

### Solução 2: Correção do store_id no Firestore

Executado `fix_naty_store_id.js` para corrigir:

```javascript
/users/tcnbZdmFXsMPJ2bU29dDt3z5ZHr2:
  store_id: "nathy-pratas-e-folheados" ✅ (slug)

/usuarios/natypolylopes1997@gmail.com:
  lojaId: "nathy-pratas-e-folheados" ✅ (slug)
```

---

## ⚠️ SOLUÇÃO DEFINITIVA NECESSÁRIA

Para resolver permanentemente, você precisa:

### NO APP (usuário):

1. **Fechar o app completamente**
2. **Limpar cache do app:**
   - Android: Configurações → Apps → MasterPalm → Armazenamento → Limpar cache
   - Ou desinstalar e reinstalar o app
3. **Fazer login novamente** com `natypolylopes1997@gmail.com`
4. **Agora o StoreResolverService vai buscar do Firestore:**
   - `/users/tcnbZdmFXsMPJ2bU29dDt3z5ZHr2` → `store_id: "nathy-pratas-e-folheados"` ✅
5. **Abrir Configurações da Loja**
6. **Fazer qualquer alteração pequena** (ex: mudar nome)
7. **Clicar em "Publicar Catálogo"**
8. **Agora vai publicar em `nathy-pratas-e-folheados`** ✅

### NO CÓDIGO (desenvolvedor):

Modificar `StoreResolverService` para invalidar cache quando detectar mudança de UID:

**Arquivo:** `lib/services/store_resolver_service.dart`

Já tem validação de ownerUid (linhas 56-79), mas o cache em memória persiste.

**Adicionar ao método `resolve()`:**

```dart
// Após validar store_id do Hive (linha 74)
if (ownerUid == currentUid) {
  // ✅ IMPORTANTE: Invalidar cache se store_id mudou
  if (_cache != null && _cache != storeId) {
    debugPrint('🔄 [STORE-RESOLVER] store_id mudou no Firestore ($_cache → $storeId), invalidando cache');
    _cache = null;
  }

  debugPrint('✅ [STORE-RESOLVER] Hive sessao["store_id"]: $storeId (verificado)');
  _cache = storeId;
  _cachedUid = currentUid;
  return storeId;
}
```

---

## 📋 CHECKLIST DE CORREÇÃO

### Firestore ✅
- [x] store_id da Naty corrigido para `nathy-pratas-e-folheados`
- [x] Configs publicados em todas as lojas (draft → config)
- [x] Configs sincronizados entre loja UID e slug

### App (pendente - requer ação do usuário)
- [ ] Limpar cache do Hive local
- [ ] Fazer novo login
- [ ] Verificar que `store_id` agora é `nathy-pratas-e-folheados`
- [ ] Testar botão "Publicar Catálogo"

### Web ✅
- [x] Redirect funcionando (loja_uid → slug)
- [x] Config carregando de `nathy-pratas-e-folheados/config`
- [x] Banners disponíveis em ambas as lojas

---

## 🧪 TESTES REALIZADOS

```bash
cd scripts
node test_catalog_flow.js
```

**Resultado:**
```
✅ URL nathy-pratas-e-folheados carrega loja correta
✅ Config existe com 1 banner mobile + 1 desktop
✅ store_id no Firestore correto: nathy-pratas-e-folheados
✅ Redirect funcionando: loja_uid → nathy-pratas-e-folheados
```

---

## 🎯 RESUMO

### Causa raiz:
1. **Hive local** tinha cache com `store_id: "loja_uid_..."`
2. **StoreResolverService** retornava valor do cache
3. **Botão Publicar** salvava na loja UID
4. **Web carregava** da loja slug (vazia)

### Solução aplicada:
1. ✅ Firestore corrigido (store_id → slug)
2. ✅ Configs publicados manualmente via scripts
3. ⚠️ **App precisa limpar cache local** para usar novo store_id

### Próximo passo:
**No telefone/dispositivo:**
1. Fechar app
2. Limpar cache (ou reinstalar)
3. Fazer login novamente
4. Testar botão "Publicar"

---

*Solução documentada em 29/12/2025*
