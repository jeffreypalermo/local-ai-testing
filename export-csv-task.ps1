# Copies the CSV-parser coding task to %USERPROFILE%\llm-tasks\csv-parser so it can be run by hand.
$src = "$PSScriptRoot\agent-tasks\cs-feature"
$dst = "$env:USERPROFILE\llm-tasks\csv-parser"
$log = "$PSScriptRoot\export-csv-task.txt"
& {
    New-Item -ItemType Directory -Force "$env:USERPROFILE\llm-tasks" | Out-Null
    Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item "$src\repo" $dst -Recurse
    Copy-Item "$src\task.txt" "$dst\TASK.txt"
    Get-ChildItem $dst -Recurse -File | ForEach-Object FullName
    "dotnet on PATH: $((Get-Command dotnet -ErrorAction SilentlyContinue).Source)"
    Push-Location $dst; & dotnet run --project tests 2>&1 | Select-Object -Last 3; "baseline exit $LASTEXITCODE"; Pop-Location
    Remove-Item "$dst\src\bin", "$dst\src\obj", "$dst\tests\bin", "$dst\tests\obj" -Recurse -Force -ErrorAction SilentlyContinue
    'done'
} *> $log
