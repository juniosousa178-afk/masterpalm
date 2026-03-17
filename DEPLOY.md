# Guia de Deploy - MasterPalm

## Pré-requisitos

- Flutter SDK 3.x
- Conta Firebase (projeto configurado)
- Conta Google Play Developer (para Android)
- Node.js (para Cloud Functions)

---

## 1. Assinatura do APK (Android Release)

1. Gere o keystore:
   ```bash
   keytool -genkey -v -keystore android/app/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. Copie o exemplo e preencha:
   ```bash
   cp android/key.properties.example android/key.properties
   ```
   Edite `android/key.properties` com suas senhas e caminho do keystore.

3. **Nunca** commite `key.properties` ou `*.jks` (já estão no .gitignore).

---

## 2. Firebase

### Remote Config

**Opção A – Importar template (recomendado):**

1. Firebase Console → Remote Config → Menu (⋮) → **Publicar de um arquivo**
2. Selecione o arquivo `firebase_remote_config_template.json` na raiz do projeto
3. Edite o valor de `recaptcha_site_key` com sua chave reCAPTCHA v3 e publique

**Opção B – Criar manualmente:**

- **Chave:** `recaptcha_site_key`
- **Tipo:** String
- **Valor padrão:** sua chave reCAPTCHA v3 (obtenha em https://www.google.com/recaptcha/admin)

### App Check

- Ative App Check no Firebase Console para Firestore, Auth e Storage.
- Em debug: use o token de debug (já configurado em `web/index.html`).
- Em produção: configure Play Integrity (Android) e App Attest (iOS).

### Alertas de custo

1. Firebase Console → Configurações do projeto → Uso e faturamento
2. Configure alertas de orçamento (ex: R$ 100, R$ 500)
3. Ative notificações por e-mail

---

## 3. Build Release

```bash
# Android
flutter build apk --release

# Ou AAB (recomendado para Play Store)
flutter build appbundle --release
```

O APK/AAB estará em `build/app/outputs/`.

---

## 4. Deploy Web

```bash
flutter build web
firebase deploy --only hosting
```

---

## 5. Cloud Functions

```bash
cd functions  # ou main
npm install
firebase deploy --only functions
```

---

## 6. Atualizar tudo (catálogo, app web, APK, site)

Use o script que faz build do app web, APK, copia o APK para download e opcionalmente deploy:

```powershell
.\scripts\atualizar-tudo.ps1
```

Opções: `-SemDeploy`, `-IncluirCatalogo`, `-IncluirSite`, `-SemWeb`, `-SemApk`.  
Comandos manuais e detalhes: **docs/COMANDOS_ATUALIZAR_TUDO.md**.

---

## 7. Setup rápido (script)

Execute o script de setup para preparar o ambiente:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup_release.ps1
```

Isso irá:
- Criar `key.properties` a partir do exemplo (se não existir)
- Exibir instruções para Remote Config e próximos passos

## 8. Checklist pós-deploy

- [ ] Testar login e cadastro
- [ ] Testar fluxo de checkout completo
- [ ] Verificar Crashlytics recebendo eventos
- [ ] Verificar Analytics
- [ ] Confirmar que App Check está ativo (Firebase Console)
