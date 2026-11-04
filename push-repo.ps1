# Commits this folder and pushes it to the (empty) GitHub repo's default branch, master.
$git = 'C:\Program Files\Git\cmd\git.exe'
Set-Location $PSScriptRoot
if (-not (Test-Path .git)) { & $git init -b master }
& $git config user.name 'Jeffrey Palermo'
& $git config user.email 'jeffrey@clear-measure.com'
& $git config core.autocrlf true
& $git add -A
& $git status --short | Measure-Object | ForEach-Object { "files staged: $($_.Count)" }
$msg = @'
Local AI coding-model evaluation on an Ollama box

Scripts, task sources, raw results and logs from testing local models for
agentic coding with pi and opencode: a coding gate, a needle-in-a-haystack
context test and time-to-first-token measurements. Also includes the
daily-use setup script and prompts for configuring other computers.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
'@
& $git commit -q -m $msg
& $git log --oneline -1
if (-not (& $git remote)) { & $git remote add origin https://github.com/jeffreypalermo/local-ai-testing.git }
& $git push -u origin master
"push exit $LASTEXITCODE"
