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

$fswSrc = Join-Path $ProjectRoot "web\flutter_service_worker.js"
$fswOut = Join-Path $ProjectRoot "build\web\flutter_service_worker.js"
if (Test-Path -LiteralPath $fswSrc) {
  Copy-Item -LiteralPath $fswSrc -Destination $fswOut -Force
  Write-Host "==> flutter_service_worker.js: copiado web/ -> build/web (stub)"
}

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
