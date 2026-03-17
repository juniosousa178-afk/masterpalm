# MasterPalm – Comandos para atualizar tudo

Use o script automático (recomendado):

```powershell
.\scripts\ATUALIZAR-TUDO-COMANDOS.ps1
.\scripts\ATUALIZAR-TUDO-COMANDOS.ps1 -IncluirCatalogo   # inclui sync catálogo
.\scripts\ATUALIZAR-TUDO-COMANDOS.ps1 -SkipPlayStore    # não gera AAB
.\scripts\ATUALIZAR-TUDO-COMANDOS.ps1 -SkipDeploy        # não faz firebase deploy
.\scripts\ATUALIZAR-TUDO-COMANDOS.ps1 -ApenasLista       # só mostra os comandos
```

---

## Comandos manuais (ordem sugerida)

Execute na **raiz do projeto** (`temp_naty`).

### 1. Dependências Flutter
```powershell
fvm flutter clean
fvm flutter pub get
```

### 2. Gerar código (Hive, etc.)
```powershell
fvm dart run build_runner build --delete-conflicting-outputs
```

### 3. Sincronizar versão web (manifest, index.html)
```powershell
fvm dart run tool/sync_web_version.dart
```

### 4. Atualizar catálogo (produtos → Firestore) [opcional]
```powershell
fvm dart run lib/scripts/deploy_catalog_live.dart
```

### 5. Build app web (desktop + mobile web + catálogo)
```powershell
fvm flutter build web --release
```

### 6. Build APK Android
```powershell
fvm flutter build apk --release
```

### 7. Copiar APK para download no site
```powershell
New-Item -ItemType Directory -Force -Path build\web\downloads
Copy-Item build\app\outputs\flutter-apk\app-release.apk build\web\downloads\masterpalm.apk
```

### 8. Build AAB (Play Store)
```powershell
fvm flutter build appbundle --release
```
- Arquivo gerado: `build\app\outputs\bundle\release\app-release.aab`
- Publicar em: https://play.google.com/console

### 9. Copiar arquivos estáticos
```powershell
New-Item -ItemType Directory -Force -Path build\web\.well-known
Copy-Item public\.well-known\assetlinks.json build\web\.well-known\
Copy-Item public\privacidade.html build\web\
```

### 10. Firebase deploy completo
```powershell
firebase deploy
```
Inclui: **Firestore** (rules + indexes), **Storage** (rules), **Functions**, **Hosting**.

#### Deploy por partes
```powershell
firebase deploy --only firestore
firebase deploy --only storage
firebase deploy --only functions
firebase deploy --only hosting
firebase deploy --only hosting,firestore,storage
```

---

## URLs após o deploy

| Canal        | URL |
|-------------|-----|
| App Web     | https://mastepalm.com.br ou https://app.mastepalm.com.br |
| Download APK | https://mastepalm.com.br/downloads/masterpalm.apk |
| Catálogo    | https://mastepalm.com.br/loja/SEU-SLUG ou /c/SEU-SLUG |
| Play Store  | https://play.google.com/console (upload do AAB) |

---

## Outros scripts do projeto

| Script | Uso |
|--------|-----|
| `.\scripts\release-completo.ps1` | Incrementa versão, build web + APK + AAB, mostra comandos de publicação |
| `.\scripts\tudo-100.ps1` | Instalador deps + build + deploy; opções `-IncluirCatalogo`, `-IncluirSite`, `-IncluirFunctions` |
| `.\scripts\deploy-completo.ps1` | Build web/APK + copiar APK + opcional deploy hosting |
| `.\scripts\deploy_full.ps1` | Build web + APK + deploy functions + hosting + firestore/storage |
| `.\deploy-tudo.ps1` | Deploy Firebase (rules + functions + hosting); use `-BuildWeb` para rebuild web |
