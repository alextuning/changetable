\echo Use "CREATE EXTENSION changetable" to load this file. \quit

CREATE SCHEMA IF NOT EXISTS ss_util;

CREATE TABLE ss_util.all_tables_log (
	begstatobj varchar(2000) NULL,
	endstatobj varchar(2000) NULL,
	timeproc timestamp NULL DEFAULT CURRENT_TIMESTAMP,
	username varchar(20) NOT NULL,
	tablename varchar(60) NOT NULL,
	proctypename varchar(3) NULL,
	comment_ varchar(100) NULL,
	id serial not NULL,
	query varchar(3200) NULL,
CONSTRAINT "all_tables_log_id" PRIMARY KEY (id)
);

CREATE TABLE ss_util.ct_no_load (
  id serial not NULL,
	role_name varchar(64) not NULL,
	CONSTRAINT "ct_no_load_id" PRIMARY KEY (id)
);

INSERT INTO ss_util.ct_no_load VALUES (1, 'ogw_ops');
INSERT INTO ss_util.ct_no_load VALUES (2, 'ZABBIX_SLUICE');
INSERT INTO ss_util.ct_no_load VALUES (3, 'postgres_exporter');

CREATE OR REPLACE FUNCTION ss_util.instr(string character varying, string_to_search_for character varying, beg_index integer)
 RETURNS integer
 LANGUAGE plpgsql
 IMMUTABLE STRICT
AS $function$
DECLARE
    pos integer NOT NULL DEFAULT 0;
    temp_str varchar;
    beg integer;
    length integer;
    ss_length integer;
BEGIN
    IF beg_index > 0 THEN
        temp_str := substring(string FROM beg_index);
        pos := position(string_to_search_for IN temp_str);

        IF pos = 0 THEN
            RETURN 0;
        ELSE
            RETURN pos + beg_index - 1;
        END IF;
    ELSIF beg_index < 0 THEN
        ss_length := char_length(string_to_search_for);
        length := char_length(string);
        beg := length + 1 + beg_index;

        WHILE beg > 0 LOOP
            temp_str := substring(string FROM beg FOR ss_length);
            IF string_to_search_for = temp_str THEN
                RETURN beg;
            END IF;

            beg := beg - 1;
        END LOOP;

        RETURN 0;
    ELSE
        RETURN 0;
    END IF;
END;
$function$
;

CREATE OR REPLACE FUNCTION ss_util.getsetclause(str character varying)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
 declare
 res varchar;
 begin
    if str = '*' then
      return str;
    elsif ss_util.instr(upper(str),'SET',1) <= 0 then
      return null;
    end if;

     select a[2] into res from regexp_matches(str,
    '(set )(.*)( where)') AS a;
    
	if res is null then
		 select a[2] into res from regexp_matches(str,
	    '(set )(.*)') AS a;
	end if;
		   
    return res;

  end;
 $function$
;


CREATE OR REPLACE FUNCTION ss_util.getwhereclause(str character varying)
 RETURNS character varying
 LANGUAGE plpgsql
AS $function$
  declare
  res varchar;
  begin
    if str = '*' then
      return str;
    elsif ss_util.instr(upper(str),'WHERE',1) <= 0 then
      return null;
    end if;

    select * into res from substr(str,ss_util.instr(upper(str),'WHERE',1) + 5);
	return res;
  end;
  $function$
;


CREATE OR REPLACE FUNCTION ss_util.checkpkpredicate(query character varying, cur_scheme_name character varying, cur_table_name character varying)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare
   PRcols cursor (c_schema_name varchar,
                  c_table_name  varchar) for
select upper(field) as column_name, case when uniq=1 then 1 else 0 end as uniqkey_entry, case when pri=1 then 1 else 0 end as pk_entry,
sum(coalesce(t.uniq,0)) over() as cnt_uniqkey_entry,
sum(coalesce(t.pri,0)) over() as cnt_pk_entry,
count(1) over() as cnt_cols
from (
SELECT
        c.relname::varchar AS tab_name,
        a.attnum::integer,
        a.attname::varchar AS field,
        t.typname::varchar AS type,
        a.attnotnull::boolean AS isnotnull,
        (SELECT 1
            FROM pg_index i
            WHERE a.attrelid = i.indrelid
            AND a.attnum = ANY(i.indkey)
            AND i.indisprimary
        ) AS pri,
        (SELECT distinct 1
            FROM pg_index i
            WHERE a.attrelid = i.indrelid
            AND a.attnum = ANY(i.indkey)
        ) AS uniq
    FROM pg_attribute a, pg_class c, pg_type t, pg_namespace n
    WHERE n.nspname = c_schema_name
        AND a.attnum > 0
        AND a.attrelid = c.oid
        AND a.atttypid = t.oid
        AND n.oid = c.relnamespace
        and c.relname=c_table_name) t
        order by pk_entry desc, uniqkey_entry desc;

    where_cols varchar[];
    where_str   varchar(4000);
    match_cnt integer := 0;
