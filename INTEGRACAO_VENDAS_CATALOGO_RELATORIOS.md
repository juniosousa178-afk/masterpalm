# 📊 Integração: Vendas do Catálogo → Relatórios

## ✅ Implementação Concluída

Todas as vendas realizadas pelo **catálogo público** agora são automaticamente registradas no **sistema de relatórios** do MasterPalm.

---

## 🎯 O Que Foi Feito

### 1️⃣ **Serviço de Integração Criado**

**Arquivo**: `lib/services/catalogo_venda_service.dart`

**Funcionalidades**:

- ✅ **`registrarVendaCatalogo()`** - Registra venda do catálogo como venda normal
  - Salva no Hive local (box: `vendas`)
  - Sincroniza com Firestore (`/lojas/{lojaId}/vendas/`)
  - Cria/vincula cliente automaticamente
  - Calcula custos e taxas
  - Gera itens detalhados (VendaItem)
  - Salva pedido completo no Firestore

- ✅ **`atualizarStatusPedido()`** - Atualiza status (pendente → pago → cancelado)

- ✅ **`confirmarPagamento()`** - Marca pagamento como confirmado

- ✅ **`cancelarVenda()`** - Cancela venda do catálogo

### 2️⃣ **Integração no Checkout**

**Modificado**: `lib/screens/public_catalog_screen.dart`

#### **Checkout WhatsApp** (linha 422-443):
```dart
// Registra venda ANTES de abrir WhatsApp
vendaId = await CatalogoVendaService.registrarVendaCatalogo(
  lojaId: widget.lojaId,
  customer: customer,
  items: _cart,
  entrega: entrega,
  pagamento: pagamento,
  observacao: observacao,
);

// Inclui ID do pedido no WhatsApp
buffer.writeln('🔖 Pedido #$vendaId');
```

#### **Checkout Mercado Pago** (linha 517-539):
```dart
// Registra venda com status "pendente"
vendaId = await CatalogoVendaService.registrarVendaCatalogo(...);

// Envia vendaId para a API do MP (webhook pode confirmar depois)
final body = {
  'vendaId': vendaId,
  // ... outros dados
};
```

---

## 📊 Estrutura de Dados

### Venda Registrada (Hive + Firestore)

```dart
Venda {
  // Financeiro
  preco: 150.00,           // Subtotal dos produtos
  total: 160.00,           // Total com frete
  desconto: 0,             // % de desconto aplicado
  frete: 10.00,            // Valor do frete
  custoProdutos: 75.00,    // 50% do preço (estimativa)
  taxas: 21.75,            // R$ 3,50/un + 15% do custo

  // Pagamento
  pagamentoPix: 160.00,    // OU
  pagamentoCartao: 160.00, // OU
  pagamentoDinheiro: 160.00,

  // Cliente
  clienteNome: "João Silva",

  // Produtos
  produtosDescricao: "Produto A x2, Produto B x1",
  quantidade: 3,           // Total de unidades

  // Itens detalhados
  itens: [
    VendaItem {
      produtoNome: "Produto A",
      quantidade: 2,
      precoUnitario: 50.00,
      tamanho: "M",
      lojaId: "loja123",
    },
    VendaItem {
      produtoNome: "Produto B",
      quantidade: 1,
      precoUnitario: 50.00,
      tamanho: "",
      lojaId: "loja123",
    },
  ],

  // Metadata
  data: DateTime.now(),
  vendedor: "Catálogo Web",
  observacao: "...",
  lojaId: "loja123",
}
```

### Cliente Criado/Atualizado

```dart
Cliente {
  nome: "João Silva",
  telefone: "(11) 99999-9999",
  email: "joao@email.com",
  endereco: "CEP 01310-100 - Av. Paulista, 1000 - Bela Vista, São Paulo",
  cep: "01310-100",
  cidade: "São Paulo",
  lojaId: "loja123",
  vendas: [venda1, venda2, ...], // Histórico
}
```

### Pedido no Firestore

```javascript
// /lojas/{lojaId}/pedidos/{pedidoId}
{
  "tipo": "catalogo_web",
  "vendaId": "vendaKey123",
  "cliente": {
    "nome": "João Silva",
    "email": "joao@email.com",
    "telefone": "(11) 99999-9999",
    "endereco": {...}
  },
  "itens": [
    {
      "nome": "Produto A",
      "quantidade": 2,
      "precoUnitario": 50.00,
      "tamanho": "M",
      "total": 100.00
    }
  ],
  "subtotal": 150.00,
  "frete": {
    "nome": "Correios PAC",
    "valor": 10.00,
    "gratis": false,
    "tipo": "correios"
  },
  "cupom": {
    "codigo": "DESCONTO10",
    "desconto": 15.00
  },
  "total": 160.00,
  "pagamento": "PIX",
  "observacao": "Entregar após 18h",
  "dataHora": Timestamp,
  "status": "pendente" // pendente | pago | cancelado
}
```

