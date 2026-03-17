# =============================================================================
# MasterPalm - TUDO 100%: Instalador + Site + Catálogo Web + App Web + APK + Deploy
# =============================================================================
# Executa na ordem: dependências (npm + Flutter) -> build_runner -> sync_web ->
# (opcional) deploy catálogo -> build web -> build APK -> copiar APK/privacidade ->
# (opcional) build site Next.js -> firebase deploy.
#
# Uso (na raiz do projeto ou de scripts/):
#   .\scripts\tudo-100.ps1
#   .\scripts\tudo-100.ps1 -ApenasInstalar     # Só instala deps (npm + flutter)
#   .\scripts\tudo-100.ps1 -SemDeploy          # Build tudo, não faz firebase deploy
#   .\scripts\tudo-100.ps1 -IncluirCatalogo   # Sincroniza produtos para catálogo público (Firestore)
#   .\scripts\tudo-100.ps1 -IncluirSite       # Build do site Next.js (mastepalm.com.br)
#   .\scripts\tudo-100.ps1 -IncluirFunctions  # Inclui Cloud Functions no deploy (padrão: só hosting, firestore, storage)
#   .\scripts\tudo-100.ps1 -SemWeb            # Não faz build Flutter web
#   .\scripts\tudo-100.ps1 -SemApk            # Não faz build APK Android
# =============================================================================

