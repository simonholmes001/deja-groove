-- Immutable write-audit trail for all collection mutations.
-- before_state/after_state capture the full row snapshot as JSONB.
CREATE TABLE collection_audit_log (
    audit_id            UUID        NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
    collection_record_id UUID       NOT NULL,
    user_id             UUID        NOT NULL,
    operation           TEXT        NOT NULL,
    occurred_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    before_state        JSONB,
    after_state         JSONB,

    CONSTRAINT collection_audit_log_operation_check
        CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE'))
);

-- Supports fetching the audit history for a single collection record.
CREATE INDEX ix_collection_audit_log_record_id
    ON collection_audit_log (collection_record_id, occurred_at DESC);
