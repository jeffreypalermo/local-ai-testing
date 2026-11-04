# Writes the four agent tasks into .\agent-tasks\<id>\. Each task has:
#   repo\      the starting code the agent works in
#   grade\     canonical tests copied over the agent's copy before grading
#   task.txt   the prompt given to the agent
$root = "$PSScriptRoot\agent-tasks"
function Put($path, $text) {
    $full = Join-Path $root $path
    New-Item -ItemType Directory -Force (Split-Path $full) | Out-Null
    Set-Content $full $text -Encoding utf8
}

$csproj = @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>net10.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable></PropertyGroup>
</Project>
'@
$testsProj = @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable></PropertyGroup>
  <ItemGroup><ProjectReference Include="..\src\Lib.csproj" /></ItemGroup>
</Project>
'@
$checkHelper = @'
static int fails = 0;
static void Check(bool ok, string name) { Console.WriteLine((ok ? "PASS " : "FAIL ") + name); if (!ok) fails++; }
'@

# ---------- cs-bugfix: coupons are broken ----------
Put 'cs-bugfix\repo\src\Lib.csproj' $csproj
Put 'cs-bugfix\repo\src\Invoice.cs' @'
namespace Billing;

public record LineItem(string Sku, int Quantity, decimal UnitPrice);

public class Invoice
{
    public List<LineItem> Lines { get; } = new();
    public string? CouponCode { get; set; }

    public decimal Subtotal() => Lines.Sum(l => l.Quantity * l.UnitPrice);

    /// <summary>Subtotal minus coupon discount, plus 8.25% tax on the discounted amount, rounded half away from zero to cents.</summary>
    public decimal Total()
    {
        var subtotal = Subtotal();
        var taxable = subtotal - Discounts.For(CouponCode, subtotal);
        return Math.Round(taxable + Tax.On(taxable), 2, MidpointRounding.AwayFromZero);
    }
}
'@
Put 'cs-bugfix\repo\src\Discounts.cs' @'
namespace Billing;

/// <summary>
/// Coupon codes are case-insensitive.
/// SAVE10: 10% off. BULK50: $50 off when the subtotal is $500 or more. HALF: 50% off, capped at $100 off.
/// Unknown or missing codes give no discount.
/// </summary>
public static class Discounts
{
    public static decimal For(string? code, decimal subtotal) => code?.ToLowerInvariant() switch
    {
        "SAVE10" => subtotal * 0.10m,
        "BULK50" => subtotal > 500m ? 50m : 0m,
        "HALF" => Math.Min(subtotal * 0.5m, 100m),
        _ => 0m,
    };
}
'@
Put 'cs-bugfix\repo\src\Tax.cs' @'
namespace Billing;

public static class Tax
{
    public const decimal Rate = 0.0825m;
    public static decimal On(decimal amount) => amount * Rate;
}
'@
$csBugTests = @"
using Billing;
public static class Program
{
$checkHelper
    static Invoice Inv(string? coupon, params (int q, decimal p)[] lines)
    { var i = new Invoice { CouponCode = coupon }; foreach (var (q, p) in lines) i.Lines.Add(new LineItem("x", q, p)); return i; }

    public static int Main()
    {
        Check(Inv(null, (2, 10m), (1, 5m)).Total() == 27.06m, "no coupon");
        Check(Inv("save10", (2, 10m), (1, 5m)).Total() == 24.36m, "SAVE10 lowercase");
        Check(Inv("SAVE10", (2, 10m), (1, 5m)).Total() == 24.36m, "SAVE10 uppercase");
        Check(Inv("BULK50", (1, 500m)).Total() == 487.13m, "BULK50 at exactly 500");
        Check(Inv("bulk50", (1, 499.99m)).Total() == 541.24m, "BULK50 below threshold");
        Check(Inv("Half", (4, 100m)).Total() == 324.75m, "HALF capped at 100");
        Check(Inv("HALF", (1, 100m)).Total() == 54.13m, "HALF under cap");
        Check(Inv("NOPE", (2, 10m), (1, 5m)).Total() == 27.06m, "unknown coupon");
        return fails == 0 ? 0 : 1;
    }
}
"@
Put 'cs-bugfix\repo\tests\Tests.csproj' $testsProj
Put 'cs-bugfix\repo\tests\Program.cs' $csBugTests
Put 'cs-bugfix\grade\tests\Program.cs' $csBugTests
Put 'cs-bugfix\task.txt' 'The test suite in this repo is failing: customers report coupon codes do not work correctly. Run the tests with `dotnet run --project tests`, find the bugs in src/, and fix them. Do not modify the tests. Stop when all tests pass.'

