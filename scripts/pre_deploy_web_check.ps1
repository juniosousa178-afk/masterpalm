# Pré-deploy Web MasterPalm — validação de artefactos (R8.4.33).
#
#   .\scripts\pre_deploy_web_check.ps1 -ValidateOnly -BuildId stable-r8433-...
#   .\scripts\pre_deploy_web_check.ps1 -ValidateOnly -BuildId ... -ExpectProduction

param(
  [string]$BuildId,
  [switch]$ValidateOnly,
  [switch]$SkipAnalyze,
  [switch]$SkipTest,
  [switch]$ExpectProduction,
  [switch]$AllowSourceMaps
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $ProjectRoot

. (Join-Path $ProjectRoot 'scripts\web_version_manifest.ps1')

if (-not $BuildId -or $BuildId.Trim() -eq '') {
  $BuildId = $env:CATALOG_BUILD_ID
}
if (-not $BuildId -or $BuildId.Trim() -eq '') {
  $vjGuess = Join-Path $ProjectRoot 'build\web\version.json'
  if ($ValidateOnly -and (Test-Path -LiteralPath $vjGuess)) {
    try {
      $BuildId = ([string]((Get-Content -LiteralPath $vjGuess -Raw | ConvertFrom-Json).buildId)).Trim()
    } catch { }
  }
}
if (-not $BuildId -or $BuildId.Trim() -eq '') {
  throw 'BuildId obrigatório (-BuildId ou CATALOG_BUILD_ID)'
}

$head = (git rev-parse --short HEAD).Trim()

if (-not $ValidateOnly) {
  if (-not $SkipAnalyze) {
    flutter analyze
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  }
  if (-not $SkipTest) {
    flutter test test/catalog_initial_web_route_test.dart
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  }
  throw 'Use build_web_release.ps1 para build; este script valida artefactos existentes.'
}

Write-Host '==> ValidateOnly' -ForegroundColor Cyan

Repair-MasterPalmWebServiceWorkerStub -ProjectRoot $ProjectRoot

$bw = Join-Path $ProjectRoot 'build\web'
$fb = Join-Path $bw 'flutter_bootstrap.js'
$vj = Join-Path $bw 'version.json'
$js = Join-Path $bw 'main.dart.js'
$map = Join-Path $bw 'main.dart.js.map'
$fsw = Join-Path $bw 'flutter_service_worker.js'

foreach ($p in @($fb, $js, $fsw, $vj)) {
  if (-not (Test-Path -LiteralPath $p)) { throw "Ficheiro crítico em falta: $p" }
  if ((Get-Item -LiteralPath $p).Length -lt 1) { throw "Ficheiro vazio: $p" }
}

if ((Get-Item -LiteralPath $js).Length -lt 1000) {
  throw 'main.dart.js suspeito (muito pequeno)'
}

if ((Get-Item -LiteralPath $fsw).Length -lt 100) {
  throw 'WEB_SERVICE_WORKER_STUB_REPRODUCIBLE: flutter_service_worker.js inválido'
}

if ((Test-Path -LiteralPath $map) -and -not $AllowSourceMaps) {
  throw 'main.dart.js.map presente — build production não deve publicar source maps'
}

Test-MasterPalmWebVersionManifest -LiteralPath $vj -ExpectedBuildId $BuildId -ExpectedGitCommit $head

if ($ExpectProduction) {
  Test-MasterPalmProductionWebArtifact -BuildWebDir $bw
}

# Scan artefacto por strings bloqueadas
$allText = Get-ChildItem -LiteralPath $bw -Recurse -File -Include *.js,*.json,*.html |
  ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding utf8 -ErrorAction SilentlyContinue }
$blob = $allText -join "`n"
$forbidden = @(
  'masterpalm-planos-e2e-local',
  'C:\\Users\\',
  'AppData\\Local\\Temp',
  'BEGIN PRIVATE KEY',
  'service_account'
)
foreach ($f in $forbidden) {
  if ($blob.Contains($f)) {
    throw "Artefato contém padrão proibido: $f"
  }
}
if ($ExpectProduction -and $blob -match 'MP_ENVIRONMENT=qa') {
  throw 'MP_ENVIRONMENT=qa no artefato production'
}

Write-Host "OK version.json + SW + main.dart.js (HEAD=$head, buildId=$BuildId)"
Write-Host "SHA-256 main.dart.js=$(Get-MasterPalmFileSha256 -LiteralPath $js)"

Write-Host ''
Write-Host 'Proximo passo manual: firebase deploy --only hosting:masterpalm-58c46'
