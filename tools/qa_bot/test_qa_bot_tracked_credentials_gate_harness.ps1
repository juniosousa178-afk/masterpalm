#Requires -Version 5.1
<#
  QASEC-1..5: integracao fail-closed de check_tracked_credentials no run_qa_bot (M1P0).
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
$RunQaBot = Join-Path $ScriptDir 'run_qa_bot.ps1'
$CredCheck = Join-Path $ScriptDir 'check_tracked_credentials.ps1'
$GateModule = Join-Path $ScriptDir 'tracked_credentials_gate.ps1'
. $GateModule
$MatrixPath = Join-Path $ScriptDir 'flow_matrix.json'
$MatrixHashBefore = (Get-FileHash -LiteralPath $MatrixPath -Algorithm SHA256).Hash

$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True {
  param([bool]$Cond, [string]$Label)
  if (-not $Cond) { [void]$failures.Add($Label) }
}

function Assert-False {
  param([bool]$Cond, [string]$Label)
  Assert-True -Cond:(-not $Cond) -Label $Label
}

# QASEC-1: preflight PASS no repo real -> gate retorna passed
$gatePass = Invoke-TrackedCredentialsGate -RepoRoot $RepoRoot -CredCheckScript $CredCheck
Assert-True ($gatePass.passed -eq $true) 'QASEC-1: gate PASS quando repo limpo'
Assert-True ($gatePass.exitCode -eq 0) 'QASEC-1: exit code 0'

# QASEC-2: preflight FAIL em repo temporario -> gate bloqueia (nao executa matriz)
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("qa_gate_fail_" + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Force -Path $tempRoot
$leakPath = Join-Path $tempRoot 'leak.json'
@'
{
  "type": "service_account",
  "project_id": "fake-project",
  "private_key": "-----BEGIN PRIVATE KEY-----\nFAKE_TEST_KEY_NOT_A_REAL_CREDENTIAL\n-----END PRIVATE KEY-----\n"
}
'@ | Set-Content -LiteralPath $leakPath -Encoding UTF8

Push-Location $tempRoot
try {
  git init -q | Out-Null
  git add leak.json | Out-Null
  $gateFail = Invoke-TrackedCredentialsGate -RepoRoot $tempRoot -CredCheckScript $CredCheck
  Assert-False $gateFail.passed 'QASEC-2: gate FAIL com credencial tracked em repo temp'
  Assert-True ($gateFail.exitCode -ne 0) 'QASEC-2: exit code != 0'
} finally {
  Pop-Location
  Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

# QASEC-3: script ausente -> fail-closed
$gateMissing = Invoke-TrackedCredentialsGate -RepoRoot $RepoRoot -CredCheckScript (Join-Path $tempRoot 'missing.ps1')
Assert-False $gateMissing.passed 'QASEC-3: fail-closed quando script ausente'
Assert-True ($gateMissing.exitCode -eq 2) 'QASEC-3: exit code 2 script ausente'

# QASEC-4: saida do check nao contem PRIVATE KEY literal de credencial real
$outFile = Join-Path (Join-Path $ScriptDir 'artifacts') ("qasec4_stdout_" + [Guid]::NewGuid().ToString('N') + '.txt')
Push-Location $RepoRoot
try {
  & powershell -NoProfile -ExecutionPolicy Bypass -File $CredCheck -RepoRoot $RepoRoot *> $outFile
} finally {
  Pop-Location
}
$outText = Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue
if ($outText -match 'BEGIN PRIVATE KEY') {
  [void]$failures.Add('QASEC-4: saida contem BEGIN PRIVATE KEY')
}
Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue

# QASEC-5: integracao nao altera flow_matrix.json
$runSource = Get-Content -LiteralPath $RunQaBot -Raw
Assert-True ($runSource -match 'Invoke-TrackedCredentialsGate') 'QASEC-5: run_qa_bot referencia gate'
Assert-True ($runSource -match 'check_tracked_credentials\.ps1') 'QASEC-5: run_qa_bot referencia check_tracked_credentials'
$MatrixHashAfter = (Get-FileHash -LiteralPath $MatrixPath -Algorithm SHA256).Hash
Assert-True ($MatrixHashBefore -eq $MatrixHashAfter) 'QASEC-5: flow_matrix.json inalterado'

if ($failures.Count -gt 0) {
  Write-Host "QASEC HARNESS FAIL ($($failures.Count) case(s))"
  foreach ($f in $failures) { Write-Host "  $f" }
  exit 1
}

Write-Host 'QASEC HARNESS PASS (5 cases)'
exit 0
