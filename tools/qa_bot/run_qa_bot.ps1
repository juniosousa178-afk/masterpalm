#Requires -Version 5.1
<#
.SYNOPSIS
  QA Bot MasterPalm - orquestrador fail-closed (M0.1 smoke default, M1P0 categorizado).

.PARAMETER M1P0
  Executa fluxos P0 allowlisted separadamente (fase M1).
#>
param(
  [switch]$M1P0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $ScriptDir 'qa_parser.ps1')
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
$MatrixPath = Join-Path $ScriptDir 'flow_matrix.json'
$RenderScript = Join-Path $ScriptDir 'render_report.ps1'
$ArtifactsDir = Join-Path $ScriptDir 'artifacts'
$DenyProjectSubstring = 'masterpalm-58c46'

# Allowlist absoluta - unica execucao permitida na fase M0
$SmokeAllowlist = @{
  Executable = 'flutter'
  Arguments  = @(
    'test',
    'test/critical_flows_source_contract_test.dart',
    '--reporter',
    'json',
    '--no-pub'
  )
  LogicalCommand = 'flutter test test/critical_flows_source_contract_test.dart --reporter json --no-pub'
  RelatedFlowIds = @('exclusao_estorno')
}

# Allowlist M1P0 - unica fonte de comandos flutter test por fluxo (nao derivar paths do JSON em runtime).
function Get-M1P0FlowAllowlist {
  return @{
    produto_simples     = @('test/produto_cadastro_persistencia_test.dart')
    produto_variacao    = @(
      'test/produto_variacao_edicao_persistencia_test.dart'
      'test/produto_estoque_grade_canonica_save_test.dart'
    )
    pdv_venda           = @(
      'test/vendas_service_test.dart'
      'test/venda_persistencia_consistencia_test.dart'
    )
    pdv_venda_variacao  = @(
      'test/venda_validacao_variacao_tamanho_cor_test.dart'
      'test/estoque_baixa_nova_venda_variacoes_test.dart'
    )
    fiado               = @(
      'test/venda_fiado_conta_receber_test.dart'
      'test/contas_receber_fiado_aparece_test.dart'
    )
    baixa_parcial       = @(
      'test/conta_receber_baixa_parcial_test.dart'
      'test/financeiro_estorna_baixa_parcial_reabre_saldo_test.dart'
    )
    exclusao_estorno    = @(
      'test/venda_exclusao_estorno_estoque_test.dart'
      'test/critical_flows_source_contract_test.dart'
    )
    sync_hive_firestore = @(
      'test/sync_produto_deletefield_set_test.dart'
      'test/contas_receber_firestore_sync_test.dart'
    )
  }
}

function Test-AllowlistedFlutterTestPath {
  param([string]$RelativePath)

  if ([string]::IsNullOrWhiteSpace($RelativePath)) { return $false }
  $normalized = $RelativePath.Trim() -replace '\\', '/'
  if ($normalized -notmatch '^test/') { return $false }
  if ($normalized -match '\.\.') { return $false }
  $full = Join-Path $RepoRoot ($normalized -replace '/', [IO.Path]::DirectorySeparatorChar)
  return (Test-Path -LiteralPath $full -PathType Leaf)
}

