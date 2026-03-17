# 🔗 Configuração de Deep Links - MasterPalm

## ✅ Status Atual

O sistema de Deep Links está **100% configurado** para abrir links do tipo:
- `https://mastepalm.com.br/pedido/ABC123?loja=minhaloja`
- `mastepalm://pedido/ABC123?loja=minhaloja`

Diretamente no **app MasterPalm** em vez do navegador.

---

## 📱 Como Testar no Android

### 1. Compile o APK de Debug

```bash
flutter build apk --debug
```

Ou para release:

```bash
flutter build apk --release
```

### 2. Instale no Dispositivo

```bash
flutter install
```

Ou manualmente:
```bash
adb install build/app/outputs/flutter-apk/app-debug.apk
```

### 3. Teste o Deep Link

**Opção A: Via ADB (mais rápido)**
```bash
adb shell am start -W -a android.intent.action.VIEW \
  -d "https://mastepalm.com.br/pedido/TEST123?loja=masterpalm_gmail_com" \
  com.masterpalm.app
```

**Opção B: Via WhatsApp**
1. Envie uma mensagem com o link para você mesmo
2. Clique no link
3. O Android deve mostrar opção "Abrir com MasterPalm"

**Opção C: Via Navegador**
1. Abra o Chrome no Android
2. Digite: `https://mastepalm.com.br/pedido/TEST123?loja=masterpalm_gmail_com`
3. O app deve abrir automaticamente (Android App Links)

---

## 🔧 Arquivos Configurados

### 1. AndroidManifest.xml
```xml
<intent-filter android:autoVerify="true">
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="https" android:host="mastepalm.com.br" />
  <data android:scheme="https" android:host="mastepalm.com.br" android:pathPrefix="/pedido" />
</intent-filter>
```

### 2. assetlinks.json (Deploy no Firebase)
Localização: `https://mastepalm.com.br/.well-known/assetlinks.json`

Este arquivo valida que o app com package `com.masterpalm.app` tem permissão para abrir links de `mastepalm.com.br`.

### 3. DeepLinkHandler (Flutter)
Localização: `lib/services/deep_link_handler.dart`

Escuta links e navega para a tela correta:
- `/pedido/:id?loja=:lojaId` → `PedidoPublicoScreen`

### 4. onGenerateRoute (main.dart)
Trata rotas dinâmicas como `/pedido/ABC123`.

---

## 🚀 Deploy para Produção

### Importante: Certificado de Release

Quando publicar na Google Play, você precisa atualizar o `assetlinks.json` com o SHA256 do certificado de **release**:

```bash
# Obter SHA256 do keystore de release
keytool -list -v -keystore /caminho/para/release.keystore \
  -alias release_alias -storepass SUA_SENHA -keypass SUA_SENHA \
  | grep "SHA256"
```

Depois, atualize `public/.well-known/assetlinks.json`:

```json
{
  "sha256_cert_fingerprints": [
    "AA:BB:CC:DD:EE:FF:... (SHA256 DO RELEASE)"
  ]
}
```

E faça o deploy:

```bash
./build-and-deploy.sh
```

---

## 🧪 Verificar Status dos App Links

```bash
# Verificar associações de domínio no Android
adb shell pm get-app-links com.masterpalm.app

# Forçar re-verificação
adb shell pm verify-app-links --re-verify com.masterpalm.app

# Ver status detalhado
adb shell pm get-app-links --user cur com.masterpalm.app
```

---

## 🐛 Troubleshooting

### O app não abre, só o navegador

1. **Verificar se o assetlinks.json está acessível:**
   ```bash
   curl https://mastepalm.com.br/.well-known/assetlinks.json
   ```

2. **Verificar SHA256 no assetlinks.json:**
   - Debug: `53:CC:53:91:C2:59:92:DD:ED:F6:BB:6A:E2:30:7F:FF:FA:2B:B5:6C:50:BB:4B:C6:C1:F6:38:A6:9A:E5:BD:1D`
   - Release: Você precisa adicionar

3. **Limpar configurações do Android:**
   ```bash
   adb shell pm clear com.masterpalm.app
   adb shell pm verify-app-links --re-verify com.masterpalm.app
   ```

4. **Testar com custom scheme (sempre funciona):**
   ```bash
   adb shell am start -W -a android.intent.action.VIEW \
     -d "mastepalm://pedido/TEST123?loja=masterpalm_gmail_com" \
     com.masterpalm.app
   ```

### Android não verifica o assetlinks.json

- O dispositivo precisa ter internet
- Pode levar alguns minutos para o Android verificar
- Reinstale o app para forçar nova verificação

---

## 📚 Referências

- [Android App Links](https://developer.android.com/training/app-links)
- [Flutter app_links package](https://pub.dev/packages/app_links)
- [Google App Links Assistant](https://developers.google.com/digital-asset-links/tools/generator)

---

## ✅ Checklist de Deploy

- [x] assetlinks.json criado
- [x] assetlinks.json acessível em https://mastepalm.com.br/.well-known/assetlinks.json
- [x] SHA256 do debug keystore adicionado
- [ ] SHA256 do release keystore adicionado (fazer antes da Play Store)
- [x] AndroidManifest.xml com intent-filters
- [x] DeepLinkHandler implementado e inicializado
- [x] onGenerateRoute tratando rotas `/pedido/:id`
- [x] Firebase Hosting configurado com headers corretos

**Status**: ✅ Pronto para testar no Android!
