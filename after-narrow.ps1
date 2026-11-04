# Waits for the running narrow.ps1 to finish, then runs it again: finished work is skipped, so this
# pass only adds what was queued later (gpt-oss-120b, time-to-first-token measurements).
while (Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'narrow\.ps1' }) {
    Start-Sleep 60
}
& "$PSScriptRoot\narrow.ps1"
