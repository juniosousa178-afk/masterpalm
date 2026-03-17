# Sistema de Comissões por Vendedor - MasterPalm

## Visão Geral

Sistema profissional de comissões para vendedores que compartilham o catálogo com clientes.
Quando um vendedor envia o catálogo via link de tracking e o cliente finaliza a compra,
a venda é automaticamente atribuída ao vendedor para cálculo de comissão.

---

## Arquitetura

### Modelos de Dados

| Arquivo | Descrição |
|---------|-----------|
| `lib/models/comissao_config.dart` | Configuração global e por vendedor |
| `lib/models/venda_tracking.dart` | Tracking de links e registro de comissões |

### Serviços

| Arquivo | Descrição |
|---------|-----------|
| `lib/services/tracking_service.dart` | Geração e validação de links de tracking |
| `lib/services/comissao_config_service.dart` | Gerenciamento de configurações |
| `lib/services/comissao_service.dart` | Cálculo e registro de comissões |

### Telas

| Arquivo | Descrição |
|---------|-----------|
| `lib/screens/metas_comissoes_screen.dart` | Painel de metas e comissões |
| `lib/widgets/compartilhar_catalogo_widget.dart` | Botão de compartilhamento |

### Cloud Functions

| Função | Descrição |
|--------|-----------|
| `calcularComissaoPagamento` | Calcula comissão quando pedido é pago |
| `estornarComissaoCancelamento` | Estorna comissão quando pedido é cancelado |
| `sincronizarNovoVendedor` | Cria config de comissão para novos vendedores |

---

## Estrutura Firestore

```
/lojas/{lojaId}/
  ├── configuracoes/
  │   └── comissao                    # Config global de comissões
  ├── comissoes_vendedores/{uid}      # Config por vendedor
  ├── comissoes/{comissaoId}          # Registro de comissões
  ├── trackings/{trackingId}          # Links de tracking
  ├── metas/{metaId}                  # Metas de vendedores
  └── pedidos_pendentes/{pedidoId}    # Pedidos com tracking
```

### Documento: configuracoes/comissao

```json
{
  "lojaId": "abc123",
  "comissaoGlobalPercent": 5.0,
  "apenasAposPagamentoConfirmado": true,
  "excluirFreteDaBase": true,
  "descontoReduzBase": true,
  "trackingExpiracaoDias": 7,
  "regraAtribuicao": "ultimo_clique",
  "bonusMetaBatida100": 1.0,
  "bonusMetaBatida150": 2.0,
  "comissaoMinimaValor": 0.0,
  "comissaoMaximaValor": 0.0,
  "estornoAutomaticoEmCancelamento": true
}
```

### Documento: comissoes/{comissaoId}

```json
{
  "comissaoId": "com_1234567890",
  "lojaId": "abc123",
  "vendaId": "pedido_xyz",
  "vendedorUid": "uid_vendedor",
  "vendedorEmail": "vendedor@email.com",
  "vendedorNome": "João Silva",
  "trackingId": "trk_abc123",
  "subtotalProdutos": 500.00,
  "frete": 25.00,
  "desconto": 50.00,
  "totalVenda": 475.00,
  "baseComissao": 450.00,
  "comissaoPercentual": 5.0,
  "comissaoValor": 22.50,
  "status": "confirmado",
  "origem": "catalogo",
  "statusPagamentoVenda": "pago",
  "dataVenda": "2024-01-15T10:30:00Z",
  "dataConfirmacao": "2024-01-15T10:35:00Z"
}
```

### Documento: trackings/{trackingId}

```json
{
  "trackingId": "trk_abc123def456",
  "lojaId": "abc123",
  "vendedorUid": "uid_vendedor",
  "vendedorEmail": "vendedor@email.com",
  "vendedorNome": "João Silva",
  "token": "hash_validacao_32chars",
  "clienteTelefone": "5533999999999",
  "clienteNome": "Maria Cliente",
  "criadoEm": "2024-01-15T10:00:00Z",
  "expiraEm": "2024-01-22T10:00:00Z",
  "utilizado": false,
  "vendaId": null,
  "origem": "whatsapp"
}
```

