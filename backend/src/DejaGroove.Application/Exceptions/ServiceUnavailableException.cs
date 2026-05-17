namespace DejaGroove.Application.Exceptions;

public sealed class ServiceUnavailableException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}
