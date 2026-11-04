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