---

## Fluxo de Funcionamento

### 1. Vendedor Compartilha Catálogo

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   App Vendedor  │────▶│  TrackingService │────▶│   Firestore     │
│  "Enviar Catálogo"│   │  gerarLink()     │     │  /trackings/    │
└─────────────────┘     └──────────────────┘     └─────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│ Link gerado:                                                     │
│ https://mastepalm.com.br/loja/ABC123?v=UID&t=TOKEN&tid=TRK_ID  │
└─────────────────────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────┐
│    WhatsApp     │
│   Compartilhar  │
└─────────────────┘
```

### 2. Cliente Compra pelo Link

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Catálogo Web   │────▶│  Validar Tracking │────▶│   Checkout      │
│  (com params)   │     │  (v, t, tid)      │     │  + vendedorId   │
└─────────────────┘     └──────────────────┘     └─────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│ Pedido salvo com:                                                │
│ - vendedorUid                                                    │
│ - vendedorNome                                                   │
│ - trackingId                                                     │
│ - origem: "catalogo"                                             │
└─────────────────────────────────────────────────────────────────┘
```

### 3. Pagamento Confirmado → Comissão Calculada

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│ Pedido status   │────▶│  Cloud Function  │────▶│   Firestore     │
│ = "pago"        │     │  calcularComissao│     │  /comissoes/    │
└─────────────────┘     └──────────────────┘     └─────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────────────────────┐
│ Comissão registrada:                                             │
│ - baseComissao = subtotal - desconto (sem frete)                │
│ - comissaoValor = baseComissao * percentual%                    │
│ - status = "confirmado"                                          │
└─────────────────────────────────────────────────────────────────┘
```

---

## Regras de Cálculo

### Base de Comissão (Padrão Recomendado)

```
baseComissao = subtotalProdutos - desconto
```

- **Frete**: Não entra na base (configurável)
- **Desconto**: Reduz a base (configurável)

### Percentual de Comissão

1. Usa percentual específico do vendedor (se configurado)
2. Senão, usa percentual global da loja
3. Aplica bônus se meta foi batida:
   - Meta 100% → +1% (configurável)
   - Meta 150% → +2% (configurável)

### Limites

- Comissão mínima por venda (R$)
- Comissão máxima por venda (R$)

---

## Regras de Tracking

### Expiração
- Padrão: 7 dias (configurável)
- Após expirar, link não atribui mais vendas ao vendedor

### Atribuição (Last-Click vs First-Click)

| Regra | Descrição |
|-------|-----------|
| `ultimo_clique` | Usa o tracking mais recente válido (padrão) |
| `primeiro_clique` | Usa o primeiro tracking válido |

### Múltiplos Vendedores
Se cliente recebeu link de 2+ vendedores:
- Aplica a regra de atribuição configurada
- Apenas UM vendedor recebe a comissão

---

## Segurança (Firestore Rules)

### Comissões
```javascript
match /comissoes/{comissaoId} {
  // Vendedor só lê suas próprias comissões
  allow read: if isAdminOrSystem()
    || (isSignedIn() && resource.data.vendedorUid == request.auth.uid);
  // Apenas sistema pode criar/atualizar
  allow create: if isSignedIn();
  allow update, delete: if isAdminOrSystem();
}
```

### Configurações
```javascript
match /configuracoes/comissao {
  allow read: if isSignedIn();
  allow write: if isAdminOrSystem();
}

