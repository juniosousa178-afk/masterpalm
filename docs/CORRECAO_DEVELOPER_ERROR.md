# Correção do erro DEVELOPER_ERROR no Android

O erro `ConnectionResult{statusCode=DEVELOPER_ERROR}` e `Unknown calling package name 'com.google.android.gms'` ocorrem quando o **SHA-1** do seu app não está registrado no Firebase ou há conflito de configuração.

---

## Passo 1: Obter o SHA-1 do debug keystore

No terminal (PowerShell ou CMD), execute:

```powershell
cd android
keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```

Ou no Git Bash / WSL:

```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```

Copie o valor de **SHA1** (ex: `A1:B2:C3:...`).

**Seu SHA-1 de debug (verifique se já está no Firebase):**
```
20:7F:5B:7B:6F:29:8D:05:D1:8D:6A:D9:BC:18:E7:C2:E7:33:87:4D
```

---

## Passo 2: Adicionar SHA-1 no Firebase Console

1. Acesse [Firebase Console](https://console.firebase.google.com)
2. Selecione o projeto **masterpalm-58c46**
3. Clique no ícone de engrenagem → **Configurações do projeto**
4. Na aba **Geral**, role até **Seus apps**
5. Clique no app Android (`com.masterpalm.app`)
6. Clique em **Adicionar impressão digital** e cole o SHA-1
7. Clique em **Salvar**

---

## Passo 3: Baixar o novo google-services.json

1. No Firebase Console, na mesma tela do app Android
2. Clique em **Fazer download do google-services.json**
3. Substitua o arquivo em `android/app/google-services.json`

---

## Passo 4: Para release (Play Store)

Quando publicar na Play Store, você precisará adicionar também:

- **SHA-1 da chave de upload** (se usar Play App Signing)
- **SHA-1 da chave de assinatura do app** (do Google Play Console)

No Google Play Console: **Configuração** → **Integridade do app** → copie o SHA-1 e adicione no Firebase.

---

## Passo 5: Limpar e recompilar

```powershell
flutter clean
flutter pub get
flutter run
```

---

## Erros relacionados

| Erro | Causa provável |
|------|----------------|
| `DEVELOPER_ERROR` | SHA-1 não registrado ou desatualizado |
| `Unknown calling package name` | google-services.json antigo ou package name incorreto |
| `ProviderInstaller failed` | Pode ser ignorado em debug; em produção verifique o device |

---

## Verificação rápida

Após adicionar o SHA-1 e atualizar o google-services.json, o OAuth deve funcionar. Se o erro persistir:

1. Confirme que o **package name** é exatamente `com.masterpalm.app`
2. Aguarde alguns minutos (o Firebase pode demorar para propagar)
3. Desinstale o app do dispositivo e instale novamente
