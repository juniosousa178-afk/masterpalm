# Pré-deploy Web MasterPalm — análise, testes de rota, build e checagens de artefactos.
# Uso: .\scripts\pre_deploy_web_check.ps1
# Opcional: $env:CATALOG_BUILD_ID = "diag-20260427-APPSTARTFIX-f14fe79"

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $ProjectRoot

$BuildId = if ($env:CATALOG_BUILD_ID) { $env:CATALOG_BUILD_ID } else { "diag-20260427-APPSTARTFIX-f14fe79" }

Write-Host "==> flutter analyze"
flutter analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "==> flutter test (rotas)"
flutter test test/catalog_initial_web_route_test.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "==> flutter build web --release --source-maps"
flutter build web --release --source-maps "--dart-define=CATALOG_BUILD_ID=$BuildId"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$vj = Join-Path $ProjectRoot "build\web\version.json"
$js = Join-Path $ProjectRoot "build\web\main.dart.js"
$map = Join-Path $ProjectRoot "build\web\main.dart.js.map"

foreach ($p in @($vj, $js, $map)) {
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Error "Ficheiro em falta: $p"
        exit 1
    }
    Write-Host "OK: $p"
}

$raw = Get-Content -LiteralPath $vj -Raw
if ($raw -notmatch [regex]::Escape($BuildId)) {
    Write-Warning "build/web/version.json pode não conter CATALOG_BUILD_ID=$BuildId — verificar web/version.json antes do build."
} else {
    Write-Host "OK: version.json contém buildId $BuildId"
}

Write-Host ""
Write-Host "Próximo passo manual: firebase deploy --only hosting:masterpalm-58c46"
Write-Host "Depois: validar docs/DEPLOY_CHECKLIST.md (pós-deploy)."
