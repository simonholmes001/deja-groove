-- Blocker M2: make duplicate detection atomic for title/artist-only albums.
--
-- V001 only enforces uniqueness for stable IDs (mbid / discogs_release_id).
-- An album with neither (title + artist only) had no DB constraint, so two
-- concurrent adds could both pass the application duplicate check and insert
-- duplicate rows. This partial unique index closes that race using the same
-- case-insensitive comparison as AlbumIdentity.Equals (upper(title)/
-- upper(artist)). It applies only when both stable IDs are absent and the row
-- is active, so soft-deleted rows and stable-ID rows are unaffected.
--
-- The name is prefixed ux_collection_records so the repository's existing
-- 23505 handler (ConstraintName startswith "ux_collection_records") maps a
-- lost race to DuplicateCollectionRecordException, degrading to a normal
-- duplicate-detected response.
CREATE UNIQUE INDEX ux_collection_records_user_title_artist
    ON collection_records (user_id, upper(title), upper(artist))
    WHERE mbid IS NULL
      AND discogs_release_id IS NULL
      AND deleted_at IS NULL;
