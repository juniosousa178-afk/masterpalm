# 🎡 Guia de Integração: Roleta e Campanhas no Catálogo

## ✅ Widgets Criados

### 1. `RoletaCatalogWidget` - Widget da Roleta
**Arquivo:** `lib/widgets/roleta_catalog_widget.dart`

**Funcionalidades:**
- ✨ Roleta animada com `flutter_fortune_wheel`
- 🎯 Verifica elegibilidade (valor mínimo de compra)
- 🎁 Sorteia prêmios aleatoriamente
- 💾 Registra participação no Firestore
- 🏆 Exibe modal com prêmio ganho
- ⚠️ Mostra quanto falta para atingir o valor mínimo

### 2. `CampanhaBannerWidget` - Banner de Campanhas
**Arquivo:** `lib/widgets/campanha_banner_widget.dart`

**Funcionalidades:**
- 📢 Exibe campanhas ativas em carrossel
- ⏰ Auto-scroll a cada 5 segundos
- 🎨 Design com gradiente e estrelas
- ⏳ Mostra dias restantes
- 💰 Exibe valor mínimo
- 📊 Indicadores de página

---

## 🔧 Como Integrar no Catálogo Público

### Passo 1: Adicionar imports

No arquivo `lib/screens/public_catalog_screen.dart`, adicione:

```dart
import '../widgets/roleta_catalog_widget.dart';
import '../widgets/campanha_banner_widget.dart';
```

### Passo 2: Adicionar banner de campanhas no topo

Encontre onde o catálogo renderiza a lista de produtos e adicione o banner **ANTES** da grade de produtos:

```dart
// Dentro do StreamBuilder que carrega os produtos
StreamBuilder<QuerySnapshot>(
  stream: // seu stream de produtos,
  builder: (context, snapshot) {
    if (!snapshot.hasData) return CircularProgressIndicator();

    // ... seu código de processamento de produtos ...

    return Column(
      children: [
        // ✨ ADICIONE AQUI: Banner de campanhas
        CampanhaBannerWidget(lojaId: widget.lojaId),

        // Sua grade de produtos existente
        GridView.builder(
          // ...
        ),
      ],
    );
  },
)
```

### Passo 3: Adicionar roleta antes do checkout

Adicione a roleta **APÓS** o usuário adicionar produtos ao carrinho, antes de finalizar a compra:

**Opção A: Na tela de carrinho/checkout**

```dart
Column(
  children: [
    // Lista de itens do carrinho
    ListView.builder(
      itemCount: cart.length,
      itemBuilder: (context, index) {
        // seus itens do carrinho
      },
    ),

    // ✨ ADICIONE AQUI: Widget da roleta
    RoletaCatalogWidget(
      lojaId: widget.lojaId,
      totalCarrinho: _calcularTotalCarrinho(),
      onPremioGanho: () {
        // Opcional: fazer algo quando ganhar prêmio
        debugPrint('Prêmio ganho!');
      },
    ),

    // Botão de finalizar compra
    ElevatedButton(
      onPressed: _finalizarCompra,
      child: Text('Finalizar Compra'),
    ),
  ],
)
```

**Opção B: Como um modal após adicionar ao carrinho**

```dart
void _mostrarRoleta(BuildContext context, double totalCarrinho) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.emoji_events, color: Colors.amber, size: 32),
                SizedBox(width: 12),
                Text(
                  'Gire a Roleta!',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Spacer(),
                IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Roleta
          Expanded(
            child: RoletaCatalogWidget(
              lojaId: widget.lojaId,
              totalCarrinho: totalCarrinho,
              onPremioGanho: () {
                Navigator.pop(context);
                // Mostrar mensagem de sucesso
              },
            ),
          ),
        ],
      ),
    ),
  );
}

// Chamada ao adicionar produto ao carrinho:
void _adicionarAoCarrinho(produto) {
  setState(() {
    _carrinho.add(produto);
  });

  // Mostra roleta se tiver campanha ativa
  Future.delayed(Duration(milliseconds: 500), () {
    _mostrarRoleta(context, _calcularTotalCarrinho());
  });
}
```

---

## 🎯 Integração Completa - Exemplo Prático

### Exemplo: Catálogo com Banner + Roleta no Carrinho

