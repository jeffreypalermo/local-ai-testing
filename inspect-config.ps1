# Read-only: reports what the real (unsandboxed) shell sees for pi, opencode and Ollama settings.
$out = "$PSScriptRoot\inspect-config.txt"
& {
    '== where'; where.exe pi; where.exe opencode
    '== pi version'; try { & pi --version } catch { $_.Exception.Message }
    '== opencode version'; try { & opencode --version } catch { $_.Exception.Message }
    '== ~/.pi'; Get-ChildItem "$env:USERPROFILE\.pi" -Recurse -File -ErrorAction SilentlyContinue | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize | Out-String -Width 250
    foreach ($f in 'models.json', 'settings.json') { $p = "$env:USERPROFILE\.pi\agent\$f"; if (Test-Path $p) { "== $p"; Get-Content $p -Raw } }
    '== ~/.config/opencode'; Get-ChildItem "$env:USERPROFILE\.config\opencode" -File -ErrorAction SilentlyContinue | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize | Out-String -Width 250
    $oc = "$env:USERPROFILE\.config\opencode\opencode.jsonc"; if (Test-Path $oc) { "== $oc"; Get-Content $oc -Raw }
    '== user env OLLAMA_*'; foreach ($n in 'OLLAMA_HOST', 'OLLAMA_CONTEXT_LENGTH', 'OLLAMA_FLASH_ATTENTION', 'OLLAMA_KV_CACHE_TYPE', 'OLLAMA_MAX_LOADED_MODELS', 'OLLAMA_KEEP_ALIVE') { "$n=" + [Environment]::GetEnvironmentVariable($n, 'User') }
    '== ollama app config'; Get-ChildItem "$env:LOCALAPPDATA\Ollama", "$env:APPDATA\Ollama" -File -ErrorAction SilentlyContinue | Select-Object FullName, Length | Format-Table -AutoSize | Out-String -Width 250
    '== startup'; Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" -Name -ErrorAction SilentlyContinue
} *> $out
