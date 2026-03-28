# =============================================================================
# MasterPalm - Script ÚNICO com TODOS os comandos para atualizar:
#   Catálogo (Firestore) | App Web | App Web Mobile | APK Android |
#   APK download no site | AAB Play Store | Firestore deploy completo
# =============================================================================
# Uso (na raiz do projeto):
#   .\scripts\ATUALIZAR-TUDO-COMANDOS.ps1              # Executa tudo
#   .\scripts\ATUALIZAR-TUDO-COMANDOS.ps1 -ApenasLista # Só mostra os comandos (não executa)
#   .\scripts\ATUALIZAR-TUDO-COMANDOS.ps1 -IncluirCatalogo  # Inclui sync catálogo para Firestore
#   .\scripts\ATUALIZAR-TUDO-COMANDOS.ps1 -SkipPlayStore    # Não gera AAB (Play Store)
#   .\scripts\ATUALIZAR-TUDO-COMANDOS.ps1 -SkipDeploy      # Não faz firebase deploy
# =============================================================================

param(
    [switch]$ApenasLista,      # Só imprime a lista de comandos (referência)
    [switch]$IncluirCatalogo,  # Roda deploy_catalog_live.dart (produtos -> Firestore)
    [switch]$SkipPlayStore,     # Não gera AAB (app bundle) para Play Store
    [switch]$SkipDeploy         # Não executa firebase deploy no final
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
if ($root -match "scripts$") { $root = Split-Path -Parent $root }
Set-Location $root

# Usar fvm se existir .fvm e o comando fvm estiver disponível; senao usar flutter/dart direto
$FlutterCmd = "flutter"
$DartCmd = "dart"
if ((Test-Path ".fvm") -and (Get-Command "fvm" -ErrorAction SilentlyContinue)) {
    $FlutterCmd = "fvm flutter"
    $DartCmd = "fvm dart"
}

# -----------------------------------------------------------------------------
# LISTA DE COMANDOS (referência rápida)
# -----------------------------------------------------------------------------
$comandosRef = @"
========================================
  MASTERPALM - COMANDOS DE ATUALIZAÇÃO (referência)
========================================

1) DEPENDÊNCIAS FLUTTER
   fvm flutter clean
   fvm flutter pub get

2) GERAR CÓDIGO (Hive, etc.)
   fvm dart run build_runner build --delete-conflicting-outputs

3) SINCRONIZAR VERSÃO WEB (manifest.json, index.html)
   fvm dart run tool/sync_web_version.dart

4) ATUALIZAR CATÁLOGO (produtos -> Firestore LIVE) [opcional]
   fvm dart run lib/scripts/deploy_catalog_live.dart

5) BUILD APP WEB (desktop + mobile web + catálogo online)
   fvm flutter build web --release

6) BUILD APK ANDROID (release)
   fvm flutter build apk --release

7) COPIAR APK PARA DOWNLOAD NO SITE
   Copy-Item build\app\outputs\flutter-apk\app-release.apk build\web\downloads\masterpalm.apk

8) BUILD AAB (Play Store)
   fvm flutter build appbundle --release
   -> Arquivo: build\app\outputs\bundle\release\app-release.aab
   -> Publicar em: https://play.google.com/console

9) COPIAR ARQUIVOS ESTÁTICOS
   - public\.well-known\assetlinks.json -> build\web\.well-known\
   - public\privacidade.html -> build\web\

10) FIREBASE DEPLOY COMPLETO
    firebase deploy
    (inclui: Firestore rules + indexes, Storage rules, Functions, Hosting)

    Ou por partes:
    firebase deploy --only firestore          # Rules + indexes
    firebase deploy --only storage           # Storage rules
    firebase deploy --only functions         # Cloud Functions
    firebase deploy --only hosting            # App web + APK download
    firebase deploy --only hosting,firestore,storage  # Hosting + Firestore + Storage

