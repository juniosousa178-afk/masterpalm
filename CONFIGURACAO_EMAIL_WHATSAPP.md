# Configuração de Email e WhatsApp - Cloud Functions

Este guia mostra como configurar o envio automático de emails e WhatsApp quando um pagamento é aprovado pelo gateway (Mercado Pago).

---

## 📧 Parte 1: Configurar Email (Gmail)

### Passo 1: Criar Senha de App no Gmail

1. **Acesse**: https://myaccount.google.com/

2. **Ative a verificação em 2 etapas** (obrigatório):
   - Clique em "Segurança" no menu lateral
   - Encontre "Verificação em duas etapas"
   - Clique em "Ativar" e siga os passos
   - Use seu celular para receber códigos

3. **Gere uma Senha de App**:
   - Ainda em "Segurança", procure por "Senhas de app"
   - Se não encontrar, use este link direto: https://myaccount.google.com/apppasswords
   - Em "Selecionar app": escolha "Outro (nome personalizado)"
   - Digite: `MasterPalm Functions`
   - Clique em "Gerar"
   - **COPIE A SENHA** que aparece (formato: `xxxx xxxx xxxx xxxx`)
   - **IMPORTANTE**: Guarde essa senha em local seguro, ela só aparece uma vez!

### Passo 2: Configurar no Firebase

Abra o terminal (CMD ou PowerShell) e execute:

```bash
# Navegar para a pasta functions
cd C:\Users\Pichau\apk_nathy\temp_naty\functions

# Fazer login no Firebase (se necessário)
firebase login

# Configurar o email
firebase functions:config:set email.user="seu-email@gmail.com"

# Configurar a senha (cole a senha de app SEM espaços)
firebase functions:config:set email.pass="suasenhasemespaços"
```

**Exemplo real**:
```bash
firebase functions:config:set email.user="masterpalm.vendas@gmail.com"
firebase functions:config:set email.pass="abcdefghijklmnop"
```

### Passo 3: Verificar Configuração

```bash
# Ver todas as configurações
firebase functions:config:get

# Deve aparecer algo como:
# {
#   "email": {
#     "user": "masterpalm.vendas@gmail.com",
#     "pass": "****************"
#   }
# }
```

---

## 📱 Parte 2: Configurar WhatsApp (Opcional)

### Opção A: Evolution API (Recomendado)

1. **Contratar serviço Evolution API**:
   - Site: https://evolution-api.com/
   - Ou instalar self-hosted: https://doc.evolution-api.com/

2. **Obter credenciais**:
   - URL da API (ex: `https://sua-api.evolution.com/message/sendText`)
   - API Key / Token

3. **Configurar no Firebase**:
```bash
firebase functions:config:set whatsapp.api_url="https://sua-api.evolution.com/message/sendText"
firebase functions:config:set whatsapp.api_key="seu-token-aqui"
```

### Opção B: Twilio

1. **Criar conta**: https://www.twilio.com/
2. **Obter credenciais** no Dashboard
3. **Configurar**:
```bash
firebase functions:config:set whatsapp.api_url="https://api.twilio.com/2010-04-01/Accounts/YOUR_ACCOUNT_SID/Messages.json"
firebase functions:config:set whatsapp.api_key="seu-auth-token"
```

### Opção C: Sem API (Padrão)

Se você **NÃO** configurar WhatsApp API:
- O sistema funcionará normalmente
- Emails serão enviados automaticamente
- WhatsApp **NÃO** será enviado automaticamente
- O log mostrará: `⚠️ WhatsApp API não configurada`

---

## 🚀 Parte 3: Deploy da Cloud Function

### Passo 1: Instalar Dependências

```bash
cd C:\Users\Pichau\apk_nathy\temp_naty\functions
npm install
```

### Passo 2: Fazer Deploy

```bash
# Deploy apenas da função de webhook
firebase deploy --only functions:mercadopagoWebhook

# Ou deploy de todas as functions
firebase deploy --only functions
```

### Passo 3: Obter URL do Webhook

Após o deploy, você receberá uma URL como:
```
https://southamerica-east1-seu-projeto.cloudfunctions.net/mercadopagoWebhook
```

**COPIE ESSA URL** - você precisará dela no próximo passo.

---

## 🔗 Parte 4: Configurar Webhook no Mercado Pago

### Passo 1: Acessar Dashboard do Mercado Pago

1. Entre em: https://www.mercadopago.com.br/
2. Vá em "Seu negócio" → "Configurações" → "Webhooks"
3. Ou acesse direto: https://www.mercadopago.com.br/developers/panel/webhooks

### Passo 2: Criar Webhook

1. Clique em "Criar webhook"
2. **URL de produção**: Cole a URL da Cloud Function que você copiou
3. **Eventos**: Selecione:
   - ✅ Pagamentos (Payments)
