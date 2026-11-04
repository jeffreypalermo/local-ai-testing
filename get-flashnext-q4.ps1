# Downloads bartowski's Qwen3.8-Flash-Next Q4_K_M (sharded GGUF, which `ollama pull` can't fetch) and builds
# the Ollama model qwen3.8-flash-next:q4_k_m from it, reusing the 3-bit build's chat template and sampling
# settings so tool calls behave the same. Restartable: curl resumes partial files.
$repo = 'bartowski/Qwen3.8-Flash-Next-GGUF'
$dir = "$env:USERPROFILE\models\Qwen3.8-Flash-Next-Q4_K_M"
$log = "$PSScriptRoot\get-flashnext-q4.txt"
$name = 'qwen3.8-flash-next:q4_k_m'
function Say($m) { $l = "$(Get-Date -Format 'HH:mm:ss') $m"; Write-Host $l; Add-Content $log $l }
New-Item -ItemType Directory -Force $dir | Out-Null

$files = @(1..4 | ForEach-Object { "Qwen3.8-Flash-Next-Q4_K_M/Qwen3.8-Flash-Next-Q4_K_M-0000$_-of-00004.gguf" }) + 'mmproj-Qwen3.8-Flash-Next-f16.gguf'
$tree = (Invoke-RestMethod "https://huggingface.co/api/models/$repo/tree/main?recursive=true") | Where-Object type -eq 'file'
Say "downloading $($files.Count) files, $([math]::Round((($tree | Where-Object { $files -contains $_.path }).size | Measure-Object -Sum).Sum / 1e9, 1)) GB, to $dir"
# All files in parallel (one connection each ran at ~33 MB/s); the loop below then checks sizes and retries.
$procs = foreach ($f in $files) {
    $dest = Join-Path $dir (Split-Path $f -Leaf)
    $want = ($tree | Where-Object path -eq $f).size
    if ((Test-Path $dest) -and (Get-Item $dest).Length -eq $want) { continue }
    Start-Process curl.exe -NoNewWindow -PassThru -ArgumentList '-sS', '-L', '--fail', '--retry', '5', '--retry-delay', '10', '-C', '-', '-o', "`"$dest`"", "https://huggingface.co/$repo/resolve/main/$f"
}
$procs | ForEach-Object { $null = $_.Handle }
$procs | Wait-Process
Say 'parallel downloads finished; verifying'
foreach ($f in $files) {
    $dest = Join-Path $dir (Split-Path $f -Leaf)
    $want = ($tree | Where-Object path -eq $f).size
    for ($try = 1; $try -le 10 -and -not ((Test-Path $dest) -and (Get-Item $dest).Length -eq $want); $try++) {
        & curl.exe -L --fail --retry 5 --retry-delay 10 -C - -o $dest "https://huggingface.co/$repo/resolve/main/$f"
        if ($try -gt 1 -or $LASTEXITCODE) { Say "  $f curl exit $LASTEXITCODE (try $try)" }
    }
    $have = if (Test-Path $dest) { (Get-Item $dest).Length } else { 0 }
    if ($have -ne $want) { Say "FAILED $f ($have of $want bytes)"; exit 1 }
    Say "ok $f"
}

# Modelfile: same template and parameters as metalspork/qwen3.8-flash-next-ud:UD-Q3_K_XL.
$ref = Invoke-RestMethod http://127.0.0.1:11434/api/show -Method Post -ContentType 'application/json' -Body '{"model":"metalspork/qwen3.8-flash-next-ud:UD-Q3_K_XL"}'
if ($ref.template -match '"""') { Say 'FAILED: template contains """'; exit 1 }
$mf = @(
    "FROM $dir\Qwen3.8-Flash-Next-Q4_K_M-00001-of-00004.gguf"
    "FROM $dir\mmproj-Qwen3.8-Flash-Next-f16.gguf"
    "TEMPLATE `"`"`"$($ref.template)`"`"`""
    'PARAMETER top_p 0.95', 'PARAMETER temperature 1', 'PARAMETER top_k 20'
) -join "`n"
[IO.File]::WriteAllText("$dir\Modelfile", $mf, [Text.UTF8Encoding]::new($false))
Say "creating $name"
& ollama create $name -f "$dir\Modelfile"
Say "ollama create exit $LASTEXITCODE"
$s = Invoke-RestMethod http://127.0.0.1:11434/api/show -Method Post -ContentType 'application/json' -Body (@{ model = $name } | ConvertTo-Json)
Say "capabilities: $($s.capabilities -join ', '); params: $($s.model_info.'general.parameter_count'); context: $($s.model_info.'qwen4exp.context_length')"
Say 'done'
