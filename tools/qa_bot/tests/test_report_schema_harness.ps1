#Requires -Version 5.1

Set-StrictMode -Version Latest

$ErrorActionPreference = 'Stop'



$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$QaBotDir = Split-Path -Parent $ScriptDir

. (Join-Path $QaBotDir 'qa_report_schema.ps1')



$failures = 0



function Run-Case {

  param([string]$Name, [scriptblock]$Body)

  Write-Host "CASE $Name"

  try {

    & $Body

    Write-Host "  OK"

  } catch {

    Write-Host "  FAIL: $($_.Exception.Message)"

    $script:failures += 1

  }

}



function New-FlowPass {

  param(

    [string[]]$Planned,

    [string[]]$Executed,

    [int]$Passed,

    [int]$Failed = 0,

    [int]$Skipped = 0

  )

  $entry = [ordered]@{

    id                = 'fluxo_teste'

    plannedTestFiles  = $Planned

    executedTestFiles = $Executed

    status            = 'PASS'

  }

  Set-QaFlowCaseMetrics -Entry $entry -PassedTestCases $Passed -FailedTestCases $Failed -SkippedTestCases $Skipped

  return [pscustomobject]$entry

}



Run-Case 'QM1 um arquivo cinco casos' {

  $fr = New-FlowPass -Planned @('test/a_test.dart') -Executed @('test/a_test.dart') -Passed 5

  $artifact = [pscustomobject]@{

    runId = 'qm1'; repoRoot = 'C:\repo'; verdict = 'GO'; flowResults = @($fr)

  }

  $check = Test-QaRunArtifactSchema -RunArtifact $artifact

  if (-not $check.valid) { throw ($check.errors -join ' | ') }

  if ($fr.executedTestFiles.Count -ne 1 -or $fr.executedTestCases -ne 5) { throw 'metricas incorretas' }

}



Run-Case 'QM2 quatro arquivos 26 casos' {
  $fr = New-FlowPass -Planned @('test/a.dart','test/b.dart','test/c.dart','test/d.dart') -Executed @('test/a.dart','test/b.dart','test/c.dart','test/d.dart') -Passed 26
  if ($fr.executedTestFiles.Count -ne 4) { throw 'arquivos != 4' }
  if ($fr.executedTestCases -ne 26) { throw 'casos != 26' }
  if ($fr.executedTestFiles.Count -eq $fr.executedTestCases) { throw 'comparacao arquivo==caso proibida' }
  $artifact = [pscustomobject]@{ runId='qm2'; repoRoot='C:\repo'; verdict='GO'; flowResults=@($fr) }
  $check = Test-QaRunArtifactSchema -RunArtifact $artifact
  if (-not $check.valid) { throw ($check.errors -join ' | ') }
}



Run-Case 'QM3 contagem casos inconsistente' {

  $entry = [ordered]@{

    id='x'; plannedTestFiles=@('test/a.dart'); executedTestFiles=@('test/a.dart'); status='PASS'

  }

  Set-QaFlowCaseMetrics -Entry $entry -PassedTestCases 25 -FailedTestCases 0 -SkippedTestCases 0

  $entry.executedTestCases = 26

  $check = Test-QaFlowResultSchema -FlowResult ([pscustomobject]$entry)

  if ($check.valid) { throw 'esperava INFRA_ERROR por invariante' }

}



Run-Case 'QM4 arquivo planejado nao executado' {

  $entry = [ordered]@{

    id='x'; plannedTestFiles=@('test/a.dart','test/b.dart'); executedTestFiles=@('test/a.dart'); status='PARTIAL'

  }

  Set-QaFlowCaseMetrics -Entry $entry -PassedTestCases 3 -FailedTestCases 0 -SkippedTestCases 0

  $check = Test-QaFlowResultSchema -FlowResult ([pscustomobject]$entry)

  if (-not $check.valid) { throw ($check.errors -join ' | ') }

}



Run-Case 'QM5 zero arquivos e zero casos nunca PASS' {

  $entry = [ordered]@{

    id='x'; plannedTestFiles=@('test/a.dart'); executedTestFiles=@(); status='PASS'

  }

  Clear-QaFlowCaseMetrics -Entry $entry

  $check = Test-QaFlowResultSchema -FlowResult ([pscustomobject]$entry)

  if ($check.valid) { throw 'PASS com zero execucao deve falhar' }

}



Run-Case 'QM6 arquivos executados zero casos' {

  $entry = [ordered]@{

    id='x'; plannedTestFiles=@('test/a.dart'); executedTestFiles=@('test/a.dart'); status='INFRA_ERROR'

  }

  Clear-QaFlowCaseMetrics -Entry $entry

  $check = Test-QaFlowResultSchema -FlowResult ([pscustomobject]$entry)

  if (-not $check.valid) { throw ($check.errors -join ' | ') }

}



Run-Case 'QM7 caso skipped contabilizado' {

  $fr = New-FlowPass -Planned @('test/a.dart') -Executed @('test/a.dart') -Passed 4 -Skipped 1

  if ($fr.executedTestCases -ne 5) { throw 'skip nao contabilizado' }

  if ($fr.skippedTestCases -ne 1) { throw 'skippedTestCases ausente' }

}



