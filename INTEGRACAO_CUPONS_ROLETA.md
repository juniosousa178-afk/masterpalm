# 🎰 Sistema de Cupons da Roleta - Guia de Integração

## 📋 Visão Geral

Este sistema permite que clientes girem a roleta no catálogo web e ganhem cupons de desconto que podem ser usados na **PRÓXIMA compra**, com validade de **60 dias** e **uso único**.

---

## ✅ O que foi implementado

### 1. Modelo de Cupom (`lib/models/cupom_premio.dart`)

**Campos principais:**
- `codigo` - Código único (ex: "PREMIO-1234")
- `tipo` - Tipo de desconto: 'percentual', 'valor' ou 'frete_gratis'
- `valorDesconto` - Valor do desconto (% ou R$)
- `dataExpiracao` - Válido por 60 dias
- `usado` - Flag de uso único
- `dataUso` - Quando foi usado
- `vendaId` - ID da venda onde foi usado

**Métodos importantes:**
```dart
bool get isValido {
  if (usado) return false;
  if (DateTime.now().isAfter(dataExpiracao)) return false;
  return true;
}

Future<void> marcarComoUsado(String vendaId) async {
  usado = true;
  dataUso = DateTime.now();
  this.vendaId = vendaId;
  await save();
}

double calcularDesconto(double valorCompra) {
  if (!isValido) return 0.0;

  if (tipo == 'percentual') {
    return valorCompra * (valorDesconto / 100);
  } else if (tipo == 'valor') {
    return valorDesconto.clamp(0.0, valorCompra);
  } else if (tipo == 'frete_gratis') {
    return 0.0; // Desconto aplicado no frete
  }

  return 0.0;
}

static String gerarCodigo() {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final random = (timestamp % 10000).toString().padLeft(4, '0');
  return 'PREMIO-$random';
}
```

### 2. Widget da Roleta (`lib/widgets/roleta_web_widget.dart`)

**Características:**
- Baseado no estilo do `roleta_sorte_screen.dart`
- Usa `CustomPainter` para desenhar a roleta
- AnimationController com 4 segundos de animação
- Gera cupom após girar
- Salva no Hive e Firestore
- Modal bonito mostrando o cupom ganho

**Uso:**
```dart
RoletaWebWidget(
  lojaId: widget.lojaId,
  campanhaId: widget.campanhaId,
  clienteEmail: emailDoCliente, // Opcional
  onCupomGerado: (cupom) {
    // Callback quando cupom for gerado
    debugPrint('Cupom gerado: ${cupom.codigo}');
  },
)
```

### 3. Registro no Hive

Os adapters já foram registrados no `main.dart`:
```dart
if (!Hive.isAdapterRegistered(14)) Hive.registerAdapter(CupomPremioAdapter());
```

---

## 🔧 Integração no Catálogo Público

### Passo 1: Adicionar a Roleta no Catálogo

No arquivo `lib/screens/public_catalog_screen.dart`, adicione a roleta no carrinho/checkout:

```dart
import '../widgets/roleta_web_widget.dart';

// Dentro do modal do carrinho ou na tela de checkout:
Column(
  children: [
    // ... itens do carrinho ...

    // ✨ ROLETA
    if (_podeGirarRoleta()) // Verifica se tem campanha ativa
      RoletaWebWidget(
        lojaId: widget.lojaId,
        campanhaId: _campanhaAtivaId,
        clienteEmail: _clienteEmail,
        onCupomGerado: (cupom) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 Cupom ${cupom.codigo} gerado!'),
              backgroundColor: Colors.green,
            ),
          );
        },
      ),

    // ... botão de finalizar compra ...
  ],
)
```

### Passo 2: Verificar Campanha Ativa

```dart
String? _campanhaAtivaId;

Future<void> _verificarCampanhaAtiva() async {
  final snapshot = await FirebaseFirestore.instance
    .collection('lojas')
    .doc(widget.lojaId)
    .collection('campanhas_sorteio')
    .where('ativa', isEqualTo: true)
    .where('dataFim', isGreaterThanOrEqualTo: Timestamp.now())
    .limit(1)
    .get();

  if (snapshot.docs.isNotEmpty) {
    setState(() {
      _campanhaAtivaId = snapshot.docs.first.id;
    });
  }
}

bool _podeGirarRoleta() {
  return _campanhaAtivaId != null;
}
```

---

## 💳 Integração no Checkout

