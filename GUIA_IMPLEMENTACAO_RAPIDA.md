# Guia de Implementação Rápida - MasterPalm

## STATUS ATUAL DAS IMPLEMENTAÇÕES

### ✅ COMPLETADO (Pronto para usar):
1. **Auto-sincronização Estoque → Catálogo**
   - Produtos sincronizam automaticamente ao serem alterados
   - Remoção automática quando deletados ou sem estoque
   - Iniciado automaticamente no app

2. **Campos de Promoção em Produtos**
   - Modelo atualizado com campos de promoção
   - Cálculo automático de preço com desconto
   - Sincronização com Firestore incluindo promoções

### 🔄 EM ANDAMENTO:
- Sub-categorias (modelo criado, falta UI e filtros)

### ⏳ PENDENTE (Código pronto nos próximos arquivos):
- Fretes funcionais no carrinho
- Cupons funcionais no carrinho
- Roleta no catálogo
- Campanhas no catálogo
- Migração de dados para Firestore

---

## COMO APLICAR AS MUDANÇAS

### Passo 1: Rebuild dos Adapters Hive
```bash
cd C:\Users\Pichau\apk_nathy\temp_naty
flutter pub run build_runner build --delete-conflicting-outputs
```

### Passo 2: Testar Auto-Sync
1. Execute o app: `flutter run`
2. Vá em Estoque
3. Edite um produto (mude nome ou preço)
4. Salve
5. Verifique os logs:
   ```
   📝 [AUTO-SYNC] Produto modificado: Nome do Produto
   🔄 [AUTO-SYNC] Executando sync de 1 produto(s)...
   ✅ [AUTO-SYNC] Sync concluído
   ```
6. Verifique no Firebase Console se o produto foi atualizado

### Passo 3: Testar Deleção Automática
1. Delete um produto no estoque
2. Verifique os logs:
   ```
   🗑️ [AUTO-SYNC] Produto deletado: key
   🗑️ [AUTO-SYNC] Removido do Firestore
   ```
3. Confirme que sumiu do Firebase

### Passo 4: Testar Promoções (quando adicionar UI)
```dart
// No formulário de produto:
produto.emPromocao = true;
produto.percentualPromo = 15.0; // 15% OFF
produto.dataInicioPromo = DateTime.now();
produto.dataFimPromo = DateTime.now().add(Duration(days: 7));
produto.save();

// Verificar:
print(produto.precoFinal); // Preço original
print(produto.precoComPromocao); // Preço com 15% desconto
print(produto.promocaoAtiva); // true
```

---

## TAREFAS QUE EXIGEM CÓDIGO ADICIONAL

### A. Adicionar UI de Promoção no Formulário de Produto

**Local:** `lib/screens/estoque/produto_form_screen.dart`

**Adicionar após os campos de preço:**

```dart
// Switch de promoção
SwitchListTile(
  title: Text('Produto em Promoção'),
  value: _emPromocao,
  onChanged: (val) => setState(() => _emPromocao = val),
),

if (_emPromocao) ...[
  SizedBox(height: 16),

  // Tipo de desconto
  SegmentedButton<String>(
    segments: [
      ButtonSegment(value: 'percentual', label: Text('% Desconto')),
      ButtonSegment(value: 'valor', label: Text('R\$ Desconto')),
    ],
    selected: {_tipoPromocao},
    onSelectionChanged: (Set<String> val) {
      setState(() => _tipoPromocao = val.first);
    },
  ),

  SizedBox(height: 16),

  // Campo de valor do desconto
  TextFormField(
    decoration: InputDecoration(
      labelText: _tipoPromocao == 'percentual'
          ? 'Desconto (%)'
          : 'Desconto (R\$)',
      prefixText: _tipoPromocao == 'percentual' ? '' : 'R\$ ',
      suffixText: _tipoPromocao == 'percentual' ? '%' : '',
    ),
    keyboardType: TextInputType.numberWithOptions(decimal: true),
    onSaved: (val) {
      final valor = double.tryParse(val ?? '0') ?? 0;
      if (_tipoPromocao == 'percentual') {
        _percentualPromo = valor;
        _valorPromo = null;
      } else {
        _valorPromo = valor;
        _percentualPromo = null;
      }
    },
  ),

  SizedBox(height: 16),

  // Data início
  ListTile(
    title: Text('Início da Promoção'),
    subtitle: Text(_dataInicioPromo != null
        ? DateFormat('dd/MM/yyyy').format(_dataInicioPromo!)
        : 'Não definido'),
    trailing: Icon(Icons.calendar_today),
    onTap: () async {
      final date = await showDatePicker(
        context: context,
        initialDate: _dataInicioPromo ?? DateTime.now(),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(Duration(days: 365)),
      );
      if (date != null) {
        setState(() => _dataInicioPromo = date);
      }
    },
  ),

  // Data fim
  ListTile(
    title: Text('Fim da Promoção'),
    subtitle: Text(_dataFimPromo != null
        ? DateFormat('dd/MM/yyyy').format(_dataFimPromo!)
        : 'Não definido'),
    trailing: Icon(Icons.calendar_today),
    onTap: () async {
      final date = await showDatePicker(
        context: context,
        initialDate: _dataFimPromo ?? DateTime.now().add(Duration(days: 7)),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(Duration(days: 365)),
      );
      if (date != null) {
        setState(() => _dataFimPromo = date);
      }
    },
  ),
],
```

