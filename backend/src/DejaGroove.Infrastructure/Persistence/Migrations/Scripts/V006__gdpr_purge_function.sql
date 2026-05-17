-- GDPR Article 17 (Right to Erasure) purge procedure.
-- Hard-deletes all personal data for a user across all tables.
-- Called by the DELETE /v1/account endpoint after identity verification.
--
-- Deletion order matters: audit log and cache before collection_records
-- to avoid any FK-style dependency issues and to ensure clean erasure.
--
-- SECURITY DEFINER: the function runs as its owner (the migration admin role),
-- which bypasses RLS. This is intentional — the app role (deja_app) is granted
-- EXECUTE so it can trigger erasure, but the function itself runs with elevated
-- rights to delete across all user rows regardless of the session context.
CREATE OR REPLACE FUNCTION purge_user(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM scan_results_cache  WHERE user_id = p_user_id;
    DELETE FROM scan_events         WHERE user_id = p_user_id;
    DELETE FROM collection_audit_log WHERE user_id = p_user_id;
    DELETE FROM collection_records  WHERE user_id = p_user_id;
END;
$$;

-- Restrict direct invocation: only the app role may call this function.
REVOKE ALL ON FUNCTION purge_user(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION purge_user(UUID) TO deja_app;