# ---------- cs-feature: RFC 4180 CSV parser ----------
Put 'cs-feature\repo\src\Lib.csproj' $csproj
Put 'cs-feature\repo\src\Csv.cs' @'
namespace Text;

public static class Csv
{
    /// <summary>
    /// Parses RFC 4180 CSV text into rows of fields.
    /// - Fields are separated by commas; rows by LF or CRLF.
    /// - A field may be wrapped in double quotes; inside quotes, commas and line breaks are literal and "" is one quote.
    /// - Empty fields are preserved ("a,,b" has three fields).
    /// - A single trailing line break does not produce an extra empty row; empty input gives no rows.
    /// - Throws FormatException for an unterminated quoted field or a quote appearing inside an unquoted field.
    /// </summary>
    public static List<string[]> Parse(string text) => throw new NotImplementedException();
}
'@
$csFeatTests = @"
using Text;
public static class Program
{
$checkHelper
    static string Show(List<string[]> rows) => string.Join("|", rows.Select(r => string.Join(",", r.Select(f => "[" + f + "]"))));
    static bool Throws(string s) { try { Csv.Parse(s); return false; } catch (FormatException) { return true; } }

    public static int Main()
    {
        try
        {
            Check(Show(Csv.Parse("a,b,c\n1,2,3\n")) == "[a],[b],[c]|[1],[2],[3]", "simple LF");
            Check(Show(Csv.Parse("a,b\r\n1,2")) == "[a],[b]|[1],[2]", "CRLF, no trailing newline");
            Check(Show(Csv.Parse("a,,b\n")) == "[a],[],[b]", "empty field");
            Check(Show(Csv.Parse("\"x,y\",z")) == "[x,y],[z]", "quoted comma");
            Check(Show(Csv.Parse("\"say \"\"hi\"\"\",2")) == "[say \"hi\"],[2]", "escaped quotes");
            Check(Show(Csv.Parse("\"line1\nline2\",b\n")) == "[line1\nline2],[b]", "newline in quotes");
            Check(Show(Csv.Parse("a,\"\"\n")) == "[a],[]", "empty quoted field");
            Check(Csv.Parse("").Count == 0, "empty input");
            Check(Show(Csv.Parse("a\n\nb\n")) == "[a]|[]|[b]", "blank middle row is one empty field");
            Check(Throws("\"abc"), "unterminated quote throws");
            Check(Throws("ab\"c,d"), "stray quote throws");
        }
        catch (Exception e) { Console.WriteLine("EXCEPTION " + e.GetType().Name + ": " + e.Message); return 1; }
        return fails == 0 ? 0 : 1;
    }
}
"@
Put 'cs-feature\repo\tests\Tests.csproj' $testsProj
Put 'cs-feature\repo\tests\Program.cs' $csFeatTests
Put 'cs-feature\grade\tests\Program.cs' $csFeatTests
Put 'cs-feature\task.txt' 'Implement Csv.Parse in src/Csv.cs according to its doc comment. Run the tests with `dotnet run --project tests`. Do not modify the tests. Stop when all tests pass.'

# ---------- py-bugfix: pagination ----------
Put 'py-bugfix\repo\pager\__init__.py' @'
from .core import paginate

__all__ = ["paginate"]
'@
Put 'py-bugfix\repo\pager\core.py' @'
def paginate(items, page, per_page=10):
    """Return one page of `items`.

    Pages are 1-based. Returns a dict with:
      items        the items on that page (empty list if page is past the end)
      page         the requested page
      total_pages  number of pages (0 for an empty list)
      has_next     whether a later page exists
    Raises ValueError if page < 1 or per_page < 1.
    """
    if page < 0 or per_page < 1:
        raise ValueError("page and per_page must be >= 1")
    total_pages = len(items) // per_page
    start = page * per_page
    return {
        "items": list(items[start:start + per_page]),
        "page": page,
        "total_pages": total_pages,
        "has_next": page <= total_pages,
    }
'@
$pyBugTests = @'
import unittest
from pager import paginate


class PaginateTests(unittest.TestCase):
    def test_first_page(self):
        r = paginate(list(range(25)), 1, 10)
        self.assertEqual(r["items"], list(range(10)))
        self.assertEqual(r["total_pages"], 3)
        self.assertTrue(r["has_next"])

    def test_last_partial_page(self):
        r = paginate(list(range(25)), 3, 10)
        self.assertEqual(r["items"], [20, 21, 22, 23, 24])
        self.assertFalse(r["has_next"])

    def test_exact_multiple(self):
        r = paginate(list(range(20)), 2, 10)
        self.assertEqual(r["total_pages"], 2)
        self.assertFalse(r["has_next"])

    def test_past_end(self):
        self.assertEqual(paginate([1, 2], 5, 10)["items"], [])

    def test_empty(self):
        r = paginate([], 1, 10)
        self.assertEqual((r["items"], r["total_pages"], r["has_next"]), ([], 0, False))

    def test_invalid(self):
        for page, per in [(0, 10), (-1, 10), (1, 0)]:
            with self.assertRaises(ValueError):
                paginate([1], page, per)


