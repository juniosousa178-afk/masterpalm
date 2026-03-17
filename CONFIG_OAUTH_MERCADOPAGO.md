# Configuração OAuth Mercado Pago (Conexão com 1 clique)

Para permitir que o botão "Conectar com Mercado Pago" funcione sem copiar/colar token:

## 1. Obter credenciais no Mercado Pago

1. Acesse [Suas integrações](https://www.mercadopago.com.br/developers/panel/app)
2. Crie ou selecione uma aplicação
3. Vá em **Detalhes da aplicação** → **Credenciais**
4. Copie o **App ID** (client_id) e o **Client Secret**

## 2. Configurar URL de redirecionamento no Mercado Pago

1. Em **Detalhes da aplicação** → **URLs de redirecionamento**
2. Adicione exatamente:
   ```
   https://southamerica-east1-masterpalm-58c46.cloudfunctions.net/mpOAuthCallback
   ```
3. Salve

## 3. Configurar secrets no Firebase

```bash
firebase functions:secrets:set MP_APP_ID
# Cole o App ID (número da aplicação) quando solicitado

firebase functions:secrets:set MP_CLIENT_SECRET
# Cole o Client Secret quando solicitado
```

## 4. Deploy das funções OAuth

```bash
cd functions
npm run deploy
# Ou deploy apenas das funções OAuth:
firebase deploy --only functions:mpOAuthInit,functions:mpOAuthCallback
```

## Fluxo

1. Usuário toca em "Conectar com Mercado Pago" no app
2. Abre o navegador → redireciona para o Mercado Pago
3. Usuário autoriza a aplicação
4. Mercado Pago redireciona para nossa Cloud Function
5. Function troca o código por access_token e salva no Firestore
6. Usuário redirecionado para página de sucesso: "Conectado! Feche e volte ao app"
7. Ao voltar ao app, os dados são atualizados automaticamente

## Fallback: token manual

Se o OAuth não estiver configurado, o usuário pode usar "Ou conectar com token manual" para colar o Access Token manualmente.
