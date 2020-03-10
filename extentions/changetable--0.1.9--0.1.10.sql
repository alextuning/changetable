CREATE TABLE ss_util.ct_no_load (
  id serial not NULL,
  role_name varchar(64) not NULL,
  CONSTRAINT "ct_no_load_id" PRIMARY KEY (id)
);

CREATE OR REPLACE FUNCTION ss_util.ct_group_enable (group_role varchar(64)) RETURNS VOID AS $$
DECLARE
  user_role varchar(64);
  c integer;
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
    SELECT COUNT(*) INTO c FROM ss_util.ct_no_load WHERE role_name = user_role;

    if c = 0 then
      execute 'ALTER ROLE ' || user_role || ' SET session_preload_libraries = "changetable.so"';
      RAISE NOTICE 'changetable enabled for %', user_role;
    else
      RAISE NOTICE '% ignored', user_role;
    end if;

  END LOOP;
END;
$$ LANGUAGE plpgsql;
