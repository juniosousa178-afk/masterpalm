# Build Web QA E2E — emulator only, não publicável (R8.4.33).
param(
  [string]$BuildId = "qa-e2e-local"
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $ProjectRoot

. (Join-Path $ProjectRoot 'scripts\web_version_manifest.ps1')

$bw = Join-Path $ProjectRoot 'build\web-qa-e2e'
if (Test-Path -LiteralPath $bw) { Remove-Item -LiteralPath $bw -Recurse -Force }

$defines = @(
  "--dart-define=CATALOG_BUILD_ID=$BuildId",
  '--dart-define=MP_ENVIRONMENT=qa',
  '--dart-define=MP_USE_FIREBASE_EMULATORS=true',
  '--dart-define=MP_AUTH_EMULATOR_HOST=127.0.0.1:9199',
  '--dart-define=MP_FIRESTORE_EMULATOR_HOST=127.0.0.1:8180',
  '--dart-define=MP_STORAGE_EMULATOR_HOST=127.0.0.1:9199'
)

Write-Host '==> flutter build web (QA E2E, não publicável)'
Invoke-MasterPalmFlutterBuildWeb @('build', 'web', '--release', '--pwa-strategy=none', '-o', 'build/web-qa-e2e') + $defines

$head = (git rev-parse --short HEAD).Trim()
Repair-MasterPalmWebServiceWorkerStub -ProjectRoot $ProjectRoot -BuildDir 'build\web-qa-e2e'

$vjOut = Join-Path $bw 'version.json'
Write-MasterPalmWebVersionManifest -ProjectRoot $ProjectRoot -OutPath $vjOut -BuildId $BuildId -GitCommit $head

Write-Host "QA build em $bw (NÃO usar em deploy production)"
