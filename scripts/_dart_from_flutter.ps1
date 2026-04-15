# Dot-source a partir de outros .ps1 em scripts\:
#   . (Join-Path $PSScriptRoot "_dart_from_flutter.ps1")
#
# Define:
#   $script:FlutterCmd     -> "fvm flutter" ou "flutter"
#   $script:ProjDartExe   -> caminho do dart.exe do SDK Flutter (quando nao usa FVM)
#   $script:UseFvmDart     -> $true se .fvm existe, fvm no PATH, fvm flutter e fvm dart respondem
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

function Get-FvmCmdMergedOutput([string]$Arguments) {
    $raw = cmd /c "$Arguments"
    if ($null -eq $raw) { return '' }
    if ($raw -is [array]) { return ($raw | ForEach-Object { "$_" }) -join "`n" }
    return "$raw"
}

if (-not $skipFvm -and
    (Test-Path (Join-Path $script:DartFvmProjRoot ".fvm")) -and
    (Get-Command "fvm" -ErrorAction SilentlyContinue)) {
    $script:UseFvmDart = $true
    $script:FlutterCmd = "fvm flutter"
    Push-Location $script:DartFvmProjRoot
    try {
        # Redirecionar no cmd: stderr ("Building flutter tool...", kernel binary, etc.) quebra o PS com $ErrorActionPreference Stop.
        $prevEap = $ErrorActionPreference
        $fvmOk = $false
        try {
            $ErrorActionPreference = 'SilentlyContinue'
            # fvm pode devolver exit 0 e ainda emitir "Invalid kernel binary" (stderr mesclado com 2>&1).
            $flutterTxt = Get-FvmCmdMergedOutput 'fvm flutter --version 2>&1'
            $flutterBad = ($LASTEXITCODE -ne 0) -or
                ($flutterTxt -match 'Invalid kernel|Kernel binary|doesn''t support Dart|doesn.t support Dart|Can''t load Kernel')
            if (-not $flutterBad) {
                $dartTxt = Get-FvmCmdMergedOutput 'fvm dart --version 2>&1'
                $dartBad = ($LASTEXITCODE -ne 0) -or
                    ($dartTxt -match 'Invalid kernel|Kernel binary|doesn''t support Dart|doesn.t support Dart|Can''t load Kernel')
                $fvmOk = -not $dartBad
            }
        }
        finally {
            $ErrorActionPreference = $prevEap
        }
        if (-not $fvmOk) {
            Write-Warning @"
FVM nao esta utilizavel (flutter/dart do FVM ou pacote global incompativel com seu Dart).
Usando 'flutter' / dart do SDK no PATH.
Reparo FVM: dart pub global activate fvm
  ou SDK/pasta: fvm install   / excluir versao em $env:USERPROFILE\fvm\versions\<versao>
Ignorar FVM neste shell: `$env:MASTERPALM_SKIP_FVM = '1'   ou script -SkipFvm
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
            $prevEap = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'SilentlyContinue'
                cmd /c "fvm dart $argLine"
            }
            finally {
                $ErrorActionPreference = $prevEap
            }
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
