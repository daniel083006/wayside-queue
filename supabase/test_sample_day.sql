-- Sample-day test for the queue rules. For a developer's test database only:
-- it ADDS test techs, so do NOT run it on the real salon database.
-- Each check prints PASS or FAIL.
\set pw '''CHANGE-THIS-PASSWORD'''
set client_min_messages = warning;

create or replace function pg_temp.line() returns text language sql as $$
  select coalesce(string_agg(t.name || case r.status when 'requested' then '(R)' else '' end, ', ' order by r.position), '')
  from roster r join techs t on t.id = r.tech_id where r.position is not null;
$$;
create or replace function pg_temp.busy() returns text language sql as $$
  select coalesce(string_agg(t.name, ', ' order by t.name), '')
  from roster r join techs t on t.id = r.tech_id where r.status = 'busy';
$$;
create or replace function pg_temp.check(label text, got text, want text) returns text language sql as $$
  select case when got is not distinct from want then 'PASS  ' else 'FAIL  ' end || label
         || case when got is distinct from want then '   got: ' || coalesce(got,'NULL') || '   want: ' || want else '' end;
$$;
create or replace function pg_temp.tid(n text) returns bigint language sql as $$ select id from techs where name = n and not archived $$;
create or replace function pg_temp.sid(n text) returns bigint language sql as $$ select id from services where name = n and not archived $$;

select check_login(:pw, 'America/New_York') as login_ok, check_login('wrong') as wrong_login;

-- Techs from the example: Maria (pedicure, eyebrows), Linh (pedicure, full set, eyebrows), Ana (full set)
select save_tech(:pw, null, 'Maria', array[pg_temp.sid('Pedicure'), pg_temp.sid('Eyebrows')]);
select save_tech(:pw, null, 'Linh',  array[pg_temp.sid('Pedicure'), pg_temp.sid('Full Set'), pg_temp.sid('Eyebrows')]);
select save_tech(:pw, null, 'Ana',   array[pg_temp.sid('Full Set')]);
select save_tech(:pw, null, 'Kim',   array[pg_temp.sid('Waxing')]);

select add_to_line(:pw, pg_temp.tid('Maria'));
select add_to_line(:pw, pg_temp.tid('Linh'));
select add_to_line(:pw, pg_temp.tid('Ana'));
select pg_temp.check('morning line', pg_temp.line(), 'Maria, Linh, Ana');

-- Example: full set walk-in -> Maria skipped, Linh gets it
select assign_walkin(:pw, pg_temp.sid('Full Set'))->>'message';
select pg_temp.check('full set skips Maria, Linh busy', pg_temp.line() || ' | ' || pg_temp.busy(), 'Maria, Ana | Linh');
select pg_temp.check('Linh finishes -> bottom', (finish_job(:pw, pg_temp.tid('Linh'))->>'ok') || ' ' || pg_temp.line(), 'true Maria, Ana, Linh');

-- Requested tech keeps spot and moves up
select mark_requested(:pw, pg_temp.tid('Ana'), pg_temp.sid('Full Set'))->>'message';
select pg_temp.check('Ana requested keeps spot', pg_temp.line(), 'Maria, Ana(R), Linh');
select pg_temp.check('pedicure goes to Maria', assign_walkin(:pw, pg_temp.sid('Pedicure'))->>'tech_name', 'Maria');
select pg_temp.check('Ana moved up to #1', pg_temp.line(), 'Ana(R), Linh');
select pg_temp.check('full set skips requested Ana, goes to Linh', assign_walkin(:pw, pg_temp.sid('Full Set'))->>'tech_name', 'Linh');
select pg_temp.check('everyone busy message', assign_walkin(:pw, pg_temp.sid('Full Set'))->>'message',
                     'No one is free for Full Set right now. All 2 tech(s) who do it are busy.');
select pg_temp.check('no eligible tech message', assign_walkin(:pw, pg_temp.sid('Waxing'))->>'message',
                     'Nobody on the line today can do Waxing.');
select pg_temp.check('requested tech busy is blocked', mark_requested(:pw, pg_temp.tid('Linh'), pg_temp.sid('Pedicure'))->>'message',
                     'Linh is busy with a walk-in. Mark them done first.');
