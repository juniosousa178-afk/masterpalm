$ErrorActionPreference = 'Stop'
if (Get-Command gcloud -ErrorAction SilentlyContinue) {
  Write-Output ((gcloud auth print-access-token).Trim())
  exit 0
}
$cands = @(
  'C:\Program Files (x86)\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd',
  'C:\Program Files\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd'
)
foreach ($c in $cands) {
  if (Test-Path -LiteralPath $c) {
    Write-Output ((& $c auth print-access-token).Trim())
    exit 0
  }
}
Write-Error 'gcloud not found'
exit 1
