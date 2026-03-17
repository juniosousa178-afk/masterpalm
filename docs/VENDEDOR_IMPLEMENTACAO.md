# Implementação do Perfil VENDEDOR - MasterPalm

## Arquitetura Final

### Coleções Firestore

```
lojas/{lojaId}/
├── vendedores/{vendedorUid}     # ✅ NOVO: Perfil do vendedor
│   ├── email
│   ├── nome
│   ├── telefone
│   ├── storeId                   # Loja vinculada (OBRIGATÓRIO)
│   ├── adminUid                  # UID do admin que cadastrou
│   ├── adminEmail
│   ├── ativo                     # true/false
│   ├── permissoes                # Map<String, bool> - permissões dinâmicas
│   ├── comissaoPercentual        # null = usa global
│   ├── criadoEm
│   └── atualizadoEm
│
├── notificacoes/{notifId}        # ✅ NOVO: Notificações
│   ├── destinatarioUid
│   ├── destinatarioEmail
│   ├── tipo                      # novaVenda | vendaConfirmada | vendaCancelada
│   ├── titulo
│   ├── mensagem
│   ├── pedidoId
│   ├── vendaId
│   ├── storeId
│   ├── valor                     # Apenas para admin
│   ├── comissao                  # Apenas para vendedor
│   ├── lida
│   └── criadaEm
│
├── pre_pedidos/{pedidoId}        # Atualizado com vendedorRef
│   ├── ...campos existentes...
│   ├── vendedorRef               # ✅ UID do vendedor (se vier do link)
│   └── temComissao               # ✅ true se vendedorRef presente
│
└── members/{memberId}            # Legado - mantido para compatibilidade
```

### Campos Essenciais

| Campo | Descrição | Obrigatório |
|-------|-----------|-------------|
| `storeId` | ID da loja vinculada | SIM |
| `vendedorRef` | UID do vendedor na venda | Para comissão |
| `temComissao` | Flag de comissão | Automático |
| `permissoes` | Map de permissões | SIM |
| `ativo` | Status do vendedor | SIM |

### Fluxo Completo

```
LINK → PEDIDO → CONFIRMAÇÃO → VENDA → COMISSÃO → NOTIFICAÇÃO

1. Vendedor compartilha: /loja/{storeId}?ref={vendedorUid}
2. Cliente acessa catálogo da loja do ADMIN
3. Cliente finaliza compra
4. Sistema:
   - Valida se vendedorRef pertence à loja (anti-fraude)
   - Cria pré-pedido com vendedorRef
   - Notifica ADMIN: "Nova venda recebida"
5. ADMIN confirma venda:
   - Baixa estoque
   - Gera código de campanha (se ativa)
   - Salva venda com vendedorRef
   - Atualiza histórico do cliente
   - Gera comissão para vendedor
6. Sistema notifica VENDEDOR: "Venda confirmada - Comissão R$ X"
```

---

## Arquivos Criados/Modificados

### Novos Arquivos

| Arquivo | Descrição |
|---------|-----------|
| `lib/services/vendedor_service.dart` | Serviço centralizado de vendedores |
| `lib/services/notificacao_vendas_service.dart` | Notificações de vendas |
| `lib/widgets/vendedor_aguarde_widget.dart` | Tela "aguarde liberação" |
| `lib/screens/gerenciar_vendedores_screen.dart` | Admin gerencia vendedores |

### Arquivos Modificados

| Arquivo | Alteração |
|---------|-----------|
| `lib/services/permissao_service.dart` | Permissões dinâmicas via Firestore |
| `lib/services/pre_pedido_service.dart` | vendedorRef + notificações |
| `lib/screens/home_screen.dart` | Verificação de permissões vendedor |
| `lib/screens/pre_pedidos_screen.dart` | Bloqueio para vendedor |
| `lib/screens/app_start_router.dart` | Bypass de plano para vendedor |
| `firestore.rules` | Regras para vendedores e notificações |

---

## Passos de Teste

### 1. Vendedor recém-cadastrado: login sem tela de planos

```
SETUP:
1. Admin cria vendedor via /cadastro_usuario
2. Vendedor faz logout e login

ESPERADO:
✅ Vendedor faz login normalmente
✅ NÃO vê tela de planos
✅ NÃO precisa escolher/pagar plano
✅ Usa automaticamente o plano da loja do admin
```

### 2. Vendedor sem telas liberadas: só mensagem "aguarde liberação"

```
SETUP:
1. Admin cadastra vendedor SEM liberar nenhuma permissão
2. Vendedor faz login

ESPERADO:
✅ Vendedor vê tela "Aguarde liberação do administrador"
✅ Pode ver/copiar seu link do catálogo
✅ NÃO vê menu do app
✅ NÃO acessa nenhuma funcionalidade
```

