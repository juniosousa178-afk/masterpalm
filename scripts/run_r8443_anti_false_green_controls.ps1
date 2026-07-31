# R8.4.44A — controles negativos anti-falso-verde (flutter drive real + validador PS).
param(
  [int]$WebPort = 8811,
  [int]$ChromeDriverPort = 4455
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$env:R8443_PROJECT_ROOT = $ProjectRoot
Set-Location $ProjectRoot

. (Join-Path $ProjectRoot 'scripts/r8443_report_validator.ps1')

$WebHost = '127.0.0.1'
$RunSuffix = [guid]::NewGuid().ToString('N').Substring(0, 8)
$ProfileBase = Join-Path $env:TEMP "masterpalm-r8443-anti-fg-profile-$RunSuffix"
$CreatedProfiles = @()
$manifest = Get-R8443Manifest
$controlRows = @()

function Test-PortListening {
  param([int]$Port)
  $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
  return ($null -ne $conns -and $conns.Count -gt 0)
}

function Resolve-ChromeDriverPort {
  param([int]$PreferredPort)
  for ($p = $PreferredPort; $p -le ($PreferredPort + 10); $p++) {
    if (-not (Test-PortListening -Port $p)) {
      return $p
    }
  }
  throw "Nenhuma porta ChromeDriver livre entre $PreferredPort e $($PreferredPort + 10)"
}

function Find-ChromeDriverExe {
  param([int]$Major = 150)
  foreach ($root in @(
      (Join-Path $ProjectRoot 'tool\e2e_web\chromedriver'),
      (Join-Path $env:USERPROFILE '.cache\puppeteer\chromedriver')
    )) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    $candidates = Get-ChildItem -Path $root -Recurse -Filter 'chromedriver.exe' -ErrorAction SilentlyContinue
    $match = $candidates | Where-Object { $_.FullName -match "win64-$Major" } | Select-Object -First 1
    if ($match) { return $match.FullName }
    if ($candidates) { return $candidates[0].FullName }
  }
  return $null
}

function Get-ChromeExe {
  foreach ($p in @(
      "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
      "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
      "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )) {
    if (Test-Path -LiteralPath $p) { return $p }
  }
  return $null
}

function Get-MajorVersion {
  param([string]$VersionString)
  if ([string]::IsNullOrWhiteSpace($VersionString)) { return 0 }
  $m = [regex]::Match($VersionString, '(\d+)')
  if ($m.Success) { return [int]$m.Groups[1].Value }
  return 0
}

function Stop-ProcessTree {
  param([int]$ParentId)
  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ParentProcessId -eq $ParentId } |
    ForEach-Object { Stop-ProcessTree -ParentId $_.ProcessId }
  Stop-Process -Id $ParentId -Force -ErrorAction SilentlyContinue
}

function New-R8443ChromeProfile {
  param([string]$Label)
  $path = Join-Path $ProfileBase $Label
  if (Test-Path -LiteralPath $path) {
    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
  }
  New-Item -ItemType Directory -Path $path -Force | Out-Null
  $CreatedProfiles += $path
  return $path
}

