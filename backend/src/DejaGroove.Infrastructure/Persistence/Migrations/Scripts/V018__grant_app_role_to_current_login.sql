-- Current deployments wire both ConnectionStrings:Postgres and
-- ConnectionStrings:PostgresAdmin to the Azure PostgreSQL administrator login.
-- Grant that login membership in the deja_app group role so runtime requests can
-- SET LOCAL ROLE deja_app while migrations continue to run with DDL rights.
DO $$
DECLARE
    login_name text := current_user;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_roles granted_role
        JOIN pg_auth_members members ON members.roleid = granted_role.oid
        JOIN pg_roles login_role ON login_role.oid = members.member
        WHERE granted_role.rolname = 'deja_app'
          AND login_role.rolname = login_name
    ) THEN
        RETURN;
    END IF;

    EXECUTE format('GRANT deja_app TO %I', login_name);
END
$$;
