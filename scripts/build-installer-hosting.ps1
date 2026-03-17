# MasterPalm - Build instalador (APK) e prepara para hospedar no site mastepalm.com.br
# Uso: .\scripts\build-installer-hosting.ps1
# Gera o APK, copia para build/web/downloads/ e prepara a pasta para firebase deploy

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
Set-Location $root

Write-Host "`n==> 1/4 Dependencias Flutter" -ForegroundColor Cyan
fvm flutter pub get
if ($LASTEXITCODE -ne 0) { throw "fvm flutter pub get falhou" }
Write-Host "OK: Dependencias instaladas" -ForegroundColor Green

Write-Host "`n==> 2/4 Build APK (release)" -ForegroundColor Cyan
fvm flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw "fvm flutter build apk falhou" }
$apkSource = Join-Path $root "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apkSource)) { throw "APK nao encontrado em $apkSource" }
Write-Host "OK: APK gerado" -ForegroundColor Green

Write-Host "`n==> 3/4 Build Web (para site)" -ForegroundColor Cyan
fvm flutter build web --release
if ($LASTEXITCODE -ne 0) { throw "fvm flutter build web falhou" }
Write-Host "OK: Build web concluido" -ForegroundColor Green

Write-Host "`n==> 4/4 Copiando APK e pagina de download para build/web" -ForegroundColor Cyan
$buildWeb = Join-Path $root "build\web"
$downloadsDir = Join-Path $buildWeb "downloads"
if (-not (Test-Path $downloadsDir)) { New-Item -ItemType Directory -Path $downloadsDir -Force | Out-Null }

# Copia APK com nome amigavel
$apkDest = Join-Path $downloadsDir "masterpalm.apk"
Copy-Item $apkSource $apkDest -Force
Write-Host "   APK copiado para: build/web/downloads/masterpalm.apk" -ForegroundColor Gray

# Copia pagina de download (se existir em web/)
$downloadHtml = Join-Path $root "web\download.html"
if (Test-Path $downloadHtml) {
    Copy-Item $downloadHtml (Join-Path $buildWeb "download.html") -Force
    Write-Host "   Pagina de download copiada: build/web/download.html" -ForegroundColor Gray
}

# Versao do pubspec
$version = (Get-Content (Join-Path $root "pubspec.yaml") -Raw) -match 'version:\s*([^\s+]+)' | Out-Null; $v = $matches[1]
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  Instalador pronto para deploy!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "  APK: build/web/downloads/masterpalm.apk" -ForegroundColor White
Write-Host "  Pagina: https://mastepalm.com.br/download.html" -ForegroundColor White
Write-Host "  (ou app.mastepalm.com.br/download.html)" -ForegroundColor Gray
Write-Host "`n  Para publicar, execute: firebase deploy" -ForegroundColor Yellow
Write-Host "========================================`n" -ForegroundColor Green
