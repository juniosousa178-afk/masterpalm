# 🧪 COMO TESTAR A CORREÇÃO DE VARIAÇÕES

## ⚠️ IMPORTANTE: Teste Antes de Usar em Produção

A correção foi aplicada no código. Agora você precisa testar para garantir que funciona corretamente.

---

## 📋 TESTE 1: Verificar Produto Existente com Problema

### Passo 1: Identificar Produto com Duplicação

1. **Abra Firebase Console:**
   - https://console.firebase.google.com/project/masterpalm-58c46

2. **Vá em Firestore Database:**
   - `lojas` → `{sua-loja-id}` → `produtos` ou `estoque_produtos`

3. **Procure o produto "Anel" (ou outro com problema):**
   - Veja o campo `variacoes`
   - Exemplo esperado SE HOUVER DUPLICAÇÃO:
     ```json
     {
       "variacoes": {
         "13": {"Rosa": 2, "Azul": 5},
         "12": {"Azul": 3},
         "14": {"Rosa": 2}
       },
       "quantidade": 12
     }
     ```
   - Note: 2+5+3+2 = 12 (incorreto, deveria ser 7)

### Passo 2: Abrir Produto no App Desktop

1. **Execute o app:**
   ```bash
   flutter run -d windows
   ```

2. **Vá em "Produtos"**

3. **Abra o produto "Anel"**

4. **Veja a grade de variações:**
   - Quantas linhas aparecem?
   - Há linhas duplicadas?
   - Anote o que você vê

---

## 📋 TESTE 2: Editar Variação (Mudando Tamanho/Cor)

### Cenário:
Você tem um produto com estas variações:
- Tam 13 Rosa: 2un
- Tam 12 Azul: 3un
- Tam 13 Azul: 5un

### Ação: Editar a terceira linha

1. **Abra produto no app**
2. **Na terceira linha da grade, mude:**
   - Tamanho: 13 → **14**
   - Cor: Azul → **Rosa**
   - Quantidade: 5 → **2**
3. **Clique "Salvar"**
4. **Aguarde mensagem "Produto salvo"**

### Verificação 1: No App (após salvar)

1. **Feche e abra o produto novamente**
2. **Veja a grade de variações**

**✅ ESPERADO:**
```
Linha 1: Tam 13  Rosa  2
Linha 2: Tam 12  Azul  3
Linha 3: Tam 14  Rosa  2
Total: 7un
```

**❌ SE APARECER ISSO (problema não resolvido):**
```
Linha 1: Tam 13  Rosa  2
Linha 2: Tam 12  Azul  3
Linha 3: Tam 13  Azul  5  ← Linha antiga ainda está aqui
Linha 4: Tam 14  Rosa  2
Total: 12un
```

### Verificação 2: No Firestore

1. **Abra Firebase Console** → Firestore
2. **Vá no documento do produto**
3. **Veja campo `variacoes`**

**✅ ESPERADO:**
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

**❌ NÃO DEVE TER:**
```json
{
  "13": {"Rosa": 2, "Azul": 5}  ← "Azul" não deve estar aqui
}
```

### Verificação 3: No Catálogo Web

1. **Abra catálogo:** https://mastepalm.web.app
2. **Pressione Ctrl + F5** (limpar cache)
3. **Abra o produto**
4. **Clique "Adicionar ao Carrinho"**
5. **No modal de seleção:**
   - Selecione tamanho **13**
   - **✅ Deve mostrar apenas cor "Rosa"**
   - **❌ NÃO deve mostrar "Azul"**

6. **Selecione tamanho 14:**
   - **✅ Deve mostrar apenas cor "Rosa"**

7. **Selecione tamanho 12:**
   - **✅ Deve mostrar apenas cor "Azul"**

---

## 📋 TESTE 3: Adicionar Variação Duplicada

### Cenário:
Produto tem:
- Tam 10 Azul: 5un

### Ação: Adicionar linha com MESMA combinação