URLs após deploy:
  - App Web:     https://mastepalm.com.br  ou  https://app.mastepalm.com.br
  - Modelos CSV: https://mastepalm.com.br/modelos-importacao.html (barra fixa no app + aba no /modelos-importacao)
  - Download:    https://mastepalm.com.br/downloads/masterpalm.apk
  - Catálogo:    https://mastepalm.com.br/loja/SEU-SLUG  ou  /c/SEU-SLUG
  - Play Store:  https://play.google.com/console (upload do AAB)

========================================
"@

if ($ApenasLista) {
    Write-Host $comandosRef -ForegroundColor Cyan
    exit 0
}

# -----------------------------------------------------------------------------
# EXECUÇÃO
# -----------------------------------------------------------------------------
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  MasterPalm - Atualizar Tudo" -ForegroundColor Cyan
Write-Host "  Catalogo | Web | APK | AAB | Deploy" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$step = 0

# 1. Dependências
$step++; Write-Host "[$step/11] flutter clean + pub get..." -ForegroundColor Yellow
& cmd /c "$FlutterCmd clean"
& cmd /c "$FlutterCmd pub get"
if ($LASTEXITCODE -ne 0) { throw "flutter pub get falhou" }
Write-Host "  OK" -ForegroundColor Green

# 2. Build runner
$step++; Write-Host "`n[$step/11] build_runner (Hive)..." -ForegroundColor Yellow
& cmd /c "$DartCmd run build_runner build --delete-conflicting-outputs" 2>$null
Write-Host "  OK" -ForegroundColor Green

# 3. Sync versao web
$step++; Write-Host "`n[$step/11] sync_web_version..." -ForegroundColor Yellow
& cmd /c "$DartCmd run tool/sync_web_version.dart"
if ($LASTEXITCODE -ne 0) { throw "sync_web_version falhou" }
Write-Host "  OK" -ForegroundColor Green

# 4. Catalogo (opcional)
$step++; Write-Host "`n[$step/11] Catalogo (deploy Firestore)..." -ForegroundColor Yellow
if ($IncluirCatalogo) {
    & cmd /c "$DartCmd run lib/scripts/deploy_catalog_live.dart" 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Host "  Aviso: deploy_catalog_live falhou (pode ser SDK). Continuando." -ForegroundColor Yellow }
    else { Write-Host "  OK" -ForegroundColor Green }
} else {
    Write-Host "  Pulado (use -IncluirCatalogo para incluir)" -ForegroundColor Gray
}

# 5. Build Web
$step++; Write-Host "`n[$step/11] flutter build web --release..." -ForegroundColor Yellow
& cmd /c "$FlutterCmd build web --release"
if ($LASTEXITCODE -ne 0) { throw "build web falhou" }
Write-Host "  OK -> build/web" -ForegroundColor Green

# 6. Build APK
$step++; Write-Host "`n[$step/11] flutter build apk --release..." -ForegroundColor Yellow
& cmd /c "$FlutterCmd build apk --release"
if ($LASTEXITCODE -ne 0) { throw "build apk falhou" }
Write-Host "  OK" -ForegroundColor Green

# 7. Copiar APK para downloads
$step++; Write-Host "`n[$step/11] Copiando APK para build/web/downloads..." -ForegroundColor Yellow
$apkSrc = "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apkSrc)) { $apkSrc = "android\app\build\outputs\apk\release\app-release.apk" }
$downloadsDir = "build\web\downloads"
if (-not (Test-Path $downloadsDir)) { New-Item -ItemType Directory -Path $downloadsDir -Force | Out-Null }
if (Test-Path $apkSrc) {
    Copy-Item $apkSrc (Join-Path $downloadsDir "masterpalm.apk") -Force
    Write-Host "  OK -> build/web/downloads/masterpalm.apk" -ForegroundColor Green
} else {
    Write-Host "  Aviso: APK não encontrado em $apkSrc" -ForegroundColor Yellow
}

