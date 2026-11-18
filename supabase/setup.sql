-- =====================================================================
--  Wayside Nails - Walk-in Queue
--  Database setup. Paste this whole file into Supabase > SQL Editor > Run.
--
--  BEFORE YOU RUN IT: change the manager password on the very last
--  lines of this file (search for  CHANGE-THIS-PASSWORD ).
--
--  It is safe to run this file again later: it updates the rules
--  without deleting your techs, services or history.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- 1. TABLES
-- ---------------------------------------------------------------------

-- General settings (one row only). Everyone can read this.
create table if not exists public.settings (
  id          int primary key default 1 check (id = 1),
  salon_name  text not null default 'Wayside Nails',
  timezone    text not null default 'America/New_York',
  current_day date
);
insert into public.settings (id) values (1) on conflict (id) do nothing;

-- The manager password (stored scrambled). Nobody can read this table.
create table if not exists public.app_secret (
  id            int primary key default 1 check (id = 1),
  password_hash text not null
);

-- Services the salon offers.
create table if not exists public.services (
  id         bigint generated always as identity primary key,
  name       text not null,
  sort_order int not null default 100,
  archived   boolean not null default false
);

-- All techs who work at the salon (on the line or not).
create table if not exists public.techs (
  id         bigint generated always as identity primary key,
  name       text not null,
  archived   boolean not null default false,
  created_at timestamptz not null default now()
);

-- Which tech can do which service.
create table if not exists public.tech_services (
  tech_id    bigint not null references public.techs(id) on delete cascade,
  service_id bigint not null references public.services(id) on delete cascade,
  primary key (tech_id, service_id)
);

-- The history log: one row per customer job.
create table if not exists public.jobs (
  id           bigint generated always as identity primary key,
  day          date not null,
  tech_id      bigint references public.techs(id) on delete set null,
  tech_name    text not null,
  service_name text not null,
  kind         text not null check (kind in ('walk-in', 'requested')),
  started_at   timestamptz not null default now(),
  finished_at  timestamptz
);
create index if not exists jobs_day_idx on public.jobs (day);

-- Today's line. A tech is "Off" when they have no row here.
--   waiting   = in the line, can get walk-ins
--   requested = keeps their spot, working on a requested customer
--   busy      = working on a walk-in, sits in the Busy area (no spot)
create table if not exists public.roster (
  tech_id    bigint primary key references public.techs(id) on delete cascade,
  status     text not null check (status in ('waiting', 'requested', 'busy')),
  position   bigint,
  job_id     bigint references public.jobs(id) on delete set null,
  updated_at timestamptz not null default now()
);

-- Saved copies of the line so "Undo" can go back one step.
create table if not exists public.undo_log (
  id         bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  label      text not null,
  roster     jsonb not null,
  jobs       jsonb not null
);

-- Default services (only added the first time).
insert into public.services (name, sort_order)
select v.name, v.ord
from (values ('Pedicure',1),('Manicure',2),('Full Set',3),('Fill',4),('Take Off',5),
             ('Waxing',6),('Eyebrows',7),('Dip',8),('Nail Polish',9)) as v(name, ord)
where not exists (select 1 from public.services);

-- ---------------------------------------------------------------------
-- 2. SECURITY: everyone may READ the line, nobody may WRITE directly.
--    All changes go through the password-checked functions below.
-- ---------------------------------------------------------------------
alter table public.settings      enable row level security;
alter table public.app_secret    enable row level security;
alter table public.services      enable row level security;
alter table public.techs         enable row level security;
alter table public.tech_services enable row level security;
alter table public.jobs          enable row level security;
alter table public.roster        enable row level security;
alter table public.undo_log      enable row level security;

do $$
declare t text;
begin
  -- Website visitors may only READ these tables (newer Supabase projects
  -- do not expose new tables automatically, so we grant it here).
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'grant usage on schema public to anon, authenticated';
    execute 'revoke all on public.app_secret, public.undo_log from anon, authenticated';
  end if;
  foreach t in array array['settings','services','techs','tech_services','jobs','roster'] loop
    if exists (select 1 from pg_roles where rolname = 'anon') then
      execute format('grant select on public.%I to anon, authenticated', t);
    end if;
    execute format('drop policy if exists "public read" on public.%I', t);
    execute format('create policy "public read" on public.%I for select using (true)', t);
  end loop;
end $$;

