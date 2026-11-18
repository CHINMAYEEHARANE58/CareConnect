-- Account deletion removes the patient's booking data through the auth -> profile cascade.
alter table public.appointments drop constraint appointments_patient_id_fkey;
alter table public.appointments add constraint appointments_patient_id_fkey foreign key (patient_id) references public.profiles(id) on delete cascade;

-- A patient name is visible to staff only when they have an appointment to manage.
create policy profiles_booking_staff on public.profiles for select to authenticated using (
  exists(select 1 from public.appointments a where a.patient_id=profiles.id and (public.is_doctor(a.doctor_id) or public.is_clinic_admin(a.clinic_id)))
);
-- The mobile client can acknowledge a notification; delivery state stays server owned.
revoke update on public.notifications from authenticated;
grant update(read_at) on public.notifications to authenticated;

-- Generate over real UTC instants. This retains both occurrences of a repeated local hour
-- and skips nonexistent clock times when a time zone moves its clocks forward.
create or replace function public.available_slots(p_clinic uuid,p_doctor uuid,p_day date)
returns table(starts_at timestamptz,ends_at timestamptz) language sql stable security definer set search_path = public as $$
  with clinic as (
    select c.time_zone,c.booking_cutoff_minutes,dc.consultation_minutes
    from clinics c join doctor_clinics dc on dc.clinic_id=c.id
    join doctors d on d.id=dc.doctor_id
    where c.id=p_clinic and dc.doctor_id=p_doctor and c.active and dc.active and d.active
  ), candidates as (
    select g.instant as starts_at,g.instant+make_interval(mins=>clinic.consultation_minutes) as ends_at
    from clinic join schedules s on s.clinic_id=p_clinic and s.doctor_id=p_doctor
    cross join lateral generate_series(
      p_day::timestamp at time zone clinic.time_zone,
      (p_day+1)::timestamp at time zone clinic.time_zone - interval '1 minute',
      interval '1 minute') as g(instant)
    where s.weekday=extract(dow from p_day)::integer and p_day>=s.valid_from and (s.valid_until is null or p_day<=s.valid_until)
      and (g.instant at time zone clinic.time_zone)::date=p_day
      and (g.instant at time zone clinic.time_zone)::time>=s.start_local
      and ((g.instant+make_interval(mins=>clinic.consultation_minutes)) at time zone clinic.time_zone)::date=p_day
      and ((g.instant+make_interval(mins=>clinic.consultation_minutes)) at time zone clinic.time_zone)::time<=s.end_local
      and (extract(epoch from ((g.instant at time zone clinic.time_zone)::time-s.start_local))::integer/60) % clinic.consultation_minutes=0
      and g.instant>=now()+make_interval(mins=>clinic.booking_cutoff_minutes)
  )
  select distinct candidates.starts_at,candidates.ends_at from candidates
  where not exists(select 1 from schedule_exceptions e where e.clinic_id=p_clinic and (e.doctor_id is null or e.doctor_id=p_doctor) and tstzrange(e.starts_at,e.ends_at,'[)') && tstzrange(candidates.starts_at,candidates.ends_at,'[)'))
    and not exists(select 1 from appointments a where a.doctor_id=p_doctor and a.status='booked' and a.during && tstzrange(candidates.starts_at,candidates.ends_at,'[)'))
  order by starts_at;
$$;

alter table public.notifications add column delivery_locked_until timestamptz;
create function public.claim_notifications(p_limit integer default 50)
returns setof public.notifications language plpgsql security definer set search_path=public as $$
begin
  return query
    with picked as (select id from notifications
      where delivered_at is null and deliver_after<=now() and attempts<5
        and (delivery_locked_until is null or delivery_locked_until<now())
      order by deliver_after for update skip locked limit least(greatest(p_limit,1),100))
    update notifications n set delivery_locked_until=now()+interval '2 minutes',attempts=n.attempts+1
    from picked where n.id=picked.id returning n.*;
end $$;
revoke all on function public.claim_notifications(integer) from public,anon,authenticated;
grant execute on function public.claim_notifications(integer) to service_role;

create function public.add_clinic_holiday(p_clinic uuid,p_start timestamptz,p_end timestamptz,p_reason text default '')
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if not public.is_clinic_admin(p_clinic) then raise exception 'Forbidden' using errcode='42501'; end if;
  if p_end<=p_start then raise exception 'Invalid interval'; end if;
  insert into schedule_exceptions(clinic_id,starts_at,ends_at,reason) values(p_clinic,p_start,p_end,p_reason) returning id into v_id;
  return v_id;
