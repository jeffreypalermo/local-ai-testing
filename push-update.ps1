# Commits all changes in this folder and pushes them to origin/master.
param([Parameter(Mandatory)][string]$Message)
$git = 'C:\Program Files\Git\cmd\git.exe'
Set-Location $PSScriptRoot
& $git add -A
& $git -c core.safecrlf=false status --short
& $git commit -q -m "$Message`n`nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
& $git log --oneline -1
& $git push
"push exit $LASTEXITCODE"
