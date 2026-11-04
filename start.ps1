# Entry point for the Terminal panel: make sure pi is installed where the eval expects it, then run everything.
# Re-run any time; finished work is skipped. Add -SkipPull to run fully offline.
param([switch]$SkipPull)
# Wait for any other run of the pipeline to finish so two runs never share the server or CSVs.
while (Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'start\.ps1|run-all\.ps1' }) {
    Write-Host "$(Get-Date -Format 'HH:mm:ss') another eval run is active; waiting..."
    Start-Sleep 120
}
$base = "$env:LOCALAPPDATA\llm-eval"
if (-not (Test-Path "$base\opencode.exe")) { & "$PSScriptRoot\install-harnesses.ps1" }
New-Item -ItemType Directory -Force "$base\pi-agent" | Out-Null
Copy-Item "$PSScriptRoot\pi-models.json" "$base\pi-agent\models.json" -Force
Remove-Item "$PSScriptRoot\pulled.txt" -ErrorAction SilentlyContinue
& "$PSScriptRoot\run-all.ps1" -SkipPull:$SkipPull
