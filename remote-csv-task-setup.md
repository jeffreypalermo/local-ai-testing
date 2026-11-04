Set up a small C# coding exercise on this computer so I can hand it to a coding agent. Don't solve the exercise; only set it up.

## 1. Prerequisites
- The .NET 10 SDK must be installed (`dotnet --list-sdks` shows a 10.x entry). If it's missing, install it with this OS's normal package manager (winget `Microsoft.DotNet.SDK.10` on Windows, Homebrew `dotnet-sdk` on macOS, or Microsoft's packages or `dotnet-install` script on Linux).
- git must be installed.

## 2. Create the project
Create a folder named `llm-tasks/csv-parser` in my home directory (`%USERPROFILE%\llm-tasks\csv-parser` on Windows). If it already exists, stop and ask me. Create these four files with exactly this content:

`src/Lib.csproj`
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>net10.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable></PropertyGroup>
</Project>
```

`src/Csv.cs`
```csharp
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
```

`tests/Tests.csproj`
```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable></PropertyGroup>
  <ItemGroup><ProjectReference Include="..\src\Lib.csproj" /></ItemGroup>
</Project>
```

`tests/Program.cs`
```csharp
using Text;
public static class Program
{
static int fails = 0;
static void Check(bool ok, string name) { Console.WriteLine((ok ? "PASS " : "FAIL ") + name); if (!ok) fails++; }
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
```

Also create `TASK.txt` containing this one line:
```
Implement Csv.Parse in src/Csv.cs according to its doc comment. Run the tests with `dotnet run --project tests`. Do not modify the tests. Stop when all tests pass.
```

## 3. Verify and save a baseline
- In the folder, run `dotnet run --project tests`. It must build and then print `EXCEPTION NotImplementedException: ...`. That's the expected starting state, so don't fix it.
- Add a `.gitignore` containing `bin/` and `obj/`, then run `git init`, `git add -A` and `git commit -m "baseline"`, so the exercise can be reset with `git reset --hard; git clean -fdx`.

Report the folder path, the .NET SDK version, and the output of the baseline test run.
