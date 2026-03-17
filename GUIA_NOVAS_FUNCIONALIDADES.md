# 📚 Guia Completo das Novas Funcionalidades

Este guia detalha todas as funcionalidades implementadas e como usá-las no app MasterPalm.

---

## 🎉 Funcionalidades Implementadas

### ✅ 1. Sistema de Promoções em Produtos

**Arquivo modificado:** `lib/screens/produto_form_screen.dart`
**Modelo atualizado:** `lib/models/produto.dart`

#### O que foi adicionado:

- **Card de Promoções** no formulário de produtos com:
  - Toggle para ativar/desativar promoção
  - Escolha entre dois tipos de desconto:
    - **Percentual (%)** - Ex: 10%, 20%, 50%
    - **Valor fixo (R$)** - Ex: R$ 10,00, R$ 25,00
  - **Período da promoção (opcional)**:
    - Data de início
    - Data de fim
    - Botão para limpar datas

#### Campos adicionados ao modelo Produto:

```dart
@HiveField(21, defaultValue: false)
bool emPromocao;

@HiveField(22)
double? percentualPromo;

@HiveField(23)
double? valorPromo;

@HiveField(24)
DateTime? dataInicioPromo;

@HiveField(25)
DateTime? dataFimPromo;
```

#### Getters para cálculo automático:

```dart
// Retorna o preço com desconto aplicado
double get precoComPromocao {
  if (!emPromocao) return precoFinal;

  final now = DateTime.now();
  if (dataInicioPromo != null && now.isBefore(dataInicioPromo!)) return precoFinal;
  if (dataFimPromo != null && now.isAfter(dataFimPromo!)) return precoFinal;

  if (percentualPromo != null && percentualPromo! > 0) {
    final desconto = precoFinal * (percentualPromo! / 100);
    return (precoFinal - desconto).clamp(0.0, double.infinity);
  }

  if (valorPromo != null && valorPromo! > 0) {
    return (precoFinal - valorPromo!).clamp(0.0, double.infinity);
  }

  return precoFinal;
}

// Verifica se a promoção está ativa no momento
bool get promocaoAtiva {
  if (!emPromocao) return false;

  final now = DateTime.now();
  if (dataInicioPromo != null && now.isBefore(dataInicioPromo!)) return false;
  if (dataFimPromo != null && now.isAfter(dataFimPromo!)) return false;

  return (percentualPromo != null && percentualPromo! > 0) ||
         (valorPromo != null && valorPromo! > 0);
}
```

#### Como usar:

1. Abra a tela de **Estoque**
2. Clique em um produto para editar (ou crie um novo)
3. Role até encontrar o card **"Promoção"** (aparece antes de "Publicar no catálogo")
4. Ative o switch "Promoção"
5. Escolha o tipo de desconto (Percentual ou Valor fixo)
6. Digite o valor do desconto
7. **(Opcional)** Defina o período da promoção clicando nos botões de data
8. Salve o produto

#### Exibindo produtos em promoção no catálogo:

Para exibir o preço promocional no catálogo, use:

```dart
final produto = // seu produto
final precoOriginal = produto.precoFinal;
final precoPromocional = produto.precoComPromocao;
final emPromocao = produto.promocaoAtiva;

// No widget:
if (emPromocao) {
  Column(
    children: [
      Text(
        'R\$ ${precoOriginal.toStringAsFixed(2)}',
        style: TextStyle(
          decoration: TextDecoration.lineThrough,
          color: Colors.grey,
        ),
      ),
      Text(
        'R\$ ${precoPromocional.toStringAsFixed(2)}',
        style: TextStyle(
          color: Colors.red,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  )
} else {
  Text('R\$ ${precoOriginal.toStringAsFixed(2)}')
}
```

---

### ✅ 2. Tela de Sincronização Firestore

**Arquivo criado:** `lib/screens/admin_sync_screen.dart`

#### O que foi implementado:

Tela administrativa completa para sincronizar dados locais (Hive) para o Firestore (nuvem).

#### Funcionalidades:

- **Botão "Sincronizar Tudo"** - Sincroniza vendas, clientes e fornecedores em sequência
- **Sincronização individual** para:
  - 📦 **Vendas** - Todas as vendas realizadas
  - 👥 **Clientes** - Cadastro de clientes
  - 🚚 **Fornecedores** - Cadastro de fornecedores
- **Feedback visual**:
  - Loading indicators durante sincronização
  - Mensagens de sucesso/erro
  - Cards coloridos por tipo de dados

#### Como acessar a tela:

**Opção 1: Adicionar no menu/drawer**

