# R8.4.44A — validador PowerShell de evidência R8443 (manifesto JSON único).
param()

$ErrorActionPreference = 'Stop'

function Get-R8443ProjectRoot {
  if ($env:R8443_PROJECT_ROOT) { return $env:R8443_PROJECT_ROOT }
  $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
  return (Resolve-Path (Join-Path $scriptDir '..')).Path
}

function Get-R8443Manifest {
  $root = Get-R8443ProjectRoot
  $path = Join-Path $root 'integration_test/support/r8443_report_manifest.json'
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Manifesto R8443 ausente: $path"
  }
  return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
}

function Test-R8443ReportData {
  param(
    [hashtable]$ReportData,
    [string]$ExpectedTestCaseId,
    [string]$ExpectedRunId,
    [object]$Manifest
  )

  if ($null -eq $ReportData) {
    return @{ Ok = $false; Code = 'R8443_MISSING_REPORTDATA_REJECTED'; Message = 'reportData null' }
  }
  if ($ReportData.Count -eq 0) {
    return @{ Ok = $false; Code = 'R8443_EMPTY_REPORTDATA_REJECTED'; Message = 'reportData vazio' }
  }

  if (-not $Manifest.cases.$ExpectedTestCaseId) {
    return @{
      Ok = $false
      Code = 'R8443_WRONG_TEST_CASE_REJECTED'
      Message = "testCaseId desconhecido: $ExpectedTestCaseId"
    }
  }

  $caseDef = $Manifest.cases.$ExpectedTestCaseId
  foreach ($key in $Manifest.envelopeKeys) {
    if (-not $ReportData.ContainsKey($key)) {
      return @{
        Ok = $false
        Code = 'R8443_MISSING_REQUIRED_MARKER_REJECTED'
        Message = "envelope ausente: $key"
      }
    }
  }

  if ($ReportData['schemaVersion'] -ne $Manifest.schemaVersion) {
    return @{
      Ok = $false
      Code = 'R8443_WRONG_VALUE_REJECTED'
      Message = "schemaVersion incorreto"
    }
  }

  $gotRunId = [string]$ReportData['runId']
  if ([string]::IsNullOrWhiteSpace($gotRunId)) {
    return @{
      Ok = $false
      Code = 'R8443_MISSING_REQUIRED_MARKER_REJECTED'
      Message = 'runId vazio'
    }
  }
  if ($ExpectedRunId -and $gotRunId -ne $ExpectedRunId) {
    return @{
      Ok = $false
      Code = 'R8443_WRONG_RUN_ID_REJECTED'
      Message = "runId=$gotRunId esperado=$ExpectedRunId"
    }
  }

  $gotCase = [string]$ReportData['testCaseId']
  if ($gotCase -ne $ExpectedTestCaseId) {
    return @{
      Ok = $false
      Code = 'R8443_WRONG_TEST_CASE_REJECTED'
      Message = "testCaseId=$gotCase esperado=$ExpectedTestCaseId"
    }
  }

  foreach ($prop in $Manifest.productionCounters.PSObject.Properties) {
    $k = $prop.Name
    $expected = [string]$prop.Value
    if (-not $ReportData.ContainsKey($k)) {
      return @{
        Ok = $false
        Code = 'R8443_MISSING_REQUIRED_MARKER_REJECTED'
        Message = "contador ausente: $k"
      }
    }
    if ([string]$ReportData[$k] -ne $expected) {
      return @{
        Ok = $false
        Code = 'R8443_WRONG_VALUE_REJECTED'
        Message = "$k incorreto"
      }
    }
  }

  foreach ($prop in $caseDef.requiredMarkers.PSObject.Properties) {
    $k = $prop.Name
    $expected = [string]$prop.Value
    if (-not $ReportData.ContainsKey($k)) {
      return @{
        Ok = $false
        Code = 'R8443_MISSING_REQUIRED_MARKER_REJECTED'
        Message = "marcador ausente: $k"
      }
    }
    if ([string]$ReportData[$k] -ne $expected) {
      return @{
        Ok = $false
        Code = 'R8443_WRONG_VALUE_REJECTED'
        Message = "$k incorreto"
      }
    }
  }

  return @{ Ok = $true; Code = 'R8443_VALID_REPORT_ACCEPTED'; Message = 'ok' }
}

