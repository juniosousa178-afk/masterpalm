# R8.4.43 — sobe Auth + Firestore emulators com readiness estável (sem stderr falso no PowerShell).
param(
  [int]$StableSeconds = 10,
  [int]$TimeoutMinutes = 3
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$configPath = Join-Path $ProjectRoot 'tool\e2e_web\firebase.json'
if (-not (Test-Path -LiteralPath $configPath)) {
  throw "firebase.json não encontrado: $configPath"
}

function Test-PortOpen {
  param([int]$Port)
  $client = New-Object System.Net.Sockets.TcpClient
  try {
    $client.Connect('127.0.0.1', $Port)
    return $true
  } catch {
    return $false
  } finally {
    $client.Close()
  }
}

$stdout = Join-Path $env:TEMP 'firebase-emulators.stdout.log'
$stderr = Join-Path $env:TEMP 'firebase-emulators.stderr.log'

$cmdLine = @(
  'npx --yes firebase-tools@latest emulators:start',
  '--project masterpalm-r8433-web-e2e-local',
  '--config tool\e2e_web\firebase.json',
  '--only auth,firestore'
) -join ' '

$process = Start-Process `
  -FilePath 'cmd.exe' `
  -ArgumentList @('/d', '/s', '/c', $cmdLine) `
  -RedirectStandardOutput $stdout `
  -RedirectStandardError $stderr `
  -PassThru `
  -WindowStyle Hidden `
  -WorkingDirectory $ProjectRoot

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$readySince = $null

while ((Get-Date) -lt $deadline) {
  if ($process.HasExited) {
    if (Test-Path -LiteralPath $stderr) {
      Get-Content -LiteralPath $stderr -Tail 40 | Write-Host
    }
    throw "Firebase Emulators encerraram antes da readiness. ExitCode=$($process.ExitCode)"
  }

  $authReady = Test-PortOpen -Port 9199
  $firestoreReady = Test-PortOpen -Port 8180

  if ($authReady -and $firestoreReady) {
    if ($null -eq $readySince) {
      $readySince = Get-Date
    }
    if (((Get-Date) - $readySince).TotalSeconds -ge $StableSeconds) {
      Write-Host 'AUTH_EMULATOR_STABLE_READY=true'
      Write-Host 'FIRESTORE_EMULATOR_STABLE_READY=true'
      Write-Host "EMULATOR_PROCESS_ID=$($process.Id)"
      Write-Host "EMULATOR_STDOUT_LOG=$stdout"
      Write-Host "EMULATOR_STDERR_LOG=$stderr"
      return
    }
  } else {
    $readySince = $null
  }

  Start-Sleep -Seconds 1
}

throw 'Firebase Emulators não ficaram disponíveis dentro do prazo.'
