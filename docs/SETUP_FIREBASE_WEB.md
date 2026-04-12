# Configuração Firebase – Web (MasterPalm)

## Domínio autorizado para OAuth (Auth)

Para login social (Google, etc.) e redirecionamento funcionarem no catálogo/app Web, o domínio deve estar autorizado no Firebase:

1. Abra [Firebase Console](https://console.firebase.google.com) → seu projeto.
2. **Authentication** → **Settings** (Settings / Configurações) → aba **Authorized domains**.
3. Adicione o domínio do app Web, por exemplo:
   - **`app.masterpalm.com.br`** (canônico do SPA admin — ver `docs/DOMAIN_APP_WEB.md`)
   - `app.mastepalm.com.br` (legado / typo, enquanto houver tráfego)
   - `mastepalm.web.app`
   - `masterpalm-58c46.web.app`
   - `localhost` (desenvolvimento)

**Hosting:** o que o `firebase.json` publica é o conteúdo de `build/web` nos sites configurados; o hostname que o usuário acessa vem dos **domínios personalizados** ligados a cada site no Console. Detalhes e checklist de infra: `docs/DOMAIN_APP_WEB.md` (seção Firebase Hosting).

Se o domínio não estiver na lista, você verá no console do navegador:

> "The current domain is not authorized for OAuth operations. Add your domain to the OAuth redirect domains list in the Firebase console → Authentication → Settings → Authorized domains."

**Isso não bloqueia o app:** o catálogo continua funcionando; apenas login com popup/redirect OAuth pode falhar até o domínio ser adicionado.

---

## Google Sign-In no catálogo (Web) – Client ID do tipo “Aplicativo da Web”

Se ao clicar em **“Entrar com Google”** no catálogo (Web) aparecer:

- **“Acesso bloqueado: erro de autorização”**  
- **“Storagerelay URI is not allowed for 'NATIVE_ANDROID' client type”**

significa que no `web/index.html` está sendo usado um **Client ID do Android**. Na Web é obrigatório usar um Client ID do tipo **Aplicativo da Web**.

### O que fazer

1. Abra [Google Cloud Console](https://console.cloud.google.com) → seu projeto → **APIs e serviços** → **Credenciais**.
2. **Criar credenciais** → **ID do cliente OAuth 2.0**.
3. Tipo de aplicativo: **Aplicativo da Web** (não “Android”).
4. Em **Origens JavaScript autorizadas** adicione:
   - `http://localhost`
   - `http://localhost:PORTA` (ex.: `http://localhost:62785` para desenvolvimento)
   - Seu domínio em produção (ex.: `https://app.masterpalm.com.br`)
5. Salve e copie o **Client ID** (termina em `.apps.googleusercontent.com`).
6. No projeto, em **web/index.html**, na meta tag `google-signin-client_id`, substitua o valor pelo **Client ID do Aplicativo da Web** (não use o do Android).

Assim o “Entrar com Google” no navegador passa a usar o cliente correto e o erro de autorização deixa de ocorrer.

---

## Redefinir senha do cliente no catálogo (Web)

No catálogo Web, o cliente pode usar **“Esqueci a senha”** e receber o código por email. O envio é feito pela Cloud Function `solicitarRedefinicaoSenhaCatalogo`, que precisa das variáveis de ambiente de SMTP:

- **SMTP_EMAIL** – email Gmail usado para enviar (ex.: `masterpalm26@gmail.com`)
- **SMTP_PASSWORD** – senha de app do Gmail (não a senha normal da conta)

**Em desenvolvimento (emulador):** crie ou edite o arquivo `functions/.env` e adicione:

```
SMTP_EMAIL=seu_email@gmail.com
SMTP_PASSWORD=senha_de_app_do_gmail
```

**Em produção:** a função usa **Secret Manager**. Crie os secrets em [Secret Manager](https://console.cloud.google.com/security/secret-manager?project=masterpalm-58c46): `SMTP_EMAIL` (valor = email Gmail) e `SMTP_PASSWORD` (valor = senha de app). Depois: `firebase deploy --only functions:solicitarRedefinicaoSenhaCatalogo`. Sem essas variáveis, a função retorna erro e o cliente vê “Envio de email não configurado no servidor”.
