# Installs the tested versions of pi and opencode under %LOCALAPPDATA%\llm-eval (run while online).
$base = "$env:LOCALAPPDATA\llm-eval"
$env:Path = "$env:ProgramFiles\nodejs;$env:Path"
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
if (-not (Test-Path "$base\npm\node_modules\opencode-ai")) {
    npm install --prefix "$base\npm" @earendil-works/pi-coding-agent@1.5.0 opencode-ai@1.19.5
}
# The native binary comes from an optional dependency, which npm can skip; install it directly if missing.
function Find-Opencode { Get-ChildItem "$base\npm\node_modules" -Recurse -Filter opencode.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match "opencode-windows-$arch" } | Select-Object -First 1 }
if (-not (Find-Opencode)) { npm install --prefix "$base\npm" --no-save "opencode-windows-$arch@1.19.5" }
$oc = Find-Opencode
if ($oc) { Copy-Item $oc.FullName "$base\opencode.exe" -Force }
Write-Host "pi:       $(Test-Path "$base\npm\node_modules\@earendil-works\pi-coding-agent\dist\cli.js")"
Write-Host "opencode: $(Test-Path "$base\opencode.exe") $(if ($oc) { $oc.FullName; & "$base\opencode.exe" --version })"
