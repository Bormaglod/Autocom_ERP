--
-- PostgreSQL database dump
--

-- Dumped from database version 10.2
-- Dumped by pg_dump version 11.2

-- Started on 2019-08-07 23:30:14

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 2 (class 3079 OID 77824)
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- TOC entry 3313 (class 0 OID 0)
-- Dependencies: 2
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- TOC entry 837 (class 1247 OID 119753)
-- Name: rec_operation; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.rec_operation AS (
	operation_id uuid,
	operation_count integer
);


ALTER TYPE public.rec_operation OWNER TO postgres;

--
-- TOC entry 832 (class 1247 OID 119705)
-- Name: tax_nds; Type: DOMAIN; Schema: public; Owner: postgres
--

CREATE DOMAIN public.tax_nds AS integer
	CONSTRAINT chk_tax_nds CHECK ((VALUE = ANY (ARRAY[0, 10, 20])));


ALTER DOMAIN public.tax_nds OWNER TO postgres;

--
-- TOC entry 275 (class 1255 OID 78220)
-- Name: account_test(integer[]); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.account_test(account integer[]) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
declare
   k integer[] := '{ 7, 1, 3, 7, 1, 3, 7, 1, 3, 7, 1, 3, 7, 1, 3, 7, 1, 3, 7, 1, 3, 7, 1 }';
   sum integer;
begin
   if (array_length(account, 1) != 23) then
      return false;
   end if;

   sum := control_sum(account, k);
   return sum % 10 = 0;
end;
$$;


ALTER FUNCTION public.account_test(account integer[]) OWNER TO postgres;

