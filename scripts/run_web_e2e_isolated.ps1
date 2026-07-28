# Execução E2E Web isolado (R8.4.33) — emulator + Playwright + seed.
# Não usa produção.

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $ProjectRoot

Write-Host '==> build probe PackageInfo'
& (Join-Path $ProjectRoot 'scripts\build_web_probe_e2e.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$e2eDir = Join-Path $ProjectRoot 'tool\e2e_web'
if (-not (Test-Path (Join-Path $e2eDir 'node_modules\playwright'))) {
  Push-Location $e2eDir
  npm install
  npx playwright install chromium
  Pop-Location
}

# Verificar emulator Firestore
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8180'
try {
  $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8180' -UseBasicParsing -TimeoutSec 2
} catch {
  Write-Error 'Firebase Emulator Firestore não detectado em 127.0.0.1:8180. Inicie (tool/e2e_web): firebase emulators:start --only firestore,auth --project masterpalm-r8433-web-e2e-local'
  exit 2
}

Push-Location $e2eDir
$env:R8433_PROBE_BUILD_DIR = Join-Path $ProjectRoot 'build\web-probe'
npm run seed
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
npm run test:packageinfo
$pi = $LASTEXITCODE
npm run test:emulator
$em = $LASTEXITCODE
Pop-Location

if ($pi -ne 0 -or $em -ne 0) { exit 1 }
Write-Host 'E2E Web isolado: OK' -ForegroundColor Green
