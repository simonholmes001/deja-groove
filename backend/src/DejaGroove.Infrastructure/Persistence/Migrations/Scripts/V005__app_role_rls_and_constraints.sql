-- Application role with least-privilege DML rights.
-- The migration runner connects as the database owner (postgres / azure admin)
-- and retains CREATE/DROP. The application connects as deja_app with DML only.
-- At deploy time, grant this role to the actual login:
--   GRANT deja_app TO <connection_user>;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'deja_app') THEN
        CREATE ROLE deja_app NOLOGIN;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA public TO deja_app;

GRANT SELECT, INSERT, UPDATE, DELETE ON collection_records  TO deja_app;
GRANT SELECT, INSERT                 ON scan_events          TO deja_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON scan_results_cache  TO deja_app;
GRANT SELECT, INSERT                 ON collection_audit_log TO deja_app;

-- Row-Level Security.
-- The application sets SET LOCAL app.current_user_id = '<uuid>' at the start
-- of every transaction. Policies filter all DML to the current user's rows.
-- current_setting(..., true) returns NULL (not error) when the setting is absent,
-- which causes the policy to evaluate to FALSE — a safe fail-closed default.
ALTER TABLE collection_records  ENABLE ROW LEVEL SECURITY;
ALTER TABLE scan_events         ENABLE ROW LEVEL SECURITY;
ALTER TABLE scan_results_cache  ENABLE ROW LEVEL SECURITY;
ALTER TABLE collection_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_collection_records ON collection_records
    TO deja_app
    USING      (user_id = current_setting('app.current_user_id', true)::uuid)
    WITH CHECK (user_id = current_setting('app.current_user_id', true)::uuid);

CREATE POLICY rls_scan_events ON scan_events
    TO deja_app
    USING      (user_id = current_setting('app.current_user_id', true)::uuid)
    WITH CHECK (user_id = current_setting('app.current_user_id', true)::uuid);

CREATE POLICY rls_scan_results_cache ON scan_results_cache
    TO deja_app
    USING      (user_id = current_setting('app.current_user_id', true)::uuid)
    WITH CHECK (user_id = current_setting('app.current_user_id', true)::uuid);

CREATE POLICY rls_collection_audit_log ON collection_audit_log
    TO deja_app
    USING      (user_id = current_setting('app.current_user_id', true)::uuid)
    WITH CHECK (user_id = current_setting('app.current_user_id', true)::uuid);

-- Year plausibility guards.
-- The earliest commercially released recordings date to approximately 1860.
-- The upper bound is a rolling 5-year buffer to accommodate pre-announced releases.
ALTER TABLE collection_records
    ADD CONSTRAINT collection_records_year_check
    CHECK (year IS NULL OR year BETWEEN 1860 AND 2031);

ALTER TABLE scan_events
    ADD CONSTRAINT scan_events_year_check
    CHECK (year IS NULL OR year BETWEEN 1860 AND 2031);

-- collection_audit_log.collection_record_id intentionally has no FK constraint.
-- Audit logs are a denormalised, append-only record. The GDPR purge function
-- (V006) deletes audit rows explicitly before deleting collection_records rows,
-- so no FK cascade is needed. This avoids FK lock contention on high-volume
-- audit inserts and keeps the audit trail readable after soft-deletes.
