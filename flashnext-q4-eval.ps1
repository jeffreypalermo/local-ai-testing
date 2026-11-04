# Full test of qwen3.8-flash-next:q4_k_m (bartowski Q4_K_M), same tests as the other models:
# context test first (does it fit fully on the GPU, and at what context), then pi, opencode and time to first token.
$root = $PSScriptRoot
$m = 'qwen3.8-flash-next:q4_k_m'
$log = "$root\flashnext-q4-eval.log"
function Say($t) { $l = "$(Get-Date -Format 'HH:mm:ss') $t"; Write-Host $l; Add-Content $log $l }
Say "start $m"
& "$root\bench.ps1" -Models $m -Contexts 262144, 131072, 65536 -Out "$root\ctx-qwen3.8-flash-next_q4_k_m.csv" *>> $log
Say 'context test done'
& "$root\agent-eval.ps1" -Models $m -Harness pi *>> $log
Say 'pi done'
& "$root\agent-eval.ps1" -Models $m -Harness opencode *>> $log
Say 'opencode done'
& "$root\ttft.ps1" -Models $m -Out "$root\ttft-results.csv" *>> $log
Say 'ttft done'
Say 'done'