--
-- TOC entry 274 (class 1255 OID 103152)
-- Name: add_percent_archive(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_percent_archive() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  last_percent numeric;
begin
  if (new.percentage != old.percentage and old.percentage > 0) then
    with rows as(
      insert into directory (owner_id, kind_id)
        values (old.id, get_uuid('percentage')) returning id
    )
    insert into percentage (id, percent_value)
      values ((select id from rows), old.percentage);
  end if;
    
  return new;
end;
$$;


ALTER FUNCTION public.add_percent_archive() OWNER TO postgres;

--
-- TOC entry 272 (class 1255 OID 78270)
-- Name: add_price_archive(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_price_archive() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  last_price money;
begin
  if (new.price != old.price and old.price > 0.0::money) then
    with rows as(
      insert into directory (owner_id, kind_id)
        values (old.id, get_uuid('price')) returning id
    )
    insert into price (id, price_value)
      values ((select id from rows), old.price);
  end if;
    
  return new;
end;
$$;


ALTER FUNCTION public.add_price_archive() OWNER TO postgres;

--
-- TOC entry 283 (class 1255 OID 102898)
-- Name: add_salary_archive(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.add_salary_archive() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  last_salary money;
begin
  if (new.salary != old.salary and old.salary > 0.0::money) then
    with rows as(
      insert into directory (owner_id, kind_id)
        values (old.id, 'b5fc483e-da12-49bb-addf-5ec81054cd66') returning id
    )
    insert into price (id, price_value)
      values ((select id from rows), old.salary);
  end if;
    
  return new;
end;
$$;


ALTER FUNCTION public.add_salary_archive() OWNER TO postgres;

--
-- TOC entry 299 (class 1255 OID 86515)
-- Name: bank_test_account(numeric, numeric, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.bank_test_account(account numeric, bik numeric, table_name character varying) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
declare
   bik_a integer[];
   account_a integer[];
begin
   bik_a = case table_name
     when 'bank' then string_to_array('0' || substring(lpad(bik::character varying, 9, '0') from 5 for 2), NULL)::integer[]
     when 'account' then string_to_array((bik % 1000)::character varying, NULL)::integer[]
   end;
   
   account_a = string_to_array(account::character varying, NULL)::integer[];
   return account_test(bik_a || account_a);
end;
$$;


ALTER FUNCTION public.bank_test_account(account numeric, bik numeric, table_name character varying) OWNER TO postgres;

--
-- TOC entry 290 (class 1255 OID 127942)
-- Name: calculate_complete_status(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.calculate_complete_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
	if (new.operation_count != 0) then
		new.complete_status = new.completed * 100 / new.operation_count;
	else
    	new.complete_status = 0;
	end if;
    
    return new;
end;
$$;


ALTER FUNCTION public.calculate_complete_status() OWNER TO postgres;

--
-- TOC entry 259 (class 1255 OID 78190)
-- Name: change_status(uuid, bigint, boolean, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.change_status(document_id uuid, new_status_id bigint, auto boolean DEFAULT false, note character varying DEFAULT NULL::character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	user_id uuid;
	locked_user uuid;
	locked_name varchar;
	date_lock timestamp with time zone;
	cur_status bigint;
	can_empty_note boolean;
begin
	select id into user_id from user_alias where pg_name = session_user;
 
	select d.status_id, u.name, d.date_locked, d.user_locked_id
		into cur_status, locked_name, date_lock, locked_user
		from document_info d
			left join user_alias u on (d.user_locked_id = u.id)
		where d.id = document_id;
    
	if (locked_user is not null) and (locked_user != user_id) then
		raise 'Запись заблокирована пользователем % в %', locked_name, date_lock;
	end if;
  
	if (new_status_id != cur_status) then
		select c.empty_note
			into can_empty_note
			from document_info d
				join condition c on (c.kind_id = d.kind_id)
				join changing_status s on (s.id = c.changing_status_id)
			where 
				d.id = document_id and s.status_from_id = cur_status and s.status_to_id = new_status_id;
 
		can_empty_note = coalesce(can_empty_note, true);
		if (not can_empty_note and coalesce(note, '') = '') then
			raise 'Для данного перевода должно быть указано примечание.';
		end if;

		perform check_document_values(document_id, cur_status, new_status_id, auto);

		with rows as
		(
			insert into history (reference_id, status_from_id, status_to_id, user_id, auto, note)
				values (document_id, cur_status, new_status_id, user_id, auto, note) returning id
		)
		update document_info
			set status_id = new_status_id,
				history_id = (select id from rows)
			where id = document_id;

		perform document_updated(document_id, cur_status, new_status_id, auto);
	end if;
 end;
$$;


ALTER FUNCTION public.change_status(document_id uuid, new_status_id bigint, auto boolean, note character varying) OWNER TO postgres;

--
-- TOC entry 265 (class 1255 OID 78217)
-- Name: check_bank_codes(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_bank_codes() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
   if new.bik > 0 and new.account > 0 then
     if (not bank_test_account(new.account, new.bik, TG_TABLE_NAME::character varying)) then
        raise exception 'Некорректное значение БИК или корр. счета';
     end if;
   end if;

   return new;
end;
$$;


ALTER FUNCTION public.check_bank_codes() OWNER TO postgres;

--
-- TOC entry 305 (class 1255 OID 78309)
-- Name: check_contractor_account(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_contractor_account() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  bik numeric(9, 0);
begin
  if ((new.bank_id is not null) and (new.account_value is not null)) then
    select bank.bik into bik from bank where bank.id = new.bank_id;
    if (not bank_test_account(new.account_value, bik, TG_TABLE_NAME::character varying)) then
      raise exception 'Некорректное значение расч. счета';
    end if;
  end if;
  
  return new;
end;
$$;


ALTER FUNCTION public.check_contractor_account() OWNER TO postgres;

--
-- TOC entry 320 (class 1255 OID 78165)
-- Name: check_contractor_codes(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_contractor_codes() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  bik numeric(9,0);
  code numeric;
begin
  code = coalesce(new.inn, 0);  
  if ((code > 0) and (not contractor_test_inn(code))) then
    raise exception 'Некорректное значение ИНН';
  end if;

  code = coalesce(new.okpo, 0);
  if ((code > 0) and (not contractor_test_okpo(code))) then
    raise exception 'Некорректное значение ОКПО';
  end if;

  return new;
end;
$$;


ALTER FUNCTION public.check_contractor_codes() OWNER TO postgres;

--
-- TOC entry 317 (class 1255 OID 78049)
-- Name: check_document_deleting(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_document_deleting() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  sys boolean;
  name_value character varying(20);
  status_s bigint;
  status_e bigint;
begin
  select e.name, k.is_system, t.starting_status_id, t.canceled_status_id
    into name_value, sys, status_s, status_e
    from kind k
      join kind_enum e on (e.id = k.enum_id)
      join transition t on (t.id = k.transition_id)
    where k.id = old.kind_id;
  
  if (select administrator from user_alias where pg_name = session_user) = false then
    if sys then
      raise '% (%) может удалить только администратор.', name_value, old.code;
    end if;
  end if;
  
  status_e = coalesce(status_e, 0);
  if old.status_id not in (status_s, status_e, 500) then
    raise '% (id = %) можно удалить только в состоянии "%" (или в отмененном состоянии)',
      name_value,
      old.id,
      (select note from status where id = status_s);
  end if;

  return old;
end;
$$;


ALTER FUNCTION public.check_document_deleting() OWNER TO postgres;

--
-- TOC entry 306 (class 1255 OID 78188)
-- Name: check_document_values(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_document_values(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	doc_kind uuid;
	doc_code varchar;
begin
	select k.id, e.code
		into doc_kind, doc_code
		from document_info d 
			join kind k on (d.kind_id = k.id)
			join kind_enum e on (k.enum_id = e.id)
		where d.id = document_id;

	if (doc_code = 'document') then
		perform checking_document(document_id, status_from, status_to, auto);
	end if;
	
	case doc_kind
		-- типы производственных операций
		when get_uuid('operation_type') then
			perform checking_operation_type(document_id, status_from, status_to, auto);
		
		-- производственные операции
		when get_uuid('operation') then
			perform checking_operation(document_id, status_from, status_to, auto);
		
		-- калькуляция
		when get_uuid('calculation') then
			perform checking_calculation(document_id, status_from, status_to, auto);
	
		-- список сырья и основных материалов
		when get_uuid('item_goods') then
			perform checking_item_goods(document_id, status_from, status_to, auto);
	
		-- список операций
		when get_uuid('item_operation') then
			perform checking_item_operation(document_id, status_from, status_to, auto);
		
		-- список отчислений
		when get_uuid('item_deduction') then
			perform checking_item_deduction(document_id, status_from, status_to, auto);
		
		-- отчисления с суммы
		when get_uuid('deduction') then
			perform checking_deduction(document_id, status_from, status_to, auto);
		
		-- заявка на приобретение материалов
		when get_uuid('request') then
			perform checking_request(document_id, status_from, status_to, auto);
		
		-- заказ на изготовление
		when get_uuid('order_production') then
			perform checking_order(document_id, status_from, status_to, auto);
		
		-- выполнение заказа
		when get_uuid('order_complete') then
			perform checking_order_complete(document_id, status_from, status_to, auto);
		
		-- отгрузка заказа
		when get_uuid('order_shipped') then
			perform checking_order_shipped(document_id, status_from, status_to, auto);
		
		else
        	-- nothing
	end case;
end;
$$;


ALTER FUNCTION public.check_document_values(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 318 (class 1255 OID 78137)
-- Name: check_kind(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_kind() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  -- если есть записи определяющие переходы состояния документа, то...
  if exists(select id from changing_status where transition_id = new.id) then
    -- ... код состояния должен быть одним из начальных в таблице переходов
    if not exists(select id from changing_status where status_from_id = new.starting_status_id and transition_id = new.id) then
      raise 'Неизвестное состояние документа.';
    end if;
  else
    if new.starting_status_id != 0 then
      raise 'Для данного документа не предусмотрены переходы состояний.';
    end if;
  end if;
  
  return new;
end;
$$;


ALTER FUNCTION public.check_kind() OWNER TO postgres;

--
-- TOC entry 316 (class 1255 OID 103307)
-- Name: checking_calculation(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.checking_calculation(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	_owner_id uuid;
	status_value bigint;
begin
	-- СОСТАВЛЕН => КОРРЕКТЕН
	if (status_from = 1000 and status_to = 1001) then
		if (exists(select id from directory where kind_id = get_uuid('item_goods') and owner_id = document_id and status_id = 1000)) then
			raise 'Все материалы должны быть в состоянии КОРРЕКТЕН';
		end if;

		if (exists(select id from directory where kind_id = get_uuid('item_operation') and owner_id = document_id and status_id = 1000)) then
			raise 'Все операции должны быть в состоянии КОРРЕКТЕН';
		end if;
	end if;

	-- КОРРЕКТЕН => УТВЕРЖДЁН
	if (status_from = 1001 and status_to = 1002) then
		select owner_id into _owner_id from directory where id = document_id;
		if (exists(select id from directory where status_id = 1002 and owner_id = _owner_id)) then
			raise 'Может быть только одна утверждённая калькуляция';
		end if;
	end if;

	-- КОРРЕКТЕН, УТВЕРЖДЁН => ИЗМЕНЯЕТСЯ
	if (status_from in (1001, 1002) and status_to = 1004) then
		select owner_id into _owner_id from directory where id = document_id;
		select status_id into status_value from directory where id = _owner_id;
		if (status_value not in (1000, 1004)) then
			raise 'Номенклатура должна быть в стостянии СОСТАВЛЕН или ИЗМЕНЯЕТСЯ';
		end if;
	end if;
end;
$$;


ALTER FUNCTION public.checking_calculation(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 285 (class 1255 OID 103312)
-- Name: checking_deduction(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.checking_deduction(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	int_value integer;
begin
	-- СОСТАВЛЕН, ИЗМЕНЯЕТСЯ => КОРРЕКТЕН
    if (status_from in (1000, 1004) and status_to = 1001) then
		select accrual_base into int_value from deduction where id = document_id;
		if (int_value = 0) then
			raise 'Необходимо выбрать базу для начисления';
		end if;
	end if;
end;
$$;


ALTER FUNCTION public.checking_deduction(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 307 (class 1255 OID 103313)
-- Name: checking_document(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.checking_document(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	org_id uuid;
begin
	-- СОСТАВЛЕН, ИЗМЕНЯЕТСЯ => КОРРЕКТЕН
	if (status_from in (1000, 1004) and status_to = 1001) then
		select organization_id into org_id from document where id = document_id;
		if (org_id is null) then
			raise 'Необходимо указать организацию от которой выписывается документ.';
		end if;
	end if;
end;
$$;


ALTER FUNCTION public.checking_document(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 297 (class 1255 OID 103311)
-- Name: checking_item_deduction(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.checking_item_deduction(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	status_value bigint;
begin
	-- КОРРЕКТЕН => СОСТАВЛЕН
    if (status_from = 1001 and status_to = 1000) then
		select o.status_id
			into status_value
			from item_deduction i
				join directory d on (i.id = d.id)
				join directory o on (d.owner_id = o.id)
			where i.id = document_id;
		if (status_value not in (1000, 1004)) then
			raise 'Калькуляция должна быть в стостянии СОСТАВЛЕН или ИЗМЕНЯЕТСЯ';
		end if;
	end if;
end;
$$;


ALTER FUNCTION public.checking_item_deduction(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 314 (class 1255 OID 103309)
-- Name: checking_item_goods(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.checking_item_goods(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	status_value bigint;
	item_name varchar;
begin
	-- КОРРЕКТЕН => СОСТАВЛЕН
    if (status_from = 1001 and status_to = 1000) then
		select g.status_id
			into status_value
			from item_goods i
				join directory d on (i.id = d.id)
				join directory g on (d.owner_id = g.id)
			where i.id = document_id;
		if (status_value not in (1000, 1004)) then
			raise 'Калькуляция должна быть в стостянии СОСТАВЛЕН или ИЗМЕНЯЕТСЯ';
		end if;

		with owner as
		(
			select d.owner_id
				from item_goods i
					join directory d on (i.id = d.id)
				where i.id = document_id
		)
		select dn.name
			into item_name
			from item_deduction i
				join directory d on (i.id = d.id)
				join deduction ded on (ded.id = i.deduction_id)
				join directory dn on (dn.id = ded.id)
				join owner o on (o.owner_id = d.owner_id)
			where ded.accrual_base = 1 and d.status_id = 1001
			limit 1;

		if (item_name is not null) then
			raise 'Отчисление "%" должно быть в состоянии СОСТАВЛЕН', item_name;
		end if;
	end if;
end;
$$;


ALTER FUNCTION public.checking_item_goods(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 302 (class 1255 OID 103310)
-- Name: checking_item_operation(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.checking_item_operation(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	status_value bigint;
	item_name varchar;
begin
	-- КОРРЕКТЕН => СОСТАВЛЕН
    if (status_from = 1001 and status_to = 1000) then
		select o.status_id
			into status_value
			from item_operation i
				join directory d on (i.id = d.id)
				join directory o on (d.owner_id = o.id)
			where i.id = document_id;
		if (status_value not in (1000, 1004)) then
			raise 'Калькуляция должна быть в стостянии СОСТАВЛЕН или ИЗМЕНЯЕТСЯ';
		end if;

		with owner as
		(
			select d.owner_id
				from item_operation i
					join directory d on (i.id = d.id)
				where i.id = document_id
		)
		select dn.name
			into item_name
			from item_deduction i
				join directory d on (i.id = d.id)
				join deduction ded on (ded.id = i.deduction_id)
				join directory dn on (dn.id = ded.id)
				join owner o on (o.owner_id = d.owner_id)
			where ded.accrual_base = 2 and d.status_id = 1001
			limit 1;

		if (item_name is not null) then
			raise 'Отчисление "%" должно быть в состоянии СОСТАВЛЕН', item_name;
		end if;
	end if;
end;
$$;


ALTER FUNCTION public.checking_item_operation(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 287 (class 1255 OID 103308)
-- Name: checking_operation(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.checking_operation(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	_produced integer;
	_prod_time integer;
	_production_rate integer;
	salary_value money;
	salary_type money;
begin
	if (status_from in (1000, 1004) and status_to = 1001) then
		select o.produced, o.prod_time, o.production_rate, o.salary, t.salary
			into _produced, _prod_time, _production_rate, salary_value, salary_type
			from operation o
				left join operation_type t on (t.id = o.type_id)
			where
				o.id = document_id;

		if (salary_type is null) then
			raise 'Не установлен тип операции или значение расценки за операцию.';
		end if;

		if (salary_type = 0::money) then
			raise 'Не установлено значение расценки за операцию.';
		end if;

		_produced = coalesce(_produced, 0);
		if (_produced < 0) then
			raise 'Значение выработки должно быть больше или равно 0.';
		end if;

		_prod_time = coalesce(_prod_time, 0);
		if (_prod_time < 0) then
			raise 'Значение времени выработки должно быть больше или равно 0.';
		end if;

		salary_value = coalesce(salary_value, 0::money);
		if (salary_value < 0::money) then
			raise 'Значение расценки зар. платы должно быть больше или равно 0.';
		end if;

		if (salary_value = 0::money and (_produced = 0 or _prod_time = 0)) then
			raise 'Расценка зар. платы за операцию должна быть больше 0.';
		end if;
	end if;
end;
$$;


ALTER FUNCTION public.checking_operation(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 277 (class 1255 OID 103304)
-- Name: checking_operation_type(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.checking_operation_type(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	salary_value money;
begin
	if (status_from = 1000 and status_to = 1001) then
		select salary into salary_value from operation_type where id = document_id;
		if (salary_value <= 0::money) then
			raise 'Расценка за операцию должна быть больше 0.';
		end if;
	end if;
end;
$$;


ALTER FUNCTION public.checking_operation_type(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 269 (class 1255 OID 103482)
-- Name: checking_order(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.checking_order(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	c_id uuid;
	detail_count integer;
	total_goods numeric(12, 3);
	goods_rec record;
begin
	select contractor_id into c_id from order_production where id = document_id;

	-- СОСТАВЛЕН, ИЗМЕНЯЕТСЯ => КОРРЕКТЕН
	if (status_from in (1000, 1004) and status_to = 1001) then
		if (c_id is null) then
			raise 'Необходимо указать контрагента.';
		end if;
	
		select count(id) into detail_count from order_detail where owner_id = document_id;
		if (detail_count = 0) then
			raise 'Список неоменклатуры пуст. Заполните его.';
		end if;
	end if;

    -- В ПРОИЗВОДСТВЕ => ИЗГОТОВЛЕН
    if (status_from = 1013 and status_to = 1014) then
    	if (exists(select o.id from order_complete o join document d on (d.id = o.id) where d.owner_id = document_id and d.status_id != 1014)) then
        	raise 'Все записи о выполнении заказа должны быть в состоянии ИЗГОТОВЛЕН';
        end if;

		for goods_rec in 
			select o.goods_id, sum(o.goods_count) goods_count
				from order_complete o 
					join document d on (d.id = o.id)
				where 
					d.owner_id = document_id and 
					d.status_id = 1014
				group by o.goods_id
		loop
			select sum(goods_count) 
				into total_goods 
				from order_detail 
				where owner_id = document_id and goods_id = goods_rec.goods_id;
			
			if (goods_rec.goods_count != total_goods) then
				raise 'Количество изделий в заказе не соответствует количеству изделий в списке выполнения заказа.';
			end if;
		end loop;
    end if;
   
	-- ИЗГОТОВЛЕН => ОТГРУЖЕН
	if (status_from = 1014 and status_to = 1015) then
		if (exists(select o.id from order_shipped o join document d on (d.id = o.id) where d.owner_id = document_id and d.status_id != 1015)) then
        	raise 'Все записи об отгрузках заказа должны быть в состоянии ОТГРУЖЕН';
        end if;
       
       for goods_rec in 
			select o.goods_id, sum(o.goods_count) goods_count
				from order_shipped o 
					join document d on (d.id = o.id)
				where 
					d.owner_id = document_id and 
					d.status_id = 1015
				group by o.goods_id
		loop
			select sum(goods_count) 
				into total_goods 
				from order_detail 
				where owner_id = document_id and goods_id = goods_rec.goods_id;
			
			if (goods_rec.goods_count != total_goods) then
				raise 'Количество изделий в заказе не соответствует количеству изделий в списке отгрузки заказа.';
			end if;
		end loop;
	end if;
   
end;
$$;


ALTER FUNCTION public.checking_order(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 300 (class 1255 OID 103517)
-- Name: checking_order_complete(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.checking_order_complete(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	owner_status_id bigint;
begin
	select production.status_id 
		into owner_status_id
		from document complete
			join document production on (complete.owner_id = production.id)
		where complete.id = document_id;
	
	-- КОРРЕКТЕН => В ПРОИЗВОДСТВЕ
	if (status_from = 1001 and status_to = 1013) then
		if (owner_status_id != 1013) then
			raise 'Заказ на изготовление должен быть в состоянии В ПРОИЗВОДСТВЕ!';
		end if;
	end if;
end;
$$;


ALTER FUNCTION public.checking_order_complete(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 254 (class 1255 OID 119715)
-- Name: checking_order_shipped(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.checking_order_shipped(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	production_id uuid;
	owner_status_id bigint;
	shipped_count numeric(12, 3);
	complete_count numeric(12, 3);
	shipped_count_all numeric(12, 3);
	shipped_id uuid;
begin
	select production.id, production.status_id 
		into production_id, owner_status_id
		from document shipped
			join document production on (shipped.owner_id = production.id)
		where shipped.id = document_id;
	
	select goods_id, goods_count into shipped_id, shipped_count from order_shipped where id = document_id;
	
	-- КОРРЕКТЕН => ОТГРУЖЕН
	if (status_from = 1001 and status_to = 1015) then
		if (owner_status_id not in (1013, 1014)) then
			raise 'Заказ на изготовление должен быть в состоянии В ПРОИЗВОДСТВЕ или ИЗГОТОВЛЕН!';
		end if;
	
		-- количество изделий в состоянии ИЗГОТОВЛЕН
		select sum(goods_count)
			into complete_count
			from order_complete o
				join document d on (d.id = o.id)
			where d.owner_id = production_id and o.goods_id = shipped_id and d.status_id = 1014;
		
		-- количество уже отгруженных изделий
		select sum(goods_count)
			into shipped_count_all
			from order_shipped o
				join document d on (d.id = o.id)
			where d.owner_id = production_id and o.goods_id = shipped_id and d.status_id = 1015;
		
		if (complete_count - shipped_count_all < shipped_count) then
			raise 'Недостаточно изделий для отгрузки!';
		end if;
	end if;
end;
$$;


ALTER FUNCTION public.checking_order_shipped(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 301 (class 1255 OID 103314)
-- Name: checking_request(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.checking_request(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	c_id uuid;
	detail_count integer;
	_waybill_number varchar;
	_waybill_date timestamptz;
	_invoice_number varchar;
	_invoice_date timestamptz;
	_tax_payer boolean;
begin
	select contractor_id, waybill_number, waybill_date, invoice_number, invoice_date, tax_payer
		into c_id, _waybill_number, _waybill_date, _invoice_number, _invoice_date, _tax_payer
		from request 
		where id = document_id;

	-- СОСТАВЛЕН, ИЗМЕНЯЕТСЯ => КОРРЕКТЕН
	if (status_from in (1000, 1004) and status_to = 1001) then
		if (c_id is null) then
			raise 'Необходимо указать контрагента.';
		end if;
	
		select count(id) into detail_count from request_detail where owner_id = document_id;
		if (detail_count = 0) then
			raise 'Список неоменклатуры пуст. Заполните его.';
		end if;
	end if;

	-- СЧЁТ ОПЛАЧЕН => МАТЕРИАЛ ПОЛУЧЕН
	if (status_from = 1009 and status_to = 1010) then
		if (_waybill_number is null) then
			raise 'Укажите номер накладной!';
		end if;
		
		if (_waybill_date is null) then
			raise 'Укажите дату накладной!';
		end if;
		
		if (_tax_payer) then
			if (_invoice_number is null) then
				raise 'Укажите номер счёт-фактуры!';
			end if;
		
			if (_invoice_date is null) then
				raise 'Укажите дату счёт-фактуры!';
			end if;
		end if;
	end if;
end;
$$;


ALTER FUNCTION public.checking_request(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 279 (class 1255 OID 103210)
-- Name: complete_calculation(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.complete_calculation(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	cost_material money;
	cost_operation money;
	cost_deduction money;
	_cost money;
	_profit_percent numeric;
	_profit_value money;
	_price money;
begin
	-- СОСТАВЛЕН, ИЗМЕНЯЕТСЯ => КОРРЕКТЕН
	if (status_from in (1000, 1004) and status_to = 1001) then
		select sum(i.cost) into cost_material from item_goods i inner join directory d on (d.id = i.id) where d.owner_id = document_id;
		select sum(i.cost) into cost_operation from item_operation i inner join directory d on (d.id = i.id) where d.owner_id = document_id;
		select sum(i.cost) into cost_deduction from item_deduction i inner join directory d on (d.id = i.id) where d.owner_id = document_id;
      
		cost_material = coalesce(cost_material, 0::money);
		cost_operation = coalesce(cost_operation, 0::money);
		cost_deduction = coalesce(cost_deduction, 0::money);
		_cost = cost_material + cost_operation + cost_deduction;

		select profit_percent, profit_value, price into _profit_percent, _profit_value, _price from calculation where id = document_id;
		if (_profit_percent > 0 or _profit_value > 0::money) then
			if (_profit_percent > 0) then
				_profit_value = _cost * _profit_percent / 100;
			else
				_profit_percent = _profit_value / _cost * 100;
			end if;

			_price = _cost + _profit_value;
		else
			if (_price > 0::money) then
				_profit_value = _price - _cost;
				_profit_percent = _profit_value / _cost * 100;
			else
				_price = _cost;
			end if;
		end if;

		update calculation 
			set cost = _cost,
				profit_percent = _profit_percent,
				profit_value = _profit_value,
				price = _price
			where id = document_id;
	end if;
end;
$$;


ALTER FUNCTION public.complete_calculation(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 270 (class 1255 OID 103211)
-- Name: complete_goods(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.complete_goods(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	_price money;
begin
	-- СОСТАВЛЕН, ИЗМЕНЯЕТСЯ => КОРРЕКТЕН
	if (status_from in (1000, 1004) and status_to = 1001) then
		select price into _price from goods where id = document_id;
		if (_price = 0::money) then
			select c.price 
				into _price 
				from calculation c 
					join directory d on (d.id = c.id) 
				where 
					d.owner_id = document_id and d.status_id = 1002
				limit 1;

			_price = coalesce(_price, 0::money);
			update goods set price = _price where id = document_id;
		end if;    

	end if;
end;
$$;


ALTER FUNCTION public.complete_goods(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 258 (class 1255 OID 103209)
-- Name: complete_item_deduction(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.complete_item_deduction(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	count_item numeric;
	price_item money;
	cost_item money;
	do_update boolean;
	_accrual_base integer;
	_percentage numeric;
	_calc_deep boolean;
	_owner_id uuid;
begin
	-- СОСТАВЛЕН => КОРРЕКТЕН
	if (status_from = 1000 and status_to = 1001) then
		select i.percentage, i.price, i.cost, o.percentage, o.accrual_base, i.calc_deep
			into count_item, price_item, cost_item, _percentage, _accrual_base, _calc_deep
			from item_deduction i
				join deduction o on (o.id = i.deduction_id)
			where i.id = document_id;

		do_update = false;
		if (count_item = 0) then
			count_item = _percentage;
			do_update = true;
		end if;

		if (price_item = 0::money) then
			select d.owner_id
				into _owner_id
				from item_deduction i
					join directory d on (d.id = i.id)
				where i.id = document_id;

			if (_accrual_base = 1) then
				if (_calc_deep) then
					price_item = get_sum_item_goods(_owner_id);
				else
					select sum(i.cost) 
						into price_item
						from item_goods i
							join directory d on (d.id = i.id)
						where d.owner_id = _owner_id
						group by d.owner_id; 
				end if;
			else
				if (_calc_deep) then
					price_item = get_sum_item_operation(_owner_id);
				else
					select sum(i.cost) 
						into price_item
						from item_operation i
							join directory d on (d.id = i.id)
						where d.owner_id = _owner_id
						group by d.owner_id; 
				end if;
			end if;

			do_update = true;
		end if;
       
		price_item = coalesce(price_item, 0::money);
       
		if (do_update or cost_item = 0::money) then
			cost_item = price_item * count_item / 100;

			update item_deduction
				set percentage = count_item,
					price = price_item,
					cost = cost_item
				where id = document_id;
		end if;
	end if;
end;
$$;


ALTER FUNCTION public.complete_item_deduction(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 252 (class 1255 OID 103206)
-- Name: complete_item_goods(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.complete_item_goods(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	count_item numeric;
	price_item money;
	cost_item money;
	price_material money;
	do_update boolean;
begin
	-- СОСТАВЛЕН => КОРРЕКТЕН
	if (status_from = 1000 and status_to = 1001) then
		select i.goods_count, i.price, i.cost, g.price
			into count_item, price_item, cost_item, price_material
			from item_goods i
				join goods g on (g.id = i.goods_id)
			where i.id = document_id;

		do_update = false;
		if (price_item = 0::money) then
			price_item = price_material;
			do_update = true;
		end if;

		if (do_update or cost_item = 0::money) then
			cost_item = price_item * count_item;

			update item_goods
				set price = price_item,
					cost = cost_item
				where id = document_id;
		end if;
	end if;
end;
$$;


ALTER FUNCTION public.complete_item_goods(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 294 (class 1255 OID 103208)
-- Name: complete_item_operation(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.complete_item_operation(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
declare
	count_item numeric;
	price_item money;
	cost_item money;
	price_material money;
	do_update boolean;
begin
	-- СОСТАВЛЕН => КОРРЕКТЕН
	if (status_from = 1000 and status_to = 1001) then
		select i.operation_count, i.price, i.cost, o.salary
			into count_item, price_item, cost_item, price_material
			from item_operation i
				join operation o on (o.id = i.operation_id)
			where i.id = document_id;

		do_update = false;
		if (price_item = 0::money) then
			price_item = price_material;
			do_update = true;
		end if;

		if (do_update or cost_item = 0::money) then
			cost_item = price_item * count_item;

			update item_operation
				set price = price_item,
					cost = cost_item
				where id = document_id;
		end if;
	end if;
end;
$$;


ALTER FUNCTION public.complete_item_operation(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 303 (class 1255 OID 103205)
-- Name: complete_operation(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.complete_operation(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	_produced integer;
	_prod_time integer;
	_production_rate integer;
	_salary_value money;
	_salary_type money;
begin
	-- СОСТАВЛЕН, ИЗМЕНЯЕТСЯ => КОРРЕКТЕН
	if (status_from in (1000, 1004) and status_to = 1001) then
		select o.produced, o.prod_time, o.production_rate, o.salary, t.salary
			into _produced, _prod_time, _production_rate, _salary_value, _salary_type
			from operation o
				left join operation_type t on (t.id = o.type_id)
			where 
				o.id = document_id;

		_produced = coalesce(_produced, 0);
		_prod_time = coalesce(_prod_time, 0);

		_production_rate = coalesce(_production_rate, 0);
		if ((_production_rate = 0 or _produced != 0) and _prod_time != 0) then
			_production_rate = _produced * 3600 / _prod_time;
		end if;

		_salary_value = coalesce(_salary_value, 0::money);
		if (_salary_value = 0::money or _production_rate != 0) then
			_salary_value = (_salary_type / _production_rate)::money;
		end if;

		update operation 
		set production_rate = _production_rate,
			salary = _salary_value
		where id = document_id;
	end if;
end;
$$;


ALTER FUNCTION public.complete_operation(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 248 (class 1255 OID 127931)
-- Name: complete_operation_executor(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.complete_operation_executor(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	_order_id uuid;
	_goods_id uuid;
	_operation_id uuid;
	_operation_count integer;
	_op uuid;
	_op_count integer;
	_op_complete integer;
	rec_exec record;
	
begin
	-- ВТОРОЕ ДОПОЛНЕНИЕ => КОРРЕКТЕН
	if (status_from = 1018 and status_to = 1001) then
		update document
			set owner_id = _op
			where id = document_id;
	end if;

	-- КОРРЕКТЕН => ВЫПОЛНЕНО
	if (status_from = 1001 and status_to = 1016) then
		select o_e.order_id, o_e.goods_id, o_e.operation_id, o_e.operation_count
			into _order_id, _goods_id, _operation_id, _operation_count
			from operation_executor o_e
			where id = document_id;
		
		for rec_exec in
			select o_c.id
				from order_production o_p
					join document d_oc on (d_oc.owner_id = o_p.id)
					join order_complete o_c on (o_c.id = d_oc.id)
				where 
					o_p.id = _order_id and
					o_c.goods_id = _goods_id and
					d_oc.status_id = 1013
				order by d_oc.doc_date
		loop
			select o_e.id, o_e.operation_count, o_e.completed
				into _op, _op_count, _op_complete
				from operation_execute o_e
					join document d on (d.id = o_e.id)
				where
					d.owner_id = rec_exec.id and
					o_e.operation_id = _operation_id;
			
			if (_op is null) then
				raise 'Не найдена запись содержащая указанные данные о заказе, номенклатуре и операции.';
			end if;
				
			if (_operation_count + _op_complete <= _op_count) then
				_op_complete = _op_complete + _operation_count;
				_operation_count = 0;
			else
				_operation_count = _operation_count - (_op_count - _op_complete);
				_op_complete = _op_count;
			end if;
		
			update operation_execute
				set completed = _op_complete
				where id = _op;
			
			if (_op_complete = _op_count) then
				perform change_status(_op, 1016, true, 'Выполнены все операции');
			end if;
		end loop;
	
		if (_operation_count > 0) then
			raise 'Невозможно распределить указанное количество операций. Оно слишком большое!';
		end if;	
	end if;

	-- КОРРЕКТЕН => ИЗМЕНЯЕТСЯ
	if (status_from = 1001 and status_to = 1004) then
		update operation_executor
			set goods_id = null,
				operation_id = null,
				employee_id = null,
				operation_count = 0
			where id = document_id;
	end if;
end;
$$;


ALTER FUNCTION public.complete_operation_executor(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 266 (class 1255 OID 103484)
-- Name: complete_order(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.complete_order(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	cost_sum money;
	tax_value_sum money;
	cost_with_tax_sum money;
begin
	-- СОСТАВЛЕН, ИЗМЕНЯЕТСЯ => КОРРЕКТЕН
	if (status_from in (1000, 1004) and status_to = 1001) then
		select sum(cost), sum(tax_value), sum(cost_with_tax) 
			into cost_sum, tax_value_sum, cost_with_tax_sum
			from order_detail 
			where owner_id = document_id;
		update order_production
			set order_price = cost_sum,
				order_tax_value = tax_value_sum,
				order_price_with_tax = cost_with_tax_sum
			where id = document_id;
	end if;
end;
$$;


ALTER FUNCTION public.complete_order(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 296 (class 1255 OID 103520)
-- Name: complete_order_complete(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.complete_order_complete(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	order_goods record;
	order_id uuid;
	complete_id uuid;
	complete_count numeric(12, 3);
	new_remaind numeric(12, 3);
	active_calculation uuid;
begin
	select d.owner_id, o.goods_id, o.goods_count
		into order_id, complete_id, complete_count
		from order_complete o
			join document d on (d.id = o.id)
		where d.id = document_id;
	
	-- СОСТАВЛЕН, ИЗМЕНЯЕТСЯ => КОРРЕКТЕН
	if (status_from in (1000, 1004) and status_to = 1001) then
		select d.id
			into active_calculation
			from calculation c
				join directory d on (d.owner_id = complete_id)
			where d.status_id = 1002;
	
		if (active_calculation is null) then
			raise 'Для изделия "%" не найдена утвержденная калькуляция!', (select name from directory where id = complete_id);
		end if;
	end if;
	
	-- КОРРЕКТЕН => В ПРОИЗВОДСТВЕ
	if (status_from = 1001 and status_to = 1013) then
		perform fill_operation_execute(document_id);
	end if;
	
	-- В ПРОИЗВОДСТВЕ => ИЗГОТОВЛЕН
	if (status_from = 1013 and status_to = 1014) then
		for order_goods in 
			select id, goods_id, goods_count, remaind_count from order_detail where owner_id = order_id and remaind_count >= 0 and goods_id = complete_id
		loop
			if (complete_count < order_goods.remaind_count) then
				new_remaind = order_goods.remaind_count - complete_count;
				update order_detail
					set remaind_count = new_remaind,
						complete_status = round(((order_goods.goods_count - new_remaind) / order_goods.goods_count) * 100)
					where id = order_goods.id;
				
				complete_count = 0; 
			else
				update order_detail
					set remaind_count = 0,
						complete_status = 100
					where id = order_goods.id;
				complete_count = complete_count - order_goods.remaind_count;
			end if;
		
			if (complete_count = 0) then
				exit;
			end if;
		end loop;
	
		if (not exists(select 1 from order_detail where owner_id = order_id and complete_status < 100)) then
			perform change_status(order_id, 1014, true, 'Заказ полностью выполнен.');
		end if;
	end if;
end;
$$;


ALTER FUNCTION public.complete_order_complete(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 309 (class 1255 OID 119713)
-- Name: complete_order_shipped(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.complete_order_shipped(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	_goods_count numeric(12, 3); 
	_price money;
	_goods_id uuid;
	_tax integer;
	_tax_value money;
	_cost money;
	order_id uuid;
	order_goods record;
	can_change_status boolean;
begin
	select d.owner_id, o.price, o.goods_id, o.tax, o.goods_count
		into order_id, _price, _goods_id, _tax, _goods_count
		from order_shipped o
			join document d on (d.id = o.id)
		where d.id = document_id;
	
	-- СОСТАВЛЕН, ИЗМЕНЯЕТСЯ => КОРРЕКТЕН
	if (status_from in (1000, 1004) and status_to = 1001) then
		if (_price = 0::money) then
			select price into _price from goods where id = _goods_id;
		end if;

		if (_tax = 0) then
			_tax = 20;
		end if;
	
		_cost = _price * _goods_count;
		_tax_value = _cost * _tax / 100;
	
		update order_shipped
			set price = _price,
				tax = _tax,
				tax_value = _tax_value,
				cost = _cost,
				cost_with_tax = _cost + _tax_value 
			where id = document_id;
	end if;

	-- КОРРЕКТЕН => ОТГРУЖЕН
	if (status_from = 1001 and status_to = 1015) then
		can_change_status = true;
		for order_goods in
			select id, goods_id, goods_count from order_detail where owner_id = order_id
		loop
			select sum(goods_count)
				into _goods_count
				from order_shipped
				where id = document_id and goods_id = order_goods.goods_id;
			if (order_goods.goods_count != _goods_count) then
				can_change_status = false;
				exit;
			end if;
		end loop;
	
		if (can_change_status) then
			perform change_status(order_id, 1015, true, 'Заказ полностью отгружен.');
		end if;
	end if;
end;
$$;


ALTER FUNCTION public.complete_order_shipped(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 267 (class 1255 OID 103318)
-- Name: complete_request(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.complete_request(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	cost_sum money;
	tax_value_sum money;
	cost_with_tax_sum money;
begin
	-- СОСТАВЛЕН, ИЗМЕНЯЕТСЯ => КОРРЕКТЕН
	if (status_from in (1000, 1004) and status_to = 1001) then
		select sum(cost), sum(tax_value), sum(cost_with_tax)
			into cost_sum, tax_value_sum, cost_with_tax_sum 
			from request_detail 
			where owner_id = document_id;
		update request
			set request_price = cost_sum,
				request_tax_value = tax_value_sum,
				request_price_with_tax = cost_with_tax_sum
			where id = document_id;
	end if;

	-- КОРРЕКТЕН => ОТПРАВЛЕН
	if (status_from = 1001 and status_to = 1007) then
		update request
			set sending_date = current_timestamp
			where id = document_id;
	end if;
end;
$$;


ALTER FUNCTION public.complete_request(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 273 (class 1255 OID 78158)
-- Name: contractor_initialize(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.contractor_initialize() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  if new.short_name is null then
    select name into new.short_name from directory where directory.id = new.id;
  end if;
  
  return new;
end;
$$;


ALTER FUNCTION public.contractor_initialize() OWNER TO postgres;

--
-- TOC entry 304 (class 1255 OID 78163)
-- Name: contractor_test_inn(numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.contractor_test_inn(inn numeric) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
declare
   inn_arr integer[];
   k integer[] := '{ 2, 4, 10, 3, 5, 9, 4, 6, 8 }';
   k1 integer[] := '{ 7, 2, 4, 10, 3, 5, 9, 4, 6, 8 }';
   k2 integer[] := '{3, 7, 2, 4, 10, 3, 5, 9, 4, 6, 8 }';
begin
   inn_arr := string_to_array(inn::character varying, NULL)::integer[];

   if (array_length(inn_arr, 1) != 10 and array_length(inn_arr, 1) != 12) then
      return false;
   end if;

   if (control_value(inn_arr, k, 11) = inn_arr[10]) then
      if (array_length(inn_arr, 1) = 12) then
         return control_value(inn_arr, k1, 11) == inn_arr[11] && control_value(inn_arr, k2, 11) == inn_arr[12];
      end if;
		
      return true;
   end if;

   return false;
end;
$$;


ALTER FUNCTION public.contractor_test_inn(inn numeric) OWNER TO postgres;

--
-- TOC entry 319 (class 1255 OID 78164)
-- Name: contractor_test_okpo(numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.contractor_test_okpo(okpo numeric) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
declare
   okpo_arr integer[];
   k1 integer[] := '{ 1, 2, 3, 4, 5, 6, 7 }';
   k2 integer[] := '{ 3, 4, 5, 6, 7, 8, 9 }';
   c integer;
begin
   okpo_arr := string_to_array(lpad(okpo::character varying, 8, '0'), NULL)::integer[];
   if (array_length(okpo_arr, 1) < 8) then
      return false;
   end if;
	
   c := control_value(okpo_arr, k1, 11, false);
   if (c > 9) then
      c := control_value(okpo_arr, k2, 11);
   end if;

   return c = okpo_arr[8];
end;
$$;


ALTER FUNCTION public.contractor_test_okpo(okpo numeric) OWNER TO postgres;

--
-- TOC entry 262 (class 1255 OID 78161)
-- Name: control_sum(integer[], integer[]); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.control_sum(source integer[], coeff integer[]) RETURNS integer
    LANGUAGE plpgsql IMMUTABLE
    AS $$
declare
   sum integer;
   m integer;
begin
   m := min_int(array_length(source, 1), array_length(coeff, 1));

   sum := 0;
   for i in 1 .. m loop
      sum := sum + source[i] * coeff[i];
   end loop;
	
   return sum;
end;
$$;


ALTER FUNCTION public.control_sum(source integer[], coeff integer[]) OWNER TO postgres;

--
-- TOC entry 249 (class 1255 OID 78162)
-- Name: control_value(integer[], integer[], integer, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.control_value(source integer[], coeff integer[], divider integer, test10 boolean DEFAULT true) RETURNS integer
    LANGUAGE plpgsql IMMUTABLE
    AS $$
declare
   r integer;
begin
   r := control_sum(source, coeff) % divider;
   if (test10 and r = 10) then
      r := 0;
   end if;

   return r;
end;
$$;


ALTER FUNCTION public.control_value(source integer[], coeff integer[], divider integer, test10 boolean) OWNER TO postgres;

--
-- TOC entry 310 (class 1255 OID 78076)
-- Name: document_checking(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.document_checking() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  current_type character varying(20);
  is_valid boolean;
  changing_id uuid;
  parent_code character varying(20);
  parent_name character varying(255);
  parent_status bigint;
  ref_id uuid;
  status_from bigint; 
  status_to bigint;
begin
  select e.code into current_type 
    from kind k
      join kind_enum e on (e.id = k.enum_id)
    where k.id = new.kind_id;
    
  case
    when tg_table_name = 'directory' then
      is_valid = current_type = 'directory';
    when tg_table_name = 'document' then
      is_valid = current_type = 'document';
    else
      is_valid = false;
  end case;

  if not is_valid then
    raise 'Неверный тип добавляемого документа/справочника.';
  end if;

  if tg_op = 'UPDATE' then
    -- проверим право пользователя менять состояние документа
    if new.status_id != old.status_id then
      select c.id 
        into changing_id 
        from kind k
          join transition t on (k.transition_id = t.id)
          join changing_status c on (c.transition_id = t.id)
        where
          k.id = new.kind_id and
          old.status_id in (0, c.status_from_id) and
          c.status_to_id = new.status_id;
          
      if changing_id is null then
        raise 'Переход документа из состояния "%" в состояние "%" невозможен.',
          (select note from status where id = old.status_id),
          (select note from status where id = new.status_id);
      end if;
      
      -- изменение состояния возможно только с помощью процедуры change_status,
      -- в которой создаётся запись в таблице истории
      if old.status_id != 0 then
        select status_from_id, 
               status_to_id, 
               reference_id
          into status_from, status_to, ref_id
          from history
          where id = new.history_id;

        ref_id = coalesce(ref_id, uuid_nil());
        if (new.id != ref_id) then
          raise 'Некорректное значение справочника в истории переводов';
        end if;

        status_from = coalesce(status_from, 0);
        status_to = coalesce(status_to, 0);
        if (old.status_id != status_from) or (new.status_id != status_to) then
          raise 'Для корректного перевода воспользуйтесь процедурой change_status()';
        end if;
      end if;
    end if;
    
    if new.kind_id != old.kind_id then
      raise 'Тип документа менять нельзя.';
    end if;
    
    if tg_table_name = 'directory' then
      if new.code != old.code and left(new.code, char_length(new.discriminator)) = new.discriminator then
        raise 'Значение поля "Код" начинающееся с "%" является зарезервированным', new.discriminator;
      end if;
    end if;
  end if;
  
  if tg_op = 'INSERT' then
  end if;
  
  if tg_table_name = 'directory' then
    if new.parent_id is not null then
      select code, name, status_id
        into parent_code, parent_name, parent_status
        from directory
        where id = new.parent_id;

      if parent_status != 500 then
        parent_name = coalesce(parent_name, '');
        if parent_name = '' then
          parent_name = parent_code;
        end if;

        raise 'Запись справочника "%" не является группой.', parent_name;
      end if;
    end if;
  end if;

  return new;
end;
$$;


ALTER FUNCTION public.document_checking() OWNER TO postgres;

--
-- TOC entry 271 (class 1255 OID 77987)
-- Name: document_initialize(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.document_initialize() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  user_id uuid;
  new_status bigint;
  dir_has_group boolean;
  discriminator character varying(20);
  doc_prefix character varying(5);
  doc_digits integer;
begin
  select id into user_id from user_alias where pg_name = session_user;

  new.user_created_id = user_id;
  new.date_created = current_timestamp;

  new.user_updated_id = user_id;
  new.date_updated = current_timestamp;
   
  -- стартовое значение состояния документа указанное в new.kind_id
  select t.starting_status_id, k.has_group, k.prefix, k.number_digits
    into new_status, dir_has_group, doc_prefix, doc_digits
    from kind k
      join transition t on (t.id = k.transition_id)
    where k.id = new.kind_id;
    
  if new.status_id is null or new.status_id != 500 or not dir_has_group then
    new.status_id = new_status;
  end if;
  
  select code 
    into new.discriminator 
    from kind 
    where id = new.kind_id;
    
  if (tg_table_name = 'directory') then
    if new.code is null then
      new.code = new.discriminator || '_' || nextval('directory_code_seq');
    end if;
  end if;
  
  if (tg_table_name = 'document') then
    new.doc_date = current_timestamp;
    new.doc_year = extract(year from new.doc_date);
    select max(doc_number) + 1 into new.doc_number from document where kind_id = new.kind_id and doc_year = new.doc_year;
    
    new.doc_number = coalesce(new.doc_number, 1);
    doc_digits = coalesce(doc_digits, 0);
    doc_prefix = coalesce(doc_prefix, '');
    if (doc_digits = 0) then
      new.view_number = doc_prefix || new.doc_number;
    else
      new.view_number = doc_prefix || lpad(new.doc_number::varchar, doc_digits, '0');
    end if;
   
	select id into new.organization_id from organization where default_org = true limit 1;
  end if;
    
  return new;
end;
$$;


ALTER FUNCTION public.document_initialize() OWNER TO postgres;

--
-- TOC entry 291 (class 1255 OID 78187)
-- Name: document_updated(uuid, bigint, bigint, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.document_updated(document_id uuid, status_from bigint, status_to bigint, auto boolean DEFAULT false) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
  doc_kind uuid;
begin
	select kind_id into doc_kind from document_info where id = document_id;

	case doc_kind
		-- производственные операции
		when get_uuid('operation') then
			perform complete_operation(document_id, status_from, status_to, auto);
		
		-- список сырья и основных материалов
		when get_uuid('item_goods') then
			perform complete_item_goods(document_id, status_from, status_to, auto);
		
		-- список операций
		when get_uuid('item_operation') then
			perform complete_item_operation(document_id, status_from, status_to, auto);
		
		-- список отчислений
		when get_uuid('item_deduction') then
			perform complete_item_deduction(document_id, status_from, status_to, auto);
		
		-- калькуляция
		when get_uuid('calculation') then
			perform complete_calculation(document_id, status_from, status_to, auto);
		
		-- номенклатура
		when get_uuid('goods') then
			perform complete_goods(document_id, status_from, status_to, auto);
		
		-- заявка на приобретение материалов
		when get_uuid('request') then
			perform complete_request(document_id, status_from, status_to, auto);
		
		-- заказ на изготовление
		when get_uuid('order_production') then
			perform complete_order(document_id, status_from, status_to, auto);
		
		-- выполнение заказа
		when get_uuid('order_complete') then
			perform complete_order_complete(document_id, status_from, status_to, auto);
		
		-- отгрузка заказа
		when get_uuid('order_shipped') then
			perform complete_order_shipped(document_id, status_from, status_to, auto);
		
		-- Выполненные операции
		when get_uuid('operation_executor') then
			perform complete_operation_executor(document_id, status_from, status_to, auto);
        
        else
        	-- nothing
	end case;
end;
$$;


ALTER FUNCTION public.document_updated(document_id uuid, status_from bigint, status_to bigint, auto boolean) OWNER TO postgres;

--
-- TOC entry 322 (class 1255 OID 77991)
-- Name: document_updating(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.document_updating() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
  user_id uuid;
begin
  select id into user_id from user_alias where pg_name = session_user;
  new.user_updated_id = user_id;
  new.date_updated = current_timestamp;
  return new;
end;
$$;


ALTER FUNCTION public.document_updating() OWNER TO postgres;

--
-- TOC entry 293 (class 1255 OID 119749)
-- Name: fill_operation_execute(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fill_operation_execute(order_complete_id uuid) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
	c_id uuid;
	cnt numeric(12, 3);
	rec rec_operation;
	new_id uuid;
begin
	select calculation_id, goods_count into c_id, cnt from order_complete where id = order_complete_id;

	for rec in
		select operation_id, sum(operation_count) as operation_count from get_operations(c_id) group by operation_id
	loop
		new_id = uuid_generate_v4();
		insert into document (id, owner_id, kind_id) values (new_id, order_complete_id, get_uuid('operation_execute'));
		insert into operation_execute (id, operation_id, operation_count) values (new_id, rec.operation_id, rec.operation_count * cnt);
		perform change_status(new_id, 1001, true, 'Строка выполнения заказа переведена в состояние В ПРОИЗВОДСТВЕ');
	end loop;
end;
$$;


ALTER FUNCTION public.fill_operation_execute(order_complete_id uuid) OWNER TO postgres;

--
-- TOC entry 313 (class 1255 OID 119756)
-- Name: get_operations(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_operations(calculation_id uuid) RETURNS SETOF public.rec_operation
    LANGUAGE plpgsql
    AS $$
declare
	rec rec_operation;
	calculations record;
begin
	for rec in
		select i.operation_id, i.operation_count
			from calculation c
				join directory d on (d.owner_id = c.id)
				join item_operation i on (i.id = d.id)
			where c.id = calculation_id
	loop
		return next rec;
	end loop;

	for calculations in
		select ic.id, i.goods_count
			from calculation c
				join directory d on (d.owner_id = c.id)
				join item_goods i on (i.id = d.id)
				join directory dc on (dc.owner_id = i.goods_id)
				join calculation ic on (ic.id = dc.id)
			where c.id = calculation_id
	loop
		for rec in
			select * from get_operations(calculations.id)
		loop
			rec.operation_count = rec.operation_count * calculations.goods_count;
			return next rec;
		end loop;
	end loop;
end;
$$;


ALTER FUNCTION public.get_operations(calculation_id uuid) OWNER TO postgres;

--
-- TOC entry 3314 (class 0 OID 0)
-- Dependencies: 313
-- Name: FUNCTION get_operations(calculation_id uuid); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.get_operations(calculation_id uuid) IS 'Список операций для указанной калькуляции (с учетом полуфабрикатов)';


--
-- TOC entry 261 (class 1255 OID 103225)
-- Name: get_sum_item_goods(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_sum_item_goods(g_id uuid) RETURNS money
    LANGUAGE plpgsql
    AS $$
declare
	cost_items money;
	count_sum money;
	item record;
begin
	count_sum = 0::money;
	for item in 
		select items.goods_id, items.goods_count, items.cost, calc.id calc_id
			from item_goods items
				join directory items_detail on (items_detail.id = items.id and items_detail.status_id = 1001)
				join directory g on (g.id = items.goods_id)
				left join directory calc on (calc.owner_id = g.id and calc.status_id = 1002)
			where items_detail.owner_id = g_id
	loop
		if (item.calc_id is null) then
			count_sum = count_sum + item.cost;
		else
			count_sum = count_sum + get_sum_item_goods(item.calc_id) * item.goods_count;
		end if;
	end loop;

	return count_sum;
end;
$$;


ALTER FUNCTION public.get_sum_item_goods(g_id uuid) OWNER TO postgres;

--
-- TOC entry 3315 (class 0 OID 0)
-- Dependencies: 261
-- Name: FUNCTION get_sum_item_goods(g_id uuid); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.get_sum_item_goods(g_id uuid) IS 'Вычисление стоимости материалов в указанной калькуляции, включая полуфабрикаты';


--
-- TOC entry 276 (class 1255 OID 103227)
-- Name: get_sum_item_operation(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_sum_item_operation(g_id uuid) RETURNS money
    LANGUAGE plpgsql
    AS $$
declare
	count_sum money;
	item record;
begin
	select sum(i.cost)
		into count_sum
		from item_operation i
			join directory di on (di.id = i.id)
		where di.owner_id = g_id;
	
	count_sum = coalesce(count_sum, 0::money);
	for item in 
		select calc.id calc_id, items.goods_count
			from item_goods items
				join directory items_detail on (items_detail.id = items.id and items_detail.status_id = 1001)
				join directory g on (g.id = items.goods_id)
				join directory calc on (calc.owner_id = g.id and calc.status_id = 1002)
			where items_detail.owner_id = g_id
	loop
		count_sum = count_sum + get_sum_item_operation(item.calc_id) * item.goods_count;
	end loop;

	return count_sum;
end;
$$;


ALTER FUNCTION public.get_sum_item_operation(g_id uuid) OWNER TO postgres;

--
-- TOC entry 3316 (class 0 OID 0)
-- Dependencies: 276
-- Name: FUNCTION get_sum_item_operation(g_id uuid); Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON FUNCTION public.get_sum_item_operation(g_id uuid) IS 'Вычисление стоимости производственных операций в указанной калькуляции, включая полуфабрикаты';


--
-- TOC entry 286 (class 1255 OID 103014)
-- Name: get_uuid(character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_uuid(kind_name character varying) RETURNS uuid
    LANGUAGE sql IMMUTABLE
    AS $$
select id from kind where code = kind_name;
$$;


ALTER FUNCTION public.get_uuid(kind_name character varying) OWNER TO postgres;

--
-- TOC entry 311 (class 1255 OID 78045)
-- Name: history_initialize(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.history_initialize() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.changed = current_timestamp;
  return new;
end;
$$;


ALTER FUNCTION public.history_initialize() OWNER TO postgres;

--
-- TOC entry 289 (class 1255 OID 94706)
-- Name: lock_document(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.lock_document(document_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  user_id uuid;
begin
  select id into user_id from user_alias where pg_name = session_user;
  update document_info set date_locked = current_timestamp, user_locked_id = user_id where id = document_id;
end;
$$;


ALTER FUNCTION public.lock_document(document_id uuid) OWNER TO postgres;

--
-- TOC entry 247 (class 1255 OID 78097)
-- Name: login(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.login() RETURNS void
    LANGUAGE plpgsql
    AS $$
begin

end;
$$;


ALTER FUNCTION public.login() OWNER TO postgres;

--
-- TOC entry 256 (class 1255 OID 78098)
-- Name: logout(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.logout() RETURNS void
    LANGUAGE plpgsql
    AS $$
begin
end;
$$;


ALTER FUNCTION public.logout() OWNER TO postgres;

--
-- TOC entry 323 (class 1255 OID 78160)
-- Name: min_int(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.min_int(left_value integer, right_value integer) RETURNS integer
    LANGUAGE plpgsql IMMUTABLE
    AS $$
declare
   m integer;
begin
   if (left_value < right_value) then
      m = left_value;
   else
      m = right_value;
   end if;

   return m;
end;
$$;


ALTER FUNCTION public.min_int(left_value integer, right_value integer) OWNER TO postgres;

--
-- TOC entry 263 (class 1255 OID 94707)
-- Name: unlock_document(uuid); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.unlock_document(document_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  user_id uuid;
begin
  select id into user_id from user_alias where pg_name = session_user;
  update document_info set date_locked = null, user_locked_id = null where id = document_id;
end;
$$;


ALTER FUNCTION public.unlock_document(document_id uuid) OWNER TO postgres;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- TOC entry 217 (class 1259 OID 78299)
-- Name: account; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.account (
    id uuid NOT NULL,
    account_value numeric(20,0),
    bank_id uuid
);


ALTER TABLE public.account OWNER TO postgres;

--
-- TOC entry 3317 (class 0 OID 0)
-- Dependencies: 217
-- Name: TABLE account; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.account IS 'Расчётные счета';


--
-- TOC entry 213 (class 1259 OID 78206)
-- Name: bank; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.bank (
    id uuid NOT NULL,
    bik numeric(9,0),
    account numeric(20,0)
);


ALTER TABLE public.bank OWNER TO postgres;

--
-- TOC entry 3319 (class 0 OID 0)
-- Dependencies: 213
-- Name: TABLE bank; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.bank IS 'Банки';


--
-- TOC entry 220 (class 1259 OID 102925)
-- Name: calculation; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.calculation (
    id uuid NOT NULL,
    cost money,
    profit_percent numeric(6,2),
    profit_value money,
    price money,
    note character varying,
    CONSTRAINT chk_calculation_profit_percent CHECK ((profit_percent >= (0)::numeric))
);


ALTER TABLE public.calculation OWNER TO postgres;

--
-- TOC entry 3321 (class 0 OID 0)
-- Dependencies: 220
-- Name: TABLE calculation; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.calculation IS 'Калькуляции';


--
-- TOC entry 3322 (class 0 OID 0)
-- Dependencies: 220
-- Name: COLUMN calculation.cost; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.calculation.cost IS 'Себестоимость';


--
-- TOC entry 3323 (class 0 OID 0)
-- Dependencies: 220
-- Name: COLUMN calculation.profit_percent; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.calculation.profit_percent IS 'Прибыль (процент от себестоимости)';


--
-- TOC entry 3324 (class 0 OID 0)
-- Dependencies: 220
-- Name: COLUMN calculation.profit_value; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.calculation.profit_value IS 'Прибыль';


--
-- TOC entry 3325 (class 0 OID 0)
-- Dependencies: 220
-- Name: COLUMN calculation.price; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.calculation.price IS 'Цена';


--
-- TOC entry 3326 (class 0 OID 0)
-- Dependencies: 220
-- Name: COLUMN calculation.note; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.calculation.note IS 'Описание';


--
-- TOC entry 207 (class 1259 OID 78052)
-- Name: changing_status; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.changing_status (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name character varying(50) NOT NULL,
    transition_id uuid NOT NULL,
    status_from_id bigint NOT NULL,
    status_to_id bigint NOT NULL,
    picture_id uuid,
    order_index bigint DEFAULT 0,
    CONSTRAINT chk_changing_status CHECK ((status_from_id <> status_to_id))
);


ALTER TABLE public.changing_status OWNER TO postgres;

--
-- TOC entry 209 (class 1259 OID 78114)
-- Name: command; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.command (
    id uuid NOT NULL,
    refresh_dataset boolean DEFAULT false NOT NULL,
    refresh_record boolean DEFAULT false NOT NULL,
    refresh_sidebar boolean DEFAULT false NOT NULL
);


ALTER TABLE public.command OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 102970)
-- Name: condition; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.condition (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    kind_id uuid NOT NULL,
    changing_status_id uuid NOT NULL,
    confirmation boolean DEFAULT false,
    empty_note boolean DEFAULT true
);


ALTER TABLE public.condition OWNER TO postgres;

--
-- TOC entry 3330 (class 0 OID 0)
-- Dependencies: 223
-- Name: COLUMN condition.confirmation; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.condition.confirmation IS 'Для перевода необходимо подтверждение';


--
-- TOC entry 3331 (class 0 OID 0)
-- Dependencies: 223
-- Name: COLUMN condition.empty_note; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.condition.empty_note IS 'Поле note должно быть заполнено';


--
-- TOC entry 210 (class 1259 OID 78141)
-- Name: contractor; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.contractor (
    id uuid NOT NULL,
    short_name character varying(50),
    full_name character varying(150),
    inn numeric(12,0),
    kpp numeric(9,0),
    ogrn numeric(13,0),
    okpo numeric(8,0),
    okopf_id uuid,
    account_id uuid,
    tax_payer boolean
);


ALTER TABLE public.contractor OWNER TO postgres;

--
-- TOC entry 3333 (class 0 OID 0)
-- Dependencies: 210
-- Name: TABLE contractor; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.contractor IS 'Контрагенты';


--
-- TOC entry 3334 (class 0 OID 0)
-- Dependencies: 210
-- Name: COLUMN contractor.short_name; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.contractor.short_name IS 'Краткое наименование';


--
-- TOC entry 3335 (class 0 OID 0)
-- Dependencies: 210
-- Name: COLUMN contractor.full_name; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.contractor.full_name IS 'Полное наименование';


--
-- TOC entry 3336 (class 0 OID 0)
-- Dependencies: 210
-- Name: COLUMN contractor.inn; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.contractor.inn IS 'Индивидуальный номер налогоплателщика';


--
-- TOC entry 3337 (class 0 OID 0)
-- Dependencies: 210
-- Name: COLUMN contractor.kpp; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.contractor.kpp IS 'Код причины постановки на учет';


--
-- TOC entry 3338 (class 0 OID 0)
-- Dependencies: 210
-- Name: COLUMN contractor.ogrn; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.contractor.ogrn IS 'Основной государственный регистрационный номер';


--
-- TOC entry 3339 (class 0 OID 0)
-- Dependencies: 210
-- Name: COLUMN contractor.okpo; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.contractor.okpo IS 'Общероссийский классификатор предприятий и организаций';


--
-- TOC entry 3340 (class 0 OID 0)
-- Dependencies: 210
-- Name: COLUMN contractor.tax_payer; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.contractor.tax_payer IS 'Является плательщиком НДС';


--
-- TOC entry 228 (class 1259 OID 103130)
-- Name: deduction; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.deduction (
    id uuid NOT NULL,
    accrual_base integer,
    percentage numeric(5,2),
    CONSTRAINT chk_deduction_accrual_base CHECK ((accrual_base = ANY (ARRAY[0, 1, 2]))),
    CONSTRAINT chk_deduction_base_percent CHECK ((percentage >= (0)::numeric))
);


ALTER TABLE public.deduction OWNER TO postgres;

--
-- TOC entry 3342 (class 0 OID 0)
-- Dependencies: 228
-- Name: TABLE deduction; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.deduction IS 'Список начислений выраженных в процентах от базы (цена всех материалов или ФОТ)';


--
-- TOC entry 3343 (class 0 OID 0)
-- Dependencies: 228
-- Name: COLUMN deduction.accrual_base; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.deduction.accrual_base IS 'База для начислений (1 - материалы, 2 - заработная плата)';


--
-- TOC entry 202 (class 1259 OID 77897)
-- Name: document_info; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.document_info (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    status_id bigint NOT NULL,
    owner_id uuid,
    kind_id uuid NOT NULL,
    user_created_id uuid NOT NULL,
    date_created timestamp with time zone NOT NULL,
    user_updated_id uuid NOT NULL,
    date_updated timestamp with time zone NOT NULL,
    user_locked_id uuid,
    date_locked timestamp with time zone,
    history_id bigint,
    discriminator character varying(20)
);


ALTER TABLE public.document_info OWNER TO postgres;

--
-- TOC entry 3345 (class 0 OID 0)
-- Dependencies: 202
-- Name: COLUMN document_info.status_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.document_info.status_id IS 'Текущее состояние документа';


--
-- TOC entry 3346 (class 0 OID 0)
-- Dependencies: 202
-- Name: COLUMN document_info.owner_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.document_info.owner_id IS 'Владелец текущего документа';


--
-- TOC entry 3347 (class 0 OID 0)
-- Dependencies: 202
-- Name: COLUMN document_info.kind_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.document_info.kind_id IS 'Ссылка на описание свойств документа';


--
-- TOC entry 3348 (class 0 OID 0)
-- Dependencies: 202
-- Name: COLUMN document_info.user_created_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.document_info.user_created_id IS 'Пользователь создавший документ';


--
-- TOC entry 3349 (class 0 OID 0)
-- Dependencies: 202
-- Name: COLUMN document_info.date_created; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.document_info.date_created IS 'Дата создания документа';


--
-- TOC entry 3350 (class 0 OID 0)
-- Dependencies: 202
-- Name: COLUMN document_info.user_updated_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.document_info.user_updated_id IS 'Пользователь изменивший документ документ';


--
-- TOC entry 3351 (class 0 OID 0)
-- Dependencies: 202
-- Name: COLUMN document_info.date_updated; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.document_info.date_updated IS 'Дата изменения документа';


--
-- TOC entry 3352 (class 0 OID 0)
-- Dependencies: 202
-- Name: COLUMN document_info.user_locked_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.document_info.user_locked_id IS 'Пользователь заблокировавший документ';


--
-- TOC entry 3353 (class 0 OID 0)
-- Dependencies: 202
-- Name: COLUMN document_info.date_locked; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.document_info.date_locked IS 'Дата блокирования документа';


--
-- TOC entry 203 (class 1259 OID 77910)
-- Name: directory; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.directory (
    code character varying(20) NOT NULL,
    name character varying(255),
    parent_id uuid,
    picture_id uuid
)
INHERITS (public.document_info);


ALTER TABLE public.directory OWNER TO postgres;

--
-- TOC entry 211 (class 1259 OID 78176)
-- Name: directory_code_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.directory_code_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.directory_code_seq OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 103021)
-- Name: document; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.document (
    doc_date timestamp with time zone NOT NULL,
    doc_year integer NOT NULL,
    doc_number bigint NOT NULL,
    view_number character varying(20) NOT NULL,
    organization_id uuid
)
INHERITS (public.document_info);


ALTER TABLE public.document OWNER TO postgres;

--
-- TOC entry 235 (class 1259 OID 103336)
-- Name: employee; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.employee (
    id uuid NOT NULL,
    person_id uuid,
    post_id uuid,
    phone character varying(30),
    email character varying(100),
    post_role integer,
    CONSTRAINT chk_employee_post_role CHECK (((post_role >= 0) AND (post_role < 5)))
);


ALTER TABLE public.employee OWNER TO postgres;

--
-- TOC entry 3358 (class 0 OID 0)
-- Dependencies: 235
-- Name: CONSTRAINT chk_employee_post_role ON employee; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON CONSTRAINT chk_employee_post_role ON public.employee IS '0 - роль неопределена
1 - руководитель
2 - гл. бухгалтер
3 - служащий
4 - рабочий';


--
-- TOC entry 237 (class 1259 OID 103388)
-- Name: form_preview; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.form_preview (
    id uuid NOT NULL,
    kind_id uuid NOT NULL,
    data_text xml,
    default_form boolean DEFAULT false,
    data_properties jsonb
);


ALTER TABLE public.form_preview OWNER TO postgres;

--
-- TOC entry 214 (class 1259 OID 78222)
-- Name: goods; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.goods (
    id uuid NOT NULL,
    ext_article character varying(100),
    measurement_id uuid,
    price money,
    tax integer,
    min_order numeric(15,3),
    is_service boolean,
    CONSTRAINT chk_goods_price CHECK (((price IS NULL) OR (price >= (0.0)::money)))
);


ALTER TABLE public.goods OWNER TO postgres;

--
-- TOC entry 3361 (class 0 OID 0)
-- Dependencies: 214
-- Name: TABLE goods; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.goods IS 'Номенклатура';


--
-- TOC entry 3362 (class 0 OID 0)
-- Dependencies: 214
-- Name: COLUMN goods.ext_article; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.goods.ext_article IS 'Артикул';


--
-- TOC entry 3363 (class 0 OID 0)
-- Dependencies: 214
-- Name: COLUMN goods.measurement_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.goods.measurement_id IS 'Еденица измерения';


--
-- TOC entry 3364 (class 0 OID 0)
-- Dependencies: 214
-- Name: COLUMN goods.price; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.goods.price IS 'Цена';


--
-- TOC entry 3365 (class 0 OID 0)
-- Dependencies: 214
-- Name: COLUMN goods.tax; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.goods.tax IS 'Значение НДС';


--
-- TOC entry 3366 (class 0 OID 0)
-- Dependencies: 214
-- Name: COLUMN goods.min_order; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.goods.min_order IS 'Минимальная партия заказа';


--
-- TOC entry 3367 (class 0 OID 0)
-- Dependencies: 214
-- Name: COLUMN goods.is_service; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.goods.is_service IS 'Это услуга';


--
-- TOC entry 206 (class 1259 OID 78019)
-- Name: history; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.history (
    id bigint NOT NULL,
    reference_id uuid NOT NULL,
    status_from_id bigint NOT NULL,
    status_to_id bigint NOT NULL,
    changed timestamp with time zone NOT NULL,
    user_id uuid NOT NULL,
    auto boolean NOT NULL,
    note character varying(255)
);


ALTER TABLE public.history OWNER TO postgres;

--
-- TOC entry 3369 (class 0 OID 0)
-- Dependencies: 206
-- Name: COLUMN history.user_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.history.user_id IS 'Автор перевода состояния';


--
-- TOC entry 205 (class 1259 OID 78017)
-- Name: history_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.history_id_seq OWNER TO postgres;

--
-- TOC entry 3371 (class 0 OID 0)
-- Dependencies: 205
-- Name: history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.history_id_seq OWNED BY public.history.id;


--
-- TOC entry 230 (class 1259 OID 103154)
-- Name: item_deduction; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.item_deduction (
    id uuid NOT NULL,
    deduction_id uuid,
    percentage numeric(5,2),
    price money,
    cost money,
    calc_deep boolean DEFAULT false
);


ALTER TABLE public.item_deduction OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 102940)
-- Name: item_goods; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.item_goods (
    id uuid NOT NULL,
    goods_id uuid,
    goods_count numeric(12,3),
    price money,
    cost money
);


ALTER TABLE public.item_goods OWNER TO postgres;

--
-- TOC entry 3374 (class 0 OID 0)
-- Dependencies: 221
-- Name: COLUMN item_goods.goods_count; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.item_goods.goods_count IS 'Количество';


--
-- TOC entry 3375 (class 0 OID 0)
-- Dependencies: 221
-- Name: COLUMN item_goods.price; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.item_goods.price IS 'Цена за еденицу номенклатуры';


--
-- TOC entry 3376 (class 0 OID 0)
-- Dependencies: 221
-- Name: COLUMN item_goods.cost; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.item_goods.cost IS 'Сумма';


--
-- TOC entry 222 (class 1259 OID 102955)
-- Name: item_operation; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.item_operation (
    id uuid NOT NULL,
    operation_id uuid,
    operation_count integer,
    price money,
    cost money
);


ALTER TABLE public.item_operation OWNER TO postgres;

--
-- TOC entry 3378 (class 0 OID 0)
-- Dependencies: 222
-- Name: COLUMN item_operation.operation_count; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.item_operation.operation_count IS 'Количество операций';


--
-- TOC entry 3379 (class 0 OID 0)
-- Dependencies: 222
-- Name: COLUMN item_operation.price; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.item_operation.price IS 'Расценка за операцию';


--
-- TOC entry 3380 (class 0 OID 0)
-- Dependencies: 222
-- Name: COLUMN item_operation.cost; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.item_operation.cost IS 'Сумма';


--
-- TOC entry 201 (class 1259 OID 77868)
-- Name: kind; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.kind (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    code character varying(255) NOT NULL,
    name character varying(40),
    title character varying(255),
    is_system boolean DEFAULT false NOT NULL,
    has_group boolean DEFAULT false NOT NULL,
    enum_id uuid NOT NULL,
    picture_id uuid,
    transition_id uuid,
    schema_viewer jsonb,
    schema_editor jsonb,
    prefix character varying(5),
    number_digits integer DEFAULT 0,
    CONSTRAINT chk_kind_number_digits CHECK (((number_digits >= 0) AND (number_digits <= 15)))
);


ALTER TABLE public.kind OWNER TO postgres;

--
-- TOC entry 3382 (class 0 OID 0)
-- Dependencies: 201
-- Name: TABLE kind; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.kind IS 'Таблицы доступные для просмотра и редактирования';


--
-- TOC entry 3383 (class 0 OID 0)
-- Dependencies: 201
-- Name: COLUMN kind.code; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.kind.code IS 'Уникальный текстовый код документа';


--
-- TOC entry 3384 (class 0 OID 0)
-- Dependencies: 201
-- Name: COLUMN kind.name; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.kind.name IS 'Сокращенное наименование документа/справочника';


--
-- TOC entry 3385 (class 0 OID 0)
-- Dependencies: 201
-- Name: COLUMN kind.title; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.kind.title IS 'Полное наименование документа/справочника';


--
-- TOC entry 3386 (class 0 OID 0)
-- Dependencies: 201
-- Name: COLUMN kind.enum_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.kind.enum_id IS 'Вид документа';


--
-- TOC entry 3387 (class 0 OID 0)
-- Dependencies: 201
-- Name: COLUMN kind.prefix; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.kind.prefix IS 'Префикс для номерных документов';


--
-- TOC entry 3388 (class 0 OID 0)
-- Dependencies: 201
-- Name: COLUMN kind.number_digits; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.kind.number_digits IS 'Число цифр в номере документа (дополняются нулями)';


--
-- TOC entry 216 (class 1259 OID 78243)
-- Name: kind_child; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.kind_child (
    id bigint NOT NULL,
    master_id uuid NOT NULL,
    child_id uuid NOT NULL,
    order_index integer DEFAULT 0
);


ALTER TABLE public.kind_child OWNER TO postgres;

--
-- TOC entry 215 (class 1259 OID 78241)
-- Name: kind_child_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.kind_child_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.kind_child_id_seq OWNER TO postgres;

--
-- TOC entry 3391 (class 0 OID 0)
-- Dependencies: 215
-- Name: kind_child_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.kind_child_id_seq OWNED BY public.kind_child.id;


--
-- TOC entry 200 (class 1259 OID 77860)
-- Name: kind_enum; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.kind_enum (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    code character varying(20) NOT NULL,
    name character varying(80)
);


ALTER TABLE public.kind_enum OWNER TO postgres;

--
-- TOC entry 212 (class 1259 OID 78195)
-- Name: measurement; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.measurement (
    id uuid NOT NULL,
    abbreviation character varying(10)
);


ALTER TABLE public.measurement OWNER TO postgres;

--
-- TOC entry 3394 (class 0 OID 0)
-- Dependencies: 212
-- Name: TABLE measurement; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.measurement IS 'Единицы измерений';


--
-- TOC entry 224 (class 1259 OID 102998)
-- Name: okopf; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.okopf (
    id uuid NOT NULL
);


ALTER TABLE public.okopf OWNER TO postgres;

--
-- TOC entry 3396 (class 0 OID 0)
-- Dependencies: 224
-- Name: TABLE okopf; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.okopf IS 'ОКОПФ';


--
-- TOC entry 236 (class 1259 OID 103351)
-- Name: okpdtr; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.okpdtr (
    id uuid NOT NULL
);


ALTER TABLE public.okpdtr OWNER TO postgres;

--
-- TOC entry 219 (class 1259 OID 86527)
-- Name: operation; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.operation (
    id uuid NOT NULL,
    produced integer,
    prod_time integer,
    production_rate integer,
    type_id uuid,
    salary money
);


ALTER TABLE public.operation OWNER TO postgres;

--
-- TOC entry 3399 (class 0 OID 0)
-- Dependencies: 219
-- Name: TABLE operation; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.operation IS 'Производственные операции';


--
-- TOC entry 3400 (class 0 OID 0)
-- Dependencies: 219
-- Name: COLUMN operation.produced; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.operation.produced IS 'Выработка за время [prod_time], шт.';


--
-- TOC entry 3401 (class 0 OID 0)
-- Dependencies: 219
-- Name: COLUMN operation.prod_time; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.operation.prod_time IS 'Время за которое было произведено [produced] операций, мин';


--
-- TOC entry 3402 (class 0 OID 0)
-- Dependencies: 219
-- Name: COLUMN operation.production_rate; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.operation.production_rate IS 'Норма выработки, шт./час';


--
-- TOC entry 3403 (class 0 OID 0)
-- Dependencies: 219
-- Name: COLUMN operation.type_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.operation.type_id IS 'Тип операции';


--
-- TOC entry 243 (class 1259 OID 119728)
-- Name: operation_execute; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.operation_execute (
    id uuid NOT NULL,
    operation_id uuid,
    operation_count integer,
    completed integer DEFAULT 0,
    complete_status integer DEFAULT 0,
    CONSTRAINT chk_operation_execute_completed CHECK ((completed <= operation_count)),
    CONSTRAINT chk_operation_execute_status CHECK (((complete_status >= 0) AND (complete_status <= 100)))
);


ALTER TABLE public.operation_execute OWNER TO postgres;

--
-- TOC entry 245 (class 1259 OID 127880)
-- Name: operation_executor; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.operation_executor (
    id uuid NOT NULL,
    order_id uuid,
    goods_id uuid,
    operation_id uuid,
    employee_id uuid,
    operation_count integer DEFAULT 0,
    CONSTRAINT chk_operation_executor_count CHECK ((operation_count >= 0))
);


ALTER TABLE public.operation_executor OWNER TO postgres;

--
-- TOC entry 3406 (class 0 OID 0)
-- Dependencies: 245
-- Name: COLUMN operation_executor.order_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.operation_executor.order_id IS 'Заказ';


--
-- TOC entry 3407 (class 0 OID 0)
-- Dependencies: 245
-- Name: COLUMN operation_executor.goods_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.operation_executor.goods_id IS 'Изделие';


--
-- TOC entry 3408 (class 0 OID 0)
-- Dependencies: 245
-- Name: COLUMN operation_executor.operation_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.operation_executor.operation_id IS 'Операция';


--
-- TOC entry 3409 (class 0 OID 0)
-- Dependencies: 245
-- Name: COLUMN operation_executor.employee_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.operation_executor.employee_id IS 'Исполнитель';


--
-- TOC entry 3410 (class 0 OID 0)
-- Dependencies: 245
-- Name: COLUMN operation_executor.operation_count; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.operation_executor.operation_count IS 'Количество выполненных операций';


--
-- TOC entry 218 (class 1259 OID 86516)
-- Name: operation_type; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.operation_type (
    id uuid NOT NULL,
    salary money DEFAULT 0
);


ALTER TABLE public.operation_type OWNER TO postgres;

--
-- TOC entry 3412 (class 0 OID 0)
-- Dependencies: 218
-- Name: TABLE operation_type; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.operation_type IS 'Типы производственных операций';


--
-- TOC entry 241 (class 1259 OID 103491)
-- Name: order_complete; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.order_complete (
    id uuid NOT NULL,
    goods_id uuid,
    goods_count numeric(12,3),
    calculation_id uuid
);


ALTER TABLE public.order_complete OWNER TO postgres;

--
-- TOC entry 240 (class 1259 OID 103464)
-- Name: order_detail; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.order_detail (
    id bigint NOT NULL,
    owner_id uuid NOT NULL,
    goods_id uuid NOT NULL,
    goods_count numeric(12,3),
    price money,
    cost money,
    tax integer,
    tax_value money,
    cost_with_tax money,
    complete_status integer DEFAULT 0,
    remaind_count numeric(12,3) DEFAULT 0
);


ALTER TABLE public.order_detail OWNER TO postgres;

--
-- TOC entry 3415 (class 0 OID 0)
-- Dependencies: 240
-- Name: COLUMN order_detail.price; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.order_detail.price IS 'Цена';


--
-- TOC entry 3416 (class 0 OID 0)
-- Dependencies: 240
-- Name: COLUMN order_detail.cost; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.order_detail.cost IS 'Сумма';


--
-- TOC entry 3417 (class 0 OID 0)
-- Dependencies: 240
-- Name: COLUMN order_detail.tax; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.order_detail.tax IS 'Значение НДС';


--
-- TOC entry 3418 (class 0 OID 0)
-- Dependencies: 240
-- Name: COLUMN order_detail.tax_value; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.order_detail.tax_value IS 'Сумма НДС';


--
-- TOC entry 3419 (class 0 OID 0)
-- Dependencies: 240
-- Name: COLUMN order_detail.cost_with_tax; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.order_detail.cost_with_tax IS 'Всего с НДС';


--
-- TOC entry 3420 (class 0 OID 0)
-- Dependencies: 240
-- Name: COLUMN order_detail.complete_status; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.order_detail.complete_status IS 'Процент изготовления';


--
-- TOC entry 3421 (class 0 OID 0)
-- Dependencies: 240
-- Name: COLUMN order_detail.remaind_count; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.order_detail.remaind_count IS 'Остаток изделий находящихся в производстве';


--
-- TOC entry 239 (class 1259 OID 103462)
-- Name: order_detail_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.order_detail_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.order_detail_id_seq OWNER TO postgres;

--
-- TOC entry 3423 (class 0 OID 0)
-- Dependencies: 239
-- Name: order_detail_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.order_detail_id_seq OWNED BY public.order_detail.id;


--
-- TOC entry 238 (class 1259 OID 103447)
-- Name: order_production; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.order_production (
    id uuid NOT NULL,
    contractor_id uuid,
    data_complete date,
    order_price money DEFAULT 0,
    order_tax integer DEFAULT 20,
    order_tax_value money DEFAULT 0,
    order_price_with_tax money DEFAULT 0
);


ALTER TABLE public.order_production OWNER TO postgres;

--
-- TOC entry 242 (class 1259 OID 119690)
-- Name: order_shipped; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.order_shipped (
    id uuid NOT NULL,
    goods_id uuid,
    goods_count numeric(12,3),
    price money,
    tax public.tax_nds,
    tax_value money,
    cost money,
    cost_with_tax money,
    number1c character varying(25),
    date1c timestamp with time zone
);


ALTER TABLE public.order_shipped OWNER TO postgres;

--
-- TOC entry 3426 (class 0 OID 0)
-- Dependencies: 242
-- Name: COLUMN order_shipped.price; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.order_shipped.price IS 'Цена';


--
-- TOC entry 3427 (class 0 OID 0)
-- Dependencies: 242
-- Name: COLUMN order_shipped.tax; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.order_shipped.tax IS 'Значение НДС';


--
-- TOC entry 3428 (class 0 OID 0)
-- Dependencies: 242
-- Name: COLUMN order_shipped.tax_value; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.order_shipped.tax_value IS 'Сумма НДС';


--
-- TOC entry 3429 (class 0 OID 0)
-- Dependencies: 242
-- Name: COLUMN order_shipped.cost; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.order_shipped.cost IS 'Стоимость';


--
-- TOC entry 3430 (class 0 OID 0)
-- Dependencies: 242
-- Name: COLUMN order_shipped.cost_with_tax; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.order_shipped.cost_with_tax IS 'Стоимость с НДС';


--
-- TOC entry 231 (class 1259 OID 103239)
-- Name: organization; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.organization (
    id uuid NOT NULL,
    short_name character varying(50),
    full_name character varying(150),
    inn numeric(12,0),
    kpp numeric(9,0),
    ogrn numeric(13,0),
    okpo numeric(8,0),
    okopf_id uuid,
    account_id uuid,
    default_org boolean,
    address character varying(250),
    phone character varying(100),
    email character varying(100)
);


ALTER TABLE public.organization OWNER TO postgres;

--
-- TOC entry 3432 (class 0 OID 0)
-- Dependencies: 231
-- Name: COLUMN organization.default_org; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.organization.default_org IS 'Основная организация';


--
-- TOC entry 229 (class 1259 OID 103142)
-- Name: percentage; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.percentage (
    id uuid NOT NULL,
    percent_value numeric(5,2)
);


ALTER TABLE public.percentage OWNER TO postgres;

--
-- TOC entry 3434 (class 0 OID 0)
-- Dependencies: 229
-- Name: TABLE percentage; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.percentage IS 'История изменения процентных значений';


--
-- TOC entry 234 (class 1259 OID 103326)
-- Name: person; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.person (
    id uuid NOT NULL,
    surname character varying(40),
    first_name character varying(20),
    middle_name character varying(40),
    phone character varying(30),
    email character varying(100)
);


ALTER TABLE public.person OWNER TO postgres;

--
-- TOC entry 3436 (class 0 OID 0)
-- Dependencies: 234
-- Name: COLUMN person.surname; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.person.surname IS 'Фамилия';


--
-- TOC entry 3437 (class 0 OID 0)
-- Dependencies: 234
-- Name: COLUMN person.first_name; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.person.first_name IS 'Имя';


--
-- TOC entry 3438 (class 0 OID 0)
-- Dependencies: 234
-- Name: COLUMN person.middle_name; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.person.middle_name IS 'Отчество';


--
-- TOC entry 3439 (class 0 OID 0)
-- Dependencies: 234
-- Name: COLUMN person.phone; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.person.phone IS 'Телефон';


--
-- TOC entry 3440 (class 0 OID 0)
-- Dependencies: 234
-- Name: COLUMN person.email; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.person.email IS 'Адрес эл. почты';


--
-- TOC entry 204 (class 1259 OID 77973)
-- Name: picture; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.picture (
    id uuid NOT NULL,
    size_small text,
    size_large text,
    font_name character varying(40),
    img_name character varying(255),
    note text
);


ALTER TABLE public.picture OWNER TO postgres;

--
-- TOC entry 3442 (class 0 OID 0)
-- Dependencies: 204
-- Name: TABLE picture; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.picture IS 'Изображения/иконки';


--
-- TOC entry 3443 (class 0 OID 0)
-- Dependencies: 204
-- Name: COLUMN picture.font_name; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.picture.font_name IS 'Наименование иконки из Font Awesome 5';


--
-- TOC entry 227 (class 1259 OID 103099)
-- Name: price; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.price (
    id uuid NOT NULL,
    price_value money
);


ALTER TABLE public.price OWNER TO postgres;

--
-- TOC entry 3445 (class 0 OID 0)
-- Dependencies: 227
-- Name: TABLE price; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.price IS 'История изменения цен';


--
-- TOC entry 226 (class 1259 OID 103089)
-- Name: request; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.request (
    id uuid NOT NULL,
    contractor_id uuid,
    request_price money,
    sending_date timestamp with time zone,
    invoice_number character varying(20),
    invoice_date timestamp with time zone,
    waybill_number character varying(20),
    waybill_date timestamp with time zone,
    request_tax integer,
    request_tax_value money,
    request_price_with_tax money
);


ALTER TABLE public.request OWNER TO postgres;

--
-- TOC entry 3447 (class 0 OID 0)
-- Dependencies: 226
-- Name: TABLE request; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.request IS 'Заявка за закупку комплектующих/материалов';


--
-- TOC entry 3448 (class 0 OID 0)
-- Dependencies: 226
-- Name: COLUMN request.contractor_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.request.contractor_id IS 'Контрагент (получатель заявки)';


--
-- TOC entry 3449 (class 0 OID 0)
-- Dependencies: 226
-- Name: COLUMN request.request_price; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.request.request_price IS 'Приблизительная сумма заявки';


--
-- TOC entry 3450 (class 0 OID 0)
-- Dependencies: 226
-- Name: COLUMN request.sending_date; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.request.sending_date IS 'Дата отправки';


--
-- TOC entry 3451 (class 0 OID 0)
-- Dependencies: 226
-- Name: COLUMN request.invoice_number; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.request.invoice_number IS 'Номер счет-фактуры';


--
-- TOC entry 3452 (class 0 OID 0)
-- Dependencies: 226
-- Name: COLUMN request.invoice_date; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.request.invoice_date IS 'Дата счет-фактуры';


--
-- TOC entry 3453 (class 0 OID 0)
-- Dependencies: 226
-- Name: COLUMN request.waybill_number; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.request.waybill_number IS 'Номер накладной';


--
-- TOC entry 3454 (class 0 OID 0)
-- Dependencies: 226
-- Name: COLUMN request.waybill_date; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.request.waybill_date IS 'Дата накладной';


--
-- TOC entry 233 (class 1259 OID 103272)
-- Name: request_detail; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.request_detail (
    id bigint NOT NULL,
    owner_id uuid NOT NULL,
    goods_id uuid,
    goods_count numeric(12,3),
    price money,
    cost money,
    tax integer,
    tax_value money,
    cost_with_tax money,
    fact_goods_count numeric(12,3)
);


ALTER TABLE public.request_detail OWNER TO postgres;

--
-- TOC entry 3456 (class 0 OID 0)
-- Dependencies: 233
-- Name: COLUMN request_detail.tax; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.request_detail.tax IS 'Значение НДС';


--
-- TOC entry 3457 (class 0 OID 0)
-- Dependencies: 233
-- Name: COLUMN request_detail.tax_value; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.request_detail.tax_value IS 'Сумма НДС';


--
-- TOC entry 3458 (class 0 OID 0)
-- Dependencies: 233
-- Name: COLUMN request_detail.cost_with_tax; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.request_detail.cost_with_tax IS 'Всего с НДС';


--
-- TOC entry 3459 (class 0 OID 0)
-- Dependencies: 233
-- Name: COLUMN request_detail.fact_goods_count; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.request_detail.fact_goods_count IS 'Фактическая отгрузка';


--
-- TOC entry 232 (class 1259 OID 103270)
-- Name: request_detail_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.request_detail_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.request_detail_id_seq OWNER TO postgres;

--
-- TOC entry 3461 (class 0 OID 0)
-- Dependencies: 232
-- Name: request_detail_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.request_detail_id_seq OWNED BY public.request_detail.id;


--
-- TOC entry 208 (class 1259 OID 78079)
-- Name: sidebar; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.sidebar (
    id uuid NOT NULL,
    order_index integer DEFAULT 0,
    command_id uuid,
    kind_id uuid
);


ALTER TABLE public.sidebar OWNER TO postgres;

--
-- TOC entry 3463 (class 0 OID 0)
-- Dependencies: 208
-- Name: TABLE sidebar; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.sidebar IS 'Основное меню';


--
-- TOC entry 198 (class 1259 OID 77847)
-- Name: status; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.status (
    id bigint NOT NULL,
    code character varying(80) NOT NULL,
    note character varying(255),
    picture_id uuid
);


ALTER TABLE public.status OWNER TO postgres;

--
-- TOC entry 3465 (class 0 OID 0)
-- Dependencies: 198
-- Name: TABLE status; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.status IS 'Состояния документов/справочников';


--
-- TOC entry 3466 (class 0 OID 0)
-- Dependencies: 198
-- Name: COLUMN status.code; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.status.code IS 'Наименование состояния';


--
-- TOC entry 3467 (class 0 OID 0)
-- Dependencies: 198
-- Name: COLUMN status.note; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.status.note IS 'Полное описание состояния документа/справочника';


--
-- TOC entry 199 (class 1259 OID 77852)
-- Name: transition; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.transition (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name character varying(100) NOT NULL,
    starting_status_id bigint DEFAULT 0 NOT NULL,
    finishing_status_id bigint,
    canceled_status_id bigint
);


ALTER TABLE public.transition OWNER TO postgres;

--
-- TOC entry 3469 (class 0 OID 0)
-- Dependencies: 199
-- Name: COLUMN transition.starting_status_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.transition.starting_status_id IS 'Начальное состояние документа';


--
-- TOC entry 3470 (class 0 OID 0)
-- Dependencies: 199
-- Name: COLUMN transition.finishing_status_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.transition.finishing_status_id IS 'Конечное состояние документа';


--
-- TOC entry 3471 (class 0 OID 0)
-- Dependencies: 199
-- Name: COLUMN transition.canceled_status_id; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.transition.canceled_status_id IS 'Состояние отмененного документа (возможно удаление)';


--
-- TOC entry 197 (class 1259 OID 77835)
-- Name: user_alias; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.user_alias (
    id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
    name character varying(20) NOT NULL,
    pg_name character varying(80) NOT NULL,
    surname character varying(40),
    first_name character varying(20),
    middle_name character varying(40),
    administrator boolean DEFAULT false NOT NULL,
    parent_id uuid,
    is_group boolean DEFAULT false NOT NULL
);


ALTER TABLE public.user_alias OWNER TO postgres;

--
-- TOC entry 3473 (class 0 OID 0)
-- Dependencies: 197
-- Name: TABLE user_alias; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.user_alias IS 'Пользователи';


--
-- TOC entry 3474 (class 0 OID 0)
-- Dependencies: 197
-- Name: COLUMN user_alias.name; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.user_alias.name IS 'Пользователь';


--
-- TOC entry 3475 (class 0 OID 0)
-- Dependencies: 197
-- Name: COLUMN user_alias.pg_name; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.user_alias.pg_name IS 'Имя пользователя в Postgres';


--
-- TOC entry 3476 (class 0 OID 0)
-- Dependencies: 197
-- Name: COLUMN user_alias.surname; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.user_alias.surname IS 'Фамилия';


--
-- TOC entry 3477 (class 0 OID 0)
-- Dependencies: 197
-- Name: COLUMN user_alias.first_name; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.user_alias.first_name IS 'Имя';


--
-- TOC entry 3478 (class 0 OID 0)
-- Dependencies: 197
-- Name: COLUMN user_alias.middle_name; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.user_alias.middle_name IS 'Отчество';


--
-- TOC entry 2936 (class 2604 OID 77913)
-- Name: directory id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.directory ALTER COLUMN id SET DEFAULT public.uuid_generate_v4();


--
-- TOC entry 2953 (class 2604 OID 103024)
-- Name: document id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document ALTER COLUMN id SET DEFAULT public.uuid_generate_v4();


--
-- TOC entry 2937 (class 2604 OID 78022)
-- Name: history id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.history ALTER COLUMN id SET DEFAULT nextval('public.history_id_seq'::regclass);


--
-- TOC entry 2946 (class 2604 OID 78246)
-- Name: kind_child id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.kind_child ALTER COLUMN id SET DEFAULT nextval('public.kind_child_id_seq'::regclass);


--
-- TOC entry 2964 (class 2604 OID 103467)
-- Name: order_detail id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_detail ALTER COLUMN id SET DEFAULT nextval('public.order_detail_id_seq'::regclass);


--
-- TOC entry 2957 (class 2604 OID 103275)
-- Name: request_detail id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.request_detail ALTER COLUMN id SET DEFAULT nextval('public.request_detail_id_seq'::regclass);


--
-- TOC entry 3020 (class 2606 OID 78303)
-- Name: account pk_account_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.account
    ADD CONSTRAINT pk_account_id PRIMARY KEY (id);


--
-- TOC entry 3013 (class 2606 OID 78210)
-- Name: bank pk_bank; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bank
    ADD CONSTRAINT pk_bank PRIMARY KEY (id);


--
-- TOC entry 3026 (class 2606 OID 102929)
-- Name: calculation pk_calculation_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.calculation
    ADD CONSTRAINT pk_calculation_id PRIMARY KEY (id);


--
-- TOC entry 3000 (class 2606 OID 78058)
-- Name: changing_status pk_changing_status; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.changing_status
    ADD CONSTRAINT pk_changing_status PRIMARY KEY (id);


--
-- TOC entry 3006 (class 2606 OID 78121)
-- Name: command pk_command; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.command
    ADD CONSTRAINT pk_command PRIMARY KEY (id);


--
-- TOC entry 3032 (class 2606 OID 102977)
-- Name: condition pk_condition; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.condition
    ADD CONSTRAINT pk_condition PRIMARY KEY (id);


--
-- TOC entry 3008 (class 2606 OID 78145)
-- Name: contractor pk_contractor; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contractor
    ADD CONSTRAINT pk_contractor PRIMARY KEY (id);


--
-- TOC entry 3046 (class 2606 OID 103134)
-- Name: deduction pk_deduction_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deduction
    ADD CONSTRAINT pk_deduction_id PRIMARY KEY (id);


--
-- TOC entry 2992 (class 2606 OID 77915)
-- Name: directory pk_directory_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.directory
    ADD CONSTRAINT pk_directory_id PRIMARY KEY (id);


--
-- TOC entry 3038 (class 2606 OID 103048)
-- Name: document pk_document_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document
    ADD CONSTRAINT pk_document_id PRIMARY KEY (id);


--
-- TOC entry 2990 (class 2606 OID 77902)
-- Name: document_info pk_document_info; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document_info
    ADD CONSTRAINT pk_document_info PRIMARY KEY (id);


--
-- TOC entry 3058 (class 2606 OID 103340)
-- Name: employee pk_employee_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employee
    ADD CONSTRAINT pk_employee_id PRIMARY KEY (id);


--
-- TOC entry 3062 (class 2606 OID 103392)
-- Name: form_preview pk_form_preview_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.form_preview
    ADD CONSTRAINT pk_form_preview_id PRIMARY KEY (id);


--
-- TOC entry 3016 (class 2606 OID 78226)
-- Name: goods pk_goods; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.goods
    ADD CONSTRAINT pk_goods PRIMARY KEY (id);


--
-- TOC entry 2998 (class 2606 OID 78024)
-- Name: history pk_history; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.history
    ADD CONSTRAINT pk_history PRIMARY KEY (id);


--
-- TOC entry 3050 (class 2606 OID 103158)
-- Name: item_deduction pk_item_deduction_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_deduction
    ADD CONSTRAINT pk_item_deduction_id PRIMARY KEY (id);


--
-- TOC entry 3028 (class 2606 OID 102944)
-- Name: item_goods pk_item_goods_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_goods
    ADD CONSTRAINT pk_item_goods_id PRIMARY KEY (id);


--
-- TOC entry 3030 (class 2606 OID 102959)
-- Name: item_operation pk_item_operation_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_operation
    ADD CONSTRAINT pk_item_operation_id PRIMARY KEY (id);


--
-- TOC entry 2986 (class 2606 OID 77879)
-- Name: kind pk_kind; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.kind
    ADD CONSTRAINT pk_kind PRIMARY KEY (id);


--
-- TOC entry 3018 (class 2606 OID 78248)
-- Name: kind_child pk_kind_child; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.kind_child
    ADD CONSTRAINT pk_kind_child PRIMARY KEY (id);


--
-- TOC entry 2982 (class 2606 OID 77865)
-- Name: kind_enum pk_kind_enum; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.kind_enum
    ADD CONSTRAINT pk_kind_enum PRIMARY KEY (id);


--
-- TOC entry 3011 (class 2606 OID 78199)
-- Name: measurement pk_measurement; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.measurement
    ADD CONSTRAINT pk_measurement PRIMARY KEY (id);


--
-- TOC entry 3036 (class 2606 OID 103002)
-- Name: okopf pk_okopf_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.okopf
    ADD CONSTRAINT pk_okopf_id PRIMARY KEY (id);


--
-- TOC entry 3060 (class 2606 OID 103355)
-- Name: okpdtr pk_okpdtr_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.okpdtr
    ADD CONSTRAINT pk_okpdtr_id PRIMARY KEY (id);


--
-- TOC entry 3072 (class 2606 OID 119732)
-- Name: operation_execute pk_operation_execute_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operation_execute
    ADD CONSTRAINT pk_operation_execute_id PRIMARY KEY (id);


--
-- TOC entry 3074 (class 2606 OID 127884)
-- Name: operation_executor pk_operation_executor_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operation_executor
    ADD CONSTRAINT pk_operation_executor_id PRIMARY KEY (id);


--
-- TOC entry 3024 (class 2606 OID 86531)
-- Name: operation pk_operation_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operation
    ADD CONSTRAINT pk_operation_id PRIMARY KEY (id);


--
-- TOC entry 3022 (class 2606 OID 86521)
-- Name: operation_type pk_operation_type; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operation_type
    ADD CONSTRAINT pk_operation_type PRIMARY KEY (id);


--
-- TOC entry 3068 (class 2606 OID 103495)
-- Name: order_complete pk_order_complete_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_complete
    ADD CONSTRAINT pk_order_complete_id PRIMARY KEY (id);


--
-- TOC entry 3066 (class 2606 OID 103469)
-- Name: order_detail pk_order_detail_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_detail
    ADD CONSTRAINT pk_order_detail_id PRIMARY KEY (id);


--
-- TOC entry 3064 (class 2606 OID 103451)
-- Name: order_production pk_order_production_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_production
    ADD CONSTRAINT pk_order_production_id PRIMARY KEY (id);


--
-- TOC entry 3070 (class 2606 OID 119694)
-- Name: order_shipped pk_order_shipped_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_shipped
    ADD CONSTRAINT pk_order_shipped_id PRIMARY KEY (id);


--
-- TOC entry 3052 (class 2606 OID 103243)
-- Name: organization pk_organization_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organization
    ADD CONSTRAINT pk_organization_id PRIMARY KEY (id);


--
-- TOC entry 3048 (class 2606 OID 103146)
-- Name: percentage pk_percentage_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.percentage
    ADD CONSTRAINT pk_percentage_id PRIMARY KEY (id);


--
-- TOC entry 3056 (class 2606 OID 103330)
-- Name: person pk_person_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.person
    ADD CONSTRAINT pk_person_id PRIMARY KEY (id);


--
-- TOC entry 2996 (class 2606 OID 77980)
-- Name: picture pk_picture; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.picture
    ADD CONSTRAINT pk_picture PRIMARY KEY (id);


--
-- TOC entry 3044 (class 2606 OID 103103)
-- Name: price pk_price_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.price
    ADD CONSTRAINT pk_price_id PRIMARY KEY (id);


--
-- TOC entry 3054 (class 2606 OID 103277)
-- Name: request_detail pk_request_detail_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.request_detail
    ADD CONSTRAINT pk_request_detail_id PRIMARY KEY (id);


--
-- TOC entry 3042 (class 2606 OID 103093)
-- Name: request pk_request_id; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.request
    ADD CONSTRAINT pk_request_id PRIMARY KEY (id);


--
-- TOC entry 3004 (class 2606 OID 78084)
-- Name: sidebar pk_sidebar; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sidebar
    ADD CONSTRAINT pk_sidebar PRIMARY KEY (id);


--
-- TOC entry 2976 (class 2606 OID 77851)
-- Name: status pk_status; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.status
    ADD CONSTRAINT pk_status PRIMARY KEY (id);


--
-- TOC entry 2978 (class 2606 OID 77857)
-- Name: transition pk_transition; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transition
    ADD CONSTRAINT pk_transition PRIMARY KEY (id);


--
-- TOC entry 2974 (class 2606 OID 77841)
-- Name: user_alias pk_user_alias; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_alias
    ADD CONSTRAINT pk_user_alias PRIMARY KEY (id);


--
-- TOC entry 3002 (class 2606 OID 78060)
-- Name: changing_status unq_changing_status; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.changing_status
    ADD CONSTRAINT unq_changing_status UNIQUE (transition_id, status_from_id, status_to_id);


--
-- TOC entry 3034 (class 2606 OID 102996)
-- Name: condition unq_condition_kind_status; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.condition
    ADD CONSTRAINT unq_condition_kind_status UNIQUE (kind_id, changing_status_id);


--
-- TOC entry 2994 (class 2606 OID 78175)
-- Name: directory unq_directory_code; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.directory
    ADD CONSTRAINT unq_directory_code UNIQUE (kind_id, code);


--
-- TOC entry 3040 (class 2606 OID 103481)
-- Name: document unq_document_number; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document
    ADD CONSTRAINT unq_document_number UNIQUE (kind_id, doc_number, doc_year, organization_id);


--
-- TOC entry 2988 (class 2606 OID 77881)
-- Name: kind unq_kind_code; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.kind
    ADD CONSTRAINT unq_kind_code UNIQUE (code);


--
-- TOC entry 2984 (class 2606 OID 77867)
-- Name: kind_enum unq_kind_enum_code; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.kind_enum
    ADD CONSTRAINT unq_kind_enum_code UNIQUE (code);


--
-- TOC entry 2980 (class 2606 OID 77859)
-- Name: transition unq_transition_name; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transition
    ADD CONSTRAINT unq_transition_name UNIQUE (name);


--
-- TOC entry 3014 (class 1259 OID 78216)
-- Name: unq_bank_bik; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX unq_bank_bik ON public.bank USING btree (bik) WHERE (bik > (0)::numeric);


--
-- TOC entry 3009 (class 1259 OID 78168)
-- Name: unq_contractor_inn; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX unq_contractor_inn ON public.contractor USING btree (inn) WHERE (inn > (0)::numeric);


--
-- TOC entry 3178 (class 2620 OID 78311)
-- Name: account account_aiu; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE CONSTRAINT TRIGGER account_aiu AFTER INSERT OR UPDATE ON public.account NOT DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE PROCEDURE public.check_contractor_account();


--
-- TOC entry 3176 (class 2620 OID 78219)
-- Name: bank bank_biu; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE CONSTRAINT TRIGGER bank_biu AFTER INSERT OR UPDATE ON public.bank NOT DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE PROCEDURE public.check_bank_codes();


--
-- TOC entry 3175 (class 2620 OID 78167)
-- Name: contractor contractor_aiu; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE CONSTRAINT TRIGGER contractor_aiu AFTER INSERT OR UPDATE ON public.contractor NOT DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE PROCEDURE public.check_contractor_codes();


--
-- TOC entry 3174 (class 2620 OID 78159)
-- Name: contractor contractor_bi; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER contractor_bi BEFORE INSERT ON public.contractor FOR EACH ROW EXECUTE PROCEDURE public.contractor_initialize();

ALTER TABLE public.contractor DISABLE TRIGGER contractor_bi;


--
-- TOC entry 3184 (class 2620 OID 103153)
-- Name: deduction deduction_au; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER deduction_au AFTER UPDATE ON public.deduction FOR EACH ROW EXECUTE PROCEDURE public.add_percent_archive();


--
-- TOC entry 3170 (class 2620 OID 78051)
-- Name: directory directory_ad; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE CONSTRAINT TRIGGER directory_ad AFTER DELETE ON public.directory NOT DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE PROCEDURE public.check_document_deleting();


--
-- TOC entry 3172 (class 2620 OID 78078)
-- Name: directory directory_aiu; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE CONSTRAINT TRIGGER directory_aiu AFTER INSERT OR UPDATE ON public.directory NOT DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE PROCEDURE public.document_checking();


--
-- TOC entry 3169 (class 2620 OID 77988)
-- Name: directory directory_bi; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER directory_bi BEFORE INSERT ON public.directory FOR EACH ROW EXECUTE PROCEDURE public.document_initialize();


--
-- TOC entry 3171 (class 2620 OID 78096)
-- Name: directory directory_bu; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER directory_bu BEFORE UPDATE ON public.directory FOR EACH ROW EXECUTE PROCEDURE public.document_updating();


--
-- TOC entry 3183 (class 2620 OID 103083)
-- Name: document document_ad; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE CONSTRAINT TRIGGER document_ad AFTER DELETE ON public.document NOT DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE PROCEDURE public.check_document_deleting();


--
-- TOC entry 3182 (class 2620 OID 103081)
-- Name: document document_aiu; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE CONSTRAINT TRIGGER document_aiu AFTER INSERT OR UPDATE ON public.document NOT DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE PROCEDURE public.document_checking();


--
-- TOC entry 3180 (class 2620 OID 103076)
-- Name: document document_bi; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER document_bi BEFORE INSERT ON public.document FOR EACH ROW EXECUTE PROCEDURE public.document_initialize();


--
-- TOC entry 3181 (class 2620 OID 103079)
-- Name: document document_bu; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER document_bu BEFORE UPDATE ON public.document FOR EACH ROW EXECUTE PROCEDURE public.document_updating();


--
-- TOC entry 3177 (class 2620 OID 78271)
-- Name: goods goods_au; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER goods_au AFTER UPDATE ON public.goods FOR EACH ROW EXECUTE PROCEDURE public.add_price_archive();


--
-- TOC entry 3173 (class 2620 OID 78046)
-- Name: history history_bi; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER history_bi BEFORE INSERT ON public.history FOR EACH ROW EXECUTE PROCEDURE public.history_initialize();


--
-- TOC entry 3179 (class 2620 OID 102899)
-- Name: operation operation_au; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER operation_au AFTER UPDATE ON public.operation FOR EACH ROW EXECUTE PROCEDURE public.add_salary_archive();


--
-- TOC entry 3186 (class 2620 OID 127943)
-- Name: operation_execute operation_execute_biu; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER operation_execute_biu BEFORE INSERT OR UPDATE ON public.operation_execute FOR EACH ROW EXECUTE PROCEDURE public.calculate_complete_status();


--
-- TOC entry 3185 (class 2620 OID 103264)
-- Name: organization organization_aiu; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER organization_aiu AFTER INSERT OR UPDATE ON public.organization FOR EACH ROW EXECUTE PROCEDURE public.check_contractor_codes();


--
-- TOC entry 3168 (class 2620 OID 78296)
-- Name: transition transition_aiu; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE CONSTRAINT TRIGGER transition_aiu AFTER INSERT OR UPDATE ON public.transition NOT DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE PROCEDURE public.check_kind();


--
-- TOC entry 3113 (class 2606 OID 78304)
-- Name: account fk_account_bank; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.account
    ADD CONSTRAINT fk_account_bank FOREIGN KEY (bank_id) REFERENCES public.bank(id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 3114 (class 2606 OID 78317)
-- Name: account fk_account_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.account
    ADD CONSTRAINT fk_account_id FOREIGN KEY (id) REFERENCES public.directory(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3108 (class 2606 OID 78211)
-- Name: bank fk_bank_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.bank
    ADD CONSTRAINT fk_bank_id FOREIGN KEY (id) REFERENCES public.directory(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3118 (class 2606 OID 102935)
-- Name: calculation fk_calculation_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.calculation
    ADD CONSTRAINT fk_calculation_id FOREIGN KEY (id) REFERENCES public.directory(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3096 (class 2606 OID 78061)
-- Name: changing_status fk_changing_status_from; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.changing_status
    ADD CONSTRAINT fk_changing_status_from FOREIGN KEY (status_from_id) REFERENCES public.status(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3099 (class 2606 OID 78169)
-- Name: changing_status fk_changing_status_picture; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.changing_status
    ADD CONSTRAINT fk_changing_status_picture FOREIGN KEY (picture_id) REFERENCES public.picture(id) ON DELETE SET NULL;


--
-- TOC entry 3097 (class 2606 OID 78066)
-- Name: changing_status fk_changing_status_to; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.changing_status
    ADD CONSTRAINT fk_changing_status_to FOREIGN KEY (status_to_id) REFERENCES public.status(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3098 (class 2606 OID 78071)
-- Name: changing_status fk_changing_status_transition; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.changing_status
    ADD CONSTRAINT fk_changing_status_transition FOREIGN KEY (transition_id) REFERENCES public.transition(id) ON DELETE CASCADE;


--
-- TOC entry 3103 (class 2606 OID 78132)
-- Name: command fk_command_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.command
    ADD CONSTRAINT fk_command_id FOREIGN KEY (id) REFERENCES public.directory(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3124 (class 2606 OID 102983)
-- Name: condition fk_condition_changing_status; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.condition
    ADD CONSTRAINT fk_condition_changing_status FOREIGN KEY (changing_status_id) REFERENCES public.changing_status(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3123 (class 2606 OID 102978)
-- Name: condition fk_condition_kind; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.condition
    ADD CONSTRAINT fk_condition_kind FOREIGN KEY (kind_id) REFERENCES public.kind(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3105 (class 2606 OID 78312)
-- Name: contractor fk_contractor_account; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contractor
    ADD CONSTRAINT fk_contractor_account FOREIGN KEY (account_id) REFERENCES public.account(id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 3104 (class 2606 OID 78148)
-- Name: contractor fk_contractor_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contractor
    ADD CONSTRAINT fk_contractor_id FOREIGN KEY (id) REFERENCES public.directory(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3106 (class 2606 OID 103254)
-- Name: contractor fk_contractor_okopf; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.contractor
    ADD CONSTRAINT fk_contractor_okopf FOREIGN KEY (okopf_id) REFERENCES public.okopf(id) ON DELETE SET NULL;


--
-- TOC entry 3136 (class 2606 OID 103135)
-- Name: deduction fk_deduction_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.deduction
    ADD CONSTRAINT fk_deduction_id FOREIGN KEY (id) REFERENCES public.directory(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3091 (class 2606 OID 78040)
-- Name: directory fk_directory_history; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.directory
    ADD CONSTRAINT fk_directory_history FOREIGN KEY (history_id) REFERENCES public.history(id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 3086 (class 2606 OID 77953)
-- Name: directory fk_directory_kind; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.directory
    ADD CONSTRAINT fk_directory_kind FOREIGN KEY (kind_id) REFERENCES public.kind(id);


--
-- TOC entry 3087 (class 2606 OID 77958)
-- Name: directory fk_directory_owner; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.directory
    ADD CONSTRAINT fk_directory_owner FOREIGN KEY (owner_id) REFERENCES public.directory(id) ON DELETE CASCADE;


--
-- TOC entry 3088 (class 2606 OID 77963)
-- Name: directory fk_directory_parent; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.directory
    ADD CONSTRAINT fk_directory_parent FOREIGN KEY (parent_id) REFERENCES public.directory(id) ON DELETE CASCADE;


--
-- TOC entry 3090 (class 2606 OID 78007)
-- Name: directory fk_directory_picture; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.directory
    ADD CONSTRAINT fk_directory_picture FOREIGN KEY (picture_id) REFERENCES public.picture(id) ON DELETE SET NULL;


--
-- TOC entry 3089 (class 2606 OID 77968)
-- Name: directory fk_directory_status; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.directory
    ADD CONSTRAINT fk_directory_status FOREIGN KEY (status_id) REFERENCES public.status(id) ON UPDATE CASCADE;


--
-- TOC entry 3083 (class 2606 OID 77938)
-- Name: directory fk_directory_user_created; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.directory
    ADD CONSTRAINT fk_directory_user_created FOREIGN KEY (user_created_id) REFERENCES public.user_alias(id);


--
-- TOC entry 3085 (class 2606 OID 77948)
-- Name: directory fk_directory_user_locked; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.directory
    ADD CONSTRAINT fk_directory_user_locked FOREIGN KEY (user_locked_id) REFERENCES public.user_alias(id);


--
-- TOC entry 3084 (class 2606 OID 77943)
-- Name: directory fk_directory_user_updated; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.directory
    ADD CONSTRAINT fk_directory_user_updated FOREIGN KEY (user_updated_id) REFERENCES public.user_alias(id);


--
-- TOC entry 3126 (class 2606 OID 103025)
-- Name: document fk_document_history; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document
    ADD CONSTRAINT fk_document_history FOREIGN KEY (history_id) REFERENCES public.history(id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- TOC entry 3127 (class 2606 OID 103030)
-- Name: document fk_document_kind; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document
    ADD CONSTRAINT fk_document_kind FOREIGN KEY (kind_id) REFERENCES public.kind(id);


--
-- TOC entry 3133 (class 2606 OID 103265)
-- Name: document fk_document_organization; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document
    ADD CONSTRAINT fk_document_organization FOREIGN KEY (organization_id) REFERENCES public.organization(id);


--
-- TOC entry 3128 (class 2606 OID 103049)
-- Name: document fk_document_owner; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document
    ADD CONSTRAINT fk_document_owner FOREIGN KEY (owner_id) REFERENCES public.document(id) ON DELETE CASCADE;


--
-- TOC entry 3129 (class 2606 OID 103054)
-- Name: document fk_document_status; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document
    ADD CONSTRAINT fk_document_status FOREIGN KEY (status_id) REFERENCES public.status(id) ON UPDATE CASCADE;


--
-- TOC entry 3130 (class 2606 OID 103059)
-- Name: document fk_document_user_created; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document
    ADD CONSTRAINT fk_document_user_created FOREIGN KEY (user_created_id) REFERENCES public.user_alias(id);


--
-- TOC entry 3131 (class 2606 OID 103064)
-- Name: document fk_document_user_locked; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document
    ADD CONSTRAINT fk_document_user_locked FOREIGN KEY (user_locked_id) REFERENCES public.user_alias(id);


--
-- TOC entry 3132 (class 2606 OID 103069)
-- Name: document fk_document_user_updated; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.document
    ADD CONSTRAINT fk_document_user_updated FOREIGN KEY (user_updated_id) REFERENCES public.user_alias(id);


--
-- TOC entry 3146 (class 2606 OID 103341)
-- Name: employee fk_employee_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employee
    ADD CONSTRAINT fk_employee_id FOREIGN KEY (id) REFERENCES public.directory(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3147 (class 2606 OID 103346)
-- Name: employee fk_employee_person; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employee
    ADD CONSTRAINT fk_employee_person FOREIGN KEY (person_id) REFERENCES public.person(id);


--
-- TOC entry 3148 (class 2606 OID 103371)
-- Name: employee fk_employee_post; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employee
    ADD CONSTRAINT fk_employee_post FOREIGN KEY (post_id) REFERENCES public.okpdtr(id) ON DELETE SET NULL;


--
-- TOC entry 3150 (class 2606 OID 103393)
-- Name: form_preview fk_form_preview_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.form_preview
    ADD CONSTRAINT fk_form_preview_id FOREIGN KEY (id) REFERENCES public.directory(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3151 (class 2606 OID 103398)
-- Name: form_preview fk_form_preview_kind; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.form_preview
    ADD CONSTRAINT fk_form_preview_kind FOREIGN KEY (kind_id) REFERENCES public.kind(id) ON DELETE CASCADE;


--
-- TOC entry 3109 (class 2606 OID 78227)
-- Name: goods fk_goods_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.goods
    ADD CONSTRAINT fk_goods_id FOREIGN KEY (id) REFERENCES public.directory(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3110 (class 2606 OID 78232)
-- Name: goods fk_goods_measurement; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.goods
    ADD CONSTRAINT fk_goods_measurement FOREIGN KEY (measurement_id) REFERENCES public.measurement(id);


--
-- TOC entry 3094 (class 2606 OID 78030)
-- Name: history fk_history_status_from; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.history
    ADD CONSTRAINT fk_history_status_from FOREIGN KEY (status_from_id) REFERENCES public.status(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3095 (class 2606 OID 78035)
-- Name: history fk_history_status_to; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.history
    ADD CONSTRAINT fk_history_status_to FOREIGN KEY (status_to_id) REFERENCES public.status(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3093 (class 2606 OID 78025)
-- Name: history fk_history_user; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.history
    ADD CONSTRAINT fk_history_user FOREIGN KEY (user_id) REFERENCES public.user_alias(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3139 (class 2606 OID 103164)
-- Name: item_deduction fk_item_deduction_deduction; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_deduction
    ADD CONSTRAINT fk_item_deduction_deduction FOREIGN KEY (deduction_id) REFERENCES public.deduction(id);


--
-- TOC entry 3138 (class 2606 OID 103159)
-- Name: item_deduction fk_item_deduction_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_deduction
    ADD CONSTRAINT fk_item_deduction_id FOREIGN KEY (id) REFERENCES public.directory(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3120 (class 2606 OID 102950)
-- Name: item_goods fk_item_goods_goods; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_goods
    ADD CONSTRAINT fk_item_goods_goods FOREIGN KEY (goods_id) REFERENCES public.goods(id);


--
-- TOC entry 3119 (class 2606 OID 102945)
-- Name: item_goods fk_item_goods_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_goods
    ADD CONSTRAINT fk_item_goods_id FOREIGN KEY (id) REFERENCES public.directory(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3121 (class 2606 OID 102960)
-- Name: item_operation fk_item_operation_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_operation
    ADD CONSTRAINT fk_item_operation_id FOREIGN KEY (id) REFERENCES public.directory(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3122 (class 2606 OID 102965)
-- Name: item_operation fk_item_operation_operation; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.item_operation
    ADD CONSTRAINT fk_item_operation_operation FOREIGN KEY (operation_id) REFERENCES public.operation(id);


--
-- TOC entry 3112 (class 2606 OID 78254)
-- Name: kind_child fk_kind_child_child; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.kind_child
    ADD CONSTRAINT fk_kind_child_child FOREIGN KEY (child_id) REFERENCES public.kind(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3111 (class 2606 OID 78249)
-- Name: kind_child fk_kind_child_master; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.kind_child
    ADD CONSTRAINT fk_kind_child_master FOREIGN KEY (master_id) REFERENCES public.kind(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3081 (class 2606 OID 77887)
-- Name: kind fk_kind_enum; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.kind
    ADD CONSTRAINT fk_kind_enum FOREIGN KEY (enum_id) REFERENCES public.kind_enum(id);


--
-- TOC entry 3082 (class 2606 OID 78002)
-- Name: kind fk_kind_picture; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.kind
    ADD CONSTRAINT fk_kind_picture FOREIGN KEY (picture_id) REFERENCES public.picture(id) ON DELETE SET NULL;


--
-- TOC entry 3080 (class 2606 OID 77882)
-- Name: kind fk_kind_transition; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.kind
    ADD CONSTRAINT fk_kind_transition FOREIGN KEY (transition_id) REFERENCES public.transition(id) ON DELETE SET NULL;


--
-- TOC entry 3107 (class 2606 OID 78200)
-- Name: measurement fk_measurement_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.measurement
    ADD CONSTRAINT fk_measurement_id FOREIGN KEY (id) REFERENCES public.directory(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3125 (class 2606 OID 103008)
-- Name: okopf fk_okopf_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.okopf
    ADD CONSTRAINT fk_okopf_id FOREIGN KEY (id) REFERENCES public.directory(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3149 (class 2606 OID 103356)
-- Name: okpdtr fk_okpdtr_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.okpdtr
    ADD CONSTRAINT fk_okpdtr_id FOREIGN KEY (id) REFERENCES public.directory(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3161 (class 2606 OID 119733)
-- Name: operation_execute fk_operation_execute_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operation_execute
    ADD CONSTRAINT fk_operation_execute_id FOREIGN KEY (id) REFERENCES public.document(id) ON DELETE CASCADE;


--
-- TOC entry 3162 (class 2606 OID 119738)
-- Name: operation_execute fk_operation_execute_operation; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operation_execute
    ADD CONSTRAINT fk_operation_execute_operation FOREIGN KEY (operation_id) REFERENCES public.operation(id);


--
-- TOC entry 3167 (class 2606 OID 127918)
-- Name: operation_executor fk_operation_executor_employee; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operation_executor
    ADD CONSTRAINT fk_operation_executor_employee FOREIGN KEY (employee_id) REFERENCES public.employee(id);


--
-- TOC entry 3165 (class 2606 OID 127903)
-- Name: operation_executor fk_operation_executor_goods; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operation_executor
    ADD CONSTRAINT fk_operation_executor_goods FOREIGN KEY (goods_id) REFERENCES public.goods(id);


--
-- TOC entry 3163 (class 2606 OID 127885)
-- Name: operation_executor fk_operation_executor_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operation_executor
    ADD CONSTRAINT fk_operation_executor_id FOREIGN KEY (id) REFERENCES public.document(id) ON DELETE CASCADE;


--
-- TOC entry 3166 (class 2606 OID 127908)
-- Name: operation_executor fk_operation_executor_operation; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operation_executor
    ADD CONSTRAINT fk_operation_executor_operation FOREIGN KEY (operation_id) REFERENCES public.operation(id);


--
-- TOC entry 3164 (class 2606 OID 127898)
-- Name: operation_executor fk_operation_executor_order; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operation_executor
    ADD CONSTRAINT fk_operation_executor_order FOREIGN KEY (order_id) REFERENCES public.order_production(id);


--
-- TOC entry 3116 (class 2606 OID 86532)
-- Name: operation fk_operation_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operation
    ADD CONSTRAINT fk_operation_id FOREIGN KEY (id) REFERENCES public.directory(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3117 (class 2606 OID 86537)
-- Name: operation fk_operation_type; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operation
    ADD CONSTRAINT fk_operation_type FOREIGN KEY (type_id) REFERENCES public.operation_type(id) ON DELETE CASCADE;


--
-- TOC entry 3115 (class 2606 OID 86522)
-- Name: operation_type fk_operation_type_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.operation_type
    ADD CONSTRAINT fk_operation_type_id FOREIGN KEY (id) REFERENCES public.directory(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3158 (class 2606 OID 119743)
-- Name: order_complete fk_order_complete_calculation; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_complete
    ADD CONSTRAINT fk_order_complete_calculation FOREIGN KEY (calculation_id) REFERENCES public.calculation(id);


--
-- TOC entry 3157 (class 2606 OID 103512)
-- Name: order_complete fk_order_complete_goods; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_complete
    ADD CONSTRAINT fk_order_complete_goods FOREIGN KEY (goods_id) REFERENCES public.goods(id);


--
-- TOC entry 3156 (class 2606 OID 103507)
-- Name: order_complete fk_order_complete_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_complete
    ADD CONSTRAINT fk_order_complete_id FOREIGN KEY (id) REFERENCES public.document(id) ON DELETE CASCADE;


--
-- TOC entry 3155 (class 2606 OID 103475)
-- Name: order_detail fk_order_detail_goods; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_detail
    ADD CONSTRAINT fk_order_detail_goods FOREIGN KEY (goods_id) REFERENCES public.goods(id);


--
-- TOC entry 3154 (class 2606 OID 103470)
-- Name: order_detail fk_order_detail_owner; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_detail
    ADD CONSTRAINT fk_order_detail_owner FOREIGN KEY (owner_id) REFERENCES public.order_production(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3153 (class 2606 OID 103457)
-- Name: order_production fk_order_production_contractor; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_production
    ADD CONSTRAINT fk_order_production_contractor FOREIGN KEY (contractor_id) REFERENCES public.contractor(id);


--
-- TOC entry 3152 (class 2606 OID 103452)
-- Name: order_production fk_order_production_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_production
    ADD CONSTRAINT fk_order_production_id FOREIGN KEY (id) REFERENCES public.document(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3159 (class 2606 OID 119700)
-- Name: order_shipped fk_order_shipped_goods; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_shipped
    ADD CONSTRAINT fk_order_shipped_goods FOREIGN KEY (goods_id) REFERENCES public.goods(id);


--
-- TOC entry 3160 (class 2606 OID 119707)
-- Name: order_shipped fk_order_shipped_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_shipped
    ADD CONSTRAINT fk_order_shipped_id FOREIGN KEY (id) REFERENCES public.document(id) ON DELETE CASCADE;


--
-- TOC entry 3142 (class 2606 OID 103259)
-- Name: organization fk_organization_account; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organization
    ADD CONSTRAINT fk_organization_account FOREIGN KEY (account_id) REFERENCES public.account(id) ON DELETE SET NULL;


--
-- TOC entry 3140 (class 2606 OID 103244)
-- Name: organization fk_organization_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organization
    ADD CONSTRAINT fk_organization_id FOREIGN KEY (id) REFERENCES public.directory(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3141 (class 2606 OID 103249)
-- Name: organization fk_organization_okopf; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.organization
    ADD CONSTRAINT fk_organization_okopf FOREIGN KEY (okopf_id) REFERENCES public.okopf(id) ON DELETE SET NULL;


--
-- TOC entry 3137 (class 2606 OID 103147)
-- Name: percentage fk_percentage_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.percentage
    ADD CONSTRAINT fk_percentage_id FOREIGN KEY (id) REFERENCES public.directory(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3145 (class 2606 OID 103331)
-- Name: person fk_person_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.person
    ADD CONSTRAINT fk_person_id FOREIGN KEY (id) REFERENCES public.directory(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3092 (class 2606 OID 77981)
-- Name: picture fk_picture_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.picture
    ADD CONSTRAINT fk_picture_id FOREIGN KEY (id) REFERENCES public.directory(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3135 (class 2606 OID 103104)
-- Name: price fk_price_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.price
    ADD CONSTRAINT fk_price_id FOREIGN KEY (id) REFERENCES public.directory(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3144 (class 2606 OID 103283)
-- Name: request_detail fk_request_detail_goods; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.request_detail
    ADD CONSTRAINT fk_request_detail_goods FOREIGN KEY (goods_id) REFERENCES public.goods(id);


--
-- TOC entry 3143 (class 2606 OID 103278)
-- Name: request_detail fk_request_detail_owner; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.request_detail
    ADD CONSTRAINT fk_request_detail_owner FOREIGN KEY (owner_id) REFERENCES public.request(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3134 (class 2606 OID 103094)
-- Name: request fk_request_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.request
    ADD CONSTRAINT fk_request_id FOREIGN KEY (id) REFERENCES public.document(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3101 (class 2606 OID 78122)
-- Name: sidebar fk_sidebar_command; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sidebar
    ADD CONSTRAINT fk_sidebar_command FOREIGN KEY (command_id) REFERENCES public.command(id) ON DELETE SET NULL;


--
-- TOC entry 3100 (class 2606 OID 78090)
-- Name: sidebar fk_sidebar_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sidebar
    ADD CONSTRAINT fk_sidebar_id FOREIGN KEY (id) REFERENCES public.directory(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3102 (class 2606 OID 78127)
-- Name: sidebar fk_sidebar_kind; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.sidebar
    ADD CONSTRAINT fk_sidebar_kind FOREIGN KEY (kind_id) REFERENCES public.kind(id) ON DELETE SET NULL;


--
-- TOC entry 3076 (class 2606 OID 77997)
-- Name: status fk_status_picture; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.status
    ADD CONSTRAINT fk_status_picture FOREIGN KEY (picture_id) REFERENCES public.picture(id) ON DELETE SET NULL;


--
-- TOC entry 3078 (class 2606 OID 103497)
-- Name: transition fk_transition_canceled_status; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transition
    ADD CONSTRAINT fk_transition_canceled_status FOREIGN KEY (canceled_status_id) REFERENCES public.status(id) ON UPDATE SET NULL ON DELETE CASCADE;


--
-- TOC entry 3079 (class 2606 OID 103502)
-- Name: transition fk_transition_finishing_status; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transition
    ADD CONSTRAINT fk_transition_finishing_status FOREIGN KEY (finishing_status_id) REFERENCES public.status(id) ON UPDATE SET NULL ON DELETE CASCADE;


--
-- TOC entry 3077 (class 2606 OID 78284)
-- Name: transition fk_transition_starting_status; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.transition
    ADD CONSTRAINT fk_transition_starting_status FOREIGN KEY (starting_status_id) REFERENCES public.status(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 3075 (class 2606 OID 77842)
-- Name: user_alias fk_user_alias_parent; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.user_alias
    ADD CONSTRAINT fk_user_alias_parent FOREIGN KEY (parent_id) REFERENCES public.user_alias(id) ON DELETE CASCADE;


--
-- TOC entry 3318 (class 0 OID 0)
-- Dependencies: 217
-- Name: TABLE account; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.account TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.account TO users;


--
-- TOC entry 3320 (class 0 OID 0)
-- Dependencies: 213
-- Name: TABLE bank; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.bank TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.bank TO users;


--
-- TOC entry 3327 (class 0 OID 0)
-- Dependencies: 220
-- Name: TABLE calculation; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.calculation TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.calculation TO users;


--
-- TOC entry 3328 (class 0 OID 0)
-- Dependencies: 207
-- Name: TABLE changing_status; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.changing_status TO admins;
GRANT SELECT ON TABLE public.changing_status TO users;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.changing_status TO designers;


--
-- TOC entry 3329 (class 0 OID 0)
-- Dependencies: 209
-- Name: TABLE command; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.command TO admins;
GRANT SELECT ON TABLE public.command TO users;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.command TO designers;


--
-- TOC entry 3332 (class 0 OID 0)
-- Dependencies: 223
-- Name: TABLE condition; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.condition TO admins;
GRANT SELECT ON TABLE public.condition TO users;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.condition TO designers;


--
-- TOC entry 3341 (class 0 OID 0)
-- Dependencies: 210
-- Name: TABLE contractor; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.contractor TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.contractor TO users;


--
-- TOC entry 3344 (class 0 OID 0)
-- Dependencies: 228
-- Name: TABLE deduction; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.deduction TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.deduction TO users;


--
-- TOC entry 3354 (class 0 OID 0)
-- Dependencies: 202
-- Name: TABLE document_info; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.document_info TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.document_info TO users;


--
-- TOC entry 3355 (class 0 OID 0)
-- Dependencies: 203
-- Name: TABLE directory; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.directory TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.directory TO users;


--
-- TOC entry 3356 (class 0 OID 0)
-- Dependencies: 211
-- Name: SEQUENCE directory_code_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.directory_code_seq TO admins;
GRANT ALL ON SEQUENCE public.directory_code_seq TO users;


--
-- TOC entry 3357 (class 0 OID 0)
-- Dependencies: 225
-- Name: TABLE document; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.document TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.document TO users;


--
-- TOC entry 3359 (class 0 OID 0)
-- Dependencies: 235
-- Name: TABLE employee; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.employee TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.employee TO users;


--
-- TOC entry 3360 (class 0 OID 0)
-- Dependencies: 237
-- Name: TABLE form_preview; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.form_preview TO admins;
GRANT SELECT,UPDATE ON TABLE public.form_preview TO designers;
GRANT SELECT ON TABLE public.form_preview TO users;


--
-- TOC entry 3368 (class 0 OID 0)
-- Dependencies: 214
-- Name: TABLE goods; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.goods TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.goods TO users;


--
-- TOC entry 3370 (class 0 OID 0)
-- Dependencies: 206
-- Name: TABLE history; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.history TO admins;
GRANT SELECT,INSERT ON TABLE public.history TO users;


--
-- TOC entry 3372 (class 0 OID 0)
-- Dependencies: 205
-- Name: SEQUENCE history_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.history_id_seq TO admins;
GRANT ALL ON SEQUENCE public.history_id_seq TO users;


--
-- TOC entry 3373 (class 0 OID 0)
-- Dependencies: 230
-- Name: TABLE item_deduction; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.item_deduction TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.item_deduction TO users;


--
-- TOC entry 3377 (class 0 OID 0)
-- Dependencies: 221
-- Name: TABLE item_goods; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.item_goods TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.item_goods TO users;


--
-- TOC entry 3381 (class 0 OID 0)
-- Dependencies: 222
-- Name: TABLE item_operation; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.item_operation TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.item_operation TO users;


--
-- TOC entry 3389 (class 0 OID 0)
-- Dependencies: 201
-- Name: TABLE kind; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.kind TO admins;
GRANT SELECT ON TABLE public.kind TO users;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.kind TO designers;


--
-- TOC entry 3390 (class 0 OID 0)
-- Dependencies: 216
-- Name: TABLE kind_child; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.kind_child TO admins;
GRANT SELECT ON TABLE public.kind_child TO users;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.kind_child TO designers;


--
-- TOC entry 3392 (class 0 OID 0)
-- Dependencies: 215
-- Name: SEQUENCE kind_child_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.kind_child_id_seq TO admins;
GRANT ALL ON SEQUENCE public.kind_child_id_seq TO users;


--
-- TOC entry 3393 (class 0 OID 0)
-- Dependencies: 200
-- Name: TABLE kind_enum; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.kind_enum TO admins;
GRANT SELECT ON TABLE public.kind_enum TO users;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.kind_enum TO designers;


--
-- TOC entry 3395 (class 0 OID 0)
-- Dependencies: 212
-- Name: TABLE measurement; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.measurement TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.measurement TO users;


--
-- TOC entry 3397 (class 0 OID 0)
-- Dependencies: 224
-- Name: TABLE okopf; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.okopf TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.okopf TO users;


--
-- TOC entry 3398 (class 0 OID 0)
-- Dependencies: 236
-- Name: TABLE okpdtr; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.okpdtr TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.okpdtr TO users;


--
-- TOC entry 3404 (class 0 OID 0)
-- Dependencies: 219
-- Name: TABLE operation; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.operation TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.operation TO users;


--
-- TOC entry 3405 (class 0 OID 0)
-- Dependencies: 243
-- Name: TABLE operation_execute; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.operation_execute TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.operation_execute TO users;


--
-- TOC entry 3411 (class 0 OID 0)
-- Dependencies: 245
-- Name: TABLE operation_executor; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.operation_executor TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.operation_executor TO users;


--
-- TOC entry 3413 (class 0 OID 0)
-- Dependencies: 218
-- Name: TABLE operation_type; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.operation_type TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.operation_type TO users;


--
-- TOC entry 3414 (class 0 OID 0)
-- Dependencies: 241
-- Name: TABLE order_complete; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.order_complete TO users;
GRANT ALL ON TABLE public.order_complete TO admins;


--
-- TOC entry 3422 (class 0 OID 0)
-- Dependencies: 240
-- Name: TABLE order_detail; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.order_detail TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.order_detail TO users;


--
-- TOC entry 3424 (class 0 OID 0)
-- Dependencies: 239
-- Name: SEQUENCE order_detail_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.order_detail_id_seq TO admins;
GRANT ALL ON SEQUENCE public.order_detail_id_seq TO users;


--
-- TOC entry 3425 (class 0 OID 0)
-- Dependencies: 238
-- Name: TABLE order_production; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.order_production TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.order_production TO users;


--
-- TOC entry 3431 (class 0 OID 0)
-- Dependencies: 242
-- Name: TABLE order_shipped; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.order_shipped TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.order_shipped TO users;


--
-- TOC entry 3433 (class 0 OID 0)
-- Dependencies: 231
-- Name: TABLE organization; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.organization TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.organization TO users;


--
-- TOC entry 3435 (class 0 OID 0)
-- Dependencies: 229
-- Name: TABLE percentage; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.percentage TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.percentage TO users;


--
-- TOC entry 3441 (class 0 OID 0)
-- Dependencies: 234
-- Name: TABLE person; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.person TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.person TO users;


--
-- TOC entry 3444 (class 0 OID 0)
-- Dependencies: 204
-- Name: TABLE picture; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.picture TO admins;
GRANT SELECT ON TABLE public.picture TO users;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.picture TO designers;


--
-- TOC entry 3446 (class 0 OID 0)
-- Dependencies: 227
-- Name: TABLE price; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.price TO admins;
GRANT SELECT,INSERT ON TABLE public.price TO users;


--
-- TOC entry 3455 (class 0 OID 0)
-- Dependencies: 226
-- Name: TABLE request; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.request TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.request TO users;


--
-- TOC entry 3460 (class 0 OID 0)
-- Dependencies: 233
-- Name: TABLE request_detail; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.request_detail TO admins;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.request_detail TO users;


--
-- TOC entry 3462 (class 0 OID 0)
-- Dependencies: 232
-- Name: SEQUENCE request_detail_id_seq; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON SEQUENCE public.request_detail_id_seq TO admins;
GRANT ALL ON SEQUENCE public.request_detail_id_seq TO users;


--
-- TOC entry 3464 (class 0 OID 0)
-- Dependencies: 208
-- Name: TABLE sidebar; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.sidebar TO admins;
GRANT SELECT ON TABLE public.sidebar TO users;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.sidebar TO designers;


--
-- TOC entry 3468 (class 0 OID 0)
-- Dependencies: 198
-- Name: TABLE status; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.status TO admins;
GRANT SELECT ON TABLE public.status TO users;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.status TO designers;


--
-- TOC entry 3472 (class 0 OID 0)
-- Dependencies: 199
-- Name: TABLE transition; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.transition TO admins;
GRANT SELECT ON TABLE public.transition TO users;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.transition TO designers;


--
-- TOC entry 3479 (class 0 OID 0)
-- Dependencies: 197
-- Name: TABLE user_alias; Type: ACL; Schema: public; Owner: postgres
--

GRANT ALL ON TABLE public.user_alias TO admins;
GRANT SELECT ON TABLE public.user_alias TO guest;
GRANT SELECT ON TABLE public.user_alias TO users;


-- Completed on 2019-08-07 23:30:15

--
-- PostgreSQL database dump complete
--

