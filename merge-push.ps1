# Merges origin/master (e.g. results pushed from the remote computer) and pushes.
$git = 'C:\Program Files\Git\cmd\git.exe'
Set-Location $PSScriptRoot
# This folder's path is long, so some result files pass Windows' 260-character limit. Repo-local setting only.
& $git config core.longpaths true
# A first merge attempt (before longpaths) left partial copies of the incoming results folder, untracked here.
# Everything in it comes from origin/master, so remove it and let the merge write it again.
if (-not (& $git ls-files results-desktop-obs4pvu)) { Remove-Item -Recurse -Force results-desktop-obs4pvu -ErrorAction SilentlyContinue }
& $git status --short | Select-Object -First 10
& $git merge --no-edit origin/master
"merge exit $LASTEXITCODE"
if ($LASTEXITCODE -eq 0) { & $git push; "push exit $LASTEXITCODE" }
& $git log --oneline -3
