# Mudanças Implementadas no MasterPalm

## ✅ 1. AUTO-SINCRONIZAÇÃO ESTOQUE → CATÁLOGO (COMPLETO)

### Implementado:
- **Campos de Promoção no Produto** (`lib/models/produto.dart`)
  - `emPromocao` (bool)
  - `percentualPromo` (double?)
  - `valorPromo` (double?)
  - `dataInicioPromo` (DateTime?)
  - `dataFimPromo` (DateTime?)
  - Getters: `precoComPromocao` e `promocaoAtiva`

- **Serviço de Auto-Sync** (`lib/services/produto_auto_sync_service.dart`)
  - Monitora mudanças no box Hive de produtos
  - Sincroniza automaticamente quando:
    - Produto é criado/editado
    - Produto é deletado
    - Produto é desmarcado do catálogo
    - Estoque é alterado
  - Debounce de 2 segundos para evitar sync excessivo
  - Remove produtos sem estoque automaticamente

- **Métodos Auxiliares no CatalogoSyncService**
  - `removeProdutoFromFirestore()` - Remove produto específico
  - `removeProdutoByKey()` - Remove quando não temos mais o objeto

- **Inicialização Automática**
  - Auto-sync inicia no bootstrap do app (`main.dart`)
  - Log: `✅ [BOOT] Auto-sincronização de produtos iniciada`

### Como Usar:
```dart
// Já está funcionando automaticamente!
// Qualquer alteração no produto dispara sync:
produto.quantidade = 0;
produto.save(); // → Auto-sync remove do catálogo

produto.publicadoNoCatalogo = false;
produto.save(); // → Auto-sync remove do catálogo live

produto.nome = "Novo Nome";
produto.save(); // → Auto-sync atualiza no Firestore
```

---

## 🔄 2. SUB-CATEGORIAS NO CATÁLOGO (EM ANDAMENTO)

### Implementado Parcialmente:
- **Modelo Subcategoria** (`lib/models/subcategoria.dart`)
  - HiveType com campos: nome, categoriaId, icone, ativa, dataCriacao
  - Métodos toMap() e fromMap()

- **Sync de Subcategorias no Catálogo**
  - CatalogoSyncService atualizado para incluir subcategoria
  - Campos adicionados: `subcategoria`, `subcategoriaId`

### Pendente:
- [ ] Registrar HiveAdapter para Subcategoria
- [ ] Criar UI de gerenciamento de subcategorias
- [ ] Adicionar filtros no public_catalog_screen.dart
- [ ] Implementar dropdown de subcategorias no formulário de produto
- [ ] Sincronizar subcategorias com Firestore

---

## ⏳ 3. MIGRAR DADOS PARA FIRESTORE (PENDENTE)

### O que precisa ser feito:

#### Vendas (Sales):
```dart
// Criar: lib/services/vendas_firestore_service.dart
- syncVenda(Venda venda) → Salva em lojas/{lojaId}/vendas/{vendaId}
- Auto-sync após cada venda registrada
- Manter compatibilidade com Hive local
```

#### Clientes (Customers):
```dart
// Criar: lib/services/clientes_firestore_service.dart
- syncCliente(Cliente cliente) → Salva em lojas/{lojaId}/clientes/{clienteId}
- Auto-sync após criação/atualização
- Vincular com vendas no Firestore
```

#### Fornecedores (Suppliers):
```dart
// Criar: lib/services/fornecedores_firestore_service.dart
- syncFornecedor(Fornecedor f) → Salva em lojas/{lojaId}/fornecedores/{id}
- Auto-sync após criação/atualização
```

#### Estrutura Firestore Recomendada:
```
lojas/{lojaId}/
  ├── vendas/
  │   └── {vendaId}
  │       - cliente, itens, total, data, status, pagamento
  ├── clientes/
  │   └── {clienteId}
  │       - nome, telefone, email, endereco, historico
  ├── fornecedores/
  │   └── {fornecedorId}
  │       - nome, telefone, email, produtos
  └── produtos/ (já existe)
```

---

## 🚚 4. FRETES FUNCIONAIS NO CARRINHO (PENDENTE)

### Já Existe (mas não integrado):
- `lib/services/frete_service.dart` - Implementado
- Providers: Correios, Melhor Envio, Frenet, Manual
- Configuração em: `lojas/{lojaId}/config/fretes`

### Precisa Integrar:
```dart
// Em: lib/screens/public_catalog_screen.dart
// Método: _openCartSheet()

1. Adicionar campo de CEP no modal do carrinho
2. Chamar FreteService.calcularOpcoesFrete() ao digitar CEP
3. Exibir opções de frete com preços
4. Adicionar frete selecionado ao total
5. Enviar frete escolhido no checkout (WhatsApp/MP)
```

### Exemplo de Integração:
```dart
List<OpcaoFrete> _opcoesFreteCalculadas = [];
String _cepDestino = '';

Future<void> _calcularFrete() async {
  if (_cepDestino.length != 8) return;

  final opcoes = await FreteService.calcularOpcoesFrete(
    lojaId: widget.lojaId,
    cepDestino: _cepDestino,
    itens: _cart.map((item) => FreteItem(
      pesoGramas: item['peso'] ?? 500,
      alturaCm: 10, larguraCm: 10, comprimentoCm: 10,
      quantidade: item['qty'],
    )).toList(),
    valorProdutos: _cartTotal,
  );

  setState(() => _opcoesFreteCalculadas = opcoes);
}
```

---

## 🎟️ 5. CUPONS FUNCIONAIS NO CARRINHO (PENDENTE)

