# =============================================================================
# Script completo: build e deploy MasterPalm (PowerShell - Windows)
# - App Web (catálogo + PWA)
# - APK Android (release) + cópia para download no site
# - Opcional: desktop Windows e análise estática
# =============================================================================

param(
    [switch]$Analyze,
    [switch]$NoWeb,
    [switch]$NoApk,
    [switch]$Desktop,
    [switch]$NoCopyApk,
    [switch]$NoSyncVersion,
    [switch]$Deploy,
    [string]$Target = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

. (Join-Path $PSScriptRoot "_dart_from_flutter.ps1")
$FlutterCmd = $script:FlutterCmd

$RunAnalyze = $Analyze
$BuildWeb = -not $NoWeb
$BuildApk = -not $NoApk
$BuildDesktop = $Desktop
$CopyApkToWeb = -not $NoCopyApk
$SyncVersion = -not $NoSyncVersion
$DeployHosting = $Deploy

Write-Host "=============================================="
Write-Host "  MasterPalm - Build e Deploy"
Write-Host "=============================================="
Write-Host "  Analisar:      $RunAnalyze"
Write-Host "  Build Web:     $BuildWeb"
Write-Host "  Build APK:     $BuildApk"
Write-Host "  Build Desktop: $BuildDesktop"
Write-Host "  Copiar APK:    $CopyApkToWeb"
Write-Host "  Sync versão:   $SyncVersion"
Write-Host "  Deploy:        $DeployHosting"
Write-Host "=============================================="

if ($RunAnalyze) {
    Write-Host ""
    Write-Host "🔍 Executando flutter analyze..."
    & cmd /c "$FlutterCmd analyze"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host "✅ Análise concluída."
}

if ($SyncVersion) {
    Write-Host ""
    Write-Host "🔄 Sincronizando versão web..."
    if (Test-Path "tool/sync_web_version.dart") {
        Invoke-ProjDart run tool/sync_web_version.dart
    } else {
        Write-Host "⚠️ tool/sync_web_version.dart não encontrado."
    }
}

if ($BuildWeb) {
    Write-Host ""
    Write-Host "🌐 Compilando Flutter Web (release)..."
    & cmd /c "$FlutterCmd build web --release"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host "✅ Build web concluído."
}

Write-Host ""
Write-Host "📄 Copiando arquivos estáticos..."
New-Item -ItemType Directory -Force -Path "build/web/.well-known" | Out-Null
if (Test-Path "public/.well-known/assetlinks.json") {
    Copy-Item "public/.well-known/assetlinks.json" "build/web/.well-known/"
    Write-Host "  .well-known/assetlinks.json"
}
if (Test-Path "public/privacidade.html") {
    Copy-Item "public/privacidade.html" "build/web/"
    Write-Host "  privacidade.html"
}

if ($BuildApk) {
    Write-Host ""
    Write-Host "📱 Compilando APK Android (release)..."
    & cmd /c "$FlutterCmd build apk --release"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host "✅ Build APK concluído."

    if ($CopyApkToWeb) {
        New-Item -ItemType Directory -Force -Path "build/web/downloads" | Out-Null
        $ApkSrc = "build/app/outputs/flutter-apk/app-release.apk"
        if (Test-Path $ApkSrc) {
            Copy-Item $ApkSrc "build/web/downloads/masterpalm.apk"
            Write-Host "  APK copiado para build/web/downloads/masterpalm.apk"
        } else {
            Write-Host "⚠️ APK não encontrado em $ApkSrc"
        }
    }
}

if ($BuildDesktop) {
    Write-Host ""
    Write-Host "🖥️ Compilando Windows..."
    & cmd /c "$FlutterCmd build windows --release"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host "✅ Build Windows concluído."
}

if ($DeployHosting) {
    Write-Host ""
    Write-Host "🚀 Deploy Firebase Hosting..."
    if ($Target) {
        firebase deploy --only hosting:$Target
    } else {
        firebase deploy --only hosting
    }
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    Write-Host "✅ Deploy concluído!"
}

Write-Host ""
Write-Host "=============================================="
Write-Host "  Concluído"
Write-Host "=============================================="
Write-Host "  Web:   build/web"
if ($BuildApk) { Write-Host "  APK:   build/app/outputs/flutter-apk/app-release.apk" }
Write-Host ""
Write-Host "Para publicar: .\scripts\deploy-completo.ps1 -Deploy"
Write-Host ""
