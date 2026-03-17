# 🚀 Teste Rápido da Roleta - Debug

## 1️⃣ PRIMEIRO: Deploy do Índice

Execute no terminal:

```bash
firebase deploy --only firestore:indexes
```

**Aguarde 2-5 minutos** para o índice ser criado.

---

## 2️⃣ SEGUNDO: Criar Campanha de Teste no Firestore

### Via Firebase Console:

1. Acesse: https://console.firebase.google.com
2. Selecione seu projeto
3. Vá em **Firestore Database**
4. Clique em **Iniciar coleção** ou navegue até uma loja existente
5. Caminho: `/lojas/{ID_DA_SUA_LOJA}/campanhas_sorteio`

### ID da Loja:
Para descobrir o ID da loja, procure no código ou nos logs do app quando abrir o catálogo.

### Criar o documento:

**Document ID:** `teste_natal_2024`

**Campos:**

| Campo | Tipo | Valor |
|-------|------|-------|
| `nome` | string | "Super Sorteio de Natal" |
| `descricao` | string | "Gire a roleta e ganhe prêmios!" |
| `ativa` | boolean | **true** |
| `valorMinimo` | number | **0** (zero para sempre mostrar) |
| `premios` | array | Ver abaixo ⬇️ |
| `dataInicio` | timestamp | **HOJE** (clique no ícone de relógio) |
| `dataFim` | timestamp | **Daqui 30 dias** |
| `createdAt` | timestamp | **AGORA** |

### Array de Prêmios:

Adicione cada string como item do array:

```
"10% de desconto"
"15% de desconto"
"R$ 20 de desconto"
"Frete grátis"
"5% de desconto"
"R$ 10 de desconto"
"20% de desconto"
"R$ 5 de desconto"
```

**⚠️ IMPORTANTE:**
- O campo `ativa` deve ser **boolean true** (não string)
- O campo `valorMinimo` deve ser **number 0** (não string)
- Os campos de data devem ser **Timestamp** (use o ícone de relógio)

---

## 3️⃣ TERCEIRO: Rodar o App com Logs

```bash
flutter run
```

### O que procurar nos logs:

Ao abrir o carrinho, você deve ver:

```
🔍 Verificando campanha ativa para loja: {ID}
📊 Campanhas encontradas: 1
✅ Campanha ativa encontrada: teste_natal_2024
   Nome: Super Sorteio de Natal
   Valor mínimo: 0
✅ _campanhaAtivaId setado: teste_natal_2024
🎰 Verificando exibição da roleta:
   _campanhaAtivaId: teste_natal_2024
   _roletaJaGirada: false
   Deve mostrar: true
```

### Se ver isso ❌:

```
📊 Campanhas encontradas: 0
⚠️ Nenhuma campanha ativa encontrada
```

**Possíveis causas:**
1. Índice não foi criado ainda (aguarde mais tempo)
2. Campanha não está no caminho correto
3. Campo `ativa` não é boolean true
4. Campo `dataFim` está no passado
5. ID da loja está errado

---

## 4️⃣ Como Descobrir o ID da Loja

Execute este código no terminal Flutter:

```bash
flutter run --verbose
```

Quando abrir o catálogo, procure nos logs por:
```
🔍 Verificando campanha ativa para loja: XXXXXXX
```

O `XXXXXXX` é o ID da loja.

**OU**

Adicione este código temporariamente no `initState`:

```dart
debugPrint('🏪 LOJA ID: ${widget.lojaId}');
```

---

## 5️⃣ Verificar se o Índice Foi Criado

### Via Firebase Console:

1. Firestore Database → **Indexes** → **Composite**
2. Procure por:
   - Collection: `campanhas_sorteio`
   - Fields: `ativa (Asc), dataFim (Asc)`
   - Status: **Enabled** ✅

### Via Terminal:

```bash
firebase firestore:indexes
```

---

## 6️⃣ Exemplo Completo de Documento

Aqui está um JSON exemplo (para referência):

```json
{
  "nome": "Super Sorteio de Natal",
  "descricao": "Gire a roleta e ganhe prêmios!",
  "ativa": true,
  "valorMinimo": 0,
  "premios": [
    "10% de desconto",
    "15% de desconto",
    "R$ 20 de desconto",
    "Frete grátis",
    "5% de desconto",
    "R$ 10 de desconto",
    "20% de desconto",
    "R$ 5 de desconto"
  ],
  "dataInicio": "2024-12-21T00:00:00.000Z",
  "dataFim": "2025-01-20T23:59:59.000Z",
  "createdAt": "2024-12-21T22:37:00.000Z"
}
```

**⚠️ ATENÇÃO:** No Firestore Console, use o tipo **Timestamp** para as datas, não string!

---

## 🐛 Troubleshooting

### Problema: Banner não aparece

**Solução:**
- Verifique se o índice está **Enabled**
- Aguarde 5 minutos após criar o índice
- Reinicie o app completamente

### Problema: Roleta não aparece mesmo com campanha

**Verificar:**
1. Logs mostram `_campanhaAtivaId: null`?
   - Campanha não foi encontrada
2. Logs mostram `_roletaJaGirada: true`?
   - Você já girou a roleta nesta sessão
   - Feche e abra o carrinho novamente

### Problema: Erro "failed-precondition"

**Causa:** Índice não foi criado ou ainda está sendo criado

**Solução:**
```bash
# Fazer deploy novamente
firebase deploy --only firestore:indexes

# Aguardar 5 minutos
```

---

## ✅ Checklist de Testes

Após seguir todos os passos:

- [ ] Índice criado e **Enabled** no Firebase Console
- [ ] Campanha criada com `ativa: true` e `dataFim` futura
- [ ] App rodando com `flutter run`
- [ ] Logs mostram "Campanha ativa encontrada"
- [ ] Logs mostram "_campanhaAtivaId setado"
- [ ] Logs mostram "Deve mostrar: true"
- [ ] **ROLETA APARECE NO CARRINHO** ✨

---

**Data:** 21/12/2024
**Versão:** Debug v1.0
