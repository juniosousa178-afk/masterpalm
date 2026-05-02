# Pré-deploy Web MasterPalm — analyze/test/build opcionais + validação de artefactos.
#
# Build recomendado (sem Service Worker):
#   flutter build web --release --source-maps --pwa-strategy=none `
#     --dart-define=CATALOG_BUILD_ID=<BUILD_ID>
#
# Ou: .\scripts\build_web_release.ps1
#
# Só validar pasta build\web existente:
#   .\scripts\pre_deploy_web_check.ps1 -ValidateOnly
#
# Uso: .\scripts\pre_deploy_web_check.ps1
# Opcional: $env:CATALOG_BUILD_ID = "stable-20260503-..."

param(
  [string]$BuildId,
  [switch]$ValidateOnly,
  [switch]$SkipAnalyze,
  [switch]$SkipTest
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $ProjectRoot

if (-not $BuildId -or $BuildId.Trim() -eq "") {
  $BuildId = $env:CATALOG_BUILD_ID
}
if (-not $BuildId -or $BuildId.Trim() -eq "") {
  $vjGuess = Join-Path $ProjectRoot "build\web\version.json"
  if ($ValidateOnly -and (Test-Path -LiteralPath $vjGuess)) {
    try {
      $BuildId = ([string]((Get-Content -LiteralPath $vjGuess -Raw | ConvertFrom-Json).buildId)).Trim()
    } catch { }
  }
}
if (-not $BuildId -or $BuildId.Trim() -eq "") {
  $short = "unknown"
  try { $short = (git rev-parse --short HEAD 2>$null).Trim() } catch { }
  $BuildId = "local-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$short"
}

function Write-MasterPalmVersionJson {
  param(
    [string]$OutPath,
    [string]$Id
  )
  $gitShort = "unknown"
  try {
    $gitShort = (git rev-parse --short HEAD 2>$null).Trim()
  } catch { }
  $o = [ordered]@{
    buildId         = $Id
    hostingTarget   = "masterpalm-58c46"
    siteId          = "masterpalm-58c46"
    expectedDomain  = "app.mastepalm.com.br"
    gitCommit       = $gitShort
  }
  ($o | ConvertTo-Json -Compress) + "`n" | Set-Content -LiteralPath $OutPath -Encoding utf8
}

function Test-FileNotHtmlDocument {
  param([string]$LiteralPath)
  $bytes = [System.IO.File]::ReadAllBytes($LiteralPath)
  if ($bytes.Length -lt 9) { return $true }
  $prefix = [System.Text.Encoding]::ASCII.GetString($bytes[0..8])
  return ($prefix -ne '<!DOCTYPE')
}

function Test-JsonFile {
  param([string]$LiteralPath)
  $raw = Get-Content -LiteralPath $LiteralPath -Raw -Encoding utf8
  $null = $raw | ConvertFrom-Json
}

if (-not $ValidateOnly) {
  if (-not $SkipAnalyze) {
    Write-Host "==> flutter analyze"
    flutter analyze
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  }

  if (-not $SkipTest) {
    Write-Host "==> flutter test (rotas catálogo web)"
    flutter test test/catalog_initial_web_route_test.dart
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  }

  Write-Host "==> flutter build web --release --source-maps --pwa-strategy=none"
  flutter build web --release --source-maps --pwa-strategy=none "--dart-define=CATALOG_BUILD_ID=$BuildId"
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  # Com --pwa-strategy=none o tooling pode omitir este ficheiro; o stub em web/ evita 404/SPA no URL do SW.
  $fswSrc = Join-Path $ProjectRoot "web\flutter_service_worker.js"
  $fswOut = Join-Path $ProjectRoot "build\web\flutter_service_worker.js"
  if (Test-Path -LiteralPath $fswSrc) {
    Copy-Item -LiteralPath $fswSrc -Destination $fswOut -Force
    Write-Host "==> flutter_service_worker.js: copiado web/ -> build/web (stub)"
  }

  $vjOut = Join-Path $ProjectRoot "build\web\version.json"
  Write-Host "==> gravar build/web/version.json (buildId + gitCommit)"
  Write-MasterPalmVersionJson -OutPath $vjOut -Id $BuildId
}
else {
  Write-Host "==> ValidateOnly (sem build)" -ForegroundColor Cyan
}

$fb = Join-Path $ProjectRoot "build\web\flutter_bootstrap.js"
$vj = Join-Path $ProjectRoot "build\web\version.json"
$js = Join-Path $ProjectRoot "build\web\main.dart.js"
$map = Join-Path $ProjectRoot "build\web\main.dart.js.map"
$fsw = Join-Path $ProjectRoot "build\web\flutter_service_worker.js"
$amJson = Join-Path $ProjectRoot "build\web\assets\AssetManifest.json"
$amBin = Join-Path $ProjectRoot "build\web\assets\AssetManifest.bin.json"

foreach ($p in @($fb, $vj, $js, $fsw)) {
  if (-not (Test-Path -LiteralPath $p)) {
    Write-Error "Ficheiro em falta: $p"
    exit 1
  }
  Write-Host "OK existe: $p"
}

if (-not (Test-Path -LiteralPath $map)) {
  Write-Warning "main.dart.js.map em falta (opcional com --source-maps): $map"
}
else {
  Write-Host "OK existe: $map"
}

foreach ($p in @($fb, $js, $fsw)) {
  if (-not (Test-FileNotHtmlDocument -LiteralPath $p)) {
    Write-Error "Conteúdo inválido (parece HTML, não JS): $p"
    exit 1
  }
}

try {
  Test-JsonFile -LiteralPath $vj
}
catch {
  Write-Error "version.json não é JSON válido: $vj"
  exit 1
}

$rawVj = Get-Content -LiteralPath $vj -Raw -Encoding utf8
if ($rawVj -notmatch [regex]::Escape($BuildId)) {
  Write-Warning "version.json não contém buildId esperado '$BuildId' — ajustar CATALOG_BUILD_ID ou voltar a correr build."
}
else {
  Write-Host "OK: version.json contém buildId $BuildId"
}

if (-not (Test-FileNotHtmlDocument -LiteralPath $vj)) {
  Write-Error "version.json parece HTML (rewrite SPA?) — $vj"
  exit 1
}

$hasAmJson = Test-Path -LiteralPath $amJson
$hasAmBin = Test-Path -LiteralPath $amBin
if (-not $hasAmJson -and -not $hasAmBin) {
  Write-Error "Nem AssetManifest.json nem AssetManifest.bin.json em build/web/assets/"
  exit 1
}
if ($hasAmJson) {
  if (-not (Test-FileNotHtmlDocument -LiteralPath $amJson)) {
    Write-Error "AssetManifest.json parece HTML: $amJson"
    exit 1
  }
  try { Test-JsonFile -LiteralPath $amJson } catch {
    Write-Error "AssetManifest.json não é JSON válido: $amJson"
    exit 1
  }
  Write-Host "OK: assets/AssetManifest.json"
}
if ($hasAmBin) {
  if (-not (Test-FileNotHtmlDocument -LiteralPath $amBin)) {
    Write-Error "AssetManifest.bin.json parece HTML: $amBin"
    exit 1
  }
  try { Test-JsonFile -LiteralPath $amBin } catch {
    Write-Error "AssetManifest.bin.json não é JSON válido: $amBin"
    exit 1
  }
  Write-Host "OK: assets/AssetManifest.bin.json"
}

$fbSrc = Join-Path $ProjectRoot "web\flutter_bootstrap.js"
if (Test-Path -LiteralPath $fbSrc) {
  $fbSrcRaw = Get-Content -LiteralPath $fbSrc -Raw -Encoding utf8
  if ($fbSrcRaw -match "serviceWorkerSettings") {
    Write-Warning "web/flutter_bootstrap.js contem serviceWorkerSettings - nao deve registar SW."
  }
}

Write-Host ""
Write-Host "Proximo passo manual: firebase deploy --only hosting:masterpalm-58c46"
Write-Host "Pos-deploy: validar URLs (checklist pos-deploy no relatorio WEB-CACHE)."