match /comissoes_vendedores/{vendedorUid} {
  allow read: if isAdminOrSystem()
    || (isSignedIn() && request.auth.uid == vendedorUid);
  allow write: if isAdminOrSystem();
}
```

---

## Integração no App

### Adicionar Tela de Metas/Comissões ao Menu

```dart
// No menu principal ou drawer
ListTile(
  leading: const Icon(Icons.trending_up),
  title: const Text('Metas & Comissões'),
  onTap: () => Navigator.pushNamed(context, '/metas-comissoes'),
),
```

### Adicionar Rota

```dart
// Em routes.dart ou main.dart
'/metas-comissoes': (context) => const MetasComissoesScreen(),
```

### Registrar Hive Adapters

```dart
// Em main.dart, antes de runApp()
Hive.registerAdapter(ComissaoConfigAdapter());
Hive.registerAdapter(ComissaoVendedorAdapter());
Hive.registerAdapter(VendaTrackingAdapter());
Hive.registerAdapter(ComissaoVendaAdapter());
```

---

## Deploy

### 1. Firestore Rules

```bash
cd c:\Users\Pichau\apk_nathy\temp_naty
firebase deploy --only firestore:rules
```

### 2. Cloud Functions

```bash
cd main
npm install
firebase deploy --only functions
```

---

## Checklist de Testes

### Fluxo do Vendedor

- [ ] Login como vendedor
- [ ] Acessar tela de Metas & Comissões
- [ ] Clicar em "Enviar Catálogo"
- [ ] Preencher dados do cliente (opcional)
- [ ] Compartilhar via WhatsApp
- [ ] Verificar link gerado contém parâmetros (v, t, tid)

### Fluxo do Cliente

- [ ] Abrir link no navegador
- [ ] Verificar catálogo carrega corretamente
- [ ] Adicionar produtos ao carrinho
- [ ] Finalizar compra
- [ ] Verificar pedido salvo com vendedorUid

### Fluxo de Comissão

- [ ] Confirmar pagamento do pedido (mudar status para "pago")
- [ ] Verificar Cloud Function executou (logs)
- [ ] Verificar comissão criada em /comissoes/
- [ ] Verificar tracking marcado como utilizado
- [ ] Vendedor vê comissão na tela de Metas

### Fluxo Admin

- [ ] Login como admin
- [ ] Acessar Metas & Comissões
- [ ] Ver lista de vendedores
- [ ] Editar percentual de comissão de vendedor
- [ ] Alterar configurações globais
- [ ] Salvar configurações

### Estorno

- [ ] Cancelar um pedido com comissão
- [ ] Verificar comissão estornada automaticamente
- [ ] Vendedor não vê mais comissão pendente

### Segurança

- [ ] Vendedor NÃO consegue ver comissões de outros
- [ ] Vendedor NÃO consegue editar configurações
- [ ] Admin consegue ver todas comissões
- [ ] Admin consegue editar configurações

---

## Troubleshooting

### Comissão não foi calculada

1. Verificar se pedido tem `vendedorUid`
2. Verificar se status mudou para `pago`
3. Verificar logs da Cloud Function
4. Verificar se vendedor tem config em `/comissoes_vendedores/`

### Link de tracking não funciona

1. Verificar se tracking existe em `/trackings/`
2. Verificar se não expirou (`expiraEm`)
3. Verificar se token é válido
4. Verificar parâmetros na URL (v, t, tid)

### Vendedor não vê comissões

1. Verificar se `vendedorUid` no pedido corresponde ao UID do vendedor
2. Verificar Firestore Rules
3. Verificar se comissão está em `/comissoes/` com status correto

---

## Arquivos Criados/Modificados

### Novos Arquivos

```
lib/models/comissao_config.dart
lib/models/comissao_config.g.dart
lib/models/venda_tracking.dart
lib/models/venda_tracking.g.dart
lib/services/tracking_service.dart
lib/services/comissao_config_service.dart
lib/services/comissao_service.dart
lib/screens/metas_comissoes_screen.dart
lib/widgets/compartilhar_catalogo_widget.dart
```

### Arquivos Modificados

```
firestore.rules                          # Regras de segurança
main/index.js                            # Cloud Functions
lib/services/catalogo_venda_service.dart # Tracking na venda
```

---

## Contato

Sistema desenvolvido para MasterPalm.
Em caso de dúvidas, consulte a documentação ou os arquivos de código.
