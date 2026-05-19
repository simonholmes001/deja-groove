ALTER TABLE collection_records
    ADD CONSTRAINT ck_collection_records_format
    CHECK (format IS NULL OR format IN ('vinyl', 'cd', 'cassette', 'other'));