**Declarar variáveis no topo da classe:**
```dart
bool _emPromocao = false;
String _tipoPromocao = 'percentual';
double? _percentualPromo;
double? _valorPromo;
DateTime? _dataInicioPromo;
DateTime? _dataFimPromo;
```

**No método de salvar:**
```dart
produto.emPromocao = _emPromocao;
produto.percentualPromo = _percentualPromo;
produto.valorPromo = _valorPromo;
produto.dataInicioPromo = _dataInicioPromo;
produto.dataFimPromo = _dataFimPromo;
```

---

### B. Badge de Promoção no Catálogo

**Local:** `lib/screens/public_catalog_screen.dart`

**No card do produto, adicionar:**

```dart
Stack(
  children: [
    // Card do produto existente
    Card(...),

    // Badge de promoção
    if (produto['promocaoAtiva'] == true)
      Positioned(
        top: 8,
        right: 8,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            produto['percentualPromo'] != null
                ? '-${produto['percentualPromo']}%'
                : 'PROMOÇÃO',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
  ],
)
```

**Mostrar preço riscado:**
```dart
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    if (produto['emPromocao'] == true)
      Text(
        'R\$ ${produto['preco'].toStringAsFixed(2)}',
        style: TextStyle(
          decoration: TextDecoration.lineThrough,
          color: Colors.grey,
          fontSize: 14,
        ),
      ),
    Text(
      'R\$ ${produto['precoComPromocao'].toStringAsFixed(2)}',
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: produto['emPromocao'] == true ? 20 : 18,
        color: produto['emPromocao'] == true ? Colors.red : null,
      ),
    ),
  ],
)
```

---

### C. Integração de Fretes no Carrinho

**Local:** `lib/screens/public_catalog_screen.dart`
**Método:** `_openCartSheet()`

**1. Adicionar variáveis de estado no topo da classe:**
```dart
final TextEditingController _cepController = TextEditingController();
List<Map<String, dynamic>> _opcoesFreteDisponiveis = [];
Map<String, dynamic>? _freteSelecionado;
bool _calculandoFrete = false;
```

**2. Adicionar campo de CEP no modal do carrinho:**
```dart
// Dentro do showModalBottomSheet
Column(
  children: [
    // Lista de produtos do carrinho...

    Divider(),

    // SEÇÃO DE FRETE
    Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Calcular Frete', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cepController,
                  decoration: InputDecoration(
                    labelText: 'CEP',
                    hintText: '00000-000',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 8,
                ),
              ),
              SizedBox(width: 8),
              ElevatedButton(
                onPressed: _calculandoFrete ? null : _calcularFreteCarrinho,
                child: _calculandoFrete
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Calcular'),
              ),
            ],
          ),

          // Opções de frete
          if (_opcoesFreteDisponiveis.isNotEmpty) ...[
            SizedBox(height: 16),
            Text('Escolha o frete:', style: TextStyle(fontWeight: FontWeight.bold)),
            ..._opcoesFreteDisponiveis.map((opcao) {
              final selecionado = _freteSelecionado == opcao;
              return RadioListTile<Map<String, dynamic>>(
                title: Text(opcao['nome']),
                subtitle: Text(
                  'R\$ ${opcao['valor'].toStringAsFixed(2)} - '
                  'Prazo: ${opcao['prazo']} dias',
                ),
                value: opcao,
                groupValue: _freteSelecionado,
                onChanged: (val) {
                  setState(() => _freteSelecionado = val);
                },
              );
            }).toList(),
          ],
        ],
      ),
    ),

    Divider(),

    // TOTAIS
    _buildTotaisCarrinho(),
  ],
)
```