### Passo 1: Criar Serviço de Validação de Cupons

Crie `lib/services/cupom_service.dart`:

```dart
import 'package:hive/hive.dart';
import '../models/cupom_premio.dart';

class CupomService {
  /// Busca cupom por código
  static Future<CupomPremio?> buscarCupom(String codigo, String lojaId) async {
    final box = await Hive.openBox<CupomPremio>('cupons_premio');

    for (var cupom in box.values) {
      if (cupom.codigo.toUpperCase() == codigo.toUpperCase() &&
          cupom.lojaId == lojaId) {
        return cupom;
      }
    }

    return null;
  }

  /// Valida cupom
  static Future<Map<String, dynamic>> validarCupom(
    String codigo,
    String lojaId,
    double valorCompra,
  ) async {
    final cupom = await buscarCupom(codigo, lojaId);

    if (cupom == null) {
      return {
        'valido': false,
        'mensagem': 'Cupom não encontrado',
      };
    }

    if (!cupom.isValido) {
      if (cupom.usado) {
        return {
          'valido': false,
          'mensagem': 'Cupom já foi utilizado',
        };
      } else if (cupom.expirou) {
        return {
          'valido': false,
          'mensagem': 'Cupom expirado',
        };
      }
    }

    final desconto = cupom.calcularDesconto(valorCompra);

    return {
      'valido': true,
      'cupom': cupom,
      'desconto': desconto,
      'mensagem': cupom.tipo == 'frete_gratis'
        ? 'Frete grátis!'
        : 'Desconto de R\$ ${desconto.toStringAsFixed(2)}',
    };
  }

  /// Aplica cupom na venda
  static Future<void> aplicarCupom(
    CupomPremio cupom,
    String vendaId,
  ) async {
    await cupom.marcarComoUsado(vendaId);
  }

  /// Lista cupons válidos do cliente
  static Future<List<CupomPremio>> listarCuponsValidos({
    String? lojaId,
    String? clienteEmail,
  }) async {
    final box = await Hive.openBox<CupomPremio>('cupons_premio');

    return box.values.where((cupom) {
      if (!cupom.isValido) return false;
      if (lojaId != null && cupom.lojaId != lojaId) return false;
      if (clienteEmail != null && cupom.clienteEmail != clienteEmail) return false;
      return true;
    }).toList();
  }
}
```

### Passo 2: Adicionar Campo de Cupom no Checkout

No arquivo de checkout/finalização de compra:

