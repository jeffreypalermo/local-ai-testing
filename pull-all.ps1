# Pulls the large models with retries (a server restart or network blip aborts a pull; re-pulling resumes it),
# then runs the eval pipeline offline for anything not yet tested.
$ollama = "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe"
$env:OLLAMA_HOST = '127.0.0.1:11434'
$models = 'devstral-2:123b-instruct-2512-q4_K_M', 'nemotron-3.5-super:120b-a12b',
          'metalspork/qwen3.8-flash-next-ud:UD-Q3_K_XL', 'frob/deepseek-v4-flash-0731:284b-a13b-ud-iq2_xxs'
foreach ($m in $models) {
    for ($try = 1; $try -le 8; $try++) {
        & $ollama pull $m
        if ($LASTEXITCODE -eq 0) { break }
        Write-Host "$(Get-Date -Format 'HH:mm:ss') pull $m failed (try $try); retrying in 30s"
        Start-Sleep 30
    }
}
& "$PSScriptRoot\start.ps1" -SkipPull
