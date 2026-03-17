# 🚀 INTEGRAÇÃO AUTOMÁTICA COM PLATAFORMAS DE FRETE

## ✅ NOVA FUNCIONALIDADE IMPLEMENTADA

Agora quando um cliente finaliza um pedido no catálogo, o sistema **AUTOMATICAMENTE**:
1. ✅ Cria o pré-pedido no app
2. ✅ **ENVIA** o pedido para a plataforma de frete (Melhor Envio)
3. ✅ Adiciona ao **carrinho** da plataforma
4. ✅ Salva ID do carrinho no pedido
5. ✅ Lojista só precisa acessar e finalizar

---

## 🎯 FLUXO COMPLETO ATUALIZADO

### **ANTES (Antigo)**
```
Cliente finaliza pedido
    ↓
Pedido salvo no app
    ↓
❌ Lojista acessa Melhor Envio
❌ Digita MANUALMENTE todos os dados
❌ CEP, nome, endereço, peso, dimensões...
❌ Cria envio do zero
```

### **AGORA (Novo)**
```
Cliente finaliza pedido
    ↓
Pedido salvo no app
    ↓
✅ App AUTOMATICAMENTE envia para Melhor Envio
✅ Todos os dados preenchidos
✅ Cliente, endereço, CEP, peso, dimensões
    ↓
✅ Pedido adicionado ao CARRINHO do Melhor Envio
    ↓
Lojista só precisa:
  1. Acessar Melhor Envio
  2. Ver carrinho (pedido JÁ está lá!)
  3. Clicar em "Checkout"
  4. Pagar frete
  5. Gerar etiqueta
```

---

## 📋 PLATAFORMAS SUPORTADAS

### **1. Melhor Envio** ✅ INTEGRADO
- ✅ **Criação automática** de pedido no carrinho
- ✅ Todos os dados preenchidos
- ✅ ID do carrinho salvo no pedido
- ✅ Protocolo de rastreamento
- ⚠️ **Requer**: Token de API válido

### **2. Frenet** ❌ NÃO SUPORTADO
- ❌ Frenet é apenas **comparador de preços**
- ❌ Não tem API para criar pedidos
- ℹ️ Lojista deve contratar com transportadora escolhida manualmente

### **3. Correios** ❌ NÃO SUPORTADO
- ❌ Requer contrato empresarial
- ❌ Integração manual no site dos Correios
- ℹ️ Sem API pública disponível

### **4. Manual** ⚙️ NÃO APLICÁVEL
- Fretes fixos configurados pelo lojista
- Não requer integração externa

---

## 🔄 FLUXO TÉCNICO DETALHADO

### **1. Cliente Finaliza Pedido**
```
Catálogo Web → Carrinho → Checkout
Cliente preenche:
- Nome: João Silva
- CPF: 123.456.789-00
- Email: joao@email.com
- Telefone: (11) 99999-9999
- CEP: 12345-678
- Endereço: Rua das Flores, 123
- Bairro: Centro
- Cidade: São Paulo
- Estado: SP
```

### **2. Cliente Escolhe Frete**
```
App calcula opções:
[ ] PAC - R$ 25,00
[x] SEDEX - R$ 35,00  ← Cliente escolhe
```

### **3. Cliente Confirma Pedido**
```
Subtotal: R$ 150,00
Frete: R$ 35,00
Total: R$ 185,00
[Finalizar Pedido]
```

### **4. App Cria Pré-Pedido (Automático)**
```dart
PrePedidoService.criarPrePedido(
  lojaId: 'nathy-pratas-e-folheados',
  customer: {
    'nome': 'João Silva',
    'cpf': '12345678900',
    'email': 'joao@email.com',
    'telefone': '11999999999',
    'endereco': {
      'cep': '12345678',
      'rua': 'Rua das Flores',
      'numero': '123',
      'bairro': 'Centro',
      'cidade': 'São Paulo',
      'estado': 'SP'
    }
  },
  items: [...],
  entrega: {
    'nome': 'SEDEX',
    'valor': 35.00,
    'tipo': 'sedex',
    'service_id': 1
  },
  ...
)
```

**Resultado**:
```
Pedido salvo no Firestore
ID: abc123xyz
```

### **5. App Envia para Melhor Envio (AUTOMÁTICO)**

