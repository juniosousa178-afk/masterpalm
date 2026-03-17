# 🔍 DEBUG - Entendendo Onde Está Duplicando

## ⚠️ TESTE COM LOGS DE DEBUG

Adicionei logs de debug para entender exatamente onde está duplicando.

---

## 📋 PASSO A PASSO PARA DEBUG

### 1. Execute o App Desktop

```bash
cd "C:\Users\Pichau\apk_nathy\temp_naty"
flutter run -d windows
```

**IMPORTANTE:** Deixe o terminal aberto para ver os logs!

---

### 2. Abra um Produto com Variações

1. **Vá em "Produtos"**
2. **Abra o produto "Anel" (ou outro com variações)**
3. **OLHE NO TERMINAL - você verá algo assim:**

```
🔍 [DEBUG CARREGAR] Carregando variações do Firestore:
  p.variacoes = {13: {Rosa: 2, Azul: 5}, 12: {Azul: 3}}
  ➜ Adicionando linha: 13 + Rosa = 2
  ➜ Adicionando linha: 13 + Azul = 5
  ➜ Adicionando linha: 12 + Azul = 3
  Total de linhas carregadas: 3
```

**➡️ COPIE E ME ENVIE ESSA PARTE DO LOG**

---

### 3. Veja a Grade de Variações no App

Na tela do produto, olhe a grade (tabela) de variações.

**Quantas linhas você vê?**

Exemplo:
```
Linha 1: Tam 13  Rosa  2
Linha 2: Tam 13  Azul  5
Linha 3: Tam 12  Azul  3
```

**➡️ ME DIGA: Quantas linhas aparecem?**

---

### 4. Edite UMA Linha

Vamos mudar a linha 2:
- **ANTES:** Tam 13, Azul, 5
- **DEPOIS:** Tam 14, Rosa, 2

**Passos:**
1. **Na linha 2 (13, Azul, 5):**
   - Mude tamanho: 13 → **14**
   - Mude cor: Azul → **Rosa**
   - Mude quantidade: 5 → **2**

2. **NÃO CLIQUE EM SALVAR AINDA!**

3. **Conte as linhas na grade:**
   - Quantas linhas você vê AGORA?
   - Linha 2 mudou para (14, Rosa, 2)?

**➡️ ME DIGA: Ainda são 3 linhas?**

---

### 5. Clique em "Salvar"

1. **Clique no botão "Salvar"**
2. **OLHE NO TERMINAL - você verá:**

```
🔍 [DEBUG SALVAR] Processando 3 linhas da grade:
  Linha 0: tamanho="13" cor="Rosa" qtd="2"
  Linha 1: tamanho="14" cor="Rosa" qtd="2"
  Linha 2: tamanho="12" cor="Azul" qtd="3"
  ➜ Processando: 13 + Rosa = 2
  ➜ Processando: 14 + Rosa = 2
  ⚠️  ATENÇÃO: Combinação 14+Rosa JÁ EXISTE com 2un
  ⚠️  Sobrescrevendo com 2 un (NÃO somando)
  ➜ Processando: 12 + Azul = 3

📊 [DEBUG SALVAR] Resultado final:
  variacoesMap: {13: {Rosa: 2}, 14: {Rosa: 2}, 12: {Azul: 3}}
  Total de variações: 7 un
```

**➡️ COPIE E ME ENVIE TODO ESSE LOG**

---

### 6. Abra o Produto Novamente

1. **Feche a tela do produto** (volte para lista)
2. **Abra o mesmo produto novamente**
3. **OLHE NO TERMINAL:**

```
🔍 [DEBUG CARREGAR] Carregando variações do Firestore:
  p.variacoes = {13: {Rosa: 2}, 14: {Rosa: 2}, 12: {Azul: 3}}
  ➜ Adicionando linha: 13 + Rosa = 2
  ➜ Adicionando linha: 14 + Rosa = 2
  ➜ Adicionando linha: 12 + Azul = 3
  Total de linhas carregadas: 3
```

**➡️ COPIE E ME ENVIE ESSE LOG**

4. **Veja a grade no app:**
   - Quantas linhas?
   - Quais combinações tamanho+cor aparecem?

**➡️ ME DIGA: Ainda vê "13 Azul 5"?**

---

### 7. Verifique no Firestore

1. **Abra Firebase Console:**
   https://console.firebase.google.com/project/masterpalm-58c46

2. **Vá em Firestore Database**

3. **Navegue:**
   - `lojas` → `{sua-loja-id}` → `estoque_produtos` → `{produto-id}`

4. **Veja o campo `variacoes`**

**➡️ ME ENVIE UM SCREENSHOT DO CAMPO `variacoes`**

OU copie e cole o conteúdo:
```json
{
  "variacoes": { ... }
}
```

---

## 📊 O QUE EU PRECISO SABER

### Me envie TODAS estas informações:

1. **Log ao CARREGAR o produto** (passo 2)
2. **Número de linhas na grade** (passo 3)
3. **Log ao SALVAR** (passo 5)
4. **Log ao CARREGAR novamente** (passo 6)
5. **Screenshot do Firestore** (passo 7)

---

## 🎯 O QUE ESTOU INVESTIGANDO

Com esses logs, vou descobrir:

1. **As variações estão corretas no Firestore?**
   - Se sim: problema está no carregamento
   - Se não: problema está no salvamento

2. **A duplicação acontece:**
   - Ao carregar? (linhas aparecem em dobro na grade)
   - Ao salvar? (variacoesMap tem duplicatas)
   - No Firestore? (documento tem dados duplicados)

3. **Possíveis causas:**
   - Firestore tem dados antigos não removidos
   - Código está carregando de dois lugares
   - Sincronização está duplicando
   - Grade está adicionando linhas extras

---

## ⚡ TESTE RÁPIDO ALTERNATIVO

Se preferir um teste mais rápido:

1. **Abra o terminal**
2. **Execute:**
   ```bash
   flutter run -d windows
   ```
3. **Abra qualquer produto com variações**
4. **COPIE TODO O CONTEÚDO DO TERMINAL**
5. **ME ENVIE**

Vou analisar os logs e identificar o problema!

---

**AGUARDANDO:** Seus logs de debug para continuar investigação.