function Test-R8443EvidenceFile {
  param(
    [string]$FilePath,
    [string]$ExpectedTestCaseId,
    [string]$ExpectedRunId,
    [long]$PhaseStartMs = 0,
    [object]$Manifest = $null
  )

  if (-not $Manifest) { $Manifest = Get-R8443Manifest }

  if (-not (Test-Path -LiteralPath $FilePath)) {
    return @{
      Ok = $false
      Code = 'R8443_MISSING_RESPONSE_FILE_REJECTED'
      Message = "arquivo inexistente: $FilePath"
    }
  }

  try {
    $raw = Get-Content -LiteralPath $FilePath -Raw
    $decoded = $raw | ConvertFrom-Json
  } catch {
    return @{
      Ok = $false
      Code = 'R8443_INVALID_JSON_REJECTED'
      Message = $_.Exception.Message
    }
  }

  $reportData = $null
  if ($decoded.reportData) {
    $reportData = @{}
    foreach ($prop in $decoded.reportData.PSObject.Properties) {
      $reportData[$prop.Name] = [string]$prop.Value
    }
  } else {
    $reportData = @{}
    foreach ($prop in $decoded.PSObject.Properties) {
      $reportData[$prop.Name] = [string]$prop.Value
    }
  }

  $inner = Test-R8443ReportData -ReportData $reportData -ExpectedTestCaseId $ExpectedTestCaseId -ExpectedRunId $ExpectedRunId -Manifest $Manifest
  if (-not $inner.Ok) { return $inner }

  if ($PhaseStartMs -gt 0) {
    $ts = 0
    if ($reportData.ContainsKey('reportTimestampMs')) {
      [long]::TryParse([string]$reportData['reportTimestampMs'], [ref]$ts) | Out-Null
    }
    if ($ts -lt $PhaseStartMs) {
      return @{
        Ok = $false
        Code = 'R8443_STALE_REPORT_ARTIFACT_REJECTED'
        Message = "reportTimestampMs=$ts phaseStartMs=$PhaseStartMs"
      }
    }
  }

  return $inner
}

function Assert-R8443EvidenceFile {
  param(
    [string]$FilePath,
    [string]$ExpectedTestCaseId,
    [string]$ExpectedRunId,
    [long]$PhaseStartMs = 0
  )

  $result = Test-R8443EvidenceFile -FilePath $FilePath -ExpectedTestCaseId $ExpectedTestCaseId -ExpectedRunId $ExpectedRunId -PhaseStartMs $PhaseStartMs
  if (-not $result.Ok) {
    Write-Host "$($result.Code)=true $($result.Message)"
    throw "Validação R8443 falhou: $($result.Code)"
  }
  Write-Host 'R8443_VALID_REPORT_ACCEPTED=true'
}

function Test-R8443SuccessTextWithoutEvidence {
  param(
    [string]$DriveStdout,
    [string]$EvidenceFilePath
  )

  if ($DriveStdout -match 'All tests passed' -and -not (Test-Path -LiteralPath $EvidenceFilePath)) {
    return @{
      Ok = $false
      Code = 'R8443_SUCCESS_TEXT_WITHOUT_EVIDENCE_REJECTED'
      Message = 'stdout verde sem arquivo de evidência'
    }
  }
  return @{ Ok = $true; Code = 'ok'; Message = 'ok' }
}

function Assert-R8443SuccessTextWithEvidence {
  param(
    [string]$DriveStdout,
    [string]$EvidenceFilePath,
    [string]$ExpectedTestCaseId,
    [string]$ExpectedRunId,
    [long]$PhaseStartMs = 0
  )

  $textCheck = Test-R8443SuccessTextWithoutEvidence -DriveStdout $DriveStdout -EvidenceFilePath $EvidenceFilePath
  if (-not $textCheck.Ok) {
    Write-Host "$($textCheck.Code)=true"
    throw $textCheck.Message
  }
  Assert-R8443EvidenceFile -FilePath $EvidenceFilePath -ExpectedTestCaseId $ExpectedTestCaseId -ExpectedRunId $ExpectedRunId -PhaseStartMs $PhaseStartMs
}

function Get-R8443ResponseFilePath {
  param(
    [string]$TestCaseId,
    [string]$RunId
  )
  $dir = Join-Path $env:TEMP 'masterpalm-r8443-reports'
  if (-not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  return (Join-Path $dir "r8443-report-$TestCaseId-$RunId.json")
}

function Remove-R8443ResponseArtifact {
  param([string]$FilePath)
  if (Test-Path -LiteralPath $FilePath) {
    Remove-Item -LiteralPath $FilePath -Force
  }
  if (Test-Path -LiteralPath $FilePath) {
    throw "artefato não removido: $FilePath"
  }
}
