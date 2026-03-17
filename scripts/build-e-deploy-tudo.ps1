# MasterPalm - Build e deploy de todas as plataformas
# Uso: .\scripts\build-e-deploy-tudo.ps1
#      .\scripts\build-e-deploy-tudo.ps1 -ApenasSetup
#      .\scripts\build-e-deploy-tudo.ps1 -SemDeploy | -SemWeb | -SemApk

param(
    [switch]$ApenasSetup,
    [switch]$SemDeploy,
    [switch]$SemWeb,
    [switch]$SemApk
)

$ErrorActionPreference = "Stop"
# Raiz do projeto = pasta que contem pubspec.yaml (um nivel acima de scripts/)
$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
Set-Location $root

Write-Host "`n==> 1/6 Dependencias Flutter (pub get)" -ForegroundColor Cyan
fvm flutter pub get
if ($LASTEXITCODE -ne 0) { throw "fvm flutter pub get falhou" }
Write-Host "OK: Flutter dependencies instaladas" -ForegroundColor Green

Write-Host "`n==> 2/6 Dependencias Cloud Functions" -ForegroundColor Cyan
$dirs = @("functions", "main")
foreach ($d in $dirs) {
    $p = Join-Path $root $d
    $pj = Join-Path $p "package.json"
    if (Test-Path $pj) {
        Push-Location $p
        npm install
        Pop-Location
    }
}
Write-Host "OK: Cloud Functions dependencies instaladas" -ForegroundColor Green

if ($ApenasSetup) {
    Write-Host "`nSetup concluido. Rode sem -ApenasSetup para build e deploy." -ForegroundColor Green
    exit 0
}

Write-Host "`n==> 3/6 Analise do codigo (fvm flutter analyze)" -ForegroundColor Cyan
$prevErr = $ErrorActionPreference
$ErrorActionPreference = "Continue"
fvm flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1 | Out-Null
$analyzeExit = $LASTEXITCODE
$ErrorActionPreference = $prevErr
if ($analyzeExit -ne 0) { Write-Host "AVISO: fvm flutter analyze encontrou erros (build continua)" -ForegroundColor Yellow }
if ($analyzeExit -eq 0) { Write-Host "OK: Analise concluida" -ForegroundColor Green }

# 4 - Build Web
if (-not $SemWeb) {
    Write-Host "`n==> 4/6 Build Flutter Web (catalogo online)" -ForegroundColor Cyan
    fvm flutter build web --release
    if ($LASTEXITCODE -ne 0) { throw "fvm flutter build web falhou" }
    Write-Host "OK: Build web em build/web" -ForegroundColor Green
}
if ($SemWeb) { Write-Host "AVISO: Pulando build web (-SemWeb)" -ForegroundColor Yellow }

# 5 - Build Android
if (-not $SemApk) {
    # Garantir keystore de release (evita conflito ao atualizar APK)
    $keystorePath = Join-Path $root "android\app\release.keystore"
    if (-not (Test-Path $keystorePath)) {
        Write-Host "Gerando release.keystore para assinatura consistente..." -ForegroundColor Yellow
        & "$PSScriptRoot\setup-release-keystore.ps1"
    }
    Write-Host "`n==> 5/6 Build Android (APK release)" -ForegroundColor Cyan
    fvm flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw "fvm flutter build apk falhou" }
    $apkPath = Join-Path $root "build\app\outputs\flutter-apk\app-release.apk"
    if (Test-Path $apkPath) { Write-Host "OK: APK gerado: $apkPath" -ForegroundColor Green }
}
if ($SemApk) { Write-Host "AVISO: Pulando build Android (-SemApk)" -ForegroundColor Yellow }

# 5b - Copiar download.html e APK para build/web (site mastepalm.com.br)
$buildWeb = Join-Path $root "build\web"
$downloadHtml = Join-Path $root "web\download.html"
if (Test-Path $downloadHtml) {
    Copy-Item $downloadHtml (Join-Path $buildWeb "download.html") -Force
    Write-Host "OK: Pagina de download copiada para build/web" -ForegroundColor Green
}
$apkPath = Join-Path $root "build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $apkPath) {
    $downloadsDir = Join-Path $buildWeb "downloads"
    if (-not (Test-Path $downloadsDir)) { New-Item -ItemType Directory -Path $downloadsDir -Force | Out-Null }
    Copy-Item $apkPath (Join-Path $downloadsDir "masterpalm.apk") -Force
    Write-Host "OK: APK copiado para build/web/downloads/" -ForegroundColor Green
}

# 6 - Deploy Firebase
if (-not $SemDeploy) {
    Write-Host "`n==> 6/6 Deploy Firebase (rules + functions + hosting)" -ForegroundColor Cyan
    firebase deploy
    if ($LASTEXITCODE -ne 0) { throw "firebase deploy falhou" }
    Write-Host "OK: Deploy concluido" -ForegroundColor Green
}
if ($SemDeploy) { Write-Host "AVISO: Deploy nao executado (-SemDeploy). Rode firebase deploy manualmente." -ForegroundColor Yellow }

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  Concluido: catalogo online, app Android e backend prontos." -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green
