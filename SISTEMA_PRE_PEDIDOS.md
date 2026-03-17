# 📦 Sistema de Pré-Pedidos

## ✅ Implementação Concluída

O sistema de pré-pedidos permite que clientes realizem pedidos via catálogo web que **aguardam confirmação do vendedor** antes de se tornarem vendas finais.

---

## 🎯 Funcionalidades

### 1️⃣ **Criação de Pré-Pedidos**

Quando o cliente finaliza compra pelo **WhatsApp**:
- ✅ Cria pré-pedido no Firestore (`/lojas/{lojaId}/pre_pedidos/`)
- ✅ Status inicial: `pendente`
- ✅ NÃO cria venda imediatamente
- ✅ Envia mensagem WhatsApp com link do pedido

### 2️⃣ **Tela de Gerenciamento para Vendedor**

**Arquivo**: `lib/screens/pre_pedidos_screen.dart`

**Funcionalidades**:
- 📋 Duas abas: **Pendentes** e **Todos**
- 🔄 Atualização em tempo real (StreamBuilder)
- 👁️ Visualizar detalhes completos
- ✅ Confirmar pedido (cria venda no sistema)
- ❌ Cancelar pedido

### 3️⃣ **Página Pública de Detalhes**

**Arquivo**: `lib/screens/pedido_publico_screen.dart`

**URL**: `https://mastepalm.com.br/pedido/{prePedidoId}?loja={lojaId}`

**Funcionalidades**:
- 📱 Acessível sem login
- 🎨 Design moderno e responsivo
- 📊 Exibe status (pendente/confirmado/cancelado)
- 🛍️ Lista de itens com imagens
- 💰 Resumo financeiro completo
- 👤 Dados do cliente
- 📋 Observações do pedido
- 📅 Data e hora do pedido
- 📋 ID do pedido copiável

---

## 🔄 Fluxo Completo

### Cenário: Checkout via WhatsApp

```
1. Cliente adiciona produtos ao carrinho
   ↓
2. Preenche dados pessoais e entrega
   ↓
3. Clica em "Finalizar pelo WhatsApp"
   ↓
4. Sistema cria PRÉ-PEDIDO (não venda)
   - Status: pendente
   - Salvo em: /lojas/{lojaId}/pre_pedidos/{id}
   ↓
5. Gera link público:
   https://mastepalm.com.br/pedido/{id}?loja={lojaId}
   ↓
6. Abre WhatsApp com mensagem formatada:
   ┌────────────────────────────────┐
   │ 🛍️ Novo pedido                │
   │                                │
   │ 1x anel cruz – R$ 55.99        │
   │                                │
   │ Subtotal: R$ 55.99             │
   │ Entrega: Retirada – R$ 0.00    │
   │ Total: R$ 55.99                │
   │ Pagamento: Pix                 │
   │                                │
   │ Cliente: João Silva            │
   │ Tel.: (11) 99999-9999          │
   │ Endereço: Rua ABC, 123         │
   │                                │
   │ 🔗 Pedido completo:            │
   │ https://mastepalm.com.br/...  │
   └────────────────────────────────┘
   ↓
7. Cliente envia mensagem ao vendedor
   ↓
8. Vendedor acessa tela "Pré-Pedidos"
   ↓
9. Vendedor clica em "Confirmar Pedido"
   ↓
10. Sistema:
    - Cria VENDA no sistema de relatórios
    - Registra cliente
    - Vincula vendaId ao pré-pedido
    - Atualiza status para: confirmado
    ↓
11. Venda aparece em todos os relatórios ✅
```

---

## 📊 Estrutura de Dados

### Pré-Pedido no Firestore

