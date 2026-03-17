# Comandos para atualizar catálogo web, app web, APK e site

Use o **script automatizado** (recomendado) ou os comandos manuais abaixo.

---

## Script único (PowerShell)

Na raiz do projeto:

```powershell
# Build completo + deploy Firebase (app web + APK para download)
.\scripts\atualizar-tudo.ps1

# Só build, sem publicar
.\scripts\atualizar-tudo.ps1 -SemDeploy

# Incluir sincronização dos dados do catálogo para o catálogo público (Firestore)
.\scripts\atualizar-tudo.ps1 -IncluirCatalogo

# Incluir build do site Next.js (mastepalm.com.br)
.\scripts\atualizar-tudo.ps1 -IncluirSite

# Não gerar app web
.\scripts\atualizar-tudo.ps1 -SemWeb

# Não gerar APK
.\scripts\atualizar-tudo.ps1 -SemApk
```

---

## Comandos manuais (um por vez)

Execute na **raiz do projeto** (onde está o `pubspec.yaml`).

### 1. Preparar projeto Flutter

```powershell
flutter clean
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart run tool/sync_web_version.dart
```

### 2. (Opcional) Sincronizar dados do catálogo para LIVE

Sincroniza produtos (Hive → Firestore) para o catálogo público. Requer loja ativa.

```powershell
dart run lib/scripts/deploy_catalog_live.dart
```

### 3. Build app web (Flutter)

```powershell
flutter build web --release
```

Saída: `build/web/` (será enviado ao Firebase Hosting.)

### 4. Build APK Android

```powershell
flutter build apk --release
```

Saída: `build/app/outputs/flutter-apk/app-release.apk`

### 5. Colocar APK e páginas em build/web (para deploy)

```powershell
# Criar pasta de downloads
New-Item -ItemType Directory -Force -Path "build/web/downloads"

# Copiar APK com nome fixo para o site
Copy-Item "build/app/outputs/flutter-apk/app-release.apk" "build/web/downloads/masterpalm.apk" -Force

# Copiar página de download (se existir)
if (Test-Path "web/download.html") { Copy-Item "web/download.html" "build/web/" -Force }

# Copiar .well-known (asset links)
if (Test-Path "public/.well-known") {
  New-Item -ItemType Directory -Force -Path "build/web/.well-known" | Out-Null
  Copy-Item "public/.well-known/*" "build/web/.well-known/" -Force
}
```

### 6. Deploy Firebase (app web + APK + rules + functions)

```powershell
firebase deploy
```

Após o deploy, o APK fica disponível em:  
`https://<seu-projeto>.web.app/downloads/masterpalm.apk`  
(ou a URL do seu Firebase Hosting configurada no projeto.)

### 7. (Opcional) Atualizar site mastepalm.com.br (Next.js)

**Para alterações de planos aparecerem no site:** edite `site/src/config/site.ts`, depois faça build e **deploy na Vercel** (o script só faz o build). Veja `site/ATUALIZAR-PLANOS-SITE.md`.

Configure em `site/src/config/site.ts`:

- `APK_DOWNLOAD_URL`: URL do APK no Firebase Hosting (ex.: `https://app.mastepalm.com.br/downloads/masterpalm.apk`)
- `apkVersion`: mesma versão do `pubspec.yaml` (ex.: `1.0.13`)

Depois, build e publicação (ex.: Vercel):

```powershell
cd site
npm ci
npm run build
# Publicar: vercel --prod   ou  git push (se Vercel conectado ao repo)
```

---

## Resumo do que cada parte faz

| Item | O que é | Onde fica após build/deploy |
|------|---------|-----------------------------|
| **Catálogo web (dados)** | Produtos no Firestore para o catálogo público | Firestore (script `deploy_catalog_live.dart`) |
| **App web** | App Flutter rodando no navegador | `build/web/` → Firebase Hosting |
| **APK Android** | App para instalar no celular | `build/app/outputs/flutter-apk/app-release.apk` |
| **APK para download no site** | Mesmo APK servido pela web | `build/web/downloads/masterpalm.apk` → Firebase Hosting → URL em `site.ts` |
| **Site mastepalm.com.br** | Landing page (Next.js) | Build em `site/.next` → publicar na Vercel |

---

## Pré-requisitos

- Flutter SDK instalado e no PATH
- Firebase CLI (`firebase deploy`) e projeto configurado (`firebase use`)
- Android: `android/key.properties` e keystore para release (ver `DEPLOY.md`)
- Node.js (para build do site em `site/`)
