-- Align V007 scan-resolution tables with the canonical app.current_user_id
-- session setting used by UserScope and V014 policies.

DROP POLICY IF EXISTS rls_scan_request_status ON scan_request_status;
DROP POLICY IF EXISTS rls_scan_ambiguities ON scan_ambiguities;
DROP POLICY IF EXISTS rls_scan_ambiguity_candidates ON scan_ambiguity_candidates;
DROP POLICY IF EXISTS rls_scan_resolutions ON scan_resolutions;
DROP POLICY IF EXISTS rls_scan_resolution_audit_log ON scan_resolution_audit_log;

CREATE POLICY rls_scan_request_status ON scan_request_status
    TO deja_app
    USING (user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid)
    WITH CHECK (user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid);

CREATE POLICY rls_scan_ambiguities ON scan_ambiguities
    TO deja_app
    USING (user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid)
    WITH CHECK (user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid);

CREATE POLICY rls_scan_ambiguity_candidates ON scan_ambiguity_candidates
    TO deja_app
    USING (user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid)
    WITH CHECK (user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid);

CREATE POLICY rls_scan_resolutions ON scan_resolutions
    TO deja_app
    USING (user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid)
    WITH CHECK (user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid);

CREATE POLICY rls_scan_resolution_audit_log ON scan_resolution_audit_log
    TO deja_app
    USING (user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid)
    WITH CHECK (user_id = NULLIF(current_setting('app.current_user_id', true), '')::uuid);
