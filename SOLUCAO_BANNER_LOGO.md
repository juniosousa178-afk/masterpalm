# 🔧 Solução para Banner e Logo Não Aparecerem

**Data:** 28/12/2025
**Problema:** Banner e logo não aparecem no catálogo após limpeza do Firestore

---

## 🔍 DIAGNÓSTICO COMPLETO

### Problema Identificado:

Após a limpeza do Firestore, o aplicativo está carregando a **LOJA ERRADA** que não tem logo/banners configurados.

**Lojas Existentes:**

| Loja ID | Logo | Banners | Produtos |
|---------|------|---------|----------|
| `loja_uid_vd0X6xXlq4be0cKhmIOiDtXTvKb2` | ✅ SIM | ✅ 2 mobile | 3 |
| `masterpalm_gmail_com` | ❌ NÃO | ❌ NÃO | 4 |
| `nathy` | ❌ NÃO | ❌ NÃO | 0 |
| `nathy-pratas-e-folheados` | ❌ NÃO | ❌ NÃO | 1 |

**Loja que DEVE ser usada:** `loja_uid_vd0X6xXlq4be0cKhmIOiDtXTvKb2`
**Loja que ESTÁ sendo usada:** Provavelmente `masterpalm_gmail_com` ou outra

---

## ✅ CORREÇÕES APLICADAS NO FIRESTORE

Já executamos os seguintes scripts para corrigir o Firestore:

1. ✅ **Todas as lojas agora têm `ownerUid`** definido corretamente
2. ✅ **Usuário root tem `store_id`** apontando para loja correta
3. ✅ **Loja padrão configurada** como `loja_uid_vd0X6xXlq4be0cKhmIOiDtXTvKb2`

---

## 🚀 SOLUÇÃO (3 PASSOS SIMPLES)

### Passo 1: Fazer Logout

1. Abrir o app
2. Clicar no menu lateral (☰)
3. Clicar em **"Sair"**

### Passo 2: Limpar Dados do App (IMPORTANTE!)

**Opção A - Desinstalar e Reinstalar (RECOMENDADO):**
1. Desinstalar o aplicativo MasterPalm
2. Reinstalar o aplicativo

**Opção B - Limpar Cache (se não quiser desinstalar):**
1. Ir em Configurações do Windows
2. Aplicativos → MasterPalm → Opções avançadas
3. Limpar dados e cache

### Passo 3: Fazer Login Novamente

1. Abrir o app
2. Fazer login com `masterpalm@gmail.com`
3. O app vai buscar a loja correta do Firestore
4. A loja `loja_uid_vd0X6xXlq4be0cKhmIOiDtXTvKb2` será carregada
5. Logo e banners vão aparecer! ✨

---

## 🎯 O QUE DEVE ACONTECER

Após seguir os passos acima:

✅ **Logo deve aparecer** no topo do catálogo
✅ **Banners mobile devem aparecer** (2 banners configurados)
✅ **Produtos corretos** da loja (anel, anel x, colar)
✅ **Tema configurado** (cores corretas)

---

## 🔍 VERIFICAÇÃO

Para confirmar que está na loja correta, verifique:

1. **No catálogo web:**
   - URL deve terminar em `/loja/loja_uid_vd0X6xXlq4be0cKhmIOiDtXTvKb2`
   - OU se acessar sem slug, deve carregar essa loja por padrão

2. **No app:**
   - Ir em Configurações da Loja
   - Verificar que está editando a loja `loja_uid_vd0X6xXlq4be0cKhmIOiDtXTvKb2`

---

## 📝 SE AINDA NÃO FUNCIONAR

Se após os 3 passos acima o logo/banners ainda não aparecerem:

### 1. Verificar se está na loja correta:

Execute este comando no terminal (pasta scripts):
```bash
node check_catalog_config.js
```

Procure por:
```
🏪 Loja: loja_uid_vd0X6xXlq4be0cKhmIOiDtXTvKb2
   Logo Mobile: CONFIGURADO ← Deve estar CONFIGURADO
   Banners Mobile: 2 banner(s) ← Deve ter 2 banners
```

### 2. Re-publicar a configuração:

1. Fazer login no app
2. Ir em menu → **Configurações da Loja**
3. Verificar que tem logo e banners (devem aparecer na tela)
4. Clicar em **"Publicar Catálogo"** (botão azul no topo)
5. Aguardar mensagem de sucesso
6. Abrir catálogo novamente

### 3. Configurar logo/banners manualmente:

Se a loja `loja_uid_vd0X6xXlq4be0cKhmIOiDtXTvKb2` perdeu as configurações:

1. Ir em menu → **Configurações da Loja**
2. Rolar até "Mídia"
3. **Logo Desktop:** Fazer upload da imagem
4. **Logo Mobile:** Fazer upload da imagem
5. **Banners Mobile:** Adicionar banners (clica em +)
6. Clicar em **"Salvar Rascunho"**
7. Clicar em **"Publicar Catálogo"**

---

## 🛠️ SCRIPTS EXECUTADOS (Para Referência)

Já foram executados automaticamente:

1. ✅ `set_default_store.js` - Definiu loja padrão no Firestore
2. ✅ `fix_store_owner.js` - Adicionou ownerUid em todas as lojas
3. ✅ `check_catalog_config.js` - Verificou configurações
4. ✅ `check_products_catalog.js` - Verificou produtos
5. ✅ `find_deleted_products.js` - Procurou produtos com problemas

**Resultado:** Todos os dados estão corretos no Firestore!

O problema está no **CACHE LOCAL** do app que ainda aponta para a loja errada.

---

## 📊 INFORMAÇÕES TÉCNICAS

### Por que isso aconteceu?

1. Após a limpeza do Firestore, algumas lojas foram recriadas
2. O cache local (Hive) do app ficou com referência à loja antiga
3. O `StoreResolverService` usa cache primeiro, depois Firestore
4. Por isso continua carregando a loja errada

### Como a correção funciona?

1. **Logout:** Não limpa o cache completamente
2. **Desinstalar/Limpar dados:** Remove todo o cache local (Hive)
3. **Login novamente:** App busca loja do Firestore
4. **StoreResolverService resolve corretamente:**
   - Busca `users/{uid}.store_id` → `loja_uid_vd0X6xXlq4be0cKhmIOiDtXTvKb2`
   - Carrega essa loja (que TEM logo e banners)
   - Sucesso! ✨

---

## ✅ RESUMO

**PROBLEMA:** Cache local apontando para loja sem logo/banners

**SOLUÇÃO:**
1. Fazer logout
2. Desinstalar e reinstalar app (ou limpar dados)
3. Fazer login novamente

**RESULTADO:** Logo e banners vão aparecer!

---

*Se precisar de ajuda adicional, verifique os logs do console ao abrir o catálogo. Procure por `[STORE-RESOLVER]` para ver qual loja está sendo carregada.*
