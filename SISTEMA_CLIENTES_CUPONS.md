# Sistema de Clientes e Cupons - Catálogo Web

Sistema completo de cadastro de clientes e gerenciamento automático de cupons de desconto no catálogo web.

---

## 📋 Visão Geral

O sistema permite que clientes se cadastrem no catálogo web e ganhem cupons de desconto que são aplicados **automaticamente** na próxima compra.

### Funcionalidades Principais

✅ **Cadastro/Login de Clientes**
- Login/cadastro simples com nome e email
- Dados salvos no Firestore (`lojas/{lojaId}/clientes_web`)
- Sessão persistente com SharedPreferences

✅ **Menu Lateral (Drawer)**
- "Minha Conta" ou "Entrar / Cadastrar"
- Indicador visual de cupons disponíveis
- Informações do cliente logado

✅ **Ícone de Perfil**
- Aparece na AppBar quando cliente está logado
- Indicador verde quando tem cupom disponível
- Acesso rápido ao perfil

✅ **Sistema de Cupons**
- Cupons armazenados no perfil do cliente
- Aplicação **automática** no carrinho
- Exibição visual do desconto
- Marcação automática como "usado" após finalizar pedido

✅ **Tela de Perfil**
- Informações do cliente
- Lista de cupons válidos
- Design responsivo e atraente
- Botão de logout

---

## 🗂️ Estrutura do Firestore

### Collection: `lojas/{lojaId}/clientes_web/{clienteId}`

```javascript
{
  nome: "João da Silva",
  email: "joao@email.com",
  telefone: "(11) 99999-9999",
  cpf: "12345678900",

  // Endereço (opcional)
  cep: "12345-678",
  endereco: "Rua Exemplo",
  numero: "123",
  complemento: "Apto 45",
  bairro: "Centro",
  cidade: "São Paulo",
  estado: "SP",

  // Cupons
  cupons: [
    {
      codigo: "DESC10-ABCD1234",
      desconto: 10.0,            // Percentual
      dataExpiracao: Timestamp,
      usado: false,
      dataUso: null,
      origem: "roleta"           // 'roleta', 'campanha', 'manual'
    }
  ],

  // Metadados
  criadoEm: Timestamp,
  atualizadoEm: Timestamp
}
```

---

## 🚀 Como Usar (Cliente)

### 1. Acessar o Catálogo

Cliente acessa o catálogo web pelo app MasterPalm.

### 2. Fazer Cadastro/Login

**Opção A**: Pelo menu lateral (hamburger)
1. Abrir menu lateral
2. Clicar em "Entrar / Cadastrar"
3. Preencher dados (nome, email, telefone, CPF)
4. Clicar em "Entrar / Cadastrar"

**Opção B**: Pelo ícone de perfil
1. Clicar no ícone de pessoa na AppBar (se já logado)
2. Ver perfil e cupons disponíveis

### 3. Ganhar Cupons

Cupons podem ser ganhos de 3 formas:

**A) Roleta da Sorte**
- Ao fazer uma compra, girar a roleta
- Se ganhar cupom, ele é automaticamente adicionado ao perfil

**B) Campanha de Sorteio**
- Participar de campanhas ativas
- Receber cupons por email/WhatsApp
- Cupons ficam disponíveis no perfil

**C) Manual (Admin)**
- Administrador pode adicionar cupons manualmente via código

### 4. Usar Cupons

**Aplicação Automática**:
1. Faça login no catálogo
2. Adicione produtos ao carrinho
3. O cupom é **automaticamente aplicado**
4. Veja o desconto no resumo do carrinho
5. Finalize o pedido normalmente

**Importante**:
- Apenas o cupom com **maior desconto** é aplicado
- Cupons são válidos por 60 dias
- Após usar, o cupom é marcado como "usado"

### 5. Visualizar Cupons

1. Abrir menu lateral
2. Clicar em "Meu Perfil"
3. Ver todos os cupons disponíveis com:
   - Código do cupom
   - Percentual de desconto
   - Data de validade
   - Dias restantes
   - Origem do cupom

---

## 🔧 Como Usar (Administrador)

### Adicionar Cupom Manualmente

```dart
import 'package:master_palm/services/cliente_web_service.dart';

// Adicionar cupom de 10% válido por 60 dias
await ClienteWebService.adicionarCupom(
  lojaId: 'nathy-pratas-e-folheados',
  clienteId: 'abc123',
  codigo: 'DESC10-NATAL2025',
  desconto: 10.0,
  dataExpiracao: DateTime.now().add(Duration(days: 60)),
  origem: 'manual',
);
```

### Adicionar Cupom da Roleta (Automático)

Quando cliente gira a roleta e ganha desconto, o cupom é adicionado automaticamente na `PedidoPublicoScreen`:

```dart
// Já implementado em pedido_publico_screen.dart (linhas 275-318)
// O cupom é criado e adicionado ao cliente automaticamente
```

### Verificar Cupons de um Cliente

```dart
// Buscar cliente
final cliente = await ClienteWebService.getClienteAutenticado(lojaId);

// Ver cupons válidos
if (cliente != null) {
  for (final cupom in cliente.cuponsValidos) {
    print('${cupom.codigo}: ${cupom.desconto}% - Válido até ${cupom.dataExpiracao}');
  }
}
```

---

## 💻 Arquivos do Sistema

### Models
- `lib/models/cliente_web.dart` - Modelo de cliente e cupom

