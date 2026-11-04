# Long-context benchmark for Ollama models.
# Tries each model at 500K; if it doesn't fit fully on the GPU or fails the needle test,
# steps down through smaller windows to find the largest one that works.
# Usage: .\bench.ps1 -Models nemotron-3.5-lightning,qwen3.8:27b
param(
    [string[]]$Models = @('nemotron-3.5-lightning'),
    [int[]]$Contexts = @(500000, 393216, 262144, 196608, 131072, 65536),
    [string]$Out = "$PSScriptRoot\results.csv"
)

# Set LLM_EVAL_OLLAMA_URL (e.g. http://192.168.1.66:11434) to test a remote server. ram_delta_gb is then
# measured on this machine, not the server, so ignore it.
$api = "$(if ($env:LLM_EVAL_OLLAMA_URL) { $env:LLM_EVAL_OLLAMA_URL.TrimEnd('/') } else { 'http://127.0.0.1:11434' })/api"
$needle = 'The secret launch code for Project Heron is 7-ALPHA-4419.'
$sentences = @(
    'The committee reviewed the quarterly logistics report and noted steady progress across all regions.',
    'Weather patterns along the coast remained mild, with occasional fog in the early mornings.',
    'Engineers replaced several worn bearings during the scheduled maintenance window last week.',
    'The library extended its weekend hours to accommodate students preparing for final exams.',
    'Supply contracts were renewed with minor adjustments to delivery schedules and pricing.'
)

function New-Haystack([long]$chars) {
    # Build filler of the given length, then insert the needle at ~60% depth.
    $sb = [System.Text.StringBuilder]::new()
    $i = 0
    while ($sb.Length -lt $chars) { [void]$sb.Append($sentences[$i % 5]).Append(' '); $i++ }
    $text = $sb.ToString()
    $pos = $text.IndexOf('. ', [int]($text.Length * 0.6)) + 2
    $text.Insert($pos, "$needle ")
}

function Get-RamUsedGB {
    $os = Get-CimInstance Win32_OperatingSystem
    [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)
}

function Invoke-Gen($body, [int]$timeout) {
    Invoke-RestMethod "$api/generate" -Method Post -ContentType 'application/json' -TimeoutSec $timeout `
        -Body ($body | ConvertTo-Json -Depth 4)
}

function Stop-Model($m) { try { Invoke-Gen @{ model = $m; keep_alive = 0 } 60 | Out-Null } catch {} }

function Test-Context($m, [int]$numCtx) {
    Stop-Model $m
    Start-Sleep 3
    $ramBefore = Get-RamUsedGB
    $row = [ordered]@{ model = $m; num_ctx = $numCtx; error = $null }
    try {
        # Short prompt first: load at this context, measure memory and generation speed.
        $short = Invoke-Gen @{ model = $m; prompt = 'Write three sentences about rivers.'; stream = $false; think = $false
                               options = @{ num_ctx = $numCtx; temperature = 0 } } 3600
        $ps = (Invoke-RestMethod "$api/ps").models | Where-Object { $_.name -like "$m*" -or $_.model -like "$m*" } | Select-Object -First 1
        $row.loaded_ctx = $ps.context_length
        $row.size_gb    = [math]::Round($ps.size / 1GB, 1)
        $row.gpu_pct    = if ($ps.size) { [math]::Round(100 * $ps.size_vram / $ps.size) } else { $null }
        $row.gen_tok_s  = [math]::Round($short.eval_count / ($short.eval_duration / 1e9), 1)

        # Calibrate this model's tokenizer on the filler so the haystack fills the window.
        $sample = New-Haystack 200000
        $cal = Invoke-Gen @{ model = $m; prompt = $sample; stream = $false; think = $false
                             options = @{ num_ctx = $numCtx; num_predict = 1 } } 3600
        $charsPerToken = $sample.Length / $cal.prompt_eval_count
        $row.chars_per_token = [math]::Round($charsPerToken, 2)

        # Needle in a haystack filling ~96% of the window.
        $prompt = (New-Haystack ([long](($numCtx * 0.96 - 200) * $charsPerToken))) +
                  "`n`nQuestion: What is the secret launch code for Project Heron? Answer with only the code."
        $sw = [Diagnostics.Stopwatch]::StartNew()
        # think=false so reasoning models answer directly within num_predict. gpt-oss cannot turn
        # reasoning off (it ignores false), so give it the lowest level and room to finish the answer.
        $oss = $m -match 'gpt-oss'
        $long = Invoke-Gen @{ model = $m; prompt = $prompt; stream = $false; think = $(if ($oss) { 'low' } else { $false })
                              options = @{ num_ctx = $numCtx; temperature = 0; num_predict = $(if ($oss) { 1024 } else { 64 }) } } 14400
        $sw.Stop()
        $row.ram_delta_gb   = [math]::Round((Get-RamUsedGB) - $ramBefore, 1)
        $row.prompt_tokens  = $long.prompt_eval_count
        $row.prefill_tok_s  = [math]::Round($long.prompt_eval_count / ($long.prompt_eval_duration / 1e9), 0)
        $row.long_gen_tok_s = [math]::Round($long.eval_count / ($long.eval_duration / 1e9), 1)
        $row.wall_min       = [math]::Round($sw.Elapsed.TotalMinutes, 1)
        $row.truncated      = $long.prompt_eval_count -lt $numCtx * 0.9
        $row.needle_found   = $long.response -match '7-ALPHA-4419'
        $row.answer         = ($long.response -replace '\s+', ' ').Trim()
    } catch {
        $row.error = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
    }
    $row.pass = (-not $row.error) -and $row.gpu_pct -eq 100 -and (-not $row.truncated) -and $row.needle_found
    Stop-Model $m
    [pscustomobject]$row
}

$results = @()
foreach ($m in $Models) {
    foreach ($ctx in $Contexts) {
        Write-Host "== $m @ $ctx"
        $r = Test-Context $m $ctx
        $r | Format-List
        $results += $r
        $results | Export-Csv $Out -NoTypeInformation
        if ($r.pass) { Write-Host "-> max working context for ${m}: $ctx"; break }
    }
}
Write-Host "Saved $Out"
