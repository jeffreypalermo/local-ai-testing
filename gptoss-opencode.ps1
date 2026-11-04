# gpt-oss-120b passed the pi gate 4/4 but ranks outside the top 3 on context, so narrow.ps1 skips
# opencode for it. Run it once the GPU is free (after narrow.ps1 and the timing step finish).
while (Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'narrow\.ps1' }) {
    Start-Sleep 60
}
Add-Content "$PSScriptRoot\run-all.log" "$(Get-Date -Format 'HH:mm:ss') opencode gpt-oss:120b"
& "$PSScriptRoot\agent-eval.ps1" -Models 'gpt-oss:120b' -Harness opencode -Out "$PSScriptRoot\agent-results.csv" *>> "$PSScriptRoot\agent-gpt-oss_120b.log"
Add-Content "$PSScriptRoot\run-all.log" "$(Get-Date -Format 'HH:mm:ss') gpt-oss opencode done"
