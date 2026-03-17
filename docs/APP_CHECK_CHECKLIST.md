# Checklist – Firebase App Check (MasterPalm)

Este documento guia a validação e ativação do App Check em modo monitoramento até estar seguro aplicar enforcement.

---

## 1. Registrar Debug Token (Android / iOS)

### Android

1. Execute o app em modo **debug** ou **profile** em dispositivo/emulador.
2. Obtenha o token no logcat:
   ```bash
   adb logcat | grep -i DebugAppCheckProvider
   ```
   Ou no Android Studio: Logcat → filtrar por `"debug secret"` ou `"App Check"`.
3. Copie o token (formato longo, ex: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`).
4. No Firebase Console:
   - **App Check** → **Apps** → selecione o app **Android**
   - **Tokens de depuração** → **Adicionar token de depuração**
   - Cole o token e salve.

### iOS

1. Execute o app em modo **debug** ou **profile** no simulador ou dispositivo.
2. O token aparece no console do Xcode ao rodar o app.
3. No Firebase Console:
   - **App Check** → **Apps** → selecione o app **iOS**
   - **Tokens de depuração** → **Adicionar token de depuração**
   - Cole o token e salve.

---

## 2. Configurar reCAPTCHA v3 (Web)

1. Acesse [Google reCAPTCHA Admin](https://www.google.com/recaptcha/admin/create).
2. Crie uma chave **reCAPTCHA v3**.
3. Adicione os domínios onde o app web roda (ex: `app.mastepalm.com.br`, `localhost`).
4. Use uma das opções:
   - **Remote Config**: chave `recaptcha_site_key` no Firebase Remote Config.
   - **Código**: preencha `kRecaptchaSiteKeyOverride` em `lib/config/app_check_config.dart`.
5. Registre no Firebase Console:
   - **App Check** → **Apps** → app **Web**
   - **Registrar** → selecione **reCAPTCHA Enterprise** ou **reCAPTCHA v3** e informe a chave.

---

## 3. Verificar % de solicitações verificadas

1. No Firebase Console: **App Check** → **APIs** (ou **Visão geral**).
2. Para **Firestore** e **Storage**, verifique a coluna **Solicitações verificadas**.
3. Objetivo: atingir **≥ 95%** antes de aplicar enforcement.
4. Se estiver baixo (ex: 4%):
   - Certifique-se de que o Debug Token está registrado (para builds debug/profile).
   - Verifique se o app de release (Play Store) está com SHA-1/SHA-256 cadastrados no projeto Firebase.
   - Para Web, confirme que a chave reCAPTCHA está correta e os domínios incluídos.

---

## 4. Quando aplicar enforcement

**Não aplique enforcement até:**

- [ ] % de solicitações verificadas estiver estável e alta (ex.: > 95%)
- [ ] App funcionando normalmente em debug, profile e release
- [ ] Testes em dispositivos reais (Android/iOS) e em navegador (Web)
- [ ] Tokens de depuração cadastrados para cada plataforma usada em desenvolvimento

**Como aplicar (no Firebase Console):**

1. **App Check** → **APIs** → selecione **Cloud Firestore**
2. Clique em **Implementar** (ou **Enforce**)
3. Repita para **Cloud Storage** e outras APIs usadas

---

## 5. Ordem de inicialização (já implementada)

O App Check é ativado na seguinte ordem no `main.dart`:

1. `Firebase.initializeApp()`
2. `RemoteConfigService.init()` (para chave reCAPTCHA)
3. `initFirebaseAppCheck()` ← **antes** de qualquer acesso ao Firestore/Storage
4. `initFirebaseMonitoring()` (Crashlytics, Analytics)

---

## 6. Resumo de providers por plataforma

| Plataforma | Debug/Profile | Release |
|-----------|----------------|---------|
| Android   | Debug          | Play Integrity |
| iOS       | Debug          | App Attest |
| Web       | reCAPTCHA v3   | reCAPTCHA v3 |
| Desktop   | Não ativado    | Não ativado |

---

## 7. Solução de problemas

- **403 / attestation failed**: Token de debug não cadastrado ou inválido. Adicione/atualize em Tokens de depuração.
- **reCAPTCHA vazio no Web**: Configure `recaptcha_site_key` no Remote Config ou `kRecaptchaSiteKeyOverride` em `lib/config/app_check_config.dart`.
- **Play Integrity falha em release**: Confirme SHA-1/SHA-256 do app de release no projeto Firebase e que o app está na Play Store ou em teste interno.
- **Desktop (macOS/Windows)**: App Check não é ativado nessa plataforma; o app segue funcionando normalmente.
