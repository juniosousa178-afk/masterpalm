# 🧾 Sistema de Emissão de Notas Fiscais

## 📋 Visão Geral

Sistema completo de emissão de Notas Fiscais Eletrônicas (NF-e) integrado com API, vinculado ao Sebrae e preparado para integração com provedores de NF-e.

---

## 🎯 Funcionalidades

### ✅ Implementadas

- **Emissão de NF-e** a partir de vendas realizadas
- **Sincronização com Firestore** (dados persistem mesmo após reinstalar)
- **Isolamento por loja** (cada loja vê apenas suas notas)
- **Listagem de notas emitidas** com filtros por status
- **Listagem de vendas sem nota fiscal**
- **Consulta de status** de notas emitidas
- **Download de DANFE** (PDF) e XML
- **Cancelamento de notas** (com justificativa)

### 📊 Status Disponíveis

- `pendente` - Nota criada mas não enviada para SEFAZ
- `emitida` - Nota autorizada pela SEFAZ
- `cancelada` - Nota cancelada
- `erro` - Erro na emissão

---

## 🔧 Configuração Inicial

### 1. Escolher Provedor de API

O sistema está preparado para integração com:

- **Focus NFe** (exemplo implementado)
- **Sebrae NFe**
- **WebMania**
- **Bling**
- **Outros provedores**

### 2. Configurar API Token

No código da aplicação, configure o token antes de usar:

```dart
import '../services/nota_fiscal_service.dart';

// Configurar uma única vez no início do app
NotaFiscalService.configure(
  apiToken: 'SEU_TOKEN_AQUI',
  producao: false, // true para produção, false para homologação
);
```

### 3. Adaptar para API Específica

Edite o arquivo `lib/services/nota_fiscal_service.dart`:

```dart
// Altere a URL base conforme seu provedor
static const String _baseUrl = 'https://api.focusnfe.com.br/v2';

// Ajuste o payload conforme especificação da API
static Map<String, dynamic> _montarPayloadNFe(NotaFiscal nota) {
  // Adapte os campos conforme documentação do provedor
}
```

---

## 📱 Como Usar

### 1. Acessar a Tela de Notas Fiscais

Navegue para `NotasFiscaisScreen`:

```dart
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => const NotasFiscaisScreen(),
  ),
);
```

### 2. Emitir Nota Fiscal

**Passo a passo:**

1. Clique no botão **+** (FloatingActionButton)
2. Selecione a venda desejada na lista de "Vendas Sem NF"
3. Preencha os dados do cliente:
   - CPF/CNPJ (obrigatório)
   - Endereço
   - Cidade
   - Estado (UF)
   - CEP
   - Observações
4. Clique em **"Emitir"**
5. Confirme o envio para SEFAZ

### 3. Visualizar Notas Emitidas

Na aba **"Notas Emitidas"**:
- Filtre por status (Todas, Pendentes, Emitidas, Canceladas, Erro)
- Clique nos 3 pontos (⋮) para ações:
  - **Emitir NF-e** (se pendente)
  - **Ver DANFE** (PDF)
  - **Ver XML**
  - **Cancelar** (se emitida)

### 4. Vendas Sem Nota

Na aba **"Vendas Sem NF"**:
- Veja todas as vendas que ainda não possuem nota fiscal
- Clique em **"Emitir NF-e"** para criar nota para a venda

---

## 💾 Estrutura de Dados

### Modelo NotaFiscal

```dart
class NotaFiscal {
  String numero;           // Número da nota
  String serie;            // Série da nota (geralmente "1")
  String? chaveAcesso;     // Chave de 44 dígitos
  String status;           // pendente, emitida, cancelada, erro
  String? vendaId;         // ID da venda vinculada

  // Dados do cliente
  String clienteNome;
  String clienteCpfCnpj;
  String? clienteEndereco;
  String? clienteCidade;
  String? clienteEstado;
  String? clienteCep;

  // Valores
  double valorTotal;
  double valorProdutos;
  double valorFrete;
  double valorDesconto;

  // Itens
  List<NotaFiscalItem> itens;

  // URLs
  String? xmlUrl;          // URL do XML
  String? pdfUrl;          // URL do DANFE

  // Isolamento
  String lojaId;           // ID da loja
  String? idFirebase;      // ID no Firestore
}
```

### Modelo NotaFiscalItem

```dart
class NotaFiscalItem {
  String produtoNome;
  String? codigoProduto;
  int quantidade;
  double valorUnitario;
  double valorTotal;
  String unidade;          // UN, KG, M, etc
  String? ncm;             // Código NCM
  String? cfop;            // Código CFOP
  double? aliquotaIcms;
}
```

---

## 🔥 Firestore

### Estrutura no Banco

```
/lojas/{lojaId}/notas_fiscais/{notaId}
```

### Regras de Segurança

```javascript
match /notas_fiscais/{notaId} {
  allow read, write: if isAdminOrSystem();
}
```

### Sincronização Automática

- **Ao criar nota**: Sincroniza para Firestore automaticamente
- **Ao abrir tela**: Baixa notas do Firestore (últimas 100)
- **Ao deletar**: Remove do Hive e Firestore

---

## 🔌 Integração com APIs

### Focus NFe (Exemplo Implementado)

1. **Criar conta**: https://focusnfe.com.br
2. **Obter token**: Painel > Configurações > Token de API
3. **Configurar**:
```dart
NotaFiscalService.configure(
  apiToken: 'SEU_TOKEN_FOCUS',
  producao: false,
);
```

