\set ON_ERROR_STOP on
begin;
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data) values
('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','admin@example.invalid',now(),'{}'),
('ffffffff-ffff-4fff-8fff-ffffffffffff','doctor@example.invalid',now(),'{}'),
('99999999-9999-4999-8999-999999999999','patient@example.invalid',now(),'{}');
set local request.jwt.claim.sub='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
set local role authenticated;
select public.register_clinic('Test Clinic','1 Main Road','Test City','Asia/Kolkata',null) as clinic_id \gset
select public.add_clinic_doctor(:'clinic_id','Dr. Test','doctor@example.invalid',(select id from public.specialties where name='Family Medicine'),30) as doctor_id \gset
select public.add_schedule(:'clinic_id',:'doctor_id',extract(dow from current_date+1)::integer,'09:00','17:00');
select public.clinic_metrics(:'clinic_id',current_date+1);
reset role;
select set_config('test.clinic',:'clinic_id',true),set_config('test.doctor',:'doctor_id',true);
insert into public.appointments(patient_id,doctor_id,clinic_id,starts_at,ends_at)
values('99999999-9999-4999-8999-999999999999',:'doctor_id',:'clinic_id',now()-interval '1 hour',now()-interval '30 minutes') returning id as completed_id \gset
select set_config('test.completed',:'completed_id',true);
set local request.jwt.claim.sub='ffffffff-ffff-4fff-8fff-ffffffffffff';
set local role authenticated;
select public.finish_appointment(:'completed_id','completed');
reset role;
do $$ begin
  if (select status from public.appointments where id=current_setting('test.completed')::uuid) <> 'completed' then raise exception 'Doctor could not conclude visit'; end if;
end $$;
do $$ begin
  if not exists(select 1 from public.available_slots(current_setting('test.clinic')::uuid,current_setting('test.doctor')::uuid,current_date+1)) then raise exception 'Schedule generated no slots'; end if;
end $$;
set local request.jwt.claim.sub='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
set local role authenticated;
select public.add_day_unavailability(:'clinic_id',:'doctor_id',current_date+1,'Test closure');
reset role;
do $$ begin
  if exists(select 1 from public.available_slots(current_setting('test.clinic')::uuid,current_setting('test.doctor')::uuid,current_date+1)) then raise exception 'Unavailable day still has slots'; end if;
end $$;
select starts_at as slot from public.available_slots('11111111-1111-4111-8111-111111111111','33333333-3333-4333-8333-333333333333',(current_date+(8-extract(dow from current_date)::integer))::date) limit 1 \gset
select set_config('test.slot',:'slot',true);
set local request.jwt.claim.sub='99999999-9999-4999-8999-999999999999';
set local role authenticated;
select public.book_appointment('11111111-1111-4111-8111-111111111111','33333333-3333-4333-8333-333333333333',:'slot') as booking_id \gset
reset role;
select set_config('test.booking',:'booking_id',true);
do $$ begin
  if (select count(*) from public.notifications where appointment_id=current_setting('test.booking')::uuid) <> 2 then raise exception 'Expected confirmation and reminder'; end if;
end $$;
set local role service_role;
do $$ begin
  if (select count(*) from public.claim_notifications(10) where appointment_id=current_setting('test.booking')::uuid and kind='confirmation') <> 1 then
    raise exception 'Confirmation was not claimed for delivery';
  end if;
end $$;
reset role;
set local request.jwt.claim.sub='ffffffff-ffff-4fff-8fff-ffffffffffff';
set local role authenticated;
do $$ begin
  perform public.cancel_appointment(current_setting('test.booking')::uuid);
  raise exception 'Doctor account changed another patient booking';
exception when sqlstate '42501' then null;
end $$;
reset role;
set local request.jwt.claim.sub='99999999-9999-4999-8999-999999999999';
set local role authenticated;
select public.cancel_appointment(:'booking_id');
reset role;
do $$ begin
  if (select status from public.appointments where id=current_setting('test.booking')::uuid) <> 'cancelled' then raise exception 'Cancellation failed'; end if;
  if (select count(*) from public.notifications where appointment_id=current_setting('test.booking')::uuid and kind='reminder' and delivered_at is null) <> 0 then raise exception 'Cancelled booking still has queued reminder'; end if;
end $$;
insert into public.clinics(id,name,address,city,time_zone,booking_cutoff_minutes) values
('66666666-6666-4666-8666-666666666666','DST Clinic','1 Test Street','New York','America/New_York',0);
insert into public.doctors(id,display_name) values ('77777777-7777-4777-8777-777777777777','Dr. DST');
insert into public.doctor_clinics(doctor_id,clinic_id,consultation_minutes) values
('77777777-7777-4777-8777-777777777777','66666666-6666-4666-8666-666666666666',30);
insert into public.schedules(doctor_id,clinic_id,weekday,start_local,end_local) values
('77777777-7777-4777-8777-777777777777','66666666-6666-4666-8666-666666666666',0,'01:00','02:00');
select set_config('test.dst_day',(
  make_date(extract(year from current_date)::integer+1,11,1)
  + ((7-extract(dow from make_date(extract(year from current_date)::integer+1,11,1))::integer)%7)
)::text,true);
do $$ begin
  if (select count(*) from public.available_slots('66666666-6666-4666-8666-666666666666','77777777-7777-4777-8777-777777777777',current_setting('test.dst_day')::date)
      where (starts_at at time zone 'America/New_York')::time='01:00') <> 2 then
    raise exception 'DST repeated hour did not produce two distinct instants';
  end if;
end $$;
rollback;
