# 🔧 Correções - Sistema de Pré-Pedidos

## ✅ Erros Corrigidos

### 1. **Missing `lojaId` parameter** (pre_pedidos_screen.dart:394)

**Erro:**
```
error - The named parameter 'lojaId' is required, but there's no corresponding argument
```

**Localização:** `lib/screens/pre_pedidos_screen.dart:394`

**Causa:** Chamada de `gerarUrlPedido()` sem passar o parâmetro obrigatório `lojaId`

**Correção:**
```dart
// ❌ ANTES
final url = PrePedidoService.gerarUrlPedido(
  prePedidoId: prePedido['id'] ?? '',
);

// ✅ DEPOIS
final url = PrePedidoService.gerarUrlPedido(
  prePedidoId: prePedido['id'] ?? '',
  lojaId: widget.lojaId,
);
```

---

### 2. **Missing `formasPagamento` parameter** (catalogo_venda_service.dart:95)

**Erro:**
```
error - The named parameter 'formasPagamento' is required, but there's no corresponding argument
```

**Localização:** `lib/services/catalogo_venda_service.dart:95`

**Causa:** Construtor de `Venda` requer o parâmetro `formasPagamento`

**Correção:**
```dart
// ❌ ANTES
final venda = Venda(
  preco: subtotal,
  total: total,
  desconto: (desconto / subtotal * 100).clamp(0, 100),
  clienteNome: cliente.nome,
  // ... outros campos
  itens: vendaItens,
);

// Definir forma de pagamento DEPOIS
switch (pagamento.toUpperCase()) {
  case 'PIX':
    venda.pagamentoPix = total;
    break;
  // ...
}

// ✅ DEPOIS
// Definir valores de pagamento ANTES
double pagamentoPix = 0.0;
double pagamentoCartao = 0.0;
double pagamentoDinheiro = 0.0;

switch (pagamento.toUpperCase()) {
  case 'PIX':
    pagamentoPix = total;
    break;
  case 'CARTÃO':
  case 'CARTAO':
  case 'MERCADO PAGO':
    pagamentoCartao = total;
    break;
  case 'DINHEIRO':
    pagamentoDinheiro = total;
    break;
  default:
    pagamentoPix = total;
}

final venda = Venda(
  preco: subtotal,
  total: total,
  // ... outros campos
  formasPagamento: pagamento, // ✅ Adicionado
  pagamentoPix: pagamentoPix, // ✅ Adicionado
  pagamentoCartao: pagamentoCartao, // ✅ Adicionado
  pagamentoDinheiro: pagamentoDinheiro, // ✅ Adicionado
);
```

---

### 3. **Undefined getter/setter 'vendas'** (catalogo_venda_service.dart:141-144)

**Erros:**
```
error - The getter 'vendas' isn't defined for the type 'Cliente'
error - The setter 'vendas' isn't defined for the type 'Cliente'
```

**Localização:** `lib/services/catalogo_venda_service.dart:141-144`

**Causa:** O modelo `Cliente` usa `historico`, não `vendas`

**Correção:**
```dart
// ❌ ANTES
if (cliente.vendas == null) {
  cliente.vendas = HiveList(vendasBox);
}
cliente.vendas!.add(venda);
await cliente.save();

// ✅ DEPOIS
if (cliente.historico == null) {
  cliente.historico = HiveList(vendasBox);
}
cliente.historico!.add(venda);
await cliente.save();
```

---

### 4. **Wrong parameters for syncVenda** (catalogo_venda_service.dart:149)

**Erro:**
```
error - Too many positional arguments: 1 expected, but 2 found
```

**Localização:** `lib/services/catalogo_venda_service.dart:149`

**Causa:** `syncVenda()` espera `lojaId` como parâmetro nomeado, não posicional

**Correção:**
```dart
// ❌ ANTES
await VendasFirestoreService.syncVenda(venda, lojaId);

// ✅ DEPOIS
await VendasFirestoreService.syncVenda(venda, lojaId: lojaId);
```

---

### 5. **Incorrect parameter name in fold** (catalogo_venda_service.dart:101)

**Info:**
```
info - The parameter name 'sum' matches a visible type name
```

**Localização:** `lib/services/catalogo_venda_service.dart:101`

**Causa:** Nome do parâmetro `sum` pode confundir com tipo `num`

**Correção:**
```dart
// ❌ ANTES
quantidade: items.fold<int>(0, (sum, item) => sum + ((item['qty'] as int?) ?? 1)),

// ✅ DEPOIS
quantidade: items.fold<int>(0, (prev, item) => prev + ((item['qty'] as int?) ?? 1)),
```

---

## 📊 Resultado Final

### Antes das Correções:
```
220 issues found
- 6 errors ❌
- 214 warnings/info
```

### Depois das Correções:
```
213 issues found
- 0 errors ✅
- 213 warnings/info
```

**Status:** ✅ **Todos os erros corrigidos!**

Apenas warnings e sugestões de estilo permanecem (que são aceitáveis).

---

## 🔍 Arquivos Modificados

### 1. `lib/screens/pre_pedidos_screen.dart`
- **Linha 394-397**: Adicionado parâmetro `lojaId` na chamada de `gerarUrlPedido()`

### 2. `lib/services/catalogo_venda_service.dart`
- **Linhas 94-135**: Refatorado criação da `Venda`
  - Movido definição de formas de pagamento para ANTES do construtor
  - Adicionado parâmetro `formasPagamento`
  - Adicionado parâmetros `pagamentoPix`, `pagamentoCartao`, `pagamentoDinheiro`

- **Linhas 149-153**: Corrigido uso de `cliente.historico` (antes era `vendas`)

- **Linha 157**: Corrigido chamada de `syncVenda()` com parâmetro nomeado

- **Linha 123**: Renomeado parâmetro de `sum` para `prev` no fold

---

## ✅ Checklist de Validação

- [x] `flutter analyze` sem erros
- [x] Parâmetros obrigatórios fornecidos
- [x] Nomes de campos corretos (historico vs vendas)
- [x] Parâmetros nomeados usados corretamente
- [x] Código compila sem erros

---

**Data:** 22/12/2024
**Status:** ✅ Correções Completas
**Próximo:** Testar fluxo completo de pré-pedidos
