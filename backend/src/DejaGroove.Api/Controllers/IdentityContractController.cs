using DejaGroove.Api.Middleware;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace DejaGroove.Api.Controllers;

[ApiController]
[Route("v1/identity")]
public sealed class IdentityContractController : ControllerBase
{
    [Authorize(Policy = "IdentityContract")]
    [HttpGet("contract-probe")]
    public IActionResult GetContractProbe()
    {
        var requestId = HttpContext.Items[RequestIdMiddleware.RequestIdKey] is Guid g ? g : Guid.Empty;
        return Ok(new
        {
            request_id = requestId,
            subject = User.FindFirst("sub")?.Value,
            audience = User.FindFirst("aud")?.Value,
            issuer = User.FindFirst("iss")?.Value
        });
    }
}