function Invoke-FlutterFlowTest {
  param(
    [string]$FlowId,
    [string[]]$TestPaths,
    [string]$RunId,
    [System.Collections.Generic.List[string]]$ParserWarnings
  )

  $args = @('test') + $TestPaths + @('--reporter', 'json', '--no-pub')
  $logicalCommand = 'flutter test ' + ($TestPaths -join ' ') + ' --reporter json --no-pub'
  $safeFlowId = ($FlowId -replace '[^a-zA-Z0-9_\-]', '_')
  $stdoutFile = Join-Path $ArtifactsDir "flow_${safeFlowId}_stdout_$RunId.jsonl"
  $stderrFile = Join-Path $ArtifactsDir "flow_${safeFlowId}_stderr_$RunId.log"

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $exitCode = -1
  $stderrText = ''

  try {
    $proc = Start-Process -FilePath 'flutter' `
      -ArgumentList $args `
      -WorkingDirectory $RepoRoot `
      -NoNewWindow `
      -Wait `
      -PassThru `
      -RedirectStandardOutput $stdoutFile `
      -RedirectStandardError $stderrFile
    $exitCode = $proc.ExitCode
  } catch {
    $sw.Stop()
    return @{
      flowId                = $FlowId
      logicalCommand        = $logicalCommand
      executedTests         = $TestPaths
      exitCode              = -1
      durationSeconds       = [Math]::Round($sw.Elapsed.TotalSeconds, 3)
      passed                = 0
      failed                = 0
      skipped               = 0
      realTestCasesDetected = 0
      metricsReliable       = $false
      protocolCompleted     = $false
      executionStatus       = 'INFRA_ERROR'
      evidence              = "Falha ao iniciar flutter test para fluxo $FlowId."
      error                 = $_.Exception.Message
      failures              = @()
      stdoutArtifact        = $stdoutFile
      stderrArtifact        = $stderrFile
    }
  }

  $sw.Stop()
  $stdoutLines = @()
  if (Test-Path -LiteralPath $stdoutFile) {
    $stdoutLines = Get-Content -LiteralPath $stdoutFile -Encoding UTF8
  }
  if (Test-Path -LiteralPath $stderrFile) {
    $rawErr = Get-Content -LiteralPath $stderrFile -Raw -Encoding UTF8
    if ($null -ne $rawErr) { $stderrText = $rawErr }
  }

  $parsed = Parse-FlutterTestJsonLines -Lines $stdoutLines -ParserWarnings $ParserWarnings
  $resolved = Resolve-SmokeExecutionStatus -Parsed $parsed -ExitCode $exitCode -StderrText $stderrText

  return @{
    flowId                = $FlowId
    logicalCommand        = $logicalCommand
    executedTests         = $TestPaths
    exitCode              = $exitCode
    durationSeconds       = [Math]::Round($sw.Elapsed.TotalSeconds, 3)
    passed                = $parsed.passed
    failed                = $parsed.failed
    skipped               = $parsed.skipped
    realTestCasesDetected = $parsed.realTestCasesDetected
    metricsReliable       = $parsed.metricsReliable
    protocolCompleted     = $parsed.protocolCompleted
    executionStatus       = $resolved.status
    evidence              = $resolved.evidence
    error                 = if ($resolved.error) { $resolved.error } else { '' }
    failures              = $parsed.failures
    stdoutArtifact        = $stdoutFile
    stderrArtifact        = $stderrFile
  }
}

function Get-FlowSuggestion {
  param(
    [string]$FlowId,
    [string]$Status
  )
  if ($Status -eq 'FAIL' -or $Status -eq 'INFRA_ERROR') {
    switch ($FlowId) {
      'produto_simples' { return 'Revisar produto_cadastro_persistencia_test.dart e servicos de persistencia Hive/Firestore.' }
    'produto_variacao' { return 'Revisar persistencia de variacoes e grade canonica no cadastro.' }
    'pdv_venda' { return 'Revisar VendasService, resolucao de produto e persistencia/rollback pre-Hive.' }
    'pdv_venda_variacao' { return 'Revisar validacao de variacao obrigatoria e baixa de estoque por variacao.' }
    'fiado' { return 'Revisar criacao de conta a receber e exibicao de fiado em contas_receber.' }
    'baixa_parcial' { return 'Revisar baixa parcial e estorno parcial de saldo em financeiro.' }
    'exclusao_estorno' { return 'Revisar estorno de estoque e guardas de exclusao definitiva.' }
    'sync_hive_firestore' { return 'Revisar sync produto/contas_receber entre Hive e Firestore fake.' }
      default { return "Inspecionar testes mapeados para o fluxo $FlowId." }
    }
  }
  return ''
}

function Build-FlowResultsM1 {
  param(
    $Matrix,
    [hashtable]$FlowExecutions,
    [bool]$PreflightPassed,
    [string[]]$PreflightBlockers,
    [string[]]$ExecuteFlowIds,
    [string[]]$ExcludedP0Ids
  )

  $results = @()
  foreach ($flow in $Matrix.flows) {
    $flowId = [string]$flow.id
    $entry = [ordered]@{
      id              = $flowId
      descricao       = [string]$flow.descricao
      impacto         = [string]$flow.impacto
      runner          = [string]$flow.runner
      statusCobertura = [string]$flow.statusCobertura
      tests           = @()
      executedTests   = @()
      status          = $null
      evidence        = ''
      error           = ''
      errorLocation   = ''
      suggestion      = ''
      m1Note          = ''
      passed          = $null
      failed          = $null
      skipped         = $null
      durationSeconds = $null
      logicalCommand  = ''
      metricsReliable = $null
    }

    if ($flow.tests) {
      foreach ($t in $flow.tests) { $entry.tests += [string]$t }
    }

    if (-not $PreflightPassed) {
      $entry.status = 'BLOCKED'
      $entry.evidence = ($PreflightBlockers -join ' ')
      $results += [pscustomobject]$entry
      continue
    }

    if ([string]$flow.statusCobertura -eq 'NOT_COVERED') {
      $entry.status = 'NOT_COVERED'
      $entry.evidence = 'Nenhum teste dedicado identificado na matriz atual.'
      $results += [pscustomobject]$entry
      continue
    }

    if ($ExcludedP0Ids -contains $flowId) {
      $entry.m1Note = 'P0 omitido na fase M1P0: requer emulador ou runner nao allowlisted.'
      $entry.evidence = 'Declarado em flow_matrix.json m1P0Execution.excludedP0.'
      $results += [pscustomobject]$entry
      continue
    }

    if ($ExecuteFlowIds -contains $flowId) {
      $exec = $FlowExecutions[$flowId]
      if ($null -eq $exec) {
        $entry.status = 'INFRA_ERROR'
        $entry.evidence = 'Execucao ausente para fluxo allowlisted.'
        $entry.suggestion = 'Verificar allowlist M1P0 em run_qa_bot.ps1.'
        $results += [pscustomobject]$entry
        continue
      }

      $entry.executedTests = @($exec.executedTests)
      $entry.logicalCommand = [string]$exec.logicalCommand
      $entry.passed = $exec.passed
      $entry.failed = $exec.failed
      $entry.skipped = $exec.skipped
      $entry.durationSeconds = $exec.durationSeconds
      $entry.metricsReliable = $exec.metricsReliable
      $entry.status = [string]$exec.executionStatus
      $entry.evidence = [string]$exec.evidence
      $entry.error = [string]$exec.error

      if ($exec.failures -and $exec.failures.Count -gt 0) {
        $f = $exec.failures[0]
        if ($f.error) { $entry.error = [string]$f.error }
        if ($f.url) {
          $entry.errorLocation = ([string]$f.url) -replace '^file:///', '' -replace '\\', '/'
        }
      }

      $entry.suggestion = Get-FlowSuggestion -FlowId $flowId -Status $entry.status
      $results += [pscustomobject]$entry
      continue
    }

    $entry.m1Note = 'Omitido na fase M1P0 (escopo P1 ou fora da lista executeFlowIds).'
    $entry.evidence = 'Matriz declarativa - testes existem mas nao foram executados nesta fase.'
    $results += [pscustomobject]$entry
  }

  return $results
}

function Compute-VerdictM1 {
  param(
    [array]$FlowResults,
    [bool]$PreflightPassed,
    [string[]]$ExecuteFlowIds
  )

  if (-not $PreflightPassed) {
    return @{
      verdict = 'NO-GO'
      reason  = 'Preflight de seguranca bloqueou a execucao (BLOCKED).'
    }
  }

  foreach ($flowId in $ExecuteFlowIds) {
    $fr = $FlowResults | Where-Object { [string]$_.id -eq $flowId } | Select-Object -First 1
    if ($null -eq $fr) {
      return @{
        verdict = 'NO-GO'
        reason  = "Fluxo P0 allowlisted ausente no resultado: $flowId."
      }
    }
    $status = [string]$fr.status
    if ($status -eq 'FAIL' -or $status -eq 'INFRA_ERROR') {
      return @{
        verdict = 'NO-GO'
        reason  = "$status no fluxo P0 $flowId."
      }
    }
    if ($fr.metricsReliable -eq $false -and $status -eq 'PASS') {
      return @{
        verdict = 'NO-GO'
        reason  = "Parser nao confiavel no fluxo P0 $flowId."
      }
    }
    if ($status -ne 'PASS') {
      return @{
        verdict = 'NO-GO'
        reason  = "Status inesperado ($status) no fluxo P0 $flowId."
      }
    }
  }

  return @{
    verdict = 'GO'
    reason  = 'M1P0 concluido: todos os fluxos P0 allowlisted passaram; cliente_cadastro permanece NOT_COVERED.'
  }
}

function Get-M1ParserIntegritySummary {
  param(
    [hashtable]$FlowExecutions,
    [System.Collections.Generic.List[string]]$ParserWarnings
  )

  $passed = 0
  $failed = 0
  $skipped = 0
  $real = 0
  $allReliable = $true
  $allProtocol = $true

  foreach ($key in $FlowExecutions.Keys) {
    $e = $FlowExecutions[$key]
    $passed += [int]$e.passed
    $failed += [int]$e.failed
    $skipped += [int]$e.skipped
    $real += [int]$e.realTestCasesDetected
    if (-not $e.metricsReliable) { $allReliable = $false }
    if (-not $e.protocolCompleted) { $allProtocol = $false }
  }

  return @{
    realTestCasesDetected = $real
    passed                = $passed
    failed                = $failed
    skipped               = $skipped
    parserWarnings        = @($ParserWarnings)
    protocolCompleted     = $allProtocol
    exitCode              = $null
    metricsReliable       = $allReliable
  }
}

function Get-UtcTimestampForFile {
  return (Get-Date).ToUniversalTime().ToString('yyyyMMdd_HHmmss')
}

function Invoke-Git {
  param([string[]]$GitArgs)
  $output = & git -C $RepoRoot @GitArgs 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "git $($GitArgs -join ' ') falhou (exit $LASTEXITCODE): $output"
  }
  return ($output | Out-String).Trim()
}

function Test-ProjectIdSafe {
  param(
    [string]$Name,
    [string]$Value
  )

  $checks = @()
  $blockers = @()

  if ([string]::IsNullOrWhiteSpace($Value)) {
    $checks += [ordered]@{
      name   = $Name
      passed = $true
      detail = 'nao definido (aceito)'
    }
    return @{ checks = $checks; blockers = $blockers }
  }

  $normalized = $Value.Trim()
  $lower = $normalized.ToLowerInvariant()

  if ($lower.Contains($DenyProjectSubstring)) {
    $checks += [ordered]@{
      name   = $Name
      passed = $false
      detail = "contem identificador de producao bloqueado ($Name=$normalized)"
    }
    $blockers += "$Name contem identificador de producao bloqueado."
    return @{ checks = $checks; blockers = $blockers }
  }

  if (-not $lower.StartsWith('demo-masterpalm-')) {
    $checks += [ordered]@{
      name   = $Name
      passed = $false
      detail = "$Name=$normalized nao comeca com demo-masterpalm-"
    }
    $blockers += "$Name definido mas fora do prefixo demo-masterpalm-."
    return @{ checks = $checks; blockers = $blockers }
  }

  $checks += [ordered]@{
    name   = $Name
    passed = $true
    detail = "$Name=$normalized"
  }
  return @{ checks = $checks; blockers = $blockers }
}

function Test-FirestoreEmulatorHostSafe {
  param([string]$HostValue)

  $checks = @()
  $blockers = @()

  if ([string]::IsNullOrWhiteSpace($HostValue)) {
    $checks += [ordered]@{
      name   = 'FIRESTORE_EMULATOR_HOST'
      passed = $true
      detail = 'nao definido (aceito para smoke M0 unitaria)'
    }
    return @{ checks = $checks; blockers = $blockers }
  }

  $normalized = $HostValue.Trim()
  if ($normalized.ToLowerInvariant().Contains($DenyProjectSubstring)) {
    $checks += [ordered]@{
      name   = 'FIRESTORE_EMULATOR_HOST'
      passed = $false
      detail = 'contem identificador de producao bloqueado'
    }
    $blockers += 'FIRESTORE_EMULATOR_HOST contem identificador bloqueado.'
    return @{ checks = $checks; blockers = $blockers }
  }

  if ($normalized -match '^(localhost|127\.0\.0\.1|\[::1\]|::1)(:\d+)?$') {
    $checks += [ordered]@{
      name   = 'FIRESTORE_EMULATOR_HOST'
      passed = $true
      detail = $normalized
    }
    return @{ checks = $checks; blockers = $blockers }
  }

  $checks += [ordered]@{
    name   = 'FIRESTORE_EMULATOR_HOST'
    passed = $false
    detail = "host remoto ou invalido: $normalized"
  }
  $blockers += "FIRESTORE_EMULATOR_HOST aponta para host nao local: $normalized"
  return @{ checks = $checks; blockers = $blockers }
}

function Test-GoogleApplicationCredentialsSafe {
  param([string]$PathValue)

  $checks = @()
  $blockers = @()

  if ([string]::IsNullOrWhiteSpace($PathValue)) {
    $checks += [ordered]@{
      name   = 'GOOGLE_APPLICATION_CREDENTIALS'
      passed = $true
      detail = 'nao definido (aceito)'
    }
    return @{ checks = $checks; blockers = $blockers }
  }

  $checks += [ordered]@{
    name   = 'GOOGLE_APPLICATION_CREDENTIALS'
    passed = $false
    detail = 'variavel definida - risco de credencial de producao (conteudo nao inspecionado)'
  }
  $blockers += 'GOOGLE_APPLICATION_CREDENTIALS definido - execucao M0 abortada por seguranca.'
  return @{ checks = $checks; blockers = $blockers }
}

function Invoke-Preflight {
  $allChecks = @()
  $allBlockers = @()

  foreach ($pair in @(
      @{ Name = 'GCLOUD_PROJECT'; Value = $env:GCLOUD_PROJECT },
      @{ Name = 'FIREBASE_PROJECT'; Value = $env:FIREBASE_PROJECT }
    )) {
    $result = Test-ProjectIdSafe -Name $pair.Name -Value $pair.Value
    $allChecks += $result.checks
    $allBlockers += $result.blockers
  }

  $emu = Test-FirestoreEmulatorHostSafe -HostValue $env:FIRESTORE_EMULATOR_HOST
  $allChecks += $emu.checks
  $allBlockers += $emu.blockers

  $gac = Test-GoogleApplicationCredentialsSafe -PathValue $env:GOOGLE_APPLICATION_CREDENTIALS
  $allChecks += $gac.checks
  $allBlockers += $gac.blockers

  # Scan generico de denylist em variaveis de ambiente relevantes
  $envNames = @(
    'GCLOUD_PROJECT', 'FIREBASE_PROJECT', 'GOOGLE_CLOUD_PROJECT',
    'FIREBASE_CONFIG', 'FIRESTORE_EMULATOR_HOST'
  )
  foreach ($envName in $envNames) {
    $val = [Environment]::GetEnvironmentVariable($envName)
    if ($val -and $val.ToLowerInvariant().Contains($DenyProjectSubstring)) {
      $allChecks += [ordered]@{
        name   = "denylist_scan:$envName"
        passed = $false
        detail = 'contem identificador de producao bloqueado'
      }
      $allBlockers += "Variavel $envName contem identificador de producao bloqueado."
    }
  }

  $uniqueBlockers = @($allBlockers | Select-Object -Unique)
  return @{
    passed   = ($uniqueBlockers.Count -eq 0)
    checks   = $allChecks
    blockers = $uniqueBlockers
  }
}

function Read-FlowMatrix {
  if (-not (Test-Path -LiteralPath $MatrixPath)) {
    throw "flow_matrix.json nao encontrado: $MatrixPath"
  }
  $raw = Get-Content -LiteralPath $MatrixPath -Raw -Encoding UTF8
  try {
    return ($raw | ConvertFrom-Json)
  } catch {
    throw "flow_matrix.json invalido: $($_.Exception.Message)"
  }
}

function Build-FlowResults {
  param(
    $Matrix,
    [hashtable]$SmokeResult,
    [string]$PreflightPassed,
    [string[]]$PreflightBlockers
  )

  $results = @()
  $smokeRelated = @($SmokeAllowlist.RelatedFlowIds)

  foreach ($flow in $Matrix.flows) {
    $entry = [ordered]@{
      id              = [string]$flow.id
      descricao       = [string]$flow.descricao
      impacto         = [string]$flow.impacto
      runner          = [string]$flow.runner
      statusCobertura = [string]$flow.statusCobertura
      tests           = @()
      status          = ''
      evidence        = ''
      error           = ''
      errorLocation   = ''
      suggestion      = ''
      m0Note          = ''
    }

    if ($flow.tests) {
      foreach ($t in $flow.tests) { $entry.tests += [string]$t }
    }

    if (-not $PreflightPassed) {
      $entry.status = 'BLOCKED'
      $entry.evidence = ($PreflightBlockers -join ' ')
      $results += [pscustomobject]$entry
      continue
    }

    if ([string]$flow.statusCobertura -eq 'NOT_COVERED') {
      $entry.status = 'NOT_COVERED'
      $entry.evidence = 'Nenhum teste mapeado em flow_matrix.json.'
      $results += [pscustomobject]$entry
      continue
    }

    if ($smokeRelated -contains [string]$flow.id) {
      if ($SmokeResult.executionStatus -eq 'INFRA_ERROR') {
        $entry.status = 'INFRA_ERROR'
        $entry.evidence = $SmokeResult.evidence
        $entry.error = $SmokeResult.error
        $entry.suggestion = 'Verificar Flutter, PATH e logs da smoke suite.'
      } elseif ($SmokeResult.failed -gt 0 -or $SmokeResult.executionStatus -eq 'FAIL') {
        $entry.status = 'FAIL'
        $entry.evidence = $SmokeResult.evidence
        if ($SmokeResult.failures.Count -gt 0) {
          $f = $SmokeResult.failures[0]
          $entry.error = if ($f.error) { $f.error } else { "result=$($f.result)" }
          if ($f.url) {
            $entry.errorLocation = $f.url -replace '^file:///', '' -replace '\\', '/'
          }
        }
        $entry.suggestion = 'Inspecionar contratos estaticos em critical_flows_source_contract_test.dart e codigo referenciado.'
      } else {
        $entry.status = 'PASS'
        $entry.evidence = $SmokeResult.evidence
      }
      $results += [pscustomobject]$entry
      continue
    }

    # Fluxo mapeado mas fora da smoke M0 - nao usar NOT_COVERED (reservado a fluxo sem teste)
    $entry.status = $null
    $entry.statusCobertura = [string]$flow.statusCobertura
    $entry.m0Note = 'Execucao omitida na fase M0 (fora da smoke allowlist). Cobertura declarada na matriz nao foi exercitada nesta execucao.'
    $entry.evidence = 'Matriz declarativa apenas - testes existem mas nao foram executados nesta fase.'
    $results += [pscustomobject]$entry
  }

  return $results
}

function Compute-Verdict {
  param(
    [array]$FlowResults,
    [bool]$PreflightPassed,
    [string]$SmokeExecutionStatus
  )

  if (-not $PreflightPassed) {
    return @{
      verdict = 'NO-GO'
      reason  = 'Preflight de seguranca bloqueou a execucao (BLOCKED).'
    }
  }

  if ($SmokeExecutionStatus -eq 'INFRA_ERROR') {
    return @{
      verdict = 'NO-GO'
      reason  = 'INFRA_ERROR impediu validar a smoke suite M0.'
    }
  }

  foreach ($fr in $FlowResults) {
    if ([string]$fr.status -eq 'FAIL' -and [string]$fr.impacto -eq 'P0') {
      return @{
        verdict = 'NO-GO'
        reason  = "FAIL P0 no fluxo $($fr.id)."
      }
    }
  }

  return @{
    verdict = 'GO'
    reason  = 'Fundacao M0.1 executou corretamente: preflight OK, smoke allowlisted concluida sem FAIL P0, BLOCKED ou INFRA_ERROR; parser alinhado ao runner humano.'
  }
}

# --- main ---

$runId = Get-UtcTimestampForFile
$timestampUtc = $runId
$branch = Invoke-Git -GitArgs @('branch', '--show-current')
$head = Invoke-Git -GitArgs @('rev-parse', 'HEAD')

if (-not (Test-Path -LiteralPath $ArtifactsDir)) {
  New-Item -ItemType Directory -Force -Path $ArtifactsDir | Out-Null
}

$matrix = Read-FlowMatrix
$parserWarnings = [System.Collections.Generic.List[string]]::new()
$risks = [System.Collections.Generic.List[object]]::new()

[void]$risks.Add([ordered]@{
    severity = 'P0'
    detail   = 'Scripts legados em scripts/ podem acessar producao - fora do escopo do QA Bot.'
  })
[void]$risks.Add([ordered]@{
    severity = 'P1'
    detail   = 'Working tree suja - baseline de testes pode divergir entre maquinas.'
  })
[void]$risks.Add([ordered]@{
    severity = 'P1'
    detail   = 'firestore_rules (P0) omitido em M1P0 por depender de emulador.'
  })

$preflight = Invoke-Preflight

if ($M1P0) {
  $m1Config = $matrix.m1P0Execution
  if ($null -eq $m1Config) {
    throw 'flow_matrix.json sem bloco m1P0Execution.'
  }

  $executeFlowIds = @($m1Config.executeFlowIds | ForEach-Object { [string]$_ })
  $excludedP0Ids = @()
  if ($m1Config.excludedP0) {
    foreach ($ex in $m1Config.excludedP0) { $excludedP0Ids += [string]$ex.id }
  }

  $allowlist = Get-M1P0FlowAllowlist
  $flowExecutions = @{}

  if ($preflight.passed) {
    foreach ($flowId in $executeFlowIds) {
      if (-not $allowlist.ContainsKey($flowId)) {
        throw "Fluxo M1P0 allowlisted sem entrada fixa no script: $flowId"
      }
      $paths = @($allowlist[$flowId])
      foreach ($p in $paths) {
        if (-not (Test-AllowlistedFlutterTestPath -RelativePath $p)) {
          throw "Arquivo de teste inexistente ou invalido para $flowId : $p"
        }
      }
      $flowExecutions[$flowId] = Invoke-FlutterFlowTest `
        -FlowId $flowId `
        -TestPaths $paths `
        -RunId $runId `
        -ParserWarnings $parserWarnings
    }
  }

  $flowResults = Build-FlowResultsM1 `
    -Matrix $matrix `
    -FlowExecutions $flowExecutions `
    -PreflightPassed $preflight.passed `
    -PreflightBlockers $preflight.blockers `
    -ExecuteFlowIds $executeFlowIds `
    -ExcludedP0Ids $excludedP0Ids

  $verdictInfo = Compute-VerdictM1 `
    -FlowResults $flowResults `
    -PreflightPassed $preflight.passed `
    -ExecuteFlowIds $executeFlowIds

  $parserIntegrity = Get-M1ParserIntegritySummary -FlowExecutions $flowExecutions -ParserWarnings $parserWarnings

  $flowExecutionsArtifact = @()
  foreach ($key in ($flowExecutions.Keys | Sort-Object)) {
    $flowExecutionsArtifact += $flowExecutions[$key]
  }

  $artifact = [ordered]@{
    phase            = 'M1P0'
    runId            = $runId
    timestampUtc     = $timestampUtc
    repoRoot         = $RepoRoot
    branch           = $branch
    head             = $head
    preflight        = $preflight
    smoke            = $null
    flowExecutions   = @($flowExecutionsArtifact)
    parserIntegrity  = $parserIntegrity
    flowResults      = @($flowResults)
    parserWarnings   = @($parserWarnings)
    risks            = @($risks)
    verdict          = $verdictInfo.verdict
    verdictReason    = $verdictInfo.reason
  }

  $artifactPath = Join-Path $ArtifactsDir "run_$runId.json"
  Write-QaUtf8File -Path $artifactPath -Content ($artifact | ConvertTo-Json -Depth 14)

  $reportPath = & $RenderScript -RunArtifactPath $artifactPath

  Write-Host ""
  Write-Host "QA Bot M1P0 concluido."
  Write-Host "  Veredito: $($verdictInfo.verdict)"
  Write-Host "  Relatorio: $reportPath"
  Write-Host "  Artefato:  $artifactPath"

  if ($verdictInfo.verdict -eq 'NO-GO') { exit 2 }
  exit 0
}

# --- M0.1 default (smoke) ---
$smoke = $null
$smokeResult = @{
  executionStatus = 'NOT_RUN'
  passed          = 0
  failed          = 0
  skipped         = 0
  evidence        = ''
  error           = ''
  failures        = @()
}

if ($preflight.passed) {
  $stdoutFile = Join-Path $ArtifactsDir "smoke_stdout_$runId.jsonl"
  $stderrFile = Join-Path $ArtifactsDir "smoke_stderr_$runId.log"

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $proc = Start-Process -FilePath $SmokeAllowlist.Executable `
      -ArgumentList $SmokeAllowlist.Arguments `
      -WorkingDirectory $RepoRoot `
      -NoNewWindow `
      -Wait `
      -PassThru `
      -RedirectStandardOutput $stdoutFile `
      -RedirectStandardError $stderrFile
    $exitCode = $proc.ExitCode
  } catch {
    $sw.Stop()
    $smokeResult.executionStatus = 'INFRA_ERROR'
    $smokeResult.evidence = "Falha ao iniciar processo flutter: $($_.Exception.Message)"
    $smokeResult.error = $_.Exception.Message
    [void]$parserWarnings.Add($smokeResult.evidence)
    $exitCode = -1
    $stdoutLines = @()
    $stderrText = ''
  }

  if ($smokeResult.executionStatus -ne 'INFRA_ERROR') {
    $sw.Stop()
    $stdoutLines = @()
    if (Test-Path -LiteralPath $stdoutFile) {
      $stdoutLines = Get-Content -LiteralPath $stdoutFile -Encoding UTF8
    }
    $stderrText = ''
    if (Test-Path -LiteralPath $stderrFile) {
      $rawErr = Get-Content -LiteralPath $stderrFile -Raw -Encoding UTF8
      if ($null -ne $rawErr) { $stderrText = $rawErr }
    }

    $parsed = Parse-FlutterTestJsonLines -Lines $stdoutLines -ParserWarnings $parserWarnings
    $resolved = Resolve-SmokeExecutionStatus -Parsed $parsed -ExitCode $exitCode -StderrText $stderrText

    $smokeResult.executionStatus = $resolved.status
    $smokeResult.evidence = $resolved.evidence
    if ($resolved.error) { $smokeResult.error = $resolved.error }

    $smokeResult.passed = $parsed.passed
    $smokeResult.failed = $parsed.failed
    $smokeResult.skipped = $parsed.skipped
    $smokeResult.failures = $parsed.failures
    $smokeResult.realTestCasesDetected = $parsed.realTestCasesDetected
    $smokeResult.metricsReliable = $parsed.metricsReliable
    $smokeResult.protocolCompleted = $parsed.protocolCompleted

    if ($parsed.doneSeen -eq $false -and $stdoutLines.Count -eq 0) {
      [void]$parserWarnings.Add('Smoke suite nao produziu JSON parseavel.')
    }
  }

  $smoke = [ordered]@{
    runId            = $runId
    logicalCommand   = $SmokeAllowlist.LogicalCommand
    exitCode         = $exitCode
    durationSeconds  = [Math]::Round($sw.Elapsed.TotalSeconds, 3)
    passed           = $smokeResult.passed
    failed           = $smokeResult.failed
    skipped          = $smokeResult.skipped
    realTestCasesDetected = $smokeResult.realTestCasesDetected
    metricsReliable  = $smokeResult.metricsReliable
    protocolCompleted = $smokeResult.protocolCompleted
    executionStatus  = $smokeResult.executionStatus
    stdoutArtifact   = $stdoutFile
    stderrArtifact   = $stderrFile
  }
}

$flowResults = Build-FlowResults -Matrix $matrix -SmokeResult $smokeResult -PreflightPassed $preflight.passed -PreflightBlockers $preflight.blockers
$verdictInfo = Compute-Verdict -FlowResults $flowResults -PreflightPassed $preflight.passed -SmokeExecutionStatus $smokeResult.executionStatus

$parserIntegrity = [ordered]@{
  realTestCasesDetected = if ($null -ne $smokeResult.realTestCasesDetected) { $smokeResult.realTestCasesDetected } else { 0 }
  passed                = $smokeResult.passed
  failed                = $smokeResult.failed
  skipped               = $smokeResult.skipped
  parserWarnings        = @($parserWarnings)
  protocolCompleted     = if ($null -ne $smokeResult.protocolCompleted) { $smokeResult.protocolCompleted } else { $false }
  exitCode              = if ($null -ne $smoke) { $smoke.exitCode } else { $null }
  metricsReliable       = if ($null -ne $smokeResult.metricsReliable) { $smokeResult.metricsReliable } else { $false }
}

$artifact = [ordered]@{
  phase            = 'M0.1'
  runId            = $runId
  timestampUtc     = $timestampUtc
  repoRoot         = $RepoRoot
  branch           = $branch
  head             = $head
  preflight        = $preflight
  smoke            = $smoke
  parserIntegrity  = $parserIntegrity
  flowResults      = @($flowResults)
  parserWarnings   = @($parserWarnings)
  risks            = @($risks)
  verdict          = $verdictInfo.verdict
  verdictReason    = $verdictInfo.reason
}

$artifactPath = Join-Path $ArtifactsDir "run_$runId.json"
Write-QaUtf8File -Path $artifactPath -Content ($artifact | ConvertTo-Json -Depth 12)

$reportPath = & $RenderScript -RunArtifactPath $artifactPath

Write-Host ""
Write-Host "QA Bot M0.1 concluido."
Write-Host "  Veredito: $($verdictInfo.verdict)"
Write-Host "  Relatorio: $reportPath"
Write-Host "  Artefato:  $artifactPath"

if ($verdictInfo.verdict -eq 'NO-GO') {
  exit 2
}
exit 0
