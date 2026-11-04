# Smoke test of the daily-use config: plain `pi` and `opencode` commands with no model flags.
$log = "$PSScriptRoot\smoke-daily.txt"
$dir = "$env:LOCALAPPDATA\llm-eval\smoke"
Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $dir | Out-Null
Set-Location $dir
& {
    '== server env'; ((Get-Content "$env:LOCALAPPDATA\Ollama\server.log" -TotalCount 1) -split ' (?=OLLAMA_)') | Where-Object { $_ -match '^OLLAMA_(HOST|CONTEXT_LENGTH|KV_CACHE|FLASH|MAX_LOADED)' }
    '== pi'; $sw = [Diagnostics.Stopwatch]::StartNew()
    & pi -p "Create a file hello.py that prints 'hi', run it with python, and tell me the output."
    "pi exit $LASTEXITCODE in $([int]$sw.Elapsed.TotalSeconds)s; hello.py exists: $(Test-Path .\hello.py)"
    '== opencode'; $sw.Restart()
    & opencode run "Reply with exactly: OPENCODE_OK"
    "opencode exit $LASTEXITCODE in $([int]$sw.Elapsed.TotalSeconds)s"
    '== loaded'; (Invoke-RestMethod http://127.0.0.1:11434/api/ps).models | ForEach-Object { "$($_.name) ctx=$($_.context_length)" }
    'done'
} *> $log
