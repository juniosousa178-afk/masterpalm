# Dot-source a partir de outros .ps1 em scripts\:
#   . (Join-Path $PSScriptRoot "_dart_from_flutter.ps1")
#
# Define:
#   $script:FlutterCmd     -> "fvm flutter" ou "flutter"
#   $script:ProjDartExe   -> caminho do dart.exe do SDK Flutter (quando nao usa FVM)
#   $script:UseFvmDart     -> $true se .fvm existe e fvm esta no PATH
#   Invoke-ProjDart        -> executa dart/fvm dart na raiz do projeto (hive_flutter precisa dart:ui)

$script:DartFvmProjRoot = Split-Path -Parent $PSScriptRoot
$script:UseFvmDart = $false
$script:ProjDartExe = $null
$script:FlutterCmd = "flutter"

if ((Test-Path (Join-Path $script:DartFvmProjRoot ".fvm")) -and (Get-Command "fvm" -ErrorAction SilentlyContinue)) {
    $script:UseFvmDart = $true
    $script:FlutterCmd = "fvm flutter"
}
else {
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
