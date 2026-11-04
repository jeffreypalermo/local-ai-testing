# Builds qwen3.8-flash-next:q4_k_m from the already-downloaded shards. The first attempt (FROM shard 1 only)
# failed with "split GGUF has 1 shards, expected 4", so this lists every shard as its own FROM line.
$dir = "$env:USERPROFILE\models\Qwen3.8-Flash-Next-Q4_K_M"
$log = "$PSScriptRoot\create-flashnext-q4.txt"
$name = 'qwen3.8-flash-next:q4_k_m'
function Say($m) { $l = "$(Get-Date -Format 'HH:mm:ss') $m"; Write-Host $l; Add-Content $log $l }
$d = Get-PSDrive C
Say "C: free $([math]::Round($d.Free / 1e9)) GB"
Say "ollama $(& ollama --version)"

# No TEMPLATE: like the 3-bit build, Ollama uses the Jinja chat template embedded in the GGUF. (Copying that
# template into a Modelfile TEMPLATE fails, because TEMPLATE is parsed as a Go template.)
$mf = @(1..4 | ForEach-Object { "FROM $dir\Qwen3.8-Flash-Next-Q4_K_M-0000$_-of-00004.gguf" }) + @(
    "FROM $dir\mmproj-Qwen3.8-Flash-Next-f16.gguf"
    'PARAMETER top_p 0.95', 'PARAMETER temperature 1', 'PARAMETER top_k 20'
) -join "`n"
[IO.File]::WriteAllText("$dir\Modelfile", $mf, [Text.UTF8Encoding]::new($false))
Say "creating $name (4 shard FROM lines)"
& ollama create $name -f "$dir\Modelfile" 2>&1 | Select-Object -Last 5 | ForEach-Object { Say "  $_" }
Say "ollama create exit $LASTEXITCODE"
try {
    $s = Invoke-RestMethod http://127.0.0.1:11434/api/show -Method Post -ContentType 'application/json' -Body (@{ model = $name } | ConvertTo-Json)
    $ctx = ($s.model_info.PSObject.Properties | Where-Object Name -like '*.context_length').Value
    Say "capabilities: $($s.capabilities -join ', '); params: $($s.model_info.'general.parameter_count'); context: $ctx"
} catch { Say "show failed: $_" }
Say "C: free $([math]::Round((Get-PSDrive C).Free / 1e9)) GB"
Say 'done'
