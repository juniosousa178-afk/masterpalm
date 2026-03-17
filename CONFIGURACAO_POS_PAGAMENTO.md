# 🎯 Configuração do Fluxo de Pós-Pagamento

## 📋 Visão Geral

Este documento explica como configurar o fluxo completo de pós-pagamento que inclui:

✅ **Automação Pós-Pagamento:**
- Atualização automática do status da venda para "pago"
- Baixa automática de estoque dos produtos vendidos
- Geração de número da sorte para promoções
- Envio de Email com número da sorte e cupom da roleta (se houver)
- Envio de WhatsApp com as mesmas informações

✅ **Integração com Gateway:**
- Webhook do Mercado Pago para receber confirmações de pagamento
- Suporte para PIX e Cartão
- Dados do cupom da roleta integrados nas notificações

---

## 🔧 1. Configuração das Cloud Functions

### 1.1. Adicionar Dependências

Edite o arquivo `functions/package.json` e adicione as dependências:

```json
{
  "dependencies": {
    "firebase-functions": "^5.0.0",
    "firebase-admin": "^12.0.0",
    "nodemailer": "^6.9.0",
    "axios": "^1.6.0"
  }
}
```

### 1.2. Instalar Dependências

```bash
cd functions
npm install
```

### 1.3. Registrar Função no index.js

Edite `functions/index.js` e adicione no final do arquivo:

```javascript
// Pós-pagamento (Webhook e Notificações)
import { mercadopagoWebhook } from "./src/posPagamento.js";
export { mercadopagoWebhook };
```

### 1.4. Deploy das Functions

```bash
firebase deploy --only functions:mercadopagoWebhook
```

Anote a URL gerada, algo como:
```
https://southamerica-east1-SEU_PROJETO.cloudfunctions.net/mercadopagoWebhook
```

---

## 🌐 2. Configuração do Webhook no Mercado Pago

### 2.1. Acessar o Painel do Mercado Pago

1. Acesse: https://www.mercadopago.com.br/developers/panel
2. Selecione sua aplicação
3. Vá em **Webhooks** ou **Notificações**

### 2.2. Cadastrar Webhook

**URL do Webhook:**
```
https://southamerica-east1-SEU_PROJETO.cloudfunctions.net/mercadopagoWebhook
```

**Eventos para Assinar:**
- ✅ `payment` (Pagamentos)

**Modo:**
- Produção (use suas credenciais de produção)

### 2.3. Testar Webhook

O Mercado Pago tem uma ferramenta de teste no painel. Use-a para enviar um evento de teste e verificar se o webhook está respondendo corretamente.

---

## 📧 3. Configuração do Envio de Email

### 3.1. Gmail com App Password (Recomendado para Testes)

**Passos:**

1. **Habilitar Verificação em 2 Etapas:**
   - Acesse: https://myaccount.google.com/security
   - Ative a verificação em 2 etapas

2. **Gerar App Password:**
   - Acesse: https://myaccount.google.com/apppasswords
   - Selecione "App: Mail" e "Device: Other"
   - Copie a senha gerada (16 caracteres)

3. **Configurar Variáveis de Ambiente:**

Edite `functions/.env` (crie se não existir):

```env
EMAIL_USER=seu-email@gmail.com
EMAIL_PASS=xxxx xxxx xxxx xxxx
```

### 3.2. SendGrid (Recomendado para Produção)

Se preferir usar SendGrid (mais confiável para produção):

1. Crie conta em: https://sendgrid.com
2. Gere uma API Key
3. Modifique `functions/src/posPagamento.js`:

```javascript
// Substituir nodemailer por @sendgrid/mail
import sgMail from '@sendgrid/mail';

sgMail.setApiKey(process.env.SENDGRID_API_KEY);

async function enviarEmail(email, nome, lojaNome, numeroSorte, cupomRoleta, valorTotal) {
  const msg = {
    to: email,
    from: 'seu-email-verificado@dominio.com',
    subject: `🎉 Parabéns! Você está concorrendo - ${lojaNome}`,
    html: /* seu HTML aqui */,
  };

  await sgMail.send(msg);
}
```

