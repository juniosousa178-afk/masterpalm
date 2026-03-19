# =============================================================================
# MasterPalm - Atualizar Tudo (Auto Wrapper)
# =============================================================================
# Este arquivo é um "atalho" para o script principal `tudo-100.ps1`, deixando
# mais simples para você executar uma atualização completa em um único comando.
#
# Uso:
#   .\scripts\atualizar-tudo-auto.ps1
#   .\scripts\atualizar-tudo-auto.ps1 -IncluirCatalogo
#   .\scripts\atualizar-tudo-auto.ps1 -IncluirSite
#   .\scripts\atualizar-tudo-auto.ps1 -IncluirFunctions
#   .\scripts\atualizar-tudo-auto.ps1 -SemDeploy
#   .\scripts\atualizar-tudo-auto.ps1 -SemWeb -SemApk
# =============================================================================

param(
    [switch]$IncluirCatalogo,
    [switch]$IncluirSite,
    [switch]$IncluirFunctions,
    [switch]$SemDeploy,
    [switch]$ApenasInstalar,
    [switch]$SemWeb,
    [switch]$SemApk
)

$ErrorActionPreference = "Stop"

$wrapperRoot = $PSScriptRoot
$mainScript = Join-Path $wrapperRoot "tudo-100.ps1"

if (-not (Test-Path $mainScript)) {
    throw "Script principal nao encontrado: $mainScript"
}

$forwardArgs = @()
if ($ApenasInstalar)   { $forwardArgs += "-ApenasInstalar" }
if ($IncluirCatalogo) { $forwardArgs += "-IncluirCatalogo" }
if ($IncluirSite)     { $forwardArgs += "-IncluirSite" }
if ($IncluirFunctions){ $forwardArgs += "-IncluirFunctions" }
if ($SemDeploy)       { $forwardArgs += "-SemDeploy" }
if ($SemWeb)          { $forwardArgs += "-SemWeb" }
if ($SemApk)          { $forwardArgs += "-SemApk" }

Write-Host ""
Write-Host "=== MasterPalm: Atualizar Tudo (Auto Wrapper) ===" -ForegroundColor Cyan
Write-Host "Encaminhando para: $mainScript" -ForegroundColor Gray

& "$mainScript" @forwardArgs

