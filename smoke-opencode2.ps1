# Second opencode run, to separate first-run setup time from normal response time.
$log = "$PSScriptRoot\smoke-opencode2.txt"
Set-Location "$env:LOCALAPPDATA\llm-eval\smoke"
& {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & opencode run "Reply with exactly: OPENCODE_OK"
    "opencode exit $LASTEXITCODE in $([int]$sw.Elapsed.TotalSeconds)s"
    Get-ChildItem "$env:USERPROFILE\.config\opencode\node_modules" -Directory -Name -ErrorAction SilentlyContinue
    'done'
} *> $log