4. Clique em "Salvar"

### Passo 3: Testar Webhook

1. No painel do Mercado Pago, clique em "Simular"
2. Selecione evento "payment.created" ou "payment.updated"
3. Clique em "Enviar"
4. Status deve aparecer como: ✅ 200 OK

---

## 🧪 Parte 5: Testar o Sistema

### Teste Local (Emulador)

```bash
# Baixar configuração
firebase functions:config:get > .runtimeconfig.json

# Iniciar emulador
firebase emulators:start --only functions

# Testar com curl
curl -X POST http://localhost:5001/seu-projeto/southamerica-east1/mercadopagoWebhook \
  -H "Content-Type: application/json" \
  -d '{"type":"payment","action":"payment.created","data":{"id":"123456789"}}'
```

### Teste em Produção

1. **Criar uma venda teste** no app
2. **Fazer pagamento** com valor mínimo (R$ 0,01 se possível)
3. **Verificar logs**:
```bash
firebase functions:log --only mercadopagoWebhook
```

4. **Verificar email** do cliente
5. **Verificar Firestore**:
   - Collection: `lojas/{lojaId}/campanhas_sorteio/{campanhaId}/participantes`
   - Deve ter documento com números da sorte

---

## 📋 Checklist Final

Antes de considerar concluído, verifique:

### Email
- [ ] Senha de app criada no Gmail
- [ ] `email.user` configurado no Firebase
- [ ] `email.pass` configurado no Firebase
- [ ] Deploy da função realizado
- [ ] Email de teste recebido

### WhatsApp (Opcional)
- [ ] API contratada (Evolution, Twilio, etc.)
- [ ] `whatsapp.api_url` configurado
- [ ] `whatsapp.api_key` configurado
- [ ] WhatsApp de teste recebido

### Webhook
- [ ] URL da função copiada
- [ ] Webhook configurado no Mercado Pago
- [ ] Teste de webhook aprovado (200 OK)

### Campanha
- [ ] Campanha criada no app (tela "Campanhas & Sorteios")
- [ ] `ativa: true`
- [ ] `dataInicio` no passado
- [ ] `dataFim` no futuro
- [ ] `valorMinimo` definido

---

## ❓ Problemas Comuns

### Email não está sendo enviado

**Problema**: Email não chega
**Soluções**:
1. Verifique os logs: `firebase functions:log`
2. Confirme que a senha de app está correta (sem espaços)
3. Verifique se a verificação em 2 etapas está ativa
4. Teste com outro email de destino (talvez esteja no spam)

### WhatsApp não está sendo enviado

**Problema**: WhatsApp não é enviado
**Soluções**:
1. Verifique se a API está configurada: `firebase functions:config:get`
2. Se não configurou API, é esperado que não envie (use no app manual)
3. Verifique logs da API do WhatsApp

### Webhook retorna erro 500

**Problema**: Webhook falha ao processar
**Soluções**:
1. Verifique logs: `firebase functions:log`
2. Confirme que todas as configurações estão corretas
3. Verifique se a estrutura do pedido no Firestore está correta

### Números não são gerados

**Problema**: Compra aprovada mas não gera números
**Soluções**:
1. Verifique se existe campanha ativa
2. Confirme que `valorMinimo` da campanha foi atingido
3. Verifique se `dataInicio` e `dataFim` estão corretos
4. Veja logs para mensagens de erro

---

## 🔒 Segurança

### Boas Práticas

1. **Nunca commite** senhas no código
2. **Use sempre** Firebase Config para credenciais
3. **Proteja** suas credenciais do Mercado Pago
4. **Monitore** os logs regularmente
5. **Limite** permissões da conta de email (crie email específico)

### Email Dedicado

Recomendamos criar um email específico para o sistema:
- `masterpalm.notificacoes@gmail.com`
- `noreply@mastepalm.com.br` (se tiver domínio próprio)

---

## 📞 Suporte

Se precisar de ajuda:
1. Verifique os logs: `firebase functions:log`
2. Revise este guia passo a passo
3. Consulte a documentação oficial:
   - Firebase Functions: https://firebase.google.com/docs/functions
   - Nodemailer: https://nodemailer.com/
   - Mercado Pago: https://www.mercadopago.com.br/developers/

---

## ✅ Pronto!

Após seguir todos os passos, seu sistema estará funcionando:

1. Cliente faz compra no catálogo web
2. Paga com Mercado Pago
3. Mercado Pago aprova o pagamento
4. Webhook chama a Cloud Function
5. Sistema registra participação na campanha
6. Gera números da sorte únicos
7. Envia email automaticamente ✅
8. Envia WhatsApp automaticamente (se configurado) ✅
9. Cliente recebe os números e detalhes da campanha

**Boa sorte com os sorteios! 🍀**