```javascript
// /lojas/{lojaId}/pre_pedidos/{prePedidoId}
{
  "tipo": "catalogo_web",
  "status": "pendente", // pendente | confirmado | cancelado

  // Cliente
  "cliente": {
    "nome": "João Silva",
    "cpf": "123.456.789-00",
    "email": "joao@email.com",
    "telefone": "(11) 99999-9999",
    "endereco": {
      "cep": "01310-100",
      "rua": "Av. Paulista",
      "numero": "1000",
      "complemento": "Apto 12",
      "bairro": "Bela Vista",
      "cidade": "São Paulo",
      "estado": "SP"
    },
    "enderecoFormatado": "CEP 01310-100 - Av. Paulista, 1000 - Bela Vista, São Paulo - SP"
  },

  // Itens
  "itens": [
    {
      "nome": "Anel Cruz",
      "quantidade": 1,
      "precoUnitario": 55.99,
      "tamanho": "M",
      "imagem": "https://...",
      "total": 55.99
    }
  ],

  // Valores
  "subtotal": 55.99,
  "frete": {
    "nome": "Retirada",
    "valor": 0.00,
    "gratis": false,
    "tipo": "retirada"
  },
  "cupom": null, // ou { "codigo": "...", "desconto": 10.00 }
  "total": 55.99,

  // Pagamento
  "pagamento": "Pix",
  "observacao": "Entregar após 18h",

  // Metadata
  "dataCriacao": Timestamp,
  "dataAtualizacao": Timestamp,
  "dataConfirmacao": null, // Preenchido ao confirmar
  "dataCancelamento": null, // Preenchido ao cancelar
  "origem": "catalogo_web",
  "vendaId": null, // Preenchido ao confirmar
  "lojaId": "loja123"
}
```

---

## 🔧 Serviços

### PrePedidoService

**Arquivo**: `lib/services/pre_pedido_service.dart`

#### Principais Métodos:

**1. Criar Pré-Pedido**
```dart
Future<String?> criarPrePedido({
  required String lojaId,
  required Map<String, dynamic> customer,
  required List<Map<String, dynamic>> items,
  required Map<String, dynamic> entrega,
  required String pagamento,
  String observacao = '',
  String? cupomCodigo,
  double desconto = 0.0,
})
```

**2. Buscar Pré-Pedido**
```dart
Future<Map<String, dynamic>?> buscarPrePedido({
  required String lojaId,
  required String prePedidoId,
})
```

**3. Confirmar Pré-Pedido**
```dart
Future<String?> confirmarPrePedido({
  required String lojaId,
  required String prePedidoId,
  required String vendaId,
})
```

**4. Cancelar Pré-Pedido**
```dart
Future<bool> cancelarPrePedido({
  required String lojaId,
  required String prePedidoId,
  String? motivo,
})
```

**5. Gerar URL do Pedido**
```dart
String gerarUrlPedido({
  required String prePedidoId,
  required String lojaId,
  String baseUrl = 'https://mastepalm.com.br',
})
// Retorna: https://mastepalm.com.br/pedido/{id}?loja={lojaId}
```

**6. Formatar para WhatsApp**
```dart
String formatarParaWhatsApp({
  required Map<String, dynamic> prePedido,
  required String lojaId,
  String baseUrl = 'https://mastepalm.com.br',
})
```

**7. Stream de Pré-Pedidos**
```dart
Stream<List<Map<String, dynamic>>> streamPrePedidos({
  required String lojaId,
  String? status, // null = todos, 'pendente', 'confirmado', 'cancelado'
  int limit = 50,
})
```

---

## 🎨 Telas

### 1. Tela de Gerenciamento (Vendedor)

**Arquivo**: `lib/screens/pre_pedidos_screen.dart`

**Navegação**: Menu Admin → Pré-Pedidos

**Layout**:
```
┌─────────────────────────────────────┐
│  PRÉ-PEDIDOS                        │
├─────────────────────────────────────┤
│  [Pendentes]  [Todos]               │ ← Abas
├─────────────────────────────────────┤
│                                     │
│  ┌───────────────────────────────┐ │
│  │ 🟠 PENDENTE                   │ │
│  │                               │ │
│  │ #abc123                       │ │
│  │ João Silva                    │ │
│  │ 21/12/2024 15:30              │ │
│  │                               │ │
│  │ Total: R$ 55,99               │ │
│  │ Itens: 1                      │ │
│  │ Pagamento: Pix                │ │
│  │                               │ │
│  │ [Ver Detalhes] [Confirmar]    │ │
│  │ [Cancelar]                    │ │
│  └───────────────────────────────┘ │
│                                     │
│  ┌───────────────────────────────┐ │
│  │ 🟢 CONFIRMADO                 │ │
│  │ ...                           │ │
│  └───────────────────────────────┘ │
│                                     │
└─────────────────────────────────────┘
```