1. **Abra produto**
2. **Clique "+" (adicionar linha)**
3. **Na nova linha:**
   - Tamanho: **10**
   - Cor: **Azul**
   - Quantidade: **3**
4. **Clique "Salvar"**

### Verificação:

**✅ ESPERADO (com correção):**
```json
{
  "variacoes": {
    "10": {"Azul": 3}  // ← Sobrescreveu o 5 com o 3
  },
  "quantidade": 3
}
```

**❌ ANTES DA CORREÇÃO:**
```json
{
  "variacoes": {
    "10": {"Azul": 8}  // ← Somou 5 + 3 = 8
  },
  "quantidade": 8
}
```

---

## 📋 TESTE 4: Remover Variação

### Cenário:
Produto tem:
- Tam 10 Azul: 5un
- Tam 10 Verde: 3un
- Tam 12 Azul: 7un
- Total: 15un

### Ação: Remover linha 2 (Tam 10 Verde)

1. **Abra produto**
2. **Na linha 2, clique no botão "−" (remover)**
3. **Linha deve desaparecer da grade**
4. **Clique "Salvar"**

### Verificação:

**✅ ESPERADO:**
```json
{
  "variacoes": {
    "10": {"Azul": 5},
    "12": {"Azul": 7}
  },
  "quantidade": 12  // 5 + 7 = 12
}
```

**❌ NÃO DEVE TER:**
```json
{
  "variacoes": {
    "10": {"Verde": 3}  ← Isso foi removido, não deve estar aqui
  }
}
```

---

## 📋 TESTE 5: Produto com Muitas Variações Iguais

### Cenário Extremo (para garantir que a correção funciona):

1. **Criar produto novo**
2. **Adicionar 5 linhas COM A MESMA combinação:**
   ```
   Linha 1: Tam 10  Azul  5
   Linha 2: Tam 10  Azul  3
   Linha 3: Tam 10  Azul  8
   Linha 4: Tam 10  Azul  2
   Linha 5: Tam 10  Azul  10
   ```

3. **Salvar**

### Verificação:

**✅ ESPERADO (com correção):**
```json
{
  "variacoes": {
    "10": {"Azul": 10}  // ← Última linha sobrescreve (linha 5)
  },
  "quantidade": 10
}
```

**❌ ANTES DA CORREÇÃO:**
```json
{
  "variacoes": {
    "10": {"Azul": 28}  // ← Somou 5+3+8+2+10 = 28
  },
  "quantidade": 28
}
```

---

## 🐛 O QUE FAZER SE TESTE FALHAR

### Se ainda houver duplicação após salvar:

1. **Capture screenshots:**
   - Grade de variações no app
   - Documento no Firestore
   - Modal no catálogo web

2. **Me envie:**
   - Os screenshots
   - O produto exato que está com problema
   - O que você fez (passos)
   - O que esperava
   - O que aconteceu

3. **Temporariamente, limpe manualmente:**
   - Abra produto
   - Remova linhas duplicadas clicando em "−"
   - Deixe apenas uma linha de cada combinação única
   - Salve

---

## ✅ CHECKLIST DE TESTE

Execute estes testes e marque:

- [ ] **TESTE 1:** Verificar produto existente com problema
- [ ] **TESTE 2:** Editar variação (mudar tamanho/cor)
  - [ ] Verificação 1: No app após salvar
  - [ ] Verificação 2: No Firestore
  - [ ] Verificação 3: No catálogo web
- [ ] **TESTE 3:** Adicionar variação duplicada
- [ ] **TESTE 4:** Remover variação
- [ ] **TESTE 5:** Múltiplas linhas mesma combinação

---

## 📞 REPORTAR RESULTADO

Após fazer os testes, me informe:

**✅ Se funcionou:**
- "Testei e está funcionando! Variações não duplicam mais."

**❌ Se ainda tiver problema:**
- "Testei e ainda duplica. Veja os screenshots:"
- [Anexar screenshots]
- "Passos: 1... 2... 3..."

---

**Próximo passo:** EXECUTE OS TESTES acima e me retorne o resultado!
