# ✅ CORREÇÃO CRÍTICA - Firestore Merge Duplicando Variações

## 🔴 PROBLEMA RAIZ IDENTIFICADO E CORRIGIDO

### O Que Estava Acontecendo:

**Sintoma:**
- App mostra: `{13: {rosa: 1, preto: 1}, 11: {azul: 3}, 12: {rosa: 2}, 14: {amarelo: 10}}` ✅
- Firestore tem: `{13: {azul: 5, preta: 2, preto: 1, rosa: 1, sem-cor: 4}, 16: {azul: 3}}` ❌

**Causa Raiz:**

Nos arquivos de sincronização, o código estava usando `SetOptions(merge: true)`:

```dart
.set(produtoData, SetOptions(merge: true));  // ❌ ERRADO
```

Isso fazia com que o Firestore **COMBINASSE** os dados novos com os antigos, em vez de **SUBSTITUIR** completamente.

### Exemplo do Problema:

**Passo 1:** Produto tem variações:
```json
{
  "variacoes": {
    "13": {"azul": 5, "rosa": 2}
  }
}
```

**Passo 2:** Você edita no app e remove "azul", deixa apenas "rosa":
```json
{
  "variacoes": {
    "13": {"rosa": 1}
  }
}
```

**Passo 3:** App salva corretamente no Hive:
```
✅ Hive: {13: {rosa: 1}}
```

**Passo 4:** Sync para Firestore COM `merge: true`:
```
❌ Firestore: {13: {azul: 5, rosa: 1}}  <- "azul" NÃO foi removido!
```

**Resultado:** Firestore acumula variações antigas que foram deletadas!

---

## ✅ CORREÇÃO APLICADA

### Arquivo 1: `lib/services/produtos_firestore_service.dart`

**Linha 108** (antes linha 108):

```dart
// ANTES (ERRADO):
.set(produtoData, SetOptions(merge: true));

// DEPOIS (CORRETO):
.set(produtoData);  // ✅ Remove merge: true para substituir completamente
```

### Arquivo 2: `lib/services/catalogo_sync_service.dart`

**Linha 240** (antes linha 240):

```dart
// ANTES (ERRADO):
.set(data, SetOptions(merge: true));

// DEPOIS (CORRETO):
.set(data);  // ✅ Remove merge: true para substituir completamente
```

---

## 🧪 COMO TESTAR A CORREÇÃO

### IMPORTANTE: Limpar Dados Corrompidos Primeiro

Antes de testar, você precisa **LIMPAR as variações corrompidas** no Firestore.

### Opção 1: Limpar no App Desktop (RECOMENDADO)

1. **Abra o app desktop:**
   ```bash
   cd "C:\Users\Pichau\apk_nathy\temp_naty"
   flutter run -d windows
   ```

2. **Para cada produto com problema:**
   - Abra o produto
   - Veja a grade de variações
   - **Remova TODAS as linhas** (clicando em "−")
   - **Adicione UMA linha por vez** com as variações corretas:
     - Tam 13, Rosa, 1
     - Tam 13, Preto, 1
     - Tam 11, Azul, 3
     - Tam 12, Rosa, 2
     - Tam 14, Amarelo, 10
   - **Salve o produto**
   - **Vá em "Configurações" → "Publicar Catálogo"**

3. **Verifique no Firestore:**
   - Abra Firebase Console
   - Veja documento `draft_produtos/nathy-pratas-e-folheados-anel-amarelo`
   - Campo `variacoes` deve ter APENAS as variações corretas
   - Campo `estoquePorTamanho` deve estar correto
   - **NÃO DEVE TER** size 16 ou cores antigas

---

### Opção 2: Limpar Direto no Firestore (Mais Rápido)

1. **Abra Firebase Console:**
   - https://console.firebase.google.com/project/masterpalm-58c46

2. **Vá em Firestore Database**

3. **Navegue até:**
   - `lojas` → `nathy-pratas-e-folheados` → `draft_produtos` → `nathy-pratas-e-folheados-anel-amarelo`

4. **Edite o documento:**
   - Clique no documento
   - **DELETE o campo `variacoes` completamente** (clique no X ao lado)
   - **DELETE o campo `estoquePorTamanho`** (se existir)
   - Salve

5. **No app desktop:**
   - Abra o produto "anel amarelo"
   - Configure as variações:
     - Tam 13, Rosa, 1
     - Tam 13, Preto, 1
     - Tam 11, Azul, 3
     - Tam 12, Rosa, 2
     - Tam 14, Amarelo, 10
   - **Salve**
   - **Publicar Catálogo**

6. **Verifique Firestore novamente:**
   - O campo `variacoes` deve ter sido recriado CORRETAMENTE
   - Agora SEM `merge: true`, os dados serão **SUBSTITUÍDOS** completamente

---

## 📊 TESTE DE EDIÇÃO DE VARIAÇÃO

Após limpar os dados corrompidos, teste se a correção funciona:

### Teste 1: Editar Tamanho e Cor

