# Issue #103: Identity Failure Modes Runbook and Alert Thresholds

## Alert Catalog
1. `IdentityJwtValidationFailureSpike`
- Signal: count of 401s on `/v1/identity/*` and protected endpoints due to token validation.
- Threshold: >5% of auth requests for 10 minutes.
- Severity: Sev2.

2. `IdentitySigningKeyConfigurationFailure`
- Signal: startup/runtime auth failures caused by invalid/missing signing key configuration.
- Threshold: 3 consecutive startup failures or sustained auth failures >5 minutes after config rollout.
- Severity: Sev1.

3. `ConditionalAccessDenySpike`
- Signal: external ID/CA deny events.
- Threshold: deny count > 3x 7-day same-hour baseline for 15 minutes.
- Severity: Sev2.

4. `iOSRefreshFailureSpike`
- Signal: refresh failures from iOS telemetry.
- Threshold: >10% refresh failures over 15 minutes.
- Severity: Sev2.

## KQL Starters
```kql
requests
| where timestamp > ago(15m)
| where name has "/v1/identity" or name has "/v1/scan"
| summarize total=count(), unauthorized=countif(resultCode == "401")
| extend unauthorizedRate = todouble(unauthorized) / iif(total == 0, 1, total)
```

```kql
traces
| where timestamp > ago(15m)
| where message has "JWT authentication failed"
| summarize failures=count() by bin(timestamp, 5m)
```

## Operator Actions
1. Validate whether failure is configuration, token issuance, or provider outage.
2. Confirm blast radius by tenant/app/environment.
3. If CA-related, temporarily apply documented rollback snapshot.
4. If signing-key/config rollout issue is confirmed, roll back to last known-good secret version and recycle instances.
5. Escalate to security owner when Sev1/Sev2 thresholds sustain for two windows.

## Post-Incident
- Capture root cause, impacted user count, and recovery timeline.
- Add or tune alert thresholds if false-positive/negative observed.
