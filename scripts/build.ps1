# ============================================
# Script Flutter - temp_naty
# ============================================
# Uso: .\scripts\build.ps1 [comando]
# Comandos: get | analyze | run | apk | web | clean | full

param(
    [Parameter(Position=0)]
    [ValidateSet("get", "analyze", "run", "apk", "web", "clean", "full", "doctor")]
    [string]$Acao = "full"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

Write-Host "=== Flutter Script - $Acao ===" -ForegroundColor Cyan
Write-Host "Diretório: $projectRoot`n" -ForegroundColor Gray

function Run-Flutter {
    param([string[]]$FlutterArgs)
    $fullCmd = "fvm flutter " + ($FlutterArgs -join " ")
    Write-Host "> $fullCmd" -ForegroundColor Yellow
    & fvm flutter $FlutterArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

switch ($Acao) {
    "get"    { Run-Flutter @("pub", "get") }
    "analyze"{ Run-Flutter @("analyze") }
    "run"    { Run-Flutter @("run") }
    "apk"    { Run-Flutter @("build", "apk", "--release") }
    "web"    { Run-Flutter @("build", "web", "--release") }
    "clean"  { Run-Flutter @("clean"); Run-Flutter @("pub", "get") }
    "doctor" { Run-Flutter @("doctor", "-v") }
    "full"   {
        Run-Flutter @("pub", "get")
        Run-Flutter @("analyze")
        Write-Host "`nAnalise OK. Para build: .\scripts\build.ps1 apk ou web" -ForegroundColor Green
    }
}

Write-Host "`n=== Concluido ===" -ForegroundColor Green