-- Live updates: tell Supabase to broadcast changes to these tables.
do $$
declare t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['settings','services','techs','tech_services','jobs','roster'] loop
      if not exists (select 1 from pg_publication_tables
                     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
        execute format('alter publication supabase_realtime add table public.%I', t);
      end if;
    end loop;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 3. HELPER FUNCTIONS (private, cannot be called from the website)
-- ---------------------------------------------------------------------
create schema if not exists private;
revoke all on schema private from public;

-- Today's date in the salon's time zone.
create or replace function private.salon_today() returns date
language sql stable set search_path = public as $$
  select (now() at time zone (select timezone from settings where id = 1))::date;
$$;

-- Starts a fresh day: empties the line, clears undo, drops history older than 30 days.
create or replace function private.ensure_today() returns void
language plpgsql set search_path = public as $$
declare d date := private.salon_today();
begin
  if (select current_day from settings where id = 1) is distinct from d then
    update jobs set finished_at = coalesce(finished_at, now()) where finished_at is null;
    delete from roster;
    delete from undo_log;
    delete from jobs where day < d - 30;
    update settings set current_day = d where id = 1;
  end if;
end $$;

-- Checks the password, makes requests wait their turn, and starts a new day if needed.
create or replace function private.begin_action(p_password text) returns void
language plpgsql set search_path = public, extensions as $$
begin
  if p_password is null or not exists (
       select 1 from app_secret where id = 1 and password_hash = crypt(p_password, password_hash)) then
    raise exception 'WRONG_PASSWORD';
  end if;
  -- One change at a time, even if two iPads tap at the same moment.
  perform pg_advisory_xact_lock(4242);
  perform private.ensure_today();
end $$;

-- Saves a copy of the line before a change, for Undo.
create or replace function private.save_undo(p_label text) returns void
language plpgsql set search_path = public as $$
begin
  insert into undo_log (label, roster, jobs) values (
    p_label,
    coalesce((select jsonb_agg(to_jsonb(r)) from roster r), '[]'::jsonb),
    coalesce((select jsonb_agg(to_jsonb(j)) from jobs j where j.day = private.salon_today()), '[]'::jsonb)
  );
  -- keep only the last 50 steps
  delete from undo_log where id not in (select id from undo_log order by id desc limit 50);
end $$;

create or replace function private.next_bottom() returns bigint
language sql stable set search_path = public as $$
  select coalesce(max(position), 0) + 1 from roster;
$$;

create or replace function private.tech_name(p_tech_id bigint) returns text
language sql stable set search_path = public as $$
  select name from techs where id = p_tech_id;
$$;

create or replace function private.result(p_ok boolean, p_message text) returns json
language sql immutable as $$
  select json_build_object('ok', p_ok, 'message', p_message);
$$;

-- ---------------------------------------------------------------------
-- 4. ACTIONS THE WEBSITE CAN CALL
-- ---------------------------------------------------------------------

-- Anyone can call this; it only starts a new day when the date changed.
create or replace function public.refresh_day() returns void
language plpgsql security definer set search_path = public as $$
begin
  perform pg_advisory_xact_lock(4242);
  perform private.ensure_today();
end $$;

-- Manager login. Also saves the salon's time zone from the iPad.
create or replace function public.check_login(p_password text, p_timezone text default null) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from app_secret where id = 1 and password_hash = crypt(p_password, password_hash)) then
    return false;
  end if;
  if p_timezone is not null and exists (select 1 from pg_timezone_names where name = p_timezone) then
    update settings set timezone = p_timezone where id = 1 and timezone <> p_timezone;
  end if;
  perform pg_advisory_xact_lock(4242);
  perform private.ensure_today();
  return true;
end $$;

