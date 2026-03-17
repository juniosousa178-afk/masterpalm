# 🚚 SISTEMA DE FRETE - MasterPalm

## 📋 VISÃO GERAL

O MasterPalm possui um **sistema de frete flexível** que suporta múltiplas plataformas de cálculo e integração automatizada com APIs de transportadoras.

---

## 🎯 PLATAFORMAS SUPORTADAS

### **1. Manual (Padrão)**
- Fretes fixos configurados pelo lojista
- Não depende de APIs externas
- Exemplo: "Retirada Grátis", "Entrega Local R$ 10,00"

### **2. Melhor Envio**
- Integração via API oficial
- Calcula fretes em tempo real
- Múltiplas transportadoras (Correios, Jadlog, Azul, etc.)
- **Requer**: Token de API

### **3. Frenet**
- Integração via API oficial
- Calcula fretes de múltiplas transportadoras
- Comparador de preços
- **Requer**: Token de API

### **4. Correios (Simulação)**
- Implementação básica
- **Requer**: Contrato empresarial com Correios
- PAC e SEDEX

---

## 🔄 FLUXO COMPLETO DO FRETE

### **Passo 1: Cliente Adiciona Produtos ao Carrinho**
```
Cliente navega → Adiciona produtos → Carrinho
```

### **Passo 2: Cliente Vai para Checkout**
```
Checkout Screen → Cliente informa CEP
```

### **Passo 3: Sistema Calcula Frete**

```dart
FreteService.calcularFrete(
  lojaId: 'nathy-pratas-e-folheados',
  cep: '12345678',        // CEP do cliente
  peso: 500,              // Peso total em gramas
  valorDeclarado: 150.00, // Valor dos produtos
  altura: 10,             // cm
  largura: 20,            // cm
  comprimento: 30,        // cm
)
```

**O sistema faz**:
1. Busca configuração de frete no Firestore: `lojas/{lojaId}/config/fretes`
2. Identifica qual provider usar: `manual`, `melhor_envio`, `frenet`, ou `correios`
3. Executa o cálculo conforme o provider

### **Passo 4: Sistema Retorna Opções de Frete**

```dart
[
  {
    'nome': 'PAC',
    'valor': 25.50,
    'prazo': 10,      // dias
    'empresa': 'Correios'
  },
  {
    'nome': 'SEDEX',
    'valor': 35.00,
    'prazo': 3,
    'empresa': 'Correios'
  }
]
```

### **Passo 5: Cliente Escolhe Opção de Frete**
```
[ ] PAC - R$ 25,50 (10 dias)
[x] SEDEX - R$ 35,00 (3 dias)  ← Cliente escolhe
```

### **Passo 6: Pedido é Criado**

```dart
PrePedidoService.criarPrePedido(
  lojaId: 'nathy-pratas-e-folheados',
  customer: {...},
  items: [...],
  entrega: {
    'nome': 'SEDEX',
    'valor': 35.00,
    'gratis': false,
    'tipo': 'sedex'
  },
  pagamento: 'pix',
  ...
)
```

**O sistema salva no Firestore**:
```
lojas/
  nathy-pratas-e-folheados/
    pre_pedidos/
      {pedidoId}/
        ├─ itens: [...]
        ├─ subtotal: 150.00
        ├─ frete:
        │   ├─ nome: "SEDEX"
        │   ├─ valor: 35.00
        │   ├─ gratis: false
        │   └─ tipo: "sedex"
        ├─ total: 185.00
        └─ status: "pendente"
```

---

## 🔌 INTEGRAÇÃO COM PLATAFORMAS DE FRETE

### **Como Funciona Cada Integração**

#### **1️⃣ MANUAL**
```
Configuração → Firestore
Cálculo → Valores fixos
Sem API externa
```

**Exemplo de configuração**:
```json
{
  "provider": "manual",
  "manualFretes": [
    {"nome": "Retirada", "valor": 0},
    {"nome": "Entrega Local", "valor": 10.00},
    {"nome": "Correios PAC", "valor": 25.00}
  ]
}
```

#### **2️⃣ MELHOR ENVIO**
```
Cliente informa CEP
    ↓
App chama FreteService
    ↓
FreteService → API Melhor Envio
    ↓
POST https://melhorenvio.com.br/api/v2/me/shipment/calculate
Headers: Authorization: Bearer {TOKEN}
Body: {
  "from": {"postal_code": "01310100"},
  "to": {"postal_code": "12345678"},
  "package": {
    "height": 10,
    "width": 20,
    "length": 30,
    "weight": 0.5
  }
}
    ↓
API retorna opções
    ↓
App mostra para cliente
```

