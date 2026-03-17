# MasterPalm – Comandos completos com FVM

Rode estes comandos no terminal na raiz do projeto (`temp_naty`). Use **PowerShell** no Windows.

---

## 1. Script automático (recomendado)

```powershell
cd c:\Users\Pichau\apk_nathy\temp_naty
.\scripts\fvm-tudo.ps1
```

- **Só setup** (pub get, clean, build_runner, sync_web_version, analyze):
  ```powershell
  .\scripts\fvm-tudo.ps1 -Setup
  ```
- **Só build** (web + apk + aab):
  ```powershell
  .\scripts\fvm-tudo.ps1 -Build
  ```
- **Só testes**:
  ```powershell
  .\scripts\fvm-tudo.ps1 -Test
  ```
- **Setup + build + deploy Firebase**:
  ```powershell
  .\scripts\fvm-tudo.ps1 -Deploy
  ```

---

## 2. Comandos manuais (copiar e colar)

### Verificar FVM e versão do Flutter

```powershell
fvm list
fvm flutter --version
```

### Setup do projeto

```powershell
fvm flutter pub get
fvm flutter clean
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm dart run tool/sync_web_version.dart
fvm flutter analyze
```

### Testes

```powershell
fvm flutter test
```

### Build Web

```powershell
fvm flutter build web --release
```

### Build APK (Android)

```powershell
fvm flutter build apk --release
```

### Build AAB (Play Store)

```powershell
fvm flutter build appbundle --release
```

### Rodar o app (debug)

```powershell
fvm flutter run
```

### Publicar no Firebase (após build web)

```powershell
firebase deploy --only hosting
```

### Publicar tudo (hosting + functions + rules)

```powershell
firebase deploy
```

---

## 3. Ordem completa para release (um por vez)

```powershell
cd c:\Users\Pichau\apk_nathy\temp_naty

fvm flutter pub get
fvm flutter clean
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
fvm dart run tool/sync_web_version.dart
fvm flutter build web --release
fvm flutter build apk --release
fvm flutter build appbundle --release
firebase deploy --only hosting
```

---

## 4. Onde ficam os arquivos gerados

| Saída              | Caminho |
|--------------------|--------|
| Web                | `build\web\` |
| APK                | `build\app\outputs\flutter-apk\app-release.apk` |
| APK (cópia site)   | `build\web\downloads\masterpalm.apk` |
| AAB (Play Store)  | `build\app\outputs\bundle\release\app-release.aab` |

---

## 5. Se FVM não estiver no PATH

Use o Flutter gerenciado pelo FVM no projeto:

```powershell
.fvm\flutter_sdk\bin\flutter pub get
.fvm\flutter_sdk\bin\dart run build_runner build --delete-conflicting-outputs
```

Ou instale/atualize o FVM:

```powershell
dart pub global activate fvm
fvm install
fvm use
```