```dart
// No drawer ou menu principal, adicione:
ListTile(
  leading: const Icon(Icons.cloud_sync, color: Colors.deepPurple),
  title: const Text('Sincronizar Firestore'),
  subtitle: const Text('Backup dos dados locais'),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminSyncScreen(),
      ),
    );
  },
),
```

**Opção 2: Adicionar na HomeScreen**

```dart
// Em home_screen.dart, adicione um card:
Card(
  child: ListTile(
    leading: const Icon(Icons.cloud_upload, size: 32),
    title: const Text('Sincronizar dados'),
    subtitle: const Text('Backup para a nuvem'),
    trailing: const Icon(Icons.arrow_forward_ios),
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const AdminSyncScreen(),
        ),
      );
    },
  ),
)
```

#### Executar sincronização programaticamente:

```dart
import 'lib/services/vendas_firestore_service.dart';
import 'lib/services/clientes_firestore_service.dart';
import 'lib/services/fornecedores_firestore_service.dart';

// Sincronizar vendas
await VendasFirestoreService.syncTodasVendas(boxName: 'vendas');

// Sincronizar clientes
await ClientesFirestoreService.syncTodosClientes(boxName: 'clientes');

// Sincronizar fornecedores
await FornecedoresFirestoreService.syncTodosFornecedores(boxName: 'fornecedores');
```

#### Estrutura no Firestore:

Os dados são salvos em:

```
/lojas/{lojaId}/vendas/{vendaId}
/lojas/{lojaId}/clientes/{clienteId}
/lojas/{lojaId}/fornecedores/{fornecedorId}
```

Cada documento contém todos os campos do modelo + metadata (createdAt, updatedAt, status).

#### Quando usar:

- **Migração inicial**: Execute uma vez para enviar todos os dados existentes para o Firestore
- **Backup periódico**: Execute semanalmente ou mensalmente
- **Antes de trocar de dispositivo**: Garante que os dados estejam na nuvem
- **Multi-dispositivo**: Permite acessar os mesmos dados em vários dispositivos

---

### ✅ 3. Gerenciamento de Sub-categorias

**Arquivo criado:** `lib/screens/subcategorias_screen.dart`
**Modelo criado:** `lib/models/subcategoria.dart`

#### O que foi implementado:

Tela completa para gerenciar sub-categorias de produtos, permitindo organização hierárquica.

#### Funcionalidades:

- ➕ **Adicionar sub-categoria** com:
  - Nome (Ex: "Anéis de Prata")
  - Categoria pai (Ex: "Anéis")
  - Ícone emoji (opcional)
- ✏️ **Editar** sub-categorias existentes
- 🗑️ **Excluir** sub-categorias
- 🔄 **Ativar/Desativar** com switch
- 🔃 **Recarregar** lista
- 💾 **Sincronização automática** com Firestore

#### Modelo Subcategoria:

```dart
@HiveType(typeId: 13)
class Subcategoria extends HiveObject {
  @HiveField(0)
  String nome;

  @HiveField(1)
  String categoriaId;

  @HiveField(2)
  String? icone;

  @HiveField(3)
  bool ativa;

  @HiveField(4)
  DateTime dataCriacao;
}
```

#### Como acessar:

Adicione um botão na tela de configurações ou no menu:

```dart
ListTile(
  leading: const Icon(Icons.category, color: Colors.deepPurple),
  title: const Text('Sub-categorias'),
  subtitle: const Text('Gerenciar sub-categorias de produtos'),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const SubcategoriasScreen(),
      ),
    );
  },
)
```

#### Exemplo de uso:

**Categorias e Sub-categorias:**

```
Anéis
  ├─ Anéis de Prata 🥈
  ├─ Anéis de Ouro 🥇
  └─ Anéis Cravejados 💎

Colares
  ├─ Colares Curtos
  ├─ Colares Longos
  └─ Correntes 🔗

Brincos
  ├─ Argolas
  ├─ Brincos Pequenos
  └─ Brincos Longos
```

#### Integração com produtos:

No formulário de produtos (`produto_form_screen.dart`), o campo **subcategoria** já existe. Para usar as sub-categorias criadas:

**Opção 1: Dropdown com sub-categorias**

```dart
// Carregar sub-categorias da categoria selecionada
Future<List<String>> _getSubcategorias(String categoria) async {
  final box = await Hive.openBox<Subcategoria>('subcategorias');
  return box.values
      .where((s) => s.categoriaId == categoria && s.ativa)
      .map((s) => s.nome)
      .toList();
}

// No widget:
FutureBuilder<List<String>>(
  future: _getSubcategorias(_categoria.text),
  builder: (context, snapshot) {
    if (!snapshot.hasData) return SizedBox();

    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(labelText: 'Sub-categoria'),
      value: _subcategoria.text.isEmpty ? null : _subcategoria.text,
      items: snapshot.data!.map((sub) =>
        DropdownMenuItem(value: sub, child: Text(sub))
      ).toList(),
      onChanged: (value) {
        setState(() => _subcategoria.text = value ?? '');
      },
    );
  },
)
```