**3. Implementar método de cálculo:**
```dart
Future<void> _calcularFreteCarrinho() async {
  final cep = _cepController.text.replaceAll(RegExp(r'[^0-9]'), '');

  if (cep.length != 8) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('CEP inválido')),
    );
    return;
  }

  setState(() {
    _calculandoFrete = true;
    _opcoesFreteDisponiveis = [];
    _freteSelecionado = null;
  });

  try {
    // Converter itens do carrinho para FreteItem
    final itens = _cart.map((item) {
      return FreteItem(
        pesoGramas: (item['peso'] as num?)?.toDouble() ?? 500.0,
        alturaCm: 10,
        larguraCm: 10,
        comprimentoCm: 10,
        quantidade: item['qty'] as int,
      );
    }).toList();

    final opcoes = await FreteService.calcularOpcoesFrete(
      lojaId: widget.lojaId,
      cepDestino: cep,
      itens: itens,
      valorProdutos: _cartTotal,
    );

    setState(() {
      _opcoesFreteDisponiveis = opcoes.map((o) => {
        'nome': o.nome,
        'valor': o.valor,
        'prazo': o.prazoEntrega,
        'id': o.id,
      }).toList();
      _calculandoFrete = false;
    });
  } catch (e) {
    setState(() => _calculandoFrete = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Erro ao calcular frete: $e')),
    );
  }
}
```

**4. Atualizar totais para incluir frete:**
```dart
Widget _buildTotaisCarrinho() {
  final valorFrete = _freteSelecionado?['valor'] ?? 0.0;
  final totalComFrete = _cartTotal + valorFrete;

  return Padding(
    padding: EdgeInsets.all(16),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Subtotal:'),
            Text('R\$ ${_cartTotal.toStringAsFixed(2)}'),
          ],
        ),
        if (_freteSelecionado != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Frete (${_freteSelecionado!['nome']}):'),
              Text('R\$ ${valorFrete.toStringAsFixed(2)}'),
            ],
          ),
        Divider(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('TOTAL:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text(
              'R\$ ${totalComFrete.toStringAsFixed(2)}',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green),
            ),
          ],
        ),
      ],
    ),
  );
}
```

---

### D. Integração de Cupons no Carrinho

**1. Adicionar variáveis de estado:**
```dart
final TextEditingController _cupomController = TextEditingController();
Map<String, dynamic>? _cupomAplicado;
double _descontoCupom = 0.0;
```

**2. Adicionar campo de cupom no modal:**
```dart
// Após a seção de frete
Divider(),

Padding(
  padding: EdgeInsets.all(16),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Cupom de Desconto', style: TextStyle(fontWeight: FontWeight.bold)),
      SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _cupomController,
              decoration: InputDecoration(
                labelText: 'Código do Cupom',
                hintText: 'EX: MASTER10',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
          ),
          SizedBox(width: 8),
          ElevatedButton(
            onPressed: _aplicarCupom,
            child: Text('Aplicar'),
          ),
        ],
      ),
      if (_cupomAplicado != null) ...[
        SizedBox(height: 8),
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cupom "${_cupomAplicado!['codigo']}" aplicado! '
                  'Desconto: R\$ ${_descontoCupom.toStringAsFixed(2)}',
                  style: TextStyle(color: Colors.green),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _cupomAplicado = null;
                    _descontoCupom = 0.0;
                    _cupomController.clear();
                  });
                },
              ),
            ],
          ),
        ),
      ],
    ],
  ),
),
```

**3. Implementar validação:**
```dart
void _aplicarCupom() {
  final codigo = _cupomController.text.trim().toUpperCase();

  if (codigo.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Digite um código de cupom')),
    );
    return;
  }

  // Buscar cupom na lista (passada via parâmetro ou carregada do config)
  final cupom = cupons.firstWhere(
    (c) => c['codigo'].toString().toUpperCase() == codigo && c['ativo'] == true,
    orElse: () => null,
  );

  if (cupom == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Cupom inválido ou expirado')),
    );
    return;
  }

  // Calcular desconto
  final tipo = cupom['tipo'];
  final valor = (cupom['valor'] as num).toDouble();
  final aplicarEm = cupom['aplicarEm'] ?? 'produtos';

  double desconto = 0.0;

  if (tipo == 'percentual') {
    if (aplicarEm == 'produtos') {
      desconto = _cartTotal * (valor / 100);
    } else { // total (produtos + frete)
      final valorFrete = _freteSelecionado?['valor'] ?? 0.0;
      desconto = (_cartTotal + valorFrete) * (valor / 100);
    }
  } else { // valor fixo
    desconto = valor;
  }

  // Aplicar frete grátis se configurado
  if (cupom['freteGratis'] == true) {
    _freteSelecionado = {
      'nome': 'Grátis (cupom)',
      'valor': 0.0,
      'prazo': 0,
      'id': 'free',
    };
  }

  setState(() {
    _cupomAplicado = cupom;
    _descontoCupom = desconto;
  });

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Cupom aplicado com sucesso!'), backgroundColor: Colors.green),
  );
}
```

