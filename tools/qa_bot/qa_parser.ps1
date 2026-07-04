#Requires -Version 5.1
<#
.SYNOPSIS
  Parser NDJSON compartilhado do Flutter test reporter (protocolo 0.1.x).

.DESCRIPTION
  Contrato M0.1: passed/failed/skipped contam apenas casos de teste reais.
  Exclui testDone com hidden=true (pseudo-teste de loading do framework).
  Uma unica implementacao - consumida por run_qa_bot.ps1 e test_parser_harness.ps1.
#>

Set-StrictMode -Version Latest

function Write-QaUtf8File {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Content
  )
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $utf8NoBom = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Test-FlutterTestDoneIsCountable {
  param(
    [object]$TestDoneEvent,
    [object]$TestStartRecord
  )

  if ($null -eq $TestDoneEvent) { return $false }

  # Campo estrutural comprovado: hidden=true marca pseudo-teste de loading (NDJSON real M0.1).
  if ($null -ne $TestDoneEvent.hidden) {
    $hiddenVal = $TestDoneEvent.hidden
  } else {
    $hiddenVal = Get-JsonPropertyValue -Object $TestDoneEvent -Name 'hidden'
  }
  if ($null -ne $hiddenVal -and [bool]$hiddenVal) {
    return $false
  }

  # Reforco estrutural: testes reais possuem url em testStart; loading possui url=null.
  if ($null -ne $TestStartRecord -and $null -eq $TestStartRecord.url) {
    return $false
  }

  return $true
}

function Get-FlutterTestDoneOutcome {
  param(
    [object]$TestDoneEvent
  )

  $skipped = $false
  if ($null -ne $TestDoneEvent.skipped) {
    $skipped = [bool]$TestDoneEvent.skipped
  } else {
    $skipProp = Get-JsonPropertyValue -Object $TestDoneEvent -Name 'skipped'
    if ($null -ne $skipProp) { $skipped = [bool]$skipProp }
  }
  if ($skipped) { return 'skipped' }

  $result = Get-JsonStringProperty -Object $TestDoneEvent -Name 'result'
  switch ($result) {
    'success' { return 'passed' }
    'failure' { return 'failed' }
    'error' { return 'failed' }
    default { return 'unknown' }
  }
}

function Get-JsonPropertyValue {
  param(
    [object]$Object,
    [string]$Name
  )
  if ($null -eq $Object) { return $null }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $null }
  return $prop.Value
}

function Get-JsonStringProperty {
  param(
    [object]$Object,
    [string]$Name
  )
  $value = Get-JsonPropertyValue -Object $Object -Name $Name
  if ($null -eq $value) { return '' }
  return [string]$value
}

