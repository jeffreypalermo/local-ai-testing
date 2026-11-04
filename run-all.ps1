# One-shot, restartable pipeline: start Ollama with long-context settings, pull every
# candidate, then run the context sweep and the coding eval for any model not done yet.
# Safe to re-run after a crash or reboot: finished pulls and finished models are skipped.
# Usage: .\run-all.ps1            (add -SkipPull to run fully offline)
param([switch]$SkipPull)

$root = $PSScriptRoot
$ollama = "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe"
$env:OLLAMA_HOST = '127.0.0.1:11434'
$env:OLLAMA_FLASH_ATTENTION = '1'
$env:OLLAMA_KV_CACHE_TYPE = 'q8_0'
$env:OLLAMA_CONTEXT_LENGTH = '65536'   # default for agent runs; the context sweep sets num_ctx itself
$env:OLLAMA_MAX_LOADED_MODELS = '1'    # Ollama-only box: give each model the whole 109.7 GiB

# Small/coding models first so results arrive early; the ~90 GB models last.
$models = @(
    'nemotron-3.5-lightning', 'nemotron-3-nano', 'qwen3.8:27b',
    'qwen3-coder:30b-a3b-q8_0', 'gemma4:31b-it-bf16',
    'qwen3-coder-next:q8_0', 'devstral-2:123b-instruct-2512-q4_K_M', 'nemotron-3.5-super:120b-a12b',
    'metalspork/qwen3.8-flash-next-ud:UD-Q3_K_XL', 'frob/deepseek-v4-flash-0731:284b-a13b-ud-iq2_xxs'
)

function Log($msg) { $line = "$(Get-Date -Format 'HH:mm:ss') $msg"; Write-Host $line; Add-Content "$root\run-all.log" $line }

# The tray app relaunches its own server without these settings, so replace it with ours.
# If our server is already up (no tray app), keep it: restarting would break in-flight pulls.
$up = try { [bool](Invoke-RestMethod http://127.0.0.1:11434/api/version -TimeoutSec 3) } catch { $false }
if (-not $up -or (Get-Process 'ollama app' -ErrorAction SilentlyContinue)) {
    Get-Process 'ollama app', 'ollama' -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep 2
    Start-Process $ollama -ArgumentList 'serve' -WindowStyle Hidden `
        -RedirectStandardError "$root\ollama-serve.log" -RedirectStandardOutput "$root\ollama-serve.out"
    Start-Sleep 6
}
Log "server $((Invoke-RestMethod http://127.0.0.1:11434/api/version).version)"

# Downloads run in a parallel job; each model is tested as soon as its pull lands.
$pullJob = $null
if (-not $SkipPull) {
    $pullJob = Start-Job -ArgumentList $ollama, $models, $root -ScriptBlock {
        param($ollama, $models, $root)
        $env:OLLAMA_HOST = '127.0.0.1:11434'
        foreach ($m in $models) {
            & $ollama pull $m *> $null
            Add-Content "$root\run-all.log" "$(Get-Date -Format 'HH:mm:ss') pull $m exit=$LASTEXITCODE"
            Add-Content "$root\pulled.txt" $m
        }
    }
}

foreach ($m in $models) {
    $tag = if ($m -match ':') { $m } else { "${m}:latest" }
    while ($true) {
        $have = (Invoke-RestMethod http://127.0.0.1:11434/api/tags).models.name
        if ($have -contains $tag) { break }
        $pulled = if (Test-Path "$root\pulled.txt") { Get-Content "$root\pulled.txt" } else { @() }
        if ($SkipPull -or $pulled -contains $m -or ($pullJob -and $pullJob.State -ne 'Running')) { break }
        Start-Sleep 60
    }
    if ($have -notcontains $tag) { Log "skip $m (not downloaded)"; continue }
    $slug = $m -replace '[^\w\.-]', '_'

    # 1) Largest working context (skipped if already measured).
    $ctxFile = "$root\ctx-$slug.csv"
    if (-not (Test-Path $ctxFile)) {
        Log "context sweep $m"
        & "$root\bench.ps1" -Models $m -Contexts 500000, 262144, 131072, 65536 -Out $ctxFile *> "$root\ctx-$slug.log"
    }
    # GPU memory grew to 109.7 GiB after the 2026-11-03 firmware update: models that pass 500K
    # get probed higher (largest first) to find their real ceiling.
    $extFile = "$root\ctx-$slug-ext.csv"
    $passed500 = Import-Csv $ctxFile | Where-Object { $_.pass -eq 'True' -and [int]$_.num_ctx -ge 500000 }
    if ($passed500 -and -not (Test-Path $extFile)) {
        Log "context sweep above 500K $m"
        & "$root\bench.ps1" -Models $m -Contexts 1048576, 786432 -Out $extFile *> "$root\ctx-$slug-ext.log"
    }

    # 2) Agentic coding eval with the pi harness (resumes per task).
    foreach ($h in 'pi', 'opencode') {
        Log "agent eval $m ($h)"
        & "$root\agent-eval.ps1" -Models $m -Harness $h -Out "$root\agent-results.csv" *>> "$root\agent-$slug.log"
    }
    Log "done $m"
}
Log 'all done'