**4. Atualizar cálculo de totais:**
```dart
Widget _buildTotaisCarrinho() {
  final valorFrete = _freteSelecionado?['valor'] ?? 0.0;
  final subtotal = _cartTotal;
  final desconto = _descontoCupom;
  final total = (subtotal + valorFrete - desconto).clamp(0.0, double.infinity);

  return Padding(
    padding: EdgeInsets.all(16),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Subtotal:'),
            Text('R\$ ${subtotal.toStringAsFixed(2)}'),
          ],
        ),
        if (_freteSelecionado != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Frete:'),
              Text('R\$ ${valorFrete.toStringAsFixed(2)}'),
            ],
          ),
        if (_descontoCupom > 0)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Desconto (cupom):', style: TextStyle(color: Colors.green)),
              Text(
                '- R\$ ${desconto.toStringAsFixed(2)}',
                style: TextStyle(color: Colors.green),
              ),
            ],
          ),
        Divider(height: 24, thickness: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('TOTAL:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            Text(
              'R\$ ${total.toStringAsFixed(2)}',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.green),
            ),
          ],
        ),
      ],
    ),
  );
}
```

---

## IMPORTS NECESSÁRIOS

Adicione estes imports no topo de `public_catalog_screen.dart`:

```dart
import '../services/frete_service.dart';
import '../models/frete_item.dart';
import 'package:intl/intl.dart';
```

---

## TESTAR AS IMPLEMENTAÇÕES

### Teste 1: Fretes
1. Adicione produtos ao carrinho
2. Clique no botão "Ver Carrinho"
3. Digite um CEP válido (ex: 01310100)
4. Clique em "Calcular"
5. Selecione uma opção de frete
6. Verifique se o total foi atualizado

### Teste 2: Cupons
1. Vá em Configurações → Fretes e Cupons
2. Crie um cupom de teste (ex: TESTE10, 10%, ativo)
3. No catálogo, adicione produtos ao carrinho
4. Digite o código "TESTE10"
5. Clique em "Aplicar"
6. Verifique o desconto aplicado

### Teste 3: Promoções
1. Edite um produto no estoque
2. Ative "Produto em Promoção"
3. Configure 20% de desconto
4. Defina data início = hoje, fim = daqui 7 dias
5. Salve
6. Abra o catálogo público
7. Verifique badge "PROMOÇÃO" e preço riscado

---

## PROBLEMAS COMUNS

### Erro: "FreteService not found"
**Solução:** Verifique se o import está correto e se o arquivo existe em `lib/services/frete_service.dart`

### Cupons não aparecem
**Solução:** Verifique se salvou cupons em Hive: `config.put('cupons', [...])`

### Auto-sync não funciona
**Solução:**
1. Verifique logs no console
2. Confirme que Firestore está configurado
3. Verifique permissões no Firebase

### Promoção não aparece
**Solução:**
1. Execute `flutter pub run build_runner build --delete-conflicting-outputs`
2. Restart do app
3. Verifique se `emPromocao = true`

---

## PRÓXIMAS MELHORIAS SUGERIDAS

1. **Histórico de Vendas em Tempo Real**
   - Dashboard com gráficos
   - Sincronizar vendas automaticamente

2. **Notificações Push**
   - Nova venda
   - Estoque baixo
   - Promoção expirando

3. **Relatórios Avançados**
   - Exportar Excel/PDF
   - Análise de produtos mais vendidos
   - ROI de campanhas

4. **Multi-idioma**
   - Suporte para EN/ES além de PT-BR

5. **App para Cliente**
   - App separado para clientes
   - Acompanhamento de pedidos
   - Programa de fidelidade

---

Criado em: 2025-12-21
Por: Claude (Anthropic)
