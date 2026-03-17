# 📱 Canais Meta - Integração Completa

## ✅ Implementação Finalizada

### Backend (Cloud Functions - TypeScript)

Localização: `functions/src/`

**Arquivos Principais:**
- `index.ts` - Exporta 3 webhooks: `webhookWhatsApp`, `webhookInstagram`, `webhookMessenger`
- `config.ts` - Configuração global (rate limits, timeouts, versões API)
- `types/` - Interfaces TypeScript para todos os domínios
- `utils/` - Utilitários (logger, normalização, regex, segurança, rate limit, retry, validação)
- `repositories/` - Acesso ao Firestore (lojas, produtos, conversas, idempotência, configuração)
- `services/` - Lógica de negócio (classificação de intents, busca de produtos, composição de respostas, horário comercial, handover, regras WhatsApp, analytics)
- `adapters/` - Adaptadores para APIs da Meta (WhatsApp, Instagram, Messenger)
- `routes/` - Handlers de webhook e verificação

**Funcionalidades Implementadas:**
- ✅ Resposta automática a 10 tipos de intents:
  - Preço de produto
  - Estoque/disponibilidade
  - Tamanhos disponíveis
  - Cores disponíveis
  - Fotos/imagens
  - Descrição detalhada
  - Frete/entrega
  - Formas de pagamento
  - Horário de funcionamento
  - Saudação/boas-vindas

- ✅ Handover para atendente humano
- ✅ Respeito a horário de funcionamento e férias
- ✅ Rate limiting (proteção contra spam)
- ✅ Idempotência (evita processamento duplicado)
- ✅ Regras do WhatsApp (janela 24h, templates)
- ✅ Busca inteligente de produtos
- ✅ Analytics e rastreamento
- ✅ Multi-tenant (cada loja com suas credenciais)

### Frontend (Flutter)

**Arquivos Criados:**
- `lib/screens/configuracoes/canais_meta_screen.dart` - Tela principal com 3 abas
- `lib/screens/configuracoes/canais_meta_widgets.dart` - Widgets das tabs (part file)

**Funcionalidades da UI:**
- ✅ 3 tabs (WhatsApp, Instagram, Messenger)
- ✅ Toggle on/off para cada canal
- ✅ Campos de configuração com validação:
  - **WhatsApp**: Phone Number ID, Business Account ID, Access Token, Template Name
  - **Instagram**: Business Account ID, Page ID, Page Access Token
  - **Messenger**: Page ID, Page Access Token
- ✅ Botão "Testar Conexão" (apenas WhatsApp)
- ✅ Botão "Salvar Configurações"
- ✅ Display de Webhook URL e Verify Token para configuração na Meta
- ✅ Botões de ajuda com tutoriais passo-a-passo
- ✅ Status de sucesso/erro em tempo real
- ✅ Integração com LojaIdService (multi-tenant)
- ✅ Persistência no Firestore em `lojas/{lojaId}/canais/{canal}`

**Integração com Home:**
- ✅ Menu lateral atualizado em `lib/screens/home_screen.dart`
- ✅ Rota `/configuracoes/canais_meta` configurada
- ✅ Ícone `Icons.chat_bubble`

## 🔧 Configuração

### 1. Backend (Cloud Functions)

```bash
cd functions
npm install
npm run build
firebase deploy --only functions
```

**Funções Deployadas:**
- `webhookWhatsApp` - https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookWhatsApp
- `webhookInstagram` - https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookInstagram
- `webhookMessenger` - https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookMessenger

### 2. Firestore

**Estrutura de Dados:**
```
lojas/
  {lojaId}/
    canais/
      whatsapp/
        - enabled: boolean
        - phone_number_id: string
        - business_account_id: string
        - access_token: string
        - verify_token: string (fixo: "masterpalm_verify_2026")
        - messageTemplates:
            - outside24h_template_name: string
        - updatedAt: timestamp

      instagram/
        - enabled: boolean
        - ig_business_account_id: string
        - page_id: string
        - page_access_token: string
        - verify_token: string
        - updatedAt: timestamp

      messenger/
        - enabled: boolean
        - page_id: string
        - page_access_token: string
        - verify_token: string
        - updatedAt: timestamp
```

### 3. Meta Developers (Para Cada Loja)

#### WhatsApp Cloud API
1. Acesse https://developers.facebook.com/apps
2. Crie um app Business
3. Adicione o produto "WhatsApp"
4. Configure Webhook:
   - URL: `https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookWhatsApp`
   - Verify Token: `masterpalm_verify_2026`