-- Put a tech on the line (at the bottom).
create or replace function public.add_to_line(p_password text, p_tech_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare n text;
begin
  perform private.begin_action(p_password);
  select name into n from techs where id = p_tech_id and not archived;
  if n is null then return private.result(false, 'That tech was not found.'); end if;
  if exists (select 1 from roster where tech_id = p_tech_id) then
    return private.result(false, n || ' is already on the line.');
  end if;
  perform private.save_undo('Added ' || n);
  insert into roster (tech_id, status, position) values (p_tech_id, 'waiting', private.next_bottom());
  return private.result(true, n || ' added to the bottom of the line.');
end $$;

-- Take a tech off the line (break, leaving, day off). Any open job is closed.
create or replace function public.remove_from_line(p_password text, p_tech_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare r roster; n text := private.tech_name(p_tech_id);
begin
  perform private.begin_action(p_password);
  select * into r from roster where tech_id = p_tech_id;
  if r is null then return private.result(false, coalesce(n, 'That tech') || ' is not on the line.'); end if;
  perform private.save_undo('Removed ' || n);
  if r.job_id is not null then
    update jobs set finished_at = now() where id = r.job_id and finished_at is null;
  end if;
  delete from roster where tech_id = p_tech_id;
  return private.result(true, n || ' taken off the line.');
end $$;

-- A walk-in arrives: give them to the first free tech from the top who can do the service.
create or replace function public.assign_walkin(p_password text, p_service_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare s text; t_id bigint; n text; j_id bigint; busy_count int;
begin
  perform private.begin_action(p_password);
  select name into s from services where id = p_service_id and not archived;
  if s is null then return private.result(false, 'That service was not found.'); end if;

  select r.tech_id into t_id
  from roster r
  join tech_services ts on ts.tech_id = r.tech_id and ts.service_id = p_service_id
  where r.status = 'waiting'
  order by r.position
  limit 1;

  if t_id is null then
    select count(*) into busy_count
    from roster r join tech_services ts on ts.tech_id = r.tech_id and ts.service_id = p_service_id;
    if busy_count = 0 then
      return private.result(false, 'Nobody on the line today can do ' || s || '.');
    end if;
    return private.result(false, 'No one is free for ' || s || ' right now. All '
      || busy_count || ' tech(s) who do it are busy.');
  end if;

  n := private.tech_name(t_id);
  perform private.save_undo(s || ' walk-in to ' || n);
  insert into jobs (day, tech_id, tech_name, service_name, kind)
    values (private.salon_today(), t_id, n, s, 'walk-in') returning id into j_id;
  update roster set status = 'busy', position = null, job_id = j_id, updated_at = now()
    where tech_id = t_id;
  return json_build_object('ok', true, 'message', s || ' walk-in goes to ' || n || '.', 'tech_name', n);
end $$;

-- A customer asked for a specific tech: the tech keeps their spot but is not available.
create or replace function public.mark_requested(p_password text, p_tech_id bigint, p_service_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare r roster; n text := private.tech_name(p_tech_id); s text; j_id bigint;
begin
  perform private.begin_action(p_password);
  select name into s from services where id = p_service_id;
  if s is null then return private.result(false, 'Please pick a service.'); end if;
  select * into r from roster where tech_id = p_tech_id;
  if r is null then
    return private.result(false, coalesce(n, 'That tech') || ' is not on the line. Add them first.');
  end if;
  if r.status = 'busy' then
    return private.result(false, n || ' is busy with a walk-in. Mark them done first.');
  end if;
  if r.status = 'requested' then
    return private.result(false, n || ' is already with a requested customer. Mark them done first.');
  end if;
  perform private.save_undo(s || ' request for ' || n);
  insert into jobs (day, tech_id, tech_name, service_name, kind)
    values (private.salon_today(), p_tech_id, n, s, 'requested') returning id into j_id;
  update roster set status = 'requested', job_id = j_id, updated_at = now() where tech_id = p_tech_id;
  return private.result(true, n || ' is with a requested customer (' || s || ') and keeps spot.');
end $$;

-- A tech finished their customer.
--   walk-in   -> back to the bottom of the line
--   requested -> available again in the same spot
create or replace function public.finish_job(p_password text, p_tech_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare r roster; n text := private.tech_name(p_tech_id);
begin
  perform private.begin_action(p_password);
  select * into r from roster where tech_id = p_tech_id;
  if r is null or r.status = 'waiting' then
    return private.result(false, coalesce(n, 'That tech') || ' is not working on a customer.');
  end if;
  perform private.save_undo(n || ' finished');
  update jobs set finished_at = now() where id = r.job_id and finished_at is null;
  if r.status = 'busy' then
    update roster set status = 'waiting', position = private.next_bottom(), job_id = null, updated_at = now()
      where tech_id = p_tech_id;
    return private.result(true, n || ' is done and back at the bottom of the line.');
  else
    update roster set status = 'waiting', job_id = null, updated_at = now() where tech_id = p_tech_id;
    return private.result(true, n || ' is done and available again in the same spot.');
  end if;
end $$;

-- Manager dragged the line into a new order. p_tech_ids = everyone with a spot, top to bottom.
create or replace function public.reorder_line(p_password text, p_tech_ids bigint[]) returns json
language plpgsql security definer set search_path = public as $$
begin
  perform private.begin_action(p_password);
  if (select coalesce(array_agg(tech_id order by tech_id), '{}') from roster where position is not null)
     is distinct from (select coalesce(array_agg(x order by x), '{}') from unnest(p_tech_ids) x) then
    return private.result(false, 'The line changed while you were dragging. Please try again.');
  end if;
  perform private.save_undo('Reordered the line');
  update roster r set position = o.ord, updated_at = now()
  from unnest(p_tech_ids) with ordinality as o(tech_id, ord)
  where r.tech_id = o.tech_id;
  return private.result(true, 'Line order saved.');
end $$;

-- Go back one step.
create or replace function public.undo_last(p_password text) returns json
language plpgsql security definer set search_path = public as $$
declare u undo_log;
begin
  perform private.begin_action(p_password);
  select * into u from undo_log order by id desc limit 1;
  if u is null then return private.result(false, 'Nothing to undo.'); end if;

  delete from roster;
  delete from jobs where day = private.salon_today();
  insert into jobs overriding system value
    select * from jsonb_populate_recordset(null::jobs, u.jobs);
  insert into roster
    select x.* from jsonb_populate_recordset(null::roster, u.roster) x
    where exists (select 1 from techs t where t.id = x.tech_id and not t.archived);
  update roster set job_id = null where job_id is not null and job_id not in (select id from jobs);
  delete from undo_log where id = u.id;
  return private.result(true, 'Undone: ' || u.label);
end $$;

-- What the Undo button should say.
create or replace function public.last_undo_label(p_password text) returns text
language plpgsql security definer set search_path = public as $$
begin
  perform private.begin_action(p_password);
  return (select label from undo_log order by id desc limit 1);
end $$;

-- Add a new tech, or rename one and set their services.
create or replace function public.save_tech(p_password text, p_tech_id bigint, p_name text, p_service_ids bigint[]) returns json
language plpgsql security definer set search_path = public as $$
declare t_id bigint := p_tech_id; nm text := btrim(coalesce(p_name, ''));
begin
  perform private.begin_action(p_password);
  if nm = '' then return private.result(false, 'Please type a name.'); end if;
  if exists (select 1 from techs where lower(name) = lower(nm) and not archived and id is distinct from t_id) then
    return private.result(false, 'There is already a tech named ' || nm || '.');
  end if;
  if t_id is null then
    insert into techs (name) values (nm) returning id into t_id;
  else
    update techs set name = nm where id = t_id and not archived;
    if not found then return private.result(false, 'That tech was not found.'); end if;
  end if;
  delete from tech_services where tech_id = t_id;
  insert into tech_services (tech_id, service_id)
    select distinct t_id, s.id from services s where s.id = any(coalesce(p_service_ids, '{}')) and not s.archived;
  return private.result(true, nm || ' saved.');
end $$;

-- Delete a tech (history is kept).
create or replace function public.delete_tech(p_password text, p_tech_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare n text := private.tech_name(p_tech_id);
begin
  perform private.begin_action(p_password);
  update jobs set finished_at = now()
    where id in (select job_id from roster where tech_id = p_tech_id) and finished_at is null;
  delete from roster where tech_id = p_tech_id;
  delete from tech_services where tech_id = p_tech_id;
  update techs set archived = true where id = p_tech_id;
  return private.result(true, coalesce(n, 'Tech') || ' deleted.');
end $$;

-- Add a custom service.
create or replace function public.add_service(p_password text, p_name text) returns json
language plpgsql security definer set search_path = public as $$
declare nm text := btrim(coalesce(p_name, ''));
begin
  perform private.begin_action(p_password);
  if nm = '' then return private.result(false, 'Please type a service name.'); end if;
  if exists (select 1 from services where lower(name) = lower(nm) and not archived) then
    return private.result(false, nm || ' already exists.');
  end if;
  insert into services (name, sort_order)
    values (nm, coalesce((select max(sort_order) from services), 0) + 1);
  return private.result(true, nm || ' added. Now tick which techs can do it.');
end $$;

-- Delete a service (history keeps the name).
create or replace function public.delete_service(p_password text, p_service_id bigint) returns json
language plpgsql security definer set search_path = public as $$
declare nm text;
begin
  perform private.begin_action(p_password);
  update services set archived = true where id = p_service_id returning name into nm;
  delete from tech_services where service_id = p_service_id;
  return private.result(true, coalesce(nm, 'Service') || ' deleted.');
end $$;

-- Change the manager password.
create or replace function public.change_password(p_password text, p_new_password text) returns json
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform private.begin_action(p_password);
  if length(coalesce(p_new_password, '')) < 6 then
    return private.result(false, 'The new password must be at least 6 characters.');
  end if;
  update app_secret set password_hash = crypt(p_new_password, gen_salt('bf')) where id = 1;
  return private.result(true, 'Password changed. Use the new one on every device.');
end $$;

-- Only the website-facing functions may be called from outside.
revoke all on all functions in schema private from public;
do $$
declare f text;
begin
  for f in select p.oid::regprocedure::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in (
             'refresh_day','check_login','add_to_line','remove_from_line','assign_walkin','mark_requested',
             'finish_job','reorder_line','undo_last','last_undo_label','save_tech','delete_tech',
             'add_service','delete_service','change_password') loop
    execute format('revoke all on function %s from public', f);
    if exists (select 1 from pg_roles where rolname = 'anon') then
      execute format('grant execute on function %s to anon, authenticated', f);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 5. MANAGER PASSWORD  (only set the first time this file runs)
--    Change  CHANGE-THIS-PASSWORD  below to your own password first!
--    Later you can change it inside the app (Techs & Services tab).
-- ---------------------------------------------------------------------
insert into public.app_secret (id, password_hash)
values (1, extensions.crypt('CHANGE-THIS-PASSWORD', extensions.gen_salt('bf')))
on conflict (id) do nothing;
