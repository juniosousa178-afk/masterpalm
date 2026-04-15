# Dot-source a partir de outros .ps1 em scripts\:
#   . (Join-Path $PSScriptRoot "_dart_from_flutter.ps1")
#
# Define:
#   $script:FlutterCmd     -> "fvm flutter" ou "flutter"
#   $script:ProjDartExe   -> caminho do dart.exe do SDK Flutter (quando nao usa FVM)
#   $script:UseFvmDart     -> $true se .fvm existe, fvm no PATH e fvm flutter responde
#   Invoke-ProjDart        -> executa dart/fvm dart na raiz do projeto (hive_flutter precisa dart:ui)
#
# Forcar PATH (ignorar FVM): $env:MASTERPALM_SKIP_FVM = "1"
#   ou parametro -SkipFvm no script que define antes do dot-source.

$script:DartFvmProjRoot = Split-Path -Parent $PSScriptRoot
$script:UseFvmDart = $false
$script:ProjDartExe = $null
$script:FlutterCmd = "flutter"

function Set-ProjDartExeFromFlutterPath {
    $script:ProjDartExe = $null
    $flutterCmd = Get-Command "flutter" -ErrorAction SilentlyContinue
    if ($flutterCmd) {
        $flutterBin = Split-Path $flutterCmd.Source -Parent
        foreach ($rel in @("cache\dart-sdk\bin\dart.exe", "cache\dart-sdk\bin\dart.bat")) {
            $cand = Join-Path $flutterBin $rel
            if (Test-Path $cand) {
                $script:ProjDartExe = $cand
                break
            }
        }
    }
    if (-not $script:ProjDartExe) {
        $dartCmd = Get-Command "dart" -ErrorAction SilentlyContinue
        if ($dartCmd) { $script:ProjDartExe = $dartCmd.Source }
    }
}

$skipFvm = $env:MASTERPALM_SKIP_FVM -match '^(1|true|yes)$'

if (-not $skipFvm -and
    (Test-Path (Join-Path $script:DartFvmProjRoot ".fvm")) -and
    (Get-Command "fvm" -ErrorAction SilentlyContinue)) {
    $script:UseFvmDart = $true
    $script:FlutterCmd = "fvm flutter"
    Push-Location $script:DartFvmProjRoot
    try {
        # Redirecionar tudo no cmd: stderr do Flutter ("Building flutter tool...") vira erro no PS com $ErrorActionPreference Stop.
        $prevEap = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'SilentlyContinue'
            cmd /c "fvm flutter --version >nul 2>&1" | Out-Null
        }
        finally {
            $ErrorActionPreference = $prevEap
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Warning @"
FVM falhou (SDK corrompido ou pasta travada). Usando 'flutter' do PATH.
Reparo manual: feche VS Code/Cursor/terminais, depois exclua a pasta da versao em
  $env:USERPROFILE\fvm\versions\<versao>
ou rode: fvm install
Para sempre ignorar FVM neste shell: `$env:MASTERPALM_SKIP_FVM = '1'
"@
            $script:UseFvmDart = $false
            $script:FlutterCmd = "flutter"
            Set-ProjDartExeFromFlutterPath
        }
    }
    finally {
        Pop-Location
    }
}
else {
    if ($skipFvm) {
        Write-Host "  (MASTERPALM_SKIP_FVM: usando flutter no PATH, sem FVM)" -ForegroundColor DarkGray
    }
    Set-ProjDartExeFromFlutterPath
}

function Invoke-ProjDart {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$RemainingArgs
    )
    Push-Location $script:DartFvmProjRoot
    try {
        if ($script:UseFvmDart) {
            $quoted = $RemainingArgs | ForEach-Object {
                if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
            }
            $argLine = $quoted -join ' '
            & cmd /c "fvm dart $argLine"
        }
        elseif ($null -ne $script:ProjDartExe -and (Test-Path -LiteralPath $script:ProjDartExe)) {
            & $script:ProjDartExe @RemainingArgs
        }
        else {
            Write-Warning "Dart do Flutter nao encontrado. Instale Flutter (PATH) ou FVM (dart pub global activate fvm)."
            & dart @RemainingArgs
        }
    }
    finally {
        Pop-Location
    }
}