---

## 🔄 Fluxo Completo

### Cenário 1: Checkout via WhatsApp

```
1. Cliente finaliza compra
   ↓
2. Sistema registra venda
   - Salva em Hive (vendas)
   - Sincroniza Firestore (/lojas/{id}/vendas/)
   - Salva pedido (/lojas/{id}/pedidos/)
   - Cria/atualiza cliente
   - Status: "pendente"
   ↓
3. Abre WhatsApp com mensagem
   - Inclui "🔖 Pedido #123"
   ↓
4. Lojista confirma pagamento manualmente
   - Via admin ou automaticamente
   ↓
5. Chama: CatalogoVendaService.confirmarPagamento()
   - Atualiza status para "pago"
   ↓
6. Venda aparece nos relatórios ✅
```

### Cenário 2: Checkout via Mercado Pago

```
1. Cliente finaliza compra
   ↓
2. Sistema registra venda
   - Status: "pendente"
   - vendaId enviado para API do MP
   ↓
3. Cliente paga no Mercado Pago
   ↓
4. Webhook do MP recebe notificação
   - Busca vendaId
   - Chama: confirmarPagamento(vendaId)
   - Atualiza status para "pago"
   ↓
5. Venda aparece nos relatórios ✅
```

---

## 📈 Relatórios Integrados

Todas as vendas do catálogo agora aparecem em:

### 1. **Relatório de Vendas** (`RelatoriosScreen`)
- ✅ Lista de vendas por período
- ✅ Gráfico de vendas por data
- ✅ Produtos mais vendidos
- ✅ Clientes que mais compram
- ✅ Exportação para Excel

### 2. **Relatório Financeiro** (`RelatorioFinanceiroScreen`)
- ✅ Resumo por DIA/MÊS/ANO
- ✅ Venda total, custo, taxas, lucro
- ✅ Distribuição por forma de pagamento
- ✅ Fechamentos mensais

### 3. **Relatório por Vendedor** (`RelatorioVendedorScreen`)
- ✅ Vendas do "Catálogo Web" (vendedor fixo)
- ✅ Total acumulado
- ✅ Lista detalhada

### 4. **Histórico do Cliente**
- ✅ Cliente criado automaticamente
- ✅ Histórico de compras vinculado
- ✅ Total gasto, última compra, etc.

---

## 💰 Cálculos Financeiros

### Subtotal
```dart
subtotal = soma(item.preco * item.qty)
```

### Frete
```dart
frete = entrega['freteGratis'] ? 0 : entrega['valor']
```

### Desconto
```dart
desconto = cupom aplicado (se houver)
```

### Total
```dart
total = subtotal + frete - desconto
```

### Custo Estimado
```dart
// Como não temos o custo real dos produtos do catálogo,
// usamos 50% como estimativa conservadora
custoProdutos = subtotal * 0.50
```

### Taxas
```dart
// R$ 3,50 por unidade + 15% do custo
taxas = (quantidade * 3.50) + (custoProdutos * 0.15)
```

### Lucro
```dart
lucro = total - (custoProdutos + taxas)
```

**Exemplo**:
```
Subtotal: R$ 150,00
Frete:    R$  10,00
Total:    R$ 160,00

Custo:    R$  75,00  (50% do subtotal)
Taxas:    R$  21,75  (3 un * 3,50 + 75 * 0,15)

Lucro:    R$  63,25  (160 - 75 - 21,75)
```

---

## 🔧 Funções Utilitárias

### Confirmar Pagamento

```dart
await CatalogoVendaService.confirmarPagamento(
  lojaId: 'loja123',
  vendaId: 'vendaKey456',
);
```

### Cancelar Venda

```dart
await CatalogoVendaService.cancelarVenda(
  lojaId: 'loja123',
  vendaId: 'vendaKey456',
);
```

### Atualizar Status

```dart
await CatalogoVendaService.atualizarStatusPedido(
  lojaId: 'loja123',
  vendaId: 'vendaKey456',
  status: 'enviado', // ou 'entregue', 'cancelado', etc
);
```

---

## 🎯 Benefícios da Integração

### Para o Lojista:
✅ **Visão unificada** de todas as vendas (loja física + catálogo web)
✅ **Relatórios precisos** com dados consolidados
✅ **Histórico de clientes** completo
✅ **Fechamento mensal** automático incluindo vendas web
✅ **Análise de produtos** mais vendidos (online + offline)

