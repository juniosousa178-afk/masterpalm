# scripts/setup_release.ps1
# Script para preparar o ambiente de release do MasterPalm

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

Write-Host ""
Write-Host "=== MasterPalm - Setup Release ===" -ForegroundColor Cyan
Write-Host ""

# 1. key.properties
$keyPropsExample = Join-Path $projectRoot "android\key.properties.example"
$keyProps = Join-Path $projectRoot "android\key.properties"

if (-not (Test-Path $keyProps)) {
    Write-Host "[1/3] Criando key.properties..." -ForegroundColor Yellow
    Copy-Item $keyPropsExample $keyProps
    Write-Host "      Arquivo criado. EDITE android\key.properties com suas senhas e caminho do keystore." -ForegroundColor Green
    Write-Host "      Para gerar o keystore:" -ForegroundColor Gray
    Write-Host "      keytool -genkey -v -keystore android\app\upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload" -ForegroundColor Gray
} else {
    Write-Host "[1/3] key.properties ja existe." -ForegroundColor Green
}

# 2. Remote Config
Write-Host ""
Write-Host "[2/3] Remote Config" -ForegroundColor Yellow
Write-Host "      Template em: firebase_remote_config_template.json" -ForegroundColor Gray
Write-Host "      Para publicar: Firebase Console > Remote Config > Menu (⋮) > Publicar de um arquivo" -ForegroundColor Gray

# 3. Verificar Firebase CLI
Write-Host ""
Write-Host "[3/3] Verificando Firebase CLI..." -ForegroundColor Yellow
try {
    $firebaseVersion = firebase --version 2>$null
    Write-Host "      Firebase CLI: $firebaseVersion" -ForegroundColor Green
} catch {
    Write-Host "      Firebase CLI nao encontrado. Instale: npm install -g firebase-tools" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Proximos passos ===" -ForegroundColor Cyan
Write-Host "1. Edite android\key.properties (se acabou de criar)"
Write-Host "2. Publique o Remote Config (Console ou firebase deploy --only remoteconfig)"
Write-Host "3. Ative App Check no Firebase Console"
Write-Host "4. Execute: fvm flutter build appbundle --release"
Write-Host ""
