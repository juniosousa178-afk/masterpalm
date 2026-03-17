# Logcat apenas do app MasterPalm (com.masterpalm.app)
# Uso: .\scripts\logcat-app.ps1   ou   .\scripts\logcat-app.ps1 -ErrorsOnly
# Requer: app aberto no dispositivo/emulador

param([switch]$ErrorsOnly)

$package = "com.masterpalm.app"

# Verifica dispositivo
$dev = adb devices
if ($dev -notmatch "device$") {
    Write-Host "Nenhum dispositivo conectado. Conecte o celular com USB (depuração ativada) ou inicie o emulador."
    exit 1
}

# Pega o PID do app (precisa estar rodando)
$pid = adb shell pidof $package 2>$null
$pid = $pid -replace "`r`n","" -replace "`n",""

if ([string]::IsNullOrWhiteSpace($pid)) {
    Write-Host "App $package nao esta rodando. Abra o MasterPalm no celular e execute este script de novo."
    Write-Host ""
    Write-Host "Alternativa (todos os logs do sistema, depois filtre no terminal):"
    Write-Host "  adb logcat"
    exit 1
}

Write-Host "App PID: $pid (package: $package)"
Write-Host "Pressione Ctrl+C para parar."
Write-Host ""

if ($ErrorsOnly) {
    adb logcat *:E --pid=$pid
} else {
    adb logcat --pid=$pid
}
