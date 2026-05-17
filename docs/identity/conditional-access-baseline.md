# Issue #102: Conditional Access and Authentication Strength Baseline

## Policy Set (MVP)
1. `DG-CA-Require-Strong-Auth-For-App`
- Targets: Deja Groove API and iOS app registrations.
- Grant controls: require MFA/authentication strength compliant with tenant baseline.
- Session: default sign-in frequency (24h) unless stricter control required by risk.

2. `DG-CA-Block-Legacy-And-Unsupported-Clients`
- Block non-modern auth and unsupported grant paths.

3. `DG-CA-BreakGlass-Exclusion`
- Exclude emergency admin identities only.
- Access review and owner sign-off required each sprint.

## Verification Scenarios
- Compliant user can sign in and call protected endpoint.
- Non-compliant user is blocked or challenged per policy.
- Break-glass user can recover access during outage simulation.
- Policy rollback script/steps can restore previous known-good state.

## Evidence Required
- Screenshots or exports of each policy assignment and grant control.
- Test logs from positive and negative sign-in paths.
- Date-stamped decision record for go/no-go.

## Rollback
- Keep previous policy snapshots (JSON export).
- Reapply baseline snapshot if deny rates exceed thresholds defined in runbook.
