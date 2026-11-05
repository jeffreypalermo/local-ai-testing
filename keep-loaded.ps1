# Makes Ollama keep a loaded model in memory indefinitely (OLLAMA_KEEP_ALIVE=-1) instead of unloading it after
# 5 idle minutes. A model is still swapped out when a different one is requested (OLLAMA_MAX_LOADED_MODELS=1),
# and a request with keep_alive=0 (the test scripts send these) still unloads it.
# Waits for the server to go idle before restarting it, so nobody's request gets cut off. Report: keep-loaded.txt.
# -NoWait restarts right away, cutting off any request in progress.
param([switch]$NoWait)
$log = "$PSScriptRoot\keep-loaded.txt"
Set-Content $log "keep-loaded $(Get-Date -Format s)"
function Say($m) { $l = "$(Get-Date -Format 'HH:mm:ss') $m"; Write-Host $l; Add-Content $log $l }

[Environment]::SetEnvironmentVariable('OLLAMA_KEEP_ALIVE', '-1', 'User')
Say "user env OLLAMA_KEEP_ALIVE=$([Environment]::GetEnvironmentVariable('OLLAMA_KEEP_ALIVE', 'User'))"

# Idle = nothing loaded. With the old 5-minute keep-alive, that means no requests for 5 minutes.
$loaded = $null
for ($i = 0; $i -lt 180 -and -not $NoWait; $i++) {
    $loaded = @((Invoke-RestMethod http://127.0.0.1:11434/api/ps).models)
    if (-not $loaded) { break }
    if ($i % 6 -eq 0) { Say "waiting for idle: $(($loaded | ForEach-Object { "$($_.name) until $($_.expires_at)" }) -join '; ')" }
    Start-Sleep 10
}
if ($loaded) { Say 'FAILED: server still busy after 30 minutes; not restarting. Run again later.'; exit 1 }

Say 'idle; restarting the Ollama app'
Get-Process 'ollama app', 'ollama' -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 3
# The app inherits this process's environment, which can hold stale OLLAMA_* values from earlier test runs.
# Use exactly the saved user settings; an unset one (OLLAMA_HOST) is removed so the app's own setting decides.
Get-ChildItem env: | Where-Object Name -like 'OLLAMA_*' | ForEach-Object { Remove-Item "env:$($_.Name)" }
$userEnv = [Environment]::GetEnvironmentVariables('User')
foreach ($k in @($userEnv.Keys | Where-Object { $_ -like 'OLLAMA_*' })) { Set-Item "env:$k" $userEnv[$k]; Say "launch env $k=$($userEnv[$k])" }
Start-Process "$env:LOCALAPPDATA\Programs\Ollama\ollama app.exe"
$up = $false
for ($i = 0; $i -lt 60 -and -not $up; $i++) { Start-Sleep 2; $up = try { [bool](Invoke-RestMethod http://127.0.0.1:11434/api/version -TimeoutSec 3) } catch { $false } }
Say "server up: $up"
Start-Sleep 3
# The newest "server config" line, not the log's first line (which can be from an older start).
$cfg = (Get-Content "$env:LOCALAPPDATA\Ollama\server.log" | Select-String 'server config' | Select-Object -Last 1).Line
$envLine = $cfg -split ' (?=OLLAMA_)' | Where-Object { $_ -match '^OLLAMA_(KEEP_ALIVE|HOST|CONTEXT_LENGTH|MAX_LOADED)' }
$envLine | ForEach-Object { Say "server $_" }
$lan = try { (Invoke-RestMethod http://192.168.1.66:11434/api/version -TimeoutSec 5).version } catch { "FAILED: $($_.Exception.Message)" }
Say "reachable at 192.168.1.66:11434: $lan"

# Check: load the default model with no keep_alive in the request, as pi and opencode do, and read its expiry.
$m = 'nemotron-3.5-super:120b-a12b'
Invoke-RestMethod http://127.0.0.1:11434/api/generate -Method Post -ContentType 'application/json' -TimeoutSec 1800 `
    -Body (@{ model = $m; prompt = 'Say OK.'; stream = $false; think = $false; options = @{ num_predict = 4 } } | ConvertTo-Json) | Out-Null
(Invoke-RestMethod http://127.0.0.1:11434/api/ps).models | ForEach-Object { Say "loaded $($_.name) ctx=$($_.context_length) expires $($_.expires_at)" }
Say 'done'