end $$;
revoke all on function public.add_clinic_holiday(uuid,timestamptz,timestamptz,text) from public;
grant execute on function public.add_clinic_holiday(uuid,timestamptz,timestamptz,text) to authenticated;

create function public.add_day_unavailability(p_clinic uuid,p_doctor uuid,p_day date,p_reason text default '')
returns uuid language plpgsql security definer set search_path=public as $$
declare v_zone text; v_id uuid;
begin
  if not (public.is_clinic_admin(p_clinic) or (p_doctor is not null and public.is_doctor(p_doctor) and exists(select 1 from doctor_clinics where clinic_id=p_clinic and doctor_id=p_doctor))) then raise exception 'Forbidden' using errcode='42501'; end if;
  select time_zone into v_zone from clinics where id=p_clinic;
  if v_zone is null then raise exception 'Clinic not found'; end if;
  insert into schedule_exceptions(clinic_id,doctor_id,starts_at,ends_at,reason)
    values(p_clinic,p_doctor,p_day::timestamp at time zone v_zone,(p_day+1)::timestamp at time zone v_zone,p_reason)
    returning id into v_id;
  return v_id;
end $$;
revoke all on function public.add_day_unavailability(uuid,uuid,date,text) from public;
grant execute on function public.add_day_unavailability(uuid,uuid,date,text) to authenticated;

-- Explicit privileges; RLS further narrows which rows can be read or edited.
grant usage on schema public to anon,authenticated;
grant select on public.clinics,public.specialties,public.doctors,public.doctor_specialties,public.doctor_clinics,public.schedules to anon;
grant select on public.profiles,public.clinics,public.specialties,public.doctors,public.doctor_specialties,public.clinic_memberships,public.doctor_clinics,public.schedules,public.schedule_exceptions,public.appointments,public.appointment_status_history,public.notifications,public.audit_events to authenticated;
grant update(full_name,phone,notification_enabled,updated_at) on public.profiles to authenticated;
grant update(name,description,address,city,phone,email,time_zone,booking_cutoff_minutes,cancellation_cutoff_minutes,active) on public.clinics to authenticated;

create function public.clinic_today(p_clinic uuid) returns date language sql stable security definer set search_path=public as $$
  select (now() at time zone time_zone)::date from clinics where id=p_clinic and active
$$;
grant execute on function public.clinic_today(uuid) to anon,authenticated;

create function public.validate_unavailability() returns trigger language plpgsql set search_path=public as $$
begin
  perform 1 from clinics where id=new.clinic_id for update;
  if exists(select 1 from appointments a where a.clinic_id=new.clinic_id and a.status='booked'
    and (new.doctor_id is null or a.doctor_id=new.doctor_id)
    and a.during && tstzrange(new.starts_at,new.ends_at,'[)')) then
    raise exception 'Existing bookings overlap this unavailable period. Reschedule or cancel them first.';
  end if;
  return new;
end $$;
create trigger check_unavailability before insert or update on public.schedule_exceptions
for each row execute function public.validate_unavailability();

create function public.clinic_metrics(p_clinic uuid,p_day date) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare v_zone text; v_booked integer; v_cancelled integer; v_total integer; v_available integer;
begin
  if not public.is_clinic_admin(p_clinic) then raise exception 'Forbidden' using errcode='42501'; end if;
  select time_zone into v_zone from clinics where id=p_clinic;
  if v_zone is null then raise exception 'Clinic not found'; end if;
  select count(*) filter (where status='booked'),count(*) filter (where status='cancelled'),count(*)
    into v_booked,v_cancelled,v_total from appointments
    where clinic_id=p_clinic and (starts_at at time zone v_zone)::date=p_day;
  select count(*) into v_available from doctor_clinics dc
    cross join lateral public.available_slots(p_clinic,dc.doctor_id,p_day) s
    where dc.clinic_id=p_clinic and dc.active;
  return jsonb_build_object('booked',v_booked,'available',v_available,'cancelled',v_cancelled,
    'cancellation_rate',case when v_total=0 then 0 else round(100.0*v_cancelled/v_total) end,
    'utilization',case when v_booked+v_available=0 then 0 else round(100.0*v_booked/(v_booked+v_available)) end);
end $$;
revoke all on function public.clinic_metrics(uuid,date) from public;
grant execute on function public.clinic_metrics(uuid,date) to authenticated;

create function public.purge_expired_data(p_now timestamptz default now()) returns void
language plpgsql security definer set search_path=public as $$
begin
  delete from notifications where created_at < p_now - interval '90 days';
  delete from appointments where status in ('completed','no_show','cancelled') and ends_at < p_now - interval '730 days';
  delete from audit_events where occurred_at < p_now - interval '730 days';
