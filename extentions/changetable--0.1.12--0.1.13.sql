CREATE OR REPLACE FUNCTION ss_util.validate(operation TEXT, sourcetext TEXT) RETURNS boolean
  LANGUAGE plpgsql
AS $function$
declare
  Query                varchar(4000) := sourcetext;
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
      res        varchar(4000) := '';
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
      res           varchar(4000);
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

INSERT INTO ss_util.ct_no_load (id,role_name) VALUES (1, 'ogw_ops') ON CONFLICT DO NOTHING;
INSERT INTO ss_util.ct_no_load (id,role_name) VALUES (2, 'ZABBIX_SLUICE') ON CONFLICT DO NOTHING;
INSERT INTO ss_util.ct_no_load (id,role_name) VALUES (3, 'postgres_exporter') ON CONFLICT DO NOTHING;
