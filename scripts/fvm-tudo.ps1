# MasterPalm - Script completo Flutter/Dart
# Usa fvm se disponivel, senao .fvm/flutter_sdk ou flutter global.
#
# Uso:
#   .\scripts\fvm-tudo.ps1              # setup + build completo
#   .\scripts\fvm-tudo.ps1 -Setup      # só setup
#   .\scripts\fvm-tudo.ps1 -Build      # só builds (web, apk, aab)
#   .\scripts\fvm-tudo.ps1 -Test       # só testes
#   .\scripts\fvm-tudo.ps1 -Deploy     # setup + build + firebase deploy

param(
    [switch]$Setup,
    [switch]$Build,
    [switch]$Test,
    [switch]$Deploy
)

$ErrorActionPreference = "Stop"
$root = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { Get-Location }
Set-Location $root

# Detectar flutter/dart: fvm > .fvm/flutter_sdk > global
$flutterCmd = $null
$dartCmd = $null
if (Get-Command fvm -ErrorAction SilentlyContinue) {
    $flutterCmd = "fvm flutter"; $dartCmd = "fvm dart"
} elseif (Test-Path ".fvm\flutter_sdk\bin\flutter.bat") {
    $flutterCmd = ".\.fvm\flutter_sdk\bin\flutter.bat"
    $dartCmd = ".\.fvm\flutter_sdk\bin\dart.bat"
} elseif (Get-Command flutter -ErrorAction SilentlyContinue) {
    $flutterCmd = "flutter"; $dartCmd = "dart"
}
if (-not $flutterCmd) {
    Write-Host "ERRO: Flutter nao encontrado. Instale Flutter ou FVM e configure o PATH." -ForegroundColor Red
    Write-Host "  - FVM: dart pub global activate fvm" -ForegroundColor Gray
    Write-Host "  - Flutter: https://docs.flutter.dev/get-started/install/windows" -ForegroundColor Gray
    exit 1
}
Write-Host "Usando: $flutterCmd" -ForegroundColor Gray

function Step { param($n, $msg) Write-Host "`n[$n] $msg" -ForegroundColor Cyan }
function Ok   { Write-Host "  OK" -ForegroundColor Green }
function Run  { param($cmd) Invoke-Expression $cmd; if ($LASTEXITCODE -ne 0) { throw "Falhou" } }

# Se nenhum flag, faz setup + build
$doSetup = $Setup -or $Deploy -or (-not $Setup -and -not $Build -and -not $Test)
$doBuild = $Build -or $Deploy -or (-not $Setup -and -not $Build -and -not $Test -and -not $Deploy)
$doTest  = $Test

Write-Host ""
Write-Host "========================================"
Write-Host " MasterPalm - FVM (Flutter Version Manager)"
Write-Host "========================================"

# --- SETUP ---
if ($doSetup) {
    Step "1/5" "flutter pub get"
    Run "$flutterCmd pub get"
    Ok

    Step "2/5" "flutter clean + pub get"
    try { Invoke-Expression "$flutterCmd clean" 2>$null | Out-Null } catch {}
    Run "$flutterCmd pub get"
    Ok

    Step "3/5" "dart run build_runner build --delete-conflicting-outputs"
    Invoke-Expression "$dartCmd run build_runner build --delete-conflicting-outputs" 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  AVISO: build_runner falhou (pode ignorar se nao alterou modelos Hive). Continuando..." -ForegroundColor Yellow
    } else { Ok }

    Step "4/5" "dart run tool/sync_web_version.dart"
    Run "$dartCmd run tool/sync_web_version.dart"
    Ok

    Step "5/5" "flutter analyze"
    Invoke-Expression "$flutterCmd analyze 2>`$null" | Out-Null
    if ($LASTEXITCODE -eq 0) { Ok } else { Write-Host "  Avisos/erros no analyze" -ForegroundColor Yellow }
}

# --- TEST ---
if ($doTest) {
    Write-Host ""
    Step "TEST" "flutter test"
    Run "$flutterCmd test"
    Ok
}

# --- BUILD ---
if ($doBuild) {
    Write-Host ""
    Step "BUILD WEB" "flutter build web --release"
    Run "$flutterCmd build web --release"
    Ok

    Step "BUILD APK" "flutter build apk --release"
    Run "$flutterCmd build apk --release"
    Ok

    $apkSrc = "build\app\outputs\flutter-apk\app-release.apk"
    if (-not (Test-Path $apkSrc)) { $apkSrc = "android\app\build\outputs\apk\release\app-release.apk" }
    if (Test-Path $apkSrc) {
        $dir = "build\web\downloads"
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
        Copy-Item $apkSrc "$dir\masterpalm.apk" -Force
        Write-Host "  APK copiado para build\web\downloads\masterpalm.apk" -ForegroundColor Green
    }

    Step "BUILD AAB" "flutter build appbundle --release"
    Invoke-Expression "$flutterCmd build appbundle --release" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Ok } else { Write-Host "  Aviso: appbundle falhou" -ForegroundColor Yellow }
}

# --- DEPLOY ---
if ($Deploy) {
    Write-Host ""
    Step "DEPLOY" "firebase deploy --only hosting"
    Run "firebase deploy --only hosting"
    Ok
    Write-Host "  App Web: https://mastepalm.com.br" -ForegroundColor White
    Write-Host "  APK:     https://mastepalm.com.br/downloads/masterpalm.apk" -ForegroundColor White
}

Write-Host ""
Write-Host "========================================"
Write-Host " Concluido" -ForegroundColor Green
Write-Host "========================================"
Write-Host ""
