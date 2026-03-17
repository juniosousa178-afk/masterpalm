# 📨 Exemplos de Requisições Webhook

## Testar Verificação (GET)

### WhatsApp

```bash
curl -X GET "https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookWhatsApp?hub.mode=subscribe&hub.verify_token=masterpalm_verify_2026&hub.challenge=TESTE123"
```

**Resposta esperada:** `TESTE123`

### Instagram

```bash
curl -X GET "https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookInstagram?hub.mode=subscribe&hub.verify_token=masterpalm_verify_2026&hub.challenge=TESTE456"
```

**Resposta esperada:** `TESTE456`

### Messenger

```bash
curl -X GET "https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookMessenger?hub.mode=subscribe&hub.verify_token=masterpalm_verify_2026&hub.challenge=TESTE789"
```

**Resposta esperada:** `TESTE789`

---

## Simular Mensagem WhatsApp (POST)

```bash
curl -X POST https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookWhatsApp \
  -H "Content-Type: application/json" \
  -d '{
    "object": "whatsapp_business_account",
    "entry": [{
      "id": "WHATSAPP_BUSINESS_ACCOUNT_ID",
      "changes": [{
        "field": "messages",
        "value": {
          "messaging_product": "whatsapp",
          "metadata": {
            "display_phone_number": "15551234567",
            "phone_number_id": "123456789012345"
          },
          "contacts": [{
            "profile": {
              "name": "Test User"
            },
            "wa_id": "5511999999999"
          }],
          "messages": [{
            "from": "5511999999999",
            "id": "wamid.test123",
            "timestamp": "1234567890",
            "type": "text",
            "text": {
              "body": "Olá!"
            }
          }]
        }
      }]
    }]
  }'
```

**Importante:** Substitua `phone_number_id` pelo ID configurado no Firestore!

---

## Simular Mensagem Instagram (POST)

```bash
curl -X POST https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookInstagram \
  -H "Content-Type: application/json" \
  -d '{
    "object": "instagram",
    "entry": [{
      "id": "17841405822304914",
      "time": 1234567890,
      "messaging": [{
        "sender": {
          "id": "1234567890"
        },
        "recipient": {
          "id": "17841405822304914"
        },
        "timestamp": 1234567890,
        "message": {
          "mid": "mid.test123",
          "text": "Quanto custa a camisa?"
        }
      }]
    }]
  }'
```

**Importante:** Substitua o `entry.id` pelo Instagram Business Account ID!

---

## Simular Mensagem Messenger (POST)

```bash
curl -X POST https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookMessenger \
  -H "Content-Type: application/json" \
  -d '{
    "object": "page",
    "entry": [{
      "id": "108316244769394",
      "time": 1234567890,
      "messaging": [{
        "sender": {
          "id": "1234567890"
        },
        "recipient": {
          "id": "108316244769394"
        },
        "timestamp": 1234567890,
        "message": {
          "mid": "mid.test456",
          "text": "Tem em estoque?"
        }
      }]
    }]
  }'
```

**Importante:** Substitua o `entry.id` pelo Page ID configurado!

---

## Testar Diferentes Intents

### Saudação

```json
{
  "text": {
    "body": "Olá!"
  }
}
```

### Consulta de Preço

```json
{
  "text": {
    "body": "Quanto custa a camisa polo?"
  }
}
```

### Consulta de Estoque

```json
{
  "text": {
    "body": "Tem camisa polo em estoque?"
  }
}
```

### Tamanhos

```json
{
  "text": {
    "body": "Quais tamanhos têm?"
  }
}
```

### Cores

```json
{
  "text": {
    "body": "Quais cores disponíveis?"
  }
}
```

### Fotos

```json
{
  "text": {
    "body": "Manda foto do produto"
  }
}
```

### Handover

```json
{
  "text": {
    "body": "Quero falar com um atendente"
  }
}
```

### Frete

```json
{
  "text": {
    "body": "Quanto fica o frete?"
  }
}
```