function Invoke-R8443GuardedDrive {
  param(
    [string]$Target,
    [string]$TestCaseId,
    [string]$RunId,
    [string]$ResponseFile,
    [string]$ProfilePath
  )

  $userDataFlag = "--user-data-dir=$($ProfilePath -replace '\\','/')"
  $defines = @(
    '--dart-define=MP_ENVIRONMENT=qa',
    '--dart-define=MP_USE_FIREBASE_EMULATORS=true',
    '--dart-define=MP_AUTH_EMULATOR_HOST=127.0.0.1:9199',
    '--dart-define=MP_FIRESTORE_EMULATOR_HOST=127.0.0.1:8180',
    '--dart-define=MP_STORAGE_EMULATOR_HOST=127.0.0.1:9199',
    "--dart-define=R8443_RUN_ID=$RunId",
    "--dart-define=R8443_TEST_CASE_ID=$TestCaseId",
    "--dart-define=R8443_RESPONSE_FILE=$($ResponseFile -replace '\\','/')"
  )

  $stdout = @()
  $env:R8443_RUN_ID = $RunId
  $env:R8443_TEST_CASE_ID = $TestCaseId
  $env:R8443_RESPONSE_FILE = $ResponseFile
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  flutter drive `
    --driver=test_driver/r8443_guarded_driver.dart `
    --target=$Target `
    -d chrome `
    --release `
    --driver-port=$ChromeDriverPort `
    --web-hostname=$WebHost `
    --web-port=$WebPort `
    --web-browser-flag=$userDataFlag `
    --web-browser-flag="--headless=new" `
    @defines 2>&1 | ForEach-Object {
      $stdout += $_.ToString()
      Write-Host $_
    }
  $exit = $LASTEXITCODE
  $ErrorActionPreference = $prevEap
  return @{ Exit = $exit; Stdout = ($stdout -join "`n") }
}

function Add-ControlRow {
  param(
    [string]$TestCase,
    [int]$FlutterDriveExit = -1,
    [int]$ValidatorExit = 0,
    [bool]$ExpectedFailureObserved,
    [string]$ReportFile = '',
    [string]$RunId = '',
    [string]$TestCaseId = '',
    [bool]$Pass,
    [bool]$ValidatorExecuted = $false,
    [string]$EvidenceSource = ''
  )
  $reportCreated = $false
  if ($ReportFile -and (Test-Path -LiteralPath $ReportFile)) {
    $reportCreated = $true
  }
  $runIdRecorded = if ($reportCreated) { $RunId } else { 'N/A' }
  $testCaseIdRecorded = if ($reportCreated) { $TestCaseId } else {
    if ($TestCase -in @('missing_reportdata', 'empty_reportdata', 'missing_marker')) { $TestCaseId }
    else { 'N/A' }
  }
  $validatorExitRecorded = if ($ValidatorExecuted) { $ValidatorExit } else { 'N/A' }
  $script:controlRows += [pscustomobject]@{
    TEST_CASE = $TestCase
    RUN_ID_EXPECTED = $RunId
    REPORT_FILE_EXPECTED = $ReportFile
    REPORT_FILE_CREATED = $reportCreated
    FLUTTER_DRIVE_EXIT_CODE = $FlutterDriveExit
    VALIDATOR_EXECUTED = $ValidatorExecuted
    VALIDATOR_EXIT_CODE = $validatorExitRecorded
    EXPECTED_FAILURE_OBSERVED = $ExpectedFailureObserved
    RUN_ID = $runIdRecorded
    TEST_CASE_ID = $testCaseIdRecorded
    EVIDENCE_SOURCE = $EvidenceSource
    PASS = $Pass
  }
}

# --- Versões (sem download silencioso) ---
$flutterVer = (flutter --version 2>&1 | Out-String).Trim()
Write-Host "FLUTTER_VERSION=$flutterVer"

$cdExe = Find-ChromeDriverExe -Major 150
if (-not $cdExe) {
  Write-Host 'R8443_CHROME_DRIVER_VERSION_MISMATCH'
  throw 'chromedriver.exe não encontrado localmente (sem install automático neste gate)'
}
$cdVer = (& $cdExe --version 2>&1 | Out-String).Trim()
Write-Host "CHROMEDRIVER_PATH=$cdExe"
Write-Host "CHROMEDRIVER_VERSION=$cdVer"

$chromeExe = Get-ChromeExe
$chromeMajor = 0
if ($chromeExe) {
  $chromeVer = (Get-Item -LiteralPath $chromeExe).VersionInfo.ProductVersion
  $chromeMajor = Get-MajorVersion $chromeVer
  Write-Host "CHROME_PATH=$chromeExe"
  Write-Host "CHROME_VERSION=$chromeVer"
}
$cdMajor = Get-MajorVersion $cdVer
if ($chromeExe -and $chromeMajor -gt 0 -and $cdMajor -gt 0 -and $chromeMajor -ne $cdMajor) {
  Write-Host 'R8443_CHROME_DRIVER_VERSION_MISMATCH'
  throw "Chrome major=$chromeMajor ChromeDriver major=$cdMajor"
}

