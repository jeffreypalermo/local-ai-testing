# Agentic coding eval: the pi coding agent works on each task repo with a local Ollama model,
# then the canonical tests are restored and run to grade it. Fully offline.
# Usage: .\agent-eval.ps1 -Models qwen3-coder-next:q8_0 [-Tasks cs-bugfix,py-feature] [-TimeoutMin 15]
param(
    [string[]]$Models = @('nemotron-3.5-lightning'),
    [string[]]$Tasks = @('cs-bugfix', 'cs-feature', 'py-bugfix', 'py-feature'),
    [int]$TimeoutMin = 15,
    [ValidateSet('pi', 'opencode')][string]$Harness = 'pi',
    [string]$Out = "$PSScriptRoot\agent-results.csv"
)

$taskRoot = "$PSScriptRoot\agent-tasks"
$work = "$env:LOCALAPPDATA\llm-eval\agent"   # short path: MSBuild trips MAX_PATH under deep folders
$pyDir = Split-Path (Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe" | Select-Object -Last 1).FullName
$env:Path = "$pyDir;$env:ProgramFiles\dotnet;$env:ProgramFiles\nodejs;$env:APPDATA\npm;$env:Path"
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'; $env:DOTNET_NOLOGO = '1'; $env:PI_OFFLINE = '1'
# pi and its config live under %LOCALAPPDATA%\llm-eval so detached processes can see them.
$env:PI_CODING_AGENT_DIR = "$env:LOCALAPPDATA\llm-eval\pi-agent"
$pi = "$env:LOCALAPPDATA\llm-eval\npm\node_modules\@earendil-works\pi-coding-agent\dist\cli.js"
$opencode = "$env:LOCALAPPDATA\llm-eval\opencode.exe"   # copied there by install-harnesses.ps1
if ($Harness -eq 'pi' -and -not (Test-Path $pi)) { throw "pi not found at $pi" }
if ($Harness -eq 'opencode') {
    if (-not (Test-Path $opencode)) { throw "opencode not found at $opencode" }
    # Offline: no catalog fetch, updates, plugins, LSP downloads or project/Claude config discovery.
    foreach ($v in 'DISABLE_MODELS_FETCH', 'DISABLE_AUTOUPDATE', 'DISABLE_LSP_DOWNLOAD', 'DISABLE_CLAUDE_CODE',
                   'DISABLE_DEFAULT_PLUGINS', 'DISABLE_PROJECT_CONFIG', 'DISABLE_EXTERNAL_SKILLS') { Set-Item "env:OPENCODE_$v" '1' }
}

function Set-OpencodeConfig($m) {
    $env:OPENCODE_CONFIG_CONTENT = @{
        '$schema' = 'https://opencode.ai/config.json'; autoupdate = $false; share = 'disabled'
        provider = @{ ollama = @{ npm = '@ai-sdk/openai-compatible'; name = 'Ollama'
                                  options = @{ baseURL = 'http://127.0.0.1:11434/v1' }
                                  models = @{ $m = @{ name = $m; tool_call = $true; limit = @{ context = 65536; output = 16384 } } } } }
    } | ConvertTo-Json -Depth 8 -Compress
}

function Invoke-Proc($exe, $argList, $cwd, [int]$timeoutSec, $logBase) {
    $p = Start-Process $exe -ArgumentList $argList -WorkingDirectory $cwd -NoNewWindow -PassThru `
        -RedirectStandardOutput "$logBase.out.txt" -RedirectStandardError "$logBase.err.txt"
    $null = $p.Handle   # PS 5.1: ExitCode is null unless the handle is opened before exit
    if (-not $p.WaitForExit($timeoutSec * 1000)) {
        & taskkill /T /F /PID $p.Id *> $null
        return @{ ok = $false; timedOut = $true }
    }
    @{ ok = $p.ExitCode -eq 0; timedOut = $false }
}

function Get-Grade($dir, $id) {
    Copy-Item "$taskRoot\$id\grade\*" $dir -Recurse -Force   # undo any edits to the tests
    if ($id -like 'cs-*') {
        Remove-Item "$dir\src\bin", "$dir\src\obj", "$dir\tests\bin", "$dir\tests\obj" -Recurse -Force -ErrorAction SilentlyContinue
        Invoke-Proc 'dotnet' @('run', '--project', 'tests', '-c', 'Release') $dir 300 "$dir\..\$id.grade"
    } else {
        Invoke-Proc 'python' @('-m', 'unittest', 'discover', '-s', 'tests', '-t', '.') $dir 120 "$dir\..\$id.grade"
    }
}

$results = @(if (Test-Path $Out) { Import-Csv $Out })
$done = @($results | ForEach-Object { "$($_.model)|$($_.task)|$(if ($_.harness) { $_.harness } else { 'pi' })" })
foreach ($m in $Models) {
    $slug = ($m -replace '[^\w\.-]', '_') + $(if ($Harness -ne 'pi') { "-$Harness" })
    if ($Harness -eq 'opencode') { Set-OpencodeConfig $m }
    foreach ($id in $Tasks) {
        if ($done -contains "$m|$id|$Harness") { continue }
        $dir = "$work\$slug\$id"
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force $dir | Out-Null
        Copy-Item "$taskRoot\$id\repo\*" $dir -Recurse -Force
        $prompt = Get-Content "$taskRoot\$id\task.txt" -Raw

        $sw = [Diagnostics.Stopwatch]::StartNew()
        $quoted = '"' + ($prompt.Trim() -replace '"', '\"') + '"'
        $agent = if ($Harness -eq 'pi') {
            $agentArgs = @($pi, '--offline', '--no-session', '--provider', 'ollama', '--model', $m,
                           '--tools', 'read,powershell,edit,write', '-nc', '-ne', '-ns', '-np', '--no-mcp', '-p', $quoted)
            Invoke-Proc 'node' $agentArgs $dir ($TimeoutMin * 60) "$work\$slug\$id.agent"
        } else {
            Invoke-Proc $opencode @('run', '--pure', '--auto', '-m', "ollama/$m", '--dir', ".", $quoted) $dir ($TimeoutMin * 60) "$work\$slug\$id.agent"
        }
        $sw.Stop()
        $grade = Get-Grade $dir $id
        $gradeOut = (Get-Content "$work\$slug\$id.grade.out.txt", "$work\$slug\$id.grade.err.txt" -Raw -ErrorAction SilentlyContinue) -join ''
        $row = [pscustomobject][ordered]@{
            model     = $m
            harness   = $Harness
            task      = $id
            pass      = [bool]$grade.ok
            minutes   = [math]::Round($sw.Elapsed.TotalMinutes, 1)
            timed_out = $agent.timedOut
            checks    = "$(([regex]::Matches($gradeOut, '(?m)^PASS ')).Count) pass / $(([regex]::Matches($gradeOut, '(?m)^FAIL ')).Count) fail"
            detail    = (($gradeOut -split "`n" | Where-Object { $_ -match 'FAIL|Error|error CS|Traceback|EXCEPTION|OK|Ran ' } | Select-Object -First 4) -join ' ').Trim()
        }
        if ($id -like 'py-*') { $row.checks = ($gradeOut -split "`n" | Where-Object { $_ -match '^(OK|FAILED|Ran )' }) -join ' ' }
        Write-Host ("[{5}] {0,-45} {1,-11} {2,-5} {3,5} min  {4}" -f $m, $id, $(if ($row.pass) { 'PASS' } else { 'FAIL' }), $row.minutes, $row.checks, $Harness)
        $results += $row
        # Explicit columns: Export-Csv otherwise takes them from the first (older, harness-less) row.
        $results | Select-Object model, @{ n = 'harness'; e = { if ($_.harness) { $_.harness } else { 'pi' } } },
                                 task, pass, minutes, timed_out, checks, detail |
            Export-Csv $Out -NoTypeInformation
    }
    try { Invoke-RestMethod 'http://127.0.0.1:11434/api/generate' -Method Post -ContentType 'application/json' -Body (@{ model = $m; keep_alive = 0 } | ConvertTo-Json) | Out-Null } catch {}
}
$results | Group-Object model, harness | ForEach-Object {
    [pscustomobject]@{ model = $_.Name; passed = @($_.Group | Where-Object { $_.pass -eq $true -or $_.pass -eq 'True' }).Count; total = $_.Count; minutes = [math]::Round(($_.Group | Measure-Object minutes -Sum).Sum, 1) }
} | Format-Table -AutoSize
