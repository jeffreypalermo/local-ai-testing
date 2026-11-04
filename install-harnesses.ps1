# Installs pi and opencode under %LOCALAPPDATA%\llm-eval\npm (run while online).
$base = "$env:LOCALAPPDATA\llm-eval"
$env:Path = "$env:ProgramFiles\nodejs;$env:Path"
if (-not (Test-Path "$base\npm\node_modules\opencode-ai")) {
    npm install --prefix "$base\npm" @earendil-works/pi-coding-agent opencode-ai
}
# The native binary comes from an optional dependency, which npm can skip; install it directly if missing.
function Find-Opencode { Get-ChildItem "$base\npm\node_modules" -Recurse -Filter opencode.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match 'opencode-windows-arm64' } | Select-Object -First 1 }
if (-not (Find-Opencode)) { npm install --prefix "$base\npm" --no-save opencode-windows-arm64@1.19.5 }
$oc = Get-ChildItem "$base\npm\node_modules" -Recurse -Filter opencode.exe -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -match 'opencode-windows-arm64' } | Select-Object -First 1
if ($oc) { Copy-Item $oc.FullName "$base\opencode.exe" -Force }
Write-Host "pi:       $(Test-Path "$base\npm\node_modules\@earendil-works\pi-coding-agent\dist\cli.js")"
Write-Host "opencode: $(Test-Path "$base\opencode.exe") $(if ($oc) { $oc.FullName; & "$base\opencode.exe" --version })"
