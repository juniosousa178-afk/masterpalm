# =============================================================================
# MasterPalm - Corrigir e atualizar índice Firestore (campanhas_sorteio)
# =============================================================================
# Causa comum do erro na venda:
# "You can create it here: ...create_composite=..."
#
# Este script:
# 1) Garante que `firestore.indexes.json` contenha o composite index necessário
#    para `campanhas_sorteio` (ativa + dataInicio + dataFim).
# 2) Faz deploy apenas dos índices: `firebase deploy --only firestore:indexes`
# 3) Aguarda alguns minutos (pode ficar "Ativando" no console).
#
# Uso:
#   .\scripts\corrigir-atualizar-indice-campanhas-sorteio.ps1
#   .\scripts\corrigir-atualizar-indice-campanhas-sorteio.ps1 -ProjectId "masterpalm-58c46"
#   .\scripts\corrigir-atualizar-indice-campanhas-sorteio.ps1 -WaitMinutes 5
# =============================================================================

param(
    [string]$ProjectId = "masterpalm-58c46",
    [int]$WaitMinutes = 3
)

$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
if ($root -match "scripts$") {
    $root = Split-Path -Parent $root
}

Set-Location $root

$indexesPath = Join-Path $root "firestore.indexes.json"
if (-not (Test-Path $indexesPath)) {
    throw "Arquivo nao encontrado: $indexesPath"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Indice campanhas_sorteio - Corrigir/Deploy" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

function Test-IndexExists {
    param(
        [Parameter(Mandatory=$true)] $indexes,
        [Parameter(Mandatory=$true)] [string] $collectionGroup,
        [Parameter(Mandatory=$true)] [string] $queryScope,
        [Parameter(Mandatory=$true)] [array]  $fields
    )

    foreach ($idx in $indexes) {
        if ($idx.collectionGroup -ne $collectionGroup) { continue }
        if ($idx.queryScope -ne $queryScope) { continue }
        $sameCount = ($idx.fields | Measure-Object).Count -eq ($fields | Measure-Object).Count
        if (-not $sameCount) { continue }

        $allMatch = $true
        for ($i = 0; $i -lt $fields.Count; $i++) {
            $a = $idx.fields[$i]
            $b = $fields[$i]
            if ($a.fieldPath -ne $b.fieldPath) { $allMatch = $false; break }
            if ($a.order -ne $b.order) { $allMatch = $false; break }
        }
        if ($allMatch) { return $true }
    }

    return $false
}

function Ensure-Index {
    param(
        [Parameter(Mandatory=$true)] [ref] $indexesRef,
        [Parameter(Mandatory=$true)] [string] $collectionGroup,
        [Parameter(Mandatory=$true)] [string] $queryScope,
        [Parameter(Mandatory=$true)] [array]  $fields,
        [Parameter(Mandatory=$true)] [string] $tag
    )

    if (-not (Test-IndexExists -indexes $indexesRef.Value -collectionGroup $collectionGroup -queryScope $queryScope -fields $fields)) {
        Write-Host "  + Adicionando indice faltante ($tag)..." -ForegroundColor Yellow
        $indexesRef.Value += [pscustomobject]@{
            collectionGroup = $collectionGroup
            queryScope      = $queryScope
            fields           = $fields
        }
        return $true
    }

    Write-Host "  OK Indice ok ($tag)" -ForegroundColor Green
    return $false
}

$raw = Get-Content $indexesPath -Raw
$json = $raw | ConvertFrom-Json

if (-not $json.indexes) {
    $json | Add-Member -MemberType NoteProperty -Name "indexes" -Value @()
}

$indexesChanged = $false

# Índices alvo (para query):
# .where('ativa', isEqualTo: true)
# .where('dataInicio', isLessThanOrEqualTo: ts)
# .where('dataFim', isGreaterThanOrEqualTo: ts)
#
# Normalmente o Firestore pede um composite index com:
#   ativa (ASC), dataInicio (ASC), dataFim (ASC)
# Observacao: manter tambem o 2-campos (ativa, dataFim) ajuda se a query
# for variada em outras telas.

$collectionGroup = "campanhas_sorteio"
$queryScope = "COLLECTION"

$fields3 = @(
    [pscustomobject]@{ fieldPath = "ativa"; order = "ASCENDING" },
    [pscustomobject]@{ fieldPath = "dataInicio"; order = "ASCENDING" },
    [pscustomobject]@{ fieldPath = "dataFim"; order = "ASCENDING" }
)

$fields2 = @(
    [pscustomobject]@{ fieldPath = "ativa"; order = "ASCENDING" },
    [pscustomobject]@{ fieldPath = "dataFim"; order = "ASCENDING" }
)

$indexesChanged = (Ensure-Index -indexesRef ([ref]$json.indexes) -collectionGroup $collectionGroup -queryScope $queryScope -fields $fields3 -tag "ativa+dataInicio+dataFim") -or $indexesChanged
$indexesChanged = (Ensure-Index -indexesRef ([ref]$json.indexes) -collectionGroup $collectionGroup -queryScope $queryScope -fields $fields2 -tag "ativa+dataFim") -or $indexesChanged

if ($indexesChanged) {
    Write-Host ""
    Write-Host "Salvando arquivo: $indexesPath" -ForegroundColor Cyan
    ($json | ConvertTo-Json -Depth 99) | Set-Content -Path $indexesPath -Encoding UTF8
}
else {
    Write-Host ""
    Write-Host "Nenhuma alteracao no firestore.indexes.json foi necessaria." -ForegroundColor Gray
}

Write-Host ""
Write-Host "Deploy apenas dos índices do Firestore..." -ForegroundColor Yellow

$deployArgs = @("deploy", "--only", "firestore:indexes", "--project", $ProjectId)
Write-Host "Executando: firebase $($deployArgs -join ' ')" -ForegroundColor Gray
& firebase @deployArgs

if ($LASTEXITCODE -ne 0) {
    throw "Falha no deploy de firestore:indexes (exit code $LASTEXITCODE)"
}

Write-Host ""
if ($WaitMinutes -gt 0) {
    Write-Host "Aguardando $WaitMinutes minuto(s) para os indices ativarem..." -ForegroundColor Cyan
    Start-Sleep -Seconds ($WaitMinutes * 60)
}

Write-Host ""
Write-Host "Pronto. Agora teste uma venda e, se continuar falhando, aguarde o indice ficar Enabled no console." -ForegroundColor Green