```dart
class PublicCatalogScreen extends StatefulWidget {
  final String lojaId;
  final bool preview;

  const PublicCatalogScreen({
    Key? key,
    required this.lojaId,
    this.preview = false,
  }) : super(key: key);

  @override
  State<PublicCatalogScreen> createState() => _PublicCatalogScreenState();
}

class _PublicCatalogScreenState extends State<PublicCatalogScreen> {
  List<Map<String, dynamic>> _carrinho = [];

  double _calcularTotalCarrinho() {
    return _carrinho.fold(0.0, (sum, item) {
      final preco = (item['preco'] as num?)?.toDouble() ?? 0.0;
      final qty = (item['qty'] as int?) ?? 1;
      return sum + (preco * qty);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Catálogo'),
        actions: [
          // Botão do carrinho
          IconButton(
            icon: Badge(
              label: Text('${_carrinho.length}'),
              child: Icon(Icons.shopping_cart),
            ),
            onPressed: () => _abrirCarrinho(),
          ),
        ],
      ),
      body: Column(
        children: [
          // ✨ Banner de campanhas
          CampanhaBannerWidget(lojaId: widget.lojaId),

          // Grade de produtos
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('lojas')
                  .doc(widget.lojaId)
                  .collection('produtos')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator());
                }

                final produtos = snapshot.data!.docs;

                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.7,
                  ),
                  itemCount: produtos.length,
                  itemBuilder: (context, index) {
                    final produto = produtos[index].data() as Map<String, dynamic>;

                    return Card(
                      child: Column(
                        children: [
                          // Imagem do produto
                          Expanded(
                            child: Image.network(
                              produto['imageUrl'] ?? '',
                              fit: BoxFit.cover,
                            ),
                          ),

                          // Nome e preço
                          Padding(
                            padding: EdgeInsets.all(8),
                            child: Column(
                              children: [
                                Text(
                                  produto['nome'] ?? '',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                Text('R\$ ${produto['preco']}'),

                                // Botão adicionar
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() => _carrinho.add(produto));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Adicionado ao carrinho!')),
                                    );
                                  },
                                  child: Text('Adicionar'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _abrirCarrinho() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            // Título
            Text(
              'Meu Carrinho',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Divider(),

            // Itens do carrinho
            Expanded(
              child: ListView.builder(
                itemCount: _carrinho.length,
                itemBuilder: (context, index) {
                  final item = _carrinho[index];
                  return ListTile(
                    title: Text(item['nome'] ?? ''),
                    subtitle: Text('R\$ ${item['preco']}'),
                    trailing: IconButton(
                      icon: Icon(Icons.delete),
                      onPressed: () {
                        setState(() => _carrinho.removeAt(index));
                      },
                    ),
                  );
                },
              ),
            ),

            // Total
            Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total:',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'R\$ ${_calcularTotalCarrinho().toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            // ✨ Roleta
            RoletaCatalogWidget(
              lojaId: widget.lojaId,
              totalCarrinho: _calcularTotalCarrinho(),
              onPremioGanho: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('🎉 Parabéns pelo prêmio!'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),

            SizedBox(height: 16),

            // Botão finalizar
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  // Finalizar compra
                  Navigator.pop(context);
                  // Ir para checkout
                },
                child: Text('Finalizar Compra'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## 📊 Estrutura de Dados no Firestore

### Campanha de Sorteio

```
/lojas/{lojaId}/campanhas_sorteio/{campanhaId}
{
  "nome": "Super Sorteio de Natal",
  "descricao": "Concorra a prêmios incríveis!",
  "ativa": true,
  "valorMinimo": 50.0,
  "premios": [
    "10% de desconto",
    "Frete grátis",
    "Brinde surpresa",
    "Vale R$ 20",
    "Cupom R$ 50"
  ],
  "dataInicio": Timestamp,
  "dataFim": Timestamp,
  "createdAt": Timestamp
}
```

### Participante da Campanha

```
/lojas/{lojaId}/campanhas_sorteio/{campanhaId}/participantes/{participanteId}
{
  "premio": "10% de desconto",
  "valorCompra": 75.50,
  "dataParticipacao": Timestamp,
  "clienteEmail": "cliente@email.com",  // opcional
  "clienteNome": "João Silva"           // opcional
}
```

---

## 🎨 Customização

### Alterar cores da roleta

Em `roleta_catalog_widget.dart`, modifique:

```dart
FortuneItemStyle(
  color: Colors.primaries[index % Colors.primaries.length],
  // Mudar para cores específicas:
  // color: [Colors.red, Colors.blue, Colors.green][index],
  borderColor: Colors.white,
  borderWidth: 2,
),
```

### Alterar duração da animação

```dart
await Future.delayed(const Duration(seconds: 3));
// Mudar para 5 segundos:
// await Future.delayed(const Duration(seconds: 5));
```

### Alterar gradiente do banner

Em `campanha_banner_widget.dart`:

```dart
gradient: LinearGradient(
  colors: [
    Colors.deepPurple.shade600,
    Colors.purple.shade400,
    Colors.pink.shade400,
  ],
  // Mudar para outras cores:
  // colors: [Colors.blue, Colors.cyan, Colors.teal],
),
```

---

## ✅ Checklist de Integração

- [ ] Importar os widgets no `public_catalog_screen.dart`
- [ ] Adicionar `CampanhaBannerWidget` no topo do catálogo
- [ ] Adicionar `RoletaCatalogWidget` no carrinho/checkout
- [ ] Testar com uma campanha ativa no Firestore
- [ ] Verificar cálculo do total do carrinho
- [ ] Testar sorteio e registro de participação
- [ ] Customizar cores e textos conforme identidade visual

---

## 🆘 Troubleshooting

### A roleta não aparece
- Verifique se existe uma campanha ativa no Firestore
- Confirme que `dataFim` é maior que a data atual
- Verifique o campo `ativa: true`

### Erro ao girar a roleta
- Confirme que o pacote `flutter_fortune_wheel` está instalado
- Verifique se o `lojaId` está correto
- Veja os logs do Firestore para erros de permissão

### Banner não faz auto-scroll
- Certifique-se que há mais de uma campanha ativa
- Verifique se o widget está montado (`mounted`)

---

**Pronto para usar!** 🎊

Agora seu catálogo tem um sistema completo de campanhas e sorteios para engajar os clientes!
