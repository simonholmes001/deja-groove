using DejaGroove.Api.Errors;
using Microsoft.AspNetCore.Http;

namespace DejaGroove.Api.Tests.Errors;

public sealed class ApiErrorCatalogTests
{
    [Theory]
    [InlineData(StatusCodes.Status400BadRequest, "validation_error", false)]
    [InlineData(StatusCodes.Status401Unauthorized, "unauthorized", false)]
    [InlineData(StatusCodes.Status404NotFound, "not_found", false)]
    [InlineData(StatusCodes.Status409Conflict, "conflict", false)]
    [InlineData(StatusCodes.Status429TooManyRequests, "rate_limited", true)]
    [InlineData(StatusCodes.Status502BadGateway, "bad_gateway", true)]
    [InlineData(StatusCodes.Status503ServiceUnavailable, "service_unavailable", true)]
    [InlineData(StatusCodes.Status504GatewayTimeout, "timeout", true)]
    public void FromStatusCode_ReturnsExpectedContract(int statusCode, string code, bool retryable)
    {
        var error = ApiErrorCatalog.FromStatusCode(statusCode);

        Assert.Equal(statusCode, error.StatusCode);
        Assert.Equal(code, error.Code);
        Assert.Equal(retryable, error.Retryable);
        Assert.NotEmpty(error.Message);
    }
}