**Estado Inicial:**
```
Tam 13  Rosa   1
Tam 13  Preto  1
Tam 11  Azul   3
Tam 12  Rosa   2
Tam 14  Amarelo 10
Total: 17un
```

**Ação:**
1. Abra produto no app
2. **Edite linha 1:** Mude "Tam 13 Rosa 1" para "Tam 16 Verde 5"
3. **Salve**

**Resultado ESPERADO no Firestore:**
```json
{
  "variacoes": {
    "16": {"Verde": 5},      // ✅ Nova variação
    "13": {"Preto": 1},      // ✅ "Rosa" foi REMOVIDO
    "11": {"Azul": 3},
    "12": {"Rosa": 2},
    "14": {"Amarelo": 10}
  },
  "quantidade": 21
}
```

**❌ ANTES DA CORREÇÃO (com merge: true):**
```json
{
  "variacoes": {
    "16": {"Verde": 5},
    "13": {"Rosa": 1, "Preto": 1},  // ❌ "Rosa" NÃO foi removido
    "11": {"Azul": 3},
    "12": {"Rosa": 2},
    "14": {"Amarelo": 10}
  },
  "quantidade": 22  // ❌ Errado (conta "Rosa" duplicado)
}
```

---

### Teste 2: Remover Variação

**Estado Inicial:**
```
Tam 13  Preto   1
Tam 11  Azul    3
Tam 12  Rosa    2
Tam 14  Amarelo 10
Tam 16  Verde   5
Total: 21un
```

**Ação:**
1. Abra produto
2. **Remova linha 5** (Tam 16 Verde 5) - clique no "−"
3. **Salve**

**Resultado ESPERADO no Firestore:**
```json
{
  "variacoes": {
    "13": {"Preto": 1},
    "11": {"Azul": 3},
    "12": {"Rosa": 2},
    "14": {"Amarelo": 10}
    // ✅ Size 16 REMOVIDO completamente
  },
  "quantidade": 16
}
```

**❌ ANTES DA CORREÇÃO:**
```json
{
  "variacoes": {
    "13": {"Preto": 1},
    "11": {"Azul": 3},
    "12": {"Rosa": 2},
    "14": {"Amarelo": 10},
    "16": {"Verde": 5}  // ❌ Size 16 NÃO foi removido
  },
  "quantidade": 21  // ❌ Errado
}
```

---

## 🔧 PRÓXIMOS PASSOS

### PASSO 1: Limpar Dados Corrompidos

Escolha Opção 1 (app) OU Opção 2 (Firestore direto) acima.

### PASSO 2: Testar Edição de Variações

Execute os testes 1 e 2 acima.

### PASSO 3: Publicar Catálogo

Após limpar e testar:
1. App desktop → "Configurações"
2. Clicar em "Publicar Catálogo"
3. Aguardar sincronização completa

### PASSO 4: Verificar Catálogo Web

1. Abrir catálogo: https://mastepalm.web.app
2. **Limpar cache:** Ctrl + F5
3. Abrir produto "anel amarelo"
4. Clicar em "Adicionar ao Carrinho"
5. **Verificar modal:**
   - ✅ Deve mostrar apenas tamanhos: 11, 12, 13, 14
   - ✅ **NÃO DEVE** mostrar tamanho 16
   - ✅ Ao selecionar tam 13, deve mostrar apenas cores: Rosa, Preto
   - ✅ **NÃO DEVE** mostrar cores antigas: azul, preta, sem-cor

---

## 📝 RESUMO DAS CORREÇÕES

| Problema | Antes | Depois |
|----------|-------|--------|
| Sync usa merge | `SetOptions(merge: true)` | `SetOptions()` removido |
| Editar variação | ❌ Acumula antiga + nova | ✅ Substitui completamente |
| Remover variação | ❌ Permanece no Firestore | ✅ Removido do Firestore |
| Tamanhos phantom | ❌ Size 16 aparece | ✅ Removido |
| Cores antigas | ❌ "azul", "preta", "sem-cor" | ✅ Removidas |
| Total de estoque | ❌ Soma duplicatas | ✅ Soma correta |

---

## 🐛 SE AINDA TIVER PROBLEMA

Se após limpar os dados e testar ainda houver duplicação:

1. **Capture logs do terminal:**
   ```bash
   flutter run -d windows
   ```
   - Abra produto
   - Edite variação
   - Salve
   - **COPIE TODO o log do terminal**
   - Me envie

2. **Screenshot do Firestore:**
   - Após salvar, tire screenshot do campo `variacoes` no Firestore
   - Me envie

3. **Descreva:**
   - O que você fez (passos)
   - O que esperava
   - O que aconteceu

---

## ✅ STATUS

**Data:** 2026-01-17
**Arquivos Modificados:**
- `lib/services/produtos_firestore_service.dart` linha 108
- `lib/services/catalogo_sync_service.dart` linha 240

**Correção:** ✅ Aplicada
**Teste:** ⏳ Aguardando você limpar dados e testar
**Deploy:** ⏳ Aguardando confirmação de que funciona

**IMPORTANTE:** Não faça deploy ainda! Primeiro limpe os dados corrompidos e teste localmente.
