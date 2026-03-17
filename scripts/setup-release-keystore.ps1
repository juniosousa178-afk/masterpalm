# MasterPalm - Garantir keystore de release para assinatura consistente
# Evita o erro "conflito com pacote já existente" ao atualizar o APK
#
# Execute uma vez. O release.keystore deve ser commitado no repo para que
# todos os builds (inclusive em outras máquinas/CI) usem a mesma assinatura.
#
# IMPORTANTE: Se você já tem o app instalado com outra assinatura (ex: debug),
# os usuários precisarão DESINSTALAR uma vez e reinstalar. Depois disso,
# todas as atualizações funcionarão normalmente.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$keystorePath = Join-Path $root "android\app\release.keystore"

if (Test-Path $keystorePath) {
    Write-Host "OK: release.keystore já existe em android/app/" -ForegroundColor Green
    exit 0
}

Write-Host "Gerando release.keystore para assinatura consistente..." -ForegroundColor Cyan
Push-Location (Join-Path $root "android\app")
try {
    keytool -genkey -v -keystore release.keystore -keyalg RSA -keysize 2048 -validity 10000 `
        -alias masterpalm -storepass masterpalm2024 -keypass masterpalm2024 `
        -dname "CN=MasterPalm, OU=App, O=MasterPalm, L=SaoPaulo, ST=SP, C=BR"
    Write-Host "OK: release.keystore criado!" -ForegroundColor Green
    Write-Host ""
    Write-Host "IMPORTANTE: Faça commit do arquivo android/app/release.keystore no Git" -ForegroundColor Yellow
    Write-Host "para garantir que todos os builds usem a mesma assinatura." -ForegroundColor Yellow
} finally {
    Pop-Location
}
