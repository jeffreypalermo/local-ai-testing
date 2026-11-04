# Runs the coding tests (pi and opencode) and the time-to-first-token test from this computer against an
# Ollama server elsewhere on the network. The agent's tools, builds and tests run here; only the model runs
# on the server. Results go to results-<this computer>\ so they don't mix with the server's own results.
# Restartable: finished tasks and models are skipped.
# Uses its own pinned copies of pi and opencode (install-harnesses.ps1) with their own config folder, so any
# pi/opencode you've already set up on this computer is left alone.
# Usage: .\remote-eval.ps1 [-Url http://192.168.1.66:11434] [-Models a,b] [-Harnesses pi,opencode]
#                          [-Tasks cs-bugfix,...] [-SkipTtft] [-Context]
param(
    [string]$Url = 'http://192.168.1.66:11434',
    [string[]]$Models = @('nemotron-3.5-super:120b-a12b', 'qwen3.8:27b', 'gpt-oss:120b',
                          'qwen3.8-flash-next:q4_k_m', 'nemotron-3.5-lightning'),
    [string[]]$Harnesses = @('pi', 'opencode'),
    [string[]]$Tasks = @('cs-bugfix', 'cs-feature', 'py-bugfix', 'py-feature'),
    [switch]$SkipTtft,
    [switch]$Context   # also re-run the needle-in-a-haystack test at each model's tested max (slow: up to hours)
)
$root = $PSScriptRoot
$env:LLM_EVAL_OLLAMA_URL = $Url.TrimEnd('/')
$out = "$root\results-$($env:COMPUTERNAME.ToLower())"
New-Item -ItemType Directory -Force $out | Out-Null
function Log($msg) { $line = "$(Get-Date -Format 'HH:mm:ss') $msg"; Write-Host $line; Add-Content "$out\run.log" $line }
function Slug($m) { $m -replace '[^\w\.-]', '_' }

# Fail fast if the server or a model is missing.
$tags = try { (Invoke-RestMethod "$Url/api/tags" -TimeoutSec 10).models.name } catch { throw "Can't reach Ollama at ${Url}: $($_.Exception.Message)" }
$missing = @($Models | Where-Object { $tag = if ($_ -match ':') { $_ } else { "${_}:latest" }; $tags -notcontains $tag })
if ($missing) { throw "Not on the server: $($missing -join ', ')" }
Log "server $Url ($((Invoke-RestMethod "$Url/api/version").version)), models: $($Models -join ', ')"

foreach ($m in $Models) {
    foreach ($h in $Harnesses) {
        Log "coding ($h) $m"
        & "$root\agent-eval.ps1" -Models $m -Harness $h -Tasks $Tasks -Out "$out\agent-results.csv" *>> "$out\agent-$(Slug $m).log"
    }
}
if (-not $SkipTtft) {
    Log 'time to first token'
    & "$root\ttft.ps1" -Models $Models -Out "$out\ttft-results.csv" *>> "$out\ttft.log"
}
if ($Context) {
    # Largest context each model passed on the server itself.
    $max = @{ 'nemotron-3.5-super:120b-a12b' = 1048576; 'nemotron-3.5-lightning' = 1048576; 'gpt-oss:120b' = 131072
              'qwen3.8:27b' = 262144; 'metalspork/qwen3.8-flash-next-ud:UD-Q3_K_XL' = 262144; 'qwen3.8-flash-next:q4_k_m' = 262144
              'frob/deepseek-v4-flash-0731:284b-a13b-ud-iq2_xxs' = 1048576; 'gemma4:31b-it-q8_0' = 262144 }
    foreach ($m in $Models) {
        $file = "$out\ctx-$(Slug $m).csv"
        if ((Test-Path $file) -or -not $max[$m]) { continue }
        Log "context $m at $($max[$m])"
        & "$root\bench.ps1" -Models $m -Contexts $max[$m] -Out $file *> "$out\ctx-$(Slug $m).log"
    }
}

# Summary: tasks passed within 15 minutes, total minutes for those, and time to first token.
$rows = @(if (Test-Path "$out\agent-results.csv") { Import-Csv "$out\agent-results.csv" })
$ttft = @(if (Test-Path "$out\ttft-results.csv") { Import-Csv "$out\ttft-results.csv" })
function T($m, $n) { ($ttft | Where-Object { $_.model -eq $m -and [int]$_.prompt_tokens -ge $n * 0.8 -and [int]$_.prompt_tokens -le $n * 1.2 } | Select-Object -First 1).ttft_s }
$summary = foreach ($m in $Models) {
    $o = [ordered]@{ model = $m }
    foreach ($h in $Harnesses) {
        $ok = @($rows | Where-Object { $_.model -eq $m -and $_.harness -eq $h -and $_.pass -eq 'True' -and [double]$_.minutes -le 15 })
        $o[$h] = "$($ok.Count)/$(@($rows | Where-Object { $_.model -eq $m -and $_.harness -eq $h }).Count)"
        $o["${h}_min"] = [math]::Round((($ok | ForEach-Object { [double]$_.minutes }) | Measure-Object -Sum).Sum, 1)
    }
    $o['ttft_4k_s'] = T $m 4096; $o['ttft_32k_s'] = T $m 32768; $o['ttft_128k_s'] = T $m 131072
    [pscustomobject]$o
}
$summary | Format-Table -AutoSize | Out-String -Width 250 | Tee-Object -FilePath "$out\summary.txt"
Log 'done'