### Para o Sistema:
✅ **Banco de dados único** (Hive + Firestore sincronizados)
✅ **Não duplica estruturas** (usa mesmos modelos)
✅ **Mantém compatibilidade** com código existente
✅ **Fácil manutenção** (um serviço centralizado)

---

## 📊 Localizações dos Dados

### Hive (Local)
```
vendas (box)
  └─ Venda (com lojaId para isolamento)
       └─ itens: [VendaItem, ...]

clientes (box)
  └─ Cliente (com lojaId)
       └─ vendas: [Venda, ...]
```

### Firestore (Cloud)
```
/lojas/{lojaId}/
  ├─ vendas/{vendaId}          ← Sincronizado do Hive
  │    ├─ preco, total, desconto
  │    ├─ clienteNome
  │    ├─ data, vendedor
  │    └─ itens: [...]
  │
  └─ pedidos/{pedidoId}         ← Detalhes completos do pedido
       ├─ tipo: "catalogo_web"
       ├─ vendaId
       ├─ cliente: {...}
       ├─ itens: [...]
       ├─ frete: {...}
       ├─ cupom: {...}
       ├─ status: "pendente|pago|cancelado"
       └─ dataHora
```

---

## 🔐 Segurança Multi-Loja

Todas as vendas são isoladas por `lojaId`:

```dart
// Filtro automático por loja
final vendasDaLoja = vendasBox.values
    .where((v) => v.lojaId == lojaId)
    .toList();
```

Clientes também pertencem a uma única loja:

```dart
Cliente {
  lojaId: "loja123", // Obrigatório
  // ...
}
```

---

## ⚠️ TODOs Pendentes

No código há 2 TODOs para melhorias futuras:

### 1. Integrar Cupons Aplicados

```dart
// TODO: Pegar do estado se tiver cupom aplicado
cupomCodigo: _cupomAplicado?['codigo'],
desconto: _cupomAplicado?['valor'] ?? 0.0,
```

**O que fazer**:
- No `_CarrinhoSheetWeb`, passar o `_cupomAplicado` para o callback
- Modificar assinatura de `onCheckoutWhatsapp` para incluir cupom

### 2. Webhook Mercado Pago

**Cloud Function necessária**:

```javascript
// functions/webhooks/mercadopago.js
exports.mercadopagoWebhook = functions.https.onRequest(async (req, res) => {
  const { vendaId, status } = req.body;

  if (status === 'approved') {
    // Confirmar pagamento
    await admin.firestore()
      .collection('lojas').doc(lojaId)
      .collection('pedidos')
      .where('vendaId', '==', vendaId)
      .update({ status: 'pago' });
  }

  res.status(200).send('OK');
});
```

---

## ✅ Checklist de Teste

### Teste 1: Venda via WhatsApp
- [ ] Adicionar produtos ao carrinho
- [ ] Preencher dados do cliente
- [ ] Selecionar frete
- [ ] Finalizar pelo WhatsApp
- [ ] Verificar que venda aparece em:
  - [ ] Hive (box vendas)
  - [ ] Firestore (/lojas/{id}/vendas/)
  - [ ] Firestore (/lojas/{id}/pedidos/)
  - [ ] Relatório de Vendas
  - [ ] Relatório Financeiro
  - [ ] Histórico do cliente

### Teste 2: Venda via Mercado Pago
- [ ] Finalizar compra via MP
- [ ] Verificar venda com status "pendente"
- [ ] Confirmar pagamento manualmente:
  ```dart
  CatalogoVendaService.confirmarPagamento(...)
  ```
- [ ] Verificar status atualizado para "pago"

### Teste 3: Cliente Novo vs Existente
- [ ] Primeira compra → cria cliente novo
- [ ] Segunda compra (mesmo email) → vincula ao cliente existente
- [ ] Verificar histórico do cliente

### Teste 4: Relatórios
- [ ] Abrir Relatório de Vendas
- [ ] Filtrar por data que inclua vendas do catálogo
- [ ] Verificar vendas aparecem na lista
- [ ] Verificar vendedor = "Catálogo Web"
- [ ] Exportar para Excel
- [ ] Verificar dados corretos no Excel

---

## 📁 Arquivos Modificados/Criados

### Criados:
1. ✅ `lib/services/catalogo_venda_service.dart` - Serviço de integração

### Modificados:
1. ✅ `lib/screens/public_catalog_screen.dart`
   - Linha 21: Import do serviço
   - Linhas 422-443: Checkout WhatsApp com registro
   - Linhas 517-539: Checkout MP com registro

---

**Data:** 22/12/2024
**Versão:** 1.0 - Integração Vendas Catálogo
**Status:** ✅ Implementado e pronto para teste
**Próximo:** Testar fluxo completo e implementar TODOs opcionais
