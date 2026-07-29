# R8.4.43 — persistência de sessão Web QA (Auth Emulator) — sem deploy.
param(
  [int]$Runs = 2,
  [int]$WebPort = 8811,
  [int]$IsolationPort = 8812,
  [int]$ChromeDriverPort = 4444,
  [string]$ExpectedHead = '8eda11a7198bb4afd6b493ff1b7577ece9d3a106'
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $ProjectRoot

$WebHost = '127.0.0.1'
$WebOrigin = "http://${WebHost}:$WebPort"
$IsolationOrigin = "http://${WebHost}:$IsolationPort"
$ProfileBase = Join-Path $env:TEMP 'masterpalm-r8443-chrome-profile'
$NegativeProfile = Join-Path $env:TEMP 'masterpalm-r8443-negative-profile'

$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8180'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9199'
$env:GCLOUD_PROJECT = 'masterpalm-r8433-web-e2e-local'

Write-Host "WEB_TEST_ORIGIN=$WebOrigin"
Write-Host "WEB_TEST_HOST=$WebHost"
Write-Host "WEB_TEST_PORT=$WebPort"
Write-Host 'WEB_AUTH_PERSISTENCE_ORIGIN_FIXED'

function Assert-Head {
  $head = (git rev-parse HEAD).Trim()
  if ($head -ne $ExpectedHead) {
    Write-Host "AVISO: HEAD local=$head esperado sprint=$ExpectedHead (continuando com HEAD atual)"
  }
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

function Stop-ProfileChrome {
  param([string]$ProfilePath)
  Get-Process chrome,chromedriver -ErrorAction SilentlyContinue | ForEach-Object {
    try {
      $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)" -ErrorAction SilentlyContinue).CommandLine
      if ($cmd -and $ProfilePath -and $cmd -like "*$ProfilePath*") {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
      }
    } catch {}
  }
}

function Reset-ProfileDir {
  param([string]$Path)
  Stop-ProfileChrome -ProfilePath $Path
  Start-Sleep -Seconds 1
  if (Test-Path -LiteralPath $Path) {
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
  }
  New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Invoke-FlutterDrive {
  param(
    [string]$Target,
    [string]$ProfilePath,
    [int]$Port = $WebPort,
    [string[]]$ExtraDefines = @()
  )
  $userDataFlag = "--user-data-dir=$($ProfilePath -replace '\\','/')"
  $defines = @(
    '--dart-define=MP_ENVIRONMENT=qa',
    '--dart-define=MP_USE_FIREBASE_EMULATORS=true',
    '--dart-define=MP_AUTH_EMULATOR_HOST=127.0.0.1:9199',
    '--dart-define=MP_FIRESTORE_EMULATOR_HOST=127.0.0.1:8180',
    '--dart-define=MP_STORAGE_EMULATOR_HOST=127.0.0.1:9199'
  ) + $ExtraDefines

  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  flutter drive `
    --driver=test_driver/integration_test.dart `
    --target=$Target `
    -d chrome `
    --release `
    --web-hostname=$WebHost `
    --web-port=$Port `
    --web-browser-flag=$userDataFlag `
    --web-browser-flag="--headless=new" `
    @defines 2>&1 | ForEach-Object { Write-Host $_ }
  $exit = $LASTEXITCODE
  $ErrorActionPreference = $prevEap
  if ($exit -ne 0) { throw "flutter drive falhou: $Target (exit=$exit)" }
}

function Start-StaticServer {
  param(
    [int]$Port,
    [string]$WebRoot = (Join-Path $ProjectRoot 'build\web')
  )
  if (-not (Test-Path (Join-Path $WebRoot 'index.html'))) {
    throw "build web ausente em $WebRoot - execute Fase A antes"
  }
  $outLog = Join-Path $env:TEMP "r8443-serve-$Port.out.log"
  $errLog = Join-Path $env:TEMP "r8443-serve-$Port.err.log"
  $proc = Start-Process -FilePath 'node' `
    -ArgumentList @(
      (Join-Path $ProjectRoot 'tool\e2e_web\lib\serve-build-cli.mjs'),
      "$Port",
      $WebRoot
    ) `
    -WorkingDirectory $ProjectRoot `
    -PassThru `
    -WindowStyle Hidden `
    -RedirectStandardOutput $outLog `
    -RedirectStandardError $errLog
  Start-Sleep -Seconds 2
  $ok = Test-NetConnection -ComputerName 127.0.0.1 -Port $Port -WarningAction SilentlyContinue
  if (-not $ok.TcpTestSucceeded) {
    if (Test-Path $outLog) { Get-Content $outLog | Write-Host }
    if (Test-Path $errLog) { Get-Content $errLog | Write-Host }
    throw "servidor estatico nao subiu na porta $Port"
  }
  return $proc
}

function Stop-StaticServer {
  param($Proc)
  if ($Proc -and -not $Proc.HasExited) {
    Stop-Process -Id $Proc.Id -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-PlaywrightPhase {
  param(
    [string]$Mode,
    [string]$ProfilePath,
    [string]$Origin = $WebOrigin,
    [string]$NegProfile = $NegativeProfile,
    [string]$IsoOrigin = $IsolationOrigin
  )
  Push-Location (Join-Path $ProjectRoot 'tool\e2e_web')
  $env:R8443_CHROME_PROFILE = $ProfilePath
  $env:R8443_WEB_ORIGIN = $Origin
  $env:R8443_NEGATIVE_PROFILE = $NegProfile
  $env:R8443_ISOLATION_ORIGIN = $IsoOrigin
  node ./ui/r8443-auth-persistence.mjs $Mode
  $exit = $LASTEXITCODE
  Pop-Location
  if ($exit -ne 0) { throw "Playwright $Mode falhou (exit=$exit)" }
}

function Stop-PortListeners {
  param([int[]]$Ports)
  foreach ($port in $Ports) {
    $conns = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    foreach ($c in $conns) {
      try { Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue } catch {}
    }
  }
  Start-Sleep -Seconds 1
}

Assert-Head

Stop-PortListeners -Ports @($WebPort, $IsolationPort)

foreach ($port in @(8180, 9199)) {
  $ok = Test-NetConnection -ComputerName 127.0.0.1 -Port $port -WarningAction SilentlyContinue
  if (-not $ok.TcpTestSucceeded) { throw "Emulator indisponível em 127.0.0.1:$port" }
}

$chromeExe = Get-ChromeExe
if ($chromeExe) {
  $pv = (Get-Item -LiteralPath $chromeExe).VersionInfo.ProductVersion
  Write-Host "Chrome ProductVersion=$pv ($chromeExe)"
}

$cdExe = Find-ChromeDriverExe -Major 150
if (-not $cdExe) {
  Write-Host 'Instalando chromedriver@150 ...'
  Push-Location (Join-Path $ProjectRoot 'tool\e2e_web')
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  npx --yes @puppeteer/browsers install chromedriver@150 2>&1 | ForEach-Object { Write-Host $_ }
  $ErrorActionPreference = $prevEap
  Pop-Location
  $cdExe = Find-ChromeDriverExe -Major 150
}
if (-not $cdExe) { throw 'chromedriver.exe não encontrado' }
$env:PATH = "$(Split-Path -Parent $cdExe);$env:PATH"
Write-Host "ChromeDriver: $(& $cdExe --version 2>&1 | Out-String)"

Get-Process chromedriver -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$cdJob = Start-Process -FilePath $cdExe -ArgumentList "--port=$ChromeDriverPort" -PassThru
Write-Host "ChromeDriver PID=$($cdJob.Id) porta=$ChromeDriverPort"
Start-Sleep -Seconds 2

$runSummaries = @()

try {
  for ($run = 1; $run -le $Runs; $run++) {
    $runProfile = "${ProfileBase}-run$run"
    $runNegProfile = "${NegativeProfile}-run$run"
    $t0 = Get-Date
    Write-Host "========== RUN $run/$Runs =========="

    Reset-ProfileDir -Path $runProfile
    Reset-ProfileDir -Path $runNegProfile

    Write-Host '==> Seed R8439 (único antes da Fase A)'
    $seedOut = node (Join-Path $ProjectRoot 'tool\e2e_web\seed\seed.mjs') 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Seed falhou: $seedOut" }
    $uid = (($seedOut | Select-Object -Last 1).ToString() | ConvertFrom-Json).uid
    Write-Host "Seed uid=$uid"

    Write-Host '==> Fase A'
    Invoke-FlutterDrive `
      -Target 'integration_test/r8443_web_auth_persistence_phase_a_test.dart' `
      -ProfilePath $runProfile `
      -ExtraDefines @("--dart-define=R8442_EXPECTED_UID=$uid")

    Stop-ProfileChrome -ProfilePath $runProfile
    Start-Sleep -Seconds 2

    Write-Host '==> Fase B'
    Invoke-FlutterDrive `
      -Target 'integration_test/r8443_web_auth_persistence_phase_b_test.dart' `
      -ProfilePath $runProfile `
      -ExtraDefines @("--dart-define=R8442_EXPECTED_UID=$uid")

    Stop-ProfileChrome -ProfilePath $runProfile
    Start-Sleep -Seconds 2

    Write-Host '==> Fase C (reload real via integration_test + window.location.reload)'
    Invoke-FlutterDrive `
      -Target 'integration_test/r8443_web_auth_persistence_phase_c_test.dart' `
      -ProfilePath $runProfile `
      -ExtraDefines @("--dart-define=R8442_EXPECTED_UID=$uid")

    Stop-ProfileChrome -ProfilePath $runProfile
    Start-Sleep -Seconds 2

    Write-Host '==> Perfil limpo (integration_test)'
    Invoke-FlutterDrive `
      -Target 'integration_test/r8443_web_auth_persistence_negative_clean_test.dart' `
      -ProfilePath $runNegProfile `
      -ExtraDefines @("--dart-define=R8442_EXPECTED_UID=$uid")

    Stop-ProfileChrome -ProfilePath $runNegProfile
    Start-Sleep -Seconds 2

    Write-Host '==> Origin isolation (porta $IsolationPort, perfil limpo)'
    Invoke-FlutterDrive `
      -Target 'integration_test/r8443_web_auth_persistence_negative_origin_test.dart' `
      -ProfilePath $runNegProfile `
      -Port $IsolationPort `
      -ExtraDefines @(
        "--dart-define=R8442_EXPECTED_UID=$uid",
        "--dart-define=R8443_ISOLATION_PORT=$IsolationPort"
      )

    Write-Host '==> Fail-closed (sessão persistida + Firestore indisponível)'
    Invoke-FlutterDrive `
      -Target 'integration_test/r8443_web_auth_persistence_fail_closed_test.dart' `
      -ProfilePath $runProfile `
      -ExtraDefines @(
        "--dart-define=R8442_EXPECTED_UID=$uid",
        '--dart-define=MP_FIRESTORE_EMULATOR_HOST=127.0.0.1:1',
        '--dart-define=R8443_FAIL_CLOSED_MODE=persisted-firestore'
      )

    $dur = [int]((Get-Date) - $t0).TotalSeconds
    $runSummaries += [pscustomobject]@{
      Run = $run
      PhaseA = 'pass'
      PhaseB = 'pass'
      PhaseC = 'pass'
      NegativeProfile = 'pass'
      OriginIsolation = 'pass'
      FailClosed = 'pass'
      DurationSec = $dur
    }
    Write-Host "RUN $run GREEN ($dur sec)"
  }

  Write-Host 'WEB_AUTH_PERSISTENCE_SUITE_2_OF_2_GREEN'
  $runSummaries | Format-Table | Out-String | Write-Host
}
finally {
  if ($cdJob -and -not $cdJob.HasExited) {
    Stop-Process -Id $cdJob.Id -Force -ErrorAction SilentlyContinue
  }
  Get-Job -ErrorAction SilentlyContinue | Remove-Job -Force -ErrorAction SilentlyContinue
}
