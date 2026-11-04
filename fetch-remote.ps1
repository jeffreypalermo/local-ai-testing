# Shows what's on origin/master that this copy doesn't have yet.
$git = 'C:\Program Files\Git\cmd\git.exe'
Set-Location $PSScriptRoot
& $git fetch -q origin
& $git log --format='%h %an %ad %s' --date=iso HEAD..origin/master
& $git diff --stat HEAD...origin/master
'fetch done'
