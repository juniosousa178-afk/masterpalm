# Deploy completo: Firestore rules + Cloud Functions + Hosting
# Uso: .\deploy-tudo.ps1
# Para incluir rebuild do site: .\deploy-tudo.ps1 -BuildWeb

param(
    [switch]$BuildWeb
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if ($BuildWeb) {
    Write-Host "Building Flutter web..." -ForegroundColor Cyan
    fvm flutter build web --release
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "Deploying Firebase (rules + functions + hosting)..." -ForegroundColor Cyan
firebase deploy
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Deploy concluido." -ForegroundColor Green
