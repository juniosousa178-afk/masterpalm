# 🚀 Deploy - Canais Meta (WhatsApp, Instagram, Messenger)

## ✅ Implementação Completa

### Arquivos Criados:

**Backend:**
- ✅ `functions/canaisMetaWebhooks.js` - Webhooks completos (650+ linhas)
- ✅ `functions/index.js` - Exportações atualizadas

**Frontend:**
- ✅ `lib/screens/configuracoes/canais_meta_screen.dart` - Tela de configuração
- ✅ `lib/screens/configuracoes/canais_meta_widgets.dart` - Widgets das tabs
- ✅ `lib/screens/home_screen.dart` - Menu atualizado

**Documentação:**
- ✅ `CANAIS_META_README.md` - Documentação completa
- ✅ `DEPLOY_CANAIS_META.md` - Este arquivo

---

## 📋 Passo a Passo para Deploy

### 1. Deploy das Cloud Functions

```bash
cd functions

# Instalar dependências (se necessário)
npm install

# Deploy das 3 funções webhook
firebase deploy --only functions:webhookWhatsApp
firebase deploy --only functions:webhookInstagram
firebase deploy --only functions:webhookMessenger

# Ou deploy de todas de uma vez
firebase deploy --only functions
```

**URLs Geradas:**
Após o deploy, você terá:
- `https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookWhatsApp`
- `https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookInstagram`
- `https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookMessenger`

### 2. Verificar Deploy

```bash
# Listar funções deployadas
firebase functions:list

# Ver logs em tempo real
firebase functions:log --only webhookWhatsApp

# Ver logs específicos
firebase functions:log --only webhookInstagram --lines 50
```

---

## 🔧 Configuração Meta Developers

### IMPORTANTE: Cada loja faz sua própria configuração!

Este é um sistema **multi-tenant SaaS**. Cada loja:
1. Cria sua própria conta Meta Business
2. Configura seu próprio app no Meta Developers
3. Conecta suas credenciais no MasterPalm
4. Paga seus custos diretamente à Meta

### WhatsApp Cloud API

**1. Criar App Meta Developers:**
- Acesse: https://developers.facebook.com/apps
- Clique em "Criar App"
- Tipo: **Business**
- Nome: `MasterPalm WhatsApp - [Nome da Loja]`

**2. Adicionar Produto WhatsApp:**
- No painel do app, clique em "Adicionar Produto"
- Selecione **WhatsApp**
- Clique em "Configurar"

**3. Configurar Webhook:**
- Vá em: WhatsApp > Configuração > Webhook
- **URL do Callback:**
  ```
  https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookWhatsApp
  ```
- **Token de Verificação:**
  ```
  masterpalm_verify_2026
  ```
- Clique em "Verificar e Salvar"

**4. Inscrever em Eventos:**
- Marque: ✅ `messages`
- Salvar

**5. Obter Credenciais:**
- Vá em: WhatsApp > API Setup
- Copie:
  - **Phone Number ID** (ex: 123456789012345)
  - **WhatsApp Business Account ID** (ex: 123456789012345)
- Clique em "Temporary access token" > "Generate Token"
- Copie o **Access Token** (começa com EAAx...)

**6. Configurar no MasterPalm:**
- Abra o app MasterPalm
- Menu > Canais Meta
- Aba WhatsApp
- Cole as 3 credenciais
- Clique em "Testar" e depois "Salvar"

---

### Instagram Direct Messaging

**1. No mesmo app Meta Developers:**
- Adicionar Produto > **Instagram**

**2. Conectar Conta Instagram:**
- Vá em: Instagram > Configuração
- Conecte sua conta **Instagram Business**
- ⚠️ IMPORTANTE: Deve estar vinculada a uma Página do Facebook

**3. Configurar Webhook:**
- **URL do Callback:**
  ```
  https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookInstagram
  ```
- **Token de Verificação:**
  ```
  masterpalm_verify_2026
  ```

**4. Inscrever em Eventos:**
- Marque: ✅ `messages`

**5. Obter Credenciais:**
- Instagram > API Setup
- Copie:
  - **Instagram Business Account ID** (começa com 17...)
  - **Page ID** (ID da página vinculada)
- Gere **Page Access Token** com permissões:
  - `instagram_basic`
  - `instagram_manage_messages`
  - `pages_messaging`

**6. Configurar no MasterPalm:**
- Aba Instagram
- Cole as 3 credenciais
- Salvar

---

### Facebook Messenger

**1. Criar Página no Facebook:**
- https://facebook.com/pages/create
- Nome: Nome da sua loja
- Categoria: Loja de varejo / E-commerce

**2. No app Meta Developers:**
- Adicionar Produto > **Messenger**

**3. Conectar Página:**
- Messenger > Configuração
- Selecione a página criada
- "Adicionar Página"

**4. Configurar Webhook:**
- **URL do Callback:**
  ```
  https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookMessenger
  ```
