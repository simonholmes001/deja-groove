-- pHash-keyed result cache. Replaces Redis as the scan deduplication store.
-- phash is stored as BIGINT (signed) — the application layer casts ulong bits
-- to/from int64 using unchecked arithmetic; the bit pattern is preserved.
-- phash_version allows future algorithm changes without cache poisoning.
CREATE TABLE scan_results_cache (
    user_id             UUID        NOT NULL,
    phash               BIGINT      NOT NULL,
    phash_version       SMALLINT    NOT NULL DEFAULT 1,
    result_status       TEXT        NOT NULL,
    confidence          REAL        NOT NULL,
    mbid                TEXT,
    discogs_release_id  TEXT,
    title               TEXT,
    artist              TEXT,
    year                SMALLINT,
    collection_record_id UUID,
    expires_at          TIMESTAMPTZ NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (user_id, phash, phash_version),

    CONSTRAINT scan_results_cache_result_status_check
        CHECK (result_status IN ('Owned', 'SafeToBuy', 'Ambiguous', 'NoMatch'))
);

-- Supports efficient purging of expired cache entries.
CREATE INDEX ix_scan_results_cache_expires_at
    ON scan_results_cache (expires_at);