### 3. Admin libera uma tela depois: vendedor passa a ver sem recadastrar

```
SETUP:
1. Admin acessa Gerenciar Vendedores
2. Libera permissão "vendas" para o vendedor
3. Vendedor atualiza/reabre o app

ESPERADO:
✅ Vendedor agora vê menu com opção "Vendas"
✅ Pode registrar vendas
✅ Outras telas continuam bloqueadas
```

### 4. Link do vendedor abre loja correta e registra ref

```
SETUP:
1. Vendedor copia link: /loja/{storeId}?ref={vendedorUid}
2. Cliente abre link no navegador

ESPERADO:
✅ Abre catálogo da loja do ADMIN
✅ WhatsApp vai para número do ADMIN
✅ vendedorRef é registrado no carrinho
✅ vendedorRef aparece no pré-pedido
```

### 5. Venda via gateway pelo link do vendedor gera comissão e notifica admin

```
SETUP:
1. Cliente acessa link do vendedor
2. Finaliza compra com pagamento via Mercado Pago
3. Gateway confirma pagamento

ESPERADO:
✅ Pré-pedido criado com vendedorRef
✅ Admin recebe notificação "Nova venda PAGA recebida!"
✅ Notificação mostra nome do vendedor
✅ vendedorRef validado (pertence à loja)
```

### 6. Admin confirma: baixa estoque + salva venda + campanha + histórico

```
SETUP:
1. Admin acessa Pré-Pedidos
2. Confirma pedido com vendedorRef

ESPERADO:
✅ Estoque é baixado
✅ Venda é registrada com vendedorRef
✅ Se campanha ativa: código gerado
✅ Histórico do cliente atualizado
✅ Comissão calculada e registrada
```

### 7. Vendedor recebe notificação de CONFIRMADA

```
SETUP:
1. Admin confirma pedido do vendedor

ESPERADO:
✅ Vendedor recebe notificação no app
✅ Título: "Venda confirmada!"
✅ Mostra apenas comissão (NÃO mostra valor total)
✅ Mostra nome do cliente
```

### 8. Admin cancela: vendedor recebe notificação de CANCELADA

```
SETUP:
1. Admin cancela pedido do vendedor

ESPERADO:
✅ Vendedor recebe notificação no app
✅ Título: "Venda cancelada"
✅ Mostra motivo (se houver)
✅ NÃO mostra valores
```

### 9. Vendedor nunca vê valores globais e nunca acessa pré-pedidos

```
SETUP:
1. Vendedor tenta acessar via URL direta

ESPERADO:
✅ Tela de relatórios financeiros: mostra apenas % de progresso, SEM R$
✅ Tela de pré-pedidos: acesso negado, volta para home
✅ Firestore rules: permission-denied se tentar ler pre_pedidos
```

---

## Comandos para Deploy

### 1. Deploy Firestore Rules

```bash
cd c:\Users\Pichau\apk_nathy\temp_naty
firebase deploy --only firestore:rules
```

### 2. Build APK

```bash
flutter build apk --release
```

### 3. Build Web

```bash
flutter build web
firebase deploy --only hosting
```

---

## Permissões do Vendedor

### Sempre Ativas
- `meu_perfil`: Ver próprio perfil
- `minhas_comissoes`: Ver próprias comissões
- `meu_link`: Ver/copiar link do catálogo

### Liberáveis pelo Admin
- `catalogo`: Ver catálogo de produtos
- `vendas`: Registrar vendas
- `estoque`: Gerenciar estoque
- `clientes`: Gerenciar clientes
- `historico_cliente`: Ver histórico

### NUNCA Liberáveis (Bloqueadas)
- `pre_pedidos`: ❌
- `confirmar_compra`: ❌
- `valores_globais`: ❌
- `relatorios`: ❌
- `relatorio_financeiro`: ❌
- `precificacao`: ❌
- `fornecedores`: ❌
- `cadastro_usuarios`: ❌
- `configuracoes`: ❌
- `licenca`: ❌
- `backup`: ❌
- `canais`: ❌
- `cupons`: ❌
- `campanhas`: ❌

---

## Hierarquia

```
PROGRAMADOR (root)
    │
    ├── Acesso total a TODAS as lojas
    ├── Pode criar admins
    └── Bypass de TUDO

ADMIN (dono da loja)
    │
    ├── Acesso total à SUA loja
    ├── Pode criar vendedores
    ├── Confirma pré-pedidos
    ├── Vê valores globais
    └── Gerencia permissões

VENDEDOR (subordinado)
    │
    ├── Acesso APENAS à loja do admin
    ├── Permissões dinâmicas
    ├── NÃO vê pré-pedidos
    ├── NÃO confirma compras
    ├── NÃO vê valores globais
    └── Gera comissão via link
```
