# Issue #100: External ID JWT Claim Contract

## API Summary
- Consumer: `DejaGroove.Api` authenticated endpoints.
- Contract probe endpoint: `GET /v1/identity/contract-probe`.
- Authentication scheme: `Bearer` JWT.

## Contract Specification
- Required claims:
  - `iss` must match issuer from configured identity provider authority/metadata.
  - `aud` must equal configured `IdentityJwt:Audience`.
  - subject identity must be present and non-empty (`sub`, or mapped `nameidentifier`).
  - `exp` must be valid and in the future.
- Signature:
  - JWT signature must validate using provider signing keys resolved from OIDC metadata/JWKS.
- Clock skew:
  - Controlled by `IdentityJwt:ClockSkewSeconds`.

## Compatibility and Versioning Policy
- Claim requirements are additive-only after launch unless a breaking-change release note is published.
- `IdentityJwt:Authority` and `IdentityJwt:Audience` are environment-specific configuration, not code constants.

## Operational Behavior
- Invalid token behavior: `401 Unauthorized`.
- Auth failures are logged with path, exception type, and configured authority/audience context.
- Request correlation: `X-Request-Id` response header via request middleware.

## Test Evidence
- API contract tests in `backend/tests/DejaGroove.Api.Tests/Auth/JwtClaimContractTests.cs` validate:
  - valid token accepted
  - wrong audience rejected
  - wrong issuer rejected
  - expired token rejected
  - missing `sub` denied at policy/endpoint level (`backend/tests/DejaGroove.Api.Tests/Auth/IdentityContractEndpointTests.cs`)
