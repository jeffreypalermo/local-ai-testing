using System.Collections.Concurrent;
public static partial class Program {
    static int fails = 0;
    static void Check(bool ok, [System.Runtime.CompilerServices.CallerLineNumber] int line = 0) { if (!ok) { fails++; Console.WriteLine("FAIL line " + line); } }
    public static int Main() {
        try {
Check(true);
        } catch (Exception e) { Console.WriteLine("EXCEPTION " + e.GetType().Name + ": " + e.Message); return 1; }
        return fails == 0 ? 0 : 1;
    }
}
