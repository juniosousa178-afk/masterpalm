# R8.4.42 — integration_test login Web QA + Auth Emulator (sem deploy).
param(
  [int]$Runs = 3,
  [int]$ChromeDriverPort = 4444,
  [switch]$SkipSeed,
  [switch]$SkipFailClosed,
  [switch]$SkipPlaywrightCompare
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $ProjectRoot

$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8180'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9199'
$env:GCLOUD_PROJECT = 'masterpalm-r8433-web-e2e-local'

Write-Host '==> Chrome / ChromeDriver'
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
$chromeExe = Get-ChromeExe
if ($chromeExe) {
  try {
    $chromeVer = (& $chromeExe --version 2>&1 | Out-String).Trim()
    if ($chromeVer) { Write-Host "Chrome: $chromeVer" }
  } catch {}
  if (-not $chromeVer) { Write-Host "Chrome: $chromeExe" }
} else {
  Write-Host 'Chrome: (flutter -d chrome resolverá o binário)'
}

$chromeMajor = 150
if ($chromeExe) {
  $pv = (Get-Item -LiteralPath $chromeExe).VersionInfo.ProductVersion
  if ($pv -match '^(\d+)\.') { $chromeMajor = [int]$Matches[1] }
  Write-Host "Chrome major=$chromeMajor (ProductVersion=$pv)"
}

function Find-ChromeDriverExe {
  param([int]$Major)
  foreach ($root in @(
      (Join-Path $ProjectRoot 'tool\e2e_web\chromedriver'),
      (Join-Path $env:USERPROFILE '.cache\puppeteer\chromedriver')
    )) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    $candidates = Get-ChildItem -Path $root -Recurse -Filter 'chromedriver.exe' -ErrorAction SilentlyContinue
    $match = $candidates | Where-Object { $_.FullName -match "win64-$Major" } | Select-Object -First 1
    if ($match) { return $match.FullName }
    if (-not $match -and $candidates) { return $candidates[0].FullName }
  }
  return $null
}

$cdExe = Find-ChromeDriverExe -Major $chromeMajor
$cdMajor = 0
if ($cdExe) {
  $cdVerLine = (& $cdExe --version 2>&1 | Out-String).Trim()
  if ($cdVerLine -match 'ChromeDriver\s+(\d+)\.') { $cdMajor = [int]$Matches[1] }
}
if (-not $cdExe -or $cdMajor -ne $chromeMajor) {
  Write-Host "Instalando chromedriver@$chromeMajor ..."
  Push-Location (Join-Path $ProjectRoot 'tool\e2e_web')
  npx --yes @puppeteer/browsers install "chromedriver@$chromeMajor" | Out-Host
  Pop-Location
  $cdExe = Find-ChromeDriverExe -Major $chromeMajor
}
if (-not $cdExe) { throw 'chromedriver.exe não encontrado após instalação' }
$env:PATH = "$(Split-Path -Parent $cdExe);$env:PATH"
$cdVer = (& $cdExe --version 2>&1 | Out-String).Trim()
Write-Host "ChromeDriver: $cdVer ($cdExe)"

$cdProc = Get-Process chromedriver -ErrorAction SilentlyContinue | Where-Object { $_.Path }
if ($cdProc) {
  Write-Host "Encerrando chromedriver existente PID=$($cdProc.Id)"
  $cdProc | Stop-Process -Force
}
$cdLog = Join-Path $env:TEMP "r8442-chromedriver-$ChromeDriverPort.log"
$cdJob = Start-Process -FilePath $cdExe -ArgumentList "--port=$ChromeDriverPort" -PassThru
Write-Host "ChromeDriver PID=$($cdJob.Id) porta=$ChromeDriverPort"
Start-Sleep -Seconds 2

function Stop-ChromeDriverStarted {
  if ($cdJob -and -not $cdJob.HasExited) {
    Stop-Process -Id $cdJob.Id -Force -ErrorAction SilentlyContinue
  }
}

