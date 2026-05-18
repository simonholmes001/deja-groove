-- Blocker C1: enforce RLS at the database floor.
--
-- PostgreSQL skips RLS for a table's OWNER unless FORCE ROW LEVEL SECURITY is
-- set. Migrations run as the database owner, so without FORCE the entire
-- tenant-isolation model depended on the unenforced, untested assumption that
-- the runtime login is never the owner/superuser. FORCE removes that single
-- point of failure: the per-user policies now apply even to the owner.
ALTER TABLE collection_records          FORCE ROW LEVEL SECURITY;
ALTER TABLE scan_events                 FORCE ROW LEVEL SECURITY;
ALTER TABLE scan_results_cache          FORCE ROW LEVEL SECURITY;
ALTER TABLE collection_audit_log        FORCE ROW LEVEL SECURITY;
ALTER TABLE collection_idempotency_keys FORCE ROW LEVEL SECURITY;

-- Blocker H2: keep GDPR erasure working once RLS is forced.
--
-- purge_user() is SECURITY DEFINER and runs as the owner. With FORCE enabled
-- the owner is now subject to RLS, and the existing rls_* policies are scoped
-- TO deja_app — so the owner would match no policy and purge_user would
-- silently delete zero rows, breaking Article 17 erasure.
--
-- These additional PERMISSIVE policies are scoped TO PUBLIC (every role,
-- including the owner) and only grant visibility to rows of the single user
-- currently being purged, identified by a transaction-local GUC that is set
-- exclusively by purge_user (V012). When the GUC is unset OR has been reset
-- to an empty string (a pooled backend that previously set it), NULLIF makes
-- the predicate NULL (never true), so these policies grant nothing and normal
-- app traffic is unaffected (multiple permissive policies are OR-combined).
CREATE POLICY purge_collection_records ON collection_records
    AS PERMISSIVE FOR DELETE TO PUBLIC
    USING (user_id = NULLIF(current_setting('dejagroove.purge_user_id', true), '')::uuid);

CREATE POLICY purge_scan_events ON scan_events
    AS PERMISSIVE FOR DELETE TO PUBLIC
    USING (user_id = NULLIF(current_setting('dejagroove.purge_user_id', true), '')::uuid);

CREATE POLICY purge_scan_results_cache ON scan_results_cache
    AS PERMISSIVE FOR DELETE TO PUBLIC
    USING (user_id = NULLIF(current_setting('dejagroove.purge_user_id', true), '')::uuid);

CREATE POLICY purge_collection_audit_log ON collection_audit_log
    AS PERMISSIVE FOR DELETE TO PUBLIC
    USING (user_id = NULLIF(current_setting('dejagroove.purge_user_id', true), '')::uuid);

CREATE POLICY purge_collection_idempotency_keys ON collection_idempotency_keys
    AS PERMISSIVE FOR DELETE TO PUBLIC
    USING (user_id = NULLIF(current_setting('dejagroove.purge_user_id', true), '')::uuid);