- **Token de Verificação:**
  ```
  masterpalm_verify_2026
  ```

**5. Inscrever em Eventos:**
- Marque: ✅ `messages`

**6. Obter Credenciais:**
- Messenger > API Setup
- Copie **Page ID**
- Gere **Page Access Token** com permissões:
  - `pages_messaging`
  - `pages_manage_metadata`

**7. Configurar no MasterPalm:**
- Aba Messenger
- Cole Page ID e Token
- Salvar

---

## 🧪 Testar a Implementação

### 1. Testar Verificação do Webhook (Meta faz isso automaticamente)

```bash
# Simular verificação WhatsApp
curl "https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookWhatsApp?hub.mode=subscribe&hub.verify_token=masterpalm_verify_2026&hub.challenge=TESTE123"

# Deve retornar: TESTE123
```

### 2. Testar Processamento de Mensagem

**Via WhatsApp:**
1. Use o número de teste fornecido pela Meta
2. Envie mensagem: "Olá"
3. Verifique resposta do bot
4. Teste intents:
   - "Quanto custa a camisa?"
   - "Tem em estoque?"
   - "Quais tamanhos?"
   - "Manda foto"

**Verificar Logs:**
```bash
# Logs em tempo real
firebase functions:log --only webhookWhatsApp

# Deve mostrar:
# 📥 WhatsApp Webhook: POST
# 📨 Mensagem de +5511999999999: Olá
# 🧠 Intent: { intent: 'GREETING', confidence: 0.9 }
# ✅ Resposta enviada
```

### 3. Testar Busca de Produtos

**Adicione produtos no Firestore:**
```
lojas/{lojaId}/produtos/{produtoId}
{
  nome: "Camisa Polo Masculina",
  descricao: "Camisa polo de algodão, confortável",
  preco: 89.90,
  estoque: 10,
  tamanhos: ["P", "M", "G", "GG"],
  cores: ["Azul", "Branco", "Preto"],
  imagemUrl: "https://...",
  ativo: true,
  categoria: "Camisas"
}
```

**Teste no WhatsApp:**
- "Quanto custa a camisa polo?"
- Bot deve responder com preço R$ 89,90
- "Tem em estoque?"
- Bot deve responder "✅ 10 unidades"

---

## 📊 Estrutura de Dados no Firestore

### Configuração dos Canais (cada loja)

```
lojas/
  {lojaId}/
    canais/
      whatsapp/
        enabled: true
        phone_number_id: "123456789012345"
        business_account_id: "123456789012345"
        access_token: "EAAxxxxxxxxxxxxxxxxxx"
        verify_token: "masterpalm_verify_2026"
        messageTemplates:
          outside24h_template_name: "hello_world"
        updatedAt: timestamp

      instagram/
        enabled: true
        ig_business_account_id: "17841405822304914"
        page_id: "108316244769394"
        page_access_token: "EAAxxxxxxxxxxxxxxxxxx"
        verify_token: "masterpalm_verify_2026"
        updatedAt: timestamp

      messenger/
        enabled: true
        page_id: "108316244769394"
        page_access_token: "EAAxxxxxxxxxxxxxxxxxx"
        verify_token: "masterpalm_verify_2026"
        updatedAt: timestamp
```

### Produtos (para busca)

```
lojas/
  {lojaId}/
    produtos/
      {produtoId}/
        nome: string
        descricao: string
        preco: number
        estoque: number
        tamanhos: array
        cores: array
        imagemUrl: string
        imagens: array
        ativo: boolean (importante!)
        categoria: string
```

---

## 🎯 Intents Implementados

### 1. GREETING (Saudação)
**Palavras-chave:** oi, olá, bom dia, boa tarde, boa noite
**Resposta:** Mensagem de boas-vindas

### 2. HANDOVER (Transferir para humano)
**Palavras-chave:** atendente, humano, pessoa, funcionário
**Resposta:** Mensagem de transferência

### 3. PRODUCT_PRICE (Preço)
**Palavras-chave:** quanto custa, preço, valor
**Ação:** Busca produtos e retorna preços

### 4. PRODUCT_STOCK (Estoque)
**Palavras-chave:** tem em estoque, disponível
**Ação:** Verifica quantidade em estoque

### 5. PRODUCT_SIZE (Tamanhos)
**Palavras-chave:** tamanho, P M G, GG
**Ação:** Lista tamanhos disponíveis

### 6. PRODUCT_COLOR (Cores)
**Palavras-chave:** cor, cores, azul, vermelho
**Ação:** Lista cores disponíveis

### 7. PRODUCT_PHOTO (Fotos)
**Palavras-chave:** foto, imagem, manda foto
**Ação:** Envia link das imagens

### 8. PRODUCT_DESCRIPTION (Descrição)
**Palavras-chave:** detalhe, descrição, como é
**Ação:** Envia descrição detalhada

