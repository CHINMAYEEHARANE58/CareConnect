create extension if not exists btree_gist with schema extensions;
create extension if not exists pgcrypto with schema extensions;

create type public.appointment_state as enum ('booked','completed','no_show','cancelled');
create type public.member_role as enum ('clinic_admin','doctor');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text,
  notification_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.platform_administrators (
  user_id uuid primary key references auth.users(id) on delete cascade
);
create table public.clinics (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 120),
  description text not null default '',
  address text not null,
  city text not null,
  phone text,
  email text,
  time_zone text not null,
  booking_cutoff_minutes integer not null default 60 check (booking_cutoff_minutes >= 0),
  cancellation_cutoff_minutes integer not null default 120 check (cancellation_cutoff_minutes >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint valid_clinic_zone check (length(time_zone) between 3 and 80)
);
create table public.specialties (
  id bigint generated always as identity primary key,
  name text not null unique
);
create table public.doctors (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid unique references public.profiles(id) on delete set null,
  display_name text not null,
  bio text not null default '',
  active boolean not null default true
);
create table public.doctor_specialties (
  doctor_id uuid not null references public.doctors(id) on delete cascade,
  specialty_id bigint not null references public.specialties(id) on delete cascade,
  primary key (doctor_id, specialty_id)
);
create table public.clinic_memberships (
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.member_role not null,
  primary key (clinic_id, user_id, role)
);
create table public.doctor_clinics (
  doctor_id uuid not null references public.doctors(id) on delete cascade,
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  consultation_minutes integer not null default 30 check (consultation_minutes between 10 and 240),
  active boolean not null default true,
  primary key (doctor_id, clinic_id)
);
create table public.schedules (
  id uuid primary key default gen_random_uuid(),
  doctor_id uuid not null,
  clinic_id uuid not null,
  weekday integer not null check (weekday between 0 and 6),
  start_local time not null,
  end_local time not null,
  valid_from date not null default current_date,
  valid_until date,
  check (start_local < end_local),
  check (valid_until is null or valid_until >= valid_from),
  foreign key (doctor_id, clinic_id) references public.doctor_clinics(doctor_id, clinic_id) on delete cascade
);
create table public.schedule_exceptions (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  doctor_id uuid references public.doctors(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  reason text not null default '',
  check (starts_at < ends_at)
);
create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.profiles(id),
  doctor_id uuid not null,
  clinic_id uuid not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  during tstzrange generated always as (tstzrange(starts_at, ends_at, '[)')) stored,
  status public.appointment_state not null default 'booked',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (starts_at < ends_at),
  foreign key (doctor_id, clinic_id) references public.doctor_clinics(doctor_id, clinic_id),
  constraint no_doctor_overlap exclude using gist (doctor_id with =, during with &&) where (status = 'booked'),
  constraint no_patient_overlap exclude using gist (patient_id with =, during with &&) where (status = 'booked')
);
create index appointments_patient_start_idx on public.appointments(patient_id, starts_at desc);
create index appointments_doctor_start_idx on public.appointments(doctor_id, starts_at);
create table public.appointment_status_history (
  id bigint generated always as identity primary key,
  appointment_id uuid not null references public.appointments(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  old_status public.appointment_state,
  new_status public.appointment_state not null,
  old_starts_at timestamptz,
  new_starts_at timestamptz,
  occurred_at timestamptz not null default now()
);
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  appointment_id uuid references public.appointments(id) on delete cascade,
  kind text not null check (kind in ('confirmation','cancellation','reschedule','reminder')),
  title text not null,
  body text not null,
  deliver_after timestamptz not null default now(),
  delivered_at timestamptz,
  attempts integer not null default 0,
  last_error text,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  unique (appointment_id, user_id, kind, deliver_after)
);
create index notifications_due_idx on public.notifications(deliver_after) where delivered_at is null;
create table public.audit_events (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id) on delete set null,
  clinic_id uuid references public.clinics(id) on delete set null,
  entity text not null,
  entity_id uuid not null,
  action text not null,
  occurred_at timestamptz not null default now()
);