5. Inscreva em eventos: `messages`
6. Copie:
   - Phone Number ID (WhatsApp > API Setup)
   - Business Account ID (WhatsApp > API Setup)
   - Access Token (WhatsApp > API Setup > Generate Token)
7. Cole na tela de configuração do MasterPalm

#### Instagram Direct Messaging
1. No mesmo app, adicione "Instagram"
2. Conecte sua conta Instagram Business (vinculada a uma Página)
3. Configure Webhook:
   - URL: `https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookInstagram`
   - Verify Token: `masterpalm_verify_2026`
4. Inscreva em eventos: `messages`
5. Copie:
   - Instagram Business Account ID
   - Page ID
   - Page Access Token
6. Cole na tela de configuração do MasterPalm

#### Facebook Messenger
1. Crie uma Página no Facebook (facebook.com/pages/create)
2. No app Meta Developers, adicione "Messenger"
3. Conecte à página criada
4. Configure Webhook:
   - URL: `https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookMessenger`
   - Verify Token: `masterpalm_verify_2026`
5. Inscreva em eventos: `messages`
6. Gere Page Access Token (permissões: pages_messaging, pages_manage_metadata)
7. Copie:
   - Page ID
   - Page Access Token
8. Cole na tela de configuração do MasterPalm

## 🚀 Uso

1. **Acesse a tela de configuração:**
   - Menu lateral > "Canais Meta"

2. **Configure cada canal:**
   - Ative o toggle
   - Preencha as credenciais obtidas na Meta
   - Clique em "Salvar"

3. **Teste a conexão:**
   - No WhatsApp, clique em "Testar"
   - Verifique se a conexão foi bem-sucedida

4. **Use no dia-a-dia:**
   - Clientes enviam mensagens via WhatsApp/Instagram/Messenger
   - Bot responde automaticamente
   - Consultas de preço, estoque, fotos, etc.
   - Handover para humano quando necessário
   - Respeita horário de funcionamento

## 💰 Modelo SaaS

- Cada loja conecta seus próprios tokens da Meta
- Cada loja paga os custos diretamente à Meta
- MasterPalm fornece apenas a plataforma de automação
- Sem custos adicionais de intermediação

## 📊 Intents Suportados

1. **PRODUCT_PRICE** - "Quanto custa?" "Qual o preço?"
2. **PRODUCT_STOCK** - "Tem em estoque?" "Está disponível?"
3. **PRODUCT_SIZE** - "Quais tamanhos?" "Tem P/M/G?"
4. **PRODUCT_COLOR** - "Quais cores?" "Tem na cor azul?"
5. **PRODUCT_PHOTO** - "Manda foto" "Quero ver imagem"
6. **PRODUCT_DESCRIPTION** - "Detalhe o produto" "Como é?"
7. **SHIPPING** - "Quanto fica o frete?" "Entrega aqui?"
8. **PAYMENT** - "Formas de pagamento" "Aceita cartão?"
9. **BUSINESS_HOURS** - "Horário de funcionamento" "Está aberto?"
10. **GREETING** - "Olá" "Oi" "Bom dia"

## 🔐 Segurança

- ✅ Validação de assinatura dos webhooks
- ✅ Rate limiting (máx 10 mensagens/minuto por usuário)
- ✅ Idempotência (evita duplicação)
- ✅ Sanitização de entrada
- ✅ Tokens armazenados criptografados no Firestore
- ✅ Acesso multi-tenant isolado

## 📝 Logs e Monitoramento

- Logs estruturados no Firebase Functions
- Níveis: DEBUG, INFO, WARN, ERROR
- Analytics de intents e produtos mais buscados
- Rastreamento de handover para humano

## 🐛 Troubleshooting

**Webhook não recebe mensagens:**
- Verifique se a URL do webhook está correta
- Confirme que o Verify Token é `masterpalm_verify_2026`
- Certifique-se de que está inscrito nos eventos `messages`

**Bot não responde:**
- Verifique se o canal está habilitado (toggle on)
- Confirme que os tokens estão corretos
- Veja os logs no Firebase Console

**Erro "Invalid token":**
- Regenere o Access Token na Meta Developers
- Atualize na tela de configuração do MasterPalm

## 📚 Documentação Completa

- Backend: `functions/README.md`
- Tipos: `functions/src/types/`
- Serviços: `functions/src/services/`
- Adaptadores: `functions/src/adapters/`

## ✨ Próximos Passos (Opcional)

- [ ] Adicionar suporte a mensagens multimídia (áudio, vídeo, documentos)
- [ ] Implementar templates de mensagem personalizados
- [ ] Criar dashboard de analytics
- [ ] Adicionar suporte a chatbots com IA generativa
- [ ] Integrar com CRM externo
