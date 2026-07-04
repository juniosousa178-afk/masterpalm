#Requires -Version 5.1
<#
.SYNOPSIS
  Renderiza qa_reports/QA_REPORT_<UTC>.md a partir do artefato JSON do run_qa_bot.ps1.
  Modulo separado para manter run_qa_bot.ps1 focado em preflight/execucao/parser.
#>
param(
  [Parameter(Mandatory = $true)]
  [string]$RunArtifactPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'qa_parser.ps1')

if (-not (Test-Path -LiteralPath $RunArtifactPath)) {
  throw "Artefato de execucao nao encontrado: $RunArtifactPath"
}

$run = Get-Content -LiteralPath $RunArtifactPath -Raw -Encoding UTF8 | ConvertFrom-Json

$reportsDir = Join-Path $run.repoRoot 'qa_reports'
if (-not (Test-Path -LiteralPath $reportsDir)) {
  New-Item -ItemType Directory -Force -Path $reportsDir | Out-Null
}

$reportId = if ($run.runId) { [string]$run.runId } else { [string]$run.timestampUtc }
$reportPath = Join-Path $reportsDir ("QA_REPORT_{0}.md" -f $reportId)
$phaseLabel = if ($run.phase) { [string]$run.phase } else { 'M0' }

function Format-MdBlock {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return '_n/a_' }
  return ($Text -replace "`r`n", "`n").Trim()
}

$preflightStatus = if ($run.preflight.passed) { 'PASS' } else { 'BLOCKED' }

$summary = @{
  PASS         = 0
  FAIL         = 0
  NOT_COVERED  = 0
  BLOCKED      = 0
  INFRA_ERROR  = 0
}

foreach ($flowResult in $run.flowResults) {
  if ($null -eq $flowResult.status -or [string]::IsNullOrWhiteSpace([string]$flowResult.status)) {
    continue
  }
  $key = [string]$flowResult.status
  if ($summary.ContainsKey($key)) {
    $summary[$key] += 1
  }
}

$verdict = [string]$run.verdict
$verdictReason = [string]$run.verdictReason

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# QA Bot MasterPalm')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Identidade da execucao')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("* **Fase:** QA-BOT $phaseLabel")
[void]$sb.AppendLine("* **Run ID:** ``$reportId``")
[void]$sb.AppendLine("* **Timestamp UTC:** $($run.timestampUtc)")
[void]$sb.AppendLine("* **Branch:** ``$($run.branch)``")
[void]$sb.AppendLine("* **HEAD:** ``$($run.head)``")
[void]$sb.AppendLine('')

[void]$sb.AppendLine('## Preflight')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("* **Status:** $preflightStatus")
[void]$sb.AppendLine('* **Checks executados:**')
foreach ($check in $run.preflight.checks) {
  $mark = if ($check.passed) { 'OK' } else { 'FAIL' }
  [void]$sb.AppendLine("  * [$mark] $($check.name): $($check.detail)")
}
if ($run.preflight.blockers.Count -gt 0) {
  [void]$sb.AppendLine('* **Bloqueios encontrados:**')
  foreach ($blocker in $run.preflight.blockers) {
    [void]$sb.AppendLine("  * $blocker")
  }
} else {
  [void]$sb.AppendLine('* **Bloqueios encontrados:** nenhum')
}
[void]$sb.AppendLine('')

[void]$sb.AppendLine('## Resumo executivo')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("| Status | Quantidade |")
[void]$sb.AppendLine("|--------|------------|")
foreach ($statusName in @('PASS', 'FAIL', 'NOT_COVERED', 'BLOCKED', 'INFRA_ERROR')) {
  [void]$sb.AppendLine("| $statusName | $($summary[$statusName]) |")
}
[void]$sb.AppendLine('')

if ($null -ne $run.smoke) {
  [void]$sb.AppendLine('## Smoke suite')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine("* **Run ID:** ``$($run.smoke.runId)``")
  [void]$sb.AppendLine("* **Comando logico:** ``$($run.smoke.logicalCommand)``")
  [void]$sb.AppendLine("* **Exit code:** $($run.smoke.exitCode)")
  [void]$sb.AppendLine("* **Duracao (s):** $($run.smoke.durationSeconds)")
  [void]$sb.AppendLine("* **Passou:** $($run.smoke.passed)")
  [void]$sb.AppendLine("* **Falhou:** $($run.smoke.failed)")
  [void]$sb.AppendLine("* **Ignorados:** $($run.smoke.skipped)")
  if ($null -ne $run.smoke.realTestCasesDetected) {
    [void]$sb.AppendLine("* **Casos reais detectados:** $($run.smoke.realTestCasesDetected)")
  }
  [void]$sb.AppendLine("* **Status execucao:** $($run.smoke.executionStatus)")
  [void]$sb.AppendLine('')
}

if ($null -ne $run.parserIntegrity) {
  $metricsLabel = if ($run.parserIntegrity.metricsReliable) { 'SIM' } else { 'NAO' }
  [void]$sb.AppendLine('## Integridade do parser')
  [void]$sb.AppendLine('')
  [void]$sb.AppendLine("* **Casos de teste reais detectados:** $($run.parserIntegrity.realTestCasesDetected)")
  [void]$sb.AppendLine("* **passed:** $($run.parserIntegrity.passed)")
  [void]$sb.AppendLine("* **failed:** $($run.parserIntegrity.failed)")
  [void]$sb.AppendLine("* **skipped:** $($run.parserIntegrity.skipped)")
  [void]$sb.AppendLine("* **protocolo concluido:** $($run.parserIntegrity.protocolCompleted)")
  [void]$sb.AppendLine("* **exit code:** $($run.parserIntegrity.exitCode)")
  [void]$sb.AppendLine("* **metricas confiaveis:** $metricsLabel")
  [void]$sb.AppendLine('')
}
[void]$sb.AppendLine('## Matriz de fluxos')
[void]$sb.AppendLine('')

