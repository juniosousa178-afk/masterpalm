# MasterPalm - Script completo de deploy (PowerShell)
# Uso: .\scripts\deploy_full.ps1 [-SkipApk] [-SkipFunctions] [-SkipHosting]
# Exemplo: .\scripts\deploy_full.ps1 -SkipApk  (só web + functions, mais rápido)

param(
    [switch]$SkipApk,
    [switch]$SkipFunctions,
    [switch]$SkipHosting
)

$ErrorActionPreference = "Stop"
Push-Location $PSScriptRoot\..

try {
    Write-Host ""
    Write-Host "========================================"
    Write-Host " MasterPalm - Deploy Completo"
    Write-Host "========================================"
    Write-Host ""

    # 1) Dependencies
    Write-Host "[1/7] fvm flutter pub get..." -ForegroundColor Cyan
    fvm flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "fvm flutter pub get falhou" }

    # 2) Analyze
    Write-Host "`n[2/7] fvm flutter analyze..." -ForegroundColor Cyan
    fvm flutter analyze 2>$null; if ($LASTEXITCODE -ne 0) { Write-Host "  AVISO: analyze encontrou problemas" -ForegroundColor Yellow }

    # 3) Build Web
    Write-Host "`n[3/7] fvm flutter build web --release..." -ForegroundColor Cyan
    fvm flutter build web --release
    if ($LASTEXITCODE -ne 0) { throw "build web falhou" }

    # 4) Build APK
    if ($SkipApk) {
        Write-Host "`n[4/7] APK: pulado (-SkipApk)" -ForegroundColor Yellow
    } else {
        Write-Host "`n[4/7] fvm flutter build apk --release..." -ForegroundColor Cyan
        fvm flutter build apk --release
        if ($LASTEXITCODE -ne 0) { throw "build apk falhou" }

        $apkSrc = "build\app\outputs\flutter-apk\app-release.apk"
        if (-not (Test-Path $apkSrc)) { $apkSrc = "android\app\build\outputs\apk\release\app-release.apk" }
        if (Test-Path $apkSrc) {
            $destDir = "build\web\downloads"
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir | Out-Null }
            Copy-Item $apkSrc -Destination "$destDir\masterpalm.apk" -Force
            Write-Host "  APK copiado para build\web\downloads\masterpalm.apk" -ForegroundColor Green
        } else {
            Write-Host "  AVISO: APK nao encontrado" -ForegroundColor Yellow
        }
    }

    # 5) Deploy Functions
    if (-not $SkipFunctions) {
        Write-Host "`n[5/7] firebase deploy --only functions..." -ForegroundColor Cyan
        firebase deploy --only functions
        if ($LASTEXITCODE -ne 0) { throw "deploy functions falhou" }
    } else {
        Write-Host "`n[5/7] Functions: pulado" -ForegroundColor Yellow
    }

    # 6) Deploy Hosting
    if (-not $SkipHosting) {
        Write-Host "`n[6/7] firebase deploy --only hosting..." -ForegroundColor Cyan
        firebase deploy --only hosting
        if ($LASTEXITCODE -ne 0) { throw "deploy hosting falhou" }
    } else {
        Write-Host "`n[6/7] Hosting: pulado" -ForegroundColor Yellow
    }

    # 7) Rules
    Write-Host "`n[7/7] firebase deploy --only firestore:rules,storage..." -ForegroundColor Cyan
    firebase deploy --only firestore:rules,storage 2>$null

    Write-Host ""
    Write-Host "========================================"
    Write-Host " Deploy concluido com sucesso!" -ForegroundColor Green
    Write-Host "========================================"
    Write-Host ""
    Write-Host "- App Web:   https://mastepalm.com.br"
    Write-Host "- Download:  https://mastepalm.com.br/downloads/masterpalm.apk"
    Write-Host "- Catalogo:  https://mastepalm.com.br/c/SEU-SLUG"
    Write-Host ""

} catch {
    Write-Host ""
    Write-Host "ERRO: $_" -ForegroundColor Red
    exit 1
} finally {
    Pop-Location
}
