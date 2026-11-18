-- Fictional demonstration data only. Never use for real patient information.
insert into public.specialties(name) values ('Family Medicine'),('Dermatology'),('Pediatrics'),('Cardiology') on conflict do nothing;
insert into public.clinics(id,name,description,address,city,phone,time_zone) values
('11111111-1111-4111-8111-111111111111','Willow Health Clinic','Everyday family care.','14 Garden Road','Bengaluru','+91 80000 00001','Asia/Kolkata'),
('22222222-2222-4222-8222-222222222222','Harbor Care Centre','Care for all ages.','28 Lake Avenue','Mumbai','+91 80000 00002','Asia/Kolkata') on conflict do nothing;
insert into public.doctors(id,display_name,bio) values
('33333333-3333-4333-8333-333333333333','Dr. Mira Shah','Family physician with a focus on preventive care.'),
('44444444-4444-4444-8444-444444444444','Dr. Arjun Rao','Consultant dermatologist.'),
('55555555-5555-4555-8555-555555555555','Dr. Leena Menon','Pediatrician caring for children and families.') on conflict do nothing;
insert into public.doctor_specialties(doctor_id,specialty_id)
select '33333333-3333-4333-8333-333333333333',id from public.specialties where name='Family Medicine' on conflict do nothing;
insert into public.doctor_specialties(doctor_id,specialty_id)
select '44444444-4444-4444-8444-444444444444',id from public.specialties where name='Dermatology' on conflict do nothing;
insert into public.doctor_specialties(doctor_id,specialty_id)
select '55555555-5555-4555-8555-555555555555',id from public.specialties where name='Pediatrics' on conflict do nothing;
insert into public.doctor_clinics(doctor_id,clinic_id,consultation_minutes) values
('33333333-3333-4333-8333-333333333333','11111111-1111-4111-8111-111111111111',30),
('44444444-4444-4444-8444-444444444444','11111111-1111-4111-8111-111111111111',20),
('55555555-5555-4555-8555-555555555555','22222222-2222-4222-8222-222222222222',30) on conflict do nothing;
insert into public.schedules(doctor_id,clinic_id,weekday,start_local,end_local)
select dc.doctor_id,dc.clinic_id,w.weekday,'09:00'::time,'17:00'::time
from public.doctor_clinics dc cross join (values (1),(2),(3),(4),(5)) as w(weekday)
where not exists(select 1 from public.schedules s where s.doctor_id=dc.doctor_id and s.clinic_id=dc.clinic_id and s.weekday=w.weekday);
