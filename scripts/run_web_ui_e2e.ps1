# Execução Web UI E2E isolado (R8.4.38) — Playwright + Emulator + seed.
# Não usa produção. Não faz deploy.

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $ProjectRoot

$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8180'
$env:FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9199'
$env:GCLOUD_PROJECT = 'masterpalm-r8433-web-e2e-local'

Write-Host '==> build QA Web (emulator only)'
& (Join-Path $ProjectRoot 'scripts\build_web_qa_e2e.ps1') -BuildId 'r8438-ui-e2e'
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$e2eDir = Join-Path $ProjectRoot 'tool\e2e_web'
if (-not (Test-Path (Join-Path $e2eDir 'node_modules\playwright'))) {
  Push-Location $e2eDir
  npm install
  npx playwright install chromium
  Pop-Location
}

# Verificar emulators (fail-closed)
try {
  Invoke-WebRequest -Uri 'http://127.0.0.1:8180' -UseBasicParsing -TimeoutSec 3 | Out-Null
  Invoke-WebRequest -Uri 'http://127.0.0.1:9199' -UseBasicParsing -TimeoutSec 3 | Out-Null
} catch {
  Write-Error 'Emulators indisponíveis. Inicie: Push-Location tool/e2e_web; firebase emulators:start --only firestore,auth --project masterpalm-r8433-web-e2e-local'
  exit 2
}

Push-Location $e2eDir
npm run seed
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
$env:R8438_UI_BUILD_DIR = Join-Path $ProjectRoot 'build\web-qa-e2e'
npm run test:ui
$ui = $LASTEXITCODE
Pop-Location
exit $ui
