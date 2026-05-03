# Build Web MasterPalm — release com PWA/SW desativados e artefactos validados.
# Uso:
#   .\scripts\build_web_release.ps1
#   $env:CATALOG_BUILD_ID = "stable-20260503-XYZ-abc1234"; .\scripts\build_web_release.ps1
#
# Não faz deploy nem commit.

param(
  [string]$BuildId = $env:CATALOG_BUILD_ID
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $ProjectRoot

if (-not $BuildId -or $BuildId.Trim() -eq "") {
  $short = ""
  try {
    $short = (git rev-parse --short HEAD 2>$null).Trim()
  } catch { }
  if (-not $short) { $short = "unknown" }
  $BuildId = "local-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$short"
}

$env:CATALOG_BUILD_ID = $BuildId
Write-Host "==> CATALOG_BUILD_ID=$BuildId" -ForegroundColor Cyan

Write-Host "==> flutter build web --release --source-maps --pwa-strategy=none"
flutter build web --release --source-maps --pwa-strategy=none "--dart-define=CATALOG_BUILD_ID=$BuildId"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '==> Reparar artefactos web (manifests / SW - evita SPA fallback = HTML em URLs estaticas)'
$bw = Join-Path $ProjectRoot "build\web"
$assets = Join-Path $bw "assets"
if (-not (Test-Path -LiteralPath $assets)) {
  Write-Error "Pasta em falta após build: $assets"
  exit 1
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
  Write-Error "web/flutter_service_worker.js em falta (stub obrigatório com --pwa-strategy=none)"
  exit 1
}
Copy-Item -LiteralPath $fswSrc -Destination $fswOut -Force
Write-Host "==> flutter_service_worker.js: stub web/ -> build/web" -ForegroundColor Cyan

$gitShort = "unknown"
try { $gitShort = (git rev-parse --short HEAD 2>$null).Trim() } catch { }
$vjOut = Join-Path $ProjectRoot "build\web\version.json"
$ver = [ordered]@{
  buildId        = $BuildId
  hostingTarget  = "masterpalm-58c46"
  siteId         = "masterpalm-58c46"
  expectedDomain = "app.mastepalm.com.br"
  gitCommit      = $gitShort
}
($ver | ConvertTo-Json -Compress) + "`n" | Set-Content -LiteralPath $vjOut -Encoding utf8
Write-Host "==> gravado $vjOut"

& (Join-Path $ProjectRoot "scripts\pre_deploy_web_check.ps1") -ValidateOnly -BuildId $BuildId
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "Build OK. Próximo passo: firebase deploy --only hosting:masterpalm-58c46" -ForegroundColor Green
