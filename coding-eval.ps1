# Offline coding eval for Ollama models.
# Short tasks: model writes C# / Python code, graded by unit tests (dotnet run / python -I).
# Long task: find and fix a bug hidden in a large generated C# codebase at -LongCtx tokens.
# Usage: .\coding-eval.ps1 -Models qwen3-coder-next:q8_0,gemma4:31b-it-bf16 -LongCtx 131072
param(
    [string[]]$Models = @('nemotron-3.5-lightning'),
    [int]$ShortCtx = 32768,
    [int]$LongCtx = 131072,      # 0 skips the long-context task
    [int]$NumPredict = 16384,
    [string]$Out = "$PSScriptRoot\coding-results.csv"
)

$api = 'http://localhost:11434/api'
$env:Path = "$env:ProgramFiles\dotnet;$env:Path"
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'; $env:DOTNET_NOLOGO = '1'
$work = "$env:LOCALAPPDATA\llm-eval"   # short path: MSBuild output trips MAX_PATH under deep folders
$csProj = "$work\cs"
$py = (Get-Command python -ErrorAction SilentlyContinue | Where-Object { $_.Source -notmatch 'WindowsApps' } | Select-Object -First 1).Source
if (-not $py) { $py = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe" -ErrorAction SilentlyContinue | Select-Object -Last 1 -ExpandProperty FullName }

# ---------- tasks ----------
$csRules = 'Respond with exactly one ```csharp code block containing the complete code (with any using directives). No Main method, no explanation.'
$pyRules = 'Respond with exactly one ```python code block containing the complete code (with any imports). No example usage, no explanation.'

$tasks = @(
    @{ id = 'cs-parens'; lang = 'cs'; prompt = "Write ``public static class Solution`` with ``public static bool IsValid(string s)`` returning true if every (), [], {} in s is correctly matched and nested. Other characters are ignored."
       test = @'
Check(Solution.IsValid("()[]{}")); Check(Solution.IsValid("{[()()]}")); Check(Solution.IsValid("a(b)c"));
Check(!Solution.IsValid("(]")); Check(!Solution.IsValid("([)]")); Check(!Solution.IsValid("((")); Check(!Solution.IsValid(")("));
Check(Solution.IsValid(""));
'@ }
    @{ id = 'cs-merge'; lang = 'cs'; prompt = "Write ``public static class Solution`` with ``public static List<int[]> Merge(List<int[]> intervals)`` that merges overlapping or touching closed intervals [start,end] and returns them sorted by start. Do not mutate the input."
       test = @'
string F(List<int[]> r) => string.Join(";", r.Select(x => x[0] + "," + x[1]));
Check(F(Solution.Merge(new List<int[]>{new[]{1,3},new[]{8,10},new[]{2,6},new[]{15,18}})) == "1,6;8,10;15,18");
Check(F(Solution.Merge(new List<int[]>{new[]{1,4},new[]{4,5}})) == "1,5");
Check(F(Solution.Merge(new List<int[]>{new[]{5,7},new[]{1,10}})) == "1,10");
Check(F(Solution.Merge(new List<int[]>())) == "");
'@ }
    @{ id = 'cs-roman'; lang = 'cs'; prompt = "Write ``public static class Solution`` with ``public static string ToRoman(int n)`` for 1 <= n <= 3999 using standard subtractive notation, and ``public static int FromRoman(string s)`` as its inverse."
       test = @'
Check(Solution.ToRoman(1994) == "MCMXCIV"); Check(Solution.ToRoman(3999) == "MMMCMXCIX"); Check(Solution.ToRoman(4) == "IV");
for (int i = 1; i <= 3999; i++) if (Solution.FromRoman(Solution.ToRoman(i)) != i) { Check(false); break; }
'@ }
    @{ id = 'cs-lru'; lang = 'cs'; prompt = "Write ``public class LruCache`` with constructor ``LruCache(int capacity)``, ``public int Get(int key)`` returning -1 if missing, and ``public void Put(int key, int value)``. Both operations must be O(1); evict the least recently used entry when over capacity. Get counts as a use."
       test = @'
var c = new LruCache(2); c.Put(1,1); c.Put(2,2); Check(c.Get(1)==1); c.Put(3,3); Check(c.Get(2)==-1);
c.Put(4,4); Check(c.Get(1)==-1); Check(c.Get(3)==3); Check(c.Get(4)==4); c.Put(4,40); Check(c.Get(4)==40);
var big = new LruCache(50000); var sw = System.Diagnostics.Stopwatch.StartNew();
for (int i = 0; i < 1000000; i++) { big.Put(i % 70000, i); big.Get(i % 50000); }
Check(sw.ElapsedMilliseconds < 5000);
'@ }
    @{ id = 'cs-inversions'; lang = 'cs'; prompt = "Write ``public static class Solution`` with ``public static long CountInversions(int[] a)`` returning the number of pairs i<j with a[i]>a[j]. Must handle 200,000 elements in well under a second. Do not mutate the input."
       test = @'
Check(Solution.CountInversions(new[]{2,4,1,3,5}) == 3); Check(Solution.CountInversions(new int[0]) == 0);
var desc = Enumerable.Range(0, 200000).Reverse().ToArray(); var copy = (int[])desc.Clone();
var sw = System.Diagnostics.Stopwatch.StartNew(); Check(Solution.CountInversions(desc) == 200000L*199999/2);
Check(sw.ElapsedMilliseconds < 2000); Check(desc.SequenceEqual(copy));
'@ }
    @{ id = 'cs-async'; lang = 'cs'; prompt = "Write ``public static class Solution`` with ``public static async Task<List<TOut>> MapConcurrent<TIn, TOut>(IEnumerable<TIn> items, Func<TIn, Task<TOut>> fn, int maxConcurrency)`` that runs fn over items with at most maxConcurrency calls in flight at once, and returns results in input order. If any call throws, the returned task must fault with that exception."
       test = @'
int inFlight = 0, peak = 0;
var r = Solution.MapConcurrent(Enumerable.Range(0, 40), async i => { var n = Interlocked.Increment(ref inFlight); lock (typeof(Program)) peak = Math.Max(peak, n); await Task.Delay(20 + (i % 3) * 10); Interlocked.Decrement(ref inFlight); return i * 2; }, 5).GetAwaiter().GetResult();
Check(r.SequenceEqual(Enumerable.Range(0, 40).Select(i => i * 2))); Check(peak <= 5 && peak >= 2);
bool threw = false; try { Solution.MapConcurrent(new[]{1,2,3}, async i => { await Task.Delay(5); if (i == 2) throw new InvalidOperationException("x"); return i; }, 2).GetAwaiter().GetResult(); } catch (InvalidOperationException) { threw = true; }
Check(threw);
'@ }
    @{ id = 'py-duration'; lang = 'py'; prompt = 'Write `def parse_duration(s: str) -> int` that converts strings like "1h30m", "45s", "2d3h4m5s", "90m" into total seconds. Units d,h,m,s appear at most once, in that order. Raise ValueError for empty or malformed input (e.g. "", "5", "1x", "1m1h", "h1").'
       test = @'
assert parse_duration("1h30m") == 5400
assert parse_duration("45s") == 45
assert parse_duration("2d3h4m5s") == 2*86400+3*3600+4*60+5
assert parse_duration("90m") == 5400
for bad in ["", "5", "1x", "1m1h", "h1", "1h1h"]:
    try:
        parse_duration(bad); assert False, bad
    except ValueError:
        pass
'@ }
    @{ id = 'py-topo'; lang = 'py'; prompt = 'Write `def topo_sort(graph: dict) -> list` where graph maps each node to a list of nodes it depends on (dependencies must come first). Nodes that appear only as dependencies are included too. Among nodes that are ready at the same time, output them in sorted order. Raise ValueError if there is a cycle.'
       test = @'
assert topo_sort({"app": ["lib", "log"], "lib": ["log"], "log": []}) == ["log", "lib", "app"]
assert topo_sort({"b": ["a"], "c": ["a"]}) == ["a", "b", "c"]
assert topo_sort({}) == []
try:
    topo_sort({"a": ["b"], "b": ["a"]}); assert False
except ValueError:
    pass
'@ }
    @{ id = 'py-dijkstra'; lang = 'py'; prompt = 'Write `def shortest_paths(n: int, edges: list, src: int) -> list` for a directed graph with nodes 0..n-1 and edges as (u, v, w) tuples with non-negative weights. Return a list of shortest distances from src, using float("inf") for unreachable nodes. Must be O((n+e) log n).'
       test = @'
assert shortest_paths(4, [(0,1,1),(1,2,2),(0,2,5)], 0) == [0,1,3,float("inf")]
assert shortest_paths(1, [], 0) == [0]
import random, time
random.seed(1); n = 100000
edges = [(i, i+1, 1) for i in range(n-1)] + [(random.randrange(n), random.randrange(n), random.randint(1, 100)) for _ in range(300000)]
t = time.time(); d = shortest_paths(n, edges, 0); assert d[n-1] <= n-1 and time.time() - t < 10
'@ }
    @{ id = 'py-flatten'; lang = 'py'; prompt = 'Write `def flatten(d: dict, sep: str = ".") -> dict` that flattens nested dicts into a single-level dict with joined keys, and `def unflatten(d: dict, sep: str = ".") -> dict` that reverses it. Lists are values, not nested. Empty nested dicts are preserved as values.'
       test = @'
src = {"a": 1, "b": {"c": 2, "d": {"e": [1, 2]}}, "f": {}}
flat = flatten(src)
assert flat == {"a": 1, "b.c": 2, "b.d.e": [1, 2], "f": {}}
assert unflatten(flat) == src
assert flatten({"x": {"y": 1}}, sep="/") == {"x/y": 1}
'@ }
    @{ id = 'py-rpn'; lang = 'py'; prompt = 'Write `def eval_expr(s: str) -> int` that evaluates an integer arithmetic expression with + - * / and parentheses, standard precedence, left associativity, unary minus, and whitespace. Division truncates toward zero. Do not use eval or exec.'
       test = @'
assert eval_expr("1 + 2 * 3") == 7
assert eval_expr("(1 + 2) * 3") == 9
assert eval_expr("7 / -2") == -3
assert eval_expr("-(2 + 3) * 2") == -10
assert eval_expr("10 - 2 - 3") == 5
assert eval_expr("2 * (3 + (4 - 1)) / 3") == 4
'@ }
    @{ id = 'py-ratelimit'; lang = 'py'; prompt = 'Write `class RateLimiter` with `__init__(self, limit: int, window: float)` and `allow(self, key: str, now: float) -> bool` implementing a sliding-window log: allow returns True and records the call if fewer than `limit` calls for `key` happened in the half-open window (now - window, now], else False. Timestamps for a key are non-decreasing. Memory per key must stay O(limit).'
       test = @'
r = RateLimiter(3, 10.0)
assert [r.allow("a", t) for t in [0, 1, 2, 3]] == [True, True, True, False]
assert r.allow("b", 3) is True
assert r.allow("a", 10.0) is True
assert r.allow("a", 10.5) is False
assert r.allow("a", 11.0) is True
'@ }
)

# ---------- harness ----------
function Invoke-Gen($body, [int]$timeout) {
    Invoke-RestMethod "$api/generate" -Method Post -ContentType 'application/json' -TimeoutSec $timeout `
        -Body ($body | ConvertTo-Json -Depth 4)
}

function Get-Code([string]$text) {
    $m = [regex]::Matches($text, '```[\w#+-]*\s*\r?\n([\s\S]*?)```')
    if ($m.Count) { ($m | Sort-Object { $_.Groups[1].Length } -Descending | Select-Object -First 1).Groups[1].Value } else { $text }
}

function Invoke-Proc($exe, $argList, $cwd, [int]$timeoutSec) {
    $p = Start-Process $exe -ArgumentList $argList -WorkingDirectory $cwd -NoNewWindow -PassThru `
        -RedirectStandardOutput "$cwd\stdout.txt" -RedirectStandardError "$cwd\stderr.txt"
    $null = $p.Handle   # PS 5.1: ExitCode is null unless the handle is opened before exit
    if (-not $p.WaitForExit($timeoutSec * 1000)) { $p.Kill(); return @{ ok = $false; log = 'timeout' } }
    $log = ((Get-Content "$cwd\stdout.txt" -Raw) + (Get-Content "$cwd\stderr.txt" -Raw))
    @{ ok = $p.ExitCode -eq 0; log = if ($log) { $log.Substring(0, [Math]::Min(400, $log.Length)) } else { '' } }
}

function Initialize-CsProject {
    if (Test-Path "$csProj\cs.csproj") { return }
    New-Item -ItemType Directory -Force $csProj | Out-Null
    @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings><Nullable>disable</Nullable>
    <TreatWarningsAsErrors>false</TreatWarningsAsErrors><NoWarn>CS1998;CS8981</NoWarn>
  </PropertyGroup>
</Project>
'@ | Set-Content "$csProj\cs.csproj" -Encoding utf8
}

function Test-CSharp([string]$code, [string]$test) {
    Initialize-CsProject
    Set-Content "$csProj\Solution.cs" $code -Encoding utf8
    @"
using System.Collections.Concurrent;
public static partial class Program {
    static int fails = 0;
    static void Check(bool ok, [System.Runtime.CompilerServices.CallerLineNumber] int line = 0) { if (!ok) { fails++; Console.WriteLine("FAIL line " + line); } }
    public static int Main() {
        try {
$test
        } catch (Exception e) { Console.WriteLine("EXCEPTION " + e.GetType().Name + ": " + e.Message); return 1; }
        return fails == 0 ? 0 : 1;
    }
}
"@ | Set-Content "$csProj\Program.cs" -Encoding utf8
    $b = Invoke-Proc 'dotnet' @('build', '-c', 'Release', '--nologo', '-v', 'q', '-clp:ErrorsOnly') $csProj 180
    if (-not $b.ok) { return @{ ok = $false; log = "build: " + $b.log } }
    Invoke-Proc 'dotnet' @('bin\Release\net10.0\cs.dll') $csProj 60
}

function Test-Python([string]$code, [string]$test) {
    $dir = "$work\py"; New-Item -ItemType Directory -Force $dir | Out-Null
    Set-Content "$dir\run_test.py" ($code + "`n`n" + $test + "`nprint('OK')`n") -Encoding utf8
    Invoke-Proc $py @('-I', 'run_test.py') $dir 60
}

# ---------- long-context bug hunt ----------
function New-Codebase([long]$chars) {
    $rnd = [Random]::new(42)
    $tpl = @(
        'public static class {0} {{ public static decimal Sum{1}(decimal[] a, decimal[] b) {{ decimal t = 0; for (int i = 0; i < a.Length; i++) t += a[i] * b[i] * {2}m; return t; }} }}',
        'public static class {0} {{ public static int Count{1}(IEnumerable<string> xs) {{ int n = 0; foreach (var x in xs) if (x.Length > {2}) n++; return n; }} }}',
        'public class {0} {{ private readonly Dictionary<string, int> _m = new(); public void Add{1}(string k) {{ _m[k] = _m.TryGetValue(k, out var v) ? v + {2} : {2}; }} public int Get(string k) => _m.TryGetValue(k, out var v) ? v : 0; }}',
        'public static class {0} {{ /// <summary>Applies rate {2} to every element.</summary> public static double[] Scale{1}(double[] xs) {{ var r = new double[xs.Length]; for (int i = 0; i < xs.Length; i++) r[i] = xs[i] * {2}; return r; }} }}',
        'public static class {0} {{ public static string Join{1}(IList<string> parts) {{ var sb = new System.Text.StringBuilder(); for (int i = 0; i < parts.Count; i++) {{ if (i > 0) sb.Append("-{2}-"); sb.Append(parts[i]); }} return sb.ToString(); }} }}'
    )
    $names = 'Order','Ledger','Shipment','Customer','Payroll','Inventory','Tax','Refund','Coupon','Account','Vendor','Report','Billing','Quote','Pricing'
    $suffix = 'Service','Helper','Calculator','Processor','Aggregator','Formatter','Validator','Mapper'
    $bug = @'
/// <summary>Computes an invoice total: sum of qty*price for every line, with a 10% discount when the subtotal is at least 1000.</summary>
public static class InvoiceCalculator {
    public static decimal Total(decimal[] qty, decimal[] price) {
        decimal subtotal = 0;
        for (int i = 0; i < qty.Length - 1; i++) subtotal += qty[i] * price[i];
        if (subtotal >= 1000m) subtotal *= 0.9m;
        return subtotal;
    }
}
'@
    $sb = [System.Text.StringBuilder]::new("// ===== Billing platform: core library =====`n")
    $i = 0; $inserted = $false
    while ($sb.Length -lt $chars) {
        if (-not $inserted -and $sb.Length -ge $chars * 0.5) { [void]$sb.Append($bug).Append("`n"); $inserted = $true }
        $name = $names[$rnd.Next($names.Count)] + $suffix[$rnd.Next($suffix.Count)] + $i
        [void]$sb.Append([string]::Format($tpl[$rnd.Next($tpl.Count)], $name, $i, $rnd.Next(1, 9))).Append("`n")
        $i++
    }
    $sb.ToString()
}

$longTest = @'
Check(InvoiceCalculator.Total(new[]{1m,2m}, new[]{10m,20m}) == 50m);
Check(InvoiceCalculator.Total(new[]{5m}, new[]{3m}) == 15m);
Check(InvoiceCalculator.Total(new decimal[0], new decimal[0]) == 0m);
Check(InvoiceCalculator.Total(new[]{10m,1m}, new[]{100m,50m}) == 945m);
Check(InvoiceCalculator.Total(new[]{1m}, new[]{999.99m}) == 999.99m);
'@

# ---------- run ----------
New-Item -ItemType Directory -Force $work | Out-Null
# Resume: keep rows already in $Out and skip those (model, task) pairs.
$results = @(if (Test-Path $Out) { Import-Csv $Out })
$done = @($results | ForEach-Object { "$($_.model)|$($_.task)" })
foreach ($m in $Models) {
    foreach ($t in $tasks) {
        if ($t.lang -eq 'py' -and -not $py) { continue }
        if ($done -contains "$m|$($t.id)") { continue }
        $rules = if ($t.lang -eq 'cs') { $csRules } else { $pyRules }
        $row = [ordered]@{ model = $m; task = $t.id; pass = $false; seconds = $null; tok_s = $null; log = $null }
        try {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $r = Invoke-Gen @{ model = $m; prompt = "$($t.prompt)`n`n$rules"; stream = $false
                               options = @{ num_ctx = $ShortCtx; temperature = 0; num_predict = $NumPredict } } 3600
            $row.seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
            $row.tok_s = [math]::Round($r.eval_count / ($r.eval_duration / 1e9), 1)
            $code = Get-Code $r.response
            $res = if ($t.lang -eq 'cs') { Test-CSharp $code $t.test } else { Test-Python $code $t.test }
            $row.pass = $res.ok; $row.log = ($res.log -replace '\s+', ' ').Trim()
        } catch { $row.log = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message } }
        Write-Host ("{0,-40} {1,-18} {2}" -f $m, $t.id, $(if ($row.pass) { 'PASS' } else { 'FAIL ' + $row.log }))
        $results += [pscustomobject]$row
        $results | Export-Csv $Out -NoTypeInformation
    }

    if ($LongCtx -gt 0 -and $done -notcontains "$m|cs-longctx-bugfix@$LongCtx") {
        $row = [ordered]@{ model = $m; task = "cs-longctx-bugfix@$LongCtx"; pass = $false; seconds = $null; tok_s = $null; log = $null }
        try {
            # Calibrate chars/token on generated code so the codebase fills ~90% of the window.
            $sample = New-Codebase 100000
            $cal = Invoke-Gen @{ model = $m; prompt = $sample; stream = $false; think = $false
                                 options = @{ num_ctx = $LongCtx; num_predict = 1 } } 3600
            $codebase = New-Codebase ([long](($LongCtx * 0.9 - 2000) * $sample.Length / $cal.prompt_eval_count))
            $prompt = "Below is a large C# codebase.`n`n``````csharp`n$codebase`n```````n`n" +
                      "Bug report: customers say invoices with several line items are under-billed - the last line item is never charged. " +
                      "Find the class responsible and return the complete corrected class. $csRules"
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $r = Invoke-Gen @{ model = $m; prompt = $prompt; stream = $false
                               options = @{ num_ctx = $LongCtx; temperature = 0; num_predict = $NumPredict } } 14400
            $row.seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
            $row.tok_s = [math]::Round($r.eval_count / ($r.eval_duration / 1e9), 1)
            $res = Test-CSharp (Get-Code $r.response) $longTest
            $row.pass = $res.ok
            $row.log = "prompt_tokens=$($r.prompt_eval_count) " + ($res.log -replace '\s+', ' ').Trim()
        } catch { $row.log = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message } }
        Write-Host ("{0,-40} {1,-18} {2}" -f $m, $row.task, $(if ($row.pass) { 'PASS' } else { 'FAIL ' + $row.log }))
        $results += [pscustomobject]$row
        $results | Export-Csv $Out -NoTypeInformation
    }
    try { Invoke-Gen @{ model = $m; keep_alive = 0 } 60 | Out-Null } catch {}
}

$results | Group-Object model | ForEach-Object {
    [pscustomobject]@{ model = $_.Name; passed = @($_.Group | Where-Object pass).Count; total = $_.Count }
} | Format-Table -AutoSize
Write-Host "Saved $Out"