begin
    where_str := trim(ss_util.getWhereClause(replace(replace(Query,chr(13),''),chr(10),'')));
    where_str := regexp_replace(where_str, '(!=|<=|>=|<>|<|>|=|\(.*\)| IN | OR | BETWEEN )',' ','g');
    where_str := upper(replace(replace(where_str,chr(13),''),chr(10),''));
  
   select string_to_array(trim(replace(replace(replace(where_str, ' ', ' !!'), '!! ',''), '!!','')),' ') into where_cols;
    -- проверка наличия уникальных индексов на таблице

    for i in 1 .. array_length(where_cols,1)
    loop
 
      for c in PRcols(cur_scheme_name,
                      cur_table_name)
      loop

           -- подсчитать кол-во совпадений условий в запросе и полями уникального индекса.
          -- совпадение по единственному полю в первичном ключе
          if where_cols[i] = c.column_name and c.pk_entry = 1 and c.cnt_pk_entry = 1 then
            return 0;
          -- если совпадение по полю из первичного ключа, где полей несколько, то ждем еще совпадения.
          elsif where_cols[i] = c.column_name and c.pk_entry = 1 and c.cnt_pk_entry > 1 then
            match_cnt := match_cnt + 1;
          -- совпадение по единственному полю в уникальном ключе
          elsif where_cols[i] = c.column_name and c.uniqkey_entry = 1 and c.cnt_uniqkey_entry = 1 then
            return 0;
          -- если совпадение по полю из уникального ключа, где полей несколько, то ждем еще совпадения.
          elsif where_cols[i] = c.column_name and c.uniqkey_entry = 1 and c.cnt_uniqkey_entry > 1 then
            match_cnt := match_cnt + 1;
          -- если совпадение по единственному полю в таблице без уникальных индексов
          elsif where_cols[i] = c.column_name and c.cnt_uniqkey_entry = 0 and c.cnt_cols = 1 then
            return 0;
          -- если совпадение по полю в таблице без уникальных индексов, то ждем еще совпадения
          elsif where_cols[i] = c.column_name and c.cnt_uniqkey_entry = 0 and c.cnt_cols > 1 then
            match_cnt := match_cnt + 1;
          else
             null;
          end if;
        end loop;
    end loop;

    if match_cnt >= 2 then
      return 0;
    else
      return 1;
    end if;

  exception
    when others then
      return 9998;

  end;
  $function$
;

CREATE OR REPLACE FUNCTION ss_util.validate(operation TEXT, sourcetext TEXT) RETURNS boolean
  LANGUAGE plpgsql
AS $function$
declare
  Query                varchar(4000) := regexp_replace(sourcetext,E'[\\n\\r]+', '', 'g' );
  Query_ucase          varchar(4000);
  cur_table_name       varchar(60);
  cur_scheme_name      varchar(30);
  cur_table_field_info varchar[];
  sess_user         varchar(128);
  v$cut_str varchar(4000);
  v$_error integer;
  comment_ varchar(100);
  replace_comment varchar(110);
  position integer;
-- ######################################################################################################

