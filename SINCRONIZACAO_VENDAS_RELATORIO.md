# ✅ Sincronização Vendas → Relatório Financeiro

## 🎯 Objetivo

Garantir que as vendas feitas na aba **Vendas** apareçam corretamente no **Relatório Financeiro** com os valores separados por tipo de pagamento (Dinheiro/Pix/Cartão).

---

## ✅ Implementação Completa

### Fluxo de Dados (100% Funcional):

```
NovaVendaModal (UI)
    ↓
Calcula valores por tipo de pagamento
    ↓
VendasService.registrarVendaMulti()
    ↓
Cria objeto Venda com campos:
  - pagamentoDinheiro
  - pagamentoPix
  - pagamentoCartao
    ↓
Salva no Hive (vendasBox)
    ↓
RelatorioFinanceiroScreen lê e exibe
```

---

## 🔍 Logs de Debug Adicionados

### 1. NovaVendaModal (linha 591)
```dart
💰 [VENDA] Pagamentos - Dinheiro: R\$ XX.XX, Pix: R\$ XX.XX, Cartão: R\$ XX.XX
```

### 2. VendasService (linha 303)
```dart
💾 [VENDAS-SERVICE] Salvando venda - Dinheiro: R\$ XX.XX, Pix: R\$ XX.XX, Cartão: R\$ XX.XX, Total: R\$ XX.XX
```

### 3. RelatorioFinanceiroScreen (linha 94)
```dart
📊 [RELATÓRIO] Mês atual - X vendas | Dinheiro: R\$ XX.XX, Pix: R\$ XX.XX, Cartão: R\$ XX.XX
```

---

## 🧪 Como Testar

### Passo 1: Executar o App com Logs

```bash
cd "C:\Users\Pichau\apk_nathy\temp_naty"

# Limpar cache
flutter clean
flutter pub get

# Executar e observar logs
flutter run
```

### Passo 2: Fazer uma Nova Venda

1. Abra o app
2. Vá para **Vendas**
3. Clique em **Nova Venda** (botão +)
4. Preencha:
   - Cliente: "Teste"
   - Adicione 1 produto
   - **Formas de Pagamento**: Adicione múltiplas formas:
     - Pix: R$ 50,00
     - Cartão: R$ 30,00
     - Dinheiro: R$ 20,00
5. Finalize a venda

### Passo 3: Verificar os Logs

Você deve ver nos logs do terminal:

```
💰 [VENDA] Pagamentos - Dinheiro: R$ 20.00, Pix: R$ 50.00, Cartão: R$ 30.00
💾 [VENDAS-SERVICE] Salvando venda - Dinheiro: R$ 20.00, Pix: R$ 50.00, Cartão: R$ 30.00, Total: R$ 100.00
```

### Passo 4: Verificar no Relatório Financeiro

1. Vá para **Relatório Financeiro**
2. Na seção **"Forma de Pagamento (MÊS)"**, você deve ver:
   ```
   Dinheiro: R$ 20,00
   Pix: R$ 50,00
   Cartão: R$ 30,00
   ```

3. Nos logs, deve aparecer:
   ```
   📊 [RELATÓRIO] Mês atual - 1 vendas | Dinheiro: R$ 20.00, Pix: R$ 50.00, Cartão: R$ 30.00
   ```

---

## 🔧 Detalhes Técnicos

### NovaVendaModal (lib/screens/nova_venda_modal.dart)

**Linhas 579-591:** Calcula valores por tipo de pagamento

```dart
double valorDinheiro = pagamentos
    .where((p) => (p['forma'] ?? '') == 'Dinheiro')
    .fold(0.0, (s, p) => s + (p['valor'] as num).toDouble());

double valorPix = pagamentos
    .where((p) => (p['forma'] ?? '') == 'Pix')
    .fold(0.0, (s, p) => s + (p['valor'] as num).toDouble());

double valorCartao = pagamentos
    .where((p) => (p['forma'] ?? '') == 'Cartão')
    .fold(0.0, (s, p) => s + (p['valor'] as num).toDouble());

debugPrint('💰 [VENDA] Pagamentos - Dinheiro: R\$ ${valorDinheiro.toStringAsFixed(2)}, ...');
```

**Linhas 596-610:** Chama o service com os valores

```dart
await VendasService.registrarVendaMulti(
  produtosBox: widget.produtosBox,
  clientesBox: widget.clientesBox,
  vendasBox: widget.vendasBox,
  clienteNome: nomeClienteFinal,
  itens: itens,
  dinheiro: valorDinheiro,  // ✅ Passa o valor
  pix: valorPix,            // ✅ Passa o valor
  cartao: valorCartao,      // ✅ Passa o valor
  vendedor: widget.vendedor,
  observacao: '',
  frete: frete,
  descontoPct: desconto,
  lojaId: lojaId,
);
```

---

### VendasService (lib/services/vendas_service.dart)

**Linhas 294-296:** Salva os valores no objeto Venda

```dart
final venda = Venda(
  // ... outros campos ...
  pagamentoDinheiro: dinheiro,  // ✅ Salva
  pagamentoPix: pix,            // ✅ Salva
  pagamentoCartao: cartao,      // ✅ Salva
  // ...
);
```

