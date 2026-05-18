-- Issue #46: immutable write-audit trail for collection mutations.
--
-- A row-level trigger captures every INSERT/UPDATE/DELETE on collection_records
-- and writes a full JSONB before/after snapshot into collection_audit_log,
-- atomically within the mutating transaction. Doing this in the database (not
-- the application) guarantees no write path — present or future — can bypass
-- the audit trail. The actor is the row's user_id; the timestamp is the audit
-- row's occurred_at default (now()).
--
-- GDPR safeguard: purge_user() (V008) sets dejagroove.suppress_audit = 'on'
-- so erasing a user does NOT re-create audit rows for the very data being
-- erased. current_setting(..., true) returns NULL when unset, so auditing is
-- on by default (fail-safe: a missing flag must never silence the audit).

CREATE OR REPLACE FUNCTION log_collection_audit()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF current_setting('dejagroove.suppress_audit', true) = 'on' THEN
        RETURN COALESCE(NEW, OLD);
    END IF;

    IF (TG_OP = 'INSERT') THEN
        INSERT INTO collection_audit_log
            (collection_record_id, user_id, operation, before_state, after_state)
        VALUES (NEW.id, NEW.user_id, 'INSERT', NULL, to_jsonb(NEW));
        RETURN NEW;

    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO collection_audit_log
            (collection_record_id, user_id, operation, before_state, after_state)
        VALUES (NEW.id, NEW.user_id, 'UPDATE', to_jsonb(OLD), to_jsonb(NEW));
        RETURN NEW;

    ELSIF (TG_OP = 'DELETE') THEN
        INSERT INTO collection_audit_log
            (collection_record_id, user_id, operation, before_state, after_state)
        VALUES (OLD.id, OLD.user_id, 'DELETE', to_jsonb(OLD), NULL);
        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_collection_records_audit
    AFTER INSERT OR UPDATE OR DELETE ON collection_records
    FOR EACH ROW EXECUTE FUNCTION log_collection_audit();
