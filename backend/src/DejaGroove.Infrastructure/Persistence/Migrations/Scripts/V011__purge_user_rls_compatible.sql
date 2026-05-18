-- Blocker H2 (companion to V010): make purge_user work under FORCE RLS.
--
-- purge_user sets dejagroove.purge_user_id (transaction-local) so the
-- PERMISSIVE purge_* policies (V010) admit exactly the rows of the user being
-- erased — regardless of whether the definer happens to be a superuser. This
-- removes the previous reliance on owner/superuser RLS bypass, so erasure now
-- behaves identically in tests (superuser) and production (non-superuser
-- admin). dejagroove.suppress_audit still neutralises the V007 audit trigger
-- so erasing collection_records does not re-create audit rows.
--
-- Both GUCs are is_local = true: they live only for this transaction and can
-- never leak into normal application requests.
CREATE OR REPLACE FUNCTION purge_user(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM set_config('dejagroove.suppress_audit', 'on', true);
    PERFORM set_config('dejagroove.purge_user_id', p_user_id::text, true);

    DELETE FROM scan_results_cache           WHERE user_id = p_user_id;
    DELETE FROM scan_events                  WHERE user_id = p_user_id;
    DELETE FROM collection_idempotency_keys  WHERE user_id = p_user_id;
    DELETE FROM collection_audit_log         WHERE user_id = p_user_id;
    DELETE FROM collection_records           WHERE user_id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION purge_user(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION purge_user(UUID) TO deja_app;
