CREATE OR REPLACE FUNCTION ss_util.ct_group_disable (group_role varchar(64)) RETURNS VOID AS $$
DECLARE
  user_role varchar(64);
  c integer;
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
    SELECT COUNT(*) INTO c FROM ss_util.ct_no_load WHERE role_name = user_role;

    if c = 0 then
      execute 'ALTER ROLE ' || user_role || ' RESET session_preload_libraries;';
      RAISE NOTICE 'changetable disabled for %', user_role;
    else
      RAISE NOTICE '% ignored', user_role;
    end if;
    
  END LOOP;
END;
$$ LANGUAGE plpgsql;
