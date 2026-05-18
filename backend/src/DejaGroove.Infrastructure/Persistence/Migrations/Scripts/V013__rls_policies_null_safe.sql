-- Hardening (security-review follow-on): make every per-user RLS policy
-- null-safe against an empty-string GUC.
--
-- The V005/V009 policies cast current_setting('app.current_user_id', true)
-- directly to uuid. A custom GUC that was set with is_local=true and then
-- reset (the normal case on a pooled backend after a transaction) reads back
-- as '' rather than NULL, and ''::uuid raises 22P02 — turning any statement
-- evaluated without the GUC into a hard error instead of a clean "deny".
-- Wrapping in NULLIF(..., '') makes the predicate evaluate to NULL (deny),
-- preserving the intended fail-closed behaviour in every case.
--
-- Forward-only: the original policies are dropped and recreated rather than
-- editing the already-applied V005/V009 scripts.

DROP POLICY rls_collection_records          ON collection_records;
DROP POLICY rls_scan_events                 ON scan_events;
DROP POLICY rls_scan_results_cache          ON scan_results_cache;
DROP POLICY rls_collection_audit_log        ON collection_audit_log;
DROP POLICY rls_collection_idempotency_keys ON collection_idempotency_keys;

CREATE POLICY rls_collection_records ON collection_records
    TO deja_app
    USING      (user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid)
    WITH CHECK (user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid);

CREATE POLICY rls_scan_events ON scan_events
    TO deja_app
    USING      (user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid)
    WITH CHECK (user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid);

CREATE POLICY rls_scan_results_cache ON scan_results_cache
    TO deja_app
    USING      (user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid)
    WITH CHECK (user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid);

CREATE POLICY rls_collection_audit_log ON collection_audit_log
    TO deja_app
    USING      (user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid)
    WITH CHECK (user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid);

CREATE POLICY rls_collection_idempotency_keys ON collection_idempotency_keys
    TO deja_app
    USING      (user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid)
    WITH CHECK (user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid);