```dart
FreteService.criarPrePedidoNaPlataforma(
  lojaId: 'nathy-pratas-e-folheados',
  pedido: {
    'id': 'abc123xyz',
    'itens': [...],
    'subtotal': 150.00,
    'total': 185.00
  },
  cliente: {
    'nome': 'João Silva',
    'cpf': '12345678900',
    'email': 'joao@email.com',
    'telefone': '11999999999',
    'endereco': {...}
  },
  freteSelecionado: {
    'nome': 'SEDEX',
    'valor': 35.00,
    'tipo': 'sedex',
    'service_id': 1
  }
)
```

**Chamada API**:
```
POST https://melhorenvio.com.br/api/v2/me/cart
Headers:
  Authorization: Bearer {TOKEN}
  Content-Type: application/json

Body:
{
  "service": 1,
  "from": {
    "postal_code": "01310100"
  },
  "to": {
    "name": "João Silva",
    "phone": "11999999999",
    "email": "joao@email.com",
    "document": "12345678900",
    "postal_code": "12345678",
    "address": "Rua das Flores",
    "number": "123",
    "district": "Centro",
    "city": "São Paulo",
    "state_abbr": "SP",
    "country_id": "BR"
  },
  "products": [{
    "name": "Pedido abc123xyz",
    "quantity": 1,
    "unitary_value": 150.00
  }],
  "volumes": [{
    "height": 10,
    "width": 20,
    "length": 30,
    "weight": 0.5
  }],
  "options": {
    "insurance_value": 150.00,
    "receipt": false,
    "own_hand": false
  }
}
```

**Resposta**:
```json
{
  "id": "cart-789xyz",
  "protocol": "ORD-123456",
  "status": "pending",
  ...
}
```

### **6. App Atualiza Pedido (AUTOMÁTICO)**

```
Firestore: lojas/nathy-pratas-e-folheados/pre_pedidos/abc123xyz
{
  ...dados do pedido...,

  "plataformaFrete": {
    "plataforma": "melhor_envio",
    "cart_id": "cart-789xyz",
    "protocol": "ORD-123456",
    "message": "Pedido adicionado ao carrinho do Melhor Envio",
    "instrucoes": "Acesse https://melhorenvio.com.br/painel/carrinho para finalizar",
    "criadoEm": Timestamp
  }
}
```

---

## 👨‍💼 O QUE O LOJISTA FAZ AGORA

### **Passo 1: Ver Pedido no App**
```
App → Menu → Pré-Pedidos ou Pedidos Pendentes
Ver pedido #abc123xyz
Ver dados do cliente
Ver frete escolhido: SEDEX R$ 35,00
✅ Ver que pedido JÁ FOI ENVIADO para Melhor Envio
```

### **Passo 2: Acessar Melhor Envio**
```
1. Abrir navegador
2. Ir para: https://melhorenvio.com.br
3. Fazer login
4. Ir em "Carrinho" ou "Meu Carrinho"
```

### **Passo 3: Ver Pedido no Carrinho**
```
Carrinho do Melhor Envio:
├─ Pedido abc123xyz (JÁ ESTÁ LÁ!)
│  ├─ Cliente: João Silva
│  ├─ CEP: 12345-678
│  ├─ Endereço: Rua das Flores, 123 (PREENCHIDO!)
│  ├─ Serviço: SEDEX
│  └─ Valor: R$ 35,00
```

### **Passo 4: Finalizar e Gerar Etiqueta**
```
1. Clicar em "Checkout"
2. Confirmar dados (tudo preenchido!)
3. Efetuar pagamento do frete
4. Aguardar processamento
5. Gerar etiqueta
6. Imprimir etiqueta
7. Colar na embalagem
8. Despachar produto
```

---

## 📊 ESTRUTURA DO PEDIDO ATUALIZADA