select pg_temp.check('Ana done -> same spot (#1)', (finish_job(:pw, pg_temp.tid('Ana'))->>'ok') || ' ' || pg_temp.line(), 'true Ana');
select pg_temp.check('back-to-back request', mark_requested(:pw, pg_temp.tid('Ana'), pg_temp.sid('Fill'))->>'ok', 'true');
select finish_job(:pw, pg_temp.tid('Ana'));
select finish_job(:pw, pg_temp.tid('Maria'));
select finish_job(:pw, pg_temp.tid('Linh'));
select pg_temp.check('after finishing', pg_temp.line(), 'Ana, Maria, Linh');

-- Undo
select assign_walkin(:pw, pg_temp.sid('Eyebrows'));
select pg_temp.check('eyebrows -> Maria', pg_temp.busy(), 'Maria');
select pg_temp.check('undo label', last_undo_label(:pw), 'Eyebrows walk-in to Maria');
select undo_last(:pw)->>'message';
select pg_temp.check('undo restores line', pg_temp.line() || ' | ' || pg_temp.busy(), 'Ana, Maria, Linh | ');
select pg_temp.check('undo removed history row', (select count(*)::text from jobs where service_name = 'Eyebrows'), '0');

-- Reorder
select reorder_line(:pw, array[pg_temp.tid('Linh'), pg_temp.tid('Ana'), pg_temp.tid('Maria')])->>'message';
select pg_temp.check('reorder', pg_temp.line(), 'Linh, Ana, Maria');
select pg_temp.check('reorder with stale list rejected', reorder_line(:pw, array[pg_temp.tid('Linh')])->>'ok', 'false');

-- Remove mid-shift while busy, then come back at bottom
select assign_walkin(:pw, pg_temp.sid('Pedicure'));
select pg_temp.check('pedicure -> Linh (top)', pg_temp.busy(), 'Linh');
select remove_from_line(:pw, pg_temp.tid('Linh'));
select pg_temp.check('removed busy tech job is closed', (select (finished_at is not null)::text from jobs order by id desc limit 1), 'true');
select add_to_line(:pw, pg_temp.tid('Kim'));
select add_to_line(:pw, pg_temp.tid('Linh'));
select pg_temp.check('returns at bottom', pg_temp.line(), 'Ana, Maria, Kim, Linh');

-- Two services at once (pedicure + manicure style): two techs taken
select save_tech(:pw, pg_temp.tid('Ana'), 'Ana', array[pg_temp.sid('Full Set'), pg_temp.sid('Pedicure')]);
select assign_walkin(:pw, pg_temp.sid('Pedicure'));
select assign_walkin(:pw, pg_temp.sid('Pedicure'));
select pg_temp.check('two pedicures = two techs', pg_temp.busy(), 'Ana, Maria');

-- Security: wrong password and direct writes are refused
set client_min_messages = notice;
do $$ begin perform assign_walkin('nope', 1); raise notice 'FAIL  wrong password allowed';
exception when others then raise notice 'PASS  wrong password refused (%)', sqlerrm; end $$;
set role anon;
do $$ begin delete from roster; if exists (select 1 from roster) then raise notice 'PASS  anon cannot delete line';
  else raise notice 'FAIL  anon deleted line'; end if;
exception when insufficient_privilege then raise notice 'PASS  anon cannot delete line'; end $$;
do $$ begin perform 1 from app_secret; if not found then raise notice 'PASS  anon cannot read password'; else raise notice 'FAIL  password readable'; end if;
exception when insufficient_privilege then raise notice 'PASS  anon cannot read password'; end $$;
do $$ begin perform private.ensure_today(); raise notice 'FAIL  anon called private';
exception when others then raise notice 'PASS  anon cannot call private functions'; end $$;
reset role;

-- New day resets the line and keeps history
update settings set current_day = current_day - 1;
select refresh_day();
select pg_temp.check('new day: line empty', pg_temp.line() || pg_temp.busy(), '');
select pg_temp.check('history kept', (select (count(*) > 0)::text from jobs), 'true');