---

## 📱 4. Configuração do Envio de WhatsApp

### 4.1. Opções de API WhatsApp

**Opção 1: Evolution API (Open Source)**
- GitHub: https://github.com/EvolutionAPI/evolution-api
- Gratuito e self-hosted
- Requer servidor próprio

**Opção 2: Twilio**
- https://www.twilio.com/whatsapp
- Pago, mas confiável
- Fácil integração

**Opção 3: WhatsApp Business API Oficial**
- Requer aprovação da Meta
- Para empresas de médio/grande porte

### 4.2. Configurar Evolution API (Exemplo)

1. **Instalar Evolution API:**
   ```bash
   docker run -d \
     -p 8080:8080 \
     --name evolution-api \
     atendai/evolution-api
   ```

2. **Conectar Dispositivo:**
   - Acesse: http://localhost:8080
   - Escaneie o QR Code com WhatsApp

3. **Configurar Variáveis de Ambiente:**

Edite `functions/.env`:

```env
WHATSAPP_API_URL=http://seu-servidor:8080/message/sendText/INSTANCE_NAME
WHATSAPP_API_KEY=sua-api-key
```

4. **Ajustar Código (se necessário):**

Veja a documentação da Evolution API para o formato correto da requisição.

---

## 🗄️ 5. Estrutura de Dados no Firestore

### 5.1. Pedidos

Caminho: `/lojas/{lojaId}/pedidos/{pedidoId}`

```json
{
  "vendaId": "12345",
  "cliente": {
    "nome": "João Silva",
    "email": "joao@email.com",
    "telefone": "+5511999999999"
  },
  "itens": [
    {
      "productId": "prod123",
      "nome": "Camiseta",
      "quantidade": 2,
      "precoUnitario": 50.00
    }
  ],
  "total": 100.00,
  "pagamento": "Mercado Pago",
  "status": "pendente",
  "cupomRoleta": {
    "codigo": "ROLETA-ABC123",
    "desconto": 10
  },
  "dataHora": "2024-12-29T10:00:00Z"
}
```

### 5.2. Números da Sorte

Caminho: `/lojas/{lojaId}/numerosSorte/{numeroId}`

```json
{
  "numero": "53827",
  "vendaId": "12345",
  "cliente": {
    "nome": "João Silva",
    "email": "joao@email.com",
    "telefone": "+5511999999999"
  },
  "valorCompra": 100.00,
  "dataGeracao": "2024-12-29T10:05:00Z",
  "ativo": true
}
```

---

## 🧪 6. Testando o Fluxo Completo

### 6.1. Teste Local (Sem Pagamento Real)

1. **Simular Webhook:**

Crie arquivo `test-webhook.js`:

```javascript
const axios = require('axios');

async function testarWebhook() {
  const response = await axios.post(
    'http://localhost:5001/SEU_PROJETO/southamerica-east1/mercadopagoWebhook',
    {
      action: 'payment.updated',
      type: 'payment',
      data: {
        id: '123456789'
      }
    }
  );

  console.log('Resposta:', response.data);
}

testarWebhook();
```

2. **Executar Functions Localmente:**

```bash
firebase emulators:start --only functions
node test-webhook.js
```

### 6.2. Teste em Produção (Sandbox do Mercado Pago)

1. Configure credenciais de **teste** do Mercado Pago
2. Faça uma compra de teste no app
3. Use cartões de teste: https://www.mercadopago.com.br/developers/pt/docs/checkout-api/integration-test/test-cards
4. Verifique os logs no Firebase Console

---

## 📊 7. Monitoramento e Logs

### 7.1. Ver Logs no Firebase Console

```
Firebase Console > Functions > Logs
```

Filtre por:
- `mercadopagoWebhook` para ver webhooks recebidos
- `🔔 Webhook recebido` para ver payload completo
- `❌` para ver erros

### 7.2. Logs Importantes

