# Build Web MasterPalm — release reproduzível (R8.4.33).
# Uso:
#   .\scripts\build_web_release.ps1 -BuildId stable-r8433-f459bcd
#
# Não faz deploy.

param(
  [Parameter(Mandatory = $true)]
  [string]$BuildId,
  [switch]$AllowDirtyTree
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $ProjectRoot

. (Join-Path $ProjectRoot 'scripts\web_version_manifest.ps1')

if (-not $AllowDirtyTree) {
  $status = git status --porcelain 2>$null
  if ($status) {
    throw "Working tree suja. Commit ou use -AllowDirtyTree apenas em dev local."
  }
}

$head = (git rev-parse --short HEAD).Trim()
Write-Host "==> HEAD=$head" -ForegroundColor Cyan
Write-Host "==> BuildId=$BuildId" -ForegroundColor Cyan

Write-Host '==> preflight stock client build'
dart run scripts/preflight_stock_client_build_version.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$bw = Join-Path $ProjectRoot 'build\web'
if (Test-Path -LiteralPath $bw) {
  Remove-Item -LiteralPath $bw -Recurse -Force
}

$defines = @(
  "--dart-define=CATALOG_BUILD_ID=$BuildId",
  '--dart-define=MP_ENVIRONMENT=production',
  '--dart-define=MP_USE_FIREBASE_EMULATORS=false'
)

Write-Host '==> flutter build web --release --pwa-strategy=none (sem source maps)'
Invoke-MasterPalmFlutterBuildWeb @('build', 'web', '--release', '--pwa-strategy=none') + $defines

# Manifests / SW / version.json
$assets = Join-Path $bw 'assets'
if (-not (Test-Path -LiteralPath $assets)) { throw "Pasta em falta: $assets" }
$amJson = Join-Path $assets 'AssetManifest.json'
if (-not (Test-Path -LiteralPath $amJson)) {
  Set-Content -LiteralPath $amJson -Value '{}' -Encoding utf8
}
$amBin = Join-Path $assets 'AssetManifest.bin.json'
if (-not (Test-Path -LiteralPath $amBin)) {
  Copy-Item -LiteralPath $amJson -Destination $amBin -Force
}
$fontM = Join-Path $assets 'FontManifest.json'
if (-not (Test-Path -LiteralPath $fontM)) {
  Set-Content -LiteralPath $fontM -Value "[]`n" -Encoding utf8
}
$rootManifest = Join-Path $bw 'manifest.json'
$webManifest = Join-Path $ProjectRoot 'web\manifest.json'
if (-not (Test-Path -LiteralPath $rootManifest) -and (Test-Path -LiteralPath $webManifest)) {
  Copy-Item -LiteralPath $webManifest -Destination $rootManifest -Force
}

Repair-MasterPalmWebServiceWorkerStub -ProjectRoot $ProjectRoot

$vjOut = Join-Path $bw 'version.json'
Write-MasterPalmWebVersionManifest -ProjectRoot $ProjectRoot -OutPath $vjOut -BuildId $BuildId -GitCommit $head
Test-MasterPalmWebVersionManifest -LiteralPath $vjOut -ExpectedBuildId $BuildId -ExpectedGitCommit $head

Test-MasterPalmProductionWebArtifact -BuildWebDir $bw

$shaJs = Get-MasterPalmFileSha256 -LiteralPath (Join-Path $bw 'main.dart.js')
$shaVj = Get-MasterPalmFileSha256 -LiteralPath $vjOut
$shaSw = Get-MasterPalmFileSha256 -LiteralPath (Join-Path $bw 'flutter_service_worker.js')
Write-Host "SHA-256 main.dart.js=$shaJs"
Write-Host "SHA-256 version.json=$shaVj"
Write-Host "SHA-256 flutter_service_worker.js=$shaSw"

& (Join-Path $ProjectRoot 'scripts\pre_deploy_web_check.ps1') -ValidateOnly -BuildId $BuildId -ExpectProduction
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ''
Write-Host 'Build OK. Próximo passo: firebase deploy --only hosting:masterpalm-58c46' -ForegroundColor Green
