#Requires -Version 5.1

<#

.SYNOPSIS

  Validação fail-closed do artefato JSON runner -> renderer (QA Bot).

  Contrato R6.2: arquivos planejados/executados separados de casos de teste.

#>

Set-StrictMode -Version Latest



function Set-QaFlowFileLists {

  param(

    [Parameter(Mandatory = $true)]

    $Entry,

    [string[]]$PlannedTestFiles,

    [string[]]$ExecutedTestFiles

  )



  $Entry.plannedTestFiles = @($PlannedTestFiles | ForEach-Object { [string]$_ })

  $Entry.executedTestFiles = @($ExecutedTestFiles | ForEach-Object { [string]$_ })

  if ($Entry.PSObject.Properties.Name -contains 'tests') {

    $Entry.PSObject.Properties.Remove('tests')

  }

  if ($Entry.PSObject.Properties.Name -contains 'executedTests') {

    $Entry.PSObject.Properties.Remove('executedTests')

  }

}



function Set-QaFlowCaseMetrics {

  param(

    [Parameter(Mandatory = $true)]

    $Entry,

    [int]$PassedTestCases,

    [int]$FailedTestCases,

    [int]$SkippedTestCases

  )



  $Entry.passedTestCases = $PassedTestCases

  $Entry.failedTestCases = $FailedTestCases

  $Entry.skippedTestCases = $SkippedTestCases

  $Entry.executedTestCases = $PassedTestCases + $FailedTestCases + $SkippedTestCases



  foreach ($legacy in @('passed', 'failed', 'skipped', 'realTestCasesDetected')) {

    if ($Entry.PSObject.Properties.Name -contains $legacy) {

      $Entry.PSObject.Properties.Remove($legacy)

    }

  }

}



function Clear-QaFlowCaseMetrics {

  param([Parameter(Mandatory = $true)] $Entry)



  $Entry.executedTestCases = 0

  $Entry.passedTestCases = 0

  $Entry.failedTestCases = 0

  $Entry.skippedTestCases = 0

  foreach ($legacy in @('passed', 'failed', 'skipped', 'realTestCasesDetected')) {

    if ($Entry.PSObject.Properties.Name -contains $legacy) {

      $Entry.PSObject.Properties.Remove($legacy)

    }

  }

}



function Test-M1P0FlowResolutionUsesAllowlistOnly {
  param(
    [Parameter(Mandatory = $true)][string]$FlowId,
    [Parameter(Mandatory = $true)][hashtable]$Allowlist,
    $MatrixFlow = $null
  )

  if (-not $Allowlist.ContainsKey($FlowId)) {
    return @{
      ok      = $false
      code    = 'NOT_IN_ALLOWLIST'
      message = "FlowId $FlowId ausente da allowlist fixa do runner."
    }
  }

  $paths = @($Allowlist[$FlowId])
  if ($null -ne $MatrixFlow -and $MatrixFlow.PSObject.Properties.Name -contains 'tests') {
    foreach ($jsonTest in @($MatrixFlow.tests)) {
      $jt = [string]$jsonTest
      if ($jt.Length -gt 0 -and $paths -notcontains $jt) {
        return @{
          ok      = $false
          code    = 'JSON_TEST_PATH_LEAK'
          message = "Campo tests do JSON nao deve definir execucao M1P0: $jt"
        }
      }
    }
  }

  foreach ($dangerous in @('command', 'script', 'testCommand')) {
    if ($null -ne $MatrixFlow -and $MatrixFlow.PSObject.Properties.Name -contains $dangerous) {
      $val = [string]$MatrixFlow.$dangerous
      if ($val -match 'PWNED|Remove-Item') {
        return @{
          ok      = $true
          code    = 'ALLOWLIST_ONLY'
          message = 'Campos command/script/testCommand presentes mas ignorados; paths da allowlist fixa.'
          testPaths = $paths
        }
      }
    }
  }

  return @{
    ok        = $true
    code      = 'ALLOWLIST_ONLY'
    message   = 'Resolucao M1P0 usa somente allowlist fixa.'
    testPaths = $paths
  }
}

