-- Issue #46 follow-on: keep GDPR erasure (V006 purge_user) total.
--
-- V008 added an AFTER DELETE audit trigger on collection_records. Without this
-- change, purging a user would DELETE their collection_records and the trigger
-- would immediately re-insert audit rows referencing the just-erased data —
-- defeating Article 17 erasure. We set dejagroove.suppress_audit for the
-- duration of the purge transaction so the trigger is a no-op during erasure.
-- The flag is transaction-local (is_local = true) and never leaks to normal
-- application writes.

CREATE OR REPLACE FUNCTION purge_user(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM set_config('dejagroove.suppress_audit', 'on', true);

    DELETE FROM scan_results_cache   WHERE user_id = p_user_id;
    DELETE FROM scan_events          WHERE user_id = p_user_id;
    DELETE FROM collection_audit_log WHERE user_id = p_user_id;
    DELETE FROM collection_records   WHERE user_id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION purge_user(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION purge_user(UUID) TO deja_app;
