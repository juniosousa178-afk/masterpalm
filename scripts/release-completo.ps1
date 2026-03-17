# MasterPalm - Script de Release Completo
# Atualiza versao, builda e publica em todos os canais: Web, APK, AAB (Play Store)
#
# Uso: .\scripts\release-completo.ps1
#      .\scripts\release-completo.ps1 -SkipPlayStore
#      .\scripts\release-completo.ps1 -Versao "1.0.30+40"

param(
    [switch]$SkipPlayStore,
    [switch]$SkipFunctions,
    [string]$Versao = ""   # ex: "1.0.30+40" - se vazio, incrementa automatico
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

$pubspec = Join-Path $ProjectRoot "pubspec.yaml"

# --- Helper: ler versao atual ---
function Get-PubspecVersion {
    $content = Get-Content $pubspec -Raw
    if ($content -match 'version:\s*([\d.]+)\+(\d+)') {
        return @{ Name = $matches[1]; Build = [int]$matches[2] }
    }
    throw "Versao nao encontrada no pubspec.yaml"
}

# --- Helper: atualizar versao no pubspec ---
function Set-PubspecVersion {
    param([string]$Name, [int]$Build)
    $content = Get-Content $pubspec -Raw
    $content = $content -replace 'version:\s*[\d.]+\+\d+', "version: $Name+$Build"
    Set-Content $pubspec -Value $content -NoNewline
}

Write-Host ""
Write-Host "========================================"
Write-Host " MasterPalm - Release Completo"
Write-Host "========================================"
Write-Host ""

# 1. Atualizar versao (se solicitado)
if ($Versao -ne "") {
    if ($Versao -match '^([\d.]+)\+(\d+)$') {
        Set-PubspecVersion -Name $matches[1] -Build [int]$matches[2]
        Write-Host "[1] Versao definida: $Versao" -ForegroundColor Cyan
    } else {
        Write-Host "ERRO: Versao invalida. Use formato: 1.0.30+40" -ForegroundColor Red
        exit 1
    }
} else {
    $atual = Get-PubspecVersion
    $novoBuild = $atual.Build + 1
    # Mantem o mesmo nome de versao, incrementa build
    Set-PubspecVersion -Name $atual.Name -Build $novoBuild
    Write-Host "[1] Versao incrementada: $($atual.Name)+$novoBuild (era $($atual.Name)+$($atual.Build))" -ForegroundColor Cyan
}

$versaoAtual = Get-PubspecVersion
$versaoStr = "$($versaoAtual.Name)+$($versaoAtual.Build)"
Write-Host ""

# 2. Dependencias
Write-Host "[2/9] fvm flutter pub get..." -ForegroundColor Cyan
fvm flutter pub get
if ($LASTEXITCODE -ne 0) { throw "pub get falhou" }
Write-Host "  OK" -ForegroundColor Green

# 3. Limpar build antigo
Write-Host "`n[3/9] fvm flutter clean..." -ForegroundColor Cyan
fvm flutter clean
fvm flutter pub get
Write-Host "  OK" -ForegroundColor Green

# 4. Build runner (Hive)
Write-Host "`n[4/9] build_runner..." -ForegroundColor Cyan
fvm dart run build_runner build --delete-conflicting-outputs 2>$null
Write-Host "  OK" -ForegroundColor Green

# 5. Sincronizar versao web (manifest.json, index.html)
Write-Host "`n[5/9] Sincronizar versao web..." -ForegroundColor Cyan
fvm dart run tool/sync_web_version.dart
if ($LASTEXITCODE -ne 0) { throw "sync_web_version falhou" }
Write-Host "  OK" -ForegroundColor Green

# 6. Build Web (app web + mobile web + desktop web + catalogo online)
Write-Host "`n[6/9] fvm flutter build web --release..." -ForegroundColor Cyan
fvm flutter build web --release
if ($LASTEXITCODE -ne 0) { throw "build web falhou" }
Write-Host "  OK - build/web (app web, mobile web, catalogo online)" -ForegroundColor Green

# 7. Build APK
Write-Host "`n[7/9] fvm flutter build apk --release..." -ForegroundColor Cyan
fvm flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw "build apk falhou" }

