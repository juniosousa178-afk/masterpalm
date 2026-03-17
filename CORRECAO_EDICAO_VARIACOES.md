# ✅ CORREÇÃO - Edição de Variações Duplicando Estoque

## 🔴 PROBLEMA IDENTIFICADO

Quando você **edita** uma variação existente no cadastro de produtos:

### Exemplo:
**Produto:** Anel
**Variações Originais:**
- Tam 13 Rosa: 2un
- Tam 12 Azul: 3un
- Tam 13 Azul: 5un
- **Total:** 10un

**Você edita:** Tam 13 Azul 5un → Tam 14 Rosa 2un

**Resultado ERRADO (antes da correção):**
- Tam 13 Rosa: 2un
- Tam 12 Azul: 3un
- **Tam 13 Azul: 5un** ← Variação antiga não foi removida!
- Tam 14 Rosa: 2un ← Nova variação adicionada
- **Total:** 12un ❌ (deveria ser 7un)

### Causa Raiz:

No arquivo `produto_form_screen.dart` linha 325, o código estava **SOMANDO** quantidades:

```dart
// ANTES (ERRADO):
mapaInterno[corFinal] = (mapaInterno[corFinal] ?? 0) + qtd;
```

Isso fazia com que se você tivesse duas linhas com **mesma combinação** tamanho+cor:
- Linha 1: Tam 14 Rosa 2un
- Linha 3 (antiga não removida): Tam 14 Rosa 2un
- **Resultado:** Tam 14 Rosa: 4un ❌

---

## ✅ CORREÇÃO APLICADA

### Mudança no Código:

**Arquivo:** `lib/screens/produto_form_screen.dart`
**Linha:** 329

```dart
// DEPOIS (CORRETO):
mapaInterno[corFinal] = qtd;  // ✅ SUBSTITUIR em vez de SOMAR
```

**Explicação:**
- Agora, se houver duas linhas com a mesma combinação tamanho+cor, a **última sobrescreve** a primeira
- Se você editar "Tam 13 Azul" para "Tam 14 Rosa", apenas a nova combinação ficará no estoque
- O estoque total será recalculado corretamente

---

## 🔧 COMO FUNCIONA AGORA

### Fluxo Correto:

1. **Carregar Produto:**
   ```
   _gradeVariacoes = [
     {tamanho: "13", cor: "Rosa", qtd: "2"},
     {tamanho: "12", cor: "Azul", qtd: "3"},
     {tamanho: "13", cor: "Azul", qtd: "5"},
   ]
   ```

2. **Editar Linha (usuário muda valores nos campos):**
   ```
   Linha 3: tamanho="14", cor="Rosa", qtd="2"

   _gradeVariacoes = [
     {tamanho: "13", cor: "Rosa", qtd: "2"},
     {tamanho: "12", cor: "Azul", qtd: "3"},
     {tamanho: "14", cor: "Rosa", qtd: "2"},  ← Editado
   ]
   ```

3. **Salvar - Construir variacoesMap:**
   ```dart
   Loop linha 1: variacoesMap["13"]["Rosa"] = 2
   Loop linha 2: variacoesMap["12"]["Azul"] = 3
   Loop linha 3: variacoesMap["14"]["Rosa"] = 2  ← Sobrescreve se já existir

   Resultado:
   {
     "13": {"Rosa": 2},
     "12": {"Azul": 3},
     "14": {"Rosa": 2}
   }
   Total: 7un ✅
   ```

4. **Salvar no Hive e Firestore:**
   - Campo `variacoes` é **completamente substituído** (linha 425)
   - Variação "13 Azul 5un" é **removida automaticamente**
   - Sincronização para Firestore, draft e live

---

## 🐛 PROBLEMA ADICIONAL: "No catálogo aparece todos mas no cadastro não"

Se após a correção você ainda vê variações antigas **apenas no catálogo web**, isso indica:

### Possível Causa 1: Cache do Firestore

O catálogo web pode estar lendo dados em cache do Firestore.

**Solução:**
1. Abra produto no app desktop
2. Clique em "Salvar" (mesmo sem alterar nada)
3. Aguarde sincronização
4. Vá em "Configurações da Loja" → "Publicar Catálogo"
5. No catálogo web: Ctrl + F5 (limpar cache)

### Possível Causa 2: Variações Duplicadas na Grade

Se ao abrir o produto no app você vê linhas duplicadas na grade de variações:

**Exemplo:**
```
Tam 13  Rosa  2
Tam 12  Azul  3
Tam 14  Rosa  2
Tam 14  Rosa  2  ← DUPLICADA
```

**Solução Manual:**
1. Clique no botão **"−"** (remover) nas linhas duplicadas
2. Salve o produto
3. Verifique o estoque total

**Prevenção:**
- Não adicione linhas manualmente com combinações já existentes
- Se precisar alterar quantidade, **edite** a linha existente, não adicione nova

---

## 📊 COMO VERIFICAR SE ESTÁ CORRETO

