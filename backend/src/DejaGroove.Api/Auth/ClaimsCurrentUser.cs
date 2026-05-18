using System.Security.Claims;
using DejaGroove.Application.Ports;
using DejaGroove.Domain.Shared;

namespace DejaGroove.Api.Auth;

/// <summary>
/// Resolves the authenticated caller from the validated JWT. The external
/// subject (Entra External ID <c>sub</c>) is mapped to a stable internal
/// UUID via <see cref="DeterministicUserId"/> — no users table, no first-call
/// write, same subject always yields the same id.
/// </summary>
public sealed class ClaimsCurrentUser(IHttpContextAccessor accessor) : ICurrentUser
{
    public string Subject =>
        accessor.HttpContext?.User.FindFirst("sub")?.Value
        ?? accessor.HttpContext?.User.FindFirst(ClaimTypes.NameIdentifier)?.Value
        ?? throw new InvalidOperationException("No authenticated subject on the request.");

    public Guid UserId => DeterministicUserId.FromSubject(Subject);
}
