# MasterPalm — Web release build com identidade Git (RECOVERY.2.5).
# Gera build/web/version.json DEPOIS do flutter build; não usa web/version.json como autoridade.
#
# Uso:
#   .\scripts\build_web_release.ps1
#   .\scripts\build_web_release.ps1 -ExpectedCommit 6af9a88f1f1d8df0734957be60fa51a863b0f4cd
#
# Não faz commit, push nem firebase deploy.

param(
  [string]$ExpectedCommit = "",
  [switch]$TestDirtySourceGuardOnly
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $ProjectRoot

function Fail([string]$Message) {
  Write-Error $Message
  exit 1
}

function Get-ReleaseIdentity {
  $full = (git rev-parse HEAD 2>$null).Trim()
  if (-not $full) { Fail "git rev-parse HEAD falhou" }
  $short = (git rev-parse --short=7 HEAD 2>$null).Trim()
  if (-not $short) { Fail "git rev-parse --short=7 HEAD falhou" }
  $buildId = "web-$short"
  return @{
    SourceCommitFull  = $full
    SourceCommitShort = $short
    BuildId           = $buildId
  }
}

function Test-DirtyReleaseSource {
  $patterns = @(
    "lib/",
    "web/",
    "test/",
    "assets/",
    "pubspec.yaml",
    "pubspec.lock",
    "firebase.json"
  )
  $porcelain = git status --porcelain 2>$null
  if (-not $porcelain) { return $false }
  foreach ($line in $porcelain) {
    if ($line.Length -lt 4) { continue }
    $path = $line.Substring(3).Trim()
    if ($path -match " -> ") {
      $path = ($path -split " -> ", 2)[1].Trim()
    }
    $norm = $path -replace '\\', '/'
    foreach ($p in $patterns) {
      if ($norm -eq $p.TrimEnd('/') -or $norm.StartsWith($p)) {
        return $true
      }
    }
  }
  return $false
}

$identity = Get-ReleaseIdentity
$SourceCommitFull = $identity.SourceCommitFull
$SourceCommitShort = $identity.SourceCommitShort
$BuildId = $identity.BuildId
$BuiltAtUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

Write-Host "==> Release identity (single source)" -ForegroundColor Cyan
Write-Host "    SOURCE_COMMIT_FULL=$SourceCommitFull"
Write-Host "    SOURCE_COMMIT_SHORT=$SourceCommitShort"
Write-Host "    BUILD_ID=$BuildId"

if ($ExpectedCommit -and $ExpectedCommit.Trim() -ne "") {
  $exp = $ExpectedCommit.Trim()
  if ($SourceCommitFull -ne $exp) {
    Fail "ExpectedCommit mismatch: HEAD=$SourceCommitFull expected=$exp"
  }
  Write-Host "==> ExpectedCommit guard OK" -ForegroundColor Green
}

if (Test-DirtyReleaseSource) {
  Fail "Dirty source in lib/web/test/assets/pubspec/firebase.json"
}
Write-Host "==> Dirty source guard OK" -ForegroundColor Green

if ($TestDirtySourceGuardOnly) {
  Write-Host "TestDirtySourceGuardOnly: OK (sem build)" -ForegroundColor Green
  exit 0
}

$env:CATALOG_BUILD_ID = $BuildId
$buildCmd = "flutter build web --release --source-maps --pwa-strategy=none --dart-define=CATALOG_BUILD_ID=$BuildId"
Write-Host "==> $buildCmd" -ForegroundColor Cyan
flutter build web --release --source-maps --pwa-strategy=none "--dart-define=CATALOG_BUILD_ID=$BuildId"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Reparar artefactos web (manifests / SW)
$bw = Join-Path $ProjectRoot "build\web"
$assets = Join-Path $bw "assets"
if (-not (Test-Path -LiteralPath $assets)) {
  Fail "Pasta em falta após build: $assets"
}
$amJson = Join-Path $assets "AssetManifest.json"
if (-not (Test-Path -LiteralPath $amJson)) {
  Set-Content -LiteralPath $amJson -Value '{}' -Encoding utf8
}
$amBin = Join-Path $assets "AssetManifest.bin.json"
if (-not (Test-Path -LiteralPath $amBin)) {
  Copy-Item -LiteralPath $amJson -Destination $amBin -Force
}
$fontM = Join-Path $assets "FontManifest.json"
if (-not (Test-Path -LiteralPath $fontM)) {
  Set-Content -LiteralPath $fontM -Value "[]`n" -Encoding utf8
}
$rootManifest = Join-Path $bw "manifest.json"
$webManifest = Join-Path $ProjectRoot "web\manifest.json"
if (-not (Test-Path -LiteralPath $rootManifest)) {
  if (Test-Path -LiteralPath $webManifest) {
    Copy-Item -LiteralPath $webManifest -Destination $rootManifest -Force
  }
}
$fswSrc = Join-Path $ProjectRoot "web\flutter_service_worker.js"
$fswOut = Join-Path $bw "flutter_service_worker.js"
if (-not (Test-Path -LiteralPath $fswSrc)) {
  Fail "web/flutter_service_worker.js em falta"
}
Copy-Item -LiteralPath $fswSrc -Destination $fswOut -Force

# Autoridade: version.json no artefato (substitui cópia stale de web/version.json)
$vjOut = Join-Path $bw "version.json"
$ver = [ordered]@{
  buildId         = $BuildId
  hostingTarget   = "masterpalm-58c46"
  siteId          = "masterpalm-58c46"
  expectedDomain  = "app.mastepalm.com.br"
  gitCommit       = $SourceCommitShort
  gitCommitFull   = $SourceCommitFull
  builtAtUtc      = $BuiltAtUtc
}
($ver | ConvertTo-Json -Compress) + "`n" | Set-Content -LiteralPath $vjOut -Encoding utf8
Write-Host "==> gravado $vjOut (identidade Git)" -ForegroundColor Green

# Validar version.json
$vj = Get-Content -LiteralPath $vjOut -Raw -Encoding utf8 | ConvertFrom-Json
if ($vj.gitCommit -ne $SourceCommitShort) {
  Fail "version.json gitCommit=$($vj.gitCommit) esperado $SourceCommitShort"
}
if ($vj.buildId -ne $BuildId) {
  Fail "version.json buildId=$($vj.buildId) esperado $BuildId"
}
Write-Host "==> version.json identity OK" -ForegroundColor Green

# Validar bundle
$mainJs = Join-Path $bw "main.dart.js"
if (-not (Test-Path -LiteralPath $mainJs)) {
  Fail "main.dart.js ausente"
}
$mainText = Get-Content -LiteralPath $mainJs -Raw -Encoding utf8
$occ = ([regex]::Matches($mainText, [regex]::Escape($BuildId))).Count
if ($occ -lt 1) {
  Fail "main.dart.js não contém BUILD_ID $BuildId"
}
Write-Host "==> main.dart.js contém BUILD_ID ($occ ocorrências)" -ForegroundColor Green

function Get-Sha256([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

$manifestDir = Join-Path $ProjectRoot "artifacts\release"
New-Item -ItemType Directory -Force -Path $manifestDir | Out-Null
$manifestPath = Join-Path $manifestDir "web-release-manifest.json"
$manifest = [ordered]@{
  sourceCommitFull  = $SourceCommitFull
  sourceCommitShort = $SourceCommitShort
  buildId           = $BuildId
  buildCommand      = $buildCmd
  builtAtUtc        = $BuiltAtUtc
  sha256            = [ordered]@{
    mainDartJs         = Get-Sha256 (Join-Path $bw "main.dart.js")
    mainDartJsMap      = Get-Sha256 (Join-Path $bw "main.dart.js.map")
    indexHtml          = Get-Sha256 (Join-Path $bw "index.html")
    flutterBootstrapJs = Get-Sha256 (Join-Path $bw "flutter_bootstrap.js")
    versionJson        = Get-Sha256 $vjOut
  }
}
($manifest | ConvertTo-Json -Depth 4) + "`n" | Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-Host "==> manifest $manifestPath" -ForegroundColor Green

Write-Host ""
Write-Host "Release build OK (artefato local validado; deploy não executado)." -ForegroundColor Green
exit 0
