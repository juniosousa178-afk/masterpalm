# 🔐 Configurações Master - MasterPalm

## Visão Geral

O sistema de **Configurações Master** é uma tela exclusiva para o programador root (`masterpalm@gmail.com`) que permite controlar configurações globais do aplicativo, gerenciar usuários e configurar integrações de pagamento.

## 🔑 Acesso

### Credenciais Master
- **E-mail**: `masterpalm@gmail.com`
- **Senha Master Padrão**: `030419922009jj`

### Como Acessar

1. Faça login no app com `masterpalm@gmail.com`
2. No menu lateral, procure por **"Configurações Master"** (em vermelho)
3. Clique e será solicitada a senha master
4. Digite a senha: `030419922009jj`
5. Você será direcionado para o painel de controle master

## 📋 Funcionalidades

### 1. Mercado Pago - Assinaturas

Configure as chaves da API do Mercado Pago para receber pagamentos de assinaturas:

- **Access Token**: Token de acesso para processar pagamentos
- **Public Key**: Chave pública para checkout

**Como obter as chaves:**
1. Acesse: https://www.mercadopago.com.br/developers
2. Vá em "Suas integrações" → "Credenciais"
3. Copie o Access Token e Public Key
4. Cole na tela de Configurações Master
5. Clique em "Salvar Chaves do Mercado Pago"

### 2. Usuários com Acesso Ilimitado

Conceda acesso ilimitado a usuários específicos sem necessidade de plano ativo:

**Adicionar usuário:**
1. Digite o e-mail do usuário
2. Clique em "Adicionar"
3. O usuário poderá usar o app sem restrições de plano

**Remover acesso:**
1. Clique no ícone de lixeira ao lado do e-mail
2. Confirme a remoção
3. O usuário voltará a precisar de um plano ativo

**Casos de uso:**
- Lojas de teste/demonstração
- Parceiros comerciais
- Equipe interna
- Usuários beta testers

### 3. Configurações Globais

**Exigir plano para novos usuários:**
- `ON`: Novos usuários precisam assinar um plano para usar o app
- `OFF`: Novos usuários podem usar o app livremente (não recomendado)

### 4. Segurança

**Alterar Senha Master:**
1. Clique em "Alterar Senha Master"
2. Digite a senha atual
3. Digite a nova senha (mínimo 8 caracteres)
4. Confirme a nova senha
5. A senha será atualizada localmente (Hive) e no Firestore

**IMPORTANTE:** Não perca a senha master! Ela é necessária para acessar as configurações.

## 💾 Armazenamento

As configurações master são armazenadas em **dois locais**:

1. **Hive (Local)**: Cache offline para acesso rápido
2. **Firestore**: `/app_config/master_config` - Sincronização na nuvem

### Sincronização Automática

- Toda alteração é salva localmente primeiro
- Depois sincronizada automaticamente com o Firestore
- Outras instâncias do app carregarão as configurações atualizadas

## 🔒 Segurança

### Controle de Acesso

- **Apenas** o e-mail `masterpalm@gmail.com` pode acessar
- Senha master obrigatória para entrar nas configurações
- Senha armazenada de forma segura no Firestore
- Logs de auditoria com quem fez cada alteração

### Firestore Rules

As configurações master estão protegidas por regras do Firestore:

```javascript
match /app_config/{doc} {
  allow read, write: if request.auth.token.email == 'masterpalm@gmail.com';
}
```

## 📁 Arquivos do Sistema

### Modelo de Dados
- `lib/models/master_config.dart` - Modelo Hive/Firestore
- `lib/models/master_config.g.dart` - Gerado pelo build_runner

### Serviço
- `lib/services/master_config_service.dart` - Lógica de negócio

### Telas
- `lib/screens/master_login_screen.dart` - Tela de login master
- `lib/screens/master_config_screen.dart` - Painel de configurações

### Integração
- `lib/main.dart` - Registro do adapter Hive e rotas

## 🚀 Fluxo de Uso

### Configuração Inicial (Primeira Vez)

1. **Login no App**
   ```
   E-mail: masterpalm@gmail.com
   Senha: (sua senha do Firebase)
   ```

2. **Acessar Configurações Master**
   - Menu lateral → "Configurações Master"
   - Senha: `030419922009jj`

3. **Configurar Mercado Pago**
   - Cole Access Token e Public Key
   - Salvar

4. **Configurar Políticas**
   - Decidir se novos usuários precisam de plano
   - Adicionar usuários com acesso ilimitado (se necessário)

### Gerenciamento Contínuo

**Liberar acesso para uma loja de teste:**
```
1. Configurações Master
2. Seção "Usuários com Acesso Ilimitado"
3. Digite: loja.teste@example.com
4. Adicionar
```