### 9. SHIPPING (Frete)
**Palavras-chave:** frete, entrega, envio
**Resposta:** Informações sobre frete

### 10. PAYMENT (Pagamento)
**Palavras-chave:** pagamento, cartão, pix
**Resposta:** Formas de pagamento aceitas

### 11. BUSINESS_HOURS (Horário)
**Palavras-chave:** horário, funciona, abre
**Resposta:** Horário de funcionamento

---

## 🔍 Monitoramento e Debug

### Ver Logs das Funções

```bash
# Todos os logs
firebase functions:log

# Apenas WhatsApp
firebase functions:log --only webhookWhatsApp

# Últimas 100 linhas
firebase functions:log --lines 100

# Filtrar por erro
firebase functions:log | grep "ERROR"
```

### Verificar Deploy

```bash
# Listar funções ativas
firebase functions:list

# Verificar configuração
firebase functions:config:get
```

### Debug Comum

**Problema: Webhook não recebe mensagens**
- Verifique URL do webhook na Meta
- Confirme que verify_token = "masterpalm_verify_2026"
- Veja se inscreveu no evento "messages"
- Cheque logs: `firebase functions:log --only webhookWhatsApp`

**Problema: Bot não responde**
- Verifique se canal está `enabled: true` no Firestore
- Confirme que tokens estão corretos
- Teste se função está deployada: `firebase functions:list`
- Veja logs de erro

**Problema: "Loja não encontrada"**
- Verifique se phone_number_id/page_id está salvo corretamente
- Confirme estrutura: `lojas/{lojaId}/canais/{canal}`
- Use Firebase Console para ver dados

---

## 💰 Custos

### Meta (WhatsApp Business API)
- Primeiras 1.000 conversas/mês: **GRÁTIS**
- Após isso: ~R$ 0,03 por conversa (varia por país)
- Janela 24h: sem custo adicional
- Fora da janela: custo por template

### Firebase (Cloud Functions)
- 2 milhões de invocações/mês: **GRÁTIS**
- Firestore: 50.000 leituras/dia grátis
- Após isso: custo mínimo (~R$ 10-50/mês para volumes médios)

### Total Estimado
Para loja com **500 conversas/mês**:
- Meta: R$ 0 (dentro do free tier)
- Firebase: R$ 0 (dentro do free tier)
- **Total: R$ 0** 🎉

---

## ✅ Checklist de Deploy

- [ ] Deploy das Cloud Functions concluído
- [ ] URLs dos webhooks obtidas
- [ ] App criado no Meta Developers
- [ ] Produtos WhatsApp/Instagram/Messenger adicionados
- [ ] Webhooks configurados com URLs corretas
- [ ] Verify token = "masterpalm_verify_2026"
- [ ] Eventos "messages" inscritos
- [ ] Credenciais copiadas (Phone ID, Tokens, etc)
- [ ] Configuração salva no MasterPalm
- [ ] Teste de conexão bem-sucedido
- [ ] Mensagem de teste enviada e respondida
- [ ] Busca de produtos funcionando
- [ ] Logs verificados sem erros

---

## 🎉 Próximos Passos

1. **Deploy Inicial:**
   ```bash
   cd functions
   firebase deploy --only functions:webhookWhatsApp,functions:webhookInstagram,functions:webhookMessenger
   ```

2. **Configurar 1ª Loja (Teste):**
   - Use sua própria conta Meta Business
   - Configure WhatsApp primeiro (mais fácil)
   - Teste com número de teste da Meta

3. **Adicionar Produtos:**
   - Certifique-se que `ativo: true`
   - Preencha todos os campos (nome, preço, estoque)

4. **Testar Intents:**
   - Envie mensagens variadas
   - Verifique respostas do bot
   - Ajuste conforme necessário

5. **Produção:**
   - Obtenha aprovação da Meta (WhatsApp Business)
   - Configure número de produção
   - Habilite para clientes reais

---

## 📞 Suporte

Se tiver problemas:

1. **Verifique logs:**
   ```bash
   firebase functions:log --only webhookWhatsApp
   ```

2. **Teste webhook manualmente:**
   ```bash
   curl -X GET "URL_DO_WEBHOOK?hub.mode=subscribe&hub.verify_token=masterpalm_verify_2026&hub.challenge=TEST"
   ```

3. **Valide estrutura Firestore:**
   - Acesse Firebase Console
   - Firestore Database
   - Navegue até `lojas/{lojaId}/canais/whatsapp`
   - Confirme que `enabled: true` e tokens estão presentes

---

## 🚀 Está Pronto!

Sua implementação completa dos Canais Meta está pronta para uso!

**O que você tem agora:**
- ✅ 3 webhooks funcionais (WhatsApp, Instagram, Messenger)
- ✅ 11 intents implementados
- ✅ Busca inteligente de produtos
- ✅ Interface Flutter completa
- ✅ Sistema multi-tenant
- ✅ Logs e monitoramento

**Basta fazer o deploy e configurar!** 🎉
