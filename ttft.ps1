# Time to first token and prompt intake speed at a few prompt sizes (streamed, model pre-loaded).
# Usage: .\ttft.ps1 -Models qwen3.8:27b,gpt-oss:120b [-Sizes 4096,32768,131072]
param(
    [string[]]$Models = @('qwen3.8:27b'),
    [int[]]$Sizes = @(4096, 32768, 131072),
    [string]$Out = "$PSScriptRoot\ttft-results.csv"
)
Add-Type -AssemblyName System.Net.Http
# Set LLM_EVAL_OLLAMA_URL (e.g. http://192.168.1.66:11434) to measure a remote server; network time is included.
$api = "$(if ($env:LLM_EVAL_OLLAMA_URL) { $env:LLM_EVAL_OLLAMA_URL.TrimEnd('/') } else { 'http://127.0.0.1:11434' })/api"
$http = [System.Net.Http.HttpClient]::new(); $http.Timeout = [TimeSpan]::FromHours(2)
$sentences = @(
    'The committee reviewed the quarterly logistics report and noted steady progress across all regions.',
    'Engineers replaced several worn bearings during the scheduled maintenance window last week.',
    'Supply contracts were renewed with minor adjustments to delivery schedules and pricing.',
    'The library extended its weekend hours to accommodate students preparing for final exams.')

function Post($body) {
    $req = [System.Net.Http.HttpRequestMessage]::new('POST', "$api/generate")
    $req.Content = [System.Net.Http.StringContent]::new(($body | ConvertTo-Json -Depth 5), [Text.Encoding]::UTF8, 'application/json')
    $http.SendAsync($req, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
}
function Get-Native($m) {
    $s = Invoke-RestMethod "$api/show" -Method Post -ContentType 'application/json' -Body (@{ model = $m } | ConvertTo-Json)
    [int]($s.model_info.PSObject.Properties | Where-Object Name -like '*.context_length' | Select-Object -First 1).Value
}
function New-Prompt([int]$tokens, [double]$charsPerToken) {
    # Unique first line so the server's prompt cache cannot reuse an earlier, shorter prompt.
    $sb = [Text.StringBuilder]::new("Document $([guid]::NewGuid()):`n")
    $i = 0
    while ($sb.Length -lt $tokens * $charsPerToken) { [void]$sb.Append($sentences[$i % 4]).Append(' '); $i++ }
    $sb.Append("`n`nIn one sentence, what is this document about?").ToString()
}

$rows = @(if (Test-Path $Out) { Import-Csv $Out })
foreach ($m in $Models) {
    $native = Get-Native $m
    $sizes = @($Sizes | Where-Object { $_ + 1024 -le $native })
    if (-not $sizes) { continue }
    if ($rows | Where-Object { $_.model -eq $m }) { continue }
    $numCtx = [Math]::Min($native, ($sizes | Measure-Object -Maximum).Maximum + 1024)
    $opts = @{ num_ctx = $numCtx; temperature = 0; num_predict = 48 }
    # Warm up at the final num_ctx (loads the model) and calibrate chars per token on the filler.
    $cal = Invoke-RestMethod "$api/generate" -Method Post -ContentType 'application/json' -TimeoutSec 3600 `
        -Body (@{ model = $m; prompt = (New-Prompt 2000 4); stream = $false; options = @{ num_ctx = $numCtx; num_predict = 1 } } | ConvertTo-Json -Depth 4)
    $cpt = (New-Prompt 2000 4).Length / $cal.prompt_eval_count
    foreach ($size in $sizes) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $resp = Post @{ model = $m; prompt = (New-Prompt ($size - 64) $cpt); stream = $true; options = $opts }
        $reader = [IO.StreamReader]::new($resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult())
        $ttft = $null; $final = $null
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine(); if (-not $line) { continue }
            $chunk = $line | ConvertFrom-Json
            if (-not $ttft -and ($chunk.response -or $chunk.thinking)) { $ttft = $sw.Elapsed.TotalSeconds }
            if ($chunk.done) { $final = $chunk }
        }
        $reader.Dispose()
        $row = [pscustomobject]@{
            model          = $m
            prompt_tokens  = $final.prompt_eval_count
            ttft_s         = [math]::Round($ttft, 2)
            prefill_tok_s  = [math]::Round($final.prompt_eval_count / ($final.prompt_eval_duration / 1e9), 0)
            gen_tok_s      = [math]::Round($final.eval_count / ($final.eval_duration / 1e9), 1)
        }
        Write-Host ("{0,-50} {1,7} tok  TTFT {2,7}s  intake {3,6} tok/s  gen {4,5} tok/s" -f $m, $row.prompt_tokens, $row.ttft_s, $row.prefill_tok_s, $row.gen_tok_s)
        $rows += $row
        $rows | Export-Csv $Out -NoTypeInformation
    }
    Invoke-RestMethod "$api/generate" -Method Post -ContentType 'application/json' -Body (@{ model = $m; keep_alive = 0 } | ConvertTo-Json) | Out-Null
}
$rows | Format-Table -AutoSize
