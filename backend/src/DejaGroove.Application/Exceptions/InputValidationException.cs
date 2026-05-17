namespace DejaGroove.Application.Exceptions;

public sealed class InputValidationException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}