begin
  -- Не валидируем свои запросы
  position := strpos(lower(Query), 'insert into ss_util.all_tables_log');
  if position > 0 then
    -- raise notice '%', Query;
    return true;
  end if;
  -- Не валидируем подзапросы, выполняемые по foreign key
  position := strpos(lower(Query), 'pg_catalog');
  if position > 0 then
    -- raise notice '%', Query;
    return true;
  end if;  
	
  SELECT session_user into sess_user;
    select a[2] into comment_ from regexp_matches(Query, '(/\*)(.*)(\*/)') AS a;
    replace_comment:='/*'||comment_||'*/';
    comment_ :=trim(comment_);

  -- проверки "на дурака"
  if comment_ is null then
    raise exception 'Не указан комментарий к запросу';
  end if;
  
  if length(comment_) <= 5 then
    raise exception 'Комментарий должен быть больше 5и символов';
  end if;
 
 Query := replace(Query,replace_comment,'');
 Query := trim(trailing from Query, ';');
 Query := trim(Query);
 Query_ucase := upper(Query);
 
 if operation = 'INSERT' then
    -- TODO: проверка на то что таблица указана в формате shaema.table, иначе ошибка
   
     
    SELECT lower(regexp_replace(trim(Query), '^(insert\s+into)\s+(\w+\.)?([[:graph:]]+?)(\s|\().+$','\3','i')) into cur_table_name;
        
    if cur_table_name is null then
        raise exception 'Название таблицы должно быть указано в формате schema.table';
    end if;
    declare
		old_val varchar;
        new_val varchar;
    begin
	    old_val:=substr(Query,
                            ss_util.instr(Query_ucase,
                                  '(',
                                  1),
                            ss_util.instr(Query_ucase,
                                  ')',
                                  1) - ss_util.instr(Query_ucase,
                                             '(',
                                             1) + 2);
         new_val:= substr(Query,
                            ss_util.instr(Query_ucase,
                                  'VALUES',
                                  1) + 6,
                            ss_util.instr(Query_ucase,
                                  ')',
                                  ss_util.instr(Query_ucase,
                                        'VALUES',1) + 5) - ss_util.instr(Query_ucase,
                                                               'VALUES',
                                                               1) + 5);   
	   insert into ss_util.all_tables_log
        (BEGSTATOBJ,
         ENDSTATOBJ,
         TIMEPROC,
         USERNAME,
         TABLENAME,
         PROCTYPENAME,
         comment_,
         QUERY)
      values
        (substr(old_val,1,1999),
         substr(new_val,1,1999),
         current_timestamp,
         sess_user,
         substr(cur_table_name,1,29),
         substr(trim(Query_ucase),1,3),
         substr(comment_,1,99),
         substr(Query,1,3199));
     end;

