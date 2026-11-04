# Removes the corrupted partial-download chunks of the Devstral 2 weights blob so the pull can start clean,
# then re-runs the retrying downloader. Only "-partial*" temp files of that one blob are touched.
$blobs = "$env:USERPROFILE\.ollama\models\blobs"
$parts = Get-ChildItem $blobs -Filter 'sha256-bd6c22cad19a402cea476d148800ec28704e6de55a34ca5da2d1b924df90945e-partial*'
Write-Host "removing $($parts.Count) partial files"
$parts | Remove-Item -Force
& "$PSScriptRoot\pull-all.ps1"
