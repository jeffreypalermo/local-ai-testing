# Pushes using GitHub's device sign-in: the terminal shows a code to enter at github.com/login/device
# from any device. The settings are for this repo only (not global).
$git = 'C:\Program Files\Git\cmd\git.exe'
Set-Location $PSScriptRoot
& $git config credential.gitHubAuthModes device
& $git config credential.guiPrompt false
& $git push -u origin master
"push exit $LASTEXITCODE"