**Renovar/Gerenciar Planos:**
- Use a tela "Planos" no menu admin
- Ou a tela "Admin Usuários" para gerenciar manualmente

**Alterar Chaves do Mercado Pago:**
```
1. Configurações Master
2. Atualizar Access Token / Public Key
3. Salvar
```

## ⚙️ API do Serviço

### Métodos Principais

```dart
// Carregar configuração
final config = await MasterConfigService.loadMasterConfig();

// Validar senha
final isValid = await MasterConfigService.validateMasterPassword('senha');

// Atualizar senha
await MasterConfigService.updateMasterPassword(
  oldPassword: 'antiga',
  newPassword: 'nova',
  updatedBy: 'masterpalm@gmail.com',
);

// Conceder acesso ilimitado
await MasterConfigService.grantUnlimitedAccess(
  userEmail: 'usuario@example.com',
  grantedBy: 'masterpalm@gmail.com',
);

// Revogar acesso ilimitado
await MasterConfigService.revokeUnlimitedAccess(
  userEmail: 'usuario@example.com',
  revokedBy: 'masterpalm@gmail.com',
);

// Verificar se tem acesso ilimitado
final hasAccess = await MasterConfigService.hasUnlimitedAccess('email@example.com');

// Atualizar chaves do Mercado Pago
await MasterConfigService.updateMercadoPagoKeys(
  accessToken: 'APP-xxx',
  publicKey: 'APP_USR-xxx',
  updatedBy: 'masterpalm@gmail.com',
);

// Obter tokens do Mercado Pago
final accessToken = await MasterConfigService.getMercadoPagoAccessToken();
final publicKey = await MasterConfigService.getMercadoPagoPublicKey();

// Stream de configurações (para UI reativa)
MasterConfigService.streamMasterConfig().listen((config) {
  print('Config atualizada: ${config.mercadoPagoAccessToken}');
});
```

## 🐛 Troubleshooting

### Esqueci a senha master

1. Acesse o Firestore Console
2. Vá em `/app_config/master_config`
3. Edite o campo `masterPassword`
4. Salve
5. Reinicie o app para carregar a nova senha

### Configurações não estão sincronizando

1. Verifique a conexão com internet
2. Verifique as regras do Firestore
3. Veja os logs do app para erros
4. Tente recarregar (botão de refresh no app bar)

### Usuário não consegue usar app mesmo com acesso ilimitado

1. Verifique se o e-mail está correto na lista
2. Peça para o usuário fazer logout e login novamente
3. Verifique se o documento do usuário no Firestore tem `unlimitedAccess: true`

## 📊 Estrutura de Dados

### MasterConfig (Hive + Firestore)

```dart
{
  "masterPassword": "030419922009jj",
  "mercadoPagoAccessToken": "APP-xxx",
  "mercadoPagoPublicKey": "APP_USR-xxx",
  "requirePlanForNewUsers": true,
  "usersWithUnlimitedAccess": [
    "loja1@example.com",
    "loja2@example.com"
  ],
  "globalSettings": {
    "custom_key": "custom_value"
  },
  "lastUpdated": "2025-12-28T20:00:00.000Z",
  "updatedBy": "masterpalm@gmail.com"
}
```

### Documento do Usuário (Firestore)

Quando um usuário recebe acesso ilimitado, seu documento é atualizado:

```javascript
/usuarios/{email}
{
  "email": "usuario@example.com",
  "unlimitedAccess": true,
  "grantedBy": "masterpalm@gmail.com",
  "grantedAt": Timestamp
}
```

## ✅ Checklist de Implementação

- [x] Modelo `MasterConfig` com Hive + Firestore
- [x] Serviço `MasterConfigService` completo
- [x] Tela de login master com validação de senha
- [x] Tela de configurações master com todas as seções
- [x] Integração com Mercado Pago (tokens)
- [x] Gerenciamento de usuários com acesso ilimitado
- [x] Alteração de senha master
- [x] Sincronização Hive ↔ Firestore
- [x] Controle de acesso (apenas masterpalm@gmail.com)
- [x] Botão vermelho no menu lateral
- [x] Rotas registradas no app
- [x] Adapter Hive registrado
- [x] Logs de auditoria (updatedBy, lastUpdated)

## 🎯 Próximos Passos Recomendados

1. **Adicionar mais integrações de pagamento:**
   - PagSeguro
   - Ton
   - InfinitePay

2. **Expandir configurações globais:**
   - Configurações de e-mail
   - Configurações de notificações push
   - Limites de uso por plano

3. **Dashboard de métricas:**
   - Total de usuários ativos
   - Receita de assinaturas
   - Taxa de conversão

4. **Backup automático:**
   - Exportar configurações
   - Restaurar de backup

---

**Status**: ✅ 100% Implementado e Funcional

**Última atualização**: 28/12/2025
