-- Run with psql against a disposable local database after migrations and seed.
\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','alice@example.invalid',now(),'{}'),
('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','bob@example.invalid',now(),'{}');
select starts_at as slot from public.available_slots('11111111-1111-4111-8111-111111111111','33333333-3333-4333-8333-333333333333',(current_date+(8-extract(dow from current_date)::int))::date) limit 1 \gset
select set_config('test.slot', :'slot', true);
set local request.jwt.claim.sub='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
set local role authenticated;
select public.book_appointment('11111111-1111-4111-8111-111111111111','33333333-3333-4333-8333-333333333333',:'slot');
reset role;
set local request.jwt.claim.sub='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
set local role authenticated;
do $$ begin
  perform public.book_appointment('11111111-1111-4111-8111-111111111111','33333333-3333-4333-8333-333333333333',current_setting('test.slot')::timestamptz);
  raise exception 'Double booking incorrectly succeeded';
exception when sqlstate 'P0001' then null;
end $$;
reset role;
do $$ begin
  if (select count(*) from public.appointments where starts_at=current_setting('test.slot')::timestamptz) <> 1 then raise exception 'Expected one booking'; end if;
end $$;
rollback;