### 1. No App Desktop:

1. **Abrir produto**
2. **Ver grade de variações:**
   - Cada combinação tamanho+cor deve aparecer **UMA VEZ** apenas
   - Se houver duplicadas, remova manualmente

3. **Salvar produto**
4. **Verificar estoque total:**
   - Deve ser a soma de TODAS as quantidades das variações
   - Exemplo: 2 + 3 + 2 = 7un

### 2. No Firebase Console:

1. **Abrir Firestore Database**
2. **Navegar:** `lojas/{sua-loja}/estoque_produtos/{produto-id}`
3. **Verificar campo `variacoes`:**
   ```json
   {
     "variacoes": {
       "13": {"Rosa": 2},
       "12": {"Azul": 3},
       "14": {"Rosa": 2}
     },
     "quantidade": 7
   }
   ```

4. **Cada combinação deve aparecer UMA VEZ apenas**

### 3. No Catálogo Web:

1. **Limpar cache:** Ctrl + F5
2. **Abrir produto**
3. **Clicar "Adicionar ao Carrinho"**
4. **Verificar opções no modal:**
   - Tamanhos: deve mostrar apenas os tamanhos únicos (12, 13, 14)
   - Cores: deve filtrar por tamanho selecionado
   - Ao selecionar tam 14, deve mostrar apenas "Rosa"
   - Ao selecionar tam 13, deve mostrar apenas "Rosa"
   - Ao selecionar tam 12, deve mostrar apenas "Azul"

---

## 🧹 COMO LIMPAR VARIAÇÕES DUPLICADAS

Se você já tem produtos com variações duplicadas:

### Opção 1: Limpar Manualmente no App

Para cada produto com problema:

1. **Abrir produto no app desktop**
2. **Na grade de variações:**
   - Procure linhas com MESMA combinação tamanho+cor
   - Clique no botão **"−"** para remover duplicadas
   - Deixe apenas UMA linha de cada combinação
3. **Salvar**
4. **Publicar Catálogo**

### Opção 2: Recriar Variações

1. **Abrir produto**
2. **Remover TODAS as linhas** (clicando em "−")
3. **Adicionar UMA linha** (botão "+")
4. **Preencher cada variação única:**
   - Tam 13, Rosa, 2
   - (Clique "+")
   - Tam 12, Azul, 3
   - (Clique "+")
   - Tam 14, Rosa, 2
5. **Salvar**

---

## 🎯 COMPORTAMENTO ESPERADO APÓS CORREÇÃO

### Ao Adicionar Nova Linha:
✅ Nova variação é criada
✅ Estoque total aumenta

### Ao Editar Linha Existente:
✅ Variação antiga é substituída
✅ Estoque total recalcula corretamente

### Ao Remover Linha (botão "−"):
✅ Variação é removida da lista
✅ Ao salvar, não aparece mais no Firestore
✅ Estoque total diminui

### Ao Mudar Tamanho ou Cor:
✅ Se a nova combinação já existe, sobrescreve a quantidade
✅ Se a nova combinação não existe, cria nova variação
✅ Estoque total reflete apenas variações únicas

---

## 🧪 TESTE PASSO A PASSO

1. **Criar Produto com Variações:**
   ```
   Tam 10  Azul   5
   Tam 10  Verde  3
   Tam 12  Azul   7
   Total: 15un
   ```

2. **Salvar e verificar:**
   - App: deve mostrar total 15un
   - Firestore: `quantidade: 15`

3. **Editar Linha 2:** Mudar "Tam 10 Verde 3" para "Tam 10 Azul 10"
   ```
   Tam 10  Azul   5
   Tam 10  Azul   10  ← Editado
   Tam 12  Azul   7
   ```

4. **Salvar:**
   - ✅ **ESPERADO:** Tam 10 Azul fica com 10un (sobrescreve o 5)
   - ✅ Total: 10 + 7 = 17un
   - ❌ **ANTES DA CORREÇÃO:** Total seria 5 + 10 + 7 = 22un

5. **Verificar Firestore:**
   ```json
   {
     "variacoes": {
       "10": {"Azul": 10},    // ✅ Apenas 10 (sobrescrito)
       "12": {"Azul": 7}
     },
     "quantidade": 17
   }
   ```

---

## 📝 RESUMO

| Ação | Antes da Correção | Depois da Correção |
|------|-------------------|-------------------|
| Adicionar nova linha | ✅ Funciona | ✅ Funciona |
| Editar tamanho/cor | ❌ Duplica variação | ✅ Substitui corretamente |
| Mesma combinação 2x | ❌ Soma quantidades | ✅ Última sobrescreve |
| Remover linha | ✅ Remove da grade | ✅ Remove do estoque |
| Estoque total | ❌ Soma incorreta | ✅ Soma correta |

---

**Data:** 2026-01-17
**Arquivo Modificado:** `lib/screens/produto_form_screen.dart` linha 329
**Status:** ✅ Correção aplicada | ⏳ Aguardando teste do usuário