```javascript
lojas/nathy-pratas-e-folheados/pre_pedidos/abc123xyz
{
  "lojaId": "nathy-pratas-e-folheados",
  "status": "pendente",

  // Cliente
  "cliente": {
    "nome": "João Silva",
    "cpf": "12345678900",
    "email": "joao@email.com",
    "telefone": "11999999999",
    "endereco": {
      "cep": "12345-678",
      "rua": "Rua das Flores",
      "numero": "123",
      "bairro": "Centro",
      "cidade": "São Paulo",
      "estado": "SP"
    }
  },

  // Itens
  "itens": [...],

  // Valores
  "subtotal": 150.00,
  "frete": {
    "nome": "SEDEX",
    "valor": 35.00,
    "tipo": "sedex",
    "service_id": 1
  },
  "total": 185.00,

  // ✅ NOVO: Informações da plataforma de frete
  "plataformaFrete": {
    "plataforma": "melhor_envio",
    "cart_id": "cart-789xyz",           // ID no carrinho do Melhor Envio
    "protocol": "ORD-123456",            // Protocolo de rastreamento
    "message": "Pedido adicionado ao carrinho do Melhor Envio",
    "instrucoes": "Acesse https://melhorenvio.com.br/painel/carrinho para finalizar",
    "criadoEm": Timestamp
  },

  // Pagamento
  "pagamento": "pix",
  "statusPagamento": "pendente",

  // Metadata
  "dataCriacao": Timestamp,
  "origem": "catalogo_web"
}
```

---

## ⚙️ CONFIGURAÇÃO NECESSÁRIA

### **Token Melhor Envio**

Para funcionar, você precisa configurar o token do Melhor Envio:

**1. Criar conta no Melhor Envio**
- Acesse: https://melhorenvio.com.br
- Cadastre-se
- Faça login

**2. Gerar Token de API**
- Vá em: Perfil → Configurações → Tokens
- Crie novo token
- Copie o token gerado

**3. Configurar no App**
```
App → Menu → Fretes & Cupons
├─ Provider: Melhor Envio
├─ CEP Origem: 01310-100
└─ Token: cole_o_token_aqui
```

**4. Salvar**

---

## 🎯 BENEFÍCIOS

### **Para o Lojista**
- ✅ **Economia de tempo**: Não precisa digitar dados manualmente
- ✅ **Menos erros**: Dados vêm direto do pedido
- ✅ **Mais rápido**: Pedido já está no carrinho
- ✅ **Mais organizado**: Tudo sincronizado

### **Para o Cliente**
- ✅ **Mais rápido**: Envio processado mais rápido
- ✅ **Menos erros**: Endereço correto desde o início
- ✅ **Rastreamento**: Código disponível assim que gerado

---

## 🔍 LOGS PARA DEBUG

Quando um pedido é criado, procure por estes logs:

```
✅ Pré-pedido criado: abc123xyz
📦 [PRÉ-PEDIDO] Tentando criar pedido na plataforma de frete...
📦 [FRETE] Criando pré-pedido na plataforma: melhor_envio
📤 [MELHOR ENVIO] Criando pedido no carrinho...
   Payload: {...}
📥 [MELHOR ENVIO] Status: 201
📥 [MELHOR ENVIO] Response: {...}
✅ [MELHOR ENVIO] Pedido adicionado ao carrinho!
   ID: cart-789xyz
   Protocol: ORD-123456
✅ [PRÉ-PEDIDO] Pedido adicionado ao carrinho da plataforma!
   Plataforma: melhor_envio
   ID: cart-789xyz
```

Se aparecer erro:
```
❌ [MELHOR ENVIO] Erro 401: Unauthorized
⚠️  Token inválido ou expirado
```
→ Verificar token nas configurações

---

## ⚠️ IMPORTANTE

### **O que o sistema FAZ automaticamente**:
- ✅ Criar pedido no carrinho do Melhor Envio
- ✅ Preencher todos os dados
- ✅ Salvar ID do carrinho
- ✅ Salvar protocolo

### **O que o LOJISTA ainda precisa fazer**:
- ⚙️ Acessar Melhor Envio
- ⚙️ Ir ao carrinho
- ⚙️ Fazer checkout
- ⚙️ Pagar frete
- ⚙️ Gerar etiqueta
- ⚙️ Imprimir e despachar

**O sistema NÃO**:
- ❌ Paga o frete automaticamente
- ❌ Gera etiqueta automaticamente
- ❌ Despacha automaticamente

Isso garante **controle total** ao lojista sobre quando/como enviar! 🎯

---

## 🎉 RESUMO

**ANTES**: Copiar e colar dados manualmente ❌
**AGORA**: Pedido já está no carrinho! ✅

**ECONOMIA**: ~5 minutos por pedido
**ERROS**: Reduzidos a quase zero
**EXPERIÊNCIA**: Muito melhor! 🚀