---

### ✅ 4. Auto-Sync de Produtos

**Arquivo criado:** `lib/services/produto_auto_sync_service.dart`
**Integrado em:** `lib/main.dart`

#### O que foi implementado:

Sistema automático que detecta mudanças nos produtos e sincroniza instantaneamente com o Firestore.

#### Funcionalidades:

- 👀 **Monitoramento contínuo** do Hive box de produtos
- 🔄 **Debounce de 2 segundos** para evitar sync excessivo
- 🎯 **Detecção de eventos**:
  - Produto modificado
  - Produto deletado
  - Produto desmarcado do catálogo
- ✅ **Sincronização automática** para `draft_produtos` e `produtos`
- 📝 **Logs detalhados** no console

#### Como funciona:

1. O serviço inicia automaticamente no `main.dart`
2. Monitora todas as mudanças no box de produtos
3. Ao detectar uma mudança, aguarda 2 segundos (debounce)
4. Sincroniza automaticamente para o Firestore
5. Logs aparecem no console: `[AUTO-SYNC] Produto modificado: anel (key: 0)`

#### Logs que você verá:

```
✅ [AUTO-SYNC] Iniciando monitoramento no box: produtos_loja_uid_xxx
🟢 [AUTO-SYNC] Serviço iniciado com sucesso
📝 [AUTO-SYNC] Produto modificado: anel (key: 0)
🔄 [AUTO-SYNC] Executando sync de 1 produto(s)...
✅ [AUTO-SYNC] Sync concluído
```

---

## 🔥 Regras de Segurança Firestore

As seguintes regras foram adicionadas ao `firestore.rules`:

```javascript
// Vendas
match /vendas/{vendaId} {
  allow read: if isAdminOrSystem();
  allow create: if isSignedIn();
  allow update, delete: if isAdminOrSystem();
}

// Clientes
match /clientes/{clienteId} {
  allow read: if isAdminOrSystem();
  allow create: if isSignedIn();
  allow update, delete: if isAdminOrSystem();
}

// Fornecedores
match /fornecedores/{fornecedorId} {
  allow read, write: if isAdminOrSystem();
}

// Sub-categorias
match /subcategorias/{subId} {
  allow read: if true;
  allow create, update, delete: if isAdminOrSystem();
}
```

**Deploy das regras:**

```bash
firebase deploy --only firestore:rules
```

---

## 📊 Checklist de Integração

### ✅ Concluído

- [x] Sistema de promoções em produtos
- [x] Tela de sincronização Firestore
- [x] Tela de gerenciamento de sub-categorias
- [x] Auto-sync de produtos
- [x] Serviços de sync para vendas, clientes, fornecedores
- [x] Regras de segurança Firestore
- [x] Campos de promoção no modelo Produto
- [x] Getters de cálculo de preço promocional

### 🔄 Próximos Passos (Opcional)

- [ ] Adicionar filtros de categoria/sub-categoria no catálogo público
- [ ] Exibir badge de "PROMOÇÃO" em produtos promocionais
- [ ] Criar tela de "Produtos em Promoção"
- [ ] Adicionar notificações quando promoção está próxima de expirar
- [ ] Dashboard de estatísticas do Firestore
- [ ] Sincronização bidirecional (Firestore → Hive)

---

## 🆘 Troubleshooting

### Erro: "type 'Null' is not a subtype of type 'bool'"

**Solução:** Já corrigido! O campo `emPromocao` tem `defaultValue: false` e o adapter foi regenerado.

### Produtos não sincronizam

1. Verifique os logs: `flutter run --verbose`
2. Confirme que `store_id` está definido
3. Verifique as regras do Firestore
4. Confirme que o Firebase foi inicializado

### Sub-categorias não aparecem

1. Registre o adapter do Hive:
```dart
Hive.registerAdapter(SubcategoriaAdapter());
```

2. Abra o box:
```dart
await Hive.openBox<Subcategoria>('subcategorias');
```

---

## 📞 Suporte

Para dúvidas ou problemas:
- Verifique os logs do Flutter: `flutter run --verbose`
- Verifique o console do Firebase
- Revise este guia completo
- Consulte a documentação dos serviços criados

---

**Data de atualização:** 21/12/2025
**Versão do app:** MasterPalm v1.0+
**Desenvolvido com:** Flutter + Firebase + Hive
