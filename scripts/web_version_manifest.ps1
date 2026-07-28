# Shared helpers — version.json Web manifest (R8.4.33).
# Dot-source: . "$PSScriptRoot\web_version_manifest.ps1"

$ErrorActionPreference = 'Stop'

$script:WebManifestExpectedHostingTarget = 'masterpalm-58c46'
$script:WebManifestExpectedDomain = 'app.mastepalm.com.br'
$script:WebManifestMinBuildNumber = 284

function Get-MasterPalmPubspecVersion {
  param([string]$ProjectRoot)
  $pubspecPath = Join-Path $ProjectRoot 'pubspec.yaml'
  if (-not (Test-Path -LiteralPath $pubspecPath)) {
    throw "pubspec.yaml não encontrado: $pubspecPath"
  }
  $raw = Get-Content -LiteralPath $pubspecPath -Raw -Encoding utf8
  if ($raw -notmatch '(?m)^version:\s*([0-9.]+)\+([0-9]+)\s*$') {
    throw 'pubspec.yaml: version inválida ou ausente (esperado X.Y.Z+N)'
  }
  $version = $matches[1].Trim()
  $buildNumber = $matches[2].Trim()
  if ([string]::IsNullOrWhiteSpace($version) -or [string]::IsNullOrWhiteSpace($buildNumber)) {
    throw 'pubspec version/build vazio'
  }
  $bn = 0
  if (-not [int]::TryParse($buildNumber, [ref]$bn) -or $bn -le 0) {
    throw "build_number pubspec inválido: $buildNumber"
  }
  if ($bn -lt $script:WebManifestMinBuildNumber) {
    throw "build_number $bn < mínimo $($script:WebManifestMinBuildNumber)"
  }
  return [ordered]@{
    version     = $version
    buildNumber = $buildNumber
    buildInt    = $bn
  }
}

function Write-MasterPalmWebVersionManifest {
  param(
    [string]$ProjectRoot,
    [string]$OutPath,
    [string]$BuildId,
    [string]$GitCommit
  )
  if ([string]::IsNullOrWhiteSpace($BuildId)) {
    throw 'BuildId obrigatório para candidato Web'
  }
  $pv = Get-MasterPalmPubspecVersion -ProjectRoot $ProjectRoot
  $head = ''
  try { $head = (git -C $ProjectRoot rev-parse --short HEAD 2>$null).Trim() } catch { }
  if ([string]::IsNullOrWhiteSpace($GitCommit)) { $GitCommit = $head }
  if ($GitCommit -ne $head) {
    throw "gitCommit=$GitCommit != HEAD=$head"
  }
  $o = [ordered]@{
    app_name       = 'master_palm'
    version        = $pv.version
    build_number   = $pv.buildNumber
    package_name   = 'master_palm'
    buildId        = $BuildId
    gitCommit      = $GitCommit
    hostingTarget  = $script:WebManifestExpectedHostingTarget
    siteId         = $script:WebManifestExpectedHostingTarget
    expectedDomain = $script:WebManifestExpectedDomain
  }
  $json = ($o | ConvertTo-Json -Compress) + "`n"
  $dir = Split-Path -Parent $OutPath
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  Set-Content -LiteralPath $OutPath -Value $json -Encoding utf8
  return $o
}