function Test-P1FlowIdParameter {

  param(

    [string]$FlowId,

    $Matrix

  )



  if ([string]::IsNullOrWhiteSpace($FlowId)) {

    return @{ ok = $false; code = 'FLOW_ID_EMPTY'; message = 'Parametro -Flow vazio.' }

  }



  $id = $FlowId.Trim()

  if ($id -match '[\\/;:]' -or $id -match '\.\.') {

    return @{ ok = $false; code = 'FLOW_ID_INVALID'; message = "FlowId rejeitado (path/injection): $id" }

  }

  if ($id -notmatch '^[a-zA-Z0-9_]+$') {

    return @{ ok = $false; code = 'FLOW_ID_INVALID'; message = "FlowId com caracteres invalidos: $id" }

  }



  $flowDef = $Matrix.flows | Where-Object { [string]$_.id -eq $id } | Select-Object -First 1

  if ($null -eq $flowDef) {

    return @{ ok = $false; code = 'UNKNOWN_FLOW'; message = "Fluxo nao encontrado: $id" }

  }



  $impacto = [string]$flowDef.impacto

  if ($impacto -eq 'P0') {

    return @{

      ok      = $false

      code    = 'P0_FLOW_NOT_ALLOWED_VIA_FLOW_PARAM'

      message = "Fluxo P0 '$id' nao pode ser executado via -Flow; use -M1P0."

    }

  }



  if ([string]$flowDef.runner -eq 'flutter_test_emulator') {

    return @{

      ok      = $false

      code    = 'ENVIRONMENT_REQUIRED'

      message = "Fluxo '$id' requer emulador Firestore (ENVIRONMENT_REQUIRED)."

    }

  }



  $planned = @()

  if ($flowDef.tests) {

    foreach ($t in $flowDef.tests) { $planned += [string]$t }

  }

  if ($planned.Count -eq 0) {

    return @{

      ok      = $false

      code    = 'FLOW_WITHOUT_TESTS'

      message = "Fluxo '$id' sem testes allowlisted na matriz."

    }

  }



  return @{

    ok           = $true

    code         = 'OK'

    message      = ''

    flowDef      = $flowDef

    plannedFiles = $planned

  }

}



function Test-QaFlowResultSchema {

  param(

    [Parameter(Mandatory = $true)]

    $FlowResult,

    [string]$ContextLabel = 'flowResult'

  )



  $errors = [System.Collections.Generic.List[string]]::new()

  $props = @($FlowResult.PSObject.Properties.Name)



  if ($props -contains 'executedTests') {

    [void]$errors.Add("$ContextLabel usa campo legado ambiguo 'executedTests'")

  }

  if ($props -contains 'tests' -and $props -notcontains 'plannedTestFiles') {

    [void]$errors.Add("$ContextLabel usa 'tests' sem 'plannedTestFiles'")

  }



  foreach ($required in @('id', 'plannedTestFiles', 'executedTestFiles', 'status')) {

    if ($props -notcontains $required) {

      [void]$errors.Add("$ContextLabel ausente: $required")

    }

  }



  if ($props -contains 'plannedTestFiles') {

    $ptf = $FlowResult.plannedTestFiles

    if ($null -eq $ptf) {

      [void]$errors.Add("$ContextLabel.plannedTestFiles nulo")

    } elseif ($ptf -isnot [System.Array] -and $ptf -isnot [System.Collections.IEnumerable]) {

      [void]$errors.Add("$ContextLabel.plannedTestFiles tipo invalido")

    }

  }



  if ($props -contains 'executedTestFiles') {

    $etf = $FlowResult.executedTestFiles

    if ($null -eq $etf) {

      [void]$errors.Add("$ContextLabel.executedTestFiles nulo")

    } elseif ($etf -isnot [System.Array] -and $etf -isnot [System.Collections.IEnumerable]) {

      [void]$errors.Add("$ContextLabel.executedTestFiles tipo invalido")

    }

  }



  foreach ($caseField in @('executedTestCases', 'passedTestCases', 'failedTestCases', 'skippedTestCases')) {

    if ($props -contains $caseField) {

      $val = $FlowResult.$caseField

      if ($null -ne $val -and $val -isnot [int] -and $val -isnot [long]) {

        [void]$errors.Add("$ContextLabel.$caseField tipo invalido")

      }

    }

  }



  $hasCaseCounts = ($props -contains 'executedTestCases') -and

    ($props -contains 'passedTestCases') -and

    ($props -contains 'failedTestCases') -and

    ($props -contains 'skippedTestCases')



  if ($hasCaseCounts) {

    $etc = [int]$FlowResult.executedTestCases

    $p = [int]$FlowResult.passedTestCases

    $f = [int]$FlowResult.failedTestCases

    $s = [int]$FlowResult.skippedTestCases

    if ($etc -ne ($p + $f + $s)) {

      [void]$errors.Add("$ContextLabel invariante violada: executedTestCases($etc) != passed+failed+skipped($($p + $f + $s))")

    }

  }



  if ($props -contains 'plannedTestFiles' -and $props -contains 'executedTestFiles' -and

      $null -ne $FlowResult.plannedTestFiles -and $null -ne $FlowResult.executedTestFiles) {

    $plannedCount = @($FlowResult.plannedTestFiles).Count

    $executedCount = @($FlowResult.executedTestFiles).Count

    if ($executedCount -gt $plannedCount -and $plannedCount -gt 0) {

      [void]$errors.Add("$ContextLabel executedTestFiles($executedCount) > plannedTestFiles($plannedCount)")

    }

  }



  $status = if ($props -contains 'status') { [string]$FlowResult.status } else { '' }

  if ($status -eq 'PASS') {

    $execFiles = if ($props -contains 'executedTestFiles') { @($FlowResult.executedTestFiles).Count } else { 0 }

    if ($execFiles -le 0) {

      [void]$errors.Add("$ContextLabel PASS com executedTestFiles vazio")

    }

    if ($hasCaseCounts) {

      if ([int]$FlowResult.executedTestCases -le 0) {

        [void]$errors.Add("$ContextLabel PASS com executedTestCases <= 0")

      }

      if ([int]$FlowResult.failedTestCases -ne 0) {

        [void]$errors.Add("$ContextLabel PASS com failedTestCases != 0")

      }

    }

  }



  return @{

    valid  = ($errors.Count -eq 0)

    errors = @($errors)

  }

}