```dart
import '../services/cupom_service.dart';
import '../models/cupom_premio.dart';

class CheckoutScreen extends StatefulWidget {
  // ...
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _cupomController = TextEditingController();
  CupomPremio? _cupomAplicado;
  double _descontoCupom = 0.0;
  String? _mensagemCupom;
  bool _validandoCupom = false;

  double get _subtotal => _calcularSubtotal();
  double get _total => (_subtotal - _descontoCupom).clamp(0.0, double.infinity);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Finalizar Compra')),
      body: Column(
        children: [
          // ... itens do carrinho ...

          // ✨ CAMPO DE CUPOM
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cupom de Desconto',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _cupomController,
                        decoration: InputDecoration(
                          hintText: 'Digite o código do cupom',
                          prefixIcon: Icon(Icons.card_giftcard),
                          border: OutlineInputBorder(),
                          enabled: _cupomAplicado == null,
                        ),
                        textCapitalization: TextCapitalization.characters,
                        onSubmitted: (_) => _validarCupom(),
                      ),
                    ),
                    SizedBox(width: 8),
                    if (_cupomAplicado == null)
                      ElevatedButton(
                        onPressed: _validandoCupom ? null : _validarCupom,
                        child: _validandoCupom
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text('Aplicar'),
                      )
                    else
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.red),
                        onPressed: _removerCupom,
                        tooltip: 'Remover cupom',
                      ),
                  ],
                ),
                if (_mensagemCupom != null) ...[
                  SizedBox(height: 8),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _cupomAplicado != null
                        ? Colors.green.shade50
                        : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _cupomAplicado != null
                          ? Colors.green
                          : Colors.red,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _cupomAplicado != null
                            ? Icons.check_circle
                            : Icons.error,
                          color: _cupomAplicado != null
                            ? Colors.green
                            : Colors.red,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _mensagemCupom!,
                            style: TextStyle(
                              color: _cupomAplicado != null
                                ? Colors.green.shade900
                                : Colors.red.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // RESUMO DO PEDIDO
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                _buildLinhaResumo('Subtotal', _subtotal),
                if (_descontoCupom > 0)
                  _buildLinhaResumo(
                    'Desconto (${_cupomAplicado!.codigo})',
                    -_descontoCupom,
                    cor: Colors.green,
                  ),
                Divider(),
                _buildLinhaResumo(
                  'Total',
                  _total,
                  bold: true,
                  fontSize: 20,
                ),
              ],
            ),
          ),

          // Botão finalizar
          Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _finalizarCompra,
                child: Text('Finalizar Compra'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinhaResumo(String label, double valor, {
    Color? cor,
    bool bold = false,
    double fontSize = 16,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            'R\$ ${valor.abs().toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _validarCupom() async {
    final codigo = _cupomController.text.trim();
    if (codigo.isEmpty) return;

    setState(() {
      _validandoCupom = true;
      _mensagemCupom = null;
    });

    try {
      final resultado = await CupomService.validarCupom(
        codigo,
        widget.lojaId,
        _subtotal,
      );

      setState(() {
        _validandoCupom = false;
        _mensagemCupom = resultado['mensagem'];

        if (resultado['valido']) {
          _cupomAplicado = resultado['cupom'];
          _descontoCupom = resultado['desconto'];
        } else {
          _cupomAplicado = null;
          _descontoCupom = 0.0;
        }
      });
    } catch (e) {
      setState(() {
        _validandoCupom = false;
        _mensagemCupom = 'Erro ao validar cupom';
      });
    }
  }

  void _removerCupom() {
    setState(() {
      _cupomAplicado = null;
      _descontoCupom = 0.0;
      _mensagemCupom = null;
      _cupomController.clear();
    });
  }

  Future<void> _finalizarCompra() async {
    // ... criar venda ...

    final vendaId = 'venda_${DateTime.now().millisecondsSinceEpoch}';

    // Se tem cupom aplicado, marca como usado
    if (_cupomAplicado != null) {
      await CupomService.aplicarCupom(_cupomAplicado!, vendaId);
    }

    // ... salvar venda no Firestore ...

    // Navegar para tela de sucesso
  }
}
```

---

## 📊 Estrutura no Firestore

### Cupons
```
/lojas/{lojaId}/cupons_premio/{cupomId}
{
  "codigo": "PREMIO-1234",
  "tipo": "percentual",
  "valorDesconto": 10.0,
  "dataExpiracao": Timestamp,
  "usado": false,
  "dataUso": null,
  "vendaId": null,
  "premioOriginal": "10% de desconto",
  "lojaId": "loja_uid_xxx",
  "clienteEmail": "cliente@email.com",
  "dataCriacao": Timestamp
}
```

---

## 🎨 Exemplo de Modal de Cupom Ganho

O `RoletaWebWidget` já mostra um modal bonito quando o cupom é gerado:

```dart
void _mostrarCupom(CupomPremio cupom) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        padding: EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.purple.shade700, Colors.deepPurple.shade900],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events, color: Colors.amber, size: 64),
            SizedBox(height: 16),
            Text(
              'PARABÉNS!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            // ... resto do conteúdo ...
          ],
        ),
      ),
    ),
  );
}
```

---

## ✅ Checklist de Integração

- [x] Modelo CupomPremio criado
- [x] Adapter Hive gerado e registrado
- [x] Widget RoletaWebWidget criado
- [ ] Adicionar RoletaWebWidget no catálogo público
- [ ] Criar CupomService
- [ ] Adicionar campo de cupom no checkout
- [ ] Testar validação de cupom
- [ ] Testar uso único
- [ ] Testar expiração de 60 dias
- [ ] Testar aplicação de desconto

---

## 🆘 Troubleshooting

### Cupom não aparece após girar roleta
- Verifique os logs do Flutter
- Confirme que o Hive box 'cupons_premio' está aberto
- Verifique permissões no Firestore

### Cupom não valida
- Confirme que o código está correto (case-insensitive)
- Verifique se não expirou (60 dias)
- Confirme que não foi usado anteriormente

### Desconto não aplica
- Verifique o método `calcularDesconto()`
- Confirme o tipo do cupom ('percentual', 'valor', 'frete_gratis')
- Verifique se o valor do desconto está correto

---

**Data de criação:** 21/12/2025
**Versão:** 1.0
**Desenvolvido com:** Flutter + Firebase + Hive