Run-Case 'QM8 propriedade ausente fail-closed' {

  $artifact = [pscustomobject]@{

    runId='qm8'; repoRoot='C:\repo'; verdict='GO'

    flowResults=@([pscustomobject]@{ id='x'; status='PASS' })

  }

  $check = Test-QaRunArtifactSchema -RunArtifact $artifact

  if ($check.valid) { throw 'esperava schema invalido' }

}



Run-Case 'QM9 campo legado executedTests rejeitado' {

  $entry = [pscustomobject]@{

    id='x'; plannedTestFiles=@('test/a.dart'); executedTestFiles=@('test/a.dart')

    executedTests=@('test/a.dart'); status='PASS'

    executedTestCases=1; passedTestCases=1; failedTestCases=0; skippedTestCases=0

  }

  $check = Test-QaFlowResultSchema -FlowResult $entry

  if ($check.valid) { throw 'executedTests legado deve ser rejeitado' }

}



# FS — seguranca -Flow (logica pura)

$matrixJson = Get-Content (Join-Path $QaBotDir 'flow_matrix.json') -Raw -Encoding UTF8 | ConvertFrom-Json



Run-Case 'FS1 fluxo valido P1' {

  $r = Test-P1FlowIdParameter -FlowId 'catalogo_pedido_identidade' -Matrix $matrixJson

  if (-not $r.ok) { throw $r.message }

  if ($r.plannedFiles.Count -lt 1) { throw 'sem arquivos planejados' }

}



Run-Case 'FS2 fluxo inexistente' {

  $r = Test-P1FlowIdParameter -FlowId 'fluxo_inexistente' -Matrix $matrixJson

  if ($r.ok) { throw 'deveria rejeitar' }

  if ($r.code -ne 'UNKNOWN_FLOW') { throw "code=$($r.code)" }

}



Run-Case 'FS3 string vazia' {

  $r = Test-P1FlowIdParameter -FlowId '   ' -Matrix $matrixJson

  if ($r.ok) { throw 'deveria rejeitar vazio' }

}



Run-Case 'FS4 path traversal' {

  $r = Test-P1FlowIdParameter -FlowId '../../test/qualquer_test.dart' -Matrix $matrixJson

  if ($r.ok) { throw 'deveria rejeitar traversal' }

}



Run-Case 'FS5 injection PowerShell' {

  $r = Test-P1FlowIdParameter -FlowId 'catalogo; Write-Host hacked' -Matrix $matrixJson

  if ($r.ok) { throw 'deveria rejeitar injection' }

}



Run-Case 'FS7 fluxo Firestore sem emulador' {

  $r = Test-P1FlowIdParameter -FlowId 'firestore_rules' -Matrix $matrixJson

  if ($r.ok) { throw 'deveria exigir ambiente' }

  if ($r.code -ne 'ENVIRONMENT_REQUIRED' -and $r.code -ne 'P0_FLOW_NOT_ALLOWED_VIA_FLOW_PARAM') {

    throw "code inesperado=$($r.code)"

  }

}



Run-Case 'FS8 fluxo P0 rejeitado via -Flow' {

  $r = Test-P1FlowIdParameter -FlowId 'pdv_venda' -Matrix $matrixJson

  if ($r.ok) { throw 'P0 nao deve passar via -Flow' }

  if ($r.code -ne 'P0_FLOW_NOT_ALLOWED_VIA_FLOW_PARAM') { throw "code=$($r.code)" }

}

Run-Case 'FS9 JSON arbitrario nao executa comando' {
  $malicious = [pscustomobject]@{
    id          = 'fixture_malicious'
    command     = 'Write-Host PWNED'
    script      = 'Remove-Item -Recurse C:\'
    testCommand = 'powershell -Command Write-Host PWNED'
    tests       = @('test/evil_injected_test.dart')
    impacto     = 'P0'
    runner      = 'flutter_test'
  }
  $allowlist = @{
    produto_simples = @('test/produto_cadastro_persistencia_test.dart')
  }
  $r = Test-M1P0FlowResolutionUsesAllowlistOnly -FlowId 'fixture_malicious' -Allowlist $allowlist -MatrixFlow $malicious
  if ($r.ok) { throw 'fluxo malicioso deve falhar fora da allowlist' }
  if ($r.code -ne 'NOT_IN_ALLOWLIST') { throw "code=$($r.code)" }
  $r2 = Test-P1FlowIdParameter -FlowId 'fixture_malicious' -Matrix $matrixJson
  if ($r2.ok) { throw 'P1 deve rejeitar fluxo desconhecido na matriz' }
  if ($r2.code -ne 'UNKNOWN_FLOW') { throw "code=$($r2.code)" }
  $sentinel = Join-Path $env:TEMP "qa_bot_fs9_sentinel_$PID.txt"
  if (Test-Path -LiteralPath $sentinel) { Remove-Item -LiteralPath $sentinel -Force }
  if (Test-Path -LiteralPath $sentinel) { throw 'sentinel nao deveria existir' }
}

if ($failures -gt 0) {

  Write-Host "FALHAS: $failures"

  exit 1

}

Write-Host 'QM1-QM9 + FS1-FS9 OK'

exit 0