### Já Existe:
- Cupons salvos em Hive: `config.get('cupons')`
- UI de gerenciamento: `FretesCuponsScreen`
- Estrutura de cupom:
  ```dart
  {
    'codigo': 'MASTER10',
    'tipo': 'percentual|valor',
    'valor': 10.0,
    'aplicarEm': 'produtos|total',
    'freteGratis': false
  }
  ```

### Precisa Implementar:
```dart
// Em: lib/screens/public_catalog_screen.dart
// Método: _openCartSheet()

1. Campo de input para código do cupom
2. Botão "Aplicar Cupom"
3. Validar se cupom existe na lista
4. Aplicar desconto conforme tipo (% ou R$)
5. Aplicar em produtos ou total conforme config
6. Se freteGratis=true, zerar valor do frete
7. Exibir desconto aplicado na tela
```

### Exemplo de Validação:
```dart
String? _cupomAplicado;
double _descontoCupom = 0.0;

void _aplicarCupom(String codigo) {
  final cupom = cupons.firstWhere(
    (c) => c['codigo'].toString().toUpperCase() == codigo.toUpperCase(),
    orElse: () => null,
  );

  if (cupom == null) {
    // Mostrar erro: Cupom inválido
    return;
  }

  final tipo = cupom['tipo'];
  final valor = cupom['valor'];
  final aplicarEm = cupom['aplicarEm'];

  if (tipo == 'percentual') {
    if (aplicarEm == 'produtos') {
      _descontoCupom = _cartTotal * (valor / 100);
    } else { // total
      _descontoCupom = (_cartTotal + _freteValor) * (valor / 100);
    }
  } else { // valor fixo
    _descontoCupom = valor;
  }

  if (cupom['freteGratis'] == true) {
    _freteValor = 0.0;
  }

  setState(() => _cupomAplicado = codigo);
}
```

---

## 🎰 6. ROLETA DE PROMOÇÕES NO CATÁLOGO (PENDENTE)

### Já Existe em Vendas:
- `lib/screens/nova_venda_modal.dart` - Roleta implementada
- Configuração: `lojas/{lojaId}/campanhas_sorteio_config/roleta`
- Prêmios: 5% OFF, 10% OFF, R$ 20 OFF, Frete Grátis, Brinde, Nenhum

### Precisa Criar:
```dart
// lib/widgets/roleta_catalog_widget.dart

1. Widget de roleta para o catálogo público
2. Disparar quando valor do carrinho >= valorMinimoRoleta
3. Animar roleta com flutter_fortune_wheel
4. Aplicar prêmio automaticamente ao carrinho
5. Salvar resultado em Firestore para tracking
```

### Integração no Catálogo:
```dart
// Em public_catalog_screen.dart
// No método _openCartSheet()

if (_cartTotal >= valorMinimoRoleta && !_roletaGirada) {
  // Mostrar roleta
  final premio = await showDialog(
    context: context,
    builder: (_) => RoletaCatalogWidget(),
  );

  if (premio != null) {
    _aplicarPremioRoleta(premio);
    setState(() => _roletaGirada = true);
  }
}
```

---

## 📢 7. CAMPANHAS PROMOCIONAIS (PENDENTE)

### Já Existe:
- Modelo: `CampanhaSorteio` e `TicketSorteio`
- Firestore: `lojas/{lojaId}/campanhas_sorteio/`
- Service: `lib/services/campanhas_sorteio_service.dart`

### Precisa Integrar no Catálogo:
```dart
1. Exibir campanhas ativas no catálogo
2. Gerar tickets automaticamente após compra >= valorMinimo
3. Mostrar números sorteados ao cliente
4. Listar participações do cliente
5. Notificar ganhadores
```

---

## ✅ 8. CAMPO DE PROMOÇÃO EM PRODUTOS (COMPLETO)

### Implementado:
- Campos no modelo Produto (veja item 1)
- Sync automático para Firestore com promoções
- Cálculo automático de `precoComPromocao`
- Validação de período (dataInicio/dataFim)

### Precisa:
- [ ] UI no formulário de produto para configurar promoção
- [ ] Toggle "Em Promoção"
- [ ] Campos de % ou R$ (mutuamente exclusivos)
- [ ] Date pickers para início/fim
- [ ] Badge de "PROMOÇÃO" no catálogo

---

## 🔧 PRÓXIMOS PASSOS RECOMENDADOS

### PRIORIDADE ALTA:
1. **Finalizar Sub-categorias**
   - Registrar adapter Hive
   - Criar UI de gerenciamento
   - Adicionar filtros no catálogo

2. **Integrar Fretes no Carrinho**
   - Campo CEP
   - Cálculo automático
   - Seleção de opção

3. **Integrar Cupons no Carrinho**
   - Input de código
   - Validação
   - Aplicação de desconto

### PRIORIDADE MÉDIA:
4. **UI de Promoção em Produtos**
   - Formulário de configuração
   - Badges visuais no catálogo

5. **Migrar Dados para Firestore**
   - Vendas
   - Clientes
   - Fornecedores

### PRIORIDADE BAIXA:
6. **Roleta no Catálogo**
7. **Campanhas no Catálogo**

---

## 📝 NOTAS TÉCNICAS

### Build Runner:
Após adicionar novos campos ao Produto, executar:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Firestore Security Rules:
Verificar se as rules permitem:
```javascript
match /lojas/{lojaId}/vendas/{vendaId} {
  allow write: if request.auth != null;
  allow read: if true; // ou adicionar lógica específica
}
```

### Performance:
- Auto-sync usa debounce de 2s
- Queries do catálogo com limite de docs
- Imagens devem ser otimizadas (webp, compressão)

---

Criado em: 2025-12-21
Versão do App: MasterPalm v1.0