-----------------------DELETE------------------------
  elsif operation = 'DELETE' then

    if ss_util.instr(Query_ucase,'WHERE',1) <= 0 then
      raise exception 'Запрос должен содержать условие "where"';
    end if;

    
        SELECT lower(array_to_string(a, '')) into cur_scheme_name
        FROM regexp_matches(trim(substr(Query,ss_util.instr(Query_ucase,'FROM ',1) + 4)),
        '^([[:graph:]]+)\.') AS a;
       
        SELECT lower(array_to_string(t, '')) into cur_table_name
        FROM regexp_matches(trim(substr(Query,ss_util.instr(Query_ucase,'FROM ',1) + 4)),
        '\.([[:graph:]]+)') AS t;
    if cur_scheme_name is null or cur_table_name is null then
        raise exception 'Название таблицы должно быть указано в формате schema.table';
    end if;
       
    declare
      DinamicString varchar(4000 );
      list_column   varchar(4000) := '';
      res        varchar(32000) := '';
    begin
      -- проверить что в запросе указаны поля из уникальных индексов
      if ss_util.CheckPkPredicate(Query,cur_scheme_name,cur_table_name) <> 0 then
        raise exception 'В условии DELETE должны быть указаны поля из первичного ключа таблицы!';
      end if;

      select array(select a.attname::varchar
      FROM pg_attribute a, pg_class c, pg_namespace n 
      where c.relname = cur_table_name  AND a.attnum > 0 AND atttypid<>0 AND n.oid = c.relnamespace AND a.attrelid = c.oid and n.nspname = cur_scheme_name
                      order by a.attnum::integer)  INTO cur_table_field_info ;

      for i in 1 .. array_length(cur_table_field_info,1)
      loop 
        list_column := list_column || cur_table_field_info[i] || ',';
      end loop;
      list_column := substr(list_column,1,length(list_column) - 1);
      DinamicString := 'select array(SELECT CTID from '
                       || cur_scheme_name||'.'||cur_table_name
                       || ' ' || substr(Query,ss_util.instr(Query_ucase,'WHERE ',1))
                       || ');';
                      
      execute DinamicString into cur_table_field_info;
	 
	 
      if coalesce(array_length(cur_table_field_info,1),0) = 0 then
        raise exception 'Не найдено записей для DELETE';
      end if;

      for i in 1 .. array_length(cur_table_field_info,1)
      loop
        DinamicString := 'select concat_ws('','',' || list_column || ') from ' || cur_scheme_name||'.'||cur_table_name || ' WHERE  CTID = ''' || cur_table_field_info[i] || '''';
        execute DinamicString into res;
       insert into ss_util.all_tables_log
        (BEGSTATOBJ,
         ENDSTATOBJ,
         TIMEPROC,
         USERNAME,
         TABLENAME,
         PROCTYPENAME,
         comment_,
         QUERY)
      values
        (substr(res,1,1999),
         null,
         current_timestamp,
         sess_user,
         substr(cur_table_name,1,29),
         substr(trim(Query_ucase),1,3),
         substr(comment_,1,99),
         substr(Query,1,3199));
     
      end loop;
    end;

-----------------------UPDATE------------------------
  elsif operation = 'UPDATE' then

    if ss_util.instr(Query_ucase,'WHERE',1) <= 0 then
      raise exception 'Запрос должен содержать условие "where"';
    end if;

        SELECT lower(array_to_string(a, '')) into cur_scheme_name
        FROM regexp_matches(trim(substr(Query,ss_util.instr(Query_ucase,'UPDATE ',1) + 6)),
        '^([[:graph:]]+)\.') AS a;
       
        SELECT lower(array_to_string(t, '')) into cur_table_name
        FROM regexp_matches(trim(substr(Query,ss_util.instr(Query_ucase,'UPDATE ',1) + 6)),
        '\.([[:graph:]]+)') AS t;
    if cur_scheme_name is null or cur_table_name is null then
        raise exception 'Название таблицы должно быть указано в формате schema.table';
    end if;

    declare
      DinamicString varchar(4000);
      list_column   varchar(4000) := '';
      res           varchar(32000);
      set_str		varchar(4000);
    begin
      --Проверить что в запросе указаны поля из уникальных индексов
      if ss_util.CheckPkPredicate(Query,cur_scheme_name,cur_table_name) <> 0 then
        raise exception 'В условии UPDATE должны быть указаны поля из первичного ключа таблицы!';
      end if;

      select array(select a.attname::varchar
      FROM pg_attribute a, pg_class c, pg_namespace n 
      where c.relname = cur_table_name  AND a.attnum > 0 AND atttypid<>0 AND n.oid = c.relnamespace AND a.attrelid = c.oid and n.nspname = cur_scheme_name
                      order by a.attnum::integer)  INTO cur_table_field_info ;

      for i in 1 .. array_length(cur_table_field_info,1)
      loop
        list_column := list_column || cur_table_field_info[i] || ',';
      end loop;
      list_column := substr(list_column,1,length(list_column) - 1);
      DinamicString := 'select array(SELECT CTID from '
                       || cur_scheme_name||'.'||cur_table_name
                       || ' ' || substr(Query,ss_util.instr(Query_ucase,'WHERE ',1))
                       || ');';
                   
                      
      execute DinamicString into cur_table_field_info;

      if coalesce(array_length(cur_table_field_info,1),0) = 0 then
        raise exception 'Не найдено записей для UPDATE';
      end if;

     for i in 1 .. array_length(cur_table_field_info,1)
      loop
        DinamicString := 'select concat_ws('','',' || list_column || ') from ' || cur_scheme_name||'.'||cur_table_name || ' WHERE  CTID = ''' || cur_table_field_info[i] || '''';
        execute DinamicString into res;
      
       set_str:=ss_util.getSetClause(Query); 
       insert into ss_util.all_tables_log
        (BEGSTATOBJ,
         ENDSTATOBJ,
         TIMEPROC,
         USERNAME,
         TABLENAME,
         PROCTYPENAME,
         comment_,
         QUERY)
      values
        (substr(res,1,1999),
         set_str,
         current_timestamp,
         sess_user,
         substr(cur_table_name,1,29),
         substr(trim(Query_ucase),1,3),
         substr(comment_,1,99),
         substr(Query,1,3199));
    end loop;
   end;
  else
    raise exception 'В запросе не найден DML оператор';
  end if;
  RETURN true;
exception
  when others then
    raise exception 'FATAL ERROR: %', sqlerrm;
END; 
$function$
;

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
