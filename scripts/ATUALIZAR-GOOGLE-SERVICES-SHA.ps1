# scripts/ATUALIZAR-GOOGLE-SERVICES-SHA.ps1
# Adiciona SHA-1 do Play App Signing ao Firebase e orienta atualização do google-services.json.
# Uso: .\scripts\ATUALIZAR-GOOGLE-SERVICES-SHA.ps1

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

Write-Host "=== Atualizar SHA-1 do Google Play no Firebase ===" -ForegroundColor Cyan
Write-Host ""

# Verifica Python
$pythonCmd = $null
foreach ($cmd in @("python", "python3", "py")) {
    try {
        $null = & $cmd --version 2>$null
        $pythonCmd = $cmd
        break
    } catch { }
}

if (-not $pythonCmd) {
    Write-Host "ERRO: Python nao encontrado. Instale Python 3 e adicione ao PATH." -ForegroundColor Red
    Write-Host ""
    Write-Host "Alternativa manual:" -ForegroundColor Yellow
    Write-Host "1. Firebase Console: https://console.firebase.google.com/project/masterpalm-58c46/settings/general"
    Write-Host "2. App Android -> Adicionar impressao digital SHA-1:"
    Write-Host "   11:E2:52:35:37:07:C6:C2:CB:D2:F2:DD:72:58:F2:6D:0E:8D:A4:FC"
    Write-Host "3. Baixar novo google-services.json e substituir em android\app\"
    exit 1
}

# Instala dependências se necessário
Write-Host "Verificando dependencias Python..." -ForegroundColor Gray
& $pythonCmd -m pip install --quiet google-auth requests 2>&1 | Out-Null

# Executa script
& $pythonCmd "$ScriptDir\atualizar_google_services_sha.py"
$exitCode = $LASTEXITCODE

if ($exitCode -eq 0) {
    Write-Host ""
    Write-Host "Em seguida, rode: flutter clean && flutter pub get" -ForegroundColor Green
}
exit $exitCode
