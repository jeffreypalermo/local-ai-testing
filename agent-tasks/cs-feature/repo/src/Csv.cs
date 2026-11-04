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
