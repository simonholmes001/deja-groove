CREATE TABLE scan_request_status (
    user_id         UUID        NOT NULL,
    request_id      UUID        NOT NULL,
    result_status   TEXT        NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, request_id),
    CONSTRAINT scan_request_status_result_status_check
        CHECK (result_status IN ('Owned', 'SafeToBuy', 'Ambiguous', 'NoMatch'))
);

CREATE TABLE scan_ambiguities (
    user_id         UUID        NOT NULL,
    request_id      UUID        NOT NULL,
    confidence      REAL        NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, request_id)
);

CREATE TABLE scan_ambiguity_candidates (
    user_id                 UUID        NOT NULL,
    request_id              UUID        NOT NULL,
    ordinal                 SMALLINT    NOT NULL,
    mbid                    TEXT,
    discogs_release_id      TEXT,
    title                   TEXT,
    artist                  TEXT,
    year                    SMALLINT,
    PRIMARY KEY (user_id, request_id, ordinal),
    CONSTRAINT scan_ambiguity_candidates_ordinal_check CHECK (ordinal BETWEEN 1 AND 3),
    CONSTRAINT scan_ambiguity_candidates_identity_check CHECK (
        mbid IS NOT NULL
        OR discogs_release_id IS NOT NULL
        OR (title IS NOT NULL AND artist IS NOT NULL)
    ),
    CONSTRAINT fk_scan_ambiguity_candidates_parent
        FOREIGN KEY (user_id, request_id) REFERENCES scan_ambiguities (user_id, request_id) ON DELETE CASCADE
);

CREATE TABLE scan_resolutions (
    user_id                 UUID        NOT NULL,
    request_id              UUID        NOT NULL,
    selected_mbid           TEXT,
    selected_discogs_release_id TEXT,
    result_status           TEXT        NOT NULL,
    confidence              REAL        NOT NULL,
    album_mbid              TEXT,
    album_discogs_release_id TEXT,
    album_title             TEXT,
    album_artist            TEXT,
    album_year              SMALLINT,
    collection_record_id    UUID,
    resolved_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, request_id),
    CONSTRAINT fk_scan_resolutions_request
        FOREIGN KEY (user_id, request_id) REFERENCES scan_request_status (user_id, request_id) ON DELETE CASCADE,
    CONSTRAINT scan_resolutions_result_status_check CHECK (result_status IN ('Owned', 'SafeToBuy')),
    CONSTRAINT scan_resolutions_selected_identity_check CHECK (
        selected_mbid IS NOT NULL OR selected_discogs_release_id IS NOT NULL
    )
);

CREATE TABLE scan_resolution_audit_log (
    audit_id                UUID        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id                 UUID        NOT NULL,
    request_id              UUID        NOT NULL,
    selected_mbid           TEXT,
    selected_discogs_release_id TEXT,
    occurred_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    operation               TEXT        NOT NULL DEFAULT 'RESOLVE',
    CONSTRAINT scan_resolution_audit_log_operation_check CHECK (operation = 'RESOLVE')
);

CREATE INDEX ix_scan_resolution_audit_log_user_request
    ON scan_resolution_audit_log (user_id, request_id, occurred_at DESC);

ALTER TABLE scan_request_status ENABLE ROW LEVEL SECURITY;
ALTER TABLE scan_ambiguities ENABLE ROW LEVEL SECURITY;
ALTER TABLE scan_ambiguity_candidates ENABLE ROW LEVEL SECURITY;
ALTER TABLE scan_resolutions ENABLE ROW LEVEL SECURITY;
ALTER TABLE scan_resolution_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_scan_request_status ON scan_request_status
    USING (user_id = current_setting('app.user_id', true)::uuid)
    WITH CHECK (user_id = current_setting('app.user_id', true)::uuid);

CREATE POLICY rls_scan_ambiguities ON scan_ambiguities
    USING (user_id = current_setting('app.user_id', true)::uuid)
    WITH CHECK (user_id = current_setting('app.user_id', true)::uuid);

CREATE POLICY rls_scan_ambiguity_candidates ON scan_ambiguity_candidates
    USING (user_id = current_setting('app.user_id', true)::uuid)
    WITH CHECK (user_id = current_setting('app.user_id', true)::uuid);

CREATE POLICY rls_scan_resolutions ON scan_resolutions
    USING (user_id = current_setting('app.user_id', true)::uuid)
    WITH CHECK (user_id = current_setting('app.user_id', true)::uuid);

CREATE POLICY rls_scan_resolution_audit_log ON scan_resolution_audit_log
    USING (user_id = current_setting('app.user_id', true)::uuid)
    WITH CHECK (user_id = current_setting('app.user_id', true)::uuid);

GRANT SELECT, INSERT, UPDATE ON scan_request_status TO deja_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON scan_ambiguities TO deja_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON scan_ambiguity_candidates TO deja_app;
GRANT SELECT, INSERT ON scan_resolutions TO deja_app;
GRANT SELECT, INSERT ON scan_resolution_audit_log TO deja_app;

CREATE OR REPLACE FUNCTION purge_user(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM scan_resolution_audit_log WHERE user_id = p_user_id;
    DELETE FROM scan_resolutions WHERE user_id = p_user_id;
    DELETE FROM scan_ambiguity_candidates WHERE user_id = p_user_id;
    DELETE FROM scan_ambiguities WHERE user_id = p_user_id;
    DELETE FROM scan_request_status WHERE user_id = p_user_id;

    DELETE FROM collection_audit_log WHERE user_id = p_user_id;
    DELETE FROM scan_results_cache WHERE user_id = p_user_id;
    DELETE FROM scan_events WHERE user_id = p_user_id;
    DELETE FROM collection_records WHERE user_id = p_user_id;
END;
$$;
