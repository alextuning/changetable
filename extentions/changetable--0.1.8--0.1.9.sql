CREATE OR REPLACE FUNCTION ss_util.ct_group_enable (group_role varchar(64)) RETURNS VOID AS $$
DECLARE
  user_role varchar(64);
BEGIN
  execute 'GRANT usage ON schema ss_util TO ' || group_role;
  execute 'GRANT usage ON sequence ss_util.all_tables_log_id_seq TO ' || group_role;
  execute 'GRANT insert,select ON ss_util.all_tables_log TO ' || group_role;

  FOR user_role IN
    SELECT pg_user.usename
    FROM pg_user
    JOIN pg_auth_members ON (pg_user.usesysid=pg_auth_members.member)
    JOIN pg_roles ON (pg_roles.oid=pg_auth_members.roleid)
    WHERE pg_roles.rolname=group_role
  LOOP
    execute 'ALTER ROLE ' || user_role || ' SET session_preload_libraries = "changetable.so"';
    RAISE NOTICE 'changetable enabled for %', user_role;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION ss_util.ct_group_disable (group_role varchar(64)) RETURNS VOID AS $$
DECLARE
  user_role varchar(64);
BEGIN
  execute 'REVOKE usage ON schema ss_util FROM ' || group_role;
  execute 'REVOKE usage ON sequence ss_util.all_tables_log_id_seq FROM ' || group_role;
  execute 'REVOKE insert,select ON ss_util.all_tables_log FROM ' || group_role;

  FOR user_role IN
    SELECT pg_user.usename
    FROM pg_user
    JOIN pg_auth_members ON (pg_user.usesysid=pg_auth_members.member)
    JOIN pg_roles ON (pg_roles.oid=pg_auth_members.roleid)
    WHERE pg_roles.rolname=group_role
  LOOP
    execute 'ALTER ROLE ' || user_role || ' RESET session_preload_libraries;';
    RAISE NOTICE 'changetable disabled for %', user_role;
  END LOOP;
END;
$$ LANGUAGE plpgsql;
