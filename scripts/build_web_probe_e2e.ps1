# Build probe Web para Playwright PackageInfo (R8.4.33).
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $ProjectRoot
. (Join-Path $ProjectRoot 'scripts\web_version_manifest.ps1')

$out = Join-Path $ProjectRoot 'build\web-probe'
if (Test-Path $out) { Remove-Item -Recurse -Force $out }

Invoke-MasterPalmFlutterBuildWeb @(
  'build', 'web', '--release', '--pwa-strategy=none', '-o', 'build/web-probe',
  '-t', 'tool/e2e_web/web_runtime_probe.dart',
  '--dart-define=MP_ENVIRONMENT=production',
  '--dart-define=MP_USE_FIREBASE_EMULATORS=false'
)

$head = (git rev-parse --short HEAD).Trim()
Repair-MasterPalmWebServiceWorkerStub -ProjectRoot $ProjectRoot -BuildDir 'build\web-probe'
Copy-Item -Force (Join-Path $ProjectRoot 'web\flutter_service_worker.js') (Join-Path $out 'flutter_service_worker.js')
Write-MasterPalmWebVersionManifest -ProjectRoot $ProjectRoot -OutPath (Join-Path $out 'version.json') -BuildId 'r8433-probe' -GitCommit $head