**Ações**:
- **Ver Detalhes**: Modal com informações completas
- **Confirmar**: Cria venda e registra nos relatórios
- **Cancelar**: Marca como cancelado

### 2. Página Pública

**Arquivo**: `lib/screens/pedido_publico_screen.dart`

**URL**: `/pedido/{id}?loja={lojaId}`

**Layout**:
```
┌─────────────────────────────────────┐
│  ← Detalhes do Pedido               │
├─────────────────────────────────────┤
│                                     │
│  ┌───────────────────────────────┐ │
│  │  🟠 AGUARDANDO CONFIRMAÇÃO    │ │ ← Status
│  │                               │ │
│  │  Pedido realizado em          │ │
│  │  21/12/2024 15:30             │ │
│  └───────────────────────────────┘ │
│                                     │
│  ┌───────────────────────────────┐ │
│  │  🔖 ID do Pedido              │ │
│  │  abc123 [📋 Copiar]           │ │
│  └───────────────────────────────┘ │
│                                     │
│  ┌───────────────────────────────┐ │
│  │  🛍️ Itens do Pedido           │ │
│  ├───────────────────────────────┤ │
│  │  [Img] Anel Cruz              │ │
│  │        Tamanho: M             │ │
│  │        1x R$ 55,99   R$ 55,99 │ │
│  └───────────────────────────────┘ │
│                                     │
│  ┌───────────────────────────────┐ │
│  │  📊 Resumo                    │ │
│  ├───────────────────────────────┤ │
│  │  Subtotal:  R$ 55,99          │ │
│  │  🚚 Retirada: R$ 0,00         │ │
│  │  ────────────────────          │ │
│  │  Total:     R$ 55,99          │ │
│  │                               │ │
│  │  💳 Pagamento: Pix            │ │
│  └───────────────────────────────┘ │
│                                     │
│  ┌───────────────────────────────┐ │
│  │  👤 Dados do Cliente          │ │
│  ├───────────────────────────────┤ │
│  │  Nome: João Silva             │ │
│  │  Telefone: (11) 99999-9999    │ │
│  │  Email: joao@email.com        │ │
│  │  Endereço: Rua ABC, 123       │ │
│  └───────────────────────────────┘ │
│                                     │
│  MasterPalm                         │
│                                     │
└─────────────────────────────────────┘
```

---

## 🔀 Roteamento

**Arquivo**: `lib/main.dart` (linhas 819-857)

### Lógica de Roteamento

```dart
onGenerateRoute: (settings) {
  if (settings.name?.startsWith('/pedido/') ?? false) {
    // Extrai ID do pedido
    final orderId = settings.name!.split('/pedido/').last.split('?').first;

    // Extrai lojaId dos query parameters
    final uri = Uri.parse(settings.name ?? '');
    String lojaId = uri.queryParameters['loja'] ?? '';

    // Se tem lojaId → Pré-Pedido (novo sistema)
    if (lojaId.isNotEmpty) {
      return MaterialPageRoute(
        builder: (_) => PedidoPublicoScreen(
          lojaId: lojaId,
          prePedidoId: orderId,
        ),
      );
    }
    // Se não tem lojaId → Pedido Temporário (sistema antigo)
    else {
      return MaterialPageRoute(
        builder: (_) => OrderReviewScreen(
          orderId: orderId,
          lojaId: null,
        ),
      );
    }
  }
  return null;
}
```

**URLs Suportadas**:
- `/pedido/abc123?loja=xyz789` → PedidoPublicoScreen (pré-pedido)
- `/pedido/abc123` → OrderReviewScreen (pedido temporário)

---

## 📝 Mensagem WhatsApp

### Formato da Mensagem

A mensagem enviada ao vendedor segue exatamente este formato:

```
🛍️ Novo pedido

1x anel cruz – R$ 55,99

Subtotal: R$ 55,99
Entrega: Retirada – R$ 0,00
Total: R$ 55,99
Pagamento: Pix

Cliente: João Silva
Tel.: (11) 99999-9999
Endereço: Rua ABC, 123 - Bairro - Cidade - UF

🔗 Pedido completo: https://mastepalm.com.br/pedido/abc123?loja=xyz789
```