$ChromeDriverPort = Resolve-ChromeDriverPort -PreferredPort $ChromeDriverPort
Write-Host "CHROMEDRIVER_PORT=$ChromeDriverPort"

$env:PATH = "$(Split-Path -Parent $cdExe);$env:PATH"
$cdJob = Start-Process -FilePath $cdExe -ArgumentList "--port=$ChromeDriverPort" -PassThru -WindowStyle Hidden
$ourChromeDriverPid = $cdJob.Id
Write-Host "CHROMEDRIVER_PID=$ourChromeDriverPid"
Start-Sleep -Seconds 2

if (-not (Test-PortListening -Port $ChromeDriverPort)) {
  throw "ChromeDriver não abriu porta $ChromeDriverPort (PID=$ourChromeDriverPid)"
}
Write-Host 'R8443_CHROMEDRIVER_PROCESS_ISOLATION_GREEN=true'

$orchestratorFailed = $false

try {
  if (-not (Test-Path (Join-Path $ProjectRoot 'build/web/index.html'))) {
    Write-Host 'Compilando web (release) para flutter drive ...'
    $prevEapBuild = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    flutter build web --release `
      --dart-define=MP_ENVIRONMENT=qa `
      --dart-define=MP_USE_FIREBASE_EMULATORS=true 2>&1 | ForEach-Object { Write-Host $_ }
    $buildExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEapBuild
    if ($buildExit -ne 0) { throw 'flutter build web falhou' }
  }

  # Controle 1 — reportData ausente
  $run1 = [guid]::NewGuid().ToString()
  $file1 = Get-R8443ResponseFilePath -TestCaseId 'control_positive' -RunId $run1
  Remove-R8443ResponseArtifact -FilePath $file1
  $prof1 = New-R8443ChromeProfile -Label 'c1'
  $d1 = Invoke-R8443GuardedDrive `
    -Target 'integration_test/r8443_control_no_reportdata_test.dart' `
    -TestCaseId 'control_positive' `
    -RunId $run1 `
    -ResponseFile $file1 `
    -ProfilePath $prof1
  $ok1 = ($d1.Exit -ne 0)
  if ($ok1) { Write-Host 'R8443_MISSING_REPORTDATA_REJECTED=true' }
  Add-ControlRow -TestCase 'missing_reportdata' -FlutterDriveExit $d1.Exit -ExpectedFailureObserved $ok1 `
    -ReportFile $file1 -RunId $run1 -TestCaseId 'control_positive' -Pass $ok1 `
    -ValidatorExecuted $false -EvidenceSource 'flutter_drive_only'

  # Controle 2 — reportData vazio
  $run2 = [guid]::NewGuid().ToString()
  $file2 = Get-R8443ResponseFilePath -TestCaseId 'control_positive' -RunId $run2
  Remove-R8443ResponseArtifact -FilePath $file2
  $prof2 = New-R8443ChromeProfile -Label 'c2'
  $d2 = Invoke-R8443GuardedDrive `
    -Target 'integration_test/r8443_control_empty_reportdata_test.dart' `
    -TestCaseId 'control_positive' `
    -RunId $run2 `
    -ResponseFile $file2 `
    -ProfilePath $prof2
  $ok2 = ($d2.Exit -ne 0)
  if ($ok2) { Write-Host 'R8443_EMPTY_REPORTDATA_REJECTED=true' }
  Add-ControlRow -TestCase 'empty_reportdata' -FlutterDriveExit $d2.Exit -ExpectedFailureObserved $ok2 `
    -ReportFile $file2 -RunId $run2 -TestCaseId 'control_positive' -Pass $ok2 `
    -ValidatorExecuted $false -EvidenceSource 'flutter_drive_only'

  # Controle 3 — marcador ausente
  $run3 = [guid]::NewGuid().ToString()
  $file3 = Get-R8443ResponseFilePath -TestCaseId 'phase_a' -RunId $run3
  Remove-R8443ResponseArtifact -FilePath $file3
  $prof3 = New-R8443ChromeProfile -Label 'c3'
  $d3 = Invoke-R8443GuardedDrive `
    -Target 'integration_test/r8443_control_missing_marker_test.dart' `
    -TestCaseId 'phase_a' `
    -RunId $run3 `
    -ResponseFile $file3 `
    -ProfilePath $prof3
  $ok3 = ($d3.Exit -ne 0)
  if ($ok3) { Write-Host 'R8443_MISSING_REQUIRED_MARKER_REJECTED=true' }
  Add-ControlRow -TestCase 'missing_marker' -FlutterDriveExit $d3.Exit -ExpectedFailureObserved $ok3 `
    -ReportFile $file3 -RunId $run3 -TestCaseId 'phase_a' -Pass $ok3 `
    -ValidatorExecuted $false -EvidenceSource 'flutter_drive_only'

  # Controle positivo
  $runPos = [guid]::NewGuid().ToString()
  $filePos = Get-R8443ResponseFilePath -TestCaseId 'control_positive' -RunId $runPos
  Remove-R8443ResponseArtifact -FilePath $filePos
  $phaseStartPos = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $profPos = New-R8443ChromeProfile -Label 'pos'
  $dPos = Invoke-R8443GuardedDrive `
    -Target 'integration_test/r8443_control_valid_report_test.dart' `
    -TestCaseId 'control_positive' `
    -RunId $runPos `
    -ResponseFile $filePos `
    -ProfilePath $profPos
  $valPos = Test-R8443EvidenceFile -FilePath $filePos -ExpectedTestCaseId 'control_positive' -ExpectedRunId $runPos -PhaseStartMs $phaseStartPos
  $validatorExitPos = if ($valPos.Ok) { 0 } else { 1 }
  $okPos = ($dPos.Exit -eq 0) -and $valPos.Ok -and (Test-Path -LiteralPath $filePos)
  if ($okPos) { Write-Host 'R8443_VALID_REPORT_ACCEPTED=true' }
  Add-ControlRow -TestCase 'positive_valid' -FlutterDriveExit $dPos.Exit -ValidatorExit $validatorExitPos `
    -ExpectedFailureObserved $false -ReportFile $filePos -RunId $runPos -TestCaseId 'control_positive' -Pass $okPos `
    -ValidatorExecuted $true -EvidenceSource 'flutter_drive_then_validator_ps'

  # Controle 4 — artefato antigo (validador PS)
  $runStale = [guid]::NewGuid().ToString()
  $fileStale = Get-R8443ResponseFilePath -TestCaseId 'phase_a' -RunId $runStale
  $staleEnvelope = @{
    reportData = @{
      schemaVersion = '1'
      runId = $runStale
      testCaseId = 'phase_a'
      reportTimestampMs = '1000'
      PRODUCTION_REQUEST_ATTEMPTED_COUNT = '0'
      PRODUCTION_REQUEST_COMPLETED_COUNT = '0'
      SESSION_PHASE_A_AUTHENTICATED = 'true'
      SESSION_PHASE_A_HOME_READY = 'true'
    }
  }
  Set-Content -LiteralPath $fileStale -Value ($staleEnvelope | ConvertTo-Json -Depth 6) -Encoding utf8
  $phaseStartStale = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $vStale = Test-R8443EvidenceFile -FilePath $fileStale -ExpectedTestCaseId 'phase_a' -ExpectedRunId $runStale -PhaseStartMs $phaseStartStale
  $validatorExitStale = if ($vStale.Ok) { 0 } else { 1 }
  $ok4 = (-not $vStale.Ok) -and ($vStale.Code -eq 'R8443_STALE_REPORT_ARTIFACT_REJECTED')
  if ($ok4) { Write-Host 'R8443_STALE_REPORT_ARTIFACT_REJECTED=true' }
  Add-ControlRow -TestCase 'stale_artifact' -ValidatorExit $validatorExitStale -ExpectedFailureObserved $ok4 `
    -ReportFile $fileStale -RunId $runStale -TestCaseId 'phase_a' -Pass $ok4 `
    -ValidatorExecuted $true -EvidenceSource 'validator_ps_synthetic_json'

  # Controle 5 — testCaseId incorreto
  $runWrong = [guid]::NewGuid().ToString()
  $fileWrong = Get-R8443ResponseFilePath -TestCaseId 'phase_a' -RunId $runWrong
  $wrongEnvelope = @{
    reportData = @{
      schemaVersion = '1'
      runId = $runWrong
      testCaseId = 'phase_b'
      reportTimestampMs = [string]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
      PRODUCTION_REQUEST_ATTEMPTED_COUNT = '0'
      PRODUCTION_REQUEST_COMPLETED_COUNT = '0'
      SESSION_PHASE_A_AUTHENTICATED = 'true'
      SESSION_PHASE_A_HOME_READY = 'true'
    }
  }
  Set-Content -LiteralPath $fileWrong -Value ($wrongEnvelope | ConvertTo-Json -Depth 6) -Encoding utf8
  $vWrong = Test-R8443EvidenceFile -FilePath $fileWrong -ExpectedTestCaseId 'phase_a' -ExpectedRunId $runWrong
  $validatorExitWrong = if ($vWrong.Ok) { 0 } else { 1 }
  $ok5 = (-not $vWrong.Ok) -and ($vWrong.Code -eq 'R8443_WRONG_TEST_CASE_REJECTED')
  if ($ok5) { Write-Host 'R8443_WRONG_TEST_CASE_REJECTED=true' }
  Add-ControlRow -TestCase 'wrong_test_case' -ValidatorExit $validatorExitWrong -ExpectedFailureObserved $ok5 `
    -ReportFile $fileWrong -RunId $runWrong -TestCaseId 'phase_a' -Pass $ok5 `
    -ValidatorExecuted $true -EvidenceSource 'validator_ps_synthetic_json'

  # Controle 6 — texto verde sem evidência (orquestrador)
  $missingFile = Join-Path $env:TEMP "r8443-nonexistent-evidence-$([guid]::NewGuid().ToString()).json"
  $orchestratorExit = 0
  try {
    Assert-R8443SuccessTextWithEvidence `
      -DriveStdout 'All tests passed.' `
      -EvidenceFilePath $missingFile `
      -ExpectedTestCaseId 'control_positive' `
      -ExpectedRunId ([guid]::NewGuid().ToString()) `
      -PhaseStartMs 0
  } catch {
    $orchestratorExit = 1
  }
  $ok6 = ($orchestratorExit -ne 0)
  if ($ok6) { Write-Host 'R8443_SUCCESS_TEXT_WITHOUT_EVIDENCE_REJECTED=true' }
  Add-ControlRow -TestCase 'success_text_no_evidence' -ValidatorExit $orchestratorExit -ExpectedFailureObserved $ok6 -Pass $ok6 `
    -ValidatorExecuted $true -EvidenceSource 'orchestrator_ps_assert'

  Write-Host '========== TABELA DE CONTROLES =========='
  $controlRows | Format-Table -AutoSize | Out-String | Write-Host

  $failed = $controlRows | Where-Object { -not $_.PASS }
  if ($failed.Count -gt 0) {
    Write-Host 'NO_GO_R8443_ANTI_FALSE_GREEN_CONTROLS'
    exit 1
  }
  Write-Host 'GO_R8443_ANTI_FALSE_GREEN_CONTROLS'
  exit 0
}
finally {
  if ($ourChromeDriverPid) {
    Stop-ProcessTree -ParentId $ourChromeDriverPid
  }
  if (Test-Path -LiteralPath $ProfileBase) {
    Remove-Item -LiteralPath $ProfileBase -Recurse -Force -ErrorAction SilentlyContinue
  }
}
