# Configurações Master

Painel de configurações globais do app, restrito ao root canônico da plataforma.

## Quem acessa

- Autoridade: Firebase Auth + Firestore Rules. Só `masterpalm26@gmail.com` com `email_verified == true`
  (`isRootAdmin()` em `firestore.rules`, `functions/src/rootAccounts.js`).
- Não existe senha master. O cliente apenas espelha a regra do servidor
  (`RoleUtils.isVerifiedRootAccount`) para esconder a tela de quem não é root; quem decide é o Rules.
- Rotas: `/master_config` (e o alias legado `/master_login`, que abre a mesma tela).

## O que fica em `app_config/master_config`

Só os campos de `MasterConfig.allowedFields`:

| Campo | Uso |
|---|---|
| `requirePlanForNewUsers` | Exigir plano para novos usuários |
| `usersWithUnlimitedAccess` | E-mails com acesso ilimitado |
| `globalSettings` | Manutenção, feature flags, telefone de suporte, log de auditoria |
| `lastUpdated`, `updatedBy` | Auditoria da última alteração |

`MasterConfigService.saveMasterConfig` grava só esses campos (`buildWritePayload`); campos legados ou
desconhecidos nunca são regravados. A leitura é sempre do Firestore (sem cache Hive; o box legado
`master_config` é apagado do aparelho na primeira leitura).

## Credenciais

Nenhuma credencial fica neste documento nem no app. O Mercado Pago da plataforma usa o Secret Manager
(`MP_ACCESS_TOKEN`) e a variável `MP_PUBLIC_KEY` das Functions.

## Arquivos

- `lib/models/master_config.dart` — modelo e allowlist
- `lib/services/master_config_service.dart` — leitura/escrita
- `lib/screens/master_config_screen.dart` — painel
- `test/security/master_config_security_test.dart` — testes de segurança
