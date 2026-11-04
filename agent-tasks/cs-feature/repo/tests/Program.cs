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
