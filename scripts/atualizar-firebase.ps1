# Script para atualizar o Firebase diretamente
# - Atualiza SHA-1 e SHA-256 do app Android no Firebase (corrige DEVELOPER_ERROR)
# - Opcional: faz deploy das Functions
#
# Uso: .\scripts\atualizar-firebase.ps1
#      .\scripts\atualizar-firebase.ps1 -DeployFunctions

param(
    [switch]$DeployFunctions = $false,
    [switch]$ShaOnly = $false
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir

Set-Location $RootDir

Write-Host ""
Write-Host "════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Atualizar Firebase - MasterPalm" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# 1. Atualizar SHA no Firebase
Write-Host "[1/2] Atualizando SHA-1 e SHA-256 no Firebase..." -ForegroundColor Yellow
Write-Host "      (corrige INSTALL_FAILED_UPDATE_INCOMPATIBLE / DEVELOPER_ERROR)" -ForegroundColor Gray
Write-Host ""

if (-not (Test-Path "$ScriptDir\serviceAccountKey.json")) {
    Write-Host "ERRO: serviceAccountKey.json nao encontrado em scripts\" -ForegroundColor Red
    Write-Host "      Copie de functions\serviceAccountKey.json ou baixe do Firebase Console" -ForegroundColor Gray
    Write-Host "      Firebase Console -> Configuracoes do projeto -> Contas de servico" -ForegroundColor Gray
    exit 1
}

Push-Location $ScriptDir
try {
    if (-not (Test-Path "node_modules")) {
        Write-Host "      Instalando dependencias (npm install)..." -ForegroundColor Gray
        npm install --silent 2>$null
    }
    node atualizar-sha-firebase.js
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
    Pop-Location
}

Write-Host ""

if ($ShaOnly) {
    Write-Host "Concluido (apenas SHA)." -ForegroundColor Green
    exit 0
}

# 2. Deploy Functions (opcional)
if ($DeployFunctions) {
    Write-Host "[2/2] Fazendo deploy das Functions..." -ForegroundColor Yellow
    Push-Location "$RootDir\functions"
    try {
        npx firebase deploy --only functions
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    } finally {
        Pop-Location
    }
    Write-Host ""
    Write-Host "Deploy concluido." -ForegroundColor Green
} else {
    Write-Host "[2/2] Deploy de Functions ignorado." -ForegroundColor Gray
    Write-Host "      Use -DeployFunctions para publicar as Cloud Functions" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Proximos passos opcionais:" -ForegroundColor Cyan
    Write-Host "  - Baixe o novo google-services.json em:" -ForegroundColor Gray
    Write-Host "    Firebase Console -> Configuracoes do projeto -> Seus apps -> Android" -ForegroundColor Gray
    Write-Host "  - Para deploy das Functions: .\scripts\atualizar-firebase.ps1 -DeployFunctions" -ForegroundColor Gray
}

Write-Host ""
