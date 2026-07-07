#Requires -Version 5.1
<#
.SYNOPSIS
  Harness SEC-1…SEC-10 para check_tracked_credentials.ps1
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'check_tracked_credentials.ps1')

function Assert-Equal {
  param([string]$Label, $Expected, $Actual)
  if ($Expected -ne $Actual) {
    throw "$Label - esperado: $Expected, obtido: $Actual"
  }
}

function Assert-True {
  param([string]$Label, [bool]$Condition)
  if (-not $Condition) { throw "$Label - condicao falsa." }
}

function New-TempGitRepo {
  $dir = Join-Path ([IO.Path]::GetTempPath()) ("mp_sec_harness_" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $dir | Out-Null
  Push-Location $dir
  git init -q | Out-Null
  git config user.email 'harness@test.local'
  git config user.name 'Harness'
  return $dir
}

function Remove-TempGitRepo {
  param([string]$Dir)
  Pop-Location
  if (Test-Path $Dir) {
    Remove-Item -LiteralPath $Dir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

$failures = 0

function Run-Case {
  param([string]$Name, [scriptblock]$Body)
  Write-Host "CASE $Name"
  try {
    & $Body
    Write-Host '  OK'
  } catch {
    Write-Host "  FAIL: $($_.Exception.Message)"
    $script:failures += 1
  }
}

Run-Case 'SEC-1 repo/fixture sem credencial' {
  $dir = New-TempGitRepo
  try {
  Set-Content -Path 'readme.md' -Value '# ok' -Encoding UTF8
  git add readme.md | Out-Null
  git commit -q -m 'init' | Out-Null
  $findings = @(Get-TrackedCredentialFindings -RepoRoot $dir)
  Assert-Equal 'findings' 0 $findings.Count
  Assert-Equal 'exit' 0 (Invoke-TrackedCredentialsPreflight -RepoRoot $dir)
  } finally { Remove-TempGitRepo -Dir $dir }
}

Run-Case 'SEC-2 tracked service_account + private key -> FAIL' {
  $dir = New-TempGitRepo
  try {
  $fake = @'
{
  "type": "service_account",
  "private_key": "-----BEGIN PRIVATE KEY-----\nFAKE_TEST_KEY_NOT_A_REAL_CREDENTIAL\n-----END PRIVATE KEY-----\n"
}
'@
  Set-Content -Path 'leak.json' -Value $fake -Encoding UTF8
  git add leak.json | Out-Null
  git commit -q -m 'leak' | Out-Null
  $findings = @(Get-TrackedCredentialFindings -RepoRoot $dir)
  Assert-Equal 'findings' 1 $findings.Count
  Assert-Equal 'exit' 1 (Invoke-TrackedCredentialsPreflight -RepoRoot $dir)
  } finally { Remove-TempGitRepo -Dir $dir }
}

Run-Case 'SEC-3 untracked sensivel ignorado' {
  $dir = New-TempGitRepo
  try {
  $fake = @'
{"type":"service_account","private_key":"-----BEGIN PRIVATE KEY-----\nFAKE\n-----END PRIVATE KEY-----\n"}
'@
  Set-Content -Path 'untracked.json' -Value $fake -Encoding UTF8
  # não git add
  $findings = @(Get-TrackedCredentialFindings -RepoRoot $dir)
  Assert-Equal 'findings' 0 $findings.Count
  } finally { Remove-TempGitRepo -Dir $dir }
}

Run-Case 'SEC-4 doc menciona private_key nao falha' {
  $dir = New-TempGitRepo
  try {
  Set-Content -Path 'DOC.md' -Value 'Campo private_key em documentacao.' -Encoding UTF8
  git add DOC.md | Out-Null
  git commit -q -m 'doc' | Out-Null
  Assert-Equal 'findings' 0 (@(Get-TrackedCredentialFindings -RepoRoot $dir)).Count
  } finally { Remove-TempGitRepo -Dir $dir }
}

Run-Case 'SEC-5 lista de chaves sensiveis nao falha' {
  $dir = New-TempGitRepo
  try {
  Set-Content -Path 'keys.dart' -Value "const keys = ['private_key', 'client_email'];" -Encoding UTF8
  git add keys.dart | Out-Null
  git commit -q -m 'keys' | Out-Null
  Assert-Equal 'findings' 0 (@(Get-TrackedCredentialFindings -RepoRoot $dir)).Count
  } finally { Remove-TempGitRepo -Dir $dir }
}

Run-Case 'SEC-6 JSON fake sem BEGIN PRIVATE KEY' {
  $dir = New-TempGitRepo
  try {
  Set-Content -Path 'fake.json' -Value '{"type":"service_account","private_key":"not-a-pem"}' -Encoding UTF8
  git add fake.json | Out-Null
  git commit -q -m 'fake' | Out-Null
  Assert-Equal 'findings' 0 (@(Get-TrackedCredentialFindings -RepoRoot $dir)).Count
  } finally { Remove-TempGitRepo -Dir $dir }
}

Run-Case 'SEC-7 saida nunca contem private_key' {
  $dir = New-TempGitRepo
  try {
  $fake = @'
{"type":"service_account","private_key":"-----BEGIN PRIVATE KEY-----\nFAKE_TEST_KEY_NOT_A_REAL_CREDENTIAL\n-----END PRIVATE KEY-----\n"}
'@
  Set-Content -Path 'leak.json' -Value $fake -Encoding UTF8
  git add leak.json | Out-Null
  git commit -q -m 'leak' | Out-Null
  $out = Invoke-TrackedCredentialsPreflight -RepoRoot $dir 2>&1 | Out-String
  Assert-True 'sem BEGIN PRIVATE KEY na saida' ($out -notmatch 'BEGIN PRIVATE KEY')
  Assert-True 'sem FAKE key na saida' ($out -notmatch 'FAKE_TEST_KEY')
  } finally { Remove-TempGitRepo -Dir $dir }
}

Run-Case 'SEC-8 tools/sa.json fora do git ls-files (repo real)' {
  $repoRoot = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
  Push-Location $repoRoot
  try {
    $listed = @(git ls-files 'tools/sa.json')
    Assert-Equal 'listed' 0 $listed.Count
  } finally { Pop-Location }
}

Run-Case 'SEC-9 git check-ignore tools/sa.json' {
  $repoRoot = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
  Push-Location $repoRoot
  try {
    $ignore = git check-ignore -v tools/sa.json 2>&1 | Out-String
    Assert-True 'ignored' ($ignore.Trim().Length -gt 0)
    Assert-True 'rule mentions sa.json' ($ignore -match 'sa\.json')
  } finally { Pop-Location }
}

Run-Case 'SEC-10 detector no HEAD corrigido PASS' {
  $repoRoot = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
  Assert-Equal 'exit' 0 (Invoke-TrackedCredentialsPreflight -RepoRoot $repoRoot)
}

Write-Host ''
if ($failures -gt 0) {
  Write-Host "HARNESS FAIL ($failures case(s))"
  exit 1
}
Write-Host 'HARNESS PASS (10 cases)'
exit 0
