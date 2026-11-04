# Re-runs gpt-oss-120b's context test once narrow.ps1 is done with the GPU. The first run failed only
# because gpt-oss's mandatory reasoning used up the 64-token answer budget (at 128K it had written "7-").
while (Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'narrow\.ps1' }) {
    Start-Sleep 60
}
$root = $PSScriptRoot
Add-Content "$root\run-all.log" "$(Get-Date -Format 'HH:mm:ss') context retest gpt-oss:120b"
Move-Item "$root\ctx-gpt-oss_120b.csv" "$root\ctx-gpt-oss_120b-first-try.csv" -Force -ErrorAction SilentlyContinue
& "$root\bench.ps1" -Models 'gpt-oss:120b' -Contexts 131072, 65536 -Out "$root\ctx-gpt-oss_120b.csv" *> "$root\ctx-gpt-oss_120b-retest.log"
Add-Content "$root\run-all.log" "$(Get-Date -Format 'HH:mm:ss') context retest gpt-oss done"