try {
  foreach ($port in @(8180, 9199)) {
    $ok = Test-NetConnection -ComputerName 127.0.0.1 -Port $port -WarningAction SilentlyContinue
    if (-not $ok.TcpTestSucceeded) {
      throw "Emulator indisponível em 127.0.0.1:$port"
    }
  }

  if (-not $SkipSeed) {
    Write-Host '==> Seed R8439'
    $seedOut = node (Join-Path $ProjectRoot 'tool\e2e_web\seed\seed.mjs') 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Seed falhou: $seedOut" }
    $seedJson = ($seedOut | Select-Object -Last 1).ToString()
    $uid = ($seedJson | ConvertFrom-Json).uid
    Write-Host "Seed uid=$uid"
    $env:R8442_EXPECTED_UID = $uid
  }

  $defines = @(
    '--dart-define=MP_ENVIRONMENT=qa',
    '--dart-define=MP_USE_FIREBASE_EMULATORS=true',
    '--dart-define=MP_AUTH_EMULATOR_HOST=127.0.0.1:9199',
    '--dart-define=MP_FIRESTORE_EMULATOR_HOST=127.0.0.1:8180',
    '--dart-define=MP_STORAGE_EMULATOR_HOST=127.0.0.1:9199'
  )
  if ($env:R8442_EXPECTED_UID) {
    $defines += "--dart-define=R8442_EXPECTED_UID=$($env:R8442_EXPECTED_UID)"
  }

  $passed = 0
  for ($i = 1; $i -le $Runs; $i++) {
    Write-Host "==> integration_test run $i/$Runs"
    if (-not $SkipSeed) {
      Write-Host '==> Seed R8439 (reset antes do run)'
      $seedOut = node (Join-Path $ProjectRoot 'tool\e2e_web\seed\seed.mjs') 2>&1
      if ($LASTEXITCODE -ne 0) { throw "Seed falhou: $seedOut" }
      $seedJson = ($seedOut | Select-Object -Last 1).ToString()
      $uid = ($seedJson | ConvertFrom-Json).uid
      $env:R8442_EXPECTED_UID = $uid
      $defines = @(
        '--dart-define=MP_ENVIRONMENT=qa',
        '--dart-define=MP_USE_FIREBASE_EMULATORS=true',
        '--dart-define=MP_AUTH_EMULATOR_HOST=127.0.0.1:9199',
        '--dart-define=MP_FIRESTORE_EMULATOR_HOST=127.0.0.1:8180',
        '--dart-define=MP_STORAGE_EMULATOR_HOST=127.0.0.1:9199',
        "--dart-define=R8442_EXPECTED_UID=$uid"
      )
    }
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    flutter drive `
      --driver=test_driver/integration_test.dart `
      --target=integration_test/r8442_web_login_emulator_test.dart `
      -d chrome `
      --release `
      --web-browser-flag="--headless=new" `
      @defines 2>&1 | ForEach-Object { Write-Host $_ }
    $driveExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    if ($driveExit -ne 0) { break }
    $passed++
  }

  if (-not $SkipFailClosed) {
    Write-Host '==> fail-closed auth'
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    flutter drive `
      --driver=test_driver/integration_test.dart `
      --target=integration_test/r8442_web_emulator_fail_closed_test.dart `
      -d chrome `
      --release `
      --web-browser-flag="--headless=new" `
      @defines `
      --dart-define=MP_AUTH_EMULATOR_HOST=127.0.0.1:1 `
      --dart-define=R8442_FAIL_CLOSED_MODE=auth 2>&1 | ForEach-Object { Write-Host $_ }
    $driveExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    if ($driveExit -ne 0) { throw 'fail-closed auth falhou' }

    Write-Host '==> fail-closed firestore'
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    flutter drive `
      --driver=test_driver/integration_test.dart `
      --target=integration_test/r8442_web_emulator_fail_closed_test.dart `
      -d chrome `
      --release `
      --web-browser-flag="--headless=new" `
      @defines `
      --dart-define=MP_FIRESTORE_EMULATOR_HOST=127.0.0.1:1 `
      --dart-define=R8442_FAIL_CLOSED_MODE=firestore 2>&1 | ForEach-Object { Write-Host $_ }
    $driveExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    if ($driveExit -ne 0) { throw 'fail-closed firestore falhou' }
  }

  if ($passed -eq $Runs) {
    Write-Host "FLUTTER_WEB_INTEGRATION_LOGIN_${Runs}_OF_${Runs}_GREEN"
  } else {
    Write-Host "NO_GO: $passed/$Runs runs"
    exit 1
  }
}
finally {
  Stop-ChromeDriverStarted
}