### Pagamento

```json
{
  "text": {
    "body": "Aceita cartão de crédito?"
  }
}
```

### Horário

```json
{
  "text": {
    "body": "Qual o horário de funcionamento?"
  }
}
```

---

## Ver Logs em Tempo Real

```bash
# WhatsApp
firebase functions:log --only webhookWhatsApp

# Instagram
firebase functions:log --only webhookInstagram

# Messenger
firebase functions:log --only webhookMessenger

# Todos
firebase functions:log
```

---

## Payload Real da Meta

### Exemplo WhatsApp (enviado pela Meta)

```json
{
  "object": "whatsapp_business_account",
  "entry": [
    {
      "id": "WHATSAPP_BUSINESS_ACCOUNT_ID",
      "changes": [
        {
          "value": {
            "messaging_product": "whatsapp",
            "metadata": {
              "display_phone_number": "15551234567",
              "phone_number_id": "PHONE_NUMBER_ID"
            },
            "contacts": [
              {
                "profile": {
                  "name": "John Doe"
                },
                "wa_id": "5511999999999"
              }
            ],
            "messages": [
              {
                "from": "5511999999999",
                "id": "wamid.HBgLNTUxMTk5...",
                "timestamp": "1703001234",
                "text": {
                  "body": "Olá, quanto custa a camisa?"
                },
                "type": "text"
              }
            ]
          },
          "field": "messages"
        }
      ]
    }
  ]
}
```

### Exemplo Instagram (enviado pela Meta)

```json
{
  "object": "instagram",
  "entry": [
    {
      "id": "17841405822304914",
      "time": 1703001234,
      "messaging": [
        {
          "sender": {
            "id": "1234567890"
          },
          "recipient": {
            "id": "17841405822304914"
          },
          "timestamp": 1703001234,
          "message": {
            "mid": "mid.ABCxyz123",
            "text": "Tem em estoque?"
          }
        }
      ]
    }
  ]
}
```

### Exemplo Messenger (enviado pela Meta)

```json
{
  "object": "page",
  "entry": [
    {
      "id": "108316244769394",
      "time": 1703001234,
      "messaging": [
        {
          "sender": {
            "id": "1234567890"
          },
          "recipient": {
            "id": "108316244769394"
          },
          "timestamp": 1703001234,
          "message": {
            "mid": "mid.ABCxyz456",
            "text": "Quais cores têm?"
          }
        }
      ]
    }
  ]
}
```

---

## Testar com Postman

1. **Criar requisição GET:**
   - URL: `https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookWhatsApp`
   - Params:
     - `hub.mode` = subscribe
     - `hub.verify_token` = masterpalm_verify_2026
     - `hub.challenge` = TEST123

2. **Criar requisição POST:**
   - URL: `https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/webhookWhatsApp`
   - Headers: `Content-Type: application/json`
   - Body: Copiar exemplo acima

3. **Send** e verificar resposta!

---

## Debug com Firebase Emulator (Local)

```bash
cd functions

# Iniciar emulador
firebase emulators:start --only functions

# Em outro terminal, testar
curl http://localhost:5001/masterpalm-58c46/southamerica-east1/webhookWhatsApp?hub.mode=subscribe&hub.verify_token=masterpalm_verify_2026&hub.challenge=LOCAL_TEST
```

---

## Estrutura Esperada no Firestore

Para a função encontrar a loja, deve existir:

```
lojas/
  loja123/
    canais/
      whatsapp/
        enabled: true
        phone_number_id: "123456789012345"  ← DEVE BATER com payload
        access_token: "EAAxxxx..."

      instagram/
        enabled: true
        ig_business_account_id: "17841405822304914"  ← DEVE BATER
        page_access_token: "EAAxxxx..."

      messenger/
        enabled: true
        page_id: "108316244769394"  ← DEVE BATER
        page_access_token: "EAAxxxx..."
```

**IMPORTANTE:** Os IDs no payload devem corresponder exatamente aos salvos no Firestore!