**Elementos**:
- ✅ Emoji 🛍️ no início
- ✅ Lista de itens com formato: `{qty}x {nome} – R$ {preço}`
- ✅ Resumo financeiro completo
- ✅ Dados do cliente
- ✅ Link público com emoji 🔗

---

## 🔄 Estados do Pré-Pedido

### 1. **Pendente** 🟠

**Status**: `pendente`

**Quando**: Logo após criação

**Ações disponíveis**:
- ✅ Confirmar → Cria venda
- ❌ Cancelar

### 2. **Confirmado** 🟢

**Status**: `confirmado`

**Quando**: Vendedor confirma o pedido

**Campos adicionais**:
- `vendaId`: ID da venda criada
- `dataConfirmacao`: Timestamp da confirmação

**Ações**: Somente visualização

### 3. **Cancelado** 🔴

**Status**: `cancelado`

**Quando**: Vendedor cancela ou cliente desiste

**Campos adicionais**:
- `motivoCancelamento`: Motivo opcional
- `dataCancelamento`: Timestamp do cancelamento

**Ações**: Somente visualização

---

## ✅ Diferenças: Pré-Pedido vs Venda

| Aspecto | Pré-Pedido | Venda |
|---------|------------|-------|
| **Localização** | `/lojas/{id}/pre_pedidos/` | `/lojas/{id}/vendas/` + Hive |
| **Status Inicial** | `pendente` | N/A |
| **Confirmação** | Requer aprovação do vendedor | Imediata |
| **Relatórios** | Não aparece | Aparece em todos |
| **Cliente** | Dados salvos no pedido | Cliente vinculado no Hive |
| **Link Público** | ✅ Sim | ❌ Não |
| **Editável** | ❌ Não | ❌ Não |

---

## 🚀 Como Usar

### Para o Cliente:

1. Acesse o catálogo web
2. Adicione produtos ao carrinho
3. Preencha dados pessoais e entrega
4. Clique em "Finalizar pelo WhatsApp"
5. Envie a mensagem ao vendedor
6. Clique no link para ver detalhes
7. Aguarde confirmação

### Para o Vendedor:

1. Receba notificação de novo pedido via WhatsApp
2. Acesse: Menu → Pré-Pedidos
3. Visualize pedidos pendentes
4. Clique em "Ver Detalhes" para revisar
5. Clique em "Confirmar Pedido"
6. Pedido vira venda e aparece nos relatórios

---

## 📁 Arquivos Criados/Modificados

### Criados:

1. ✅ `lib/screens/pedido_publico_screen.dart` (740 linhas)
   - Página pública para visualizar pré-pedido
   - Design responsivo e moderno
   - Status colorido, itens com imagens, resumo completo

2. ✅ `lib/screens/pre_pedidos_screen.dart` (600+ linhas)
   - Tela de gerenciamento para vendedor
   - Abas Pendentes/Todos
   - Ações: Ver Detalhes, Confirmar, Cancelar

3. ✅ `lib/services/pre_pedido_service.dart` (400+ linhas)
   - CRUD completo de pré-pedidos
   - Geração de URLs
   - Formatação para WhatsApp
   - Streams em tempo real

### Modificados:

1. ✅ `lib/main.dart`
   - Linha 61: Import de `pedido_publico_screen.dart`
   - Linhas 819-857: Roteamento `/pedido/:id?loja=:lojaId`

2. ✅ `lib/screens/public_catalog_screen.dart`
   - Linhas 417-471: Checkout WhatsApp usando pré-pedidos
   - Linha 463: Passa `lojaId` para `formatarParaWhatsApp()`

---

## ⚙️ Configuração Necessária

### 1. Firestore Rules

