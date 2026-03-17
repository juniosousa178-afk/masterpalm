# Corrige vulnerabilidades npm em functions, main e scripts
# Uso: .\scripts\fix-npm-vulnerabilities.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$dirs = @("functions", "main", "scripts")
foreach ($dir in $dirs) {
    $pkg = Join-Path (Join-Path $root $dir) "package.json"
    if (-not (Test-Path $pkg)) { continue }
    Write-Host "`n==> $dir" -ForegroundColor Cyan
    Push-Location (Join-Path $root $dir)
    Remove-Item package-lock.json -ErrorAction SilentlyContinue
    npm install
    npm audit fix
    if ($LASTEXITCODE -ne 0) { npm audit fix --force 2>$null }
    npm audit 2>&1
    Pop-Location
}
Write-Host "`nConcluido." -ForegroundColor Green