foreach ($flowResult in $run.flowResults) {
  $impacto = [string]$flowResult.impacto
  $id = [string]$flowResult.id
  [void]$sb.AppendLine("### [$impacto] $id")
  [void]$sb.AppendLine('')
  $statusLabel = if ($null -eq $flowResult.status -or [string]::IsNullOrWhiteSpace([string]$flowResult.status)) {
    '_Omitido nesta fase - testes mapeados nao executados_'
  } else {
    [string]$flowResult.status
  }
  [void]$sb.AppendLine("**Status:** $statusLabel")
  [void]$sb.AppendLine("**Cobertura:** $($flowResult.statusCobertura)")
  if ($flowResult.executedTests -and $flowResult.executedTests.Count -gt 0) {
    [void]$sb.AppendLine('**Arquivo(s) executado(s):**')
    foreach ($t in $flowResult.executedTests) {
      [void]$sb.AppendLine("* ``$t``")
    }
  } elseif ($flowResult.tests -and $flowResult.tests.Count -gt 0) {
    [void]$sb.AppendLine('**Teste(s) mapeado(s):**')
    foreach ($t in $flowResult.tests) {
      [void]$sb.AppendLine("* ``$t``")
    }
  } else {
    [void]$sb.AppendLine('**Teste(s) mapeado(s):** _nenhum_')
  }
  [void]$sb.AppendLine("**Runner:** $($flowResult.runner)")

  if ($null -ne $flowResult.passed -and ($flowResult.PSObject.Properties.Name -contains 'passed')) {
    [void]$sb.AppendLine("**passed / failed / skipped:** $($flowResult.passed) / $($flowResult.failed) / $($flowResult.skipped)")
  }
  if ($null -ne $flowResult.durationSeconds -and ($flowResult.PSObject.Properties.Name -contains 'durationSeconds')) {
    [void]$sb.AppendLine("**Duracao (s):** $($flowResult.durationSeconds)")
  }
  if ($flowResult.PSObject.Properties.Name -contains 'logicalCommand' -and $flowResult.logicalCommand) {
    [void]$sb.AppendLine("**Comando logico:** ``$($flowResult.logicalCommand)``")
  }
  if ($null -ne $flowResult.metricsReliable -and ($flowResult.PSObject.Properties.Name -contains 'metricsReliable')) {
    $mr = if ($flowResult.metricsReliable) { 'SIM' } else { 'NAO' }
    [void]$sb.AppendLine("**Metricas confiaveis:** $mr")
  }

  [void]$sb.AppendLine("**Evidencia:** $(Format-MdBlock $flowResult.evidence)")
  if ([string]$flowResult.status -eq 'FAIL') {
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("**Erro:** $(Format-MdBlock $flowResult.error)")
    if ($flowResult.errorLocation) {
      [void]$sb.AppendLine("**Arquivo/linha:** ``$($flowResult.errorLocation)``")
    }
    [void]$sb.AppendLine("**Impacto:** $impacto")
    [void]$sb.AppendLine("**Sugestao de investigacao:** $(Format-MdBlock $flowResult.suggestion)")
  }

  if ([string]$flowResult.status -eq 'NOT_COVERED') {
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('> Nenhum teste dedicado identificado na matriz atual. Este status **nao** significa que a funcao esta funcionando.')
  }

  if ($flowResult.PSObject.Properties.Name -contains 'm1Note' -and $flowResult.m1Note) {
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("**Nota M1:** $(Format-MdBlock $flowResult.m1Note)")
  }

  if ($flowResult.PSObject.Properties.Name -contains 'm0Note' -and $flowResult.m0Note) {
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("**Nota M0:** $(Format-MdBlock $flowResult.m0Note)")
  }
  [void]$sb.AppendLine('')
}

[void]$sb.AppendLine('## Parser warnings')
[void]$sb.AppendLine('')
if ($run.parserWarnings -and $run.parserWarnings.Count -gt 0) {
  foreach ($w in $run.parserWarnings) {
    [void]$sb.AppendLine("* $w")
  }
} else {
  [void]$sb.AppendLine('_Nenhum warning._')
}
[void]$sb.AppendLine('')

[void]$sb.AppendLine('## Riscos P0/P1/P2 encontrados pelo proprio QA Bot')
[void]$sb.AppendLine('')
if ($run.risks -and $run.risks.Count -gt 0) {
  foreach ($risk in $run.risks) {
    [void]$sb.AppendLine("* **$($risk.severity):** $($risk.detail)")
  }
} else {
  [void]$sb.AppendLine('_Nenhum risco adicional reportado nesta execucao._')
}
[void]$sb.AppendLine('')

[void]$sb.AppendLine('## Veredito')
[void]$sb.AppendLine('')
[void]$sb.AppendLine("**$verdict**")
[void]$sb.AppendLine('')
[void]$sb.AppendLine((Format-MdBlock $verdictReason))
[void]$sb.AppendLine('')
$footer = if ($phaseLabel -eq 'M1P0') {
  '_GO nesta fase significa que todos os fluxos P0 allowlisted passaram. Nao valida o MasterPalm inteiro._'
} else {
  '_GO nesta fase significa apenas que a fundacao executou corretamente dentro do escopo smoke. Nao valida o MasterPalm inteiro._'
}
[void]$sb.AppendLine('---')
[void]$sb.AppendLine($footer)
$content = $sb.ToString()
Write-QaUtf8File -Path $reportPath -Content $content
Write-Output $reportPath
