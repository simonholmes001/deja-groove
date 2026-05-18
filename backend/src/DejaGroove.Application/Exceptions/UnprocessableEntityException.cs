namespace DejaGroove.Application.Exceptions;

public sealed class UnprocessableEntityException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}