**Quando o pedido é finalizado**:
- ✅ Informação do frete é **salva no pedido**
- ✅ Valor é **adicionado ao total**
- ⚠️ **NÃO** cria etiqueta automaticamente
- ⚠️ **NÃO** contrata o frete automaticamente

**Para contratar o frete** (após pedido confirmado):
1. Lojista acessa painel Melhor Envio
2. Importa pedido manualmente
3. Gera etiqueta
4. Despacha o produto

#### **3️⃣ FRENET**
```
Cliente informa CEP
    ↓
App chama FreteService
    ↓
FreteService → API Frenet
    ↓
POST https://api.frenet.com.br/shipping/quote
Headers: token: {TOKEN}
Body: {
  "SellerCEP": "01310100",
  "RecipientCEP": "12345678",
  "ShipmentInvoiceValue": 150.00,
  "ShippingItemArray": [{
    "Weight": 0.5,
    "Length": 30,
    "Height": 10,
    "Width": 20,
    "Quantity": 1
  }]
}
    ↓
API retorna opções (Correios, Jadlog, etc.)
    ↓
App mostra para cliente
```

**Quando o pedido é finalizado**:
- ✅ Informação do frete é **salva no pedido**
- ✅ Valor é **adicionado ao total**
- ⚠️ **NÃO** cria etiqueta automaticamente

**Para contratar o frete**:
1. Lojista acessa painel da transportadora
2. Cria envio manualmente
3. Gera etiqueta

#### **4️⃣ CORREIOS**
```
⚠️ Implementação básica/simulada
⚠️ Requer contrato empresarial direto com Correios
```

---

## 📦 ESTRUTURA DO PEDIDO COM FRETE

### **No Firestore**:

```javascript
lojas/nathy-pratas-e-folheados/pre_pedidos/{pedidoId}
{
  "lojaId": "nathy-pratas-e-folheados",
  "tipo": "catalogo_web",
  "status": "pendente",

  // Cliente
  "cliente": {
    "nome": "João Silva",
    "telefone": "+5511999999999",
    "endereco": {
      "cep": "12345-678",
      "rua": "Rua das Flores",
      "numero": "123",
      "bairro": "Centro",
      "cidade": "São Paulo",
      "estado": "SP"
    }
  },

  // Itens do pedido
  "itens": [
    {
      "nome": "Anel de Prata",
      "quantidade": 2,
      "precoUnitario": 75.00,
      "total": 150.00
    }
  ],

  // Valores
  "subtotal": 150.00,

  // ✅ FRETE DETALHADO
  "frete": {
    "nome": "SEDEX",           // Nome da opção escolhida
    "valor": 35.00,            // Valor do frete
    "gratis": false,           // Se é frete grátis
    "tipo": "sedex",           // Tipo/código da transportadora
    "prazo": 3,                // Prazo de entrega (dias) - opcional
    "empresa": "Correios"      // Nome da transportadora - opcional
  },

  "cupom": null,
  "total": 185.00,             // subtotal + frete - desconto

  // Pagamento
  "pagamento": "pix",
  "statusPagamento": "pendente",

  // Metadata
  "dataCriacao": Timestamp,
  "origem": "catalogo_web"
}
```

---

## ⚙️ CONFIGURAÇÃO DO FRETE

### **Localização no Firestore**:
```
lojas/{lojaId}/config/fretes
```

### **Estrutura**:

```javascript
{
  // Provider ativo
  "provider": "frenet",  // manual | melhor_envio | frenet | correios

  // CEP de origem (obrigatório para APIs)
  "cepOrigem": "01310100",

  // Fretes manuais (quando provider = manual)
  "manualFretes": [
    {"nome": "Retirada", "valor": 0},
    {"nome": "Entrega Local", "valor": 10.00}
  ],

  // Token Melhor Envio
  "melhorEnvio": {
    "token": "SEU_TOKEN_AQUI"
  },

  // Token Frenet
  "frenet": {
    "token": "SEU_TOKEN_AQUI"
  },

  // Credenciais Correios
  "correios": {
    "usuario": "SEU_USUARIO",
    "senha": "SUA_SENHA"
  }
}
```

---

## 🎯 FLUXO PÓS-PEDIDO (O QUE ACONTECE APÓS FINALIZAR)

### **1. Pedido Criado → Status "Pendente"**
```
✅ Frete calculado e salvo
✅ Valor adicionado ao total
✅ Cliente vê resumo com frete
```

### **2. Lojista Visualiza Pedido**
```
Tela: "Pré-Pedidos" ou "Pedidos Pendentes"
├─ Vê todos os dados
├─ Vê opção de frete escolhida
└─ Vê valor do frete
```

