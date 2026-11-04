# Daily-use setup on this Ollama box:
#  - Ollama (the tray app's own server, which starts at login and is exposed to the LAN) defaults every
#    model to its largest tested context: OLLAMA_CONTEXT_LENGTH=1M, which Ollama caps at each model's limit.
#  - pi and opencode list every kept model at that context, with Nemotron 3.5 Super as the default.
# Writes a report to setup-daily.txt next to this script.
$root = $PSScriptRoot
$log = "$root\setup-daily.txt"
Set-Content $log "setup $(Get-Date -Format s)"
function Say($m) { Write-Host $m; Add-Content $log $m }
function Write-Json($path) { [IO.File]::WriteAllText($path, ($input | Out-String), [Text.UTF8Encoding]::new($false)) }

$default = 'nemotron-3.5-super:120b-a12b'
# id -> context window that passed the needle test fully on GPU.
$models = [ordered]@{
    'nemotron-3.5-super:120b-a12b'                     = 1048576
    'gpt-oss:120b'                                     = 131072
    'nemotron-3.5-lightning'                           = 1048576
    'qwen3.8-flash-next:q4_k_m'                        = 262144
    'qwen3.8:27b'                                      = 262144
    'frob/deepseek-v4-flash-0731:284b-a13b-ud-iq2_xxs' = 1048576
    'gemma4:31b-it-q8_0'                               = 262144
}

# 1) Ollama server settings (user environment; the tray app passes them to its server).
$envVars = [ordered]@{ OLLAMA_CONTEXT_LENGTH = '1048576'; OLLAMA_FLASH_ATTENTION = '1'; OLLAMA_KV_CACHE_TYPE = 'q8_0'; OLLAMA_MAX_LOADED_MODELS = '1' }
foreach ($k in $envVars.Keys) {
    [Environment]::SetEnvironmentVariable($k, $envVars[$k], 'User')
    Set-Item "env:$k" $envVars[$k]
    Say "env $k=$($envVars[$k])"
}
Remove-Item env:OLLAMA_HOST -ErrorAction SilentlyContinue   # let the app's "expose to network" setting decide

# 2) Replace the test server with the tray app's server.
Get-Process 'ollama app', 'ollama' -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 3
Start-Process "$env:LOCALAPPDATA\Programs\Ollama\ollama app.exe"
$up = $false
for ($i = 0; $i -lt 60 -and -not $up; $i++) { Start-Sleep 2; $up = try { [bool](Invoke-RestMethod http://127.0.0.1:11434/api/version -TimeoutSec 3) } catch { $false } }
Say "ollama app server up: $up"
$lan = try { (Invoke-RestMethod http://192.168.1.66:11434/api/version -TimeoutSec 5).version } catch { "FAILED: $($_.Exception.Message)" }
Say "reachable at 192.168.1.66:11434: $lan"

# 3) pi: model list, default model, PowerShell tools; plus a `pi` command on PATH.
$piDir = "$env:USERPROFILE\.pi\agent"
New-Item -ItemType Directory -Force $piDir | Out-Null
foreach ($f in 'models.json', 'settings.json') { if (Test-Path "$piDir\$f") { Copy-Item "$piDir\$f" "$piDir\$f.bak" -Force } }
$piModels = @(foreach ($id in $models.Keys) { [ordered]@{ id = $id; contextWindow = $models[$id]; maxTokens = 16384; input = @('text') } })
[ordered]@{
    '$schema' = 'https://pi.dev/schemas/models.schema.json'
    providers = @{ ollama = [ordered]@{ baseUrl = 'http://127.0.0.1:11434/v1'; api = 'openai-completions'; apiKey = 'ollama'; models = $piModels } }
} | ConvertTo-Json -Depth 8 | Write-Json "$piDir\models.json"
$settings = [ordered]@{}
if (Test-Path "$piDir\settings.json") { (Get-Content "$piDir\settings.json" -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $settings[$_.Name] = $_.Value } }
$settings['$schema'] = 'https://pi.dev/schemas/settings.schema.json'
$settings['defaultProvider'] = 'ollama'
$settings['defaultModel'] = $default
$settings['defaultTools'] = @('read', 'powershell', 'edit', 'write')
$settings | ConvertTo-Json -Depth 8 | Write-Json "$piDir\settings.json"
$piCli = "$env:LOCALAPPDATA\llm-eval\npm\node_modules\@earendil-works\pi-coding-agent\dist\cli.js"
New-Item -ItemType Directory -Force "$env:APPDATA\npm" | Out-Null
Set-Content "$env:APPDATA\npm\pi.cmd" "@node `"$piCli`" %*" -Encoding ASCII
Say "pi: wrote $piDir\models.json, settings.json, $env:APPDATA\npm\pi.cmd"

# 4) opencode: global config.
$ocDir = "$env:USERPROFILE\.config\opencode"
New-Item -ItemType Directory -Force $ocDir | Out-Null
if (Test-Path "$ocDir\opencode.jsonc") { Copy-Item "$ocDir\opencode.jsonc" "$ocDir\opencode.jsonc.bak" -Force }
$ocModels = [ordered]@{}
foreach ($id in $models.Keys) { $ocModels[$id] = [ordered]@{ name = $id; tool_call = $true; limit = [ordered]@{ context = $models[$id]; output = 16384 } } }
[ordered]@{
    '$schema' = 'https://opencode.ai/config.json'
    model     = "ollama/$default"
    provider  = @{ ollama = [ordered]@{ npm = '@ai-sdk/openai-compatible'; name = 'Ollama (this PC)'; options = @{ baseURL = 'http://127.0.0.1:11434/v1' }; models = $ocModels } }
} | ConvertTo-Json -Depth 8 | Write-Json "$ocDir\opencode.jsonc"
Say "opencode: wrote $ocDir\opencode.jsonc"

# 5) Check the context Ollama actually gives each model with no num_ctx set (what pi/opencode get).
foreach ($id in 'gpt-oss:120b', $default) {
    try {
        Invoke-RestMethod http://127.0.0.1:11434/api/generate -Method Post -ContentType 'application/json' -TimeoutSec 1800 `
            -Body (@{ model = $id; prompt = 'Say OK.'; stream = $false; think = $false; options = @{ num_predict = 4 } } | ConvertTo-Json) | Out-Null
        $ps = (Invoke-RestMethod http://127.0.0.1:11434/api/ps).models | Where-Object name -eq $id
        Say ("loaded {0}: context {1}, {2:N1} GB, {3:N0}% on GPU" -f $id, $ps.context_length, ($ps.size / 1GB), (100 * $ps.size_vram / $ps.size))
    } catch { Say "load $id FAILED: $($_.Exception.Message)" }
}
Say 'done'
