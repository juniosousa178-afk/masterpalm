# ⚡ Quick Start - Canais Meta

## 🚀 Deploy em 5 Minutos

### 1️⃣ Testar Localmente

```bash
cd functions
node test-webhooks.js
```

Deve mostrar classificação de 13 mensagens de teste.

---

### 2️⃣ Deploy das Functions

```bash
cd functions

# Deploy das 3 funções
firebase deploy --only functions:webhookWhatsApp,functions:webhookInstagram,functions:webhookMessenger

# Aguarde 1-2 minutos...
# ✅ Function URL (webhookWhatsApp): https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookWhatsApp
```

**Copie as 3 URLs geradas!**

---

### 3️⃣ Configurar Meta Developers (WhatsApp)

1. **Criar App:** https://developers.facebook.com/apps
   - Tipo: Business
   - Nome: MasterPalm WhatsApp

2. **Adicionar WhatsApp**
   - Produtos > Adicionar Produto > WhatsApp

3. **Configurar Webhook:**
   - URL: `https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookWhatsApp`
   - Token: `masterpalm_verify_2026`
   - Eventos: ✅ messages

4. **Copiar Credenciais:**
   - Phone Number ID
   - Business Account ID
   - Access Token (gerar temporário)

---

### 4️⃣ Configurar no MasterPalm

1. Abra o app Flutter
2. Menu > **Canais Meta**
3. Aba **WhatsApp**
4. Cole as 3 credenciais
5. Clique **Testar** → deve dar ✅
6. Clique **Salvar**

---

### 5️⃣ Testar o Bot

1. Use o número de teste da Meta
2. Envie mensagem: **"Olá"**
3. Bot responde: **"👋 Olá! Bem-vindo!..."**
4. Teste: **"Quanto custa a camisa?"**
5. Adicione produtos no Firestore para ele buscar!

---

## 📦 Adicionar Produtos para Teste

Firebase Console > Firestore:

```
lojas/
  {suaLojaId}/
    produtos/
      produto1/
        nome: "Camisa Polo Masculina"
        descricao: "Camisa polo de algodão"
        preco: 89.90
        estoque: 10
        tamanhos: ["P", "M", "G"]
        cores: ["Azul", "Branco"]
        ativo: true  ← IMPORTANTE!
        categoria: "Camisas"
```

Agora teste: **"Quanto custa a camisa polo?"**

---

## 🔍 Ver Logs

```bash
# Logs em tempo real
firebase functions:log --only webhookWhatsApp

# Últimas 50 linhas
firebase functions:log --lines 50

# Apenas erros
firebase functions:log | grep "ERROR"
```

---

## ✅ URLs dos Webhooks

Após deploy, use estas URLs na Meta:

**WhatsApp:**
```
https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookWhatsApp
```

**Instagram:**
```
https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookInstagram
```

**Messenger:**
```
https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookMessenger
```

**Verify Token (todos os 3):**
```
masterpalm_verify_2026
```

---

## 🎯 Intents Disponíveis

Digite no WhatsApp:

1. **"Olá"** → Saudação
2. **"Quanto custa X?"** → Busca preço
3. **"Tem em estoque?"** → Verifica estoque
4. **"Quais tamanhos?"** → Lista tamanhos
5. **"Quais cores?"** → Lista cores
6. **"Manda foto"** → Envia imagens
7. **"Como é esse produto?"** → Descrição
8. **"Quanto fica o frete?"** → Info frete
9. **"Aceita cartão?"** → Pagamentos
10. **"Horário de funcionamento?"** → Horários
11. **"Quero falar com atendente"** → Handover

---

## 🐛 Troubleshooting Rápido

**Webhook não verifica:**
- Confira URL copiada corretamente
- Verify token = `masterpalm_verify_2026`
- Veja logs: `firebase functions:log`

**Bot não responde:**
- Canal habilitado no app? (toggle ON)
- Tokens corretos salvos?
- Veja estrutura Firestore: `lojas/{id}/canais/whatsapp`

**"Loja não encontrada":**
- Verifique phone_number_id salvo
- Use exatamente o ID da Meta

---

## 📚 Documentação Completa

- `CANAIS_META_README.md` - Visão geral
- `DEPLOY_CANAIS_META.md` - Deploy completo
- `QUICK_START_CANAIS.md` - Este arquivo

---

## 🎉 Pronto!

Você agora tem:
- ✅ Bot WhatsApp funcionando
- ✅ 11 intents implementados
- ✅ Busca de produtos
- ✅ Interface Flutter completa
- ✅ Multi-tenant SaaS

**Próximo:** Configure Instagram e Messenger seguindo mesmo processo!
