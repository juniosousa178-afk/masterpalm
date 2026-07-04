#Requires -Version 5.1
<#
.SYNOPSIS
  Harness determinístico do parser NDJSON — mesma lógica de qa_parser.ps1 / run_qa_bot.ps1.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'qa_parser.ps1')

function Assert-Equal {
  param(
    [string]$Label,
    $Expected,
    $Actual
  )
  if ($Expected -ne $Actual) {
    throw "$Label - esperado: $Expected, obtido: $Actual"
  }
}

function Assert-True {
  param([string]$Label, [bool]$Condition)
  if (-not $Condition) { throw "$Label - condicao falsa." }
}

function Assert-WarningContains {
  param(
    [string]$Label,
    [string[]]$Warnings,
    [string]$Substring
  )
  $hit = $false
  foreach ($w in $Warnings) {
    if ($w -like "*$Substring*") { $hit = $true; break }
  }
  if (-not $hit) {
    throw "$Label - nenhum parser_warning contendo '$Substring'. Warnings: $($Warnings -join ' | ')"
  }
}

function Read-FixtureLines {
  param([string]$RelativePath)
  $path = Join-Path $ScriptDir $RelativePath
  return @(Get-Content -LiteralPath $path -Encoding UTF8)
}

$failures = 0

function Run-Case {
  param(
    [string]$Name,
    [scriptblock]$Body
  )
  Write-Host "CASE $Name"
  try {
    & $Body
    Write-Host "  OK"
  } catch {
    Write-Host "  FAIL: $($_.Exception.Message)"
    $script:failures += 1
  }
}

Run-Case '1 hidden/sintetico' {
  $warnings = [System.Collections.Generic.List[string]]::new()
  $parsed = Parse-FlutterTestJsonLines -Lines (Read-FixtureLines 'fixtures/case01_hidden_loading.ndjson') -ParserWarnings $warnings
  Assert-Equal 'passed' 3 $parsed.passed
  Assert-Equal 'failed' 0 $parsed.failed
  Assert-Equal 'skipped' 0 $parsed.skipped
  Assert-Equal 'realTestCasesDetected' 3 $parsed.realTestCasesDetected
}

Run-Case '2 pass+fail' {
  $warnings = [System.Collections.Generic.List[string]]::new()
  $parsed = Parse-FlutterTestJsonLines -Lines (Read-FixtureLines 'fixtures/case02_pass_fail.ndjson') -ParserWarnings $warnings
  Assert-Equal 'passed' 1 $parsed.passed
  Assert-Equal 'failed' 1 $parsed.failed
}

Run-Case '3 skip' {
  $warnings = [System.Collections.Generic.List[string]]::new()
  $parsed = Parse-FlutterTestJsonLines -Lines (Read-FixtureLines 'fixtures/case03_skip.ndjson') -ParserWarnings $warnings
  Assert-Equal 'skipped' 1 $parsed.skipped
  Assert-Equal 'passed' 0 $parsed.passed
}

Run-Case '4 duplicate testDone' {
  $warnings = [System.Collections.Generic.List[string]]::new()
  $parsed = Parse-FlutterTestJsonLines -Lines (Read-FixtureLines 'fixtures/case04_duplicate_testdone.ndjson') -ParserWarnings $warnings
  Assert-Equal 'passed' 1 $parsed.passed
  Assert-WarningContains 'duplicate warning' @($warnings) 'testDone duplicado'
}

Run-Case '5 linha invalida' {
  $warnings = [System.Collections.Generic.List[string]]::new()
  $parsed = Parse-FlutterTestJsonLines -Lines (Read-FixtureLines 'fixtures/case05_invalid_line.ndjson') -ParserWarnings $warnings
  Assert-Equal 'failed' 0 $parsed.failed
  Assert-WarningContains 'invalid line warning' @($warnings) 'Linha JSON invalida'
}

Run-Case '6 resultado desconhecido' {
  $warnings = [System.Collections.Generic.List[string]]::new()
  $parsed = Parse-FlutterTestJsonLines -Lines (Read-FixtureLines 'fixtures/case06_unknown_result.ndjson') -ParserWarnings $warnings
  Assert-Equal 'passed' 0 $parsed.passed
  Assert-WarningContains 'unknown result warning' @($warnings) 'resultado desconhecido'
}

Run-Case '7 exit infra sem fail funcional' {
  $warnings = [System.Collections.Generic.List[string]]::new()
  $parsed = Parse-FlutterTestJsonLines -Lines (Read-FixtureLines 'fixtures/case07_exit_infra.ndjson') -ParserWarnings $warnings
  $resolved = Resolve-SmokeExecutionStatus -Parsed $parsed -ExitCode 2 -StderrText 'synthetic infra'
  Assert-Equal 'status' 'INFRA_ERROR' $resolved.status
}

Write-Host ""
if ($failures -gt 0) {
  Write-Host "HARNESS FAIL ($failures case(s))"
  exit 1
}
Write-Host 'HARNESS PASS (7 cases)'
exit 0