### **3. Lojista Confirma Pedido**
```
Opção 1: Aprovar pedido
Opção 2: Rejeitar pedido
```

### **4. Lojista Contrata o Frete** (MANUAL)

**Se usou Melhor Envio**:
1. Acessa https://melhorenvio.com.br
2. Faz login
3. Vai em "Cotações" ou "Criar Envio"
4. Preenche dados do pedido:
   - CEP origem
   - CEP destino
   - Peso/dimensões
   - Valor declarado
5. Escolhe transportadora
6. **Gera etiqueta**
7. **Imprime etiqueta**
8. Cola na embalagem

**Se usou Frenet**:
- Frenet é um **comparador**
- Não gera etiquetas
- Lojista deve contratar com a transportadora escolhida:
  - Correios → site dos Correios
  - Jadlog → site Jadlog
  - Total Express → site Total Express
  - etc.

**Se usou Manual**:
- Lojista organiza entrega por conta própria
- Ou contrata frete diretamente

### **5. Despacho**
```
Etiqueta gerada → Cola na caixa → Envia produto → Rastreio
```

---

## ⚠️ IMPORTANTE: O QUE O APP **NÃO FAZ**

❌ **NÃO** gera etiqueta automaticamente
❌ **NÃO** contrata o frete automaticamente
❌ **NÃO** envia dados para transportadora
❌ **NÃO** cria tracking automaticamente

**O app APENAS**:
✅ Calcula o frete
✅ Mostra opções para o cliente
✅ Salva escolha no pedido
✅ Adiciona valor ao total

---

## 🔧 COMO CONFIGURAR

### **1. Acessar Configurações**
```
Menu ☰ → Fretes & Cupons
```

### **2. Escolher Provider**
```
[ ] Manual
[ ] Melhor Envio
[x] Frenet
[ ] Correios
```

### **3. Configurar Credenciais**

**Para Melhor Envio**:
1. Criar conta em https://melhorenvio.com.br
2. Gerar token de API
3. Colar no app

**Para Frenet**:
1. Criar conta em https://www.frenet.com.br
2. Gerar token de API
3. Colar no app

### **4. Definir CEP de Origem**
```
CEP de onde você envia: 01310-100
```

### **5. Testar**
```
Ir ao catálogo → Adicionar produto → Checkout → Informar CEP
Verificar se aparece opções de frete
```

---

## 📊 RESUMO VISUAL

```
FLUXO COMPLETO:

Cliente         App MasterPalm       API Frete         Firestore
   |                  |                   |                 |
   |--CEP------------>|                   |                 |
   |                  |                   |                 |
   |                  |--Calcular-------->|                 |
   |                  |   Frete           |                 |
   |                  |                   |                 |
   |                  |<--Opções----------|                 |
   |                  |   PAC, SEDEX      |                 |
   |                  |                   |                 |
   |<-Opções----------|                   |                 |
   |  PAC R$25        |                   |                 |
   |  SEDEX R$35      |                   |                 |
   |                  |                   |                 |
   |--Escolhe-------->|                   |                 |
   |  SEDEX           |                   |                 |
   |                  |                   |                 |
   |                  |--Salva Pedido------------------->  |
   |                  |  + Frete SEDEX R$35               |
   |                  |                                    |
   |<-Confirmação-----|                                    |
   |  Pedido criado!  |                                    |


PÓS-PEDIDO (Lojista):

Lojista        App MasterPalm       Melhor Envio      Transportadora
   |                  |                   |                 |
   |--Vê Pedido------>|                   |                 |
   |  (com frete)     |                   |                 |
   |                  |                   |                 |
   |                                      |                 |
   |--------------Acessa----------------->|                 |
   |              Site Manual             |                 |
   |                                      |                 |
   |<-Cotação/Etiqueta--------------------|                 |
   |                                      |                 |
   |--Envia Produto------------------------------------------->|
   |  com etiqueta                                          |
   |                                                         |
   |<-Tracking Code----------------------------------------------|
```

---

## 🎯 EM RESUMO

1. **Durante o Checkout**: App calcula frete via API
2. **Cliente escolhe**: Opção de frete desejada
3. **Pedido salvo**: Com informação completa do frete
4. **Lojista acessa**: Painel da plataforma de frete (manual)
5. **Lojista gera**: Etiqueta manualmente
6. **Lojista envia**: Produto com etiqueta

**O APP É APENAS PARA CALCULAR E MOSTRAR OPÇÕES**

**CONTRATAÇÃO E DESPACHO SÃO MANUAIS**

Isso dá flexibilidade para o lojista escolher quando/como enviar! 🚀