### Services
- `lib/services/cliente_web_service.dart` - Lógica de autenticação e cupons

### Screens
- `lib/screens/cliente_login_screen.dart` - Tela de login/cadastro
- `lib/screens/cliente_perfil_screen.dart` - Tela de perfil do cliente
- `lib/screens/catalago_screen.dart` - Catálogo com integração de cupons

---

## 🎨 Interface do Usuário

### Menu Lateral (Drawer)

```
┌─────────────────────────────┐
│ [Avatar]                    │
│ Nome do Cliente             │
│ email@cliente.com           │
├─────────────────────────────┤
│ 👤 Meu Perfil               │
│    Cupom: 10% OFF           │ ← Indicador de cupom
├─────────────────────────────┤
│ 🎁 Meus Cupons          [2] │ ← Badge com quantidade
├─────────────────────────────┤
│ ℹ️ Sobre                    │
└─────────────────────────────┘
```

### Ícone de Perfil na AppBar

```
┌─────────────────────────────┐
│ ☰  Catálogo        👤  🛒  │
│                     ↑        │
│                  Ponto verde │
│                (tem cupom)   │
└─────────────────────────────┘
```

### Carrinho com Cupom

```
┌─────────────────────────────┐
│ Seu carrinho                │
├─────────────────────────────┤
│ 🎁 Cupom aplicado:          │
│    DESC10-ABCD1234          │
│    10% de desconto          │
├─────────────────────────────┤
│ Subtotal:      R$ 100,00    │
│ Desconto (10%): - R$ 10,00  │
├─────────────────────────────┤
│ Total:         R$ 90,00     │
├─────────────────────────────┤
│ [Finalizar pedido WhatsApp] │
└─────────────────────────────┘
```

---

## 🔄 Fluxo Completo

### Fluxo: Cliente Ganha Cupom da Roleta

1. Cliente faz compra no catálogo
2. Admin confirma pedido (`pedido_publico_screen.dart`)
3. Sistema gira roleta automaticamente
4. Se ganhar desconto:
   - Cupom é criado com código único
   - Cupom é adicionado ao cliente no Firestore
   - Cliente vê cupom na próxima vez que acessar o perfil

### Fluxo: Cliente Usa Cupom

1. Cliente faz login no catálogo
2. Sistema carrega cliente e cupons disponíveis
3. Sistema aplica **automaticamente** o melhor cupom
4. Cliente adiciona produtos ao carrinho
5. Desconto aparece no resumo do carrinho
6. Cliente finaliza pedido
7. Sistema marca cupom como "usado"
8. WhatsApp mostra mensagem com desconto aplicado

---

## 🔒 Segurança

### Validações Implementadas

✅ Cupom só pode ser usado uma vez
✅ Cupom expira após 60 dias
✅ Cupom só é válido para o cliente que recebeu
✅ Sessão do cliente é validada no servidor (Firestore)
✅ Email é usado como identificador único

### Dados Sensíveis

⚠️ **Não são coletados**:
- Senha (sistema sem senha)
- Dados de cartão
- Documentos pessoais além do CPF

✅ **São coletados** (opcional):
- Nome, email, telefone
- CPF (opcional)
- Endereço (opcional, para entregas)

---

## 📊 Relatórios e Analytics

### Consultas Úteis

**Clientes cadastrados**:
```javascript
db.collection('lojas/{lojaId}/clientes_web').count()
```

**Cupons ativos**:
```javascript
db.collection('lojas/{lojaId}/clientes_web')
  .where('cupons', 'array-contains', { usado: false })
```

**Cupons usados no mês**:
```javascript
// Filtrar por cupons.dataUso >= startOfMonth
```

---

## ❓ Perguntas Frequentes

**P: O cupom é aplicado automaticamente?**
R: Sim! Assim que o cliente faz login, o sistema verifica se ele tem cupons disponíveis e aplica automaticamente o de maior desconto.

**P: Posso ter vários cupons ao mesmo tempo?**
R: Sim! Você pode ter vários cupons, mas apenas um (o de maior desconto) será aplicado por vez.

**P: O cupom expira?**
R: Sim, cupons são válidos por 60 dias após a criação.

**P: Preciso criar senha?**
R: Não! O sistema usa apenas email para identificação, sem necessidade de senha.

**P: Como faço logout?**
R: Abra o menu lateral → Meu Perfil → Clique no ícone de logout no canto superior direito.

**P: Meus dados ficam salvos?**
R: Sim, seus dados e cupons ficam salvos no Firestore e são recuperados quando você fizer login novamente.

---

## 🛠️ Manutenção

### Limpar Cupons Expirados

Execute periodicamente (via Cloud Function ou manualmente):

```javascript
const now = admin.firestore.Timestamp.now();
const clientesRef = db.collection('lojas/{lojaId}/clientes_web');

const snapshot = await clientesRef.get();
for (const doc of snapshot.docs) {
  const cupons = doc.data().cupons || [];
  const cuponsValidos = cupons.filter(c =>
    !c.usado && c.dataExpiracao.toDate() > now.toDate()
  );

  await doc.ref.update({ cupons: cuponsValidos });
}
```

---

## ✅ Pronto!

O sistema está 100% funcional e integrado com:
- ✅ Roleta da Sorte
- ✅ Campanhas de Sorteio
- ✅ Catálogo Web
- ✅ Email/WhatsApp automático

**Boas vendas! 🎉**
