-- Issue #15: per-user idempotency keys for the collection write path.
--
-- A key is bound to exactly one created record and to a fingerprint of the
-- originating request. Replay with the same key + fingerprint returns the
-- prior record; the same key with a different fingerprint is a conflict.
-- Written in the same transaction as the collection_records INSERT so a
-- committed record can never be observed without its idempotency key.
CREATE TABLE collection_idempotency_keys (
    user_id              UUID        NOT NULL,
    idempotency_key      TEXT        NOT NULL,
    request_fingerprint  TEXT        NOT NULL,
    collection_record_id UUID        NOT NULL,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (user_id, idempotency_key)
);

-- Least-privilege DML for the application role (mirrors V005). No UPDATE/DELETE:
-- an idempotency binding is immutable once written.
GRANT SELECT, INSERT ON collection_idempotency_keys TO deja_app;

-- Row-Level Security, consistent with every other application table.
ALTER TABLE collection_idempotency_keys ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_collection_idempotency_keys ON collection_idempotency_keys
    TO deja_app
    USING      (user_id = current_setting('app.current_user_id', true)::uuid)
    WITH CHECK (user_id = current_setting('app.current_user_id', true)::uuid);

-- GDPR erasure must also clear idempotency keys for the user.
CREATE OR REPLACE FUNCTION purge_user(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM set_config('dejagroove.suppress_audit', 'on', true);

    DELETE FROM scan_results_cache           WHERE user_id = p_user_id;
    DELETE FROM scan_events                  WHERE user_id = p_user_id;
    DELETE FROM collection_idempotency_keys  WHERE user_id = p_user_id;
    DELETE FROM collection_audit_log         WHERE user_id = p_user_id;
    DELETE FROM collection_records           WHERE user_id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION purge_user(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION purge_user(UUID) TO deja_app;
