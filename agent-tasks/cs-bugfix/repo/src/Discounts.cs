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
