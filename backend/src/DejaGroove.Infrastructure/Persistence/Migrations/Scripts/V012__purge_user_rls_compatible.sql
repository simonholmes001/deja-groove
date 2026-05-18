-- Blocker H2 (companion to V011): make purge_user work under FORCE RLS.
--
-- purge_user sets dejagroove.purge_user_id (transaction-local) so the
-- PERMISSIVE purge_* policies (V011) admit exactly the rows of the user being
-- erased — regardless of whether the definer happens to be a superuser. This
-- removes the previous reliance on owner/superuser RLS bypass, so erasure now
-- behaves identically in tests (superuser) and production (non-superuser
-- admin). dejagroove.suppress_audit still neutralises the V008 audit trigger
-- so erasing collection_records does not re-create audit rows.
--
-- Both GUCs are is_local = true: they live only for this transaction and can
-- never leak into normal application requests.
--
-- This is the authoritative purge_user. It is a strict superset of the V006
-- and V007 (scan-resolution) definitions: it erases every per-user table —
-- the scan-resolution set (V007) plus the collection/scan set plus the
-- idempotency keys (V010) — so a CREATE OR REPLACE here does not regress the
-- GDPR Article 17 guarantee. Deletion order respects FK chains
-- (children before parents).
CREATE OR REPLACE FUNCTION purge_user(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM set_config('dejagroove.suppress_audit', 'on', true);
    PERFORM set_config('dejagroove.purge_user_id', p_user_id::text, true);

    -- Scan-resolution domain (V007); FK children first.
    DELETE FROM scan_resolution_audit_log    WHERE user_id = p_user_id;
    DELETE FROM scan_resolutions             WHERE user_id = p_user_id;
    DELETE FROM scan_ambiguity_candidates    WHERE user_id = p_user_id;
    DELETE FROM scan_ambiguities             WHERE user_id = p_user_id;
    DELETE FROM scan_request_status          WHERE user_id = p_user_id;

    -- Collection / scan domain.
    DELETE FROM scan_results_cache           WHERE user_id = p_user_id;
    DELETE FROM scan_events                  WHERE user_id = p_user_id;
    DELETE FROM collection_idempotency_keys  WHERE user_id = p_user_id;
    DELETE FROM collection_audit_log         WHERE user_id = p_user_id;
    DELETE FROM collection_records           WHERE user_id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION purge_user(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION purge_user(UUID) TO deja_app;
