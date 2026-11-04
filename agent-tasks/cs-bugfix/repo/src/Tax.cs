namespace Billing;

public static class Tax
{
    public const decimal Rate = 0.0825m;
    public static decimal On(decimal amount) => amount * Rate;
}
