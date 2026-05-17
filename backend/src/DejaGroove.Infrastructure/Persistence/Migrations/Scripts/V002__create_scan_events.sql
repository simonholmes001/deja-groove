-- Append-only audit log of every scan attempt. Mirrors the ScanEvent domain object.
-- client_scan_id is the idempotency key the iOS client generates per capture.
CREATE TABLE scan_events (
    scan_event_id       UUID        NOT NULL PRIMARY KEY,
    user_id             UUID        NOT NULL,
    client_scan_id      UUID        NOT NULL,
    result_status       TEXT        NOT NULL,
    confidence          REAL        NOT NULL,
    mbid                TEXT,
    discogs_release_id  TEXT,
    title               TEXT,
    artist              TEXT,
    year                SMALLINT,
    captured_at         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT scan_events_result_status_check
        CHECK (result_status IN ('Owned', 'SafeToBuy', 'Ambiguous', 'NoMatch'))
);

-- Supports timeline queries per user.
CREATE INDEX ix_scan_events_user_id
    ON scan_events (user_id, created_at DESC);

-- Prevents duplicate scan records for the same client-generated request ID.
CREATE UNIQUE INDEX ux_scan_events_user_client_scan_id
    ON scan_events (user_id, client_scan_id);