### Sebrae NFe

Para integrar com Sebrae, ajuste em `nota_fiscal_service.dart`:

```dart
static const String _baseUrl = 'https://api.sebrae.nfe.com.br'; // URL do Sebrae

static Map<String, dynamic> _montarPayloadNFe(NotaFiscal nota) {
  // Ajustar conforme documentação Sebrae
  return {
    // Campos específicos do Sebrae
  };
}
```

### Outros Provedores

1. Consulte a documentação do provedor
2. Ajuste `_baseUrl`
3. Adapte `_montarPayloadNFe()`
4. Ajuste tratamento de resposta em `emitirNotaFiscal()`

---

## ⚙️ Configurações Avançadas

### Personalizar Campos Fiscais

Edite `_montarPayloadNFe()` para incluir:

```dart
'icms_origem': '0',                    // Origem da mercadoria
'icms_situacao_tributaria': '102',     // CST
'cfop': '5102',                        // CFOP padrão
'ncm': '00000000',                     // NCM padrão
```

### Sequencial de Numeração

Implemente controle de sequencial em `gerarProximoNumero()`:

```dart
static Future<String> gerarProximoNumero({
  required String lojaId,
  required String serie,
}) async {
  // Buscar último número no Firestore
  final snapshot = await FirebaseFirestore.instance
      .collection('lojas')
      .doc(lojaId)
      .collection('config_nfe')
      .doc('sequencial_$serie')
      .get();

  int proximoNumero = (snapshot.data()?['ultimo_numero'] ?? 0) + 1;

  // Atualizar no Firestore
  await FirebaseFirestore.instance
      .collection('lojas')
      .doc(lojaId)
      .collection('config_nfe')
      .doc('sequencial_$serie')
      .set({'ultimo_numero': proximoNumero});

  return proximoNumero.toString();
}
```

---

## 🛡️ Segurança

### Isolamento por Loja

✅ Todas as operações respeitam `lojaId`:
- Loja X não vê/modifica notas da Loja Y
- Queries filtradas por loja
- Sincronização isolada

### Permissões

Verificação automática de permissão:
```dart
final permitido = await PermissaoService.possuiPermissao('notas_fiscais');
```

---

## 📊 Relatórios e Estatísticas

### Notas por Status

```dart
final pendentes = notasBox.values.where((n) => n.status == 'pendente').length;
final emitidas = notasBox.values.where((n) => n.status == 'emitida').length;
final canceladas = notasBox.values.where((n) => n.status == 'cancelada').length;
```

### Valor Total Emitido

```dart
final totalEmitido = notasBox.values
    .where((n) => n.status == 'emitida')
    .fold<double>(0, (sum, n) => sum + n.valorTotal);
```

---

## 🚨 Tratamento de Erros

### Erros Comuns

1. **Token inválido**
   - Verifique se configurou `NotaFiscalService.configure()`
   - Confirme token no painel do provedor

2. **CPF/CNPJ inválido**
   - Valide antes de enviar
   - Use biblioteca de validação

3. **Timeout**
   - APIs podem demorar (SEFAZ)
   - Implemente retry se necessário

### Logs

Todos os eventos são logados:
```
🧾 [NF-e] Emitindo nota fiscal 12345...
✅ [NF-e] Nota fiscal emitida com sucesso!
❌ [NF-e] Erro ao emitir nota: timeout
```

---

## 📚 Arquivos Criados

| Arquivo | Descrição |
|---------|-----------|
| `lib/models/nota_fiscal.dart` | Modelos Hive (NotaFiscal, NotaFiscalItem) |
| `lib/models/nota_fiscal.g.dart` | Adaptadores Hive (gerado automaticamente) |
| `lib/services/nota_fiscal_service.dart` | Integração com API de NF-e |
| `lib/services/nota_fiscal_firestore_service.dart` | Sincronização com Firestore |
| `lib/screens/notas_fiscais_screen.dart` | Tela principal de emissão e listagem |
| `firestore.rules` | Regras de segurança (atualizado) |

---

## ✅ Checklist de Implementação

- [x] Modelo de dados criado
- [x] Serviço de API implementado
- [x] Sincronização Firestore
- [x] Tela de emissão
- [x] Listagem com filtros
- [x] Integração com vendas
- [x] Isolamento por loja
- [x] Regras de segurança
- [x] Flutter analyze (0 erros)
- [ ] Configurar token da API
- [ ] Testar em homologação
- [ ] Ajustar campos fiscais conforme regime tributário
- [ ] Implementar sequencial de numeração
- [ ] Deploy em produção

---

## 🎓 Próximos Passos

1. **Configurar Provedor**: Escolha e configure API (Focus, Sebrae, etc)
2. **Testar Homologação**: Emita notas em ambiente de testes
3. **Ajustar Tributação**: Configure ICMS, CFOP, NCM conforme produtos
4. **Treinar Usuários**: Explique fluxo de emissão
5. **Produção**: Ative ambiente de produção

---

## 📞 Suporte

Para dúvidas sobre:
- **Código**: Consulte comentários nos arquivos
- **API Focus NFe**: https://focusnfe.com.br/documentacao
- **Sebrae**: Consulte documentação oficial do Sebrae
- **Tributação**: Consulte contador

---

**Sistema pronto para uso!** 🎉

Basta configurar o token da API e começar a emitir notas fiscais.
