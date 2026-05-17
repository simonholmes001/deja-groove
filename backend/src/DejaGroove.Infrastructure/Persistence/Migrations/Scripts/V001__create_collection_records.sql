-- Core entity: albums a user has declared they own.
-- Identity constraint mirrors AlbumIdentity.Create() domain invariant:
-- at least one stable ID (mbid or discogs_release_id), or both title + artist.
CREATE TABLE collection_records (
    id                  UUID        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id             UUID        NOT NULL,
    mbid                TEXT,
    discogs_release_id  TEXT,
    title               TEXT,
    artist              TEXT,
    year                SMALLINT,
    format              TEXT,
    notes               TEXT,
    version             INTEGER     NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at          TIMESTAMPTZ,

    CONSTRAINT collection_records_identity_check CHECK (
        mbid IS NOT NULL
        OR discogs_release_id IS NOT NULL
        OR (title IS NOT NULL AND artist IS NOT NULL)
    )
);

-- Active records by user (excludes soft-deleted rows).
CREATE INDEX ix_collection_records_user_id
    ON collection_records (user_id)
    WHERE deleted_at IS NULL;

-- Prevent duplicate active ownership of the same MusicBrainz release per user.
CREATE UNIQUE INDEX ux_collection_records_user_mbid
    ON collection_records (user_id, mbid)
    WHERE mbid IS NOT NULL AND deleted_at IS NULL;

-- Prevent duplicate active ownership of the same Discogs release per user.
CREATE UNIQUE INDEX ux_collection_records_user_discogs
    ON collection_records (user_id, discogs_release_id)
    WHERE discogs_release_id IS NOT NULL AND deleted_at IS NULL;