function Test-QaRunArtifactSchema {

  param(

    [Parameter(Mandatory = $true)]

    $RunArtifact

  )



  $errors = [System.Collections.Generic.List[string]]::new()



  foreach ($required in @('runId', 'repoRoot', 'flowResults', 'verdict')) {

    if ($RunArtifact.PSObject.Properties.Name -notcontains $required) {

      [void]$errors.Add("artefato ausente: $required")

    }

  }



  if ($null -eq $RunArtifact.flowResults) {

    [void]$errors.Add('flowResults nulo')

  } else {

    $i = 0

    foreach ($fr in $RunArtifact.flowResults) {

      $check = Test-QaFlowResultSchema -FlowResult $fr -ContextLabel "flowResults[$i]"

      foreach ($e in $check.errors) { [void]$errors.Add($e) }

      $i++

    }

  }



  return @{

    valid  = ($errors.Count -eq 0)

    errors = @($errors)

  }

}



function Assert-QaRunArtifactSchema {

  param(

    [Parameter(Mandatory = $true)]

    $RunArtifact

  )



  $check = Test-QaRunArtifactSchema -RunArtifact $RunArtifact

  if (-not $check.valid) {

    throw "INFRA_ERROR schema artefato QA Bot invalido: $($check.errors -join ' | ')"

  }

}



function New-QaParserIntegritySummary {

  param(

    [int]$ExecutedTestCases = 0,

    [int]$PassedTestCases = 0,

    [int]$FailedTestCases = 0,

    [int]$SkippedTestCases = 0,

    [bool]$ProtocolCompleted = $false,

    [bool]$MetricsReliable = $false,

    $ExitCode = $null,

    [string[]]$ParserWarnings = @()

  )



  return [ordered]@{

    executedTestCases = $ExecutedTestCases

    passedTestCases     = $PassedTestCases

    failedTestCases     = $FailedTestCases

    skippedTestCases    = $SkippedTestCases

    parserWarnings      = @($ParserWarnings)

    protocolCompleted   = $ProtocolCompleted

    exitCode            = $ExitCode

    metricsReliable     = $MetricsReliable

  }

}


