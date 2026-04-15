# =============================================================================
# MasterPalm - Atualizar catálogo web, app web, APK Android e APK para download
# =============================================================================
# Uso:
#   .\scripts\atualizar-tudo.ps1                    # Build + deploy completo
#   .\scripts\atualizar-tudo.ps1 -SemDeploy         # Só build (sem firebase deploy)
#   .\scripts\atualizar-tudo.ps1 -IncluirCatalogo   # Inclui deploy dos dados do catálogo (Firestore)
#   .\scripts\atualizar-tudo.ps1 -IncluirSite       # Inclui build do site Next.js (mastepalm.com.br)
#   .\scripts\atualizar-tudo.ps1 -SemWeb            # Não faz build Flutter web
#   .\scripts\atualizar-tudo.ps1 -SemApk            # Não faz build APK
# =============================================================================

param(
    [switch]$SemDeploy,       # Faz build mas nao executa firebase deploy
    [switch]$IncluirCatalogo, # Executa deploy_catalog_live.dart (sincroniza produtos para catálogo público)
    [switch]$IncluirSite,    # Faz build do site Next.js (site/) para publicar em Vercel
    [switch]$SemWeb,         # Pula build Flutter web
    [switch]$SemApk          # Pula build APK Android
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
if ($root -match "scripts$") { $root = Split-Path -Parent $root }
Set-Location $root

. (Join-Path $PSScriptRoot "_dart_from_flutter.ps1")
$FlutterCmd = $script:FlutterCmd

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  MasterPalm - Atualizar tudo" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# -----------------------------------------------------------------------------
# 1. Dependências Flutter
# -----------------------------------------------------------------------------
Write-Host "[1/9] Flutter: clean + pub get" -ForegroundColor Yellow
& cmd /c "$FlutterCmd clean"
& cmd /c "$FlutterCmd pub get"
if ($LASTEXITCODE -ne 0) { throw "flutter pub get falhou" }
Write-Host "  OK" -ForegroundColor Green
Write-Host ""

# -----------------------------------------------------------------------------
# 2. Gerar código (build_runner - Hive, etc.)
# -----------------------------------------------------------------------------
Write-Host "[2/9] Gerando código (build_runner)..." -ForegroundColor Yellow
Invoke-ProjDart run build_runner build --delete-conflicting-outputs
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Aviso: build_runner falhou ou nao necessario (verifique se hive_generator/build_runner estao no pubspec)" -ForegroundColor Gray
} else {
    Write-Host "  OK" -ForegroundColor Green
}
Write-Host ""

# -----------------------------------------------------------------------------
# 3. Sincronizar versão web (manifest.json, index.html)
# -----------------------------------------------------------------------------
Write-Host "[3/9] Sincronizando versao web (tool/sync_web_version.dart)..." -ForegroundColor Yellow
Invoke-ProjDart run tool/sync_web_version.dart
if ($LASTEXITCODE -ne 0) { throw "sync_web_version falhou" }
Write-Host "  OK" -ForegroundColor Green
Write-Host ""

# -----------------------------------------------------------------------------
# 4. (Opcional) Deploy dados do catálogo para LIVE (Firestore)
# -----------------------------------------------------------------------------
if ($IncluirCatalogo) {
    Write-Host "[4/9] Deploy do catalogo para LIVE (dados produtos -> Firestore)..." -ForegroundColor Yellow
    Write-Host "  Requer: loja ativa configurada no app. Execute o app antes se precisar." -ForegroundColor Gray
    Invoke-ProjDart run lib/scripts/deploy_catalog_live.dart
    if ($LASTEXITCODE -ne 0) { throw "deploy_catalog_live falhou" }
    Write-Host "  OK" -ForegroundColor Green
} else {
    Write-Host "[4/9] Deploy catalogo (pulado; use -IncluirCatalogo para sincronizar produtos para o catálogo público)" -ForegroundColor Gray
}
Write-Host ""

# -----------------------------------------------------------------------------
# 5. Build Flutter Web (app web = catálogo online no browser)
# -----------------------------------------------------------------------------
if (-not $SemWeb) {
    Write-Host "[5/9] Build Flutter Web (release)..." -ForegroundColor Yellow
    & cmd /c "$FlutterCmd build web --release"
    if ($LASTEXITCODE -ne 0) { throw "flutter build web falhou" }
    Write-Host "  OK -> build/web" -ForegroundColor Green
} else {
    Write-Host "[5/9] Build Flutter Web (pulado; -SemWeb)" -ForegroundColor Gray
}
Write-Host ""

# -----------------------------------------------------------------------------
# 6. Build APK Android
# -----------------------------------------------------------------------------
if (-not $SemApk) {
    Write-Host "[6/9] Build APK Android (release)..." -ForegroundColor Yellow
    $keystorePath = Join-Path $root "android\app\upload-keystore.jks"
    $keyProps = Join-Path $root "android\key.properties"
    if (-not (Test-Path $keystorePath) -and -not (Test-Path (Join-Path $root "android\app\release.keystore"))) {
        Write-Host "  Aviso: keystore de release nao encontrado. Configure android/key.properties e android/app/upload-keystore.jks" -ForegroundColor Yellow
    }
    # Encerra daemons Gradle para evitar "arquivo em uso" no Windows (lint-cache)
    $gradlew = Join-Path $root "android\gradlew.bat"
    if (Test-Path $gradlew) {
        Push-Location (Join-Path $root "android")
        & .\gradlew.bat --stop 2>$null
        Pop-Location
    }
    & cmd /c "$FlutterCmd build apk --release"
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk falhou" }
    Write-Host "  OK -> build/app/outputs/flutter-apk/app-release.apk" -ForegroundColor Green
} else {
    Write-Host "[6/9] Build APK (pulado; -SemApk)" -ForegroundColor Gray
}
Write-Host ""

