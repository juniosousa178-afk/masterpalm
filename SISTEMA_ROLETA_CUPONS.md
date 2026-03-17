# 🎰 Sistema Completo de Roleta da Sorte e Cupons

## 📋 Índice

1. [Visão Geral](#visão-geral)
2. [Funcionalidades](#funcionalidades)
3. [Arquitetura](#arquitetura)
4. [Modelos de Dados](#modelos-de-dados)
5. [Fluxo de Uso](#fluxo-de-uso)
6. [Configuração](#configuração)
7. [Integração com Globo da Sorte](#integração-com-globo-da-sorte)
8. [Regras de Firestore](#regras-de-firestore)
9. [Como Usar](#como-usar)

---

## 🎯 Visão Geral

Sistema completo de gamificação para e-commerce que permite:
- **Roleta da Sorte** com prêmios configuráveis
- **Cupons automáticos** com validade de 60 dias
- **Controle de frequência** de prêmios (ex: a cada 10 vendas, 1 ganha)
- **Integração com Globo da Sorte** para sorteios reais
- **Aplicação automática** de cupons no checkout

---

## ✨ Funcionalidades

### Para o Vendedor

1. **Configuração da Roleta**
   - Definir valor mínimo para girar
   - Configurar prêmios disponíveis
   - Definir frequência de prêmios (ex: a cada X vendas, 1 sai premiada)
   - Acompanhar estatísticas

2. **Tipos de Prêmios**
   - ✅ Desconto percentual (ex: 10% off)
   - ✅ Desconto fixo (ex: R$ 20 off)
   - ✅ Frete grátis
   - ✅ Brinde (produto grátis)
   - ✅ Prêmio surpresa
   - ❌ Tente novamente (não ganha nada)

3. **Gerenciamento de Cupons**
   - Visualizar cupons gerados
   - Ver cupons por cliente
   - Limpar cupons expirados

### Para o Cliente

1. **Girar a Roleta**
   - Atingir valor mínimo de compra
   - Girar roleta e ganhar prêmio
   - Receber cupom automaticamente

2. **Cupons**
   - Ver cupons disponíveis
   - Cupons aplicados automaticamente no checkout
   - Validade de 60 dias
   - Instruções claras de uso

3. **Card de Resultado**
   - Código do cupom
   - Tipo de prêmio
   - Validade
   - Instruções de uso
   - Contagem regressiva de dias

---

## 🏗️ Arquitetura

### Estrutura de Pastas

```
lib/
├── models/
│   ├── campanha_sorteio.dart         # Modelo de campanha
│   └── cupom_cliente.dart            # Modelo de cupom
├── services/
│   ├── campanhas_sorteio_service.dart # Gerenciamento de campanhas
│   ├── cupons_service.dart            # Gerenciamento de cupons
│   └── globo_sorte_service.dart       # Integração Globo da Sorte
├── screens/
│   └── roleta_sorte_screen.dart       # Tela de configuração
└── widgets/
    ├── roleta_catalog_widget_v2.dart  # Widget da roleta (catálogo)
    └── resultado_roleta_card.dart     # Card de resultado
```

### Firestore - Estrutura de Dados

```
lojas/{lojaId}/
├── campanhas_sorteio_config/
│   └── roleta/
│       ├── valorMinimo: 50.0
│       ├── frequenciaPremio: 10
│       ├── vendasDesdePremio: 3
│       ├── totalVendas: 47
│       └── premios: [...]
│
├── cupons_clientes/
│   └── {cupomId}/
│       ├── codigo: "ROLETA-ABC123"
│       ├── tipo: "desconto"
│       ├── valorDesconto: 10.0
│       ├── dataGanho: Timestamp
│       ├── dataValidade: Timestamp
│       ├── usado: false
│       └── clienteId: "..."
│
└── campanhas_sorteio/
    └── {campanhaId}/
        ├── titulo: "Campanha Natal 2025"
        ├── status: "aberta"
        └── participantes/
            └── {participanteId}/
                ├── numero: "53827"
                └── clienteNome: "..."
```

---

## 📦 Modelos de Dados

### CupomCliente

```dart
enum TipoCupom {
  desconto,        // % de desconto
  descontoFixo,    // R$ de desconto
  freteGratis,     // Frete zerado
  brinde,          // Produto grátis
  premioSurpresa   // Surpresa!
}

class CupomCliente {
  final String id;
  final String lojaId;
  final String clienteId;
  final TipoCupom tipo;
  final String codigo;        // "ROLETA-ABC123"
  final String titulo;        // "10% de Desconto"
  final DateTime dataGanho;
  final DateTime dataValidade; // +60 dias
  final bool usado;
  // ... outros campos
}
```

### CampanhaSorteio

```dart
class CampanhaSorteio {
  final String id;
  final String lojaId;
  final int frequenciaPremio;    // A cada X vendas
  final int totalVendas;         // Total de vendas
  final int vendasDesdePremio;   // Vendas desde último prêmio
  final List<Map<String, dynamic>> premios;
  // ... outros campos
}
```

---

## 🔄 Fluxo de Uso

### 1. Configuração (Vendedor)

```
Vendedor
  ↓
Abre tela "Roleta da Sorte"
  ↓
Define:
  - Valor mínimo: R$ 50
  - Frequência: a cada 10 vendas, 1 ganha
  - Prêmios:
    * 10% desconto
    * Frete grátis
    * Brinde
    * Tente novamente
  ↓
Salva configuração
  ↓
Firestore: lojas/{lojaId}/campanhas_sorteio_config/roleta
```

### 2. Cliente Gira a Roleta

```
Cliente adiciona R$ 100 ao carrinho
  ↓
Aparece widget da roleta
  ↓
Verifica:
  ✅ Valor >= R$ 50 (OK!)
  ✅ ClienteId informado (OK!)
  ↓
Cliente clica "GIRAR A ROLETA"
  ↓
Sistema verifica frequência:
  - vendasDesdePremio: 9
  - frequenciaPremio: 10
  - Resultado: PRÓXIMA VENDA GANHA! 🎉
  ↓
Sorteia prêmio REAL (não "tente novamente")
  ↓
Animação da roleta (4 segundos)
  ↓
Cria cupom no Firestore
  ↓
Mostra card de resultado com:
  - Código: ROLETA-XYZ789
  - Prêmio: 10% de Desconto
  - Validade: 59 dias
  - Instruções
  ↓
Atualiza contador:
  - vendasDesdePremio: 0 (reset)
  - totalVendas: 48
```

### 3. Aplicação Automática no Checkout

```
Cliente adiciona produtos
  ↓
Vai para checkout
  ↓
Sistema busca cupons válidos do cliente
  ↓
Aplica automaticamente:
  - Desconto: R$ 10 (10%)
  ↓
Mostra resumo:
  Subtotal: R$ 100
  Desconto (ROLETA-XYZ789): -R$ 10
  Frete: R$ 15
  TOTAL: R$ 105
  ↓
Cliente finaliza compra
  ↓
Sistema marca cupom como usado
```

---

## ⚙️ Configuração

### 1. Habilitar Roleta na Loja

```dart
// No app admin
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => RoletaSorteScreen(
      lojaId: 'nathy-pratas-e-folheados',
    ),
  ),
);
```

### 2. Adicionar Widget no Catálogo

```dart
// No PublicCatalogScreen
import '../widgets/roleta_catalog_widget_v2.dart';

// Dentro do builder
RoletaCatalogWidgetV2(
  lojaId: lojaId,
  totalCarrinho: _calcularTotal(),
  clienteId: _clienteId,
  clienteNome: _clienteNome,
  clienteWhatsApp: _clienteWhatsApp,
  onPremioGanho: () {
    // Recarregar cupons, etc
  },
)
```

### 3. Aplicar Cupons no Checkout

```dart
// Ao calcular total do carrinho
final resultado = await CuponsService.aplicarCuponsAutomaticos(
  lojaId: lojaId,
  clienteId: clienteId,
  subtotal: subtotal,
  frete: frete,
  itens: itens,
);

final descontoTotal = resultado['descontoTotal'];
final freteDesconto = resultado['freteDesconto'];
final cuponsAplicados = resultado['cuponsAplicados'];
final brindes = resultado['brindes'];

// Ao finalizar pedido
for (final cupomId in cuponsAplicados) {
  await CuponsService.usarCupom(
    lojaId: lojaId,
    cupomId: cupomId,
    pedidoId: pedidoId,
  );
}
```

---

## 🌐 Integração com Globo da Sorte

### O que é?

A **Globo da Sorte** é uma plataforma de sorteios reais e transparentes. A integração permite:
- Registrar números da sorte automaticamente
- Realizar sorteios via API
- Consultar resultados
- Validar números

### Como Funciona

```dart
// 1. Registrar número quando cliente compra
await GloboSorteService.registrarNumero(
  numero: '53827',
  campanhaId: 'campanha-natal-2025',
  clienteNome: 'João Silva',
  clienteEmail: 'joao@email.com',
  clienteWhatsApp: '5533999999999',
  valorCompra: 150.00,
);

// 2. Realizar sorteio
final vencedor = await GloboSorteService.realizarSorteio(
  campanhaId: 'campanha-natal-2025',
);

print('Número vencedor: ${vencedor['numero_vencedor']}');
print('Cliente: ${vencedor['cliente_nome']}');

// 3. Consultar estatísticas
final stats = await GloboSorteService.obterEstatisticas(
  campanhaId: 'campanha-natal-2025',
);

print('Total de números: ${stats['total_numeros']}');
print('Total participantes: ${stats['total_participantes']}');
```

### Configurar API Key

⚠️ **IMPORTANTE**: Nunca deixe a API Key hardcoded!

Opções seguras:
1. **Firebase Remote Config**
2. **Variáveis de ambiente**
3. **Arquivo .env** (adicionar ao .gitignore)

```dart
// Exemplo com Firebase Remote Config
final remoteConfig = FirebaseRemoteConfig.instance;
await remoteConfig.fetchAndActivate();
final apiKey = remoteConfig.getString('globo_sorte_api_key');
```

---

## 🔒 Regras de Firestore

```javascript
match /lojas/{lojaId} {

  // Config da roleta (leitura pública para exibir no catálogo)
  match /campanhas_sorteio_config/{configId} {
    allow read: if true;
    allow write: if isAdminOrSystem();
  }

  // Cupons de clientes
  match /cupons_clientes/{cupomId} {
    allow read: if true; // Permite ler para exibir no catálogo
    allow create: if true; // Permite criar ao ganhar na roleta
    allow update: if isAdminOrSystem();
    allow delete: if isAdminOrSystem();
  }

  // Campanhas de sorteio
  match /campanhas_sorteio/{campanhaId} {
    allow read: if true;
    allow write: if isAdminOrSystem();

    match /participantes/{participanteId} {
      allow read: if true;
      allow create: if true; // Permite participar
      allow update, delete: if isAdminOrSystem();
    }
  }
}
```

---

## 🚀 Como Usar

### Passo 1: Deploy das Regras

```bash
firebase deploy --only firestore:rules
```

### Passo 2: Configurar Roleta (Admin)

1. Abrir app admin
2. Ir em "Roleta da Sorte"
3. Configurar:
   - Valor mínimo: R$ 50
   - Frequência: 10 (a cada 10 vendas, 1 ganha)
   - Adicionar prêmios:
     - "10% de Desconto" (desconto, 10)
     - "Frete Grátis" (freteGratis, 0)
     - "Brinde Surpresa" (brinde, "Colar de prata")
     - "Tente Novamente" (nenhum, 0)
4. Salvar

### Passo 3: Testar no Catálogo

1. Abrir catálogo web: `https://mastepalm.com.br/loja/nathy-pratas-e-folheados`
2. Adicionar R$ 50+ ao carrinho
3. Informar WhatsApp/Email (clienteId)
4. Clicar em "GIRAR A ROLETA"
5. Ver resultado e cupom

### Passo 4: Usar Cupom

1. Adicionar produtos ao carrinho
2. Ir para checkout
3. Cupom aplicado automaticamente!
4. Ver desconto no resumo

---

## 📊 Estatísticas e Monitoramento

### Console do Vendedor

```dart
// Total de cupons gerados
final totalCupons = await db
  .collection('lojas')
  .doc(lojaId)
  .collection('cupons_clientes')
  .count()
  .get();

// Cupons usados
final cuponsUsados = await db
  .collection('lojas')
  .doc(lojaId)
  .collection('cupons_clientes')
  .where('usado', isEqualTo: true)
  .count()
  .get();

// Taxa de conversão
final taxaConversao = (cuponsUsados / totalCupons) * 100;

print('Taxa de conversão de cupons: $taxaConversao%');
```

### Limpar Cupons Expirados (Manutenção)

```dart
// Executar periodicamente (ex: 1x por dia)
final removidos = await CuponsService.limparCuponsExpirados(
  lojaId: lojaId,
);

print('Removidos $removidos cupons expirados');
```

---

## 🎨 Personalização

### Cores do Card de Resultado

```dart
// Em resultado_roleta_card.dart
Color _getCorTipo() {
  switch (cupom.tipo) {
    case TipoCupom.desconto:
      return Colors.green; // Mudar aqui
    case TipoCupom.freteGratis:
      return Colors.blue;
    // ...
  }
}
```

### Textos e Mensagens

```dart
// Em cupom_cliente.dart
String get instrucoes {
  switch (tipo) {
    case TipoCupom.desconto:
      return 'Seu texto personalizado aqui';
    // ...
  }
}
```

---

## 🐛 Troubleshooting

### Problema: Roleta não aparece no catálogo

**Solução:**
1. Verificar se configuração existe:
   ```
   Firestore > lojas > {lojaId} > campanhas_sorteio_config > roleta
   ```
2. Verificar regras do Firestore (leitura pública)
3. Verificar console do navegador para erros

### Problema: Cupons não aplicam automaticamente

**Solução:**
1. Verificar se `clienteId` está definido
2. Verificar se cupons estão válidos (não expirados)
3. Verificar logs: `CuponsService.aplicarCuponsAutomaticos`

### Problema: Erro ao criar cupom

**Solução:**
1. Verificar regras do Firestore (permissão de create)
2. Verificar se `lojaId` e `clienteId` estão corretos
3. Ver logs no console

---

## 📝 Notas Importantes

1. **Segurança**: Cupons são criados server-side para evitar fraudes
2. **Performance**: Índices do Firestore são essenciais para queries rápidas
3. **Backup**: Fazer backup regular dos cupons e campanhas
4. **Testes**: Testar com diferentes frequências antes de produção
5. **Compliance**: Respeitar leis de sorteios e promoções da sua região

---

## 🎓 Próximos Passos

- [ ] Dashboard de analytics
- [ ] Push notifications quando cupom vai expirar
- [ ] Histórico de cupons usados por cliente
- [ ] Cupons compartilháveis (referral)
- [ ] Gamificação avançada (níveis, badges)

---

**Desenvolvido com ❤️ para MasterPalm**

*Última atualização: 29/12/2025*