**Sucesso:**
```
🔔 Webhook recebido do Mercado Pago: {...}
💳 Processando pagamento ID: 123456789
📊 Status do pagamento: approved
🎯 Processando pós-pagamento para venda: 12345
✅ Status atualizado para: pago
📦 Estoque atualizado: Camiseta (10 → 8)
🎲 Número da sorte gerado: 53827
📧 Email enviado para: joao@email.com
📱 WhatsApp enviado para: +5511999999999
✅ Pós-pagamento processado com sucesso!
```

**Erro:**
```
❌ Erro ao processar webhook: Error: Access token not found
```

---

## 🔐 8. Segurança e Boas Práticas

### 8.1. Validar Assinatura do Webhook (Recomendado)

O Mercado Pago envia um header `x-signature` que pode ser usado para validar a autenticidade do webhook.

Adicione em `posPagamento.js`:

```javascript
function validarAssinaturaMercadoPago(req) {
  const signature = req.headers['x-signature'];
  const requestId = req.headers['x-request-id'];
  // Implementar validação conforme documentação do MP
  return true; // ou false se inválido
}

export const mercadopagoWebhook = onRequest(async (req, res) => {
  if (!validarAssinaturaMercadoPago(req)) {
    return res.status(401).send('Unauthorized');
  }
  // resto do código...
});
```

### 8.2. Rate Limiting

O Mercado Pago pode enviar múltiplas notificações para o mesmo pagamento. Implemente idempotência:

```javascript
// Cache de processamentos recentes
const processadosRecentemente = new Set();

async function processarPosPagamento(vendaId, payment) {
  const chave = `${vendaId}-${payment.status}`;

  if (processadosRecentemente.has(chave)) {
    console.log('⚠️ Pagamento já processado recentemente, pulando...');
    return;
  }

  processadosRecentemente.add(chave);
  setTimeout(() => processadosRecentemente.delete(chave), 60000); // 1 minuto

  // resto do código...
}
```

---

## 📋 9. Checklist de Configuração

- [ ] Cloud Functions deployadas
- [ ] Webhook configurado no Mercado Pago
- [ ] Credenciais de email configuradas (.env)
- [ ] API do WhatsApp configurada (opcional)
- [ ] Teste local executado com sucesso
- [ ] Teste em sandbox executado com sucesso
- [ ] Logs monitorados no Firebase Console
- [ ] Validação de assinatura implementada (recomendado)
- [ ] Sistema em produção!

---

## 🆘 10. Troubleshooting

### Webhook não está sendo chamado

1. Verifique se a URL está correta no painel do Mercado Pago
2. Verifique se a function foi deployada: `firebase functions:list`
3. Teste manualmente com curl:
   ```bash
   curl -X POST https://URL_DA_FUNCTION \
     -H "Content-Type: application/json" \
     -d '{"type":"payment","data":{"id":"123"}}'
   ```

### Email não está sendo enviado

1. Verifique as credenciais em `.env`
2. Para Gmail, certifique-se de usar App Password, não a senha normal
3. Verifique os logs: pode haver erro de autenticação
4. Teste o nodemailer isoladamente

### WhatsApp não está sendo enviado

1. Verifique se a API do WhatsApp está rodando
2. Teste a API manualmente com Postman/Insomnia
3. Verifique se o número está no formato correto (+55...)
4. Veja os logs para detalhes do erro

### Estoque não está baixando

1. Verifique se o campo `productId` está presente em `itens[]`
2. Verifique se os produtos existem em `/lojas/{lojaId}/produtos`
3. Veja os logs para warnings sobre produtos não encontrados

---

## 📚 11. Referências

- [Documentação Webhooks Mercado Pago](https://www.mercadopago.com.br/developers/pt/docs/notifications/webhooks)
- [Firebase Cloud Functions](https://firebase.google.com/docs/functions)
- [Nodemailer Documentation](https://nodemailer.com/about/)
- [Evolution API](https://github.com/EvolutionAPI/evolution-api)
- [Twilio WhatsApp API](https://www.twilio.com/docs/whatsapp)

---

**Data:** 29/12/2024
**Versão:** 1.0
**Status:** ✅ Pronto para configuração
