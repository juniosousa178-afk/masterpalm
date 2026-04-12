# Login Web – avisos no console

## O que os logs mostram

- **Boot**: normal (Firebase, Auth, Hive, loja reutilizada, reconciliação).
- **"Cross-Origin-Opener-Policy policy would block the window.postMessage call"**: aviso do **login com Google** (popup). O header `same-origin-allow-popups` já permite o popup; o login costuma funcionar.
- **"Framing 'https://accounts.google.com/' violates... frame-ancestors 'self'" (report-only)**: CSP em modo **report-only**; só registra, não bloqueia. Pode ser ignorado.
- **POST identitytoolkit... 400 (Bad Request)**: ocorre no **login por e-mail/senha**. Pode ser:
  - **E-mail ou senha incorretos** → o app agora mostra "E-mail ou senha incorretos" (ou mensagem de reCAPTCHA se for o caso).
  - **Falha no reCAPTCHA/App Check** (web) → tentar outro navegador ou desativar bloqueador de pop-up; no Firebase Console conferir App Check / reCAPTCHA Enterprise.

## Configuração atual

No `firebase.json`, o hosting já envia o header correto para permitir o popup do Google:

```json
"Cross-Origin-Opener-Policy": "same-origin-allow-popups"
```

Com `same-origin-allow-popups`, o popup do OAuth **pode** comunicar com a janela que o abriu; o login costuma funcionar mesmo com o aviso no console.

## O que conferir

1. **Header na sua URL**  
   Abra **https://app.masterpalm.com.br/** (domínio canônico do app Web; se ainda houver tráfego no legado, teste também `https://app.mastepalm.com.br/`). DevTools → **Network** → recarregue → clique na primeira requisição (documento HTML). Em **Response Headers** deve aparecer:
   ```http
   Cross-Origin-Opener-Policy: same-origin-allow-popups
   ```
   Se você usa domínio customizado (canônico: **app.masterpalm.com.br**; legado: app.mastepalm.com.br) e um CDN/proxy na frente do Firebase Hosting, esse header precisa ser repassado (ou configurado no CDN).

2. **Login com Google**  
   Se o login com Google conclui e você entra no app, o aviso é apenas informativo e pode ser ignorado.

3. **Se o login falhar ou o popup fechar sem retorno**  
   Pode ser bloqueio por COOP (por exemplo se o header estiver como `same-origin` **sem** `-allow-popups`, ou se não estiver sendo enviado). Ajuste o header para `same-origin-allow-popups` na origem que serve o app.

## Alternativa: login por redirect (sem popup)

Para eliminar o aviso e não depender de popup/postMessage, é possível usar fluxo por **redirect** na web (pacote `google_sign_in_web_redirect` ou Firebase Auth `signInWithRedirect` / `getRedirectResult`). Isso exige mudança no fluxo de login (redirect em vez de popup) e configuração de redirect URI no Google Cloud Console.
