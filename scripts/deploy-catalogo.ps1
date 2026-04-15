# Sincroniza produtos (Hive) -> Firestore catálogo LIVE.
# Usa o Dart do SDK Flutter (evita "Offset isn't a type" ao rodar `dart` isolado do PATH).
#
# Uso (na raiz do projeto):
#   .\scripts\deploy-catalogo.ps1

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
if ($root -match "scripts$") { $root = Split-Path -Parent $root }
Set-Location $root

. (Join-Path $PSScriptRoot "_dart_from_flutter.ps1")

Write-Host "Deploy do catálogo (Firestore)..." -ForegroundColor Cyan
Write-Host "  Flutter: $script:FlutterCmd | Dart: $(if ($script:UseFvmDart) { 'fvm dart' } else { $script:ProjDartExe })" -ForegroundColor DarkGray

Invoke-ProjDart run lib/scripts/deploy_catalog_live.dart
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "OK." -ForegroundColor Green