param(
    [switch]$ApenasInstalar,  # Só instala todas as dependências (npm + flutter)
    [switch]$SemDeploy,
    [switch]$IncluirCatalogo,
    [switch]$IncluirSite,
    [switch]$IncluirFunctions, # Inclui functions no firebase deploy (padrão: não, para evitar 403 Extensions)
    [switch]$SemWeb,
    [switch]$SemApk
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
if ($root -match "scripts$") { $root = Split-Path -Parent $root }
Set-Location $root

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  MasterPalm - Tudo 100%" -ForegroundColor Cyan
Write-Host "  Instalador + Site + Web + APK + Deploy" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# -----------------------------------------------------------------------------
# FASE 0: Instalador completo (todas as dependências)
# -----------------------------------------------------------------------------
Write-Host "[0] Instalador - Dependencias npm (raiz, functions, scripts, site, main)..." -ForegroundColor Yellow
$npmDirs = @(".", "functions", "scripts", "site", "main")
foreach ($dir in $npmDirs) {
    $p = if ($dir -eq ".") { $root } else { Join-Path $root $dir }
    $pj = Join-Path $p "package.json"
    if (Test-Path $pj) {
        Push-Location $p
        Write-Host "  npm install em $dir..." -ForegroundColor Gray
        cmd /c "npm install 2>nul"
        if ($LASTEXITCODE -ne 0) { Write-Host "  Aviso: npm install em $dir falhou" -ForegroundColor Yellow }
        Pop-Location
    }
}
Write-Host "  OK: npm concluido" -ForegroundColor Green
Write-Host ""

Write-Host "[0] Instalador - Flutter (clean + pub get)..." -ForegroundColor Yellow
fvm flutter clean
fvm flutter pub get
if ($LASTEXITCODE -ne 0) { throw "fvm flutter pub get falhou" }
Write-Host "  OK: Flutter dependencias" -ForegroundColor Green
Write-Host ""

if ($ApenasInstalar) {
    Write-Host "ApenasInstalar: concluido. Rode sem -ApenasInstalar para build e deploy." -ForegroundColor Green
    Write-Host ""
    exit 0
}

# -----------------------------------------------------------------------------
# 1. Gerar código (build_runner - Hive, etc.)
# -----------------------------------------------------------------------------
Write-Host "[1/10] Gerando codigo (build_runner)..." -ForegroundColor Yellow
fvm dart run build_runner build --delete-conflicting-outputs 2>$null
if ($LASTEXITCODE -ne 0) { Write-Host "  Aviso: build_runner falhou ou nao necessario" -ForegroundColor Gray }
else { Write-Host "  OK" -ForegroundColor Green }
Write-Host ""

# -----------------------------------------------------------------------------
# 2. Sincronizar versão web (manifest.json, index.html)
# -----------------------------------------------------------------------------
Write-Host "[2/10] Sincronizando versao web (tool/sync_web_version.dart)..." -ForegroundColor Yellow
fvm dart run tool/sync_web_version.dart
if ($LASTEXITCODE -ne 0) { throw "sync_web_version falhou" }
Write-Host "  OK" -ForegroundColor Green
Write-Host ""

# -----------------------------------------------------------------------------
# 3. (Opcional) Deploy dados do catálogo para LIVE (Firestore)
# -----------------------------------------------------------------------------
if ($IncluirCatalogo) {
    Write-Host "[3/10] Deploy do catalogo para LIVE (produtos -> Firestore)..." -ForegroundColor Yellow
    fvm dart run lib/scripts/deploy_catalog_live.dart
    if ($LASTEXITCODE -ne 0) {
        Write-Host "" -ForegroundColor Yellow
        Write-Host "  AVISO: deploy_catalog_live falhou. Em Flutter 3.32.x, 'fvm dart run' pode dar erros no SDK (Offset/Color nao definidos)." -ForegroundColor Yellow
        Write-Host "  Tente: fvm flutter upgrade. Ou rode o deploy pelo app (menu) ou use -IncluirCatalogo apenas apos atualizar." -ForegroundColor Yellow
        Write-Host "  Continuando com o resto do script..." -ForegroundColor Gray
    } else {
        Write-Host "  OK" -ForegroundColor Green
    }
} else {
    Write-Host "[3/10] Deploy catalogo (pulado; use -IncluirCatalogo)" -ForegroundColor Gray
}
Write-Host ""

# -----------------------------------------------------------------------------
# 4. Build Flutter Web (app web = catálogo online no browser)
# -----------------------------------------------------------------------------
if (-not $SemWeb) {
    Write-Host "[4/10] Build Flutter Web (release)..." -ForegroundColor Yellow
    fvm flutter build web --release
    if ($LASTEXITCODE -ne 0) { throw "fvm flutter build web falhou" }
    Write-Host "  OK -> build/web" -ForegroundColor Green
} else {
    Write-Host "[4/10] Build Flutter Web (pulado; -SemWeb)" -ForegroundColor Gray
}
Write-Host ""

# -----------------------------------------------------------------------------
# 5. Build APK Android
# -----------------------------------------------------------------------------
if (-not $SemApk) {
    Write-Host "[5/10] Build APK Android (release)..." -ForegroundColor Yellow
    $keystorePath = Join-Path $root "android\app\upload-keystore.jks"
    $keyProps = Join-Path $root "android\key.properties"
    if (-not (Test-Path $keystorePath) -and -not (Test-Path (Join-Path $root "android\app\release.keystore"))) {
        Write-Host "  Aviso: keystore nao encontrado. Configure android/key.properties e upload-keystore.jks" -ForegroundColor Yellow
    }
    $gradlew = Join-Path $root "android\gradlew.bat"
    if (Test-Path $gradlew) {
        Push-Location (Join-Path $root "android")
        & .\gradlew.bat --stop 2>$null
        Pop-Location
    }
    fvm flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw "fvm flutter build apk falhou" }
    Write-Host "  OK -> build/app/outputs/flutter-apk/app-release.apk" -ForegroundColor Green
} else {
    Write-Host "[5/10] Build APK (pulado; -SemApk)" -ForegroundColor Gray
}
Write-Host ""

# -----------------------------------------------------------------------------
# 6. Preparar build/web (APK, download.html, .well-known, privacidade.html)
# -----------------------------------------------------------------------------
Write-Host "[6/10] Preparando build/web (APK + paginas)..." -ForegroundColor Yellow
$buildWeb = Join-Path $root "build\web"
$downloadsDir = Join-Path $buildWeb "downloads"
if (-not (Test-Path $buildWeb)) { New-Item -ItemType Directory -Path $buildWeb -Force | Out-Null }
if (-not (Test-Path $downloadsDir)) { New-Item -ItemType Directory -Path $downloadsDir -Force | Out-Null }

