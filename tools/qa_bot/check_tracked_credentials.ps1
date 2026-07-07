#Requires -Version 5.1
<#
.SYNOPSIS
  Preflight read-only: detecta credenciais Google service account em arquivos TRACKED.
  Nunca imprime private_key nem JSON integral.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsTrackedServiceAccountCredential {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath
  )

  if (-not (Test-Path -LiteralPath $FilePath)) {
    return $false
  }

  try {
    $content = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8
  } catch {
    return $false
  }

  if ([string]::IsNullOrWhiteSpace($content)) {
    return $false
  }

  $hasType = $content -match '"type"\s*:\s*"service_account"'
  $hasPrivateKeyBlock = $content -match '-----BEGIN PRIVATE KEY-----'

  return ($hasType -and $hasPrivateKeyBlock)
}

function Test-ShouldScanTrackedPath {
  param([string]$RelPath)

  $normalized = $RelPath.Trim().Trim('"').Replace('\', '/').ToLowerInvariant()
  if ($normalized -match '\.(json|pem|p12|key)$') { return $true }
  if ($normalized -match 'serviceaccount|credentials|/sa\.json|adminsdk') { return $true }
  return $false
}

function Get-TrackedCredentialFindings {
  param(
    [string]$RepoRoot = (Get-Location).Path
  )

  Push-Location $RepoRoot
  try {
    $tracked = @(git ls-files)
    $findings = @()

    foreach ($relRaw in $tracked) {
      $rel = $relRaw.Trim().Trim('"')
      if ([string]::IsNullOrWhiteSpace($rel)) { continue }
      if (-not (Test-ShouldScanTrackedPath -RelPath $rel)) { continue }
      if ($rel.IndexOfAny([IO.Path]::GetInvalidPathChars()) -ge 0) { continue }

      $full = Join-Path $RepoRoot ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
      try {
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
      } catch {
        continue
      }

      if (Test-IsTrackedServiceAccountCredential -FilePath $full) {
        $findings += [ordered]@{
          path         = $rel
          classification = 'TRACKED_SERVICE_ACCOUNT_CREDENTIAL'
        }
      }
    }

    return $findings
  } finally {
    Pop-Location
  }
}

function Invoke-TrackedCredentialsPreflight {
  param(
    [string]$RepoRoot = (Get-Location).Path
  )

  $findings = @(Get-TrackedCredentialFindings -RepoRoot $RepoRoot)

  if ($findings.Count -eq 0) {
    Write-Host 'TRACKED_CREDENTIALS_PREFLIGHT PASS (0 findings)'
    return 0
  }

  Write-Host "TRACKED_CREDENTIALS_PREFLIGHT FAIL ($($findings.Count) finding(s))"
  foreach ($f in $findings) {
    Write-Host "  $($f.path) [$($f.classification)]"
  }
  return 1
}

# Execução direta (não quando dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
  $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
  $RepoRoot = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
  $exitCode = Invoke-TrackedCredentialsPreflight -RepoRoot $RepoRoot
  exit $exitCode
}
