# =============================================================================
# MasterPalm - Atualizar somente índices do Firestore
# =============================================================================
# Uso:
#   .\scripts\atualizar-firestore-indices.ps1
#   .\scripts\atualizar-firestore-indices.ps1 -ProjectId "masterpalm-58c46"
#
# Observação:
# - Após o deploy, os índices ficam "Ativando" por alguns minutos.
# - Se a venda ainda falhar, espere o índice virar "Enabled" e tente novamente.
# =============================================================================

param(
    [string]$ProjectId = ""
)

$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
if ($root -match "scripts$") {
    $root = Split-Path -Parent $root
}
Set-Location $root

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " MasterPalm - Atualizar Firestore Indexes" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$args = @("deploy", "--only", "firestore:indexes")
if ([string]::IsNullOrWhiteSpace($ProjectId) -eq $false) {
    $args += @("--project", $ProjectId)
    Write-Host "Projeto: $ProjectId" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Executando: firebase $($args -join ' ')" -ForegroundColor Yellow
& firebase @args

if ($LASTEXITCODE -ne 0) {
    throw "Falha ao fazer deploy dos índices do Firestore (exit code $LASTEXITCODE)"
}

Write-Host ""
Write-Host "Deploy concluido. Aguarde alguns minutos para os índices ficarem 'Enabled'." -ForegroundColor Green
Write-Host "Se continuar falhando, tente de novo após os índices ativarem." -ForegroundColor Gray

