# Issue #8: Token Refresh and Re-Authentication Flow

Satisfies the acceptance criterion *"Token refresh/re-auth flows documented"*.
Backend issuer/audience/expiry validation and `sub`→user mapping are covered by
[jwt-claim-contract.md](jwt-claim-contract.md) (#100). This document covers the
**iOS client** side delivered in #8.

## Components

| Component | Responsibility |
|---|---|
| `PkceCodeVerifier` / `PkceChallenge` | RFC 7636 verifier + S256 challenge (pure, no platform deps). |
| `EntraTokenProvider` | OAuth 2.0 Authorization Code + PKCE sign-in and refresh-token grant against Entra External ID. ROPC is intentionally unsupported. |
| `AuthorizationCodeRequesting` | Browser-leg seam (production: `ASWebAuthenticationSession`; tests: fake). |
| `KeychainSessionStore` | Persists the session (`WhenUnlockedThisDeviceOnly`, non-syncing). |
| `AuthSessionManager` | State machine: sign-in, restore, refresh, expiry re-auth, sign-out. |
| `AuthenticatedApiClientFactory` | Binds `currentAccessToken()` into `LiveApiClient`'s bearer provider. |

## Sign-in (interactive, PKCE)

1. `EntraTokenProvider.signInInteractively()` generates a random code verifier
   and a CSRF `state` token.
2. Builds the `/oauth2/v2.0/authorize` URL with `code_challenge`,
   `code_challenge_method=S256`, `state`, and the configured scopes
   (`openid offline_access api://…`).
3. `AuthorizationCodeRequesting` presents the system browser; the redirect
   returns `code` + `state`.
4. **State is verified** against the expected value (mismatch ⇒
   `providerConfiguration`, treated as a CSRF/interception failure).
5. The code is exchanged at `/oauth2/v2.0/token` (`grant_type=authorization_code`)
   with the matching `code_verifier`.
6. The session (access token + ~90-day refresh token) is stored in the Keychain.

## Refresh (silent)

- `AuthSessionManager.currentAccessToken()` is called per outbound API request.
- If the access token is expired and the state is authenticated (or
  `reauthenticationRequired(.tokenExpired)`), `refreshIfNeeded()` performs a
  `grant_type=refresh_token` exchange and persists the rotated session.
- A structurally invalid or expired refreshed token forces credential cleanup
  and transitions to `reauthenticationRequired(.refreshFailed)`.

## Re-authentication triggers

| Trigger | State / reason |
|---|---|
| No stored session on launch | `reauthenticationRequired(.missingSession)` |
| Stored token expired, refresh fails | `reauthenticationRequired(.refreshFailed)` |
| Stored session structurally invalid | `reauthenticationRequired(.invalidStoredSession)` |
| Keychain read failure on restore | `reauthenticationRequired(.sessionStoreFailure)` |
| Token endpoint returns 400/401 | `AuthOnboardingError.invalidCredentials` → re-auth |
| Sign-out | `reauthenticationRequired(.signedOut)` |
| Sign-out Keychain clear failed | restore blocked until next successful sign-in |

## Token endpoint error mapping

| HTTP from token endpoint | Mapped error |
|---|---|
| 2xx | success |
| 400 / 401 | `invalidCredentials` (expired/revoked grant) |
| other non-2xx | `providerConfiguration` |
| transport throw | `networkUnavailable` |

## Security properties

- Refresh token never leaves the Keychain except in the token request body
  over TLS to the configured Entra authority.
- No client-side signature validation — the API performs full JWT validation
  (#100); the client reads only the `sub` claim as a local scoping/display key.
- Unauthenticated requests send no `Authorization` header, so the API rejects
  them at the edge (401) per the `IdentityContract` policy.

## Configuration (`EntraConfig`)

`authority` (CIAM tenant URL), `clientID`, `redirectURI` (custom scheme,
e.g. `msauth.com.dejagroove.app://auth`), and `scopes`. Supplied at app
composition time; no secrets are embedded (public client + PKCE).
