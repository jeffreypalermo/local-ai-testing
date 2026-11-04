using Billing;
public static class Program
{
static int fails = 0;
static void Check(bool ok, string name) { Console.WriteLine((ok ? "PASS " : "FAIL ") + name); if (!ok) fails++; }
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