Permitir leitura pública de pré-pedidos:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /lojas/{lojaId}/pre_pedidos/{pedidoId} {
      // Leitura pública (necessário para página pública)
      allow read: if true;

      // Escrita apenas autenticado
      allow write: if request.auth != null;
    }
  }
}
```

### 2. Índices Firestore

Criar índice composto:

```json
{
  "collectionGroup": "pre_pedidos",
  "queryScope": "COLLECTION",
  "fields": [
    {"fieldPath": "status", "order": "ASCENDING"},
    {"fieldPath": "dataCriacao", "order": "DESCENDING"}
  ]
}
```

### 3. Configuração da Loja

Garantir que `whatsappVendedor` está configurado:

```
Configurações → Loja → WhatsApp do Vendedor
```

---

## 🧪 Testes

### Teste 1: Criar Pré-Pedido

- [ ] Adicionar produtos ao carrinho
- [ ] Preencher todos os dados
- [ ] Finalizar pelo WhatsApp
- [ ] Verificar que pré-pedido foi criado no Firestore
- [ ] Verificar que NÃO criou venda no Hive
- [ ] Verificar mensagem WhatsApp formatada corretamente
- [ ] Verificar que link está presente na mensagem

### Teste 2: Visualizar Pré-Pedido (Página Pública)

- [ ] Clicar no link do pedido
- [ ] Verificar que página abre
- [ ] Verificar status "Aguardando Confirmação"
- [ ] Verificar lista de itens correta
- [ ] Verificar resumo financeiro correto
- [ ] Verificar dados do cliente corretos
- [ ] Copiar ID do pedido

### Teste 3: Confirmar Pré-Pedido

- [ ] Vendedor acessa tela Pré-Pedidos
- [ ] Ver pedido na aba "Pendentes"
- [ ] Clicar em "Ver Detalhes"
- [ ] Verificar informações completas
- [ ] Clicar em "Confirmar Pedido"
- [ ] Verificar que venda foi criada
- [ ] Verificar que aparece nos relatórios
- [ ] Verificar que status mudou para "Confirmado"
- [ ] Verificar que sumiu da aba "Pendentes"

### Teste 4: Cancelar Pré-Pedido

- [ ] Criar novo pré-pedido
- [ ] Acessar tela Pré-Pedidos
- [ ] Clicar em "Cancelar"
- [ ] Informar motivo
- [ ] Verificar que status mudou para "Cancelado"
- [ ] Verificar que NÃO criou venda
- [ ] Verificar que sumiu da aba "Pendentes"

### Teste 5: Link Público com Query Parameters

- [ ] Acessar: `/pedido/abc123?loja=xyz789`
- [ ] Verificar que abre PedidoPublicoScreen
- [ ] Acessar: `/pedido/abc123` (sem query)
- [ ] Verificar que abre OrderReviewScreen (sistema antigo)

---

## 📊 Métricas

### Campos para Análise

No Firestore, cada pré-pedido contém:
- `dataCriacao`: Quando foi criado
- `dataConfirmacao`: Quando foi confirmado (se confirmado)
- `dataCancelamento`: Quando foi cancelado (se cancelado)
- `status`: pendente | confirmado | cancelado

**Análises Possíveis**:
- Taxa de conversão (confirmados / total)
- Tempo médio até confirmação
- Motivos de cancelamento
- Valor médio dos pedidos confirmados vs cancelados

---

## 🔮 Melhorias Futuras

### 1. Notificações Push
- Notificar vendedor quando novo pré-pedido é criado
- Notificar cliente quando pedido é confirmado/cancelado

### 2. Edição de Pré-Pedidos
- Permitir vendedor editar quantidades/valores antes de confirmar
- Ajustar frete ou aplicar descontos

### 3. Chat Integrado
- Cliente e vendedor conversam sobre o pedido
- Histórico de mensagens vinculado ao pedido

### 4. Integração com Mercado Pago
- Criar pré-pedido também no checkout MP
- Confirmar automaticamente após pagamento aprovado

### 5. Estatísticas na Tela de Pré-Pedidos
- Total de pedidos pendentes
- Valor total aguardando confirmação
- Taxa de conversão
- Tempo médio de resposta

---

**Data:** 22/12/2024
**Versão:** 1.0 - Sistema de Pré-Pedidos
**Status:** ✅ Implementado e pronto para uso
**Próximos Passos:** Testar fluxo completo e configurar Firestore rules
