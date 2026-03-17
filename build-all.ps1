# Script para atualizar catálogo, app web, APK Android e todo o sistema
# O app web terá exatamente o mesmo código do APK (mesmo projeto Flutter)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
Set-Location $ProjectRoot

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  MasterPalm - Build Completo" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. Limpar e obter dependências
Write-Host "[1/6] Limpando e obtendo dependências..." -ForegroundColor Yellow
fvm flutter clean
fvm flutter pub get
if ($LASTEXITCODE -ne 0) { throw "fvm flutter pub get falhou" }
Write-Host "  OK" -ForegroundColor Green
Write-Host ""

# 2. Gerar código Hive (se houver models)
Write-Host "[2/6] Gerando código (build_runner)..." -ForegroundColor Yellow
fvm dart run build_runner build --delete-conflicting-outputs 2>$null
Write-Host "  OK" -ForegroundColor Green
Write-Host ""

# 3. Sincronizar versão web
Write-Host "[3/6] Sincronizando versão web (manifest, index.html)..." -ForegroundColor Yellow
fvm dart run tool/sync_web_version.dart
if ($LASTEXITCODE -ne 0) { throw "sync_web_version falhou" }
Write-Host "  OK" -ForegroundColor Green
Write-Host ""

# 4. Build Flutter Web (idêntico ao APK - mesmo código)
Write-Host "[4/6] Compilando Flutter Web (release)..." -ForegroundColor Yellow
fvm flutter build web --release
if ($LASTEXITCODE -ne 0) { throw "fvm flutter build web falhou" }
Write-Host "  OK - build/web" -ForegroundColor Green
Write-Host ""

# 5. Copiar arquivos estáticos
Write-Host "[5/6] Copiando arquivos estáticos..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path "build/web/.well-known" | Out-Null
if (Test-Path "public/.well-known/assetlinks.json") {
    Copy-Item "public/.well-known/assetlinks.json" "build/web/.well-known/"
}
if (Test-Path "public/privacidade.html") {
    Copy-Item "public/privacidade.html" "build/web/"
}
Write-Host "  OK" -ForegroundColor Green
Write-Host ""

# 6. Build APK Android
Write-Host "[6/6] Compilando APK Android (release)..." -ForegroundColor Yellow
fvm flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw "fvm flutter build apk falhou" }
Write-Host "  OK - build/app/outputs/flutter-apk/app-release.apk" -ForegroundColor Green
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  BUILD CONCLUÍDO COM SUCESSO!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Próximos passos:" -ForegroundColor White
Write-Host "  - Deploy Web: firebase deploy --only hosting" -ForegroundColor Gray
Write-Host "  - APK: android/app/build/outputs/flutter-apk/app-release.apk" -ForegroundColor Gray
Write-Host ""
