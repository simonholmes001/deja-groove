# Issue #101: iOS Auth Lifecycle Validation

## Scope
- Validate `DejaGrooveAuth.AuthSessionManager` lifecycle behavior for:
  - sign-in
  - restore
  - token refresh
  - expiry re-auth
  - sign-out
  - recovery after sign-out failure

## Verification Matrix
- Sign-in success persists session and sets authenticated state.
- Invalid provider session is rejected as provider configuration failure.
- Restore with missing session requires re-auth.
- Restore with expired token requires re-auth reason `tokenExpired`.
- Refresh from expired state re-authenticates when provider succeeds.
- Refresh failures force credential cleanup and re-auth.
- Sign-out clears session and sets re-auth reason `signedOut`.
- Sign-out clear failure blocks restore until a successful sign-in resets state.

## Automated Tests
- File: `ios/DejaGrooveAuth/Tests/DejaGrooveAuthTests/AuthSessionManagerTests.swift`
- Added case:
  - `Successful sign-in after sign-out failure clears restore block`

## Release Gate
- All lifecycle tests must pass before enabling External ID rollout for iOS.