function Test-MasterPalmWebVersionManifest {
  param(
    [string]$LiteralPath,
    [string]$ExpectedBuildId,
    [string]$ExpectedGitCommit
  )
  if (-not (Test-Path -LiteralPath $LiteralPath)) {
    throw "version.json ausente: $LiteralPath"
  }
  $raw = Get-Content -LiteralPath $LiteralPath -Raw -Encoding utf8
  $j = $raw | ConvertFrom-Json
  $required = @(
    'app_name', 'version', 'build_number', 'package_name',
    'buildId', 'gitCommit', 'hostingTarget', 'expectedDomain'
  )
  foreach ($k in $required) {
    $v = $j.$k
    if ($null -eq $v -or "$v".Trim() -eq '') {
      throw "version.json: campo obrigatório ausente/vazio: $k"
    }
  }
  if ($j.buildId -ne $ExpectedBuildId) {
    throw "buildId=$($j.buildId) != esperado $ExpectedBuildId"
  }
  if ($j.gitCommit -ne $ExpectedGitCommit) {
    throw "gitCommit=$($j.gitCommit) != HEAD $ExpectedGitCommit"
  }
  if ($j.hostingTarget -ne $script:WebManifestExpectedHostingTarget) {
    throw "hostingTarget inválido: $($j.hostingTarget)"
  }
  if ($j.expectedDomain -ne $script:WebManifestExpectedDomain) {
    throw "expectedDomain inválido: $($j.expectedDomain)"
  }
  $bn = 0
  if (-not [int]::TryParse([string]$j.build_number, [ref]$bn) -or $bn -le 0) {
    throw "build_number inválido: $($j.build_number)"
  }
  if ($bn -lt $script:WebManifestMinBuildNumber) {
    throw "build_number $bn < $($script:WebManifestMinBuildNumber)"
  }
  # Regressão R8432: só metadados deploy
  if (-not $j.PSObject.Properties.Name.Contains('build_number')) {
    throw 'WEB_VERSION_JSON_PACKAGEINFO_CONTRACT_GUARDED: build_number ausente'
  }
  return $true
}

function Repair-MasterPalmWebServiceWorkerStub {
  param(
    [string]$ProjectRoot,
    [string]$BuildDir = 'build\web'
  )
  $src = Join-Path $ProjectRoot 'web\flutter_service_worker.js'
  $dst = Join-Path $ProjectRoot (Join-Path $BuildDir 'flutter_service_worker.js')
  if (-not (Test-Path -LiteralPath $src)) {
    throw "Stub SW ausente: $src"
  }
  $srcLen = (Get-Item -LiteralPath $src).Length
  if ($srcLen -lt 100) {
    throw "Stub SW inválido (tamanho $srcLen)"
  }
  Copy-Item -LiteralPath $src -Destination $dst -Force
  if ((Get-Item -LiteralPath $dst).Length -lt 100) {
    throw 'flutter_service_worker.js no build ficou vazio após cópia'
  }
}

function Test-MasterPalmProductionWebArtifact {
  param([string]$BuildWebDir)
  $js = Join-Path $BuildWebDir 'main.dart.js'
  if (-not (Test-Path -LiteralPath $js)) { throw 'main.dart.js ausente' }
  $content = Get-Content -LiteralPath $js -Raw -Encoding utf8
  $blockedPatterns = @(
    @{ Name = 'firestore_emulator_localhost'; Pattern = 'useFirestoreEmulator\([^)]*127\.0\.0\.1' },
    @{ Name = 'auth_emulator_localhost'; Pattern = 'useAuthEmulator\([^)]*127\.0\.0\.1' },
    @{ Name = 'qa_project_bootstrap'; Pattern = 'projectId:\s*[`''"]masterpalm-r8433-web-e2e-local[`''"]' },
    @{ Name = 'planos_e2e_project'; Pattern = 'masterpalm-planos-e2e-local' }
  )
  foreach ($b in $blockedPatterns) {
    if ($content -match $b.Pattern) {
      throw "WEB_PRODUCTION_ENVIRONMENT_GUARD: artefato contém $($b.Name)"
    }
  }
}

function Get-MasterPalmFileSha256 {
  param([string]$LiteralPath)
  return (Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256).Hash
}

function Invoke-MasterPalmFlutterBuildWeb {
  param([string[]]$FlutterArgs)
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & flutter @FlutterArgs
  $exit = $LASTEXITCODE
  $ErrorActionPreference = $prevEap
  if ($exit -ne 0) {
    throw "flutter build web falhou (exit $exit)"
  }
}
