# Checklist de Deploy APK Android - MasterPalm

## Erro de Login no APK

Se o APK mostra:
- **Login manual:** "Erro de token (reCAPTCHA). Execute: node scripts/disable_recaptcha_auth.js"
- **Login Google:** "Erro ao entrar com Google. Tente novamente."

Siga este checklist.

---

## 1. Login Manual (e-mail/senha)

### Causa
Firebase Auth com **reCAPTCHA Enterprise** ativo exige token no Android. O app mobile não envia esse token automaticamente como o Web.

### Correção
Execute o script (uma vez por projeto):

```bash
cd scripts
npm install   # se ainda não instalou
node disable_recaptcha_auth.js
```

Requer: `scripts/serviceAccountKey.json` (Firebase Console → Configurações → Contas de serviço).

---

## 2. Login Google

### Causa
SHA-1 ou SHA-256 do app não está cadastrado no Firebase/Google Cloud.

### Correção
1. Obtenha o SHA-1 do keystore de debug ou release:
   ```bash
   # Debug (desenvolvimento)
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android

   # Release (produção)
   keytool -list -v -keystore path/to/your/keystore.jks -alias seu_alias
   ```

2. Firebase Console → Configurações do projeto → Seus apps → Android → Adicionar impressão digital (SHA-1 e SHA-256).

3. Google Cloud Console → APIs e serviços → Credenciais → OAuth 2.0 Client IDs → Android → Adicionar SHA-1.

---

## 3. App Check (Debug Token)

Se o erro mencionar "attestation failed" ou "App Check":

1. Rode o app em debug e capture o Debug Token no Logcat:
   ```bash
   adb logcat | grep -i DebugAppCheckProvider
   ```

2. Firebase Console → App Check → Apps → Android → Tokens de depuração → Adicionar token.

---

## 4. Logs de Diagnóstico

No Logcat (Android Studio ou `adb logcat`), filtre por:
- `[LOGIN-ANDROID]` – fluxo login manual
- `[LOGIN-GOOGLE]` – fluxo login Google
- `[LOGIN-FIREBASE]` – chamadas Firebase Auth
- `[LOGIN-TOKEN]` – erros de token/credencial
- `[LOGIN-APPCHECK]` – App Check

Esses logs mostram o código e mensagem exatos do erro.