function Parse-FlutterTestJsonLines {
  param(
    [string[]]$Lines,
    [System.Collections.Generic.List[string]]$ParserWarnings
  )

  $testsStarted = @{}
  $testsFinished = @{}
  $passed = 0
  $failed = 0
  $skipped = 0
  $realTestCasesDetected = 0
  $failures = @()
  $doneSeen = $false
  $doneSuccess = $null
  $doneTime = $null

  foreach ($line in $Lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    try {
      $evt = $line | ConvertFrom-Json
    } catch {
      [void]$ParserWarnings.Add(
        "Linha JSON invalida ignorada: $($line.Substring(0, [Math]::Min(120, $line.Length)))"
      )
      continue
    }

    $type = [string]$evt.type
    if ([string]::IsNullOrWhiteSpace($type)) {
      [void]$ParserWarnings.Add('Evento JSON sem campo type - ignorado.')
      continue
    }

    switch ($type) {
      'testStart' {
        $test = $evt.test
        if ($null -eq $test) { continue }
        $id = Get-JsonStringProperty -Object $test -Name 'id'
        if ([string]::IsNullOrWhiteSpace($id)) { continue }

        $metadata = Get-JsonPropertyValue -Object $test -Name 'metadata'
        $skipMeta = $false
        if ($null -ne $metadata) {
          $skipVal = Get-JsonPropertyValue -Object $metadata -Name 'skip'
          if ($null -ne $skipVal) { $skipMeta = [bool]$skipVal }
        }

        $groupRaw = Get-JsonPropertyValue -Object $test -Name 'groupIDs'
        $groupIds = @()
        if ($null -ne $groupRaw) { $groupIds = @($groupRaw) }

        $urlRaw = Get-JsonPropertyValue -Object $test -Name 'url'

        $testsStarted[$id] = [ordered]@{
          id       = $id
          name     = Get-JsonStringProperty -Object $test -Name 'name'
          suiteID  = Get-JsonStringProperty -Object $test -Name 'suiteID'
          groupIDs = $groupIds
          url      = if ($null -ne $urlRaw) { [string]$urlRaw } else { $null }
          skip     = $skipMeta
        }
      }

      'testDone' {
        $testId = Get-JsonStringProperty -Object $evt -Name 'testID'
        if ([string]::IsNullOrWhiteSpace($testId)) {
          [void]$ParserWarnings.Add('testDone sem testID - ignorado.')
          continue
        }

        if ($testsFinished.ContainsKey($testId)) {
          [void]$ParserWarnings.Add("testDone duplicado para testID=$testId - contagem ignorada.")
          continue
        }

        $startRecord = $null
        if ($testsStarted.ContainsKey($testId)) {
          $startRecord = $testsStarted[$testId]
        } else {
          [void]$ParserWarnings.Add("testDone sem testStart correspondente (testID=$testId).")
        }

        $testsFinished[$testId] = $true

        if (-not (Test-FlutterTestDoneIsCountable -TestDoneEvent $evt -TestStartRecord $startRecord)) {
          continue
        }

        $realTestCasesDetected += 1
        $outcome = Get-FlutterTestDoneOutcome -TestDoneEvent $evt

        switch ($outcome) {
          'passed' { $passed += 1 }
          'skipped' { $skipped += 1 }
          'failed' {
            $failed += 1
            $failures += [ordered]@{
                testId = $testId
                result = Get-JsonStringProperty -Object $evt -Name 'result'
                error  = Get-JsonStringProperty -Object $evt -Name 'error'
                stack  = Get-JsonStringProperty -Object $evt -Name 'stackTrace'
                url    = if ($startRecord) { [string]$startRecord.url } else { '' }
                name   = if ($startRecord) { [string]$startRecord.name } else { '' }
              }
          }
          default {
            [void]$ParserWarnings.Add(
              "testDone resultado desconhecido para testID=$testId result=$([string]$evt.result) - nao contabilizado como PASS."
            )
          }
        }
      }

      'error' {
        $errorTestId = Get-JsonStringProperty -Object $evt -Name 'testID'
        if ($errorTestId -and $testsFinished.ContainsKey($errorTestId)) {
          [void]$ParserWarnings.Add("error duplicado para testID=$errorTestId - nao recontabilizado.")
          continue
        }
        if ($errorTestId) {
          $testsFinished[$errorTestId] = $true
        }
        $failed += 1
        $failures += [ordered]@{
            testId = $errorTestId
            result = 'error'
            error  = Get-JsonStringProperty -Object $evt -Name 'error'
            stack  = Get-JsonStringProperty -Object $evt -Name 'stackTrace'
            url    = ''
            name   = if ($errorTestId) { 'test_error' } else { 'runner_error' }
          }
      }

      'done' {
        $doneSeen = $true
        if ($null -ne $evt.success) { $doneSuccess = [bool]$evt.success }
        if ($null -ne $evt.time) { $doneTime = $evt.time }
      }

      default {
        # Evento desconhecido (start, suite, group, allSuites, ...) - ignorado.
      }
    }
  }

  $metricsReliable = ($doneSeen -eq $true) -and (
    ($realTestCasesDetected -eq ($passed + $failed + $skipped)) -or
    ($realTestCasesDetected -eq 0 -and $passed -eq 0 -and $failed -eq 0 -and $skipped -eq 0)
  )

  if (-not $metricsReliable) {
    [void]$ParserWarnings.Add(
      'Metricas possivelmente inconsistentes: realTestCasesDetected difere da soma passed+failed+skipped.'
    )
  }

  return @{
    passed                = $passed
    failed                = $failed
    skipped               = $skipped
    realTestCasesDetected = $realTestCasesDetected
    metricsReliable       = $metricsReliable
    failures              = $failures
    doneSeen              = $doneSeen
    doneSuccess           = $doneSuccess
    doneTime              = $doneTime
    protocolCompleted     = $doneSeen
  }
}

function Resolve-SmokeExecutionStatus {
  param(
    [hashtable]$Parsed,
    [int]$ExitCode,
    [string]$StderrText
  )

  if ($Parsed.doneSeen -eq $false -and ($Parsed.passed + $Parsed.failed + $Parsed.skipped) -eq 0) {
    return @{
      status   = 'INFRA_ERROR'
      evidence = 'Nenhuma linha JSON conclusiva emitida por flutter test.'
      error    = $StderrText
    }
  }

  if ($ExitCode -ne 0 -and $Parsed.failed -eq 0 -and $Parsed.realTestCasesDetected -eq 0) {
    return @{
      status   = 'INFRA_ERROR'
      evidence = "Exit code $ExitCode sem teste funcional identificado no protocolo JSON."
      error    = $StderrText
    }
  }

  if ($Parsed.failed -gt 0 -or ($Parsed.doneSuccess -eq $false)) {
    return @{
      status   = 'FAIL'
      evidence = "Execucao concluida com falhas funcionais (exit=$ExitCode, failed=$($Parsed.failed), realCases=$($Parsed.realTestCasesDetected))."
      error    = $StderrText
    }
  }

  if (-not $Parsed.metricsReliable) {
    return @{
      status   = 'INFRA_ERROR'
      evidence = 'Parser nao produziu metricas confiaveis.'
      error    = $StderrText
    }
  }

  if ($ExitCode -ne 0) {
    return @{
      status   = 'INFRA_ERROR'
      evidence = "Exit code $ExitCode sem falha funcional identificavel no protocolo JSON."
      error    = $StderrText
    }
  }

  return @{
    status   = 'PASS'
    evidence = "Smoke concluida (exit=$ExitCode, passed=$($Parsed.passed), failed=$($Parsed.failed), skipped=$($Parsed.skipped), realCases=$($Parsed.realTestCasesDetected))."
    error    = $StderrText
  }
}