$apkSource = Join-Path $root "build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $apkSource) {
    Copy-Item $apkSource (Join-Path $downloadsDir "masterpalm.apk") -Force
    Write-Host "  APK -> build/web/downloads/masterpalm.apk" -ForegroundColor Gray
}
$downloadHtml = Join-Path $root "web\download.html"
if (Test-Path $downloadHtml) {
    Copy-Item $downloadHtml (Join-Path $buildWeb "download.html") -Force
    Write-Host "  download.html copiado" -ForegroundColor Gray
}
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
if (-not (Test-Path (Join-Path $root "public\privacidade.html")) -and (Test-Path (Join-Path $root "web\privacidade.html"))) {
    Copy-Item (Join-Path $root "web\privacidade.html") $buildWeb -Force
    Write-Host "  privacidade.html (web/) copiado" -ForegroundColor Gray
}
Write-Host "  OK" -ForegroundColor Green
Write-Host ""

# -----------------------------------------------------------------------------
# 7. (Opcional) Build do site Next.js (mastepalm.com.br)
# -----------------------------------------------------------------------------
if ($IncluirSite) {
    Write-Host "[7/10] Build site Next.js (site/)..." -ForegroundColor Yellow
    $siteDir = Join-Path $root "site"
    if (Test-Path (Join-Path $siteDir "package.json")) {
        Push-Location $siteDir
        cmd /c "npm ci 2>nul || npm install 2>nul"
        cmd /c "npm run build 2>&1"
        if ($LASTEXITCODE -ne 0) { throw "npm run build (site) falhou" }
        Pop-Location
        Write-Host "  OK -> site/.next (publique na Vercel: vercel --prod)" -ForegroundColor Green
    } else {
        Write-Host "  Aviso: site/ sem package.json" -ForegroundColor Yellow
    }
} else {
    Write-Host "[7/10] Build site Next.js (pulado; use -IncluirSite)" -ForegroundColor Gray
}
Write-Host ""

# -----------------------------------------------------------------------------
# 8. Deploy Firebase
# -----------------------------------------------------------------------------
if (-not $SemDeploy) {
    Write-Host "[8/10] Deploy Firebase..." -ForegroundColor Yellow
    if ($IncluirFunctions) {
        firebase deploy
    } else {
        # Hosting rewrites apontam para mpOAuthInit, mpOAuthCallback, redirectCatalogo.
        # Essas funções precisam existir antes do hosting finalizar; implantar só elas.
        Write-Host "  Implantando funções usadas pelo Hosting (mpOAuthInit, mpOAuthCallback, redirectCatalogo)..." -ForegroundColor Gray
        firebase deploy --only "functions:mpOAuthInit,functions:mpOAuthCallback,functions:redirectCatalogo"
        if ($LASTEXITCODE -ne 0) {
            throw "Deploy das funções falhou. Rode com -IncluirFunctions para implantar todas as funções: .\scripts\tudo-100.ps1 -IncluirCatalogo -IncluirSite -IncluirFunctions"
        }
        firebase deploy --only "hosting,firestore,storage"
    }
    if ($LASTEXITCODE -ne 0) { throw "firebase deploy falhou" }
    Write-Host "  OK: Hosting (app web + APK), Firestore, Storage" -ForegroundColor Green
} else {
    Write-Host "[8/10] Deploy Firebase (pulado; -SemDeploy). Rode: firebase deploy" -ForegroundColor Gray
}
Write-Host ""

# -----------------------------------------------------------------------------
# 9. Resumo
# -----------------------------------------------------------------------------
Write-Host "[9/10] Resumo" -ForegroundColor Cyan
Write-Host "  - App web (Flutter): build/web -> Firebase Hosting" -ForegroundColor Gray
Write-Host "  - APK: build/app/outputs/flutter-apk/app-release.apk" -ForegroundColor Gray
Write-Host "  - APK download: build/web/downloads/masterpalm.apk (apos deploy)" -ForegroundColor Gray
Write-Host "  - Atualize site/src/config/site.ts (APK_DOWNLOAD_URL) e publique o site na Vercel se usou -IncluirSite" -ForegroundColor Gray
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Tudo 100% concluido" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
