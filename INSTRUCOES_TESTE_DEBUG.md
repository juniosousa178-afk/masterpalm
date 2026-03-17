# 🔍 INSTRUÇÕES PARA TESTE - DEBUG DE COR NO PEDIDO

## ✅ DEPLOY REALIZADO

**Data:** 2026-01-17
**URLs Atualizadas:**
- https://mastepalm.web.app
- https://masterpalm-58c46.web.app

---

## 🎯 OBJETIVO DO TESTE

Identificar POR QUE a cor está chegando vazia quando você adiciona um produto ao carrinho via navegador web.

Os logs de debug vão mostrar se:
1. O campo `variacoes` está populado ou null
2. O modal de seleção está abrindo ou não
3. O produto está indo direto pro carrinho sem seleção de cor

---

## 📋 PASSO A PASSO PARA TESTE

### Passo 1: Abrir o Console do Navegador

1. **Abra o Google Chrome** (ou seu navegador)
2. **Vá para:** https://mastepalm.web.app
3. **Pressione F12** (ou Ctrl + Shift + I) para abrir as Ferramentas do Desenvolvedor
4. **Clique na aba "Console"** (ou "Consola")
5. **IMPORTANTE:** Pressione **Ctrl + F5** para limpar o cache e recarregar

### Passo 2: Adicionar Produto ao Carrinho

1. **Localize o produto "Anel Amarelo"** no catálogo
2. **Clique no botão "Adicionar"** (ou "+" ou ícone de carrinho)
3. **OBSERVE O CONSOLE IMEDIATAMENTE**

### Passo 3: Identificar os Logs

Você verá uma linha separadora e logs no console, algo assim:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛒 [ADD BUTTON] Product: anel amarelo
   estoquePorTamanho: {...}
   estoquePorCor: {...}
   variacoes: {...}
   hasTamanhos: true/false
   hasCores: true/false
   hasVariacoes: true/false
✅ Opening selection modal
OU
❌ Adding to cart directly (NO VARIATIONS)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 🔍 CENÁRIOS POSSÍVEIS

### ✅ CENÁRIO ESPERADO (CORRETO)

```
🛒 [ADD BUTTON] Product: anel amarelo
   estoquePorTamanho: null
   estoquePorCor: null
   variacoes: {11: {azul: 3}, 12: {marrom: 5, rosa: 2}, 13: {rosa: 1}, 14: {amarelo: 10}}
   hasTamanhos: false
   hasCores: false
   hasVariacoes: true
✅ Opening selection modal
```

**O que deve acontecer:**
- O modal abre com seleção de tamanho
- Você seleciona tamanho 12
- O modal mostra as cores: marrom, rosa
- Você seleciona cor rosa
- O botão "Adicionar ao Carrinho" fica habilitado
- Produto vai para o carrinho com tamanho E cor

---

### ❌ CENÁRIO A (PROBLEMA: VARIAÇÕES NULL)

```
🛒 [ADD BUTTON] Product: anel amarelo
   estoquePorTamanho: null
   estoquePorCor: null
   variacoes: null  ← ❌ PROBLEMA AQUI!
   hasTamanhos: false
   hasCores: false
   hasVariacoes: false
❌ Adding to cart directly (NO VARIATIONS)
```

**Diagnóstico:** O produto não está carregando as variações do Firestore

**Solução:** Republicar o catálogo no sistema administrativo

---

### ❌ CENÁRIO B (PROBLEMA: ESTOQUE POR COR/TAMANHO POPULADO)

```
🛒 [ADD BUTTON] Product: anel amarelo
   estoquePorTamanho: {11: 3, 12: 7, 13: 1, 14: 10}
   estoquePorCor: {azul: 3, marrom: 5, rosa: 3, amarelo: 10}
   variacoes: {11: {azul: 3}, 12: {marrom: 5, rosa: 2}, ...}
   hasTamanhos: true
   hasCores: true
   hasVariacoes: true
✅ Opening selection modal
```

**Diagnóstico:** Modal abre, mas pode estar mostrando apenas tamanho OU apenas cor (campos antigos)

**Solução:** Verificar se o modal está usando `variacoes` corretamente

---

### ❌ CENÁRIO C (PROBLEMA: MODAL ABRE MAS NÃO MOSTRA CORES)

```
✅ Opening selection modal
```

Mas quando você seleciona o tamanho 12, NÃO aparecem as cores marrom/rosa.

**Diagnóstico:** Lógica `_coresDisponiveis` não está lendo corretamente de `variacoes`

**Solução:** Corrigir a função `_coresDisponiveis` no modal

---

## 📸 O QUE ENVIAR PARA MIM

Por favor, tire **screenshots** e me envie:

### 1. Screenshot do Console
Mostrando os logs que aparecem quando você clica em "Adicionar"

### 2. Screenshot do Modal (se abrir)
Mostrando:
- Opções de tamanho disponíveis
- Depois de selecionar tamanho 12: opções de cores disponíveis
- Se o botão "Adicionar ao Carrinho" está habilitado/desabilitado

### 3. Cópia dos Logs (Texto)
Copie e cole o texto que aparece no console entre as linhas `━━━━━`

---

## 🚨 SE O MODAL NÃO ABRIR

Se ao clicar em "Adicionar" o produto for **DIRETO para o carrinho** (sem abrir modal):

**Isso significa que:**
- `hasVariacoes: false`
- O campo `variacoes` está null ou vazio
- O produto foi adicionado com `tamanho: ''` e `cor: ''`

**Solução:**
1. Abra o sistema administrativo
2. Vá em "Produtos"
3. Edite o produto "Anel Amarelo"
4. Verifique se a grade de variações está preenchida
5. Clique em **"Publicar Catálogo"** (botão no topo)
6. Aguarde a publicação terminar
7. Teste novamente no navegador (com Ctrl + F5)

---

## 🔧 VERIFICAÇÃO ADICIONAL: FIRESTORE

Se quiser verificar diretamente no banco de dados:

1. **Acesse o Firebase Console:** https://console.firebase.google.com/project/masterpalm-58c46
2. **Vá em Firestore Database**
3. **Navegue até:** `lojas/{suaLojaId}/catalogo_publicado/{documentoId}`
4. **Procure o produto "Anel Amarelo"**
5. **Verifique o campo `variacoes`:**
   - Deve ser um mapa: `{11: {azul: 3}, 12: {marrom: 5, rosa: 2}, ...}`
   - Se estiver vazio ou não existir: o problema é na publicação

---

## ✅ APÓS COLETAR OS LOGS

Me envie as informações e eu vou:
1. **Identificar a causa raiz** exata do problema
2. **Aplicar a correção** necessária
3. **Fazer novo deploy** com a solução
4. **Testar novamente** para confirmar que está funcionando

---

## 💡 DICA IMPORTANTE

**SEMPRE pressione Ctrl + F5** antes de testar, para garantir que está usando a versão mais recente do site!

---

**Aguardo seus prints e logs!** 🔍
