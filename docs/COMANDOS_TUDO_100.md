# MasterPalm – Comandos para tudo funcionar 100%

Instalador, site (Next.js), catálogo web (dados + app), app web (Flutter), APK Android e deploy Firebase.

---

## Script único (recomendado)

Na **raiz do projeto** (ou de qualquer pasta, o script detecta a raiz):

```powershell
# Tudo: instalar deps + build web + APK + deploy Firebase
.\scripts\tudo-100.ps1

# Só instalar todas as dependências (npm + Flutter)
.\scripts\tudo-100.ps1 -ApenasInstalar

# Build completo + deploy (inclui sincronizar catálogo público e site Next.js)
.\scripts\tudo-100.ps1 -IncluirCatalogo -IncluirSite

# Só build, sem publicar
.\scripts\tudo-100.ps1 -SemDeploy

# Sem build web ou sem APK
.\scripts\tudo-100.ps1 -SemWeb
.\scripts\tudo-100.ps1 -SemApk

# Incluir Cloud Functions no deploy (padrão: só hosting, firestore, storage)
.\scripts\tudo-100.ps1 -IncluirFunctions
```

---

## Comandos manuais (ordem)

Execute na **raiz do projeto** (onde está `pubspec.yaml`).

### 0. Instalador – dependências

```powershell
# npm (raiz, functions, scripts, site, main)
npm install
cd functions; npm install; cd ..
cd scripts; npm install; cd ..
cd site; npm install; cd ..
if (Test-Path main) { cd main; npm install; cd .. }

# Flutter
flutter clean
flutter pub get
```

### 1. Gerar código (Hive, etc.)

```powershell
dart run build_runner build --delete-conflicting-outputs
```

### 2. Sincronizar versão web

```powershell
dart run tool/sync_web_version.dart
```

### 3. (Opcional) Sincronizar catálogo público (produtos → Firestore)

```powershell
dart run lib/scripts/deploy_catalog_live.dart
```

**Se der erro no SDK** (ex.: "Offset/Color isn't defined" em arquivos do Flutter): é um bug conhecido do Flutter 3.32.x ao usar `dart run` com código que depende do framework. Tente `flutter upgrade`. Alternativas: rodar o deploy pelo menu do app ou omitir `-IncluirCatalogo` no script.

### 4. Build app web (Flutter)

```powershell
flutter build web --release
```

Saída: `build/web/` (Firebase Hosting)

### 5. Build APK Android

```powershell
flutter build apk --release
```

Saída: `build/app/outputs/flutter-apk/app-release.apk`

### 6. Preparar build/web (APK + páginas)

```powershell
New-Item -ItemType Directory -Force -Path "build/web/downloads"
Copy-Item "build/app/outputs/flutter-apk/app-release.apk" "build/web/downloads/masterpalm.apk" -Force
if (Test-Path "web/download.html") { Copy-Item "web/download.html" "build/web/" -Force }
if (Test-Path "public/.well-known") {
  New-Item -ItemType Directory -Force -Path "build/web/.well-known" | Out-Null
  Copy-Item "public/.well-known/*" "build/web/.well-known/" -Force
}
if (Test-Path "public/privacidade.html") { Copy-Item "public/privacidade.html" "build/web/" -Force }
```

### 7. (Opcional) Build site Next.js (mastepalm.com.br)

```powershell
cd site
npm ci
npm run build
cd ..
```

Depois: publicar na Vercel (`vercel --prod` ou push no repositório).

### 8. Deploy Firebase

```powershell
# Só hosting + Firestore + Storage (recomendado para evitar 403 em Extensions)
firebase deploy --only "hosting,firestore,storage"

# Tudo (inclui Cloud Functions)
firebase deploy
```

---

## O que cada parte faz

| Item | O que é | Comando / Saída |
|------|---------|------------------|
| **Instalador** | npm em todos os projetos + Flutter pub get | `tudo-100.ps1 -ApenasInstalar` |
| **Site (Next.js)** | Landing mastepalm.com.br | `cd site && npm run build` → publicar na Vercel |
| **Catálogo web (dados)** | Produtos no Firestore para o catálogo público | `dart run lib/scripts/deploy_catalog_live.dart` |
| **App web** | App Flutter no navegador | `flutter build web --release` → `build/web/` |
| **APK Android** | App para instalar no celular | `flutter build apk --release` |
| **APK para download** | Mesmo APK no site | Copiado para `build/web/downloads/masterpalm.apk` |
| **Deploy** | Hosting (web + APK), Firestore, Storage, (opcional) Functions | `firebase deploy` |

---

## Pré-requisitos

- **Flutter** no PATH (`flutter doctor`)
- **Node.js** (LTS) e **npm**
- **Firebase CLI**: `npm install -g firebase-tools` e `firebase login`
- **Android release**: `android/key.properties` e keystore (upload-keystore.jks ou release.keystore) para APK assinado

---

## Uma linha (PowerShell, só build + deploy, sem instalar site)

```powershell
flutter clean; flutter pub get; dart run build_runner build --delete-conflicting-outputs; dart run tool/sync_web_version.dart; flutter build web --release; flutter build apk --release; New-Item -ItemType Directory -Force -Path "build/web/downloads"; Copy-Item "build/app/outputs/flutter-apk/app-release.apk" "build/web/downloads/masterpalm.apk" -Force; if (Test-Path "public/privacidade.html") { Copy-Item "public/privacidade.html" "build/web/" -Force }; firebase deploy --only "hosting,firestore,storage"
```
