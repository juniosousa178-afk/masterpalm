# Firebase App Check - Setup Android (MasterPalm)

## 1. Verificação: google-services.json e applicationId

| Item | Valor esperado | Status |
|------|----------------|--------|
| **Projeto Firebase** | masterpalm-58c46 | ✅ `project_id` em google-services.json |
| **App Android** | com.masterpalm.app | ✅ `package_name` em google-services.json |
| **applicationId** | com.masterpalm.app | ✅ android/app/build.gradle.kts |

O arquivo `android/app/google-services.json` está correto e alinhado ao projeto Firebase e ao applicationId.

---

## 2. SHA-256 (Debug e Release)

### Gerar certificados

```powershell
cd c:\Users\Pichau\apk_nathy\temp_naty\android
.\gradlew signingReport
```

### Valores obtidos (exemplo do seu ambiente)

| Variante | Keystore | SHA-1 | SHA-256 |
|----------|----------|-------|---------|
| **debug** | `~/.android/debug.keystore` | 20:7F:5B:7B:6F:29:8D:05:D1:8D:6A:D9:BC:18:E7:C2:E7:33:87:4D | 53:CC:53:91:C2:59:92:DD:ED:F6:BB:6A:E2:30:7F:FF:FA:2B:B5:6C:50:BB:4B:C6:C1:F6:38:A6:9A:E5:BD:1D |
| **release** | `android/app/masterpalm-release.jks` | 12:0D:3B:9E:D0:EA:8B:D1:D2:64:96:26:75:8D:27:68:26:22:B6:27 | 73:26:08:9F:04:B1:11:7F:64:49:91:70:14:B5:A9:9A:AE:18:63:0F:FA:4C:3D:BB:E3:FE:AC:8C:D7:3F:0F:D1 |

### Onde cadastrar no Firebase

1. Acesse [Firebase Console](https://console.firebase.google.com/) → projeto **masterpalm-58c46**
2. **Configurações do projeto** (ícone de engrenagem) → **Seus apps**
3. Selecione o app Android (`com.masterpalm.app`)
4. Em **Certificados de impressão digital SHA**, clique em **Adicionar impressão digital**
5. Cole o **SHA-256** (e opcionalmente SHA-1) para:
   - **Debug:** use o SHA-256 do debug (desenvolvimento/emulador)
   - **Release:** use o SHA-256 do release (APK/AAB para produção)

> **Importante:** Play Integrity exige que o SHA do certificado usado para assinar o app esteja cadastrado. Sem isso, as requisições aparecem como inválidas.

---

## 3. Código de inicialização (main.dart)

| Modo | Provider Android |
|------|------------------|
| **Debug** (kDebugMode) | `AndroidProvider.debug` |
| **Release** | `AndroidProvider.playIntegrity` |

O provider debug gera um token que deve ser cadastrado no Firebase (ver seção 4). O Play Integrity usa o certificado SHA e o dispositivo para validar.

---

## 4. Token de depuração (Debug)

### Obter o token no logcat

1. Conecte o dispositivo via USB (ou use emulador)
2. Rode o app em **modo debug**: `flutter run` ou `flutter run --debug`
3. Ao fazer a primeira requisição ao Firestore, o SDK exibe o token no logcat

```powershell
adb logcat | findstr "DebugAppCheckProvider allow"
```

Ou filtre por:

```powershell
adb logcat | findstr "debug secret"
```

O formato esperado é algo como:

```
D DebugAppCheckProvider: Enter this debug secret into the allow list in the Firebase Console for your project: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
```

### Cadastrar no Firebase

1. Copie o token (formato UUID: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)
2. Firebase Console → **App Check** → **Apps**
3. Clique nos três pontos (⋮) do app Android → **Gerenciar tokens de depuração**
4. **Adicionar token de depuração** → cole o token → Salvar

Após cadastrar, as requisições em modo debug passam a ser contabilizadas como **verificadas**.

---

## 5. Validação no Console (taxa de requests verified)

### Passo a passo

1. **Firebase Console** → **App Check** → **APIs**
2. Selecione **Cloud Firestore**
3. Em **Últimos 60 minutos**, verifique:
   - **Verificadas:** % de requisições com token válido
   - **Não verificadas:** % de requisições sem token ou token inválido

### Checklist

| Etapa | Debug | Release |
|-------|-------|---------|
| SHA cadastrado no Firebase | Debug SHA-256 | Release SHA-256 |
| Token de depuração cadastrado | Sim (se usar debug) | N/A |
| App rodando | `flutter run` (debug) | APK/AAB instalado |
| Taxa verificada > 0% | Após cadastrar token | Após cadastrar SHA |

### Troubleshooting

| Problema | Solução |
|----------|---------|
| 100% inválidas (Debug) | Cadastre o token de depuração no Console |
| 100% inválidas (Release) | Cadastre o SHA-256 do keystore de release |
| Emulador | Use provider debug + token cadastrado |
| Aparelho físico | Play Integrity deve funcionar com SHA correto |

---

## 6. Habilitar Enforce (após validar tokens)

**Não ative Enforce antes de ver taxa de verificadas > 0%.**

1. App Check → APIs → Cloud Firestore
2. Clique em **Aplicar** (Enforce)
3. Repita para Auth e Storage quando necessário

---

## 7. Resumo do patch aplicado

### lib/main.dart

- Removido bypass temporário (`_bypassAppCheckParaDiagnostico`)
- Debug: `AndroidProvider.debug`
- Release: `AndroidProvider.playIntegrity`

### Arquivos não alterados

- `google-services.json` — já correto
- `android/app/build.gradle.kts` — applicationId correto
- Auth, Firestore, RemoteConfig, Crashlytics, Hive — sem alterações
