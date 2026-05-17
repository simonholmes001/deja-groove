-- Application role with least-privilege DML rights.
-- Migrations run as the database owner (postgres / Azure admin) using the
-- ConnectionStrings:PostgresAdmin connection string. The deja_app role is a
-- NOLOGIN group role; the actual login user (provisioned by IaC) must be
-- granted membership before the application can connect:
--   GRANT deja_app TO <iac_provisioned_login>;
-- That grant is performed by the database provisioning step (Bicep/IaC),
-- not by migrations, because the login name is environment-specific.
-- The runtime application connection (ConnectionStrings:Postgres) will be
-- wired to the least-privilege login by the repository layer.
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
-- Lower bound: earliest commercially released recordings (~1860).
-- Upper bound: far-future sentinel to reject obviously invalid data (e.g. year 0,
-- year 9999). Not a business rule — legitimate future releases are always within
-- this range. Raise in a future migration if required.
ALTER TABLE collection_records
    ADD CONSTRAINT collection_records_year_check
    CHECK (year IS NULL OR year BETWEEN 1860 AND 2100);

ALTER TABLE scan_events
    ADD CONSTRAINT scan_events_year_check
    CHECK (year IS NULL OR year BETWEEN 1860 AND 2100);

-- collection_audit_log.collection_record_id intentionally has no FK constraint.
-- Audit logs are a denormalised, append-only record. The GDPR purge function
-- (V006) deletes audit rows explicitly before deleting collection_records rows,
-- so no FK cascade is needed. This avoids FK lock contention on high-volume
-- audit inserts and keeps the audit trail readable after soft-deletes.