create function public.is_platform_admin() returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from platform_administrators where user_id = auth.uid())
$$;
create function public.is_clinic_admin(p_clinic uuid) returns boolean language sql stable security definer set search_path = public as $$
  select public.is_platform_admin() or exists(select 1 from clinic_memberships where clinic_id = p_clinic and user_id = auth.uid() and role = 'clinic_admin')
$$;
create function public.is_doctor(p_doctor uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from doctors where id = p_doctor and profile_id = auth.uid())
$$;
create function public.is_verified() returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from auth.users where id = auth.uid() and email_confirmed_at is not null)
$$;
create function public.on_auth_user() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, full_name) values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''));
  return new;
end $$;
create trigger create_profile after insert on auth.users for each row execute function public.on_auth_user();

create function public.register_clinic(p_name text, p_address text, p_city text, p_time_zone text, p_phone text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_verified() then raise exception 'Verified account required' using errcode = '42501'; end if;
  if not exists (select 1 from pg_timezone_names where name = p_time_zone) then raise exception 'Invalid time zone'; end if;
  insert into clinics(name,address,city,time_zone,phone) values (p_name,p_address,p_city,p_time_zone,p_phone) returning id into v_id;
  insert into clinic_memberships(clinic_id,user_id,role) values(v_id,auth.uid(),'clinic_admin');
  insert into audit_events(actor_id,clinic_id,entity,entity_id,action) values(auth.uid(),v_id,'clinic',v_id,'created');
  return v_id;
end $$;
create function public.add_clinic_doctor(p_clinic uuid,p_name text,p_email text,p_specialty_id bigint,p_minutes integer default 30)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_doctor uuid; v_user uuid;
begin
  if not public.is_clinic_admin(p_clinic) then raise exception 'Forbidden' using errcode='42501'; end if;
  if p_minutes not between 10 and 240 then raise exception 'Invalid duration'; end if;
  select id into v_user from auth.users where lower(email)=lower(p_email) and email_confirmed_at is not null;
  if v_user is null then raise exception 'Doctor must first register and verify email'; end if;
  select id into v_doctor from doctors where profile_id=v_user;
  if v_doctor is null then insert into doctors(profile_id,display_name) values(v_user,p_name) returning id into v_doctor; end if;
  insert into doctor_clinics(doctor_id,clinic_id,consultation_minutes) values(v_doctor,p_clinic,p_minutes) on conflict (doctor_id,clinic_id) do update set consultation_minutes=excluded.consultation_minutes,active=true;
  insert into clinic_memberships(clinic_id,user_id,role) values(p_clinic,v_user,'doctor') on conflict do nothing;
  insert into doctor_specialties(doctor_id,specialty_id) values(v_doctor,p_specialty_id) on conflict do nothing;
  insert into audit_events(actor_id,clinic_id,entity,entity_id,action) values(auth.uid(),p_clinic,'doctor',v_doctor,'added');
  return v_doctor;
end $$;
create function public.add_schedule(p_clinic uuid,p_doctor uuid,p_weekday integer,p_start time,p_end time)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_clinic_admin(p_clinic) then raise exception 'Forbidden' using errcode='42501'; end if;
  if not exists(select 1 from doctor_clinics where clinic_id=p_clinic and doctor_id=p_doctor and active) then raise exception 'Doctor not at clinic'; end if;
  insert into schedules(doctor_id,clinic_id,weekday,start_local,end_local) values(p_doctor,p_clinic,p_weekday,p_start,p_end) returning id into v_id;
  return v_id;
end $$;
create function public.add_unavailability(p_clinic uuid,p_doctor uuid,p_start timestamptz,p_end timestamptz,p_reason text default '')
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not (public.is_clinic_admin(p_clinic) or (public.is_doctor(p_doctor) and exists(select 1 from doctor_clinics where clinic_id=p_clinic and doctor_id=p_doctor))) then raise exception 'Forbidden' using errcode='42501'; end if;
  if p_end <= p_start then raise exception 'Invalid interval'; end if;
  insert into schedule_exceptions(clinic_id,doctor_id,starts_at,ends_at,reason) values(p_clinic,p_doctor,p_start,p_end,p_reason) returning id into v_id;
  return v_id;
end $$;

create function public.available_slots(p_clinic uuid,p_doctor uuid,p_day date)
returns table(starts_at timestamptz,ends_at timestamptz) language sql stable security definer set search_path = public as $$
  with clinic as (
    select c.time_zone,c.booking_cutoff_minutes,dc.consultation_minutes
    from clinics c join doctor_clinics dc on dc.clinic_id=c.id
    join doctors d on d.id=dc.doctor_id
    where c.id=p_clinic and dc.doctor_id=p_doctor and c.active and dc.active and d.active
  ), candidates as (
    select g.starts_at, g.starts_at + make_interval(mins=>clinic.consultation_minutes) as ends_at
    from clinic join schedules s on s.clinic_id=p_clinic and s.doctor_id=p_doctor
    cross join lateral generate_series(
      (p_day+s.start_local) at time zone clinic.time_zone,
      (p_day+s.end_local) at time zone clinic.time_zone - make_interval(mins=>clinic.consultation_minutes),
      make_interval(mins=>clinic.consultation_minutes)) as g(starts_at)
    where s.weekday = extract(dow from p_day)::integer and p_day>=s.valid_from and (s.valid_until is null or p_day<=s.valid_until)
      and (g.starts_at at time zone clinic.time_zone)::date=p_day
      and (g.starts_at at time zone clinic.time_zone)::time>=s.start_local
      and ((g.starts_at + make_interval(mins=>clinic.consultation_minutes)) at time zone clinic.time_zone)::time<=s.end_local
      and g.starts_at >= now()+make_interval(mins=>clinic.booking_cutoff_minutes)
  )
  select distinct candidates.starts_at,candidates.ends_at from candidates
  where not exists (select 1 from schedule_exceptions e where e.clinic_id=p_clinic and (e.doctor_id is null or e.doctor_id=p_doctor) and tstzrange(e.starts_at,e.ends_at,'[)') && tstzrange(candidates.starts_at,candidates.ends_at,'[)'))
    and not exists (select 1 from appointments a where a.doctor_id=p_doctor and a.status='booked' and a.during && tstzrange(candidates.starts_at,candidates.ends_at,'[)'))
  order by starts_at;
$$;
create function public.book_appointment(p_clinic uuid,p_doctor uuid,p_start timestamptz)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_end timestamptz; v_id uuid; v_zone text;
begin
  if not public.is_verified() then raise exception 'Verified account required' using errcode='42501'; end if;
  select time_zone into v_zone from clinics where id=p_clinic and active for share;
  if v_zone is null then raise exception 'Clinic unavailable'; end if;
  select s.ends_at into v_end from public.available_slots(p_clinic,p_doctor,(p_start at time zone v_zone)::date) s where s.starts_at=p_start;
  if v_end is null then raise exception 'Slot unavailable' using errcode='P0001'; end if;
  insert into appointments(patient_id,doctor_id,clinic_id,starts_at,ends_at) values(auth.uid(),p_doctor,p_clinic,p_start,v_end) returning id into v_id;
  return v_id;
exception when exclusion_violation then
  raise exception 'Slot unavailable' using errcode='P0001';
end $$;
create function public.cancel_appointment(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v appointments%rowtype; v_cutoff integer;
begin
  select * into v from appointments where id=p_id for update;
  if not found then raise exception 'Appointment not found'; end if;
  if v.status <> 'booked' then raise exception 'Appointment already closed'; end if;
  select cancellation_cutoff_minutes into v_cutoff from clinics where id=v.clinic_id;
  if not (v.patient_id=auth.uid() or public.is_clinic_admin(v.clinic_id)) then raise exception 'Forbidden' using errcode='42501'; end if;
  if v.patient_id=auth.uid() and not public.is_clinic_admin(v.clinic_id) and v.starts_at < now()+make_interval(mins=>v_cutoff) then raise exception 'Cancellation cutoff passed'; end if;
  update appointments set status='cancelled',updated_at=now() where id=p_id;
end $$;
create function public.reschedule_appointment(p_id uuid,p_start timestamptz)
returns void language plpgsql security definer set search_path = public as $$
declare v appointments%rowtype; v_zone text; v_end timestamptz; v_cutoff integer;
begin
  select * into v from appointments where id=p_id for update;
  if not found or v.status<>'booked' then raise exception 'Appointment unavailable'; end if;
  if not (v.patient_id=auth.uid() or public.is_clinic_admin(v.clinic_id)) then raise exception 'Forbidden' using errcode='42501'; end if;
  select time_zone,cancellation_cutoff_minutes into v_zone,v_cutoff from clinics where id=v.clinic_id for share;
  if v.patient_id=auth.uid() and not public.is_clinic_admin(v.clinic_id) and v.starts_at < now()+make_interval(mins=>v_cutoff) then raise exception 'Reschedule cutoff passed'; end if;
  select ends_at into v_end from public.available_slots(v.clinic_id,v.doctor_id,(p_start at time zone v_zone)::date) where starts_at=p_start;
  if v_end is null then raise exception 'Slot unavailable'; end if;
  update appointments set starts_at=p_start,ends_at=v_end,updated_at=now() where id=p_id;
exception when exclusion_violation then raise exception 'Slot unavailable' using errcode='P0001';
end $$;
create function public.finish_appointment(p_id uuid,p_state public.appointment_state)
returns void language plpgsql security definer set search_path = public as $$
declare v appointments%rowtype;
begin
  if p_state not in ('completed','no_show') then raise exception 'Invalid final status'; end if;
  select * into v from appointments where id=p_id for update;
  if not found or v.status<>'booked' then raise exception 'Appointment unavailable'; end if;
  if not (public.is_doctor(v.doctor_id) or public.is_clinic_admin(v.clinic_id)) then raise exception 'Forbidden' using errcode='42501'; end if;
  if v.starts_at > now() then raise exception 'Appointment has not started'; end if;
  update appointments set status=p_state,updated_at=now() where id=p_id;
end $$;
create function public.on_appointment_change() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' then
    insert into appointment_status_history(appointment_id,actor_id,new_status,new_starts_at) values(new.id,auth.uid(),new.status,new.starts_at);
    insert into notifications(user_id,appointment_id,kind,title,body) values(new.patient_id,new.id,'confirmation','Booking confirmed','Your appointment is confirmed.');
    insert into notifications(user_id,appointment_id,kind,title,body,deliver_after) values(new.patient_id,new.id,'reminder','Appointment reminder','You have an upcoming appointment.',greatest(now(),new.starts_at-interval '24 hours'));
  elsif new.status is distinct from old.status or new.starts_at is distinct from old.starts_at then
    insert into appointment_status_history(appointment_id,actor_id,old_status,new_status,old_starts_at,new_starts_at) values(new.id,auth.uid(),old.status,new.status,old.starts_at,new.starts_at);
    delete from notifications where appointment_id=new.id and kind='reminder' and delivered_at is null;
    if new.status='cancelled' then
      insert into notifications(user_id,appointment_id,kind,title,body) values(new.patient_id,new.id,'cancellation','Appointment cancelled','Your appointment was cancelled.');
    elsif new.starts_at is distinct from old.starts_at then
      insert into notifications(user_id,appointment_id,kind,title,body) values(new.patient_id,new.id,'reschedule','Appointment rescheduled','Your appointment time has changed.');
      insert into notifications(user_id,appointment_id,kind,title,body,deliver_after) values(new.patient_id,new.id,'reminder','Appointment reminder','You have an upcoming appointment.',greatest(now(),new.starts_at-interval '24 hours'));
    end if;
  end if;
  insert into audit_events(actor_id,clinic_id,entity,entity_id,action) values(auth.uid(),new.clinic_id,'appointment',new.id,case when tg_op='INSERT' then 'booked' when new.starts_at is distinct from old.starts_at then 'rescheduled' else new.status::text end);
  return new;
end $$;
create trigger appointment_events after insert or update of status,starts_at on appointments for each row execute function public.on_appointment_change();

alter table public.profiles enable row level security;
alter table public.platform_administrators enable row level security;
alter table public.clinics enable row level security;
alter table public.specialties enable row level security;
alter table public.doctors enable row level security;
alter table public.doctor_specialties enable row level security;
alter table public.clinic_memberships enable row level security;
alter table public.doctor_clinics enable row level security;
alter table public.schedules enable row level security;
alter table public.schedule_exceptions enable row level security;
alter table public.appointments enable row level security;
alter table public.appointment_status_history enable row level security;
alter table public.notifications enable row level security;
alter table public.audit_events enable row level security;
create policy profiles_self_select on profiles for select to authenticated using (id=auth.uid() or public.is_platform_admin());
create policy profiles_self_update on profiles for update to authenticated using (id=auth.uid()) with check (id=auth.uid());
create policy clinics_public_read on clinics for select to anon,authenticated using (active or public.is_clinic_admin(id));
create policy clinics_admin_update on clinics for update to authenticated using (public.is_clinic_admin(id)) with check (public.is_clinic_admin(id));
create policy specialties_read on specialties for select to anon,authenticated using (true);
create policy doctors_read on doctors for select to anon,authenticated using (active or public.is_doctor(id));
create policy doctor_specialties_read on doctor_specialties for select to anon,authenticated using (true);
create policy memberships_own_or_admin on clinic_memberships for select to authenticated using (user_id=auth.uid() or public.is_clinic_admin(clinic_id));
create policy doctor_clinics_read on doctor_clinics for select to anon,authenticated using (active or public.is_clinic_admin(clinic_id));
create policy schedules_read on schedules for select to anon,authenticated using (true);
create policy exceptions_read on schedule_exceptions for select to authenticated using (public.is_clinic_admin(clinic_id) or (doctor_id is not null and public.is_doctor(doctor_id)));
create policy appointments_own_staff on appointments for select to authenticated using (patient_id=auth.uid() or public.is_doctor(doctor_id) or public.is_clinic_admin(clinic_id));
create policy history_own_staff on appointment_status_history for select to authenticated using (exists(select 1 from appointments a where a.id=appointment_id and (a.patient_id=auth.uid() or public.is_doctor(a.doctor_id) or public.is_clinic_admin(a.clinic_id))));
create policy notifications_own on notifications for select to authenticated using (user_id=auth.uid());
create policy notifications_read on notifications for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
create policy audit_admin on audit_events for select to authenticated using (public.is_clinic_admin(clinic_id));

revoke all on function public.register_clinic(text,text,text,text,text) from public;
revoke all on function public.add_clinic_doctor(uuid,text,text,bigint,integer) from public;
revoke all on function public.add_schedule(uuid,uuid,integer,time,time) from public;
revoke all on function public.add_unavailability(uuid,uuid,timestamptz,timestamptz,text) from public;
revoke all on function public.book_appointment(uuid,uuid,timestamptz) from public;
revoke all on function public.cancel_appointment(uuid) from public;
revoke all on function public.reschedule_appointment(uuid,timestamptz) from public;
revoke all on function public.finish_appointment(uuid,public.appointment_state) from public;
grant execute on function public.register_clinic(text,text,text,text,text),public.add_clinic_doctor(uuid,text,text,bigint,integer),public.add_schedule(uuid,uuid,integer,time,time),public.add_unavailability(uuid,uuid,timestamptz,timestamptz,text),public.book_appointment(uuid,uuid,timestamptz),public.cancel_appointment(uuid),public.reschedule_appointment(uuid,timestamptz),public.finish_appointment(uuid,public.appointment_state) to authenticated;
grant execute on function public.available_slots(uuid,uuid,date) to anon,authenticated;
