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
# (Aplica reparacao de manifests/SW em falta, depois valida JSON/HTML.)
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
  $fs = [System.IO.File]::OpenRead($LiteralPath)
  try {
    $buf = New-Object byte[] 512
    $n = $fs.Read($buf, 0, 512)
    if ($n -lt 2) { return $true }
    $text = [System.Text.Encoding]::UTF8.GetString($buf, 0, $n)
    $t = $text.TrimStart([char]0xFEFF).TrimStart()
    if ($t.Length -lt 2) { return $true }
    $low = $t.ToLowerInvariant()
    if ($low.StartsWith('<!doctype')) { return $false }
    if ($low.StartsWith('<html')) { return $false }
    return $true
  }
  finally { $fs.Dispose() }
}

function Test-JsonFile {
  param([string]$LiteralPath)
  $raw = Get-Content -LiteralPath $LiteralPath -Raw -Encoding utf8
  $null = $raw | ConvertFrom-Json
}

function Repair-MasterPalmWebBuildArtifacts {
  param([string]$ProjectRoot)
  $bw = Join-Path $ProjectRoot "build\web"
  $assets = Join-Path $bw "assets"
  if (-not (Test-Path -LiteralPath $assets)) {
    throw "Pasta em falta após build: $assets"
  }

  $amJson = Join-Path $assets "AssetManifest.json"
  if (-not (Test-Path -LiteralPath $amJson)) {
    Write-Warning 'AssetManifest.json ausente: criando JSON vazio {} (evita index.html do SPA neste URL).'
    Set-Content -LiteralPath $amJson -Value '{}' -Encoding utf8
  }

  $amBin = Join-Path $assets "AssetManifest.bin.json"
  if (-not (Test-Path -LiteralPath $amBin)) {
    Copy-Item -LiteralPath $amJson -Destination $amBin -Force
    Write-Host "==> AssetManifest.bin.json criado a partir de AssetManifest.json" -ForegroundColor Cyan
  }

  $fontM = Join-Path $assets "FontManifest.json"
  if (-not (Test-Path -LiteralPath $fontM)) {
    Set-Content -LiteralPath $fontM -Value "[]`n" -Encoding utf8
    Write-Host '==> FontManifest.json criado (JSON [])' -ForegroundColor Cyan
  }

  $rootManifest = Join-Path $bw "manifest.json"
  $webManifest = Join-Path $ProjectRoot "web\manifest.json"
  if (-not (Test-Path -LiteralPath $rootManifest)) {
    if (Test-Path -LiteralPath $webManifest) {
      Copy-Item -LiteralPath $webManifest -Destination $rootManifest -Force
      Write-Host "==> manifest.json: copiado web/ -> build/web" -ForegroundColor Cyan
    }
    else {
      $minimal = [ordered]@{
        name       = "MasterPalm"
        short_name = "MasterPalm"
        start_url  = "."
        display    = "standalone"
      }
      (($minimal | ConvertTo-Json -Compress) + "`n") | Set-Content -LiteralPath $rootManifest -Encoding utf8
      Write-Host '==> manifest.json minimo MasterPalm criado' -ForegroundColor Cyan
    }
  }

  $fswSrc = Join-Path $ProjectRoot "web\flutter_service_worker.js"
  $fswOut = Join-Path $bw "flutter_service_worker.js"
  if (-not (Test-Path -LiteralPath $fswSrc)) {
    throw "web/flutter_service_worker.js em falta (stub obrigatório com --pwa-strategy=none)"
  }
  Copy-Item -LiteralPath $fswSrc -Destination $fswOut -Force
  Write-Host "==> flutter_service_worker.js: stub web/ -> build/web" -ForegroundColor Cyan
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

  $vjOut = Join-Path $ProjectRoot "build\web\version.json"
  Write-Host "==> gravar build/web/version.json (buildId + gitCommit)"
  Write-MasterPalmVersionJson -OutPath $vjOut -Id $BuildId
}
else {
  Write-Host "==> ValidateOnly (sem build)" -ForegroundColor Cyan
}

Write-Host '==> Artefactos web (reparacao se necessario)' -ForegroundColor Cyan
try {
  Repair-MasterPalmWebBuildArtifacts -ProjectRoot $ProjectRoot
}
catch {
  Write-Error $_
  exit 1
}

$fb = Join-Path $ProjectRoot "build\web\flutter_bootstrap.js"
$vj = Join-Path $ProjectRoot "build\web\version.json"
$js = Join-Path $ProjectRoot "build\web\main.dart.js"
$map = Join-Path $ProjectRoot "build\web\main.dart.js.map"
$fsw = Join-Path $ProjectRoot "build\web\flutter_service_worker.js"
$amJson = Join-Path $ProjectRoot "build\web\assets\AssetManifest.json"
$amBin = Join-Path $ProjectRoot "build\web\assets\AssetManifest.bin.json"
$fontM = Join-Path $ProjectRoot "build\web\assets\FontManifest.json"
$rootManifest = Join-Path $ProjectRoot "build\web\manifest.json"

$criticalJs = @($fb, $js, $fsw)
$criticalJson = @($vj, $amJson, $amBin, $fontM, $rootManifest)

foreach ($p in ($criticalJs + $criticalJson)) {
  if (-not (Test-Path -LiteralPath $p)) {
    Write-Error "Ficheiro critico em falta: $p"
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

foreach ($p in $criticalJs) {
  if (-not (Test-FileNotHtmlDocument -LiteralPath $p)) {
    Write-Error "Conteudo invalido (parece HTML, nao JS): $p"
    exit 1
  }
  Write-Host "OK nao-HTML (JS): $p"
}

foreach ($p in $criticalJson) {
  if (-not (Test-FileNotHtmlDocument -LiteralPath $p)) {
    Write-Error "Conteudo invalido (parece HTML / SPA fallback): $p"
    exit 1
  }
  try {
    Test-JsonFile -LiteralPath $p
  }
  catch {
    Write-Error "JSON invalido: $p - $($_.Exception.Message)"
    exit 1
  }
  Write-Host "OK JSON + nao-HTML: $p"
}

$rawVj = Get-Content -LiteralPath $vj -Raw -Encoding utf8
if ($rawVj -notmatch [regex]::Escape($BuildId)) {
  Write-Warning "version.json nao contem buildId esperado '$BuildId' - ajustar CATALOG_BUILD_ID ou voltar a correr build."
}
else {
  Write-Host "OK: version.json contem buildId $BuildId"
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
Write-Host 'Pos-deploy: validar URLs (checklist pos-deploy no relatorio WEB-CACHE).'
