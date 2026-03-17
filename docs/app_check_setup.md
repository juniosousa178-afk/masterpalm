# Firebase App Check - Setup MasterPalm

> **Documentação detalhada Android:** Ver [APP_CHECK_ANDROID_SETUP.md](APP_CHECK_ANDROID_SETUP.md) para SHA-256, token de depuração e validação no Console.

## Por que "100% inválidas / não verificadas"?

- **Android:** Se estiver usando `AndroidProvider.debug`, os tokens são de debug e aparecem como inválidos até serem registrados. O app foi ajustado para usar **sempre Play Integrity** no Android.
- **Emulador:** Play Integrity **falha em emuladores**. Use **aparelho físico** com Play Store oficial.
- **SHA não registrado:** O certificado de assinatura (SHA-1/SHA-256) deve estar em Firebase Console → Configurações → Seus apps → Android → Certificados.
- **Bootloader alterado / root:** Pode gerar token inválido.

## 1. Confirmar que tokens estão chegando

1. Firebase Console → **App Check** → **APIs** → **Cloud Firestore** → Últimos 60 minutos
2. Verifique **"Verificadas"** – deve mostrar % > 0 após alguns minutos de uso
3. Se permanecer 0%:
   - **Android:** adicione SHA-1 e SHA-256 do keystore em **Configurações do projeto** → **Seus apps** → Android → **Adicionar impressão digital**. Comando: `keytool -list -v -keystore android/app/upload-keystore.jks -alias upload`
   - **Web:** confirme que o domínio está autorizado no reCAPTCHA Admin e que `recaptcha_site_key` está correto no Remote Config

## 2. Ordem segura para habilitar Enforce

**Não ative Enforce até confirmar que tokens estão chegando.**

Ordem recomendada:

1. **Firestore** – ative Enforce primeiro
2. **Auth** – depois
3. **Storage** – por último

Se ativar tudo de uma vez e houver problema, será mais difícil isolar.

## 3. Build e teste

```bash
# APK para instalar em aparelho físico
flutter build apk --release

# Ou AAB para Play Store
flutter build appbundle --release
```

- **APK:** `build/app/outputs/flutter-apk/app-release.apk`
- **AAB:** `build/app/outputs/bundle/release/app-release.aab`

**Importante:** Instale no **aparelho físico** (não emulador). Play Integrity precisa de dispositivo real com Play Store oficial.

## 4. Checklist antes da Play Store

- [ ] App Check registrado (Android Play Integrity + Web reCAPTCHA v3)
- [ ] Tokens verificadas > 0% no Console
- [ ] Enforce habilitado em Firestore, Auth e Storage (após validar tokens)
- [ ] Remote Config com `recaptcha_site_key` publicado
- [ ] `key.properties` configurado para assinatura release
- [ ] Build AAB executado com sucesso

## 5. applicationId (Android)

O `applicationId` deve ser exatamente `com.masterpalm.app` (em `android/app/build.gradle.kts`). Deve bater com o `package_name` do `google-services.json` e com o app registrado no Firebase.

## 6. Debug local (Web)

Para testar App Check em localhost, adicione temporariamente em `web/index.html`:

```html
<script>self.FIREBASE_APPCHECK_DEBUG_TOKEN=true;</script>
```

Execute o app, abra o Console do navegador e copie o token exibido. Registre em Firebase Console → App Check → Web → Tokens de depuração. **Remova o script antes do deploy de produção.**

## 7. Ambiente de teste (Android)

| Ambiente | Play Integrity |
|----------|----------------|
| Aparelho físico + Play Store | ✅ Funciona |
| Emulador | ❌ Falha (token inválido) |
| Bootloader desbloqueado / root | ⚠️ Pode falhar |