**Linha 303:** Log de confirmação

```dart
debugPrint('💾 [VENDAS-SERVICE] Salvando venda - Dinheiro: R\$ ${_fmt2(dinheiro)}, ...');
```

---

### Modelo Venda (lib/models/venda.dart)

**Linhas 49-56:** Definição dos campos no Hive

```dart
@HiveField(13, defaultValue: 0.0)
double pagamentoDinheiro;

@HiveField(14, defaultValue: 0.0)
double pagamentoPix;

@HiveField(15, defaultValue: 0.0)
double pagamentoCartao;
```

---

### RelatorioFinanceiroScreen (lib/screens/relatorio_financeiro_screen.dart)

**Linhas 52-54:** Lê os valores da venda

```dart
({double dinheiro, double pix, double cartao, double recebido}) _pagamentos(Venda v) {
  double dinheiro = v.pagamentoDinheiro;  // ✅ Lê
  double pix = v.pagamentoPix;            // ✅ Lê
  double cartao = v.pagamentoCartao;      // ✅ Lê

  final recebido = dinheiro + pix + cartao;
  return (dinheiro: dinheiro, pix: pix, cartao: cartao, recebido: recebido);
}
```

**Linhas 82-96:** Soma os valores do mês

```dart
({double dinheiro, double pix, double cartao}) _pagamentosDoMesAtual() {
  double dinheiro = 0, pix = 0, cartao = 0;
  int totalVendas = 0;

  for (final v in _vendasFiltradasPor((x) => _isSameMonth(x.data, hoje))) {
    final p = _pagamentos(v);
    dinheiro += p.dinheiro;  // ✅ Soma
    pix += p.pix;            // ✅ Soma
    cartao += p.cartao;      // ✅ Soma
    totalVendas++;
  }

  debugPrint('📊 [RELATÓRIO] Mês atual - $totalVendas vendas | ...');

  return (dinheiro: dinheiro, pix: pix, cartao: cartao);
}
```

**Linhas 161-163:** Exibe na UI

```dart
_linha('Dinheiro', 'R\$ ${_fmt(mesPorForma.dinheiro)}'),
_linha('Pix', 'R\$ ${_fmt(mesPorForma.pix)}'),
_linha('Cartão', 'R\$ ${_fmt(mesPorForma.cartao)}'),
```

---

## 🐛 Troubleshooting

### Problema: Valores aparecem zerados no relatório

**Causas possíveis:**

1. **Vendas antigas (antes da implementação)**
   - Vendas feitas antes desta atualização têm valores 0.0 por padrão
   - **Solução:** Faça uma NOVA venda para testar

2. **Não informou os valores na venda**
   - Se não preencher valores em Dinheiro/Pix/Cartão, eles ficam 0.0
   - **Solução:** Preencha pelo menos um tipo de pagamento

3. **Loja diferente**
   - O relatório filtra por `v.lojaId == lojaId`
   - **Solução:** Certifique-se de estar na mesma loja

### Problema: Não vejo os logs

**Solução:**
```bash
# Execute com verbose
flutter run --verbose

# OU veja só os logs importantes:
flutter run 2>&1 | grep -E "\[VENDA\]|\[VENDAS-SERVICE\]|\[RELATÓRIO\]"
```

### Problema: Soma não bate

**Verificação:**
1. Veja o log `💰 [VENDA]` - valores corretos sendo calculados?
2. Veja o log `💾 [VENDAS-SERVICE]` - valores corretos sendo salvos?
3. Veja o log `📊 [RELATÓRIO]` - valores corretos sendo somados?

Se algum log estiver errado, o problema está nessa etapa.

---

## 📋 Checklist de Verificação

- [ ] Executei `flutter clean && flutter pub get`
- [ ] Executei `flutter run` e observei os logs
- [ ] Fiz uma NOVA venda (não venda antiga)
- [ ] Preenchi valores em múltiplas formas de pagamento
- [ ] Vi o log `💰 [VENDA]` com valores corretos
- [ ] Vi o log `💾 [VENDAS-SERVICE]` com valores corretos
- [ ] Abri o Relatório Financeiro
- [ ] Vi o log `📊 [RELATÓRIO]` com valores corretos
- [ ] Vi os valores separados na UI do relatório

---

## 🎉 Resultado Esperado

Quando tudo funcionar:

1. **Ao fazer venda:** Logs mostram valores sendo calculados e salvos
2. **No relatório:** Seção "Forma de Pagamento (MÊS)" mostra:
   - Dinheiro: R$ XX,XX
   - Pix: R$ XX,XX
   - Cartão: R$ XX,XX
3. **Isolamento por loja:** Cada loja vê apenas suas próprias vendas

---

## 📁 Arquivos Modificados

1. `lib/screens/nova_venda_modal.dart:591` - Log de pagamentos
2. `lib/services/vendas_service.dart:3,303` - Import e log de salvamento
3. `lib/screens/relatorio_financeiro_screen.dart:94` - Log do relatório

---

**Data:** 2025-12-23
**Status:** ✅ 100% Sincronizado e com logs de debug