$apkSrc = "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apkSrc)) { $apkSrc = "android\app\build\outputs\apk\release\app-release.apk" }
if (Test-Path $apkSrc) {
    $destDir = "build\web\downloads"
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir | Out-Null }
    Copy-Item $apkSrc -Destination "$destDir\masterpalm.apk" -Force
    Write-Host "  OK - APK copiado para build\web\downloads\masterpalm.apk" -ForegroundColor Green
} else {
    Write-Host "  AVISO: APK nao encontrado" -ForegroundColor Yellow
}

# 8. Build AAB (Play Store)
if ($SkipPlayStore) {
    Write-Host "`n[8/9] AAB (Play Store): pulado (-SkipPlayStore)" -ForegroundColor Yellow
} else {
    Write-Host "`n[8/9] fvm flutter build appbundle --release..." -ForegroundColor Cyan
    fvm flutter build appbundle --release
    if ($LASTEXITCODE -eq 0) {
        $aabPath = "build\app\outputs\bundle\release\app-release.aab"
        if (Test-Path $aabPath) {
            Write-Host "  OK - AAB em: $aabPath" -ForegroundColor Green
            Write-Host "      Publique em: https://play.google.com/console" -ForegroundColor Gray
        }
    } else {
        Write-Host "  AVISO: build appbundle falhou" -ForegroundColor Yellow
    }
}

# 9. Copiar arquivos estaticos
Write-Host "`n[9/9] Copiando arquivos estaticos..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path "build\web\.well-known" | Out-Null
if (Test-Path "public\.well-known\assetlinks.json") {
    Copy-Item "public\.well-known\assetlinks.json" "build\web\.well-known\" -Force
}
if (Test-Path "public\privacidade.html") {
    Copy-Item "public\privacidade.html" "build\web\" -Force
}
Write-Host "  OK" -ForegroundColor Green

# Deploy Firebase
Write-Host ""
Write-Host "========================================"
Write-Host "  COMANDOS DE PUBLICACAO"
Write-Host "========================================"
Write-Host ""
Write-Host "Versao atual: $versaoStr" -ForegroundColor White
Write-Host ""
Write-Host "1. WEB (app, mobile web, desktop, catalogo):" -ForegroundColor Cyan
Write-Host "   firebase deploy --only hosting" -ForegroundColor White
Write-Host "   -> https://mastepalm.com.br | https://app.mastepalm.com.br" -ForegroundColor Gray
Write-Host ""
Write-Host "2. FIREBASE FUNCTIONS (se necessario):" -ForegroundColor Cyan
Write-Host "   firebase deploy --only functions" -ForegroundColor White
Write-Host ""
Write-Host "3. TUDO (hosting + functions + rules + storage):" -ForegroundColor Cyan
Write-Host "   firebase deploy" -ForegroundColor White
Write-Host ""
Write-Host "4. PLAY STORE (Android):" -ForegroundColor Cyan
Write-Host "   - Abra: https://play.google.com/console" -ForegroundColor White
Write-Host "   - Selecione o app MasterPalm" -ForegroundColor White
Write-Host "   - Producao > Criar nova versao > Fazer upload do AAB:" -ForegroundColor White
Write-Host "     build\app\outputs\bundle\release\app-release.aab" -ForegroundColor Gray
Write-Host "   - Preencha as notas da versao e publique" -ForegroundColor White
Write-Host ""
Write-Host "5. APK DIRETO (download no site):" -ForegroundColor Cyan
Write-Host "   Ja incluido em build/web/downloads/ - sera publicado com hosting" -ForegroundColor Gray
Write-Host "   URL: https://mastepalm.com.br/downloads/masterpalm.apk" -ForegroundColor Gray
Write-Host ""
Write-Host "========================================"
Write-Host ""

# Perguntar se quer fazer deploy agora (opcional)
$deploy = Read-Host "Deseja executar firebase deploy --only hosting agora? (s/N)"
if ($deploy -eq "s" -or $deploy -eq "S") {
    firebase deploy --only hosting
    if ($LASTEXITCODE -ne 0) { throw "firebase deploy falhou" }
    Write-Host ""
    Write-Host "Deploy concluido!" -ForegroundColor Green
    Write-Host "- App Web:    https://mastepalm.com.br" -ForegroundColor White
    Write-Host "- Download:   https://mastepalm.com.br/downloads/masterpalm.apk" -ForegroundColor White
    Write-Host "- Catalogo:   https://mastepalm.com.br/c/SEU-SLUG" -ForegroundColor White
}
Write-Host ""