if __name__ == "__main__":
    unittest.main()
'@
Put 'py-bugfix\repo\tests\__init__.py' ''
Put 'py-bugfix\repo\tests\test_pager.py' $pyBugTests
Put 'py-bugfix\grade\tests\test_pager.py' $pyBugTests
Put 'py-bugfix\task.txt' 'The tests in this repo are failing. Run them with `python -m unittest discover -s tests -t .`, find the bugs in pager/core.py, and fix them. Do not modify the tests. Stop when all tests pass.'

# ---------- py-feature: TTL + LRU cache ----------
Put 'py-feature\repo\ttlcache.py' @'
import time


class TTLCache:
    """A dict-like cache with a maximum size and a per-entry time-to-live.

    TTLCache(maxsize, ttl, clock=time.monotonic)
      set(key, value)    store or replace; resets that entry's expiry and makes it most recently used
      get(key, default=None)
                         return the value if present and not expired, else default;
                         a successful get makes the entry most recently used
      __len__()          number of entries that have not expired
      __contains__(key)  True if present and not expired
    An entry set at time t expires at t + ttl (it is expired when clock() >= t + ttl).
    When a set would exceed maxsize, expired entries are dropped first; if still full,
    the least recently used entry is evicted.
    All operations must be O(1) on average (amortized); do not scan all entries on every call.
    Raises ValueError if maxsize < 1 or ttl <= 0.
    """

    def __init__(self, maxsize, ttl, clock=time.monotonic):
        raise NotImplementedError
'@
$pyFeatTests = @'
import time
import unittest
from ttlcache import TTLCache


class Clock:
    def __init__(self):
        self.t = 0.0

    def __call__(self):
        return self.t


class TTLCacheTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()

    def test_basic_and_default(self):
        c = TTLCache(2, 10, self.clock)
        c.set("a", 1)
        self.assertEqual(c.get("a"), 1)
        self.assertEqual(c.get("zz", "dflt"), "dflt")
        self.assertIn("a", c)

    def test_expiry_boundary(self):
        c = TTLCache(2, 10, self.clock)
        c.set("a", 1)
        self.clock.t = 9.99
        self.assertEqual(c.get("a"), 1)
        self.clock.t = 10.0
        self.assertIsNone(c.get("a"))
        self.assertEqual(len(c), 0)

    def test_set_resets_expiry(self):
        c = TTLCache(2, 10, self.clock)
        c.set("a", 1)
        self.clock.t = 8
        c.set("a", 2)
        self.clock.t = 15
        self.assertEqual(c.get("a"), 2)

    def test_lru_eviction_respects_get(self):
        c = TTLCache(2, 100, self.clock)
        c.set("a", 1)
        c.set("b", 2)
        c.get("a")
        c.set("c", 3)
        self.assertNotIn("b", c)
        self.assertIn("a", c)
        self.assertIn("c", c)

    def test_expired_dropped_before_lru(self):
        c = TTLCache(2, 10, self.clock)
        c.set("old", 1)
        self.clock.t = 5
        c.set("new", 2)
        self.clock.t = 11
        c.set("x", 3)
        self.assertIn("new", c)
        self.assertIn("x", c)

    def test_invalid(self):
        for args in [(0, 1), (1, 0), (1, -1)]:
            with self.assertRaises(ValueError):
                TTLCache(*args)

    def test_performance(self):
        c = TTLCache(50000, 1e9, self.clock)
        start = time.perf_counter()
        for i in range(300000):
            c.set(i % 80000, i)
            c.get(i % 50000)
        self.assertLess(time.perf_counter() - start, 10)


if __name__ == "__main__":
    unittest.main()
'@
Put 'py-feature\repo\tests\__init__.py' ''
Put 'py-feature\repo\tests\test_ttlcache.py' $pyFeatTests
Put 'py-feature\grade\tests\test_ttlcache.py' $pyFeatTests
Put 'py-feature\task.txt' 'Implement TTLCache in ttlcache.py according to its docstring. Run the tests with `python -m unittest discover -s tests -t .`. Do not modify the tests. Stop when all tests pass.'

Write-Host "Tasks written to $root"