# 8. Build AAB (Play Store)
$step++; Write-Host "`n[$step/11] AAB (Play Store)..." -ForegroundColor Yellow
if ($SkipPlayStore) {
    Write-Host "  Pulado (-SkipPlayStore)" -ForegroundColor Gray
} else {
    & cmd /c "$FlutterCmd build appbundle --release"
    if ($LASTEXITCODE -eq 0) {
        $aab = "build\app\outputs\bundle\release\app-release.aab"
        if (Test-Path $aab) { Write-Host "  OK -> $aab" -ForegroundColor Green }
    } else {
        Write-Host "  Aviso: build appbundle falhou" -ForegroundColor Yellow
    }
}

# 9. Arquivos estáticos
$step++; Write-Host "`n[$step/11] Arquivos estáticos (.well-known, privacidade)..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path "build\web\.well-known" | Out-Null
if (Test-Path "public\.well-known\assetlinks.json") {
    Copy-Item "public\.well-known\assetlinks.json" "build\web\.well-known\" -Force
}
if (Test-Path "public\privacidade.html") {
    Copy-Item "public\privacidade.html" "build\web\" -Force
}
if (Test-Path "web\privacidade.html") {
    Copy-Item "web\privacidade.html" "build\web\" -Force
}
# Página e CSVs de modelos de planilha (importação no app) — sempre copiar após build web
if (Test-Path "web\modelos-importacao.html") {
    Copy-Item "web\modelos-importacao.html" "build\web\" -Force
    Write-Host "  -> modelos-importacao.html" -ForegroundColor DarkGray
}
if (Test-Path "web\modelos-importacao") {
    $destModelos = "build\web\modelos-importacao"
    if (-not (Test-Path $destModelos)) { New-Item -ItemType Directory -Path $destModelos -Force | Out-Null }
    Copy-Item "web\modelos-importacao\*" $destModelos -Force
    Write-Host "  -> modelos-importacao/*.csv" -ForegroundColor DarkGray
}
Write-Host "  OK" -ForegroundColor Green

# 10. Firebase deploy
$step++; Write-Host "`n[$step/11] Firebase deploy..." -ForegroundColor Yellow
if ($SkipDeploy) {
    Write-Host "  Pulado (-SkipDeploy). Rode manualmente: firebase deploy" -ForegroundColor Gray
} else {
    firebase deploy
    if ($LASTEXITCODE -ne 0) { throw "firebase deploy falhou" }
    Write-Host "  OK: Firestore + Storage + Functions + Hosting" -ForegroundColor Green
}

$step++; Write-Host "`n[$step/11] Concluído." -ForegroundColor Cyan

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Atualização concluída" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Resumo:" -ForegroundColor White
Write-Host "  - App Web / Mobile:  build/web (já no Hosting se fez deploy)" -ForegroundColor Gray
Write-Host "  - APK:              build/app/outputs/flutter-apk/app-release.apk" -ForegroundColor Gray
Write-Host "  - APK no site:      build/web/downloads/masterpalm.apk" -ForegroundColor Gray
if (-not $SkipPlayStore) {
    Write-Host "  - AAB Play Store:   build/app/outputs/bundle/release/app-release.aab" -ForegroundColor Gray
}
Write-Host ""
Write-Host "Para ver só a lista de comandos: .\scripts\ATUALIZAR-TUDO-COMANDOS.ps1 -ApenasLista" -ForegroundColor Gray
Write-Host ""
Write-Host 'IMPORTANTE - Site de marketing (mastepalm.com.br com menu Download / Funcionalidades):' -ForegroundColor Yellow
Write-Host '  Esse site e o projeto em .\site\ (Next.js). O firebase deploy acima NAO publica essa landing.' -ForegroundColor Gray
Write-Host '  Apos alterar site: entre na pasta site, rode npm run build e faca deploy no Vercel ou Netlify (host do dominio).' -ForegroundColor Gray
Write-Host ""