# -----------------------------------------------------------------------------
# 7. Preparar APK e páginas para o site (build/web = Firebase Hosting)
# -----------------------------------------------------------------------------
Write-Host "[7/9] Preparando APK e paginas para deploy (build/web)..." -ForegroundColor Yellow
$buildWeb = Join-Path $root "build\web"
$downloadsDir = Join-Path $buildWeb "downloads"

if (-not (Test-Path $buildWeb)) {
    New-Item -ItemType Directory -Path $buildWeb -Force | Out-Null
}
if (-not (Test-Path $downloadsDir)) {
    New-Item -ItemType Directory -Path $downloadsDir -Force | Out-Null
}

# Copiar APK para download no site (Firebase Hosting servira em /downloads/masterpalm.apk)
$apkSource = Join-Path $root "build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $apkSource) {
    Copy-Item $apkSource (Join-Path $downloadsDir "masterpalm.apk") -Force
    Write-Host "  APK copiado -> build/web/downloads/masterpalm.apk" -ForegroundColor Gray
}

# Copiar página de download (se existir)
$downloadHtml = Join-Path $root "web\download.html"
if (Test-Path $downloadHtml) {
    Copy-Item $downloadHtml (Join-Path $buildWeb "download.html") -Force
    Write-Host "  download.html copiado -> build/web/" -ForegroundColor Gray
}

# Copiar .well-known (asset links, etc.)
$wellKnownSrc = Join-Path $root "public\.well-known"
$wellKnownDst = Join-Path $buildWeb ".well-known"
if (Test-Path $wellKnownSrc) {
    New-Item -ItemType Directory -Path $wellKnownDst -Force | Out-Null
    Copy-Item (Join-Path $wellKnownSrc "*") $wellKnownDst -Force -Recurse -ErrorAction SilentlyContinue
    Write-Host "  .well-known copiado" -ForegroundColor Gray
}
if (Test-Path (Join-Path $root "public\privacidade.html")) {
    Copy-Item (Join-Path $root "public\privacidade.html") $buildWeb -Force
    Write-Host "  privacidade.html copiado" -ForegroundColor Gray
}
Write-Host "  OK" -ForegroundColor Green
Write-Host ""

# -----------------------------------------------------------------------------
# 8. (Opcional) Build do site Next.js (mastepalm.com.br - landing)
# -----------------------------------------------------------------------------
if ($IncluirSite) {
    Write-Host "[8/9] Build do site Next.js (site/)..." -ForegroundColor Yellow
    $siteDir = Join-Path $root "site"
    if (-not (Test-Path (Join-Path $siteDir "package.json"))) {
        Write-Host "  Aviso: site/ nao encontrado ou sem package.json" -ForegroundColor Yellow
    } else {
        Push-Location $siteDir
        # Usar cmd /c para que avisos do npm (deprecated, etc.) nao abortem o PowerShell (npm.ps1 + stderr = RemoteException)
        cmd /c "npm ci 2>nul || npm install 2>nul"
        cmd /c "npm run build 2>&1"
        $buildOk = ($LASTEXITCODE -eq 0)
        Pop-Location
        if (-not $buildOk) { throw "npm run build (site) falhou" }
        Write-Host "  OK -> site/.next (publique na Vercel: vercel --prod ou push no Git)" -ForegroundColor Green
    }
} else {
    Write-Host "[8/9] Build site Next.js (pulado; use -IncluirSite para buildar mastepalm.com.br)" -ForegroundColor Gray
}
Write-Host ""

# -----------------------------------------------------------------------------
# 9. Deploy Firebase (Hosting = app web + APK; rules; functions)
# -----------------------------------------------------------------------------
if (-not $SemDeploy) {
    Write-Host "[9/9] Deploy Firebase (hosting + rules + functions)..." -ForegroundColor Yellow
    # Sem functions evita verificação Extensions (403). Para incluir functions: firebase deploy --only "functions"
    firebase deploy --only "hosting,firestore,storage"
    if ($LASTEXITCODE -ne 0) { throw "firebase deploy falhou" }
    Write-Host "  OK: App web e APK disponiveis no Firebase Hosting" -ForegroundColor Green
} else {
    Write-Host "[9/9] Deploy Firebase (pulado; -SemDeploy). Rode manualmente: firebase deploy" -ForegroundColor Gray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Concluido" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Resumo:" -ForegroundColor White
Write-Host "  - App web (Flutter): build/web -> Firebase Hosting" -ForegroundColor Gray
Write-Host "  - APK Android: build/app/outputs/flutter-apk/app-release.apk" -ForegroundColor Gray
Write-Host "  - APK para download: build/web/downloads/masterpalm.apk (servido apos firebase deploy)" -ForegroundColor Gray
Write-Host "  - URL do APK (ajuste em site/src/config/site.ts): APK_DOWNLOAD_URL = URL do seu Firebase Hosting + /downloads/masterpalm.apk" -ForegroundColor Gray
if ($IncluirSite) {
    Write-Host "  - Site mastepalm.com.br: faça deploy na Vercel (vercel --prod ou push no repositório conectado)" -ForegroundColor Gray
}
Write-Host ""
