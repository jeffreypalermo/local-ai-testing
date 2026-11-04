# Replaces the 3-bit Flash-Next build with the 4-bit one in the daily pi and opencode configs, keeping
# everything else (default model, other models, settings) as it is. Backups go next to each file as *.pre-q4.bak.
# Then checks that both tools list it and can use it. Report: swap-flashnext.txt next to this script.
$old = 'metalspork/qwen3.8-flash-next-ud:UD-Q3_K_XL'
$new = 'qwen3.8-flash-next:q4_k_m'
$log = "$PSScriptRoot\swap-flashnext.txt"
Set-Content $log "swap $(Get-Date -Format s)"
function Say($m) { Write-Host $m; Add-Content $log $m }
foreach ($f in "$env:USERPROFILE\.pi\agent\models.json", "$env:USERPROFILE\.config\opencode\opencode.jsonc") {
    $text = [IO.File]::ReadAllText($f)
    $n = ([regex]::Matches($text, [regex]::Escape($old))).Count
    if ($n -eq 0) { Say "$f : no '$old' found, unchanged"; continue }
    Copy-Item $f "$f.pre-q4.bak" -Force
    $text = $text.Replace($old, $new)
    $null = $text | ConvertFrom-Json   # stop before writing if the result isn't valid JSON
    [IO.File]::WriteAllText($f, $text, [Text.UTF8Encoding]::new($false))
    Say "$f : replaced $n occurrence(s); backup $f.pre-q4.bak"
}

$dir = "$env:LOCALAPPDATA\llm-eval\smoke-q4"
Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $dir | Out-Null
Set-Location $dir
Say '== pi --list-models'
& pi --list-models 2>&1 | ForEach-Object { Say "  $_" }
Say '== opencode models'
& opencode models 2>&1 | ForEach-Object { Say "  $_" }
Say "== pi with $new"
$sw = [Diagnostics.Stopwatch]::StartNew()
& pi --model "ollama/$new" -p "Create a file hello.py that prints 'hi', run it with python, and tell me the output." 2>&1 | ForEach-Object { Say "  $_" }
Say "pi exit $LASTEXITCODE in $([int]$sw.Elapsed.TotalSeconds)s; hello.py exists: $(Test-Path .\hello.py)"
Say "== opencode with $new"
$sw.Restart()
& opencode run -m "ollama/$new" "Reply with exactly: OPENCODE_OK" 2>&1 | ForEach-Object { Say "  $_" }
Say "opencode exit $LASTEXITCODE in $([int]$sw.Elapsed.TotalSeconds)s"
Say '== loaded'
(Invoke-RestMethod http://127.0.0.1:11434/api/ps).models | ForEach-Object { Say "  $($_.name) ctx=$($_.context_length) gpu=$([math]::Round(100 * $_.size_vram / $_.size))%" }
Say 'done'