end $$;
revoke all on function public.purge_expired_data(timestamptz) from public,anon,authenticated;
grant execute on function public.purge_expired_data(timestamptz) to service_role;

insert into public.specialties(name) values ('Family Medicine'),('Dermatology'),('Pediatrics'),('Cardiology'),('Orthopedics'),('General Surgery') on conflict do nothing;

create function public.validate_clinic_update() returns trigger language plpgsql set search_path=public as $$
begin
  if not exists(select 1 from pg_timezone_names where name=new.time_zone) then raise exception 'Invalid time zone'; end if;
  if tg_op='UPDATE' and old.active and not new.active and exists(select 1 from appointments where clinic_id=new.id and status='booked' and ends_at>now()) then
    raise exception 'Cancel or reschedule future bookings before deactivating a clinic';
  end if;
  return new;
end $$;
create trigger validate_clinic before insert or update on public.clinics
for each row execute function public.validate_clinic_update();

create function public.available_today_doctors()
returns table(clinic_id uuid,doctor_id uuid) language sql stable security definer set search_path=public as $$
  select dc.clinic_id,dc.doctor_id from doctor_clinics dc join clinics c on c.id=dc.clinic_id
  join doctors d on d.id=dc.doctor_id
  where dc.active and c.active and d.active
    and exists(select 1 from public.available_slots(dc.clinic_id,dc.doctor_id,(now() at time zone c.time_zone)::date));
$$;
grant execute on function public.available_today_doctors() to anon,authenticated;

create index schedules_lookup_idx on public.schedules(clinic_id,doctor_id,weekday,valid_from);
create index exceptions_overlap_idx on public.schedule_exceptions using gist(clinic_id,tstzrange(starts_at,ends_at,'[)'));
create index appointments_clinic_start_idx on public.appointments(clinic_id,starts_at);

create function public.set_doctor_clinic_active(p_clinic uuid,p_doctor uuid,p_active boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_clinic_admin(p_clinic) then raise exception 'Forbidden' using errcode='42501'; end if;
  perform 1 from clinics where id=p_clinic for update;
  if not p_active and exists(select 1 from appointments where clinic_id=p_clinic and doctor_id=p_doctor and status='booked' and ends_at>now()) then
    raise exception 'Move or cancel future bookings before deactivating this doctor';
  end if;
  update doctor_clinics set active=p_active where clinic_id=p_clinic and doctor_id=p_doctor;
  if not found then raise exception 'Provider not found'; end if;
  insert into audit_events(actor_id,clinic_id,entity,entity_id,action)
    values(auth.uid(),p_clinic,'doctor',p_doctor,case when p_active then 'activated' else 'deactivated' end);
end $$;
revoke all on function public.set_doctor_clinic_active(uuid,uuid,boolean) from public;
grant execute on function public.set_doctor_clinic_active(uuid,uuid,boolean) to authenticated;

create function public.remove_schedule(p_schedule uuid) returns void
language plpgsql security definer set search_path=public as $$
declare v schedules%rowtype; v_zone text;
begin
  select * into v from schedules where id=p_schedule for update;
  if not found then raise exception 'Schedule not found'; end if;
  if not public.is_clinic_admin(v.clinic_id) then raise exception 'Forbidden' using errcode='42501'; end if;
  select time_zone into v_zone from clinics where id=v.clinic_id for update;
  if exists(select 1 from appointments a where a.clinic_id=v.clinic_id and a.doctor_id=v.doctor_id and a.status='booked' and a.ends_at>now()
    and extract(dow from (a.starts_at at time zone v_zone))::integer=v.weekday
    and (a.starts_at at time zone v_zone)::time>=v.start_local
    and (a.starts_at at time zone v_zone)::time<v.end_local) then
    raise exception 'Move or cancel future bookings before removing these hours';
  end if;
  delete from schedules where id=p_schedule;
  insert into audit_events(actor_id,clinic_id,entity,entity_id,action) values(auth.uid(),v.clinic_id,'schedule',p_schedule,'removed');
end $$;
revoke all on function public.remove_schedule(uuid) from public;
grant execute on function public.remove_schedule(uuid) to authenticated;

-- Direct relationships let PostgREST embed clinic and doctor summaries in appointment reads.
-- The composite foreign key above still enforces that the doctor belongs to that clinic.
alter table public.appointments add constraint appointments_clinic_id_fkey foreign key (clinic_id) references public.clinics(id);
alter table public.appointments add constraint appointments_doctor_id_fkey foreign key (doctor_id) references public.doctors(id);
