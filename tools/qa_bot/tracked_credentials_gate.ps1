#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-TrackedCredentialsGate {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [Parameter(Mandatory = $true)]
    [string]$CredCheckScript
  )

  if (-not (Test-Path -LiteralPath $CredCheckScript)) {
    return @{
      passed   = $false
      exitCode = 2
      detail   = "script ausente: $CredCheckScript"
    }
  }

  Push-Location $RepoRoot
  try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $CredCheckScript -RepoRoot $RepoRoot | Out-Null
    $exitCode = $LASTEXITCODE
  } finally {
    Pop-Location
  }

  return [pscustomobject]@{
    passed   = ($exitCode -eq 0)
    exitCode = $exitCode
    detail   = if ($exitCode -eq 0) { 'PASS 0 findings' } else { 'FAIL tracked credential detectada' }
  }
}
