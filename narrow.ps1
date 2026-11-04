# Coding-first narrowing (replaces run-all's per-model order). Restartable: finished work is skipped.
#   1) pi coding gate on untested models; anything under 3/4 is dropped
#   2) context sweep only for survivors, starting at each model's own context limit
#   3) opencode only for the top 3 finalists
$root = $PSScriptRoot
$results = "$root\agent-results.csv"
# Gemma runs at q8: the bf16 build generated too slowly (bandwidth-bound) to finish turns inside the time limit.
$candidates = 'qwen3-coder-next:q8_0', 'devstral-2:123b-instruct-2512-q4_K_M',
              'nemotron-3.5-super:120b-a12b', 'metalspork/qwen3.8-flash-next-ud:UD-Q3_K_XL',
              'frob/deepseek-v4-flash-0731:284b-a13b-ud-iq2_xxs', 'gemma4:31b-it-q8_0', 'gpt-oss:120b'

# pi reads its model list from here; refresh it from the copy kept with these scripts.
New-Item -ItemType Directory -Force "$env:LOCALAPPDATA\llm-eval\pi-agent" | Out-Null
Copy-Item "$root\pi-models.json" "$env:LOCALAPPDATA\llm-eval\pi-agent\models.json" -Force
# Already gated earlier; still eligible as finalists. Dropped: qwen3-coder 30B (tool-call glitches),
# qwen2.5-14b-1m (outdated), nemotron-3-nano (weaker coder than Lightning at the same 500K context).
$tested = 'nemotron-3.5-lightning', 'qwen3.8:27b'

function Log($msg) { $line = "$(Get-Date -Format 'HH:mm:ss') $msg"; Write-Host $line; Add-Content "$root\run-all.log" $line }
function Slug($m) { $m -replace '[^\w\.-]', '_' }
# A task counts as passed if any attempt passed within the 15-minute limit (the user's usability bar).
function Score($m, $h) {
    @(Import-Csv $results | Where-Object { $_.model -eq $m -and $_.harness -eq $h -and $_.pass -eq 'True' -and [double]$_.minutes -le 15 } |
      Select-Object -ExpandProperty task -Unique).Count
}
function Wait-Model($m) {
    $tag = if ($m -match ':') { $m } else { "${m}:latest" }
    for ($i = 0; $i -lt 90; $i++) {
        if ((Invoke-RestMethod http://127.0.0.1:11434/api/tags).models.name -contains $tag) { return $true }
        if ($i -eq 0) { Log "waiting for $m to finish downloading" }
        Start-Sleep 60
    }
    $false
}
function MaxCtx($m) {
    $rows = foreach ($f in "$root\ctx-$(Slug $m).csv", "$root\ctx-$(Slug $m)-ext.csv") { if (Test-Path $f) { Import-Csv $f } }
    ($rows | Where-Object { $_.pass -eq 'True' } | ForEach-Object { [int]$_.num_ctx } | Measure-Object -Maximum).Maximum
}
function NativeCtx($m) {
    $s = Invoke-RestMethod http://127.0.0.1:11434/api/show -Method Post -ContentType 'application/json' -Body (@{ model = $m } | ConvertTo-Json)
    [int]($s.model_info.PSObject.Properties | Where-Object Name -like '*.context_length' | Select-Object -First 1).Value
}

# 1) Coding gate with pi.
foreach ($m in $candidates) {
    if (-not (Wait-Model $m)) { Log "skip $m (not downloaded)"; continue }
    Log "gate (pi) $m"
    & "$root\agent-eval.ps1" -Models $m -Harness pi -Out $results *>> "$root\agent-$(Slug $m).log"
}
function Best($m) { [Math]::Max((Score $m 'pi'), (Score $m 'opencode')) }
$survivors = @($tested + $candidates | Where-Object { (Best $_) -ge 3 })
Log "survivors: $($survivors -join ', ')"

# 2) Context sweep for survivors, from the model's own limit downward (skips steps it cannot reach).
foreach ($m in $survivors) {
    $native = NativeCtx $m
    $steps = @(1048576, 786432, 500000, 262144, 131072, 65536 | Where-Object { $_ -le $native })
    $file = if ($native -gt 500000) { "$root\ctx-$(Slug $m)-ext.csv" } else { "$root\ctx-$(Slug $m).csv" }
    $have = if (Test-Path $file) { @(Import-Csv $file) } else { @() }
    if ($have | Where-Object { $_.pass -eq 'True' }) { continue }
    $todo = @($steps | Where-Object { $have.num_ctx -notcontains "$_" })
    if (-not $todo) { continue }
    Log "context sweep $m from $($todo[0])"
    & "$root\bench.ps1" -Models $m -Contexts $todo -Out $file *> "$root\ctx-$(Slug $m)-narrow.log"
    if ($have) { ($have + @(Import-Csv $file)) | Export-Csv $file -NoTypeInformation }
}

# Kept selectable in pi/opencode, but no further testing (user's call, 2026-11-04): both scored 3/4
# and were the slowest models.
$omit = 'frob/deepseek-v4-flash-0731:284b-a13b-ud-iq2_xxs', 'gemma4:31b-it-q8_0'
$active = @($survivors | Where-Object { $omit -notcontains $_ })

# 3) opencode for every active model with a perfect score in either harness (context size is not a cut).
$finalists = $active | Where-Object { (Best $_) -ge 4 }
Log "finalists: $($finalists -join ', ')"
foreach ($m in $finalists) {
    Log "opencode $m"
    & "$root\agent-eval.ps1" -Models $m -Harness opencode -Out $results *>> "$root\agent-$(Slug $m).log"
}

# 4) Time to first token / prompt intake speed for the models that passed the coding gate.
Log 'ttft'
& "$root\ttft.ps1" -Models $active -Out "$root\ttft-results.csv" *>> "$root\ttft.log"
$ttft = @(Import-Csv "$root\ttft-results.csv")
function TTFT($m, $n) { ($ttft | Where-Object { $_.model -eq $m -and [int]$_.prompt_tokens -ge $n * 0.8 -and [int]$_.prompt_tokens -le $n * 1.2 } | Select-Object -First 1).ttft_s }

$survivors | ForEach-Object {
    [pscustomobject]@{ model = $_; pi = Score $_ 'pi'; opencode = Score $_ 'opencode'; max_ctx = MaxCtx $_
                       ttft_32k_s = TTFT $_ 32768; ttft_128k_s = TTFT $_ 131072 }
} | Sort-Object { -[Math]::Max($_.pi, $_.opencode) }, { -$_.max_ctx } | Format-Table -AutoSize | Tee-Object -FilePath "$root\narrow-summary.txt"
Log 'narrowing done'
