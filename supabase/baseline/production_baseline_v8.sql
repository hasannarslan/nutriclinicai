-- NutriClinic AI v7.0 Fresh Production Baseline
-- Generated from migrations 001-019. Run only on a NEW, empty Supabase project.
-- Existing installations must run only migration 019.


-- ============================================================================
-- 001_production_schema.sql
-- ============================================================================

-- NutriClinic AI - production authentication, roles and clinical workflow schema
-- Run this file once in a fresh Supabase project's SQL Editor.

create extension if not exists "pgcrypto";
create extension if not exists "btree_gist";

create type public.clinic_role as enum ('owner','dietitian','secretary','client');
create type public.appointment_status as enum ('pending','confirmed','completed','cancelled','no_show');
create type public.appointment_mode as enum ('in_clinic','online');
create type public.plan_status as enum ('draft','active','archived');
create type public.reward_transaction_type as enum ('earned','redeemed','adjusted','expired');

create table public.clinics (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  default_locale text not null default 'tr' check (default_locale in ('tr','en','el','ru','de')),
  timezone text not null default 'Europe/Istanbul',
  phone text,
  email text,
  created_at timestamptz not null default now()
);

insert into public.clinics (id,name,slug,default_locale,timezone)
values ('00000000-0000-0000-0000-000000000001','NutriClinic Mağusa','nutriclinic-magusa','tr','Europe/Istanbul');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  email text,
  phone text,
  preferred_locale text not null default 'tr' check (preferred_locale in ('tr','en','el','ru','de')),
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (email is not null or phone is not null)
);

create table public.clinic_memberships (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.clinic_role not null default 'client',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (clinic_id,user_id)
);

create table public.dietitian_profiles (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text default 'Diyetisyen',
  license_no text,
  bio text,
  appointment_duration_minutes int not null default 45 check (appointment_duration_minutes between 15 and 240),
  buffer_minutes int not null default 10 check (buffer_minutes between 0 and 120),
  is_bookable boolean not null default true,
  unique (clinic_id,user_id)
);

create sequence public.client_member_sequence start 1;

create table public.client_profiles (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete set null,
  member_no text not null,
  assigned_dietitian_id uuid references public.dietitian_profiles(id) on delete set null,
  full_name text not null,
  email text,
  phone text,
  birth_date date,
  gender text,
  height_cm numeric(5,2),
  target_text text,
  allergies text[] not null default '{}',
  disliked_foods text[] not null default '{}',
  medical_notes text,
  medications text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (clinic_id,member_no),
  unique (clinic_id,user_id),
  check (email is not null or phone is not null)
);

create table public.availability_rules (
  id uuid primary key default gen_random_uuid(),
  dietitian_id uuid not null references public.dietitian_profiles(id) on delete cascade,
  weekday smallint not null check (weekday between 0 and 6),
  start_time time not null,
  end_time time not null,
  is_active boolean not null default true,
  check (end_time > start_time),
  unique (dietitian_id,weekday,start_time,end_time)
);

create table public.availability_exceptions (
  id uuid primary key default gen_random_uuid(),
  dietitian_id uuid not null references public.dietitian_profiles(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  is_available boolean not null default false,
  reason text,
  check (ends_at > starts_at)
);

create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  dietitian_id uuid not null references public.dietitian_profiles(id) on delete restrict,
  client_id uuid not null references public.client_profiles(id) on delete restrict,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  mode public.appointment_mode not null default 'in_clinic',
  appointment_type text not null,
  status public.appointment_status not null default 'pending',
  public_note text,
  internal_note text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at),
  exclude using gist (
    dietitian_id with =,
    tstzrange(starts_at,ends_at,'[)') with &&
  ) where (status in ('pending','confirmed'))
);
create index appointments_clinic_starts_idx on public.appointments(clinic_id,starts_at);
create index appointments_client_starts_idx on public.appointments(client_id,starts_at);

create table public.measurements (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  recorded_by uuid references public.dietitian_profiles(id) on delete set null,
  measured_at timestamptz not null default now(),
  weight_kg numeric(6,2),
  body_fat_percent numeric(5,2),
  muscle_mass_kg numeric(6,2),
  waist_cm numeric(6,2),
  hip_cm numeric(6,2),
  neck_cm numeric(6,2),
  note text
);

create table public.meal_plans (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  dietitian_id uuid not null references public.dietitian_profiles(id) on delete restrict,
  title text not null,
  starts_on date not null,
  ends_on date not null,
  target_calories numeric(8,2),
  target_protein_g numeric(8,2),
  target_carbs_g numeric(8,2),
  target_fat_g numeric(8,2),
  target_fiber_g numeric(8,2),
  version int not null default 1,
  status public.plan_status not null default 'draft',
  dietitian_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_on >= starts_on)
);

create table public.meal_plan_items (
  id uuid primary key default gen_random_uuid(),
  meal_plan_id uuid not null references public.meal_plans(id) on delete cascade,
  day_index smallint not null default 1,
  meal_name text not null,
  sort_order smallint not null default 0,
  food_name text not null,
  portion_text text,
  calories numeric(8,2) not null default 0,
  protein_g numeric(8,2) not null default 0,
  carbs_g numeric(8,2) not null default 0,
  fat_g numeric(8,2) not null default 0,
  fiber_g numeric(8,2) not null default 0,
  alternative_tolerance_percent numeric(5,2) not null default 5
);

create table public.meal_completions (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.meal_plan_items(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  consumed_on date not null default current_date,
  consumed_at timestamptz not null default now(),
  completion_percent numeric(5,2) not null default 100 check (completion_percent between 0 and 100),
  selected_alternative jsonb,
  client_note text,
  unique (item_id,client_id,consumed_on)
);

create table public.loyalty_wallets (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  balance int not null default 0 check (balance >= 0),
  updated_at timestamptz not null default now(),
  unique (clinic_id,client_id)
);

create table public.rewards (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  name text not null,
  description text,
  points_cost int not null check (points_cost > 0),
  stock int,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.loyalty_transactions (
  id uuid primary key default gen_random_uuid(),
  wallet_id uuid not null references public.loyalty_wallets(id) on delete cascade,
  transaction_type public.reward_transaction_type not null,
  points int not null,
  reason text not null,
  reward_id uuid references public.rewards(id) on delete set null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  clinic_id uuid references public.clinics(id) on delete cascade,
  actor_user_id uuid references public.profiles(id) on delete set null,
  action text not null,
  target_type text,
  target_id text,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);

insert into public.rewards (clinic_id,name,description,points_cost,stock) values
('00000000-0000-0000-0000-000000000001','Ücretsiz vücut analizi','Bir adet ayrıntılı vücut ölçümü',2500,20),
('00000000-0000-0000-0000-000000000001','1 Aylık BodyShape','Klinik tarafından belirlenen bir aylık kullanım',5000,5),
('00000000-0000-0000-0000-000000000001','G5 Uygulama Paketi','Klinik tarafından belirlenen G5 paketi',8000,3);

-- Security-definer helpers are intentionally small and only return authorization facts.
create or replace function public.current_clinic_role(target_clinic uuid)
returns public.clinic_role
language sql stable security definer set search_path = public
as $$
  select role from public.clinic_memberships
  where clinic_id=target_clinic and user_id=auth.uid() and is_active=true
  limit 1;
$$;

create or replace function public.current_client_id(target_clinic uuid)
returns uuid
language sql stable security definer set search_path = public
as $$
  select id from public.client_profiles
  where clinic_id=target_clinic and user_id=auth.uid() and is_active=true
  limit 1;
$$;

create or replace function public.shares_clinic(target_user uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.clinic_memberships me
    join public.clinic_memberships them on them.clinic_id=me.clinic_id
    where me.user_id=auth.uid() and me.is_active=true
      and them.user_id=target_user and them.is_active=true
  );
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_clinic uuid := '00000000-0000-0000-0000-000000000001';
  v_full_name text;
  v_email text;
  v_phone text;
  v_locale text;
  v_client_id uuid;
begin
  v_email := coalesce(nullif(new.raw_user_meta_data->>'contact_email',''),new.email);
  v_phone := coalesce(nullif(new.raw_user_meta_data->>'contact_phone',''),new.phone);
  v_full_name := coalesce(nullif(new.raw_user_meta_data->>'full_name',''),split_part(coalesce(v_email,v_phone,'Danışan'),'@',1));
  v_locale := coalesce(nullif(new.raw_user_meta_data->>'preferred_locale',''),'tr');
  if v_locale not in ('tr','en','el','ru','de') then v_locale := 'tr'; end if;

  insert into public.profiles(id,full_name,email,phone,preferred_locale)
  values(new.id,v_full_name,v_email,v_phone,v_locale);

  insert into public.clinic_memberships(clinic_id,user_id,role)
  values(v_clinic,new.id,'client');

  insert into public.client_profiles(clinic_id,user_id,member_no,full_name,email,phone)
  values(
    v_clinic,new.id,
    'NCA-' || to_char(current_date,'YYYY') || '-' || lpad(nextval('public.client_member_sequence')::text,6,'0'),
    v_full_name,v_email,v_phone
  ) returning id into v_client_id;

  insert into public.loyalty_wallets(clinic_id,client_id,balance)
  values(v_clinic,v_client_id,0);

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.ensure_default_availability(p_dietitian_id uuid)
returns void
language plpgsql security definer set search_path=public
as $$
begin
  insert into public.availability_rules(dietitian_id,weekday,start_time,end_time)
  select p_dietitian_id,d,'09:00'::time,'17:00'::time
  from generate_series(1,5) d
  on conflict do nothing;
end;
$$;

create or replace function public.claim_first_owner()
returns boolean
language plpgsql security definer set search_path=public
as $$
declare
  v_clinic uuid;
  v_dietitian uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  perform pg_advisory_xact_lock(782451);
  select clinic_id into v_clinic from public.clinic_memberships where user_id=auth.uid() and is_active=true limit 1;
  if v_clinic is null then raise exception 'Clinic membership not found'; end if;
  if exists(select 1 from public.clinic_memberships where clinic_id=v_clinic and role='owner' and is_active=true) then return false; end if;
  update public.clinic_memberships set role='owner',updated_at=now() where clinic_id=v_clinic and user_id=auth.uid();
  insert into public.dietitian_profiles(clinic_id,user_id,title,is_bookable)
  values(v_clinic,auth.uid(),'Danışman Diyetisyen',true)
  on conflict(clinic_id,user_id) do update set is_bookable=true
  returning id into v_dietitian;
  perform public.ensure_default_availability(v_dietitian);
  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id)
  values(v_clinic,auth.uid(),'claim_first_owner','user',auth.uid()::text);
  return true;
end;
$$;

create or replace function public.set_member_role(p_user_id uuid,p_role public.clinic_role)
returns void
language plpgsql security definer set search_path=public
as $$
declare
  v_clinic uuid;
  v_current_role public.clinic_role;
  v_dietitian uuid;
begin
  select clinic_id into v_clinic from public.clinic_memberships
  where user_id=auth.uid() and role='owner' and is_active=true limit 1;
  if v_clinic is null then raise exception 'Only a clinic owner can change roles'; end if;

  select role into v_current_role from public.clinic_memberships
  where clinic_id=v_clinic and user_id=p_user_id and is_active=true;
  if v_current_role is null then raise exception 'User is not a member of this clinic'; end if;

  if v_current_role='owner' and p_role<>'owner' and
     (select count(*) from public.clinic_memberships where clinic_id=v_clinic and role='owner' and is_active=true)<=1
  then raise exception 'The last clinic owner cannot be demoted'; end if;

  update public.clinic_memberships set role=p_role,updated_at=now()
  where clinic_id=v_clinic and user_id=p_user_id;

  if p_role in ('owner','dietitian') then
    insert into public.dietitian_profiles(clinic_id,user_id,title,is_bookable)
    values(v_clinic,p_user_id,'Danışman Diyetisyen',true)
    on conflict(clinic_id,user_id) do update set is_bookable=true
    returning id into v_dietitian;
    perform public.ensure_default_availability(v_dietitian);
  else
    update public.dietitian_profiles set is_bookable=false where clinic_id=v_clinic and user_id=p_user_id;
  end if;

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values(v_clinic,auth.uid(),'member_role_changed','user',p_user_id::text,jsonb_build_object('old_role',v_current_role,'new_role',p_role));
end;
$$;

create or replace function public.get_client_directory()
returns table(id uuid,user_id uuid,member_no text,full_name text,email text,phone text,height_cm numeric,target_text text,created_at timestamptz)
language plpgsql stable security definer set search_path=public
as $$
declare v_clinic uuid;
begin
  select clinic_id into v_clinic from public.clinic_memberships
  where user_id=auth.uid() and is_active=true and role in ('owner','dietitian','secretary') limit 1;
  if v_clinic is null then raise exception 'Staff access required'; end if;
  return query select c.id,c.user_id,c.member_no,c.full_name,c.email,c.phone,null::numeric,null::text,c.created_at
  from public.client_profiles c where c.clinic_id=v_clinic and c.is_active=true order by c.full_name;
end;
$$;

create or replace function public.validate_appointment_slot(p_dietitian_id uuid,p_starts_at timestamptz,p_ends_at timestamptz)
returns void
language plpgsql stable security definer set search_path=public
as $$
declare
  v_timezone text;
  v_weekday int;
  v_start_time time;
  v_end_time time;
begin
  select c.timezone into v_timezone from public.dietitian_profiles d join public.clinics c on c.id=d.clinic_id where d.id=p_dietitian_id and d.is_bookable=true;
  if v_timezone is null then raise exception 'Dietitian is not available for booking'; end if;
  if p_starts_at <= now() then raise exception 'Appointment must be in the future'; end if;
  v_weekday := extract(dow from p_starts_at at time zone v_timezone)::int;
  v_start_time := (p_starts_at at time zone v_timezone)::time;
  v_end_time := (p_ends_at at time zone v_timezone)::time;
  if not exists(select 1 from public.availability_rules where dietitian_id=p_dietitian_id and weekday=v_weekday and is_active=true and start_time<=v_start_time and end_time>=v_end_time)
  then raise exception 'Selected time is outside the dietitian working hours'; end if;
  if exists(select 1 from public.availability_exceptions where dietitian_id=p_dietitian_id and is_available=false and tstzrange(starts_at,ends_at,'[)') && tstzrange(p_starts_at,p_ends_at,'[)'))
  then raise exception 'Selected time is unavailable'; end if;
end;
$$;

create or replace function public.book_appointment(
  p_dietitian_id uuid,p_starts_at timestamptz,p_appointment_type text,p_mode public.appointment_mode,p_note text default null
) returns uuid
language plpgsql security definer set search_path=public
as $$
declare
  v_clinic uuid;
  v_client uuid;
  v_duration int;
  v_end timestamptz;
  v_id uuid;
begin
  select d.clinic_id,d.appointment_duration_minutes into v_clinic,v_duration from public.dietitian_profiles d where d.id=p_dietitian_id and d.is_bookable=true;
  select id into v_client from public.client_profiles where clinic_id=v_clinic and user_id=auth.uid() and is_active=true;
  if v_client is null then raise exception 'Client profile not found'; end if;
  v_end := p_starts_at + make_interval(mins=>v_duration);
  perform public.validate_appointment_slot(p_dietitian_id,p_starts_at,v_end);
  begin
    insert into public.appointments(clinic_id,dietitian_id,client_id,starts_at,ends_at,mode,appointment_type,status,public_note,created_by)
    values(v_clinic,p_dietitian_id,v_client,p_starts_at,v_end,p_mode,p_appointment_type,'pending',p_note,auth.uid()) returning id into v_id;
  exception when exclusion_violation then raise exception 'This time slot has already been booked'; end;
  return v_id;
end;
$$;

create or replace function public.staff_book_appointment(
  p_dietitian_id uuid,p_client_id uuid,p_starts_at timestamptz,p_appointment_type text,p_mode public.appointment_mode,p_note text default null
) returns uuid
language plpgsql security definer set search_path=public
as $$
declare
  v_clinic uuid;
  v_duration int;
  v_end timestamptz;
  v_id uuid;
begin
  select clinic_id into v_clinic from public.clinic_memberships where user_id=auth.uid() and is_active=true and role in ('owner','dietitian','secretary') limit 1;
  if v_clinic is null then raise exception 'Staff access required'; end if;
  select appointment_duration_minutes into v_duration from public.dietitian_profiles where id=p_dietitian_id and clinic_id=v_clinic and is_bookable=true;
  if v_duration is null or not exists(select 1 from public.client_profiles where id=p_client_id and clinic_id=v_clinic and is_active=true) then raise exception 'Invalid dietitian or client'; end if;
  v_end := p_starts_at + make_interval(mins=>v_duration);
  perform public.validate_appointment_slot(p_dietitian_id,p_starts_at,v_end);
  begin
    insert into public.appointments(clinic_id,dietitian_id,client_id,starts_at,ends_at,mode,appointment_type,status,public_note,created_by)
    values(v_clinic,p_dietitian_id,p_client_id,p_starts_at,v_end,p_mode,p_appointment_type,'confirmed',p_note,auth.uid()) returning id into v_id;
  exception when exclusion_violation then raise exception 'This time slot has already been booked'; end;
  return v_id;
end;
$$;

create or replace function public.get_dietitian_day_slots(p_dietitian_id uuid,p_day date)
returns table(starts_at timestamptz,ends_at timestamptz,is_available boolean)
language plpgsql stable security definer set search_path=public
as $$
declare
  v_clinic uuid;
  v_timezone text;
  v_duration int;
  v_buffer int;
begin
  select d.clinic_id,c.timezone,d.appointment_duration_minutes,d.buffer_minutes
  into v_clinic,v_timezone,v_duration,v_buffer
  from public.dietitian_profiles d join public.clinics c on c.id=d.clinic_id
  where d.id=p_dietitian_id and d.is_bookable=true;
  if v_clinic is null or public.current_clinic_role(v_clinic) is null then raise exception 'Access denied'; end if;

  return query
  select slot_start,
         slot_start + make_interval(mins=>v_duration) as slot_end,
         not exists(
           select 1 from public.appointments a
           where a.dietitian_id=p_dietitian_id and a.status in ('pending','confirmed')
             and tstzrange(a.starts_at,a.ends_at,'[)') && tstzrange(slot_start,slot_start+make_interval(mins=>v_duration),'[)')
         )
         and not exists(
           select 1 from public.availability_exceptions e
           where e.dietitian_id=p_dietitian_id and e.is_available=false
             and tstzrange(e.starts_at,e.ends_at,'[)') && tstzrange(slot_start,slot_start+make_interval(mins=>v_duration),'[)')
         )
         and slot_start > now() as available
  from public.availability_rules r
  cross join lateral generate_series(
    (p_day::timestamp + r.start_time) at time zone v_timezone,
    ((p_day::timestamp + r.end_time) at time zone v_timezone) - make_interval(mins=>v_duration),
    make_interval(mins=>v_duration+v_buffer)
  ) slot_start
  where r.dietitian_id=p_dietitian_id
    and r.weekday=extract(dow from p_day)::int
    and r.is_active=true
  order by slot_start;
end;
$$;

-- Row-level security
alter table public.clinics enable row level security;
alter table public.profiles enable row level security;
alter table public.clinic_memberships enable row level security;
alter table public.dietitian_profiles enable row level security;
alter table public.client_profiles enable row level security;
alter table public.availability_rules enable row level security;
alter table public.availability_exceptions enable row level security;
alter table public.appointments enable row level security;
alter table public.measurements enable row level security;
alter table public.meal_plans enable row level security;
alter table public.meal_plan_items enable row level security;
alter table public.meal_completions enable row level security;
alter table public.loyalty_wallets enable row level security;
alter table public.rewards enable row level security;
alter table public.loyalty_transactions enable row level security;
alter table public.audit_logs enable row level security;

create policy clinics_select_members on public.clinics for select using (public.current_clinic_role(id) is not null);
create policy profiles_select_shared on public.profiles for select using (id=auth.uid() or public.shares_clinic(id));
create policy profiles_update_own on public.profiles for update using (id=auth.uid()) with check (id=auth.uid());
create policy memberships_select on public.clinic_memberships for select using (user_id=auth.uid() or public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary'));

create policy dietitians_select_members on public.dietitian_profiles for select using (public.current_clinic_role(clinic_id) is not null);
create policy dietitians_manage_clinical on public.dietitian_profiles for update using (public.current_clinic_role(clinic_id) in ('owner','dietitian')) with check (public.current_clinic_role(clinic_id) in ('owner','dietitian'));

create policy clients_select_clinical_or_self on public.client_profiles for select using (public.current_clinic_role(clinic_id) in ('owner','dietitian') or user_id=auth.uid());
create policy clients_update_clinical on public.client_profiles for update using (public.current_clinic_role(clinic_id) in ('owner','dietitian')) with check (public.current_clinic_role(clinic_id) in ('owner','dietitian'));
create policy clients_update_self_basic on public.client_profiles for update using (user_id=auth.uid()) with check (user_id=auth.uid());

create policy availability_select_members on public.availability_rules for select using (exists(select 1 from public.dietitian_profiles d where d.id=dietitian_id and public.current_clinic_role(d.clinic_id) is not null));
create policy availability_manage_clinical on public.availability_rules for all using (exists(select 1 from public.dietitian_profiles d where d.id=dietitian_id and public.current_clinic_role(d.clinic_id) in ('owner','dietitian'))) with check (exists(select 1 from public.dietitian_profiles d where d.id=dietitian_id and public.current_clinic_role(d.clinic_id) in ('owner','dietitian')));
create policy exceptions_select_members on public.availability_exceptions for select using (exists(select 1 from public.dietitian_profiles d where d.id=dietitian_id and public.current_clinic_role(d.clinic_id) is not null));
create policy exceptions_manage_clinical on public.availability_exceptions for all using (exists(select 1 from public.dietitian_profiles d where d.id=dietitian_id and public.current_clinic_role(d.clinic_id) in ('owner','dietitian'))) with check (exists(select 1 from public.dietitian_profiles d where d.id=dietitian_id and public.current_clinic_role(d.clinic_id) in ('owner','dietitian')));

create policy appointments_select on public.appointments for select using (public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary') or client_id=public.current_client_id(clinic_id));
create policy appointments_update_staff on public.appointments for update using (public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary')) with check (public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary'));

create policy measurements_select on public.measurements for select using (public.current_clinic_role(clinic_id) in ('owner','dietitian') or client_id=public.current_client_id(clinic_id));
create policy measurements_insert_clinical on public.measurements for insert with check (public.current_clinic_role(clinic_id) in ('owner','dietitian'));
create policy measurements_update_clinical on public.measurements for update using (public.current_clinic_role(clinic_id) in ('owner','dietitian')) with check (public.current_clinic_role(clinic_id) in ('owner','dietitian'));
create policy measurements_delete_clinical on public.measurements for delete using (public.current_clinic_role(clinic_id) in ('owner','dietitian'));

create policy plans_select on public.meal_plans for select using (public.current_clinic_role(clinic_id) in ('owner','dietitian') or client_id=public.current_client_id(clinic_id));
create policy plans_insert_clinical on public.meal_plans for insert with check (public.current_clinic_role(clinic_id) in ('owner','dietitian'));
create policy plans_update_clinical on public.meal_plans for update using (public.current_clinic_role(clinic_id) in ('owner','dietitian')) with check (public.current_clinic_role(clinic_id) in ('owner','dietitian'));
create policy plans_delete_clinical on public.meal_plans for delete using (public.current_clinic_role(clinic_id) in ('owner','dietitian'));

create policy items_select_parent on public.meal_plan_items for select using (exists(select 1 from public.meal_plans p where p.id=meal_plan_id and (public.current_clinic_role(p.clinic_id) in ('owner','dietitian') or p.client_id=public.current_client_id(p.clinic_id))));
create policy items_insert_clinical on public.meal_plan_items for insert with check (exists(select 1 from public.meal_plans p where p.id=meal_plan_id and public.current_clinic_role(p.clinic_id) in ('owner','dietitian')));
create policy items_update_clinical on public.meal_plan_items for update using (exists(select 1 from public.meal_plans p where p.id=meal_plan_id and public.current_clinic_role(p.clinic_id) in ('owner','dietitian'))) with check (exists(select 1 from public.meal_plans p where p.id=meal_plan_id and public.current_clinic_role(p.clinic_id) in ('owner','dietitian')));
create policy items_delete_clinical on public.meal_plan_items for delete using (exists(select 1 from public.meal_plans p where p.id=meal_plan_id and public.current_clinic_role(p.clinic_id) in ('owner','dietitian')));

create policy completions_select on public.meal_completions for select using (exists(select 1 from public.client_profiles c where c.id=client_id and (c.user_id=auth.uid() or public.current_clinic_role(c.clinic_id) in ('owner','dietitian'))));
create policy completions_insert_self on public.meal_completions for insert with check (exists(select 1 from public.client_profiles c where c.id=client_id and c.user_id=auth.uid()) and exists(select 1 from public.meal_plan_items i join public.meal_plans p on p.id=i.meal_plan_id where i.id=item_id and p.client_id=client_id));
create policy completions_delete_self on public.meal_completions for delete using (exists(select 1 from public.client_profiles c where c.id=client_id and c.user_id=auth.uid()));

create policy wallets_select on public.loyalty_wallets for select using (public.current_clinic_role(clinic_id) in ('owner','dietitian') or client_id=public.current_client_id(clinic_id));
create policy rewards_select_members on public.rewards for select using (public.current_clinic_role(clinic_id) is not null);
create policy rewards_manage_owner on public.rewards for all using (public.current_clinic_role(clinic_id)='owner') with check (public.current_clinic_role(clinic_id)='owner');
create policy transactions_select on public.loyalty_transactions for select using (exists(select 1 from public.loyalty_wallets w where w.id=wallet_id and (public.current_clinic_role(w.clinic_id) in ('owner','dietitian') or w.client_id=public.current_client_id(w.clinic_id))));
create policy audit_select_owner on public.audit_logs for select using (public.current_clinic_role(clinic_id)='owner');

revoke all on function public.claim_first_owner() from public;
revoke all on function public.set_member_role(uuid,public.clinic_role) from public;
revoke all on function public.get_client_directory() from public;
revoke all on function public.book_appointment(uuid,timestamptz,text,public.appointment_mode,text) from public;
revoke all on function public.staff_book_appointment(uuid,uuid,timestamptz,text,public.appointment_mode,text) from public;
revoke all on function public.get_dietitian_day_slots(uuid,date) from public;
grant execute on function public.claim_first_owner() to authenticated;
grant execute on function public.set_member_role(uuid,public.clinic_role) to authenticated;
grant execute on function public.get_client_directory() to authenticated;
grant execute on function public.book_appointment(uuid,timestamptz,text,public.appointment_mode,text) to authenticated;
grant execute on function public.staff_book_appointment(uuid,uuid,timestamptz,text,public.appointment_mode,text) to authenticated;
grant execute on function public.get_dietitian_day_slots(uuid,date) to authenticated;

-- Explicit API privileges. RLS policies above remain the final authorization layer.
grant usage on schema public to authenticated;
grant select on public.clinics,public.profiles,public.clinic_memberships,public.dietitian_profiles,public.client_profiles,
  public.availability_rules,public.availability_exceptions,public.appointments,public.measurements,
  public.meal_plans,public.meal_plan_items,public.meal_completions,public.loyalty_wallets,
  public.rewards,public.loyalty_transactions,public.audit_logs to authenticated;
grant update on public.profiles,public.client_profiles,public.dietitian_profiles,public.appointments,
  public.measurements,public.meal_plans,public.meal_plan_items to authenticated;
grant insert on public.measurements,public.meal_plans,public.meal_plan_items,public.meal_completions to authenticated;
grant delete on public.measurements,public.meal_plans,public.meal_plan_items,public.meal_completions to authenticated;

-- ============================================================================
-- 002_schedule_settings_upgrade.sql
-- ============================================================================

-- NutriClinic AI v2 upgrade
-- Adds richer settings, weekly/daily schedule management, and positive daily availability.
-- Safe to run once after 001_production_schema.sql on an existing project.

alter table public.clinics add column if not exists address text;
alter table public.clinics add column if not exists website text;
alter table public.clinics add column if not exists booking_horizon_days int not null default 60;
alter table public.clinics add column if not exists minimum_booking_notice_hours int not null default 2;
alter table public.clinics add column if not exists cancellation_notice_hours int not null default 12;
alter table public.clinics add column if not exists allow_client_cancellation boolean not null default true;
alter table public.clinics add column if not exists allow_online_booking boolean not null default true;
alter table public.profiles add column if not exists notification_preferences jsonb not null default '{"email_notifications":true,"appointment_reminders":true,"meal_reminders":true,"weekly_summary":true}'::jsonb;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='clinics_booking_horizon_days_check') then
    alter table public.clinics add constraint clinics_booking_horizon_days_check check (booking_horizon_days between 1 and 365);
  end if;
  if not exists (select 1 from pg_constraint where conname='clinics_minimum_booking_notice_check') then
    alter table public.clinics add constraint clinics_minimum_booking_notice_check check (minimum_booking_notice_hours between 0 and 168);
  end if;
  if not exists (select 1 from pg_constraint where conname='clinics_cancellation_notice_check') then
    alter table public.clinics add constraint clinics_cancellation_notice_check check (cancellation_notice_hours between 0 and 168);
  end if;
end $$;

drop policy if exists clinics_update_owner on public.clinics;
create policy clinics_update_owner on public.clinics
for update using (public.current_clinic_role(id)='owner')
with check (public.current_clinic_role(id)='owner');

create or replace function public.validate_appointment_slot(p_dietitian_id uuid,p_starts_at timestamptz,p_ends_at timestamptz)
returns void
language plpgsql stable security definer set search_path=public
as $$
declare
  v_timezone text;
  v_weekday int;
  v_start_time time;
  v_end_time time;
  v_horizon int;
  v_min_notice int;
  v_local_date date;
  v_in_weekly boolean;
  v_in_daily_extra boolean;
begin
  select c.timezone,c.booking_horizon_days,c.minimum_booking_notice_hours
  into v_timezone,v_horizon,v_min_notice
  from public.dietitian_profiles d
  join public.clinics c on c.id=d.clinic_id
  where d.id=p_dietitian_id and d.is_bookable=true;

  if v_timezone is null then raise exception 'Dietitian is not available for booking'; end if;
  if p_starts_at < now()+make_interval(hours=>v_min_notice) then raise exception 'Selected time is too close to the current time'; end if;

  v_local_date := (p_starts_at at time zone v_timezone)::date;
  if v_local_date > ((now() at time zone v_timezone)::date + v_horizon) then
    raise exception 'Selected date is outside the booking horizon';
  end if;

  v_weekday := extract(dow from p_starts_at at time zone v_timezone)::int;
  v_start_time := (p_starts_at at time zone v_timezone)::time;
  v_end_time := (p_ends_at at time zone v_timezone)::time;

  select exists(
    select 1 from public.availability_rules
    where dietitian_id=p_dietitian_id and weekday=v_weekday and is_active=true
      and start_time<=v_start_time and end_time>=v_end_time
  ) into v_in_weekly;

  select exists(
    select 1 from public.availability_exceptions
    where dietitian_id=p_dietitian_id and is_available=true
      and starts_at<=p_starts_at and ends_at>=p_ends_at
  ) into v_in_daily_extra;

  if not v_in_weekly and not v_in_daily_extra then
    raise exception 'Selected time is outside the dietitian working hours';
  end if;

  if exists(
    select 1 from public.availability_exceptions
    where dietitian_id=p_dietitian_id and is_available=false
      and tstzrange(starts_at,ends_at,'[)') && tstzrange(p_starts_at,p_ends_at,'[)')
  ) then
    raise exception 'Selected time is unavailable';
  end if;
end;
$$;

create or replace function public.get_dietitian_day_slots(p_dietitian_id uuid,p_day date)
returns table(starts_at timestamptz,ends_at timestamptz,is_available boolean)
language plpgsql stable security definer set search_path=public
as $$
declare
  v_clinic uuid;
  v_timezone text;
  v_duration int;
  v_buffer int;
  v_horizon int;
  v_min_notice int;
begin
  select d.clinic_id,c.timezone,d.appointment_duration_minutes,d.buffer_minutes,
         c.booking_horizon_days,c.minimum_booking_notice_hours
  into v_clinic,v_timezone,v_duration,v_buffer,v_horizon,v_min_notice
  from public.dietitian_profiles d join public.clinics c on c.id=d.clinic_id
  where d.id=p_dietitian_id and d.is_bookable=true;

  if v_clinic is null or public.current_clinic_role(v_clinic) is null then raise exception 'Access denied'; end if;
  if p_day > ((now() at time zone v_timezone)::date + v_horizon) then return; end if;

  return query
  with ranges as (
    select
      (p_day::timestamp + r.start_time) at time zone v_timezone as range_start,
      (p_day::timestamp + r.end_time) at time zone v_timezone as range_end
    from public.availability_rules r
    where r.dietitian_id=p_dietitian_id
      and r.weekday=extract(dow from p_day)::int
      and r.is_active=true

    union all

    select e.starts_at,e.ends_at
    from public.availability_exceptions e
    where e.dietitian_id=p_dietitian_id
      and e.is_available=true
      and (e.starts_at at time zone v_timezone)::date=p_day
  ), generated as (
    select generate_series(
      range_start,
      range_end-make_interval(mins=>v_duration),
      make_interval(mins=>v_duration+v_buffer)
    ) as slot_start
    from ranges
    where range_end-range_start>=make_interval(mins=>v_duration)
  ), unique_slots as (
    select distinct slot_start from generated
  )
  select
    u.slot_start,
    u.slot_start+make_interval(mins=>v_duration) as slot_end,
    not exists(
      select 1 from public.appointments a
      where a.dietitian_id=p_dietitian_id and a.status in ('pending','confirmed')
        and tstzrange(a.starts_at,a.ends_at,'[)') && tstzrange(u.slot_start,u.slot_start+make_interval(mins=>v_duration),'[)')
    )
    and not exists(
      select 1 from public.availability_exceptions e
      where e.dietitian_id=p_dietitian_id and e.is_available=false
        and tstzrange(e.starts_at,e.ends_at,'[)') && tstzrange(u.slot_start,u.slot_start+make_interval(mins=>v_duration),'[)')
    )
    and u.slot_start>=now()+make_interval(hours=>v_min_notice) as available
  from unique_slots u
  order by u.slot_start;
end;
$$;

-- API table privileges required by the new screens. RLS remains authoritative.
grant update on public.clinics to authenticated;
grant insert,update,delete on public.availability_rules,public.availability_exceptions to authenticated;

-- ============================================================================
-- 003_role_client_visibility_fix.sql
-- ============================================================================

-- NutriClinic AI v2.1
-- Registered users have one active clinic role. Only users whose active role is
-- "client" may appear as active danışan records. Historical clinical data is
-- preserved by deactivating, rather than deleting, the linked client profile.

begin;

create or replace function public.sync_client_profile_with_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.client_profiles
  set
    is_active = (new.is_active = true and new.role = 'client'),
    updated_at = now()
  where clinic_id = new.clinic_id
    and user_id = new.user_id;

  return new;
end;
$$;

drop trigger if exists sync_client_profile_role_state on public.clinic_memberships;
create trigger sync_client_profile_role_state
after insert or update of role, is_active on public.clinic_memberships
for each row
execute function public.sync_client_profile_with_membership();

-- Correct existing records, including the first account that claimed ownership.
-- Clients created manually by staff can have user_id = null and remain active.
update public.client_profiles c
set
  is_active = exists (
    select 1
    from public.clinic_memberships m
    where m.clinic_id = c.clinic_id
      and m.user_id = c.user_id
      and m.role = 'client'
      and m.is_active = true
  ),
  updated_at = now()
where c.user_id is not null;

create or replace function public.current_client_id(target_clinic uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select c.id
  from public.client_profiles c
  join public.clinic_memberships m
    on m.clinic_id = c.clinic_id
   and m.user_id = c.user_id
  where c.clinic_id = target_clinic
    and c.user_id = auth.uid()
    and c.is_active = true
    and m.role = 'client'
    and m.is_active = true
  limit 1;
$$;

create or replace function public.get_client_directory()
returns table(
  id uuid,
  user_id uuid,
  member_no text,
  full_name text,
  email text,
  phone text,
  height_cm numeric,
  target_text text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_clinic uuid;
begin
  select clinic_id into v_clinic
  from public.clinic_memberships
  where user_id = auth.uid()
    and is_active = true
    and role in ('owner','dietitian','secretary')
  limit 1;

  if v_clinic is null then
    raise exception 'Staff access required';
  end if;

  return query
  select
    c.id,
    c.user_id,
    c.member_no,
    c.full_name,
    c.email,
    c.phone,
    null::numeric,
    null::text,
    c.created_at
  from public.client_profiles c
  left join public.clinic_memberships m
    on m.clinic_id = c.clinic_id
   and m.user_id = c.user_id
  where c.clinic_id = v_clinic
    and c.is_active = true
    and (
      c.user_id is null
      or (m.role = 'client' and m.is_active = true)
    )
  order by c.full_name;
end;
$$;

-- A staff member's dormant historical client profile must not grant self-service
-- danışan access through the public API.
drop policy if exists clients_select_clinical_or_self on public.client_profiles;
create policy clients_select_clinical_or_self
on public.client_profiles
for select
using (
  public.current_clinic_role(clinic_id) in ('owner','dietitian')
  or (
    user_id = auth.uid()
    and is_active = true
    and public.current_clinic_role(clinic_id) = 'client'
  )
);

drop policy if exists clients_update_self_basic on public.client_profiles;
create policy clients_update_self_basic
on public.client_profiles
for update
using (
  user_id = auth.uid()
  and is_active = true
  and public.current_clinic_role(clinic_id) = 'client'
)
with check (
  user_id = auth.uid()
  and is_active = true
  and public.current_clinic_role(clinic_id) = 'client'
);

grant execute on function public.current_client_id(uuid) to authenticated;
grant execute on function public.get_client_directory() to authenticated;

commit;

-- ============================================================================
-- 004_booking_menu_loyalty_upgrade.sql
-- ============================================================================

-- NutriClinic AI v2.2
-- Fixes staff appointment creation after role promotion and adds owner-managed
-- reward catalogue / auditable stock adjustments.
-- Run once after migrations 001, 002 and 003.

begin;

-- One appointment endpoint decides authorization from the current database role.
-- This prevents a promoted owner/dietitian account from accidentally being treated
-- as a client by stale browser state.
create or replace function public.create_appointment_v2(
  p_dietitian_id uuid,
  p_client_id uuid,
  p_starts_at timestamptz,
  p_appointment_type text,
  p_mode public.appointment_mode,
  p_note text default null
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_client uuid;
  v_duration int;
  v_end timestamptz;
  v_id uuid;
  v_status public.appointment_status;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select m.clinic_id,m.role
  into v_clinic,v_role
  from public.clinic_memberships m
  where m.user_id=auth.uid() and m.is_active=true
  limit 1;

  if v_clinic is null then
    raise exception 'Active clinic membership not found';
  end if;

  select d.appointment_duration_minutes
  into v_duration
  from public.dietitian_profiles d
  where d.id=p_dietitian_id
    and d.clinic_id=v_clinic
    and d.is_bookable=true;

  if v_duration is null then
    raise exception 'Invalid or unavailable dietitian';
  end if;

  if v_role in ('owner','dietitian','secretary') then
    if p_client_id is null then
      raise exception 'Randevu oluşturmak için aktif bir danışan seçin';
    end if;

    select c.id into v_client
    from public.client_profiles c
    left join public.clinic_memberships cm
      on cm.clinic_id=c.clinic_id and cm.user_id=c.user_id
    where c.id=p_client_id
      and c.clinic_id=v_clinic
      and c.is_active=true
      and (c.user_id is null or (cm.role='client' and cm.is_active=true))
    limit 1;

    if v_client is null then
      raise exception 'Seçilen danışan aktif değil veya danışan rolünde değil';
    end if;
    v_status := 'confirmed';
  elsif v_role='client' then
    select c.id into v_client
    from public.client_profiles c
    where c.clinic_id=v_clinic
      and c.user_id=auth.uid()
      and c.is_active=true
    limit 1;

    if v_client is null then
      raise exception 'Aktif danışan profiliniz bulunamadı';
    end if;
    v_status := 'pending';
  else
    raise exception 'Randevu oluşturma yetkiniz bulunmuyor';
  end if;

  v_end := p_starts_at + make_interval(mins=>v_duration);
  perform public.validate_appointment_slot(p_dietitian_id,p_starts_at,v_end);

  begin
    insert into public.appointments(
      clinic_id,dietitian_id,client_id,starts_at,ends_at,mode,
      appointment_type,status,public_note,created_by
    ) values(
      v_clinic,p_dietitian_id,v_client,p_starts_at,v_end,p_mode,
      p_appointment_type,v_status,p_note,auth.uid()
    ) returning id into v_id;
  exception when exclusion_violation then
    raise exception 'Bu randevu saati başka bir kullanıcı tarafından alındı';
  end;

  return v_id;
end;
$$;

revoke all on function public.create_appointment_v2(uuid,uuid,timestamptz,text,public.appointment_mode,text) from public;
grant execute on function public.create_appointment_v2(uuid,uuid,timestamptz,text,public.appointment_mode,text) to authenticated;

-- Auditable reward stock inventory.
do $$
begin
  if not exists (select 1 from pg_constraint where conname='rewards_stock_nonnegative') then
    alter table public.rewards add constraint rewards_stock_nonnegative check (stock is null or stock >= 0);
  end if;
end $$;

create table if not exists public.reward_stock_movements (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  reward_id uuid not null references public.rewards(id) on delete cascade,
  quantity_change int not null check (quantity_change <> 0),
  stock_after int not null check (stock_after >= 0),
  reason text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists reward_stock_movements_reward_created_idx
  on public.reward_stock_movements(reward_id,created_at desc);

alter table public.reward_stock_movements enable row level security;

drop policy if exists reward_stock_movements_owner_select on public.reward_stock_movements;
create policy reward_stock_movements_owner_select
on public.reward_stock_movements
for select
using (public.current_clinic_role(clinic_id)='owner');

drop policy if exists reward_stock_movements_owner_insert on public.reward_stock_movements;
create policy reward_stock_movements_owner_insert
on public.reward_stock_movements
for insert
with check (public.current_clinic_role(clinic_id)='owner');

create or replace function public.adjust_reward_stock(
  p_reward_id uuid,
  p_delta int,
  p_reason text default null
) returns int
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_current int;
  v_next int;
begin
  if p_delta=0 then
    raise exception 'Stok değişimi sıfır olamaz';
  end if;

  select r.clinic_id,r.stock
  into v_clinic,v_current
  from public.rewards r
  where r.id=p_reward_id
  for update;

  if v_clinic is null then
    raise exception 'Ödül bulunamadı';
  end if;
  if public.current_clinic_role(v_clinic)<>'owner' then
    raise exception 'Yalnızca Klinik Sahibi stok değiştirebilir';
  end if;
  if v_current is null then
    raise exception 'Sınırsız stoklu ödülde stok hareketi yapılamaz';
  end if;

  v_next := v_current+p_delta;
  if v_next<0 then
    raise exception 'Stok sıfırın altına düşemez';
  end if;

  update public.rewards
  set stock=v_next
  where id=p_reward_id;

  insert into public.reward_stock_movements(
    clinic_id,reward_id,quantity_change,stock_after,reason,created_by
  ) values(
    v_clinic,p_reward_id,p_delta,v_next,nullif(p_reason,''),auth.uid()
  );

  return v_next;
end;
$$;

revoke all on function public.adjust_reward_stock(uuid,int,text) from public;
grant execute on function public.adjust_reward_stock(uuid,int,text) to authenticated;

-- Existing owner RLS policy is authoritative; these privileges allow the owner UI
-- to create, edit, activate/deactivate and delete catalogue items.
grant insert,update,delete on public.rewards to authenticated;
grant select,insert on public.reward_stock_movements to authenticated;

commit;

-- ============================================================================
-- 005_meal_nutrition_auth_upgrade.sql
-- ============================================================================

-- NutriClinic AI v2.3
-- Adds a clinic-editable food nutrition catalogue used for automatic macro calculations.
-- Run once after migrations 001 through 004.

begin;

create table if not exists public.food_catalog (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid references public.clinics(id) on delete cascade,
  name text not null,
  name_key text not null,
  calories_per_100g numeric(8,2) not null default 0 check (calories_per_100g >= 0),
  protein_per_100g numeric(8,2) not null default 0 check (protein_per_100g >= 0),
  carbs_per_100g numeric(8,2) not null default 0 check (carbs_per_100g >= 0),
  fat_per_100g numeric(8,2) not null default 0 check (fat_per_100g >= 0),
  default_portion_g numeric(8,2) not null default 100 check (default_portion_g > 0),
  source_label text,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (clinic_id,name_key)
);

create unique index if not exists food_catalog_global_name_key_uidx
  on public.food_catalog(name_key)
  where clinic_id is null;

create index if not exists food_catalog_clinic_active_name_idx
  on public.food_catalog(clinic_id,is_active,name);

alter table public.food_catalog enable row level security;

drop policy if exists food_catalog_select_members on public.food_catalog;
create policy food_catalog_select_members
on public.food_catalog
for select
using (
  is_active=true
  and (clinic_id is null or public.current_clinic_role(clinic_id) is not null)
);

drop policy if exists food_catalog_insert_clinical on public.food_catalog;
create policy food_catalog_insert_clinical
on public.food_catalog
for insert
with check (
  clinic_id is not null
  and public.current_clinic_role(clinic_id) in ('owner','dietitian')
  and created_by=auth.uid()
);

drop policy if exists food_catalog_update_clinical on public.food_catalog;
create policy food_catalog_update_clinical
on public.food_catalog
for update
using (
  clinic_id is not null
  and public.current_clinic_role(clinic_id) in ('owner','dietitian')
)
with check (
  clinic_id is not null
  and public.current_clinic_role(clinic_id) in ('owner','dietitian')
);

drop policy if exists food_catalog_delete_clinical on public.food_catalog;
create policy food_catalog_delete_clinical
on public.food_catalog
for delete
using (
  clinic_id is not null
  and public.current_clinic_role(clinic_id) in ('owner','dietitian')
);

grant select,insert,update,delete on public.food_catalog to authenticated;

-- Starter values are per 100 g and deliberately remain editable through a
-- clinic-specific override. Clinical teams should validate values against the
-- database and preparation method they use in practice.
insert into public.food_catalog(
  clinic_id,name,name_key,calories_per_100g,protein_per_100g,
  carbs_per_100g,fat_per_100g,default_portion_g,source_label
) values
  (null,'Yumurta','yumurta',143,12.6,0.7,9.5,50,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Süt, tam yağlı','sut tam yagli',61,3.2,4.8,3.3,200,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Yoğurt, tam yağlı','yogurt tam yagli',61,3.5,4.7,3.3,200,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Beyaz peynir','beyaz peynir',264,14.2,4.1,21.3,30,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Kaşar peyniri','kasar peyniri',404,25,1.3,33,30,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Tavuk göğsü, pişmiş','tavuk gogsu pismis',165,31,0,3.6,120,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Dana kıyma, pişmiş','dana kiyma pismis',250,26,0,15,120,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Somon, pişmiş','somon pismis',206,22,0,12,120,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Ton balığı, suda','ton baligi suda',116,26,0,1,100,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Kuru fasulye, pişmiş','kuru fasulye pismis',127,8.7,22.8,0.5,150,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Nohut, pişmiş','nohut pismis',164,8.9,27.4,2.6,150,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Yeşil mercimek, pişmiş','yesil mercimek pismis',116,9,20.1,0.4,150,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Pirinç, pişmiş','pirinc pismis',130,2.7,28.2,0.3,150,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Bulgur, pişmiş','bulgur pismis',83,3.1,18.6,0.2,150,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Yulaf ezmesi, kuru','yulaf ezmesi kuru',389,16.9,66.3,6.9,40,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Tam buğday ekmeği','tam bugday ekmegi',247,13,41,4.2,50,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Muz','muz',89,1.1,22.8,0.3,120,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Elma','elma',52,0.3,13.8,0.2,150,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Avokado','avokado',160,2,8.5,14.7,100,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Badem','badem',579,21.2,21.6,49.9,20,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Zeytinyağı','zeytinyagi',884,0,0,100,10,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Patates, haşlanmış','patates haslanmis',87,1.9,20.1,0.1,150,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Brokoli, pişmiş','brokoli pismis',35,2.4,7.2,0.4,150,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Ispanak, pişmiş','ispanak pismis',23,3,3.8,0.3,150,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Ayran','ayran',37,2,3,1.8,200,'Başlangıç kataloğu — klinik doğrulaması önerilir')
on conflict do nothing;

commit;

-- ============================================================================
-- 006_manual_loyalty_points.sql
-- ============================================================================

-- NutriClinic AI v2.4
-- Owner/dietitian manual loyalty point awards with transaction and audit logs.

alter table public.loyalty_transactions
  add column if not exists balance_after int;

create or replace function public.add_client_loyalty_points(
  p_client_id uuid,
  p_points int,
  p_reason text
) returns int
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_wallet_id uuid;
  v_old_balance int;
  v_new_balance int;
  v_transaction_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_points is null or p_points <= 0 then
    raise exception 'Points must be a positive integer';
  end if;

  if nullif(btrim(coalesce(p_reason,'')),'') is null then
    raise exception 'A reason is required for the loyalty log';
  end if;

  select c.clinic_id
    into v_clinic
  from public.client_profiles c
  where c.id=p_client_id
    and c.is_active=true;

  if v_clinic is null then
    raise exception 'Active client profile not found';
  end if;

  select m.role
    into v_role
  from public.clinic_memberships m
  where m.clinic_id=v_clinic
    and m.user_id=auth.uid()
    and m.is_active=true
  limit 1;

  if v_role is null or v_role not in ('owner','dietitian') then
    raise exception 'Only a clinic owner or dietitian can add loyalty points';
  end if;

  insert into public.loyalty_wallets(clinic_id,client_id,balance)
  values(v_clinic,p_client_id,0)
  on conflict(clinic_id,client_id) do nothing;

  select w.id,w.balance
    into v_wallet_id,v_old_balance
  from public.loyalty_wallets w
  where w.clinic_id=v_clinic
    and w.client_id=p_client_id
  for update;

  if v_old_balance > 2147483647 - p_points then
    raise exception 'Loyalty balance limit would be exceeded';
  end if;

  v_new_balance := v_old_balance + p_points;

  update public.loyalty_wallets
  set balance=v_new_balance,
      updated_at=now()
  where id=v_wallet_id;

  insert into public.loyalty_transactions(
    wallet_id,transaction_type,points,reason,created_by,balance_after
  ) values(
    v_wallet_id,'adjusted',p_points,btrim(p_reason),auth.uid(),v_new_balance
  ) returning id into v_transaction_id;

  insert into public.audit_logs(
    clinic_id,actor_user_id,action,target_type,target_id,metadata
  ) values(
    v_clinic,
    auth.uid(),
    'client_loyalty_points_added',
    'client',
    p_client_id::text,
    jsonb_build_object(
      'transaction_id',v_transaction_id,
      'points_added',p_points,
      'reason',btrim(p_reason),
      'balance_before',v_old_balance,
      'balance_after',v_new_balance,
      'actor_role',v_role
    )
  );

  return v_new_balance;
end;
$$;

create or replace function public.get_client_loyalty_history(
  p_client_id uuid
) returns table(
  id uuid,
  transaction_type public.reward_transaction_type,
  points int,
  reason text,
  actor_user_id uuid,
  actor_name text,
  actor_role public.clinic_role,
  balance_after int,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select c.clinic_id
    into v_clinic
  from public.client_profiles c
  where c.id=p_client_id;

  select m.role
    into v_role
  from public.clinic_memberships m
  where m.clinic_id=v_clinic
    and m.user_id=auth.uid()
    and m.is_active=true
  limit 1;

  if v_role is null or v_role not in ('owner','dietitian') then
    raise exception 'Only a clinic owner or dietitian can view this loyalty history';
  end if;

  return query
  select
    t.id,
    t.transaction_type,
    t.points,
    t.reason,
    t.created_by as actor_user_id,
    p.full_name as actor_name,
    membership.role as actor_role,
    t.balance_after,
    t.created_at
  from public.loyalty_transactions t
  join public.loyalty_wallets w on w.id=t.wallet_id
  left join public.profiles p on p.id=t.created_by
  left join public.clinic_memberships membership
    on membership.clinic_id=w.clinic_id
   and membership.user_id=t.created_by
  where w.client_id=p_client_id
    and w.clinic_id=v_clinic
  order by t.created_at desc
  limit 100;
end;
$$;

revoke all on function public.add_client_loyalty_points(uuid,int,text) from public;
revoke all on function public.get_client_loyalty_history(uuid) from public;
grant execute on function public.add_client_loyalty_points(uuid,int,text) to authenticated;
grant execute on function public.get_client_loyalty_history(uuid) to authenticated;

grant select on public.loyalty_wallets,public.loyalty_transactions,public.audit_logs to authenticated;

-- ============================================================================
-- 007_edit_calendar_redemption_settings.sql
-- ============================================================================

-- NutriClinic AI v2.5
-- Hides the first-owner card when an owner already exists, adds a month calendar
-- availability endpoint, atomic meal-plan create/edit and client reward redemption.
-- Run once after migrations 001 through 006.

begin;

create or replace function public.can_claim_first_owner()
returns boolean
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
begin
  if auth.uid() is null then
    return false;
  end if;

  select m.clinic_id
    into v_clinic
  from public.clinic_memberships m
  where m.user_id=auth.uid()
    and m.is_active=true
  limit 1;

  if v_clinic is null then
    return false;
  end if;

  return not exists(
    select 1
    from public.clinic_memberships owner_membership
    where owner_membership.clinic_id=v_clinic
      and owner_membership.role='owner'
      and owner_membership.is_active=true
  );
end;
$$;

create or replace function public.get_dietitian_calendar(
  p_dietitian_id uuid,
  p_start date,
  p_end date
) returns table(
  day date,
  available_count int,
  total_count int
)
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_day date;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_start is null or p_end is null or p_end < p_start then
    raise exception 'Invalid calendar date range';
  end if;

  if p_end-p_start > 42 then
    raise exception 'Calendar range cannot exceed 43 days';
  end if;

  select d.clinic_id
    into v_clinic
  from public.dietitian_profiles d
  where d.id=p_dietitian_id
    and d.is_bookable=true;

  if v_clinic is null or public.current_clinic_role(v_clinic) is null then
    raise exception 'Access denied';
  end if;

  for v_day in
    select generate_series(p_start,p_end,interval '1 day')::date
  loop
    return query
    select
      v_day,
      (count(*) filter (where slot.is_available))::int,
      count(*)::int
    from public.get_dietitian_day_slots(p_dietitian_id,v_day) slot;
  end loop;
end;
$$;

create or replace function public.save_meal_plan_v2(
  p_plan_id uuid,
  p_client_id uuid,
  p_title text,
  p_starts_on date,
  p_ends_on date,
  p_target_calories numeric,
  p_target_protein_g numeric,
  p_target_carbs_g numeric,
  p_target_fat_g numeric,
  p_note text,
  p_items jsonb
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_dietitian_id uuid;
  v_plan_id uuid;
  v_action text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select membership.clinic_id,membership.role
    into v_clinic,v_role
  from public.clinic_memberships membership
  where membership.user_id=auth.uid()
    and membership.is_active=true
  limit 1;

  if v_clinic is null or v_role not in ('owner','dietitian') then
    raise exception 'Only a clinic owner or dietitian can save meal plans';
  end if;

  if p_starts_on is null or p_ends_on is null or p_ends_on<p_starts_on then
    raise exception 'Invalid plan date range';
  end if;

  if nullif(btrim(coalesce(p_title,'')),'') is null then
    raise exception 'Plan title is required';
  end if;

  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then
    raise exception 'At least one meal item is required';
  end if;

  if not exists(
    select 1 from public.client_profiles client
    where client.id=p_client_id
      and client.clinic_id=v_clinic
      and client.is_active=true
  ) then
    raise exception 'Active client not found';
  end if;

  select dietitian.id
    into v_dietitian_id
  from public.dietitian_profiles dietitian
  where dietitian.clinic_id=v_clinic
    and dietitian.user_id=auth.uid()
  limit 1;

  if p_plan_id is null then
    if v_dietitian_id is null then
      raise exception 'Dietitian profile not found';
    end if;

    insert into public.meal_plans(
      clinic_id,client_id,dietitian_id,title,starts_on,ends_on,
      target_calories,target_protein_g,target_carbs_g,target_fat_g,
      status,dietitian_note
    ) values(
      v_clinic,p_client_id,v_dietitian_id,btrim(p_title),p_starts_on,p_ends_on,
      p_target_calories,p_target_protein_g,p_target_carbs_g,p_target_fat_g,
      'active',nullif(btrim(coalesce(p_note,'')),'')
    ) returning id into v_plan_id;
    v_action := 'meal_plan_created';
  else
    select plan.id
      into v_plan_id
    from public.meal_plans plan
    where plan.id=p_plan_id
      and plan.clinic_id=v_clinic
    for update;

    if v_plan_id is null then
      raise exception 'Meal plan not found';
    end if;

    update public.meal_plans
    set client_id=p_client_id,
        title=btrim(p_title),
        starts_on=p_starts_on,
        ends_on=p_ends_on,
        target_calories=p_target_calories,
        target_protein_g=p_target_protein_g,
        target_carbs_g=p_target_carbs_g,
        target_fat_g=p_target_fat_g,
        dietitian_note=nullif(btrim(coalesce(p_note,'')),''),
        updated_at=now()
    where id=v_plan_id;

    delete from public.meal_plan_items where meal_plan_id=v_plan_id;
    v_action := 'meal_plan_updated';
  end if;

  insert into public.meal_plan_items(
    meal_plan_id,meal_name,food_name,portion_text,
    calories,protein_g,carbs_g,fat_g,sort_order
  )
  select
    v_plan_id,
    coalesce(nullif(btrim(item.value->>'meal_name'),''),'Diğer'),
    btrim(item.value->>'food_name'),
    nullif(btrim(coalesce(item.value->>'portion_text','')),''),
    coalesce(nullif(item.value->>'calories','')::numeric,0),
    coalesce(nullif(item.value->>'protein_g','')::numeric,0),
    coalesce(nullif(item.value->>'carbs_g','')::numeric,0),
    coalesce(nullif(item.value->>'fat_g','')::numeric,0),
    coalesce(nullif(item.value->>'sort_order','')::smallint,(item.ordinality-1)::smallint)
  from jsonb_array_elements(p_items) with ordinality as item(value,ordinality)
  where nullif(btrim(item.value->>'food_name'),'') is not null;

  if not exists(select 1 from public.meal_plan_items where meal_plan_id=v_plan_id) then
    raise exception 'At least one valid food item is required';
  end if;

  insert into public.audit_logs(
    clinic_id,actor_user_id,action,target_type,target_id,metadata
  ) values(
    v_clinic,auth.uid(),v_action,'meal_plan',v_plan_id::text,
    jsonb_build_object('client_id',p_client_id,'item_count',jsonb_array_length(p_items),'actor_role',v_role)
  );

  return v_plan_id;
end;
$$;

create or replace function public.redeem_reward(
  p_reward_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_client_id uuid;
  v_wallet_id uuid;
  v_balance int;
  v_new_balance int;
  v_reward_name text;
  v_points_cost int;
  v_stock int;
  v_transaction_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select client.clinic_id,client.id
    into v_clinic,v_client_id
  from public.client_profiles client
  join public.clinic_memberships membership
    on membership.clinic_id=client.clinic_id
   and membership.user_id=client.user_id
   and membership.role='client'
   and membership.is_active=true
  where client.user_id=auth.uid()
    and client.is_active=true
  limit 1;

  if v_client_id is null then
    raise exception 'Active client profile not found';
  end if;

  select reward.name,reward.points_cost,reward.stock
    into v_reward_name,v_points_cost,v_stock
  from public.rewards reward
  where reward.id=p_reward_id
    and reward.clinic_id=v_clinic
    and reward.is_active=true
  for update;

  if v_reward_name is null then
    raise exception 'Reward is unavailable';
  end if;

  if v_stock is not null and v_stock<=0 then
    raise exception 'Reward is out of stock';
  end if;

  insert into public.loyalty_wallets(clinic_id,client_id,balance)
  values(v_clinic,v_client_id,0)
  on conflict(clinic_id,client_id) do nothing;

  select wallet.id,wallet.balance
    into v_wallet_id,v_balance
  from public.loyalty_wallets wallet
  where wallet.clinic_id=v_clinic
    and wallet.client_id=v_client_id
  for update;

  if v_balance<v_points_cost then
    raise exception 'Insufficient loyalty points';
  end if;

  v_new_balance := v_balance-v_points_cost;

  update public.loyalty_wallets
  set balance=v_new_balance,
      updated_at=now()
  where id=v_wallet_id;

  if v_stock is not null then
    update public.rewards
    set stock=v_stock-1
    where id=p_reward_id;

    insert into public.reward_stock_movements(
      clinic_id,reward_id,quantity_change,stock_after,reason,created_by
    ) values(
      v_clinic,p_reward_id,-1,v_stock-1,'Danışan ödül kullanımı',auth.uid()
    );
  end if;

  insert into public.loyalty_transactions(
    wallet_id,transaction_type,points,reason,reward_id,created_by,balance_after
  ) values(
    v_wallet_id,'redeemed',-v_points_cost,'Ödül kullanımı: '||v_reward_name,p_reward_id,auth.uid(),v_new_balance
  ) returning id into v_transaction_id;

  insert into public.audit_logs(
    clinic_id,actor_user_id,action,target_type,target_id,metadata
  ) values(
    v_clinic,auth.uid(),'loyalty_reward_redeemed','reward',p_reward_id::text,
    jsonb_build_object(
      'transaction_id',v_transaction_id,
      'client_id',v_client_id,
      'reward_name',v_reward_name,
      'points_spent',v_points_cost,
      'balance_before',v_balance,
      'balance_after',v_new_balance,
      'stock_after',case when v_stock is null then null else v_stock-1 end
    )
  );

  return jsonb_build_object(
    'balance',v_new_balance,
    'reward_name',v_reward_name,
    'transaction_id',v_transaction_id
  );
end;
$$;

revoke all on function public.can_claim_first_owner() from public;
revoke all on function public.get_dietitian_calendar(uuid,date,date) from public;
revoke all on function public.save_meal_plan_v2(uuid,uuid,text,date,date,numeric,numeric,numeric,numeric,text,jsonb) from public;
revoke all on function public.redeem_reward(uuid) from public;

grant execute on function public.can_claim_first_owner() to authenticated;
grant execute on function public.get_dietitian_calendar(uuid,date,date) to authenticated;
grant execute on function public.save_meal_plan_v2(uuid,uuid,text,date,date,numeric,numeric,numeric,numeric,text,jsonb) to authenticated;
grant execute on function public.redeem_reward(uuid) to authenticated;

commit;

-- ============================================================================
-- 008_loyalty_redemptions_food_warnings.sql
-- ============================================================================

-- NutriClinic AI v2.6
-- Loyalty earned/used/remaining summaries, visible reward redemption history,
-- and operational redemption records. Run once after migrations 001-007.

begin;

create table if not exists public.reward_redemptions (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  reward_id uuid references public.rewards(id) on delete set null,
  loyalty_transaction_id uuid unique references public.loyalty_transactions(id) on delete set null,
  reward_name text not null,
  points_spent int not null check (points_spent > 0),
  status text not null default 'requested' check (status in ('requested','approved','fulfilled','cancelled')),
  requested_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  fulfilled_at timestamptz,
  handled_by uuid references public.profiles(id) on delete set null,
  note text
);

create index if not exists reward_redemptions_client_requested_idx
  on public.reward_redemptions(client_id,requested_at desc);

alter table public.reward_redemptions enable row level security;

drop policy if exists reward_redemptions_select on public.reward_redemptions;
create policy reward_redemptions_select
on public.reward_redemptions for select
using (
  public.current_clinic_role(clinic_id) in ('owner','dietitian')
  or client_id=public.current_client_id(clinic_id)
);

drop policy if exists reward_redemptions_update_staff on public.reward_redemptions;
create policy reward_redemptions_update_staff
on public.reward_redemptions for update
using (public.current_clinic_role(clinic_id) in ('owner','dietitian'))
with check (public.current_clinic_role(clinic_id) in ('owner','dietitian'));

-- Preserve visibility for rewards redeemed before this migration.
insert into public.reward_redemptions(
  clinic_id,client_id,reward_id,loyalty_transaction_id,reward_name,
  points_spent,status,requested_at,updated_at
)
select
  wallet.clinic_id,
  wallet.client_id,
  transaction.reward_id,
  transaction.id,
  coalesce(reward.name, regexp_replace(transaction.reason,'^Ödül kullanımı:\s*','','i')),
  abs(transaction.points),
  'requested',
  transaction.created_at,
  transaction.created_at
from public.loyalty_transactions transaction
join public.loyalty_wallets wallet on wallet.id=transaction.wallet_id
left join public.rewards reward on reward.id=transaction.reward_id
where transaction.transaction_type='redeemed'
  and transaction.points<0
on conflict (loyalty_transaction_id) do nothing;

create or replace function public.get_client_loyalty_summaries()
returns table(
  client_id uuid,
  earned_points bigint,
  used_points bigint,
  remaining_points int
)
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select membership.clinic_id,membership.role
    into v_clinic,v_role
  from public.clinic_memberships membership
  where membership.user_id=auth.uid()
    and membership.is_active=true
  limit 1;

  if v_clinic is null or v_role not in ('owner','dietitian') then
    raise exception 'Only a clinic owner or dietitian can view loyalty summaries';
  end if;

  return query
  select
    client.id,
    coalesce(sum(case when transaction.points>0 then transaction.points else 0 end),0)::bigint as earned_points,
    coalesce(sum(case when transaction.transaction_type='redeemed' and transaction.points<0 then abs(transaction.points) else 0 end),0)::bigint as used_points,
    coalesce(wallet.balance,0)::int as remaining_points
  from public.client_profiles client
  left join public.loyalty_wallets wallet
    on wallet.clinic_id=client.clinic_id and wallet.client_id=client.id
  left join public.loyalty_transactions transaction
    on transaction.wallet_id=wallet.id
  where client.clinic_id=v_clinic
    and client.is_active=true
  group by client.id,wallet.balance
  order by client.created_at desc;
end;
$$;

create or replace function public.get_reward_redemptions(
  p_client_id uuid default null
) returns table(
  id uuid,
  client_id uuid,
  reward_name text,
  points_spent int,
  status text,
  requested_at timestamptz,
  fulfilled_at timestamptz,
  note text
)
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_own_client uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select membership.clinic_id,membership.role
    into v_clinic,v_role
  from public.clinic_memberships membership
  where membership.user_id=auth.uid()
    and membership.is_active=true
  limit 1;

  if v_clinic is null then
    raise exception 'Active clinic membership not found';
  end if;

  if v_role='client' then
    select client.id into v_own_client
    from public.client_profiles client
    where client.clinic_id=v_clinic
      and client.user_id=auth.uid()
      and client.is_active=true
    limit 1;

    if v_own_client is null then
      raise exception 'Active client profile not found';
    end if;

    return query
    select redemption.id,redemption.client_id,redemption.reward_name,
           redemption.points_spent,redemption.status,redemption.requested_at,
           redemption.fulfilled_at,redemption.note
    from public.reward_redemptions redemption
    where redemption.clinic_id=v_clinic
      and redemption.client_id=v_own_client
    order by redemption.requested_at desc;
  elsif v_role in ('owner','dietitian') then
    return query
    select redemption.id,redemption.client_id,redemption.reward_name,
           redemption.points_spent,redemption.status,redemption.requested_at,
           redemption.fulfilled_at,redemption.note
    from public.reward_redemptions redemption
    where redemption.clinic_id=v_clinic
      and (p_client_id is null or redemption.client_id=p_client_id)
    order by redemption.requested_at desc;
  else
    raise exception 'Access denied';
  end if;
end;
$$;

create or replace function public.redeem_reward(
  p_reward_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_client_id uuid;
  v_wallet_id uuid;
  v_balance int;
  v_new_balance int;
  v_reward_name text;
  v_points_cost int;
  v_stock int;
  v_transaction_id uuid;
  v_redemption_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select client.clinic_id,client.id
    into v_clinic,v_client_id
  from public.client_profiles client
  join public.clinic_memberships membership
    on membership.clinic_id=client.clinic_id
   and membership.user_id=client.user_id
   and membership.role='client'
   and membership.is_active=true
  where client.user_id=auth.uid()
    and client.is_active=true
  limit 1;

  if v_client_id is null then
    raise exception 'Active client profile not found';
  end if;

  select reward.name,reward.points_cost,reward.stock
    into v_reward_name,v_points_cost,v_stock
  from public.rewards reward
  where reward.id=p_reward_id
    and reward.clinic_id=v_clinic
    and reward.is_active=true
  for update;

  if v_reward_name is null then
    raise exception 'Reward is unavailable';
  end if;

  if v_stock is not null and v_stock<=0 then
    raise exception 'Reward is out of stock';
  end if;

  insert into public.loyalty_wallets(clinic_id,client_id,balance)
  values(v_clinic,v_client_id,0)
  on conflict(clinic_id,client_id) do nothing;

  select wallet.id,wallet.balance
    into v_wallet_id,v_balance
  from public.loyalty_wallets wallet
  where wallet.clinic_id=v_clinic
    and wallet.client_id=v_client_id
  for update;

  if v_balance<v_points_cost then
    raise exception 'Insufficient loyalty points';
  end if;

  v_new_balance := v_balance-v_points_cost;

  update public.loyalty_wallets
  set balance=v_new_balance,updated_at=now()
  where id=v_wallet_id;

  if v_stock is not null then
    update public.rewards set stock=v_stock-1 where id=p_reward_id;
    insert into public.reward_stock_movements(
      clinic_id,reward_id,quantity_change,stock_after,reason,created_by
    ) values(
      v_clinic,p_reward_id,-1,v_stock-1,'Danışan ödül kullanımı',auth.uid()
    );
  end if;

  insert into public.loyalty_transactions(
    wallet_id,transaction_type,points,reason,reward_id,created_by,balance_after
  ) values(
    v_wallet_id,'redeemed',-v_points_cost,'Ödül kullanımı: '||v_reward_name,p_reward_id,auth.uid(),v_new_balance
  ) returning id into v_transaction_id;

  insert into public.reward_redemptions(
    clinic_id,client_id,reward_id,loyalty_transaction_id,reward_name,
    points_spent,status,requested_at,updated_at
  ) values(
    v_clinic,v_client_id,p_reward_id,v_transaction_id,v_reward_name,
    v_points_cost,'requested',now(),now()
  ) returning id into v_redemption_id;

  insert into public.audit_logs(
    clinic_id,actor_user_id,action,target_type,target_id,metadata
  ) values(
    v_clinic,auth.uid(),'loyalty_reward_redeemed','reward',p_reward_id::text,
    jsonb_build_object(
      'transaction_id',v_transaction_id,
      'redemption_id',v_redemption_id,
      'client_id',v_client_id,
      'reward_name',v_reward_name,
      'points_spent',v_points_cost,
      'balance_before',v_balance,
      'balance_after',v_new_balance,
      'stock_after',case when v_stock is null then null else v_stock-1 end
    )
  );

  return jsonb_build_object(
    'balance',v_new_balance,
    'reward_name',v_reward_name,
    'transaction_id',v_transaction_id,
    'redemption_id',v_redemption_id
  );
end;
$$;

revoke all on function public.get_client_loyalty_summaries() from public;
revoke all on function public.get_reward_redemptions(uuid) from public;
revoke all on function public.redeem_reward(uuid) from public;

grant execute on function public.get_client_loyalty_summaries() to authenticated;
grant execute on function public.get_reward_redemptions(uuid) to authenticated;
grant execute on function public.redeem_reward(uuid) to authenticated;
grant select,update on public.reward_redemptions to authenticated;

commit;

-- ============================================================================
-- 009_uiux_payments_media_community.sql
-- ============================================================================

-- NutriClinic AI v3.0
-- Modern operational dashboard support: payments, detailed client directory,
-- enriched appointment slots/status workflow, meal photos, and dietitian-group community feed.
-- Run once after migrations 001-008.

begin;

alter table public.client_profiles
  add column if not exists community_opt_in boolean not null default true;

alter table public.appointments
  add column if not exists cancellation_reason text;

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  appointment_id uuid references public.appointments(id) on delete set null,
  service_type text not null,
  description text,
  amount numeric(12,2) not null check (amount >= 0),
  currency text not null default 'TRY',
  status text not null default 'pending' check (status in ('pending','partial','paid','refunded','cancelled')),
  method text check (method is null or method in ('cash','card','iban','other')),
  paid_at timestamptz,
  recorded_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists payments_clinic_paid_idx on public.payments(clinic_id,paid_at desc);
create index if not exists payments_client_created_idx on public.payments(client_id,created_at desc);
create index if not exists payments_status_idx on public.payments(clinic_id,status);

create table if not exists public.meal_photos (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  meal_plan_id uuid not null references public.meal_plans(id) on delete cascade,
  meal_name text not null,
  consumed_on date not null default current_date,
  photo_path text not null,
  caption text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(client_id,meal_plan_id,meal_name,consumed_on)
);

create index if not exists meal_photos_plan_date_idx on public.meal_photos(meal_plan_id,consumed_on desc);

create table if not exists public.community_posts (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  dietitian_id uuid not null references public.dietitian_profiles(id) on delete cascade,
  client_id uuid references public.client_profiles(id) on delete set null,
  author_user_id uuid not null references public.profiles(id) on delete cascade,
  content text,
  media_path text,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (nullif(trim(coalesce(content,'')),'') is not null or media_path is not null)
);

create index if not exists community_posts_group_created_idx on public.community_posts(dietitian_id,created_at desc);

create table if not exists public.community_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.community_posts(id) on delete cascade,
  author_user_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check (length(trim(content)) between 1 and 1000),
  created_at timestamptz not null default now()
);

create index if not exists community_comments_post_created_idx on public.community_comments(post_id,created_at);

create or replace function public.can_access_dietitian_group(p_dietitian_id uuid)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists (
    select 1
    from public.dietitian_profiles d
    join public.clinic_memberships m
      on m.clinic_id=d.clinic_id
     and m.user_id=auth.uid()
     and m.is_active=true
    where d.id=p_dietitian_id
      and (
        m.role='owner'
        or (m.role='dietitian' and d.user_id=auth.uid())
        or (
          m.role='client'
          and exists (
            select 1 from public.client_profiles c
            where c.clinic_id=d.clinic_id
              and c.user_id=auth.uid()
              and c.assigned_dietitian_id=d.id
              and c.is_active=true
              and c.community_opt_in=true
          )
        )
      )
  );
$$;

alter table public.payments enable row level security;
alter table public.meal_photos enable row level security;
alter table public.community_posts enable row level security;
alter table public.community_comments enable row level security;

drop policy if exists payments_select_members on public.payments;
create policy payments_select_members on public.payments for select
using (
  public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary')
  or client_id=public.current_client_id(clinic_id)
);

drop policy if exists payments_manage_owner_secretary on public.payments;
create policy payments_manage_owner_secretary on public.payments for all
using (public.current_clinic_role(clinic_id) in ('owner','secretary'))
with check (public.current_clinic_role(clinic_id) in ('owner','secretary'));

drop policy if exists meal_photos_select_clinical_or_self on public.meal_photos;
create policy meal_photos_select_clinical_or_self on public.meal_photos for select
using (
  public.current_clinic_role(clinic_id) in ('owner','dietitian')
  or client_id=public.current_client_id(clinic_id)
);

drop policy if exists meal_photos_insert_self on public.meal_photos;
create policy meal_photos_insert_self on public.meal_photos for insert
with check (client_id=public.current_client_id(clinic_id));

drop policy if exists meal_photos_update_self on public.meal_photos;
create policy meal_photos_update_self on public.meal_photos for update
using (client_id=public.current_client_id(clinic_id))
with check (client_id=public.current_client_id(clinic_id));

drop policy if exists meal_photos_delete_self on public.meal_photos;
create policy meal_photos_delete_self on public.meal_photos for delete
using (client_id=public.current_client_id(clinic_id));

drop policy if exists community_posts_select_group on public.community_posts;
create policy community_posts_select_group on public.community_posts for select
using (not is_deleted and public.can_access_dietitian_group(dietitian_id));

drop policy if exists community_comments_select_group on public.community_comments;
create policy community_comments_select_group on public.community_comments for select
using (
  exists (
    select 1 from public.community_posts p
    where p.id=post_id and not p.is_deleted and public.can_access_dietitian_group(p.dietitian_id)
  )
);

-- Storage buckets for private meal and community media.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('meal-photos','meal-photos',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=5242880,allowed_mime_types=excluded.allowed_mime_types;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('community-media','community-media',false,8388608,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=8388608,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists meal_media_insert_own on storage.objects;
create policy meal_media_insert_own on storage.objects for insert to authenticated
with check (bucket_id='meal-photos' and (storage.foldername(name))[1]=auth.uid()::text);

drop policy if exists meal_media_select_authorized on storage.objects;
create policy meal_media_select_authorized on storage.objects for select to authenticated
using (
  bucket_id='meal-photos'
  and (
    (storage.foldername(name))[1]=auth.uid()::text
    or exists (
      select 1
      from public.client_profiles c
      join public.clinic_memberships m on m.clinic_id=c.clinic_id and m.user_id=auth.uid() and m.is_active=true
      where c.user_id::text=(storage.foldername(name))[1]
        and m.role in ('owner','dietitian')
    )
  )
);

drop policy if exists meal_media_update_own on storage.objects;
create policy meal_media_update_own on storage.objects for update to authenticated
using (bucket_id='meal-photos' and (storage.foldername(name))[1]=auth.uid()::text)
with check (bucket_id='meal-photos' and (storage.foldername(name))[1]=auth.uid()::text);

drop policy if exists meal_media_delete_own on storage.objects;
create policy meal_media_delete_own on storage.objects for delete to authenticated
using (bucket_id='meal-photos' and (storage.foldername(name))[1]=auth.uid()::text);

drop policy if exists community_media_insert_own on storage.objects;
create policy community_media_insert_own on storage.objects for insert to authenticated
with check (bucket_id='community-media' and (storage.foldername(name))[1]=auth.uid()::text);

drop policy if exists community_media_select_group on storage.objects;
create policy community_media_select_group on storage.objects for select to authenticated
using (
  bucket_id='community-media'
  and exists (
    select 1 from public.community_posts p
    where p.media_path=name and not p.is_deleted and public.can_access_dietitian_group(p.dietitian_id)
  )
);

drop policy if exists community_media_delete_own on storage.objects;
create policy community_media_delete_own on storage.objects for delete to authenticated
using (bucket_id='community-media' and (storage.foldername(name))[1]=auth.uid()::text);

create or replace function public.get_client_directory_v3()
returns table(
  id uuid,
  user_id uuid,
  member_no text,
  full_name text,
  email text,
  phone text,
  birth_date date,
  gender text,
  assigned_dietitian_id uuid,
  assigned_dietitian_name text,
  height_cm numeric,
  target_text text,
  allergies text[],
  disliked_foods text[],
  medical_notes text,
  medications text,
  latest_weight_kg numeric,
  latest_body_fat_percent numeric,
  latest_muscle_mass_kg numeric,
  latest_measurement_at timestamptz,
  loyalty_earned bigint,
  loyalty_used bigint,
  loyalty_balance int,
  payment_total numeric,
  payment_paid numeric,
  payment_due numeric,
  last_payment_status text,
  last_payment_method text,
  last_payment_service text,
  last_payment_at timestamptz,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
begin
  select m.clinic_id,m.role into v_clinic,v_role
  from public.clinic_memberships m
  where m.user_id=auth.uid() and m.is_active=true
  limit 1;

  if v_clinic is null or v_role not in ('owner','dietitian','secretary') then
    raise exception 'Staff access required';
  end if;

  return query
  select
    c.id,c.user_id,c.member_no,c.full_name,c.email,c.phone,
    case when v_role='secretary' then null else c.birth_date end,
    case when v_role='secretary' then null else c.gender end,
    c.assigned_dietitian_id,
    dp.full_name,
    case when v_role='secretary' then null else c.height_cm end,
    case when v_role='secretary' then null else c.target_text end,
    case when v_role='secretary' then '{}'::text[] else c.allergies end,
    case when v_role='secretary' then '{}'::text[] else c.disliked_foods end,
    case when v_role='secretary' then null else c.medical_notes end,
    case when v_role='secretary' then null else c.medications end,
    case when v_role='secretary' then null else lm.weight_kg end,
    case when v_role='secretary' then null else lm.body_fat_percent end,
    case when v_role='secretary' then null else lm.muscle_mass_kg end,
    case when v_role='secretary' then null else lm.measured_at end,
    case when v_role='secretary' then 0 else coalesce(loyalty.earned,0) end,
    case when v_role='secretary' then 0 else coalesce(loyalty.used,0) end,
    case when v_role='secretary' then 0 else coalesce(w.balance,0) end,
    coalesce(pay.total,0),coalesce(pay.paid,0),greatest(coalesce(pay.total,0)-coalesce(pay.paid,0),0),
    last_pay.status,last_pay.method,last_pay.service_type,last_pay.paid_at,
    c.created_at
  from public.client_profiles c
  left join public.dietitian_profiles d on d.id=c.assigned_dietitian_id
  left join public.profiles dp on dp.id=d.user_id
  left join lateral (
    select m.weight_kg,m.body_fat_percent,m.muscle_mass_kg,m.measured_at
    from public.measurements m where m.client_id=c.id order by m.measured_at desc limit 1
  ) lm on true
  left join public.loyalty_wallets w on w.clinic_id=c.clinic_id and w.client_id=c.id
  left join lateral (
    select
      coalesce(sum(case when t.points>0 then t.points else 0 end),0)::bigint earned,
      coalesce(sum(case when t.points<0 then abs(t.points) else 0 end),0)::bigint used
    from public.loyalty_transactions t where t.wallet_id=w.id
  ) loyalty on true
  left join lateral (
    select
      coalesce(sum(case when p.status not in ('cancelled','refunded') then p.amount else 0 end),0)::numeric total,
      coalesce(sum(case when p.status='paid' then p.amount else 0 end),0)::numeric paid
    from public.payments p where p.client_id=c.id
  ) pay on true
  left join lateral (
    select p.status,p.method,p.service_type,p.paid_at
    from public.payments p where p.client_id=c.id order by p.created_at desc limit 1
  ) last_pay on true
  where c.clinic_id=v_clinic and c.is_active=true
  order by c.created_at desc;
end;
$$;

create or replace function public.assign_client_dietitian_v3(p_client_id uuid,p_dietitian_id uuid)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_actor_dietitian uuid;
begin
  select m.clinic_id,m.role into v_clinic,v_role
  from public.clinic_memberships m where m.user_id=auth.uid() and m.is_active=true limit 1;
  if v_role not in ('owner','dietitian') then raise exception 'Clinical access required'; end if;

  if not exists(select 1 from public.client_profiles c where c.id=p_client_id and c.clinic_id=v_clinic and c.is_active=true) then
    raise exception 'Client not found';
  end if;
  if not exists(select 1 from public.dietitian_profiles d where d.id=p_dietitian_id and d.clinic_id=v_clinic) then
    raise exception 'Dietitian not found';
  end if;

  if v_role='dietitian' then
    select d.id into v_actor_dietitian from public.dietitian_profiles d
    where d.clinic_id=v_clinic and d.user_id=auth.uid();
    if v_actor_dietitian is distinct from p_dietitian_id then raise exception 'A dietitian can only assign a client to themselves'; end if;
  end if;

  update public.client_profiles set assigned_dietitian_id=p_dietitian_id,updated_at=now() where id=p_client_id;
  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values(v_clinic,auth.uid(),'client_dietitian_assigned','client',p_client_id::text,jsonb_build_object('dietitian_id',p_dietitian_id));
end;
$$;

create or replace function public.save_payment_v3(
  p_payment_id uuid,
  p_client_id uuid,
  p_appointment_id uuid,
  p_service_type text,
  p_description text,
  p_amount numeric,
  p_status text,
  p_method text,
  p_paid_at timestamptz
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_id uuid;
  v_paid_at timestamptz;
begin
  select m.clinic_id,m.role into v_clinic,v_role
  from public.clinic_memberships m where m.user_id=auth.uid() and m.is_active=true limit 1;
  if v_clinic is null or v_role not in ('owner','secretary') then raise exception 'Owner or secretary access required'; end if;
  if p_amount<0 then raise exception 'Payment amount cannot be negative'; end if;
  if p_status not in ('pending','partial','paid','refunded','cancelled') then raise exception 'Invalid payment status'; end if;
  if p_method is not null and p_method not in ('cash','card','iban','other') then raise exception 'Invalid payment method'; end if;
  if not exists(select 1 from public.client_profiles c where c.id=p_client_id and c.clinic_id=v_clinic and c.is_active=true) then raise exception 'Client not found'; end if;
  if p_appointment_id is not null and not exists(select 1 from public.appointments a where a.id=p_appointment_id and a.clinic_id=v_clinic and a.client_id=p_client_id) then raise exception 'Appointment does not match client'; end if;

  v_paid_at := case when p_status='paid' then coalesce(p_paid_at,now()) else p_paid_at end;
  if p_payment_id is null then
    insert into public.payments(clinic_id,client_id,appointment_id,service_type,description,amount,status,method,paid_at,recorded_by)
    values(v_clinic,p_client_id,p_appointment_id,nullif(trim(p_service_type),''),nullif(trim(coalesce(p_description,'')),''),p_amount,p_status,p_method,v_paid_at,auth.uid())
    returning id into v_id;
  else
    update public.payments set
      appointment_id=p_appointment_id,
      service_type=nullif(trim(p_service_type),''),
      description=nullif(trim(coalesce(p_description,'')),''),
      amount=p_amount,status=p_status,method=p_method,paid_at=v_paid_at,recorded_by=auth.uid(),updated_at=now()
    where id=p_payment_id and clinic_id=v_clinic
    returning id into v_id;
    if v_id is null then raise exception 'Payment not found'; end if;
  end if;

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values(v_clinic,auth.uid(),case when p_payment_id is null then 'payment_created' else 'payment_updated' end,'payment',v_id::text,
    jsonb_build_object('client_id',p_client_id,'amount',p_amount,'status',p_status,'method',p_method,'service_type',p_service_type));
  return v_id;
end;
$$;

create or replace function public.get_dashboard_summary_v3()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_timezone text;
  v_today date;
  v_dietitian_id uuid;
  v_client_id uuid;
  v_result jsonb;
begin
  select m.clinic_id,m.role,c.timezone into v_clinic,v_role,v_timezone
  from public.clinic_memberships m join public.clinics c on c.id=m.clinic_id
  where m.user_id=auth.uid() and m.is_active=true limit 1;
  if v_clinic is null then raise exception 'Active membership not found'; end if;
  v_today := (now() at time zone v_timezone)::date;
  select d.id into v_dietitian_id from public.dietitian_profiles d where d.clinic_id=v_clinic and d.user_id=auth.uid();
  select c.id into v_client_id from public.client_profiles c where c.clinic_id=v_clinic and c.user_id=auth.uid() and c.is_active=true;

  if v_role='owner' then
    select jsonb_build_object(
      'today_appointments',(select count(*) from public.appointments a where a.clinic_id=v_clinic and (a.starts_at at time zone v_timezone)::date=v_today and a.status not in ('cancelled')),
      'pending_appointments',(select count(*) from public.appointments a where a.clinic_id=v_clinic and a.status='pending' and a.starts_at>=now()),
      'active_clients',(select count(*) from public.client_profiles c where c.clinic_id=v_clinic and c.is_active=true),
      'active_plans',(select count(*) from public.meal_plans p where p.clinic_id=v_clinic and p.status='active'),
      'daily_revenue',(select coalesce(sum(p.amount),0) from public.payments p where p.clinic_id=v_clinic and p.status='paid' and (p.paid_at at time zone v_timezone)::date=v_today),
      'pending_payments',(select count(*) from public.payments p where p.clinic_id=v_clinic and p.status in ('pending','partial')),
      'revenue_breakdown',coalesce((select jsonb_agg(to_jsonb(x) order by x.amount desc) from (
        select p.service_type,count(*)::int count,sum(p.amount)::numeric amount
        from public.payments p where p.clinic_id=v_clinic and p.status='paid' and (p.paid_at at time zone v_timezone)::date=v_today
        group by p.service_type
      ) x),'[]'::jsonb),
      'agenda',coalesce((select jsonb_agg(to_jsonb(x) order by x.starts_at) from (
        select a.id,a.starts_at,a.status,a.appointment_type,a.mode,c.full_name client_name,c.phone,c.email,pr.full_name dietitian_name
        from public.appointments a
        join public.client_profiles c on c.id=a.client_id
        join public.dietitian_profiles d on d.id=a.dietitian_id
        join public.profiles pr on pr.id=d.user_id
        where a.clinic_id=v_clinic and (a.starts_at at time zone v_timezone)::date=v_today and a.status<>'cancelled'
      ) x),'[]'::jsonb)
    ) into v_result;
  elsif v_role='dietitian' then
    select jsonb_build_object(
      'today_appointments',(select count(*) from public.appointments a where a.dietitian_id=v_dietitian_id and (a.starts_at at time zone v_timezone)::date=v_today and a.status<>'cancelled'),
      'pending_appointments',(select count(*) from public.appointments a where a.dietitian_id=v_dietitian_id and a.status='pending' and a.starts_at>=now()),
      'active_clients',(select count(*) from public.client_profiles c where c.assigned_dietitian_id=v_dietitian_id and c.is_active=true),
      'active_plans',(select count(*) from public.meal_plans p where p.dietitian_id=v_dietitian_id and p.status='active'),
      'agenda',coalesce((select jsonb_agg(to_jsonb(x) order by x.starts_at) from (
        select a.id,a.starts_at,a.status,a.appointment_type,a.mode,c.full_name client_name,c.phone,c.email
        from public.appointments a join public.client_profiles c on c.id=a.client_id
        where a.dietitian_id=v_dietitian_id and (a.starts_at at time zone v_timezone)::date=v_today and a.status<>'cancelled'
      ) x),'[]'::jsonb)
    ) into v_result;
  elsif v_role='secretary' then
    select jsonb_build_object(
      'today_appointments',(select count(*) from public.appointments a where a.clinic_id=v_clinic and (a.starts_at at time zone v_timezone)::date=v_today and a.status<>'cancelled'),
      'pending_appointments',(select count(*) from public.appointments a where a.clinic_id=v_clinic and a.status='pending' and a.starts_at>=now()),
      'active_clients',(select count(*) from public.client_profiles c where c.clinic_id=v_clinic and c.is_active=true),
      'pending_payments',(select count(*) from public.payments p where p.clinic_id=v_clinic and p.status in ('pending','partial')),
      'agenda',coalesce((select jsonb_agg(to_jsonb(x) order by x.starts_at) from (
        select a.id,a.starts_at,a.status,a.appointment_type,a.mode,c.full_name client_name,c.phone,c.email,pr.full_name dietitian_name
        from public.appointments a
        join public.client_profiles c on c.id=a.client_id
        join public.dietitian_profiles d on d.id=a.dietitian_id
        join public.profiles pr on pr.id=d.user_id
        where a.clinic_id=v_clinic and (a.starts_at at time zone v_timezone)::date=v_today and a.status<>'cancelled'
      ) x),'[]'::jsonb)
    ) into v_result;
  else
    select jsonb_build_object(
      'upcoming_appointments',(select count(*) from public.appointments a where a.client_id=v_client_id and a.starts_at>=now() and a.status in ('pending','confirmed')),
      'active_plans',(select count(*) from public.meal_plans p where p.client_id=v_client_id and p.status='active'),
      'measurements',(select count(*) from public.measurements m where m.client_id=v_client_id),
      'loyalty_balance',(select coalesce(w.balance,0) from public.loyalty_wallets w where w.client_id=v_client_id limit 1),
      'agenda',coalesce((select jsonb_agg(to_jsonb(x) order by x.starts_at) from (
        select a.id,a.starts_at,a.status,a.appointment_type,a.mode,pr.full_name dietitian_name
        from public.appointments a
        join public.dietitian_profiles d on d.id=a.dietitian_id
        join public.profiles pr on pr.id=d.user_id
        where a.client_id=v_client_id and a.starts_at>=now() and a.status in ('pending','confirmed') limit 5
      ) x),'[]'::jsonb)
    ) into v_result;
  end if;

  return coalesce(v_result,'{}'::jsonb) || jsonb_build_object('role',v_role,'today',v_today);
end;
$$;

create or replace function public.get_dietitian_day_slots_v3(p_dietitian_id uuid,p_day date)
returns table(
  starts_at timestamptz,
  ends_at timestamptz,
  is_available boolean,
  appointment_id uuid,
  appointment_status text,
  appointment_type text,
  client_id uuid,
  client_name text,
  client_email text,
  client_phone text
)
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_target_clinic uuid;
  v_target_user uuid;
begin
  select m.clinic_id,m.role into v_clinic,v_role from public.clinic_memberships m where m.user_id=auth.uid() and m.is_active=true limit 1;
  select d.clinic_id,d.user_id into v_target_clinic,v_target_user from public.dietitian_profiles d where d.id=p_dietitian_id and d.is_bookable=true;
  if v_clinic is null or v_target_clinic is distinct from v_clinic then raise exception 'Dietitian is not accessible'; end if;
  if v_role='dietitian' and v_target_user<>auth.uid() then raise exception 'Dietitian can only view their own detailed schedule'; end if;

  return query
  select s.starts_at,s.ends_at,
         (s.is_available and a.id is null) as is_available,
         a.id,
         a.status::text,
         a.appointment_type,
         case when v_role in ('owner','dietitian','secretary') then a.client_id else null end,
         case when v_role in ('owner','dietitian','secretary') then c.full_name else null end,
         case when v_role in ('owner','dietitian','secretary') then c.email else null end,
         case when v_role in ('owner','dietitian','secretary') then c.phone else null end
  from public.get_dietitian_day_slots(p_dietitian_id,p_day) s
  left join public.appointments a
    on a.dietitian_id=p_dietitian_id
   and a.status in ('pending','confirmed')
   and tstzrange(a.starts_at,a.ends_at,'[)') && tstzrange(s.starts_at,s.ends_at,'[)')
  left join public.client_profiles c on c.id=a.client_id
  order by s.starts_at;
end;
$$;

create or replace function public.update_appointment_status_v3(p_appointment_id uuid,p_status text,p_reason text default null)
returns text
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_client_id uuid;
  v_appointment public.appointments%rowtype;
  v_allow_cancel boolean;
  v_cancel_hours int;
  v_dietitian_id uuid;
begin
  select m.clinic_id,m.role into v_clinic,v_role from public.clinic_memberships m where m.user_id=auth.uid() and m.is_active=true limit 1;
  if v_clinic is null then raise exception 'Active membership not found'; end if;
  select * into v_appointment from public.appointments a where a.id=p_appointment_id and a.clinic_id=v_clinic for update;
  if v_appointment.id is null then raise exception 'Appointment not found'; end if;

  if v_role='client' then
    select c.id into v_client_id from public.client_profiles c where c.clinic_id=v_clinic and c.user_id=auth.uid() and c.is_active=true;
    if v_appointment.client_id<>v_client_id then raise exception 'Access denied'; end if;
    if p_status<>'cancelled' then raise exception 'Clients can only cancel their appointments'; end if;
    select c.allow_client_cancellation,c.cancellation_notice_hours into v_allow_cancel,v_cancel_hours from public.clinics c where c.id=v_clinic;
    if not v_allow_cancel then raise exception 'Client cancellation is disabled'; end if;
    if v_appointment.starts_at < now()+make_interval(hours=>v_cancel_hours) then raise exception 'Cancellation deadline has passed'; end if;
    if v_appointment.status not in ('pending','confirmed') then raise exception 'Appointment cannot be cancelled'; end if;
  elsif v_role='dietitian' then
    select d.id into v_dietitian_id from public.dietitian_profiles d where d.clinic_id=v_clinic and d.user_id=auth.uid();
    if v_appointment.dietitian_id<>v_dietitian_id then raise exception 'Access denied'; end if;
    if p_status not in ('pending','confirmed','completed','cancelled','no_show') then raise exception 'Invalid status'; end if;
  elsif v_role in ('owner','secretary') then
    if p_status not in ('pending','confirmed','completed','cancelled','no_show') then raise exception 'Invalid status'; end if;
  else
    raise exception 'Access denied';
  end if;

  update public.appointments set status=p_status::public.appointment_status,
    cancellation_reason=case when p_status='cancelled' then nullif(trim(coalesce(p_reason,'')),'') else cancellation_reason end,
    updated_at=now()
  where id=p_appointment_id;

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values(v_clinic,auth.uid(),'appointment_status_changed','appointment',p_appointment_id::text,
    jsonb_build_object('old_status',v_appointment.status,'new_status',p_status,'reason',p_reason));
  return p_status;
end;
$$;

create or replace function public.create_community_post_v3(p_content text,p_media_path text,p_dietitian_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_group uuid;
  v_client uuid;
  v_id uuid;
begin
  select m.clinic_id,m.role into v_clinic,v_role from public.clinic_memberships m where m.user_id=auth.uid() and m.is_active=true limit 1;
  if v_clinic is null then raise exception 'Active membership not found'; end if;
  if nullif(trim(coalesce(p_content,'')),'') is null and p_media_path is null then raise exception 'Post content or image is required'; end if;

  if v_role='client' then
    select c.id,c.assigned_dietitian_id into v_client,v_group
    from public.client_profiles c where c.clinic_id=v_clinic and c.user_id=auth.uid() and c.is_active=true and c.community_opt_in=true;
    if v_group is null then raise exception 'A dietitian must be assigned before joining the community'; end if;
  elsif v_role='dietitian' then
    select d.id into v_group from public.dietitian_profiles d where d.clinic_id=v_clinic and d.user_id=auth.uid();
  elsif v_role='owner' then
    v_group:=p_dietitian_id;
    if v_group is null then select d.id into v_group from public.dietitian_profiles d where d.clinic_id=v_clinic order by d.id limit 1; end if;
  else
    raise exception 'Community access denied';
  end if;

  if not exists(select 1 from public.dietitian_profiles d where d.id=v_group and d.clinic_id=v_clinic) then raise exception 'Dietitian group not found'; end if;
  insert into public.community_posts(clinic_id,dietitian_id,client_id,author_user_id,content,media_path)
  values(v_clinic,v_group,v_client,auth.uid(),nullif(trim(coalesce(p_content,'')),''),p_media_path)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.create_community_comment_v3(p_post_id uuid,p_content text)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare v_id uuid; v_group uuid;
begin
  if length(trim(coalesce(p_content,'')))<1 then raise exception 'Comment is required'; end if;
  select p.dietitian_id into v_group from public.community_posts p where p.id=p_post_id and not p.is_deleted;
  if v_group is null or not public.can_access_dietitian_group(v_group) then raise exception 'Post is not accessible'; end if;
  insert into public.community_comments(post_id,author_user_id,content) values(p_post_id,auth.uid(),trim(p_content)) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.get_community_feed_v3(p_dietitian_id uuid default null)
returns table(
  id uuid,
  dietitian_id uuid,
  author_user_id uuid,
  author_name text,
  author_role text,
  content text,
  media_path text,
  created_at timestamptz,
  comments jsonb
)
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_group uuid;
begin
  select m.clinic_id,m.role into v_clinic,v_role from public.clinic_memberships m where m.user_id=auth.uid() and m.is_active=true limit 1;
  if v_role='client' then
    select c.assigned_dietitian_id into v_group from public.client_profiles c where c.clinic_id=v_clinic and c.user_id=auth.uid() and c.is_active=true and c.community_opt_in=true;
  elsif v_role='dietitian' then
    select d.id into v_group from public.dietitian_profiles d where d.clinic_id=v_clinic and d.user_id=auth.uid();
  elsif v_role='owner' then
    v_group:=p_dietitian_id;
    if v_group is null then select d.id into v_group from public.dietitian_profiles d where d.clinic_id=v_clinic order by d.id limit 1; end if;
  else
    raise exception 'Community access denied';
  end if;
  if v_group is null or not public.can_access_dietitian_group(v_group) then return; end if;

  return query
  select p.id,p.dietitian_id,p.author_user_id,pr.full_name,m.role::text,p.content,p.media_path,p.created_at,
    coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'author_user_id',c.author_user_id,'author_name',cp.full_name,'content',c.content,'created_at',c.created_at) order by c.created_at)
      from public.community_comments c join public.profiles cp on cp.id=c.author_user_id where c.post_id=p.id),'[]'::jsonb)
  from public.community_posts p
  join public.profiles pr on pr.id=p.author_user_id
  left join public.clinic_memberships m on m.clinic_id=p.clinic_id and m.user_id=p.author_user_id and m.is_active=true
  where p.dietitian_id=v_group and not p.is_deleted
  order by p.created_at desc
  limit 100;
end;
$$;

revoke all on function public.can_access_dietitian_group(uuid) from public;
revoke all on function public.get_client_directory_v3() from public;
revoke all on function public.assign_client_dietitian_v3(uuid,uuid) from public;
revoke all on function public.save_payment_v3(uuid,uuid,uuid,text,text,numeric,text,text,timestamptz) from public;
revoke all on function public.get_dashboard_summary_v3() from public;
revoke all on function public.get_dietitian_day_slots_v3(uuid,date) from public;
revoke all on function public.update_appointment_status_v3(uuid,text,text) from public;
revoke all on function public.create_community_post_v3(text,text,uuid) from public;
revoke all on function public.create_community_comment_v3(uuid,text) from public;
revoke all on function public.get_community_feed_v3(uuid) from public;

grant execute on function public.can_access_dietitian_group(uuid) to authenticated;
grant execute on function public.get_client_directory_v3() to authenticated;
grant execute on function public.assign_client_dietitian_v3(uuid,uuid) to authenticated;
grant execute on function public.save_payment_v3(uuid,uuid,uuid,text,text,numeric,text,text,timestamptz) to authenticated;
grant execute on function public.get_dashboard_summary_v3() to authenticated;
grant execute on function public.get_dietitian_day_slots_v3(uuid,date) to authenticated;
grant execute on function public.update_appointment_status_v3(uuid,text,text) to authenticated;
grant execute on function public.create_community_post_v3(text,text,uuid) to authenticated;
grant execute on function public.create_community_comment_v3(uuid,text) to authenticated;
grant execute on function public.get_community_feed_v3(uuid) to authenticated;

grant select on public.payments,public.meal_photos,public.community_posts,public.community_comments to authenticated;
grant insert,update,delete on public.payments to authenticated;
grant insert,update,delete on public.meal_photos to authenticated;
grant insert on public.community_posts,public.community_comments to authenticated;

commit;

-- ============================================================================
-- 010_personalization_daily_ai_tools.sql
-- ============================================================================

-- NutriClinic AI v4.0
-- Personalized onboarding, daily wellness tracking, AI recipe and food label analysis.
-- Run once after migrations 001-009.

alter table public.client_profiles
  add column if not exists onboarding_completed boolean not null default false,
  add column if not exists onboarding_completed_at timestamptz,
  add column if not exists primary_goal text,
  add column if not exists motivation_reasons text[] not null default '{}',
  add column if not exists current_weight_kg numeric(6,2),
  add column if not exists target_weight_kg numeric(6,2),
  add column if not exists activity_level text,
  add column if not exists calorie_knowledge text,
  add column if not exists diet_style text,
  add column if not exists chronic_conditions text[] not null default '{}',
  add column if not exists additive_reactions text[] not null default '{}',
  add column if not exists water_goal_ml integer not null default 2000,
  add column if not exists goal_pace_kg_per_week numeric(4,2) not null default 0.50,
  add column if not exists daily_tracking_enabled boolean not null default true;

create table if not exists public.daily_water_logs (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  log_date date not null default current_date,
  amount_ml integer not null check (amount_ml between 1 and 5000),
  created_at timestamptz not null default now()
);
create index if not exists daily_water_logs_client_date_idx on public.daily_water_logs(client_id,log_date);

create table if not exists public.activity_logs (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  activity_date date not null default current_date,
  activity_type text not null,
  duration_minutes integer not null default 0 check (duration_minutes between 0 and 1440),
  calories_burned numeric(8,2) not null default 0 check (calories_burned >= 0),
  note text,
  source text not null default 'manual',
  created_at timestamptz not null default now()
);
create index if not exists activity_logs_client_date_idx on public.activity_logs(client_id,activity_date);

create table if not exists public.client_weight_logs (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  weight_date date not null default current_date,
  weight_kg numeric(6,2) not null check (weight_kg between 20 and 500),
  source text not null default 'client',
  created_at timestamptz not null default now(),
  unique(client_id,weight_date)
);
create index if not exists client_weight_logs_client_date_idx on public.client_weight_logs(client_id,weight_date desc);

create table if not exists public.ai_generated_recipes (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid references public.client_profiles(id) on delete cascade,
  created_by uuid not null references public.profiles(id) on delete cascade,
  ingredients text not null,
  meal_type text,
  max_minutes integer,
  max_calories integer,
  recipe jsonb not null,
  is_saved boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists ai_generated_recipes_user_idx on public.ai_generated_recipes(created_by,created_at desc);

create table if not exists public.food_label_scans (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid references public.client_profiles(id) on delete cascade,
  created_by uuid not null references public.profiles(id) on delete cascade,
  filename text,
  result jsonb not null,
  created_at timestamptz not null default now()
);
create index if not exists food_label_scans_user_idx on public.food_label_scans(created_by,created_at desc);

alter table public.daily_water_logs enable row level security;
alter table public.activity_logs enable row level security;
alter table public.client_weight_logs enable row level security;
alter table public.ai_generated_recipes enable row level security;
alter table public.food_label_scans enable row level security;

drop policy if exists water_select_v4 on public.daily_water_logs;
create policy water_select_v4 on public.daily_water_logs for select using (
  client_id=public.current_client_id(clinic_id)
  or public.current_clinic_role(clinic_id) in ('owner','dietitian')
);
drop policy if exists water_insert_v4 on public.daily_water_logs;
create policy water_insert_v4 on public.daily_water_logs for insert with check (
  client_id=public.current_client_id(clinic_id)
);
drop policy if exists water_delete_v4 on public.daily_water_logs;
create policy water_delete_v4 on public.daily_water_logs for delete using (
  client_id=public.current_client_id(clinic_id)
);

drop policy if exists activity_select_v4 on public.activity_logs;
create policy activity_select_v4 on public.activity_logs for select using (
  client_id=public.current_client_id(clinic_id)
  or public.current_clinic_role(clinic_id) in ('owner','dietitian')
);
drop policy if exists activity_insert_v4 on public.activity_logs;
create policy activity_insert_v4 on public.activity_logs for insert with check (
  client_id=public.current_client_id(clinic_id)
);
drop policy if exists activity_delete_v4 on public.activity_logs;
create policy activity_delete_v4 on public.activity_logs for delete using (
  client_id=public.current_client_id(clinic_id)
);

drop policy if exists weight_select_v4 on public.client_weight_logs;
create policy weight_select_v4 on public.client_weight_logs for select using (
  client_id=public.current_client_id(clinic_id)
  or public.current_clinic_role(clinic_id) in ('owner','dietitian')
);
drop policy if exists weight_insert_v4 on public.client_weight_logs;
create policy weight_insert_v4 on public.client_weight_logs for insert with check (
  client_id=public.current_client_id(clinic_id)
  or public.current_clinic_role(clinic_id) in ('owner','dietitian')
);
drop policy if exists weight_update_v4 on public.client_weight_logs;
create policy weight_update_v4 on public.client_weight_logs for update using (
  client_id=public.current_client_id(clinic_id)
  or public.current_clinic_role(clinic_id) in ('owner','dietitian')
) with check (
  client_id=public.current_client_id(clinic_id)
  or public.current_clinic_role(clinic_id) in ('owner','dietitian')
);

drop policy if exists recipes_select_v4 on public.ai_generated_recipes;
create policy recipes_select_v4 on public.ai_generated_recipes for select using (
  created_by=auth.uid()
  or (client_id is not null and public.current_clinic_role(clinic_id) in ('owner','dietitian'))
);
drop policy if exists recipes_insert_v4 on public.ai_generated_recipes;
create policy recipes_insert_v4 on public.ai_generated_recipes for insert with check (created_by=auth.uid());
drop policy if exists recipes_update_v4 on public.ai_generated_recipes;
create policy recipes_update_v4 on public.ai_generated_recipes for update using (created_by=auth.uid()) with check (created_by=auth.uid());

drop policy if exists scans_select_v4 on public.food_label_scans;
create policy scans_select_v4 on public.food_label_scans for select using (
  created_by=auth.uid()
  or (client_id is not null and public.current_clinic_role(clinic_id) in ('owner','dietitian'))
);
drop policy if exists scans_insert_v4 on public.food_label_scans;
create policy scans_insert_v4 on public.food_label_scans for insert with check (created_by=auth.uid());

grant select,insert,delete on public.daily_water_logs,public.activity_logs to authenticated;
grant select,insert,update on public.client_weight_logs to authenticated;
grant select,insert,update on public.ai_generated_recipes to authenticated;
grant select,insert on public.food_label_scans to authenticated;

create or replace function public.get_my_onboarding_v4()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_client public.client_profiles%rowtype;
  v_weight numeric;
begin
  select c.* into v_client
  from public.client_profiles c
  join public.clinic_memberships m on m.clinic_id=c.clinic_id and m.user_id=auth.uid() and m.is_active=true
  where c.user_id=auth.uid() and c.is_active=true
  limit 1;

  if v_client.id is null then raise exception 'Client profile not found'; end if;

  select coalesce(
    (select w.weight_kg from public.client_weight_logs w where w.client_id=v_client.id order by w.weight_date desc,w.created_at desc limit 1),
    (select m.weight_kg from public.measurements m where m.client_id=v_client.id and m.weight_kg is not null order by m.measured_at desc limit 1),
    v_client.current_weight_kg
  ) into v_weight;

  return jsonb_build_object(
    'id',v_client.id,
    'completed',v_client.onboarding_completed,
    'primary_goal',v_client.primary_goal,
    'motivation_reasons',v_client.motivation_reasons,
    'gender',v_client.gender,
    'birth_date',v_client.birth_date,
    'height_cm',v_client.height_cm,
    'current_weight_kg',v_weight,
    'target_weight_kg',v_client.target_weight_kg,
    'activity_level',v_client.activity_level,
    'calorie_knowledge',v_client.calorie_knowledge,
    'diet_style',v_client.diet_style,
    'chronic_conditions',v_client.chronic_conditions,
    'allergies',v_client.allergies,
    'additive_reactions',v_client.additive_reactions,
    'water_goal_ml',v_client.water_goal_ml,
    'goal_pace_kg_per_week',v_client.goal_pace_kg_per_week
  );
end;
$$;

create or replace function public.complete_client_onboarding_v4(
  p_primary_goal text,
  p_motivation_reasons text[],
  p_gender text,
  p_birth_date date,
  p_height_cm numeric,
  p_current_weight_kg numeric,
  p_target_weight_kg numeric,
  p_activity_level text,
  p_calorie_knowledge text,
  p_diet_style text,
  p_chronic_conditions text[],
  p_allergies text[],
  p_additive_reactions text[],
  p_water_goal_ml integer,
  p_goal_pace_kg_per_week numeric
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_client_id uuid;
  v_clinic uuid;
begin
  select c.id,c.clinic_id into v_client_id,v_clinic
  from public.client_profiles c
  where c.user_id=auth.uid() and c.is_active=true
  limit 1;
  if v_client_id is null then raise exception 'Client profile not found'; end if;
  if p_height_cm is null or p_height_cm<100 or p_height_cm>250 then raise exception 'Height is invalid'; end if;
  if p_current_weight_kg is null or p_current_weight_kg<20 or p_current_weight_kg>500 then raise exception 'Weight is invalid'; end if;
  if p_target_weight_kg is null or p_target_weight_kg<20 or p_target_weight_kg>500 then raise exception 'Target weight is invalid'; end if;

  update public.client_profiles set
    primary_goal=nullif(trim(p_primary_goal),''),
    motivation_reasons=coalesce(p_motivation_reasons,'{}'),
    gender=nullif(trim(p_gender),''),
    birth_date=p_birth_date,
    height_cm=p_height_cm,
    current_weight_kg=p_current_weight_kg,
    target_weight_kg=p_target_weight_kg,
    target_text=case when p_target_weight_kg is null then target_text else concat(p_target_weight_kg,' kg') end,
    activity_level=nullif(trim(p_activity_level),''),
    calorie_knowledge=nullif(trim(p_calorie_knowledge),''),
    diet_style=nullif(trim(p_diet_style),''),
    chronic_conditions=coalesce(p_chronic_conditions,'{}'),
    allergies=coalesce(p_allergies,'{}'),
    additive_reactions=coalesce(p_additive_reactions,'{}'),
    water_goal_ml=greatest(500,least(coalesce(p_water_goal_ml,2000),8000)),
    goal_pace_kg_per_week=greatest(0.10,least(coalesce(p_goal_pace_kg_per_week,0.50),1.50)),
    onboarding_completed=true,
    onboarding_completed_at=now(),
    updated_at=now()
  where id=v_client_id;

  insert into public.client_weight_logs(clinic_id,client_id,weight_date,weight_kg,source)
  values(v_clinic,v_client_id,current_date,p_current_weight_kg,'onboarding')
  on conflict(client_id,weight_date) do update set weight_kg=excluded.weight_kg,source='onboarding',created_at=now();

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values(v_clinic,auth.uid(),'client_onboarding_completed','client',v_client_id::text,
    jsonb_build_object('goal',p_primary_goal,'current_weight_kg',p_current_weight_kg,'target_weight_kg',p_target_weight_kg));

  return public.get_my_onboarding_v4();
end;
$$;

create or replace function public.add_water_v4(p_amount_ml integer,p_log_date date default current_date)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare v_client uuid;v_clinic uuid;v_total integer;
begin
  if p_amount_ml<1 or p_amount_ml>5000 then raise exception 'Invalid water amount'; end if;
  select c.id,c.clinic_id into v_client,v_clinic from public.client_profiles c where c.user_id=auth.uid() and c.is_active=true limit 1;
  if v_client is null then raise exception 'Client profile not found'; end if;
  insert into public.daily_water_logs(clinic_id,client_id,log_date,amount_ml) values(v_clinic,v_client,coalesce(p_log_date,current_date),p_amount_ml);
  select coalesce(sum(amount_ml),0)::integer into v_total from public.daily_water_logs where client_id=v_client and log_date=coalesce(p_log_date,current_date);
  return v_total;
end;
$$;

create or replace function public.add_activity_v4(
  p_activity_type text,
  p_duration_minutes integer,
  p_calories_burned numeric,
  p_note text default null,
  p_activity_date date default current_date
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare v_client uuid;v_clinic uuid;v_id uuid;
begin
  select c.id,c.clinic_id into v_client,v_clinic from public.client_profiles c where c.user_id=auth.uid() and c.is_active=true limit 1;
  if v_client is null then raise exception 'Client profile not found'; end if;
  insert into public.activity_logs(clinic_id,client_id,activity_date,activity_type,duration_minutes,calories_burned,note)
  values(v_clinic,v_client,coalesce(p_activity_date,current_date),nullif(trim(p_activity_type),''),greatest(coalesce(p_duration_minutes,0),0),greatest(coalesce(p_calories_burned,0),0),nullif(trim(coalesce(p_note,'')),''))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.add_client_weight_v4(p_weight_kg numeric,p_weight_date date default current_date)
returns numeric
language plpgsql
security definer
set search_path=public
as $$
declare v_client uuid;v_clinic uuid;
begin
  if p_weight_kg<20 or p_weight_kg>500 then raise exception 'Invalid weight'; end if;
  select c.id,c.clinic_id into v_client,v_clinic from public.client_profiles c where c.user_id=auth.uid() and c.is_active=true limit 1;
  if v_client is null then raise exception 'Client profile not found'; end if;
  insert into public.client_weight_logs(clinic_id,client_id,weight_date,weight_kg,source)
  values(v_clinic,v_client,coalesce(p_weight_date,current_date),p_weight_kg,'client')
  on conflict(client_id,weight_date) do update set weight_kg=excluded.weight_kg,source='client',created_at=now();
  update public.client_profiles set current_weight_kg=p_weight_kg,updated_at=now() where id=v_client;
  return p_weight_kg;
end;
$$;

create or replace function public.get_client_daily_hub_v4(p_date date default current_date)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_client public.client_profiles%rowtype;
  v_plan public.meal_plans%rowtype;
  v_water integer;
  v_burned numeric;
  v_weight numeric;
  v_meals jsonb;
  v_consumed jsonb;
  v_weight_history jsonb;
begin
  select c.* into v_client from public.client_profiles c where c.user_id=auth.uid() and c.is_active=true limit 1;
  if v_client.id is null then raise exception 'Client profile not found'; end if;

  select p.* into v_plan
  from public.meal_plans p
  where p.client_id=v_client.id and p.status='active' and coalesce(p_date,current_date) between p.starts_on and p.ends_on
  order by p.created_at desc limit 1;

  select coalesce(sum(w.amount_ml),0)::integer into v_water
  from public.daily_water_logs w where w.client_id=v_client.id and w.log_date=coalesce(p_date,current_date);

  select coalesce(sum(a.calories_burned),0) into v_burned
  from public.activity_logs a where a.client_id=v_client.id and a.activity_date=coalesce(p_date,current_date);

  select coalesce(
    (select w.weight_kg from public.client_weight_logs w where w.client_id=v_client.id and w.weight_date<=coalesce(p_date,current_date) order by w.weight_date desc,w.created_at desc limit 1),
    (select m.weight_kg from public.measurements m where m.client_id=v_client.id and m.weight_kg is not null order by m.measured_at desc limit 1),
    v_client.current_weight_kg
  ) into v_weight;

  if v_plan.id is null then
    v_meals='[]'::jsonb;
    v_consumed=jsonb_build_object('calories',0,'protein_g',0,'carbs_g',0,'fat_g',0);
  else
    select coalesce(jsonb_agg(row_data order by meal_sort,item_sort),'[]'::jsonb) into v_meals
    from (
      select jsonb_build_object(
        'id',i.id,'meal_name',i.meal_name,'food_name',i.food_name,'portion_text',i.portion_text,
        'calories',i.calories,'protein_g',i.protein_g,'carbs_g',i.carbs_g,'fat_g',i.fat_g,
        'completed',exists(select 1 from public.meal_completions mc where mc.item_id=i.id and mc.client_id=v_client.id and mc.consumed_on=coalesce(p_date,current_date))
      ) row_data,
      case i.meal_name when 'Kahvaltı' then 1 when 'Ara Öğün' then 2 when 'Öğle Yemeği' then 3 when 'İkindi Ara Öğünü' then 4 when 'Akşam Yemeği' then 5 when 'Gece Ara Öğünü' then 6 else 9 end meal_sort,
      i.sort_order item_sort
      from public.meal_plan_items i where i.meal_plan_id=v_plan.id
    ) s;

    select jsonb_build_object(
      'calories',coalesce(sum(i.calories),0),
      'protein_g',coalesce(sum(i.protein_g),0),
      'carbs_g',coalesce(sum(i.carbs_g),0),
      'fat_g',coalesce(sum(i.fat_g),0)
    ) into v_consumed
    from public.meal_plan_items i
    where i.meal_plan_id=v_plan.id
      and exists(select 1 from public.meal_completions mc where mc.item_id=i.id and mc.client_id=v_client.id and mc.consumed_on=coalesce(p_date,current_date));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('date',q.weight_date,'weight_kg',q.weight_kg) order by q.weight_date),'[]'::jsonb)
  into v_weight_history
  from (
    select w.weight_date,w.weight_kg from public.client_weight_logs w where w.client_id=v_client.id order by w.weight_date desc limit 14
  ) q;

  return jsonb_build_object(
    'date',coalesce(p_date,current_date),
    'client',jsonb_build_object(
      'id',v_client.id,'name',v_client.full_name,'goal',v_client.primary_goal,'height_cm',v_client.height_cm,
      'current_weight_kg',v_weight,'target_weight_kg',v_client.target_weight_kg,'water_goal_ml',v_client.water_goal_ml,
      'allergies',v_client.allergies,'disliked_foods',v_client.disliked_foods,'diet_style',v_client.diet_style
    ),
    'plan',case when v_plan.id is null then null else jsonb_build_object(
      'id',v_plan.id,'title',v_plan.title,'target_calories',coalesce(v_plan.target_calories,0),
      'target_protein_g',coalesce(v_plan.target_protein_g,0),'target_carbs_g',coalesce(v_plan.target_carbs_g,0),
      'target_fat_g',coalesce(v_plan.target_fat_g,0),'dietitian_note',v_plan.dietitian_note
    ) end,
    'consumed',v_consumed,
    'meals',v_meals,
    'water_ml',v_water,
    'burned_calories',coalesce(v_burned,0),
    'weight_history',v_weight_history
  );
end;
$$;

create or replace function public.get_client_directory_v4()
returns table(
  id uuid,user_id uuid,member_no text,full_name text,email text,phone text,birth_date date,gender text,
  assigned_dietitian_id uuid,assigned_dietitian_name text,height_cm numeric,target_text text,allergies text[],disliked_foods text[],medical_notes text,medications text,
  latest_weight_kg numeric,latest_body_fat_percent numeric,latest_muscle_mass_kg numeric,latest_measurement_at timestamptz,
  loyalty_earned bigint,loyalty_used bigint,loyalty_balance int,payment_total numeric,payment_paid numeric,payment_due numeric,
  last_payment_status text,last_payment_method text,last_payment_service text,last_payment_at timestamptz,created_at timestamptz,
  onboarding_completed boolean,primary_goal text,motivation_reasons text[],target_weight_kg numeric,activity_level text,calorie_knowledge text,diet_style text,
  chronic_conditions text[],additive_reactions text[],water_goal_ml integer
)
language plpgsql
stable
security definer
set search_path=public
as $$
declare v_clinic uuid;v_role public.clinic_role;
begin
  select m.clinic_id,m.role into v_clinic,v_role from public.clinic_memberships m where m.user_id=auth.uid() and m.is_active=true limit 1;
  if v_clinic is null or v_role not in ('owner','dietitian','secretary') then raise exception 'Staff access required'; end if;
  return query
  select c.id,c.user_id,c.member_no,c.full_name,c.email,c.phone,
    case when v_role='secretary' then null else c.birth_date end,
    case when v_role='secretary' then null else c.gender end,
    c.assigned_dietitian_id,dp.full_name,
    case when v_role='secretary' then null else c.height_cm end,
    case when v_role='secretary' then null else c.target_text end,
    case when v_role='secretary' then '{}'::text[] else c.allergies end,
    case when v_role='secretary' then '{}'::text[] else c.disliked_foods end,
    case when v_role='secretary' then null else c.medical_notes end,
    case when v_role='secretary' then null else c.medications end,
    case when v_role='secretary' then null else coalesce(cwl.weight_kg,lm.weight_kg,c.current_weight_kg) end,
    case when v_role='secretary' then null else lm.body_fat_percent end,
    case when v_role='secretary' then null else lm.muscle_mass_kg end,
    case when v_role='secretary' then null else lm.measured_at end,
    case when v_role='secretary' then 0 else coalesce(loyalty.earned,0) end,
    case when v_role='secretary' then 0 else coalesce(loyalty.used,0) end,
    case when v_role='secretary' then 0 else coalesce(w.balance,0) end,
    coalesce(pay.total,0),coalesce(pay.paid,0),greatest(coalesce(pay.total,0)-coalesce(pay.paid,0),0),
    last_pay.status,last_pay.method,last_pay.service_type,last_pay.paid_at,c.created_at,
    case when v_role='secretary' then false else c.onboarding_completed end,
    case when v_role='secretary' then null else c.primary_goal end,
    case when v_role='secretary' then '{}'::text[] else c.motivation_reasons end,
    case when v_role='secretary' then null else c.target_weight_kg end,
    case when v_role='secretary' then null else c.activity_level end,
    case when v_role='secretary' then null else c.calorie_knowledge end,
    case when v_role='secretary' then null else c.diet_style end,
    case when v_role='secretary' then '{}'::text[] else c.chronic_conditions end,
    case when v_role='secretary' then '{}'::text[] else c.additive_reactions end,
    case when v_role='secretary' then null else c.water_goal_ml end
  from public.client_profiles c
  left join public.dietitian_profiles d on d.id=c.assigned_dietitian_id
  left join public.profiles dp on dp.id=d.user_id
  left join lateral (select m.weight_kg,m.body_fat_percent,m.muscle_mass_kg,m.measured_at from public.measurements m where m.client_id=c.id order by m.measured_at desc limit 1) lm on true
  left join lateral (select x.weight_kg from public.client_weight_logs x where x.client_id=c.id order by x.weight_date desc,x.created_at desc limit 1) cwl on true
  left join public.loyalty_wallets w on w.clinic_id=c.clinic_id and w.client_id=c.id
  left join lateral (select coalesce(sum(case when t.points>0 then t.points else 0 end),0)::bigint earned,coalesce(sum(case when t.points<0 then abs(t.points) else 0 end),0)::bigint used from public.loyalty_transactions t where t.wallet_id=w.id) loyalty on true
  left join lateral (select coalesce(sum(case when p.status not in ('cancelled','refunded') then p.amount else 0 end),0)::numeric total,coalesce(sum(case when p.status='paid' then p.amount else 0 end),0)::numeric paid from public.payments p where p.client_id=c.id) pay on true
  left join lateral (select p.status,p.method,p.service_type,p.paid_at from public.payments p where p.client_id=c.id order by p.created_at desc limit 1) last_pay on true
  where c.clinic_id=v_clinic and c.is_active=true
  order by c.created_at desc;
end;
$$;

grant execute on function public.get_my_onboarding_v4() to authenticated;
grant execute on function public.complete_client_onboarding_v4(text,text[],text,date,numeric,numeric,numeric,text,text,text,text[],text[],text[],integer,numeric) to authenticated;
grant execute on function public.add_water_v4(integer,date) to authenticated;
grant execute on function public.add_activity_v4(text,integer,numeric,text,date) to authenticated;
grant execute on function public.add_client_weight_v4(numeric,date) to authenticated;
grant execute on function public.get_client_daily_hub_v4(date) to authenticated;
grant execute on function public.get_client_directory_v4() to authenticated;

-- ============================================================================
-- 011_due_notifications_rewards_stories_motivation.sql
-- ============================================================================

-- NutriClinic AI v5.0
-- Payment due dates/reminders, redemption codes, 24-hour stories,
-- once-daily motivation, and richer daily activity data.
-- Run once after migrations 001-010.

begin;

alter table public.payments
  add column if not exists due_date date,
  add column if not exists reminder_sent_at timestamptz,
  add column if not exists reminder_channel text,
  add column if not exists reminder_count integer not null default 0;

alter table public.payments drop constraint if exists payments_reminder_channel_check;
alter table public.payments add constraint payments_reminder_channel_check
  check (reminder_channel is null or reminder_channel in ('email','sms','in_app'));

create index if not exists payments_due_date_idx
  on public.payments(clinic_id,due_date)
  where status in ('pending','partial');

create table if not exists public.payment_reminder_logs (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  payment_id uuid not null references public.payments(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  channel text not null check (channel in ('email','sms','in_app')),
  recipient text,
  status text not null default 'queued' check (status in ('queued','sent','failed')),
  provider_message_id text,
  error_message text,
  sent_by uuid references public.profiles(id) on delete set null,
  sent_at timestamptz not null default now()
);
create index if not exists payment_reminder_logs_payment_idx on public.payment_reminder_logs(payment_id,sent_at desc);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  recipient_user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null,
  category text not null default 'general',
  metadata jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notifications_recipient_idx on public.notifications(recipient_user_id,created_at desc);

alter table public.reward_redemptions
  add column if not exists redemption_code text,
  add column if not exists code_expires_at timestamptz,
  add column if not exists used_at timestamptz,
  add column if not exists used_by uuid references public.profiles(id) on delete set null;

update public.reward_redemptions
set redemption_code=upper(substr(md5(id::text || random()::text),1,8)),
    code_expires_at=coalesce(code_expires_at,requested_at + interval '90 days')
where redemption_code is null;

create unique index if not exists reward_redemptions_code_uidx
  on public.reward_redemptions(redemption_code)
  where redemption_code is not null;

create table if not exists public.community_stories (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  dietitian_id uuid not null references public.dietitian_profiles(id) on delete cascade,
  client_id uuid references public.client_profiles(id) on delete set null,
  author_user_id uuid not null references public.profiles(id) on delete cascade,
  content text,
  media_path text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours'),
  check (nullif(trim(coalesce(content,'')),'') is not null or media_path is not null)
);
create index if not exists community_stories_group_expiry_idx on public.community_stories(dietitian_id,expires_at desc);

create table if not exists public.client_daily_motivations (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  motivation_date date not null default current_date,
  message text not null,
  shown_at timestamptz,
  created_at timestamptz not null default now(),
  unique(client_id,motivation_date)
);

alter table public.payment_reminder_logs enable row level security;
alter table public.notifications enable row level security;
alter table public.community_stories enable row level security;
alter table public.client_daily_motivations enable row level security;

drop policy if exists payment_reminder_logs_select_staff on public.payment_reminder_logs;
create policy payment_reminder_logs_select_staff on public.payment_reminder_logs for select to authenticated
using (public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary') or client_id=public.current_client_id(clinic_id));

drop policy if exists payment_reminder_logs_insert_staff on public.payment_reminder_logs;
create policy payment_reminder_logs_insert_staff on public.payment_reminder_logs for insert to authenticated
with check (public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary') and sent_by=auth.uid());

drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own on public.notifications for select to authenticated
using (recipient_user_id=auth.uid());

drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications for update to authenticated
using (recipient_user_id=auth.uid()) with check (recipient_user_id=auth.uid());

drop policy if exists notifications_insert_staff on public.notifications;
create policy notifications_insert_staff on public.notifications for insert to authenticated
with check (public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary'));

drop policy if exists community_stories_select_group on public.community_stories;
create policy community_stories_select_group on public.community_stories for select to authenticated
using (expires_at>now() and public.can_access_dietitian_group(dietitian_id));

drop policy if exists community_stories_insert_group on public.community_stories;
create policy community_stories_insert_group on public.community_stories for insert to authenticated
with check (author_user_id=auth.uid() and public.can_access_dietitian_group(dietitian_id));

drop policy if exists community_stories_delete_own on public.community_stories;
create policy community_stories_delete_own on public.community_stories for delete to authenticated
using (author_user_id=auth.uid() or public.current_clinic_role(clinic_id)='owner');

drop policy if exists motivations_select_own on public.client_daily_motivations;
create policy motivations_select_own on public.client_daily_motivations for select to authenticated
using (client_id=public.current_client_id(clinic_id));

-- Story images share the existing private community-media bucket.
drop policy if exists community_media_select_group on storage.objects;
create policy community_media_select_group on storage.objects for select to authenticated
using (
  bucket_id='community-media'
  and (
    exists (
      select 1 from public.community_posts p
      where p.media_path=name and not p.is_deleted and public.can_access_dietitian_group(p.dietitian_id)
    )
    or exists (
      select 1 from public.community_stories s
      where s.media_path=name and s.expires_at>now() and public.can_access_dietitian_group(s.dietitian_id)
    )
  )
);

create or replace function public.save_payment_v5(
  p_payment_id uuid,
  p_client_id uuid,
  p_appointment_id uuid,
  p_service_type text,
  p_description text,
  p_amount numeric,
  p_status text,
  p_method text,
  p_paid_at timestamptz,
  p_due_date date
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_id uuid;
  v_paid_at timestamptz;
begin
  select m.clinic_id,m.role into v_clinic,v_role
  from public.clinic_memberships m where m.user_id=auth.uid() and m.is_active=true limit 1;
  if v_clinic is null or v_role not in ('owner','secretary') then raise exception 'Owner or secretary access required'; end if;
  if p_amount<0 then raise exception 'Payment amount cannot be negative'; end if;
  if p_status not in ('pending','partial','paid','refunded','cancelled') then raise exception 'Invalid payment status'; end if;
  if p_method is not null and p_method not in ('cash','card','iban','other') then raise exception 'Invalid payment method'; end if;
  if not exists(select 1 from public.client_profiles c where c.id=p_client_id and c.clinic_id=v_clinic and c.is_active=true) then raise exception 'Client not found'; end if;

  v_paid_at := case when p_status='paid' then coalesce(p_paid_at,now()) else p_paid_at end;
  if p_payment_id is null then
    insert into public.payments(clinic_id,client_id,appointment_id,service_type,description,amount,status,method,paid_at,due_date,recorded_by)
    values(v_clinic,p_client_id,p_appointment_id,nullif(trim(p_service_type),''),nullif(trim(coalesce(p_description,'')),''),p_amount,p_status,p_method,v_paid_at,p_due_date,auth.uid())
    returning id into v_id;
  else
    update public.payments set
      appointment_id=p_appointment_id,service_type=nullif(trim(p_service_type),''),description=nullif(trim(coalesce(p_description,'')),''),
      amount=p_amount,status=p_status,method=p_method,paid_at=v_paid_at,due_date=p_due_date,recorded_by=auth.uid(),updated_at=now()
    where id=p_payment_id and clinic_id=v_clinic returning id into v_id;
    if v_id is null then raise exception 'Payment not found'; end if;
  end if;

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values(v_clinic,auth.uid(),case when p_payment_id is null then 'payment_created' else 'payment_updated' end,'payment',v_id::text,
    jsonb_build_object('client_id',p_client_id,'amount',p_amount,'status',p_status,'method',p_method,'service_type',p_service_type,'due_date',p_due_date));
  return v_id;
end;
$$;

create or replace function public.get_payment_due_summary_v5()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_client uuid;
  v_dietitian uuid;
  v_rows jsonb;
begin
  select clinic_id,role into v_clinic,v_role from public.clinic_memberships where user_id=auth.uid() and is_active=true limit 1;
  if v_clinic is null then raise exception 'Active membership not found'; end if;
  select id into v_client from public.client_profiles where clinic_id=v_clinic and user_id=auth.uid() and is_active=true;
  select id into v_dietitian from public.dietitian_profiles where clinic_id=v_clinic and user_id=auth.uid();

  select coalesce(jsonb_agg(to_jsonb(x) order by x.due_date nulls last,x.created_at desc),'[]'::jsonb) into v_rows
  from (
    select p.id,p.client_id,p.service_type,p.description,p.amount,p.currency,p.status,p.method,p.paid_at,p.due_date,p.reminder_sent_at,p.reminder_channel,p.reminder_count,p.created_at,
      c.full_name client_name,c.member_no,c.email,c.phone,c.user_id,
      case when p.due_date is null then null else (p.due_date-current_date)::int end days_remaining
    from public.payments p join public.client_profiles c on c.id=p.client_id
    where p.clinic_id=v_clinic and p.status in ('pending','partial')
      and (
        v_role in ('owner','secretary')
        or (v_role='dietitian' and c.assigned_dietitian_id=v_dietitian)
        or (v_role='client' and c.id=v_client)
      )
  ) x;
  return jsonb_build_object('role',v_role,'rows',v_rows);
end;
$$;

create or replace function public.record_payment_reminder_v5(
  p_payment_id uuid,
  p_channel text,
  p_recipient text,
  p_status text,
  p_provider_message_id text default null,
  p_error_message text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_dietitian uuid;
  v_payment public.payments%rowtype;
  v_client public.client_profiles%rowtype;
  v_title text;
  v_body text;
begin
  select clinic_id,role into v_clinic,v_role
  from public.clinic_memberships where user_id=auth.uid() and is_active=true limit 1;
  if v_clinic is null or v_role not in ('owner','dietitian','secretary') then
    raise exception 'Payment reminder access required';
  end if;
  if p_channel not in ('email','sms','in_app') then raise exception 'Invalid reminder channel'; end if;
  if p_status not in ('queued','sent','failed') then raise exception 'Invalid reminder status'; end if;

  select * into v_payment from public.payments where id=p_payment_id and clinic_id=v_clinic for update;
  if v_payment.id is null then raise exception 'Payment not found'; end if;
  select * into v_client from public.client_profiles where id=v_payment.client_id and clinic_id=v_clinic;
  if v_client.id is null then raise exception 'Client not found'; end if;
  if v_role='dietitian' then
    select id into v_dietitian from public.dietitian_profiles where clinic_id=v_clinic and user_id=auth.uid();
    if v_dietitian is null or v_client.assigned_dietitian_id is distinct from v_dietitian then
      raise exception 'This client is not assigned to you';
    end if;
  end if;

  insert into public.payment_reminder_logs(
    clinic_id,payment_id,client_id,channel,recipient,status,provider_message_id,error_message,sent_by
  ) values(
    v_clinic,v_payment.id,v_client.id,p_channel,nullif(trim(coalesce(p_recipient,'')),''),p_status,
    nullif(trim(coalesce(p_provider_message_id,'')),''),nullif(trim(coalesce(p_error_message,'')),''),auth.uid()
  );

  if p_status='sent' then
    update public.payments set reminder_sent_at=now(),reminder_channel=p_channel,
      reminder_count=coalesce(reminder_count,0)+1,updated_at=now()
    where id=v_payment.id;
    v_title:='Ödeme hatırlatması';
    v_body:=coalesce(v_payment.service_type,'Klinik hizmeti')||' için ödeme hatırlatmanız gönderildi.';
    if v_client.user_id is not null then
      insert into public.notifications(clinic_id,recipient_user_id,title,body,category,metadata)
      values(v_clinic,v_client.user_id,v_title,v_body,'payment_reminder',
        jsonb_build_object('payment_id',v_payment.id,'due_date',v_payment.due_date,'channel',p_channel));
    end if;
  end if;

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values(v_clinic,auth.uid(),case when p_status='sent' then 'payment_reminder_sent' else 'payment_reminder_failed' end,
    'payment',v_payment.id::text,jsonb_build_object('channel',p_channel,'recipient',p_recipient,
      'provider_message_id',p_provider_message_id,'error',p_error_message,'status',p_status));

  return jsonb_build_object('payment_id',v_payment.id,'status',p_status,'reminder_count',
    case when p_status='sent' then coalesce(v_payment.reminder_count,0)+1 else coalesce(v_payment.reminder_count,0) end);
end;
$$;

create or replace function public.redeem_reward(p_reward_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid; v_client_id uuid; v_wallet_id uuid; v_balance int; v_new_balance int;
  v_reward_name text; v_points_cost int; v_stock int; v_transaction_id uuid; v_redemption_id uuid; v_code text;
begin
  select c.clinic_id,c.id into v_clinic,v_client_id
  from public.client_profiles c join public.clinic_memberships m on m.clinic_id=c.clinic_id and m.user_id=c.user_id and m.role='client' and m.is_active=true
  where c.user_id=auth.uid() and c.is_active=true limit 1;
  if v_client_id is null then raise exception 'Active client profile not found'; end if;

  select r.name,r.points_cost,r.stock into v_reward_name,v_points_cost,v_stock from public.rewards r
  where r.id=p_reward_id and r.clinic_id=v_clinic and r.is_active=true for update;
  if v_reward_name is null then raise exception 'Reward is unavailable'; end if;
  if v_stock is not null and v_stock<=0 then raise exception 'Reward is out of stock'; end if;

  insert into public.loyalty_wallets(clinic_id,client_id,balance) values(v_clinic,v_client_id,0) on conflict(clinic_id,client_id) do nothing;
  select id,balance into v_wallet_id,v_balance from public.loyalty_wallets where clinic_id=v_clinic and client_id=v_client_id for update;
  if v_balance<v_points_cost then raise exception 'Insufficient loyalty points'; end if;
  v_new_balance:=v_balance-v_points_cost;
  update public.loyalty_wallets set balance=v_new_balance,updated_at=now() where id=v_wallet_id;

  if v_stock is not null then
    update public.rewards set stock=v_stock-1 where id=p_reward_id;
    insert into public.reward_stock_movements(clinic_id,reward_id,quantity_change,stock_after,reason,created_by)
    values(v_clinic,p_reward_id,-1,v_stock-1,'Danışan ödül kullanımı',auth.uid());
  end if;

  insert into public.loyalty_transactions(wallet_id,transaction_type,points,reason,reward_id,created_by,balance_after)
  values(v_wallet_id,'redeemed',-v_points_cost,'Ödül kullanımı: '||v_reward_name,p_reward_id,auth.uid(),v_new_balance)
  returning id into v_transaction_id;

  loop
    v_code:=upper(substr(md5(gen_random_uuid()::text || clock_timestamp()::text),1,8));
    exit when not exists(select 1 from public.reward_redemptions where redemption_code=v_code);
  end loop;

  insert into public.reward_redemptions(clinic_id,client_id,reward_id,loyalty_transaction_id,reward_name,points_spent,status,requested_at,redemption_code,code_expires_at,updated_at)
  values(v_clinic,v_client_id,p_reward_id,v_transaction_id,v_reward_name,v_points_cost,'requested',now(),v_code,now()+interval '90 days',now())
  returning id into v_redemption_id;

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values(v_clinic,auth.uid(),'reward_redeemed','reward_redemption',v_redemption_id::text,jsonb_build_object('reward_id',p_reward_id,'reward_name',v_reward_name,'points_spent',v_points_cost,'balance_after',v_new_balance,'redemption_code',v_code));

  return jsonb_build_object('redemption_id',v_redemption_id,'reward_name',v_reward_name,'points_spent',v_points_cost,'balance_after',v_new_balance,'redemption_code',v_code,'code_expires_at',now()+interval '90 days');
end;
$$;

-- Return columns changed from migration 008; PostgreSQL requires dropping the old function first.
drop function if exists public.get_reward_redemptions(uuid);

create or replace function public.get_reward_redemptions(p_client_id uuid default null)
returns table(
  id uuid,client_id uuid,reward_name text,points_spent integer,status text,requested_at timestamptz,
  fulfilled_at timestamptz,note text,redemption_code text,code_expires_at timestamptz,used_at timestamptz,used_by uuid
)
language plpgsql
stable
security definer
set search_path=public
as $$
declare v_clinic uuid; v_role public.clinic_role; v_own_client uuid; v_dietitian uuid;
begin
  select clinic_id,role into v_clinic,v_role from public.clinic_memberships where user_id=auth.uid() and is_active=true limit 1;
  select id into v_own_client from public.client_profiles where clinic_id=v_clinic and user_id=auth.uid() and is_active=true;
  select id into v_dietitian from public.dietitian_profiles where clinic_id=v_clinic and user_id=auth.uid();
  if v_role='client' then
    return query select r.id,r.client_id,r.reward_name,r.points_spent,r.status,r.requested_at,r.fulfilled_at,r.note,r.redemption_code,r.code_expires_at,r.used_at,r.used_by
      from public.reward_redemptions r where r.clinic_id=v_clinic and r.client_id=v_own_client order by r.requested_at desc;
  elsif v_role in ('owner','dietitian') then
    return query select r.id,r.client_id,r.reward_name,r.points_spent,r.status,r.requested_at,r.fulfilled_at,r.note,r.redemption_code,r.code_expires_at,r.used_at,r.used_by
      from public.reward_redemptions r join public.client_profiles c on c.id=r.client_id
      where r.clinic_id=v_clinic and (p_client_id is null or r.client_id=p_client_id)
        and (v_role='owner' or c.assigned_dietitian_id=v_dietitian) order by r.requested_at desc;
  else raise exception 'Access denied'; end if;
end;
$$;

create or replace function public.fulfill_reward_redemption_v5(p_code text)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_clinic uuid; v_role public.clinic_role; v_dietitian uuid; v_red public.reward_redemptions%rowtype; v_client public.client_profiles%rowtype;
begin
  select clinic_id,role into v_clinic,v_role from public.clinic_memberships where user_id=auth.uid() and is_active=true limit 1;
  if v_role not in ('owner','dietitian') then raise exception 'Owner or dietitian access required'; end if;
  select id into v_dietitian from public.dietitian_profiles where clinic_id=v_clinic and user_id=auth.uid();
  select * into v_red from public.reward_redemptions where clinic_id=v_clinic and redemption_code=upper(trim(p_code)) for update;
  if v_red.id is null then raise exception 'Reward code not found'; end if;
  select * into v_client from public.client_profiles where id=v_red.client_id;
  if v_role='dietitian' and v_client.assigned_dietitian_id is distinct from v_dietitian then raise exception 'This client is not assigned to you'; end if;
  if v_red.status in ('fulfilled','cancelled') or v_red.used_at is not null then raise exception 'This reward code has already been used'; end if;
  if v_red.code_expires_at is not null and v_red.code_expires_at<now() then raise exception 'Reward code has expired'; end if;

  update public.reward_redemptions set status='fulfilled',fulfilled_at=now(),used_at=now(),used_by=auth.uid(),updated_at=now() where id=v_red.id;
  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values(v_clinic,auth.uid(),'reward_fulfilled','reward_redemption',v_red.id::text,jsonb_build_object('client_id',v_red.client_id,'reward_name',v_red.reward_name,'redemption_code',v_red.redemption_code));
  return jsonb_build_object('redemption_id',v_red.id,'client_id',v_red.client_id,'client_name',v_client.full_name,'reward_name',v_red.reward_name,'code',v_red.redemption_code);
end;
$$;

create or replace function public.create_community_story_v5(p_content text,p_media_path text,p_dietitian_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare v_clinic uuid; v_role public.clinic_role; v_dietitian uuid; v_client uuid; v_id uuid;
begin
  select clinic_id,role into v_clinic,v_role from public.clinic_memberships where user_id=auth.uid() and is_active=true limit 1;
  if v_role='owner' then v_dietitian:=p_dietitian_id;
  elsif v_role='dietitian' then select id into v_dietitian from public.dietitian_profiles where clinic_id=v_clinic and user_id=auth.uid();
  elsif v_role='client' then select id,assigned_dietitian_id into v_client,v_dietitian from public.client_profiles where clinic_id=v_clinic and user_id=auth.uid() and is_active=true;
  else raise exception 'Access denied'; end if;
  if v_dietitian is null or not public.can_access_dietitian_group(v_dietitian) then raise exception 'Dietitian group unavailable'; end if;
  insert into public.community_stories(clinic_id,dietitian_id,client_id,author_user_id,content,media_path)
  values(v_clinic,v_dietitian,v_client,auth.uid(),nullif(trim(coalesce(p_content,'')),''),p_media_path) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.get_community_stories_v5(p_dietitian_id uuid default null)
returns table(id uuid,dietitian_id uuid,author_user_id uuid,author_name text,author_role text,content text,media_path text,created_at timestamptz,expires_at timestamptz)
language plpgsql
stable
security definer
set search_path=public
as $$
declare v_clinic uuid; v_role public.clinic_role; v_group uuid;
begin
  select clinic_id,role into v_clinic,v_role from public.clinic_memberships where user_id=auth.uid() and is_active=true limit 1;
  if v_role='owner' then v_group:=p_dietitian_id;
  elsif v_role='dietitian' then select id into v_group from public.dietitian_profiles where clinic_id=v_clinic and user_id=auth.uid();
  elsif v_role='client' then select assigned_dietitian_id into v_group from public.client_profiles where clinic_id=v_clinic and user_id=auth.uid() and is_active=true;
  else raise exception 'Access denied'; end if;
  if v_group is null or not public.can_access_dietitian_group(v_group) then return; end if;
  return query select s.id,s.dietitian_id,s.author_user_id,p.full_name,m.role::text,s.content,s.media_path,s.created_at,s.expires_at
    from public.community_stories s join public.profiles p on p.id=s.author_user_id
    join public.clinic_memberships m on m.clinic_id=s.clinic_id and m.user_id=s.author_user_id and m.is_active=true
    where s.dietitian_id=v_group and s.expires_at>now() order by s.created_at desc;
end;
$$;

create or replace function public.claim_daily_motivation_v5()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_client public.client_profiles%rowtype; v_existing public.client_daily_motivations%rowtype; v_messages text[]; v_message text; v_index int;
begin
  select * into v_client from public.client_profiles where user_id=auth.uid() and is_active=true limit 1;
  if v_client.id is null then return null; end if;
  select * into v_existing from public.client_daily_motivations where client_id=v_client.id and motivation_date=current_date;
  if v_existing.id is not null and v_existing.shown_at is not null then return null; end if;
  v_messages:=array[
    'Bugün mükemmel olmak zorunda değilsin; planına geri döndüğün her seçim ilerlemedir.',
    'Küçük ve sürdürülebilir adımlar, kısa süreli büyük değişimlerden daha değerlidir.',
    'Bir öğün planın dışına çıktıysa gün bitmedi. Bir sonraki seçimin yeni başlangıcın olabilir.',
    'Vücudunu cezalandırmak için değil, iyi hissetmesini desteklemek için besleniyorsun.',
    'Bugünkü hedefin yalnızca devam etmek: su, hareket ve planındaki bir sonraki öğün.',
    'İlerlemeni yalnızca tartı değil; enerjin, uyku düzenin ve kazandığın alışkanlıklar da gösterir.',
    'Kendine verdiğin sözlerin en önemlisi, zor günlerde bile tamamen vazgeçmemektir.'
  ];
  v_index:=1+(abs(hashtext(v_client.id::text||current_date::text)) % array_length(v_messages,1));
  v_message:=v_messages[v_index];
  insert into public.client_daily_motivations(clinic_id,client_id,motivation_date,message,shown_at)
  values(v_client.clinic_id,v_client.id,current_date,v_message,now())
  on conflict(client_id,motivation_date) do update set shown_at=coalesce(public.client_daily_motivations.shown_at,now())
  returning * into v_existing;
  return jsonb_build_object('message',v_existing.message,'date',v_existing.motivation_date,'goal',v_client.primary_goal);
end;
$$;

create or replace function public.get_client_daily_hub_v4(p_date date default current_date)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_client public.client_profiles%rowtype; v_plan public.meal_plans%rowtype; v_water integer; v_burned numeric; v_weight numeric;
  v_meals jsonb; v_consumed jsonb; v_weight_history jsonb; v_activities jsonb;
begin
  select c.* into v_client from public.client_profiles c where c.user_id=auth.uid() and c.is_active=true limit 1;
  if v_client.id is null then raise exception 'Client profile not found'; end if;
  select p.* into v_plan from public.meal_plans p where p.client_id=v_client.id and p.status='active' and coalesce(p_date,current_date) between p.starts_on and p.ends_on order by p.created_at desc limit 1;
  select coalesce(sum(w.amount_ml),0)::integer into v_water from public.daily_water_logs w where w.client_id=v_client.id and w.log_date=coalesce(p_date,current_date);
  select coalesce(sum(a.calories_burned),0) into v_burned from public.activity_logs a where a.client_id=v_client.id and a.activity_date=coalesce(p_date,current_date);
  select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'activity_type',a.activity_type,'duration_minutes',a.duration_minutes,'calories_burned',a.calories_burned,'note',a.note,'created_at',a.created_at) order by a.created_at desc),'[]'::jsonb)
    into v_activities from public.activity_logs a where a.client_id=v_client.id and a.activity_date=coalesce(p_date,current_date);
  select coalesce((select w.weight_kg from public.client_weight_logs w where w.client_id=v_client.id and w.weight_date<=coalesce(p_date,current_date) order by w.weight_date desc,w.created_at desc limit 1),(select m.weight_kg from public.measurements m where m.client_id=v_client.id and m.weight_kg is not null order by m.measured_at desc limit 1),v_client.current_weight_kg) into v_weight;
  if v_plan.id is null then v_meals='[]'::jsonb;v_consumed=jsonb_build_object('calories',0,'protein_g',0,'carbs_g',0,'fat_g',0);
  else
    select coalesce(jsonb_agg(row_data order by meal_sort,item_sort),'[]'::jsonb) into v_meals from (
      select jsonb_build_object('id',i.id,'meal_name',i.meal_name,'food_name',i.food_name,'portion_text',i.portion_text,'calories',i.calories,'protein_g',i.protein_g,'carbs_g',i.carbs_g,'fat_g',i.fat_g,'completed',exists(select 1 from public.meal_completions mc where mc.item_id=i.id and mc.client_id=v_client.id and mc.consumed_on=coalesce(p_date,current_date))) row_data,
      case i.meal_name when 'Kahvaltı' then 1 when 'Ara Öğün' then 2 when 'Öğle Yemeği' then 3 when 'İkindi Ara Öğünü' then 4 when 'Akşam Yemeği' then 5 when 'Gece Ara Öğünü' then 6 else 9 end meal_sort,i.sort_order item_sort
      from public.meal_plan_items i where i.meal_plan_id=v_plan.id) s;
    select jsonb_build_object('calories',coalesce(sum(i.calories),0),'protein_g',coalesce(sum(i.protein_g),0),'carbs_g',coalesce(sum(i.carbs_g),0),'fat_g',coalesce(sum(i.fat_g),0)) into v_consumed
    from public.meal_plan_items i where i.meal_plan_id=v_plan.id and exists(select 1 from public.meal_completions mc where mc.item_id=i.id and mc.client_id=v_client.id and mc.consumed_on=coalesce(p_date,current_date));
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('date',q.weight_date,'weight_kg',q.weight_kg) order by q.weight_date),'[]'::jsonb) into v_weight_history from (select w.weight_date,w.weight_kg from public.client_weight_logs w where w.client_id=v_client.id order by w.weight_date desc limit 14) q;
  return jsonb_build_object('date',coalesce(p_date,current_date),'client',jsonb_build_object('id',v_client.id,'name',v_client.full_name,'goal',v_client.primary_goal,'height_cm',v_client.height_cm,'current_weight_kg',v_weight,'target_weight_kg',v_client.target_weight_kg,'water_goal_ml',v_client.water_goal_ml,'allergies',v_client.allergies,'disliked_foods',v_client.disliked_foods,'diet_style',v_client.diet_style),
    'plan',case when v_plan.id is null then null else jsonb_build_object('id',v_plan.id,'title',v_plan.title,'target_calories',coalesce(v_plan.target_calories,0),'target_protein_g',coalesce(v_plan.target_protein_g,0),'target_carbs_g',coalesce(v_plan.target_carbs_g,0),'target_fat_g',coalesce(v_plan.target_fat_g,0),'dietitian_note',v_plan.dietitian_note) end,
    'consumed',v_consumed,'meals',v_meals,'water_ml',v_water,'burned_calories',coalesce(v_burned,0),'activities',v_activities,'weight_history',v_weight_history);
end;
$$;

grant execute on function public.save_payment_v5(uuid,uuid,uuid,text,text,numeric,text,text,timestamptz,date) to authenticated;
grant execute on function public.get_payment_due_summary_v5() to authenticated;
grant execute on function public.record_payment_reminder_v5(uuid,text,text,text,text,text) to authenticated;
grant execute on function public.get_reward_redemptions(uuid) to authenticated;
grant execute on function public.fulfill_reward_redemption_v5(text) to authenticated;
grant execute on function public.create_community_story_v5(text,text,uuid) to authenticated;
grant execute on function public.get_community_stories_v5(uuid) to authenticated;
grant execute on function public.claim_daily_motivation_v5() to authenticated;

commit;

-- ============================================================================
-- 012_realtime_notification_center.sql
-- ============================================================================

-- NutriClinic AI v5.1
-- Realtime in-app notification center for meal plans, measurements,
-- payment approval and approaching/overdue payments.
-- Run once after migrations 001-011.

begin;

alter table public.notifications
  add column if not exists action_view text,
  add column if not exists dedupe_key text;

create index if not exists notifications_unread_recipient_idx
  on public.notifications(recipient_user_id,created_at desc)
  where read_at is null;

create unique index if not exists notifications_recipient_dedupe_uidx
  on public.notifications(recipient_user_id,dedupe_key)
  where dedupe_key is not null;

alter table public.notifications replica identity full;

grant select,update on public.notifications to authenticated;

-- Idempotently enable Postgres Changes for the notification table.
do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime')
     and not exists(
       select 1 from pg_publication_tables
       where pubname='supabase_realtime' and schemaname='public' and tablename='notifications'
     ) then
    execute 'alter publication supabase_realtime add table public.notifications';
  end if;
end;
$$;

create or replace function public.create_app_notification_v5(
  p_clinic_id uuid,
  p_recipient_user_id uuid,
  p_title text,
  p_body text,
  p_category text,
  p_action_view text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_dedupe_key text default null
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_id uuid;
begin
  if p_clinic_id is null or p_recipient_user_id is null then return null; end if;

  if nullif(trim(coalesce(p_dedupe_key,'')),'') is not null then
    select id into v_id
    from public.notifications
    where recipient_user_id=p_recipient_user_id and dedupe_key=p_dedupe_key
    limit 1;

    if v_id is not null then
      update public.notifications
      set title=p_title,
          body=p_body,
          category=coalesce(nullif(trim(p_category),''),'general'),
          action_view=nullif(trim(coalesce(p_action_view,'')),''),
          metadata=coalesce(p_metadata,'{}'::jsonb)
      where id=v_id;
      return v_id;
    end if;
  end if;

  insert into public.notifications(
    clinic_id,recipient_user_id,title,body,category,action_view,metadata,dedupe_key
  ) values(
    p_clinic_id,p_recipient_user_id,p_title,p_body,
    coalesce(nullif(trim(p_category),''),'general'),
    nullif(trim(coalesce(p_action_view,'')),''),
    coalesce(p_metadata,'{}'::jsonb),
    nullif(trim(coalesce(p_dedupe_key,'')),'')
  ) returning id into v_id;

  return v_id;
exception when unique_violation then
  select id into v_id from public.notifications
  where recipient_user_id=p_recipient_user_id and dedupe_key=p_dedupe_key limit 1;
  return v_id;
end;
$$;

create or replace function public.notify_meal_plan_change_v5()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_user uuid;
  v_title text;
  v_body text;
  v_event text;
begin
  if new.status::text <> 'active' then return new; end if;

  select user_id into v_user
  from public.client_profiles
  where id=new.client_id and clinic_id=new.clinic_id and is_active=true;
  if v_user is null then return new; end if;

  if tg_op='INSERT' or (tg_op='UPDATE' and old.status::text is distinct from 'active') then
    v_title:='Yeni beslenme planınız hazır';
    v_body:=new.title||' planınız yayınlandı. '||to_char(new.starts_on,'DD.MM.YYYY')||' - '||to_char(new.ends_on,'DD.MM.YYYY');
    v_event:='published';
  elsif tg_op='UPDATE' then
    v_title:='Beslenme planınız güncellendi';
    v_body:=new.title||' planınız diyetisyeniniz tarafından güncellendi.';
    v_event:='updated:'||extract(epoch from new.updated_at)::bigint::text;
  else
    return new;
  end if;

  perform public.create_app_notification_v5(
    new.clinic_id,v_user,v_title,v_body,'meal_plan','mealPlans',
    jsonb_build_object('meal_plan_id',new.id,'starts_on',new.starts_on,'ends_on',new.ends_on),
    'meal_plan:'||new.id::text||':'||v_event
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_meal_plan_change_v5 on public.meal_plans;
create trigger trg_notify_meal_plan_change_v5
after insert or update on public.meal_plans
for each row execute function public.notify_meal_plan_change_v5();

create or replace function public.notify_measurement_change_v5()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_user uuid;
  v_values text[]:=array[]::text[];
  v_body text;
begin
  select user_id into v_user
  from public.client_profiles
  where id=new.client_id and clinic_id=new.clinic_id and is_active=true;
  if v_user is null then return new; end if;

  if new.weight_kg is not null then v_values:=array_append(v_values,'Kilo: '||trim(to_char(new.weight_kg,'FM999990D00'))||' kg'); end if;
  if new.body_fat_percent is not null then v_values:=array_append(v_values,'Yağ: %'||trim(to_char(new.body_fat_percent,'FM990D00'))); end if;
  if new.muscle_mass_kg is not null then v_values:=array_append(v_values,'Kas: '||trim(to_char(new.muscle_mass_kg,'FM999990D00'))||' kg'); end if;
  v_body:=case when cardinality(v_values)>0 then array_to_string(v_values,' • ') else 'Yeni ölçüm sonuçlarınız profilinize eklendi.' end;

  perform public.create_app_notification_v5(
    new.clinic_id,v_user,
    case when tg_op='INSERT' then 'Yeni ölçüm sonuçlarınız hazır' else 'Ölçüm sonuçlarınız güncellendi' end,
    v_body,'measurement','measurements',
    jsonb_build_object('measurement_id',new.id,'measured_at',new.measured_at),
    'measurement:'||new.id::text||':'||case when tg_op='INSERT' then 'created' else 'updated:'||extract(epoch from now())::bigint::text end
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_measurement_change_v5 on public.measurements;
create trigger trg_notify_measurement_change_v5
after insert or update on public.measurements
for each row execute function public.notify_measurement_change_v5();

create or replace function public.notify_payment_status_v5()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_user uuid;
  v_service text;
  v_amount text;
begin
  if new.status <> 'paid' or (tg_op='UPDATE' and old.status='paid') then return new; end if;

  select user_id into v_user
  from public.client_profiles
  where id=new.client_id and clinic_id=new.clinic_id and is_active=true;
  if v_user is null then return new; end if;

  v_service:=coalesce(nullif(trim(new.service_type),''),'Klinik hizmeti');
  v_amount:=trim(to_char(new.amount,'FM999999990D00'))||' '||coalesce(new.currency,'TRY');
  perform public.create_app_notification_v5(
    new.clinic_id,v_user,'Ödemeniz onaylandı',
    v_service||' için '||v_amount||' tutarındaki ödemeniz alındı.',
    'payment_paid','settings',
    jsonb_build_object('payment_id',new.id,'amount',new.amount,'currency',new.currency,'method',new.method,'paid_at',new.paid_at),
    'payment_paid:'||new.id::text
  );
  return new;
end;
$$;

drop trigger if exists trg_notify_payment_status_v5 on public.payments;
create trigger trg_notify_payment_status_v5
after insert or update of status on public.payments
for each row execute function public.notify_payment_status_v5();

create or replace function public.sync_due_notifications_v5()
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_client uuid;
  v_dietitian uuid;
  v_row record;
  v_days integer;
  v_phase text;
  v_title text;
  v_body text;
  v_action text;
  v_count integer:=0;
begin
  select clinic_id,role into v_clinic,v_role
  from public.clinic_memberships
  where user_id=auth.uid() and is_active=true
  limit 1;
  if v_clinic is null then return 0; end if;

  select id into v_client from public.client_profiles
  where clinic_id=v_clinic and user_id=auth.uid() and is_active=true limit 1;
  select id into v_dietitian from public.dietitian_profiles
  where clinic_id=v_clinic and user_id=auth.uid() limit 1;

  for v_row in
    select p.id,p.client_id,p.service_type,p.amount,p.currency,p.due_date,c.full_name,c.user_id
    from public.payments p
    join public.client_profiles c on c.id=p.client_id and c.clinic_id=p.clinic_id
    where p.clinic_id=v_clinic
      and p.status in ('pending','partial')
      and p.due_date is not null
      and p.due_date<=current_date+7
      and (
        (v_role='client' and c.id=v_client)
        or v_role in ('owner','secretary')
        or (v_role='dietitian' and c.assigned_dietitian_id=v_dietitian)
      )
  loop
    v_days:=(v_row.due_date-current_date)::integer;
    v_phase:=case
      when v_days<0 then 'overdue'
      when v_days=0 then 'today'
      when v_days=1 then '1day'
      when v_days<=3 then '3days'
      else '7days'
    end;

    if v_role='client' then
      v_title:=case when v_days<0 then 'Ödemenizin tarihi geçti' when v_days=0 then 'Ödemeniz bugün' else 'Yaklaşan ödemeniz var' end;
      v_body:=coalesce(v_row.service_type,'Klinik hizmeti')||' için '||trim(to_char(v_row.amount,'FM999999990D00'))||' '||coalesce(v_row.currency,'TRY')||
        case when v_days<0 then ' ödeme '||abs(v_days)||' gün gecikti.' when v_days=0 then ' ödeme bugün bekleniyor.' else ' ödemeye '||v_days||' gün kaldı.' end;
      v_action:='settings';
    else
      v_title:=case when v_days<0 then 'Geciken tahsilat' when v_days=0 then 'Bugün tahsil edilecek' else 'Yaklaşan tahsilat' end;
      v_body:=v_row.full_name||' • '||coalesce(v_row.service_type,'Klinik hizmeti')||' • '||trim(to_char(v_row.amount,'FM999999990D00'))||' '||coalesce(v_row.currency,'TRY')||
        case when v_days<0 then ' • '||abs(v_days)||' gün gecikti' when v_days=0 then ' • bugün' else ' • '||v_days||' gün kaldı' end;
      v_action:='payments';
    end if;

    perform public.create_app_notification_v5(
      v_clinic,auth.uid(),v_title,v_body,'payment_due',v_action,
      jsonb_build_object('payment_id',v_row.id,'client_id',v_row.client_id,'due_date',v_row.due_date,'days_remaining',v_days),
      'payment_due:'||v_row.id::text||':'||v_phase
    );
    v_count:=v_count+1;
  end loop;

  return v_count;
end;
$$;

grant execute on function public.sync_due_notifications_v5() to authenticated;

commit;

-- ============================================================================
-- 013_appointments_attendance_partial_payments.sql
-- ============================================================================

-- NutriClinic AI v5.2
-- Appointment history UX, attendance metrics support, multi-service payment packages,
-- and true partial-payment accounting. Run once after migrations 001-012.

begin;

alter table public.payments
  add column if not exists service_items jsonb not null default '[]'::jsonb,
  add column if not exists paid_amount numeric(12,2) not null default 0;

update public.payments
set service_items=jsonb_build_array(jsonb_build_object(
  'name',coalesce(nullif(trim(service_type),''),'Klinik hizmeti'),
  'quantity',1,
  'unit_price',amount,
  'total',amount
))
where service_items='[]'::jsonb;

update public.payments
set paid_amount=case when status='paid' then amount else 0 end
where paid_amount=0;

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='payments' and column_name='remaining_amount'
  ) then
    alter table public.payments
      add column remaining_amount numeric(12,2)
      generated always as (greatest(amount-paid_amount,0::numeric)) stored;
  end if;
end $$;

alter table public.payments drop constraint if exists payments_paid_amount_check;
alter table public.payments add constraint payments_paid_amount_check check (paid_amount>=0 and paid_amount<=amount);
alter table public.payments drop constraint if exists payments_service_items_array_check;
alter table public.payments add constraint payments_service_items_array_check check (jsonb_typeof(service_items)='array');

create index if not exists payments_remaining_due_idx
  on public.payments(clinic_id,due_date,remaining_amount)
  where status in ('pending','partial') and remaining_amount>0;

create or replace function public.save_payment_v6(
  p_payment_id uuid,
  p_client_id uuid,
  p_appointment_id uuid,
  p_service_items jsonb,
  p_description text,
  p_status text,
  p_method text,
  p_paid_amount numeric,
  p_paid_at timestamptz,
  p_due_date date
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_id uuid;
  v_total numeric(12,2);
  v_paid numeric(12,2);
  v_paid_at timestamptz;
  v_service_type text;
  v_normalized jsonb;
begin
  select m.clinic_id,m.role into v_clinic,v_role
  from public.clinic_memberships m
  where m.user_id=auth.uid() and m.is_active=true limit 1;
  if v_clinic is null or v_role not in ('owner','secretary') then raise exception 'Owner or secretary access required'; end if;
  if p_status not in ('pending','partial','paid','refunded','cancelled') then raise exception 'Invalid payment status'; end if;
  if p_method is not null and p_method not in ('cash','card','iban','other') then raise exception 'Invalid payment method'; end if;
  if not exists(select 1 from public.client_profiles c where c.id=p_client_id and c.clinic_id=v_clinic and c.is_active=true) then raise exception 'Client not found'; end if;
  if p_appointment_id is not null and not exists(select 1 from public.appointments a where a.id=p_appointment_id and a.clinic_id=v_clinic and a.client_id=p_client_id) then raise exception 'Appointment does not match client'; end if;
  if p_service_items is null or jsonb_typeof(p_service_items)<>'array' or jsonb_array_length(p_service_items)=0 then raise exception 'At least one service is required'; end if;
  if exists(
    select 1 from jsonb_array_elements(p_service_items) item
    where nullif(trim(item->>'name'),'') is null
      or coalesce(item->>'quantity','') !~ '^[0-9]+([.][0-9]+)?$'
      or coalesce(item->>'unit_price','') !~ '^[0-9]+([.][0-9]+)?$'
      or (item->>'quantity')::numeric<=0
      or (item->>'unit_price')::numeric<0
  ) then raise exception 'Invalid service item'; end if;

  select
    round(sum((item->>'quantity')::numeric*(item->>'unit_price')::numeric),2),
    left(string_agg(trim(item->>'name'),', ' order by ordinality),500),
    jsonb_agg(jsonb_build_object(
      'name',trim(item->>'name'),
      'quantity',(item->>'quantity')::numeric,
      'unit_price',round((item->>'unit_price')::numeric,2),
      'total',round((item->>'quantity')::numeric*(item->>'unit_price')::numeric,2)
    ) order by ordinality)
  into v_total,v_service_type,v_normalized
  from jsonb_array_elements(p_service_items) with ordinality as t(item,ordinality);

  if coalesce(v_total,0)<=0 then raise exception 'Payment total must be greater than zero'; end if;
  v_paid:=case
    when p_status='paid' then v_total
    when p_status='partial' then round(coalesce(p_paid_amount,0),2)
    else 0
  end;
  if p_status='partial' and (v_paid<=0 or v_paid>=v_total) then raise exception 'Partial payment must be greater than zero and lower than total'; end if;
  v_paid_at:=case when v_paid>0 then coalesce(p_paid_at,now()) else null end;

  if p_payment_id is null then
    insert into public.payments(clinic_id,client_id,appointment_id,service_type,service_items,description,amount,paid_amount,status,method,paid_at,due_date,recorded_by)
    values(v_clinic,p_client_id,p_appointment_id,v_service_type,v_normalized,nullif(trim(coalesce(p_description,'')),''),v_total,v_paid,p_status,p_method,v_paid_at,p_due_date,auth.uid())
    returning id into v_id;
  else
    update public.payments set
      appointment_id=p_appointment_id,service_type=v_service_type,service_items=v_normalized,
      description=nullif(trim(coalesce(p_description,'')),''),amount=v_total,paid_amount=v_paid,
      status=p_status,method=p_method,paid_at=v_paid_at,due_date=p_due_date,recorded_by=auth.uid(),updated_at=now()
    where id=p_payment_id and clinic_id=v_clinic returning id into v_id;
    if v_id is null then raise exception 'Payment not found'; end if;
  end if;

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values(v_clinic,auth.uid(),case when p_payment_id is null then 'payment_package_created' else 'payment_package_updated' end,'payment',v_id::text,
    jsonb_build_object('client_id',p_client_id,'service_items',v_normalized,'total_amount',v_total,'paid_amount',v_paid,'remaining_amount',greatest(v_total-v_paid,0),'status',p_status,'method',p_method,'due_date',p_due_date));
  return v_id;
end;
$$;

create or replace function public.get_client_directory_v4()
returns table(
  id uuid,user_id uuid,member_no text,full_name text,email text,phone text,birth_date date,gender text,
  assigned_dietitian_id uuid,assigned_dietitian_name text,height_cm numeric,target_text text,allergies text[],disliked_foods text[],medical_notes text,medications text,
  latest_weight_kg numeric,latest_body_fat_percent numeric,latest_muscle_mass_kg numeric,latest_measurement_at timestamptz,
  loyalty_earned bigint,loyalty_used bigint,loyalty_balance int,payment_total numeric,payment_paid numeric,payment_due numeric,
  last_payment_status text,last_payment_method text,last_payment_service text,last_payment_at timestamptz,created_at timestamptz,
  onboarding_completed boolean,primary_goal text,motivation_reasons text[],target_weight_kg numeric,activity_level text,calorie_knowledge text,diet_style text,
  chronic_conditions text[],additive_reactions text[],water_goal_ml integer
)
language plpgsql
stable
security definer
set search_path=public
as $$
declare v_clinic uuid;v_role public.clinic_role;
begin
  select m.clinic_id,m.role into v_clinic,v_role from public.clinic_memberships m where m.user_id=auth.uid() and m.is_active=true limit 1;
  if v_clinic is null or v_role not in ('owner','dietitian','secretary') then raise exception 'Staff access required'; end if;
  return query
  select c.id,c.user_id,c.member_no,c.full_name,c.email,c.phone,
    case when v_role='secretary' then null else c.birth_date end,
    case when v_role='secretary' then null else c.gender end,
    c.assigned_dietitian_id,dp.full_name,
    case when v_role='secretary' then null else c.height_cm end,
    case when v_role='secretary' then null else c.target_text end,
    case when v_role='secretary' then '{}'::text[] else c.allergies end,
    case when v_role='secretary' then '{}'::text[] else c.disliked_foods end,
    case when v_role='secretary' then null else c.medical_notes end,
    case when v_role='secretary' then null else c.medications end,
    case when v_role='secretary' then null else coalesce(cwl.weight_kg,lm.weight_kg,c.current_weight_kg) end,
    case when v_role='secretary' then null else lm.body_fat_percent end,
    case when v_role='secretary' then null else lm.muscle_mass_kg end,
    case when v_role='secretary' then null else lm.measured_at end,
    case when v_role='secretary' then 0 else coalesce(loyalty.earned,0) end,
    case when v_role='secretary' then 0 else coalesce(loyalty.used,0) end,
    case when v_role='secretary' then 0 else coalesce(w.balance,0) end,
    coalesce(pay.total,0),coalesce(pay.paid,0),greatest(coalesce(pay.total,0)-coalesce(pay.paid,0),0),
    last_pay.status,last_pay.method,last_pay.service_type,last_pay.paid_at,c.created_at,
    case when v_role='secretary' then false else c.onboarding_completed end,
    case when v_role='secretary' then null else c.primary_goal end,
    case when v_role='secretary' then '{}'::text[] else c.motivation_reasons end,
    case when v_role='secretary' then null else c.target_weight_kg end,
    case when v_role='secretary' then null else c.activity_level end,
    case when v_role='secretary' then null else c.calorie_knowledge end,
    case when v_role='secretary' then null else c.diet_style end,
    case when v_role='secretary' then '{}'::text[] else c.chronic_conditions end,
    case when v_role='secretary' then '{}'::text[] else c.additive_reactions end,
    case when v_role='secretary' then null else c.water_goal_ml end
  from public.client_profiles c
  left join public.dietitian_profiles d on d.id=c.assigned_dietitian_id
  left join public.profiles dp on dp.id=d.user_id
  left join lateral (select m.weight_kg,m.body_fat_percent,m.muscle_mass_kg,m.measured_at from public.measurements m where m.client_id=c.id order by m.measured_at desc limit 1) lm on true
  left join lateral (select x.weight_kg from public.client_weight_logs x where x.client_id=c.id order by x.weight_date desc,x.created_at desc limit 1) cwl on true
  left join public.loyalty_wallets w on w.clinic_id=c.clinic_id and w.client_id=c.id
  left join lateral (select coalesce(sum(case when t.points>0 then t.points else 0 end),0)::bigint earned,coalesce(sum(case when t.points<0 then abs(t.points) else 0 end),0)::bigint used from public.loyalty_transactions t where t.wallet_id=w.id) loyalty on true
  left join lateral (select coalesce(sum(case when p.status not in ('cancelled','refunded') then p.amount else 0 end),0)::numeric total,coalesce(sum(case when p.status not in ('cancelled','refunded') then p.paid_amount else 0 end),0)::numeric paid from public.payments p where p.client_id=c.id) pay on true
  left join lateral (select p.status,p.method,p.service_type,p.paid_at from public.payments p where p.client_id=c.id order by p.created_at desc limit 1) last_pay on true
  where c.clinic_id=v_clinic and c.is_active=true
  order by c.created_at desc;
end;
$$;



create or replace function public.get_dashboard_summary_v3()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_timezone text;
  v_today date;
  v_dietitian_id uuid;
  v_client_id uuid;
  v_result jsonb;
begin
  select m.clinic_id,m.role,c.timezone into v_clinic,v_role,v_timezone
  from public.clinic_memberships m join public.clinics c on c.id=m.clinic_id
  where m.user_id=auth.uid() and m.is_active=true limit 1;
  if v_clinic is null then raise exception 'Active membership not found'; end if;
  v_today := (now() at time zone v_timezone)::date;
  select d.id into v_dietitian_id from public.dietitian_profiles d where d.clinic_id=v_clinic and d.user_id=auth.uid();
  select c.id into v_client_id from public.client_profiles c where c.clinic_id=v_clinic and c.user_id=auth.uid() and c.is_active=true;

  if v_role='owner' then
    select jsonb_build_object(
      'today_appointments',(select count(*) from public.appointments a where a.clinic_id=v_clinic and (a.starts_at at time zone v_timezone)::date=v_today and a.status not in ('cancelled')),
      'pending_appointments',(select count(*) from public.appointments a where a.clinic_id=v_clinic and a.status='pending' and a.starts_at>=now()),
      'active_clients',(select count(*) from public.client_profiles c where c.clinic_id=v_clinic and c.is_active=true),
      'active_plans',(select count(*) from public.meal_plans p where p.clinic_id=v_clinic and p.status='active'),
      'daily_revenue',(select coalesce(sum(p.paid_amount),0) from public.payments p where p.clinic_id=v_clinic and p.paid_amount>0 and (p.paid_at at time zone v_timezone)::date=v_today),
      'pending_payments',(select count(*) from public.payments p where p.clinic_id=v_clinic and p.status in ('pending','partial')),
      'revenue_breakdown',coalesce((select jsonb_agg(to_jsonb(x) order by x.amount desc) from (
        select p.service_type,count(*)::int count,sum(p.paid_amount)::numeric amount
        from public.payments p where p.clinic_id=v_clinic and p.paid_amount>0 and (p.paid_at at time zone v_timezone)::date=v_today
        group by p.service_type
      ) x),'[]'::jsonb),
      'agenda',coalesce((select jsonb_agg(to_jsonb(x) order by x.starts_at) from (
        select a.id,a.starts_at,a.status,a.appointment_type,a.mode,c.full_name client_name,c.phone,c.email,pr.full_name dietitian_name
        from public.appointments a
        join public.client_profiles c on c.id=a.client_id
        join public.dietitian_profiles d on d.id=a.dietitian_id
        join public.profiles pr on pr.id=d.user_id
        where a.clinic_id=v_clinic and (a.starts_at at time zone v_timezone)::date=v_today and a.status<>'cancelled'
      ) x),'[]'::jsonb)
    ) into v_result;
  elsif v_role='dietitian' then
    select jsonb_build_object(
      'today_appointments',(select count(*) from public.appointments a where a.dietitian_id=v_dietitian_id and (a.starts_at at time zone v_timezone)::date=v_today and a.status<>'cancelled'),
      'pending_appointments',(select count(*) from public.appointments a where a.dietitian_id=v_dietitian_id and a.status='pending' and a.starts_at>=now()),
      'active_clients',(select count(*) from public.client_profiles c where c.assigned_dietitian_id=v_dietitian_id and c.is_active=true),
      'active_plans',(select count(*) from public.meal_plans p where p.dietitian_id=v_dietitian_id and p.status='active'),
      'agenda',coalesce((select jsonb_agg(to_jsonb(x) order by x.starts_at) from (
        select a.id,a.starts_at,a.status,a.appointment_type,a.mode,c.full_name client_name,c.phone,c.email
        from public.appointments a join public.client_profiles c on c.id=a.client_id
        where a.dietitian_id=v_dietitian_id and (a.starts_at at time zone v_timezone)::date=v_today and a.status<>'cancelled'
      ) x),'[]'::jsonb)
    ) into v_result;
  elsif v_role='secretary' then
    select jsonb_build_object(
      'today_appointments',(select count(*) from public.appointments a where a.clinic_id=v_clinic and (a.starts_at at time zone v_timezone)::date=v_today and a.status<>'cancelled'),
      'pending_appointments',(select count(*) from public.appointments a where a.clinic_id=v_clinic and a.status='pending' and a.starts_at>=now()),
      'active_clients',(select count(*) from public.client_profiles c where c.clinic_id=v_clinic and c.is_active=true),
      'pending_payments',(select count(*) from public.payments p where p.clinic_id=v_clinic and p.status in ('pending','partial')),
      'agenda',coalesce((select jsonb_agg(to_jsonb(x) order by x.starts_at) from (
        select a.id,a.starts_at,a.status,a.appointment_type,a.mode,c.full_name client_name,c.phone,c.email,pr.full_name dietitian_name
        from public.appointments a
        join public.client_profiles c on c.id=a.client_id
        join public.dietitian_profiles d on d.id=a.dietitian_id
        join public.profiles pr on pr.id=d.user_id
        where a.clinic_id=v_clinic and (a.starts_at at time zone v_timezone)::date=v_today and a.status<>'cancelled'
      ) x),'[]'::jsonb)
    ) into v_result;
  else
    select jsonb_build_object(
      'upcoming_appointments',(select count(*) from public.appointments a where a.client_id=v_client_id and a.starts_at>=now() and a.status in ('pending','confirmed')),
      'active_plans',(select count(*) from public.meal_plans p where p.client_id=v_client_id and p.status='active'),
      'measurements',(select count(*) from public.measurements m where m.client_id=v_client_id),
      'loyalty_balance',(select coalesce(w.balance,0) from public.loyalty_wallets w where w.client_id=v_client_id limit 1),
      'agenda',coalesce((select jsonb_agg(to_jsonb(x) order by x.starts_at) from (
        select a.id,a.starts_at,a.status,a.appointment_type,a.mode,pr.full_name dietitian_name
        from public.appointments a
        join public.dietitian_profiles d on d.id=a.dietitian_id
        join public.profiles pr on pr.id=d.user_id
        where a.client_id=v_client_id and a.starts_at>=now() and a.status in ('pending','confirmed') limit 5
      ) x),'[]'::jsonb)
    ) into v_result;
  end if;

  return coalesce(v_result,'{}'::jsonb) || jsonb_build_object('role',v_role,'today',v_today);
end;
$$;



create or replace function public.get_payment_due_summary_v5()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_clinic uuid;v_role public.clinic_role;v_client uuid;v_dietitian uuid;v_rows jsonb;
begin
  select clinic_id,role into v_clinic,v_role from public.clinic_memberships where user_id=auth.uid() and is_active=true limit 1;
  if v_clinic is null then raise exception 'Active membership not found'; end if;
  select id into v_client from public.client_profiles where clinic_id=v_clinic and user_id=auth.uid() and is_active=true;
  select id into v_dietitian from public.dietitian_profiles where clinic_id=v_clinic and user_id=auth.uid();
  select coalesce(jsonb_agg(to_jsonb(x) order by x.due_date nulls last,x.created_at desc),'[]'::jsonb) into v_rows
  from (
    select p.id,p.client_id,p.service_type,p.service_items,p.description,p.amount,p.paid_amount,p.remaining_amount,p.currency,p.status,p.method,p.paid_at,p.due_date,p.reminder_sent_at,p.reminder_channel,p.reminder_count,p.created_at,
      c.full_name client_name,c.member_no,c.email,c.phone,c.user_id,case when p.due_date is null then null else (p.due_date-current_date)::int end days_remaining
    from public.payments p join public.client_profiles c on c.id=p.client_id
    where p.clinic_id=v_clinic and p.status in ('pending','partial') and p.remaining_amount>0
      and (v_role in ('owner','secretary') or (v_role='dietitian' and c.assigned_dietitian_id=v_dietitian) or (v_role='client' and c.id=v_client))
  ) x;
  return jsonb_build_object('role',v_role,'rows',v_rows);
end;
$$;

create or replace function public.sync_due_notifications_v5()
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_client uuid;
  v_dietitian uuid;
  v_row record;
  v_days integer;
  v_phase text;
  v_title text;
  v_body text;
  v_action text;
  v_count integer:=0;
begin
  select clinic_id,role into v_clinic,v_role
  from public.clinic_memberships
  where user_id=auth.uid() and is_active=true
  limit 1;
  if v_clinic is null then return 0; end if;

  select id into v_client from public.client_profiles
  where clinic_id=v_clinic and user_id=auth.uid() and is_active=true limit 1;
  select id into v_dietitian from public.dietitian_profiles
  where clinic_id=v_clinic and user_id=auth.uid() limit 1;

  for v_row in
    select p.id,p.client_id,p.service_type,p.remaining_amount amount,p.currency,p.due_date,c.full_name,c.user_id
    from public.payments p
    join public.client_profiles c on c.id=p.client_id and c.clinic_id=p.clinic_id
    where p.clinic_id=v_clinic
      and p.status in ('pending','partial')
      and p.due_date is not null
      and p.due_date<=current_date+7
      and (
        (v_role='client' and c.id=v_client)
        or v_role in ('owner','secretary')
        or (v_role='dietitian' and c.assigned_dietitian_id=v_dietitian)
      )
  loop
    v_days:=(v_row.due_date-current_date)::integer;
    v_phase:=case
      when v_days<0 then 'overdue'
      when v_days=0 then 'today'
      when v_days=1 then '1day'
      when v_days<=3 then '3days'
      else '7days'
    end;

    if v_role='client' then
      v_title:=case when v_days<0 then 'Ödemenizin tarihi geçti' when v_days=0 then 'Ödemeniz bugün' else 'Yaklaşan ödemeniz var' end;
      v_body:=coalesce(v_row.service_type,'Klinik hizmeti')||' için '||trim(to_char(v_row.amount,'FM999999990D00'))||' '||coalesce(v_row.currency,'TRY')||
        case when v_days<0 then ' ödeme '||abs(v_days)||' gün gecikti.' when v_days=0 then ' ödeme bugün bekleniyor.' else ' ödemeye '||v_days||' gün kaldı.' end;
      v_action:='settings';
    else
      v_title:=case when v_days<0 then 'Geciken tahsilat' when v_days=0 then 'Bugün tahsil edilecek' else 'Yaklaşan tahsilat' end;
      v_body:=v_row.full_name||' • '||coalesce(v_row.service_type,'Klinik hizmeti')||' • '||trim(to_char(v_row.amount,'FM999999990D00'))||' '||coalesce(v_row.currency,'TRY')||
        case when v_days<0 then ' • '||abs(v_days)||' gün gecikti' when v_days=0 then ' • bugün' else ' • '||v_days||' gün kaldı' end;
      v_action:='payments';
    end if;

    perform public.create_app_notification_v5(
      v_clinic,auth.uid(),v_title,v_body,'payment_due',v_action,
      jsonb_build_object('payment_id',v_row.id,'client_id',v_row.client_id,'due_date',v_row.due_date,'days_remaining',v_days),
      'payment_due:'||v_row.id::text||':'||v_phase
    );
    v_count:=v_count+1;
  end loop;

  return v_count;
end;
$$;



create or replace function public.notify_payment_status_v5()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_user uuid;v_service text;v_amount text;v_title text;v_body text;
begin
  if new.paid_amount<=0 then return new; end if;
  if tg_op='UPDATE' and coalesce(old.paid_amount,0)>=new.paid_amount and old.status=new.status then return new; end if;
  select user_id into v_user from public.client_profiles where id=new.client_id and clinic_id=new.clinic_id and is_active=true;
  if v_user is null then return new; end if;
  v_service:=coalesce(nullif(trim(new.service_type),''),'Klinik hizmeti');
  v_amount:=trim(to_char(new.paid_amount,'FM999999990D00'))||' '||coalesce(new.currency,'TRY');
  v_title:=case when new.status='partial' then 'Kısmi ödemeniz kaydedildi' else 'Ödemeniz onaylandı' end;
  v_body:=v_service||' için '||v_amount||case when new.status='partial' then ' alındı. Kalan tutar: '||trim(to_char(new.remaining_amount,'FM999999990D00'))||' '||coalesce(new.currency,'TRY')||'.' else ' tutarındaki ödemeniz alındı.' end;
  perform public.create_app_notification_v5(new.clinic_id,v_user,v_title,v_body,'payment_paid','settings',jsonb_build_object('payment_id',new.id,'amount',new.amount,'paid_amount',new.paid_amount,'remaining_amount',new.remaining_amount,'currency',new.currency,'method',new.method,'paid_at',new.paid_at),'payment_paid:'||new.id::text||':'||new.paid_amount::text);
  return new;
end;
$$;

drop trigger if exists trg_notify_payment_status_v5 on public.payments;
create trigger trg_notify_payment_status_v5
after insert or update of status,paid_amount on public.payments
for each row execute function public.notify_payment_status_v5();

grant execute on function public.save_payment_v6(uuid,uuid,uuid,jsonb,text,text,text,numeric,timestamptz,date) to authenticated;
grant execute on function public.get_client_directory_v4() to authenticated;
grant execute on function public.get_dashboard_summary_v3() to authenticated;
grant execute on function public.get_payment_due_summary_v5() to authenticated;
grant execute on function public.sync_due_notifications_v5() to authenticated;

commit;

-- ============================================================================
-- 014_staff_managed_loyalty_coupons.sql
-- ============================================================================

-- NutriClinic AI v5.4
-- Staff-managed loyalty coupons and ambiguity fixes.
-- Run once after migrations 001-013.

begin;

-- Clients can no longer spend points and create their own coupon directly.
revoke execute on function public.redeem_reward(uuid) from authenticated;

-- The previous function used unqualified `id` references while `id` was also
-- an OUT parameter. PostgreSQL therefore reported: column reference "id" is ambiguous.
drop function if exists public.get_reward_redemptions(uuid);

create or replace function public.get_reward_redemptions(p_client_id uuid default null)
returns table(
  id uuid,
  client_id uuid,
  client_name text,
  member_no text,
  reward_id uuid,
  reward_name text,
  points_spent integer,
  status text,
  requested_at timestamptz,
  fulfilled_at timestamptz,
  note text,
  redemption_code text,
  code_expires_at timestamptz,
  used_at timestamptz,
  used_by uuid
)
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_own_client uuid;
  v_dietitian uuid;
begin
  select membership.clinic_id,membership.role
    into v_clinic,v_role
  from public.clinic_memberships membership
  where membership.user_id=auth.uid()
    and membership.is_active=true
  limit 1;

  if v_clinic is null then
    raise exception 'Aktif klinik üyeliği bulunamadı';
  end if;

  select client_profile.id
    into v_own_client
  from public.client_profiles client_profile
  where client_profile.clinic_id=v_clinic
    and client_profile.user_id=auth.uid()
    and client_profile.is_active=true
  limit 1;

  select dietitian_profile.id
    into v_dietitian
  from public.dietitian_profiles dietitian_profile
  where dietitian_profile.clinic_id=v_clinic
    and dietitian_profile.user_id=auth.uid()
  limit 1;

  if v_role='client' then
    return query
    select
      redemption.id,
      redemption.client_id,
      client_profile.full_name,
      client_profile.member_no,
      redemption.reward_id,
      redemption.reward_name,
      redemption.points_spent,
      redemption.status,
      redemption.requested_at,
      redemption.fulfilled_at,
      redemption.note,
      redemption.redemption_code,
      redemption.code_expires_at,
      redemption.used_at,
      redemption.used_by
    from public.reward_redemptions redemption
    join public.client_profiles client_profile on client_profile.id=redemption.client_id
    where redemption.clinic_id=v_clinic
      and redemption.client_id=v_own_client
    order by redemption.requested_at desc;
  elsif v_role in ('owner','dietitian') then
    return query
    select
      redemption.id,
      redemption.client_id,
      client_profile.full_name,
      client_profile.member_no,
      redemption.reward_id,
      redemption.reward_name,
      redemption.points_spent,
      redemption.status,
      redemption.requested_at,
      redemption.fulfilled_at,
      redemption.note,
      redemption.redemption_code,
      redemption.code_expires_at,
      redemption.used_at,
      redemption.used_by
    from public.reward_redemptions redemption
    join public.client_profiles client_profile on client_profile.id=redemption.client_id
    where redemption.clinic_id=v_clinic
      and (p_client_id is null or redemption.client_id=p_client_id)
      and (v_role='owner' or client_profile.assigned_dietitian_id=v_dietitian)
    order by redemption.requested_at desc;
  else
    raise exception 'Bu işlem için Klinik Sahibi veya Diyetisyen yetkisi gerekir';
  end if;
end;
$$;

create or replace function public.get_reward_issuance_clients_v54()
returns table(
  client_id uuid,
  client_name text,
  member_no text,
  remaining_points integer
)
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_dietitian uuid;
begin
  select membership.clinic_id,membership.role
    into v_clinic,v_role
  from public.clinic_memberships membership
  where membership.user_id=auth.uid()
    and membership.is_active=true
  limit 1;

  if v_clinic is null or v_role not in ('owner','dietitian') then
    raise exception 'Bu işlem için Klinik Sahibi veya Diyetisyen yetkisi gerekir';
  end if;

  select dietitian_profile.id
    into v_dietitian
  from public.dietitian_profiles dietitian_profile
  where dietitian_profile.clinic_id=v_clinic
    and dietitian_profile.user_id=auth.uid()
  limit 1;

  return query
  select
    client_profile.id,
    client_profile.full_name,
    client_profile.member_no,
    coalesce(wallet.balance,0)::integer
  from public.client_profiles client_profile
  left join public.loyalty_wallets wallet
    on wallet.clinic_id=client_profile.clinic_id
   and wallet.client_id=client_profile.id
  where client_profile.clinic_id=v_clinic
    and client_profile.is_active=true
    and (v_role='owner' or client_profile.assigned_dietitian_id=v_dietitian)
  order by client_profile.full_name;
end;
$$;

create or replace function public.issue_reward_coupon_v54(
  p_client_id uuid,
  p_reward_id uuid,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_dietitian uuid;
  v_client public.client_profiles%rowtype;
  v_reward public.rewards%rowtype;
  v_wallet_id uuid;
  v_balance integer;
  v_new_balance integer;
  v_transaction_id uuid;
  v_redemption_id uuid;
  v_code text;
begin
  select membership.clinic_id,membership.role
    into v_clinic,v_role
  from public.clinic_memberships membership
  where membership.user_id=auth.uid()
    and membership.is_active=true
  limit 1;

  if v_clinic is null or v_role not in ('owner','dietitian') then
    raise exception 'Bu işlem için Klinik Sahibi veya Diyetisyen yetkisi gerekir';
  end if;

  select dietitian_profile.id
    into v_dietitian
  from public.dietitian_profiles dietitian_profile
  where dietitian_profile.clinic_id=v_clinic
    and dietitian_profile.user_id=auth.uid()
  limit 1;

  select client_profile.*
    into v_client
  from public.client_profiles client_profile
  where client_profile.id=p_client_id
    and client_profile.clinic_id=v_clinic
    and client_profile.is_active=true;

  if v_client.id is null then
    raise exception 'Danışan bulunamadı';
  end if;

  if v_role='dietitian' and v_client.assigned_dietitian_id is distinct from v_dietitian then
    raise exception 'Bu danışan size atanmış değil';
  end if;

  select reward.*
    into v_reward
  from public.rewards reward
  where reward.id=p_reward_id
    and reward.clinic_id=v_clinic
    and reward.is_active=true
  for update;

  if v_reward.id is null then
    raise exception 'Ödül aktif değil veya bulunamadı';
  end if;

  if v_reward.stock is not null and v_reward.stock<=0 then
    raise exception 'Ödül stoğu tükendi';
  end if;

  insert into public.loyalty_wallets(clinic_id,client_id,balance)
  values(v_clinic,v_client.id,0)
  on conflict(clinic_id,client_id) do nothing;

  select wallet.id,wallet.balance
    into v_wallet_id,v_balance
  from public.loyalty_wallets wallet
  where wallet.clinic_id=v_clinic
    and wallet.client_id=v_client.id
  for update;

  if coalesce(v_balance,0)<v_reward.points_cost then
    raise exception 'Danışanın puanı yetersiz. Gerekli: %, Mevcut: %',v_reward.points_cost,coalesce(v_balance,0);
  end if;

  v_new_balance:=v_balance-v_reward.points_cost;

  update public.loyalty_wallets wallet
  set balance=v_new_balance,updated_at=now()
  where wallet.id=v_wallet_id;

  if v_reward.stock is not null then
    update public.rewards reward
    set stock=v_reward.stock-1
    where reward.id=v_reward.id;

    insert into public.reward_stock_movements(
      clinic_id,reward_id,quantity_change,stock_after,reason,created_by
    ) values(
      v_clinic,v_reward.id,-1,v_reward.stock-1,
      'Klinik tarafından danışana sadakat kuponu tanımlandı',auth.uid()
    );
  end if;

  insert into public.loyalty_transactions as loyalty_transaction(
    wallet_id,transaction_type,points,reason,reward_id,created_by,balance_after
  ) values(
    v_wallet_id,'redeemed',-v_reward.points_cost,
    'Klinik tarafından ödül tanımlandı: '||v_reward.name,
    v_reward.id,auth.uid(),v_new_balance
  ) returning loyalty_transaction.id into v_transaction_id;

  loop
    v_code:=upper(substr(md5(gen_random_uuid()::text||clock_timestamp()::text),1,8));
    exit when not exists(
      select 1
      from public.reward_redemptions redemption
      where redemption.redemption_code=v_code
    );
  end loop;

  insert into public.reward_redemptions as reward_redemption(
    clinic_id,client_id,reward_id,loyalty_transaction_id,reward_name,
    points_spent,status,requested_at,note,redemption_code,code_expires_at,handled_by,updated_at
  ) values(
    v_clinic,v_client.id,v_reward.id,v_transaction_id,v_reward.name,
    v_reward.points_cost,'requested',now(),nullif(trim(coalesce(p_note,'')),''),
    v_code,now()+interval '90 days',auth.uid(),now()
  ) returning reward_redemption.id into v_redemption_id;

  if v_client.user_id is not null then
    insert into public.notifications(
      clinic_id,recipient_user_id,title,body,category,metadata
    ) values(
      v_clinic,v_client.user_id,'Yeni sadakat ödülünüz var',
      v_reward.name||' ödülü kliniğiniz tarafından hesabınıza tanımlandı.',
      'loyalty_reward_issued',
      jsonb_build_object(
        'redemption_id',v_redemption_id,
        'reward_id',v_reward.id,
        'reward_name',v_reward.name,
        'redemption_code',v_code,
        'points_spent',v_reward.points_cost
      )
    );
  end if;

  insert into public.audit_logs(
    clinic_id,actor_user_id,action,target_type,target_id,metadata
  ) values(
    v_clinic,auth.uid(),'reward_coupon_issued','reward_redemption',v_redemption_id::text,
    jsonb_build_object(
      'client_id',v_client.id,
      'client_name',v_client.full_name,
      'reward_id',v_reward.id,
      'reward_name',v_reward.name,
      'points_spent',v_reward.points_cost,
      'balance_before',v_balance,
      'balance_after',v_new_balance,
      'redemption_code',v_code
    )
  );

  return jsonb_build_object(
    'redemption_id',v_redemption_id,
    'client_id',v_client.id,
    'client_name',v_client.full_name,
    'member_no',v_client.member_no,
    'reward_id',v_reward.id,
    'reward_name',v_reward.name,
    'points_spent',v_reward.points_cost,
    'balance_after',v_new_balance,
    'redemption_code',v_code,
    'code_expires_at',now()+interval '90 days'
  );
end;
$$;

create or replace function public.fulfill_reward_redemption_v54(p_redemption_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_dietitian uuid;
  v_redemption public.reward_redemptions%rowtype;
  v_client public.client_profiles%rowtype;
begin
  select membership.clinic_id,membership.role
    into v_clinic,v_role
  from public.clinic_memberships membership
  where membership.user_id=auth.uid()
    and membership.is_active=true
  limit 1;

  if v_clinic is null or v_role not in ('owner','dietitian') then
    raise exception 'Bu işlem için Klinik Sahibi veya Diyetisyen yetkisi gerekir';
  end if;

  select dietitian_profile.id
    into v_dietitian
  from public.dietitian_profiles dietitian_profile
  where dietitian_profile.clinic_id=v_clinic
    and dietitian_profile.user_id=auth.uid()
  limit 1;

  select redemption.*
    into v_redemption
  from public.reward_redemptions redemption
  where redemption.id=p_redemption_id
    and redemption.clinic_id=v_clinic
  for update;

  if v_redemption.id is null then
    raise exception 'Ödül kaydı bulunamadı';
  end if;

  select client_profile.*
    into v_client
  from public.client_profiles client_profile
  where client_profile.id=v_redemption.client_id
    and client_profile.clinic_id=v_clinic;

  if v_role='dietitian' and v_client.assigned_dietitian_id is distinct from v_dietitian then
    raise exception 'Bu danışan size atanmış değil';
  end if;

  if v_redemption.status='fulfilled' or v_redemption.used_at is not null then
    raise exception 'Bu ödül daha önce kullanılmış';
  end if;

  if v_redemption.status='cancelled' then
    raise exception 'İptal edilmiş ödül kullanılamaz';
  end if;

  if v_redemption.code_expires_at is not null and v_redemption.code_expires_at<now() then
    raise exception 'Ödülün kullanım süresi dolmuş';
  end if;

  update public.reward_redemptions redemption
  set status='fulfilled',fulfilled_at=now(),used_at=now(),used_by=auth.uid(),handled_by=auth.uid(),updated_at=now()
  where redemption.id=v_redemption.id;

  if v_client.user_id is not null then
    insert into public.notifications(
      clinic_id,recipient_user_id,title,body,category,metadata
    ) values(
      v_clinic,v_client.user_id,'Sadakat ödülünüz kullanıldı',
      v_redemption.reward_name||' ödülünüz klinikte kullanıldı.',
      'loyalty_reward_fulfilled',
      jsonb_build_object('redemption_id',v_redemption.id,'reward_name',v_redemption.reward_name)
    );
  end if;

  insert into public.audit_logs(
    clinic_id,actor_user_id,action,target_type,target_id,metadata
  ) values(
    v_clinic,auth.uid(),'reward_fulfilled','reward_redemption',v_redemption.id::text,
    jsonb_build_object(
      'client_id',v_redemption.client_id,
      'client_name',v_client.full_name,
      'reward_name',v_redemption.reward_name,
      'redemption_code',v_redemption.redemption_code
    )
  );

  return jsonb_build_object(
    'redemption_id',v_redemption.id,
    'client_id',v_redemption.client_id,
    'client_name',v_client.full_name,
    'reward_name',v_redemption.reward_name,
    'code',v_redemption.redemption_code
  );
end;
$$;

revoke all on function public.get_reward_redemptions(uuid) from public;
revoke all on function public.get_reward_issuance_clients_v54() from public;
revoke all on function public.issue_reward_coupon_v54(uuid,uuid,text) from public;
revoke all on function public.fulfill_reward_redemption_v54(uuid) from public;

grant execute on function public.get_reward_redemptions(uuid) to authenticated;
grant execute on function public.get_reward_issuance_clients_v54() to authenticated;
grant execute on function public.issue_reward_coupon_v54(uuid,uuid,text) to authenticated;
grant execute on function public.fulfill_reward_redemption_v54(uuid) to authenticated;

commit;

-- ============================================================================
-- 015_loyalty_balance_repair_and_reward_flow.sql
-- ============================================================================

-- NutriClinic AI v5.5
-- Loyalty balance repair, safer point awards and staff-only reward fulfillment.
-- Run once after migrations 001-014.

begin;

-- Prevent accidental entries such as 999,999,999 points while keeping the
-- existing function signature used by the application.
create or replace function public.add_client_loyalty_points(
  p_client_id uuid,
  p_points int,
  p_reason text
) returns int
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_dietitian uuid;
  v_client public.client_profiles%rowtype;
  v_wallet_id uuid;
  v_old_balance int;
  v_new_balance int;
  v_transaction_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Oturum açmanız gerekir';
  end if;

  if p_points is null or p_points <= 0 then
    raise exception 'Puan pozitif tam sayı olmalıdır';
  end if;

  if p_points > 1000000 then
    raise exception 'Tek işlemde en fazla 1.000.000 puan eklenebilir';
  end if;

  if nullif(btrim(coalesce(p_reason,'')),'') is null then
    raise exception 'Puan ekleme nedeni zorunludur';
  end if;

  select client_profile.*
    into v_client
  from public.client_profiles client_profile
  where client_profile.id=p_client_id
    and client_profile.is_active=true;

  if v_client.id is null then
    raise exception 'Aktif danışan profili bulunamadı';
  end if;

  v_clinic:=v_client.clinic_id;

  select membership.role
    into v_role
  from public.clinic_memberships membership
  where membership.clinic_id=v_clinic
    and membership.user_id=auth.uid()
    and membership.is_active=true
  limit 1;

  if v_role is null or v_role not in ('owner','dietitian') then
    raise exception 'Yalnızca Klinik Sahibi veya Diyetisyen puan ekleyebilir';
  end if;

  if v_role='dietitian' then
    select dietitian_profile.id
      into v_dietitian
    from public.dietitian_profiles dietitian_profile
    where dietitian_profile.clinic_id=v_clinic
      and dietitian_profile.user_id=auth.uid()
    limit 1;

    if v_client.assigned_dietitian_id is distinct from v_dietitian then
      raise exception 'Bu danışan size atanmış değil';
    end if;
  end if;

  insert into public.loyalty_wallets(clinic_id,client_id,balance)
  values(v_clinic,p_client_id,0)
  on conflict(clinic_id,client_id) do nothing;

  select wallet.id,wallet.balance
    into v_wallet_id,v_old_balance
  from public.loyalty_wallets wallet
  where wallet.clinic_id=v_clinic
    and wallet.client_id=p_client_id
  for update;

  if v_old_balance > 10000000 - p_points then
    raise exception 'Sadakat bakiyesi 10.000.000 puan güvenlik sınırını aşamaz. Önce bakiyeyi düzeltin';
  end if;

  v_new_balance:=v_old_balance+p_points;

  update public.loyalty_wallets wallet
  set balance=v_new_balance,updated_at=now()
  where wallet.id=v_wallet_id;

  insert into public.loyalty_transactions as loyalty_transaction(
    wallet_id,transaction_type,points,reason,created_by,balance_after
  ) values(
    v_wallet_id,'adjusted',p_points,btrim(p_reason),auth.uid(),v_new_balance
  ) returning loyalty_transaction.id into v_transaction_id;

  insert into public.audit_logs(
    clinic_id,actor_user_id,action,target_type,target_id,metadata
  ) values(
    v_clinic,auth.uid(),'client_loyalty_points_added','client',p_client_id::text,
    jsonb_build_object(
      'transaction_id',v_transaction_id,
      'points_added',p_points,
      'reason',btrim(p_reason),
      'balance_before',v_old_balance,
      'balance_after',v_new_balance,
      'actor_role',v_role
    )
  );

  if v_client.user_id is not null then
    insert into public.notifications(
      clinic_id,recipient_user_id,title,body,category,metadata
    ) values(
      v_clinic,v_client.user_id,'Sadakat puanı eklendi',
      p_points::text||' sadakat puanı hesabınıza eklendi.',
      'loyalty_points_added',
      jsonb_build_object('points',p_points,'balance_after',v_new_balance,'reason',btrim(p_reason))
    );
  end if;

  return v_new_balance;
end;
$$;

-- Exact-balance correction for accidental point entries. The delta is kept in
-- the transaction ledger and the audit log, so nothing is silently erased.
create or replace function public.set_client_loyalty_balance_v55(
  p_client_id uuid,
  p_new_balance int,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_dietitian uuid;
  v_client public.client_profiles%rowtype;
  v_wallet_id uuid;
  v_old_balance int;
  v_delta int;
  v_transaction_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Oturum açmanız gerekir';
  end if;

  if p_new_balance is null or p_new_balance < 0 then
    raise exception 'Yeni bakiye 0 veya daha büyük olmalıdır';
  end if;

  if p_new_balance > 10000000 then
    raise exception 'Sadakat bakiyesi 10.000.000 puanı aşamaz';
  end if;

  if nullif(btrim(coalesce(p_reason,'')),'') is null then
    raise exception 'Düzeltme nedeni zorunludur';
  end if;

  select client_profile.*
    into v_client
  from public.client_profiles client_profile
  where client_profile.id=p_client_id
    and client_profile.is_active=true;

  if v_client.id is null then
    raise exception 'Aktif danışan profili bulunamadı';
  end if;

  v_clinic:=v_client.clinic_id;

  select membership.role
    into v_role
  from public.clinic_memberships membership
  where membership.clinic_id=v_clinic
    and membership.user_id=auth.uid()
    and membership.is_active=true
  limit 1;

  if v_role is null or v_role not in ('owner','dietitian') then
    raise exception 'Yalnızca Klinik Sahibi veya Diyetisyen bakiye düzeltebilir';
  end if;

  if v_role='dietitian' then
    select dietitian_profile.id
      into v_dietitian
    from public.dietitian_profiles dietitian_profile
    where dietitian_profile.clinic_id=v_clinic
      and dietitian_profile.user_id=auth.uid()
    limit 1;

    if v_client.assigned_dietitian_id is distinct from v_dietitian then
      raise exception 'Bu danışan size atanmış değil';
    end if;
  end if;

  insert into public.loyalty_wallets(clinic_id,client_id,balance)
  values(v_clinic,p_client_id,0)
  on conflict(clinic_id,client_id) do nothing;

  select wallet.id,wallet.balance
    into v_wallet_id,v_old_balance
  from public.loyalty_wallets wallet
  where wallet.clinic_id=v_clinic
    and wallet.client_id=p_client_id
  for update;

  v_delta:=p_new_balance-v_old_balance;

  if v_delta=0 then
    return jsonb_build_object(
      'client_id',p_client_id,
      'old_balance',v_old_balance,
      'new_balance',p_new_balance,
      'delta',0,
      'changed',false
    );
  end if;

  update public.loyalty_wallets wallet
  set balance=p_new_balance,updated_at=now()
  where wallet.id=v_wallet_id;

  insert into public.loyalty_transactions as loyalty_transaction(
    wallet_id,transaction_type,points,reason,created_by,balance_after
  ) values(
    v_wallet_id,'adjusted',v_delta,'Bakiye düzeltmesi: '||btrim(p_reason),auth.uid(),p_new_balance
  ) returning loyalty_transaction.id into v_transaction_id;

  insert into public.audit_logs(
    clinic_id,actor_user_id,action,target_type,target_id,metadata
  ) values(
    v_clinic,auth.uid(),'client_loyalty_balance_corrected','client',p_client_id::text,
    jsonb_build_object(
      'transaction_id',v_transaction_id,
      'reason',btrim(p_reason),
      'balance_before',v_old_balance,
      'balance_after',p_new_balance,
      'delta',v_delta,
      'actor_role',v_role
    )
  );

  if v_client.user_id is not null then
    insert into public.notifications(
      clinic_id,recipient_user_id,title,body,category,metadata
    ) values(
      v_clinic,v_client.user_id,'Sadakat bakiyeniz güncellendi',
      'Sadakat bakiyeniz klinik tarafından '||p_new_balance::text||' puan olarak güncellendi.',
      'loyalty_balance_corrected',
      jsonb_build_object('old_balance',v_old_balance,'new_balance',p_new_balance,'delta',v_delta)
    );
  end if;

  return jsonb_build_object(
    'client_id',p_client_id,
    'client_name',v_client.full_name,
    'old_balance',v_old_balance,
    'new_balance',p_new_balance,
    'delta',v_delta,
    'transaction_id',v_transaction_id,
    'changed',true
  );
end;
$$;

-- The legacy code-entry fulfillment function is no longer part of the UI.
-- Staff fulfillment is done by redemption id via fulfill_reward_redemption_v54.
revoke execute on function public.fulfill_reward_redemption_v5(text) from authenticated;

revoke all on function public.set_client_loyalty_balance_v55(uuid,int,text) from public;
grant execute on function public.set_client_loyalty_balance_v55(uuid,int,text) to authenticated;
grant execute on function public.add_client_loyalty_points(uuid,int,text) to authenticated;

commit;

-- ============================================================================
-- 016_client_self_service_loyalty_rewards.sql
-- ============================================================================

-- NutriClinic AI v5.6
-- Client self-service loyalty redemption and empty-catalog experience.
-- Run once after migrations 001-015.

begin;

-- The previous staff-issued workflow is no longer exposed as the operative flow.
-- Keep the function for historical compatibility, but prevent direct calls.
revoke execute on function public.issue_reward_coupon_v54(uuid,uuid,text) from authenticated;

create or replace function public.client_redeem_reward_v56(
  p_reward_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_client public.client_profiles%rowtype;
  v_reward public.rewards%rowtype;
  v_wallet_id uuid;
  v_balance integer;
  v_new_balance integer;
  v_transaction_id uuid;
  v_redemption_id uuid;
  v_code text;
  v_dietitian_user_id uuid;
  v_recipient uuid;
begin
  if auth.uid() is null then
    raise exception 'Oturum açmanız gerekir';
  end if;

  select membership.clinic_id,membership.role
    into v_clinic,v_role
  from public.clinic_memberships membership
  where membership.user_id=auth.uid()
    and membership.is_active=true
  limit 1;

  if v_clinic is null or v_role<>'client' then
    raise exception 'Bu işlem yalnızca danışan hesabından yapılabilir';
  end if;

  select client_profile.*
    into v_client
  from public.client_profiles client_profile
  where client_profile.clinic_id=v_clinic
    and client_profile.user_id=auth.uid()
    and client_profile.is_active=true
  limit 1;

  if v_client.id is null then
    raise exception 'Aktif danışan profili bulunamadı';
  end if;

  select reward.*
    into v_reward
  from public.rewards reward
  where reward.id=p_reward_id
    and reward.clinic_id=v_clinic
    and reward.is_active=true
  for update;

  if v_reward.id is null then
    raise exception 'Ödül şu anda kullanıma açık değil';
  end if;

  if v_reward.stock is not null and v_reward.stock<=0 then
    raise exception 'Ödül stoğu tükendi';
  end if;

  insert into public.loyalty_wallets(clinic_id,client_id,balance)
  values(v_clinic,v_client.id,0)
  on conflict(clinic_id,client_id) do nothing;

  select wallet.id,wallet.balance
    into v_wallet_id,v_balance
  from public.loyalty_wallets wallet
  where wallet.clinic_id=v_clinic
    and wallet.client_id=v_client.id
  for update;

  if coalesce(v_balance,0)<v_reward.points_cost then
    raise exception 'Puanınız yetersiz. Gerekli: %, Mevcut: %',v_reward.points_cost,coalesce(v_balance,0);
  end if;

  v_new_balance:=v_balance-v_reward.points_cost;

  update public.loyalty_wallets wallet
  set balance=v_new_balance,
      updated_at=now()
  where wallet.id=v_wallet_id;

  if v_reward.stock is not null then
    update public.rewards reward
    set stock=v_reward.stock-1
    where reward.id=v_reward.id;

    insert into public.reward_stock_movements(
      clinic_id,reward_id,quantity_change,stock_after,reason,created_by
    ) values(
      v_clinic,v_reward.id,-1,v_reward.stock-1,
      'Danışan puanıyla ödül aldı',auth.uid()
    );
  end if;

  insert into public.loyalty_transactions as loyalty_transaction(
    wallet_id,transaction_type,points,reason,reward_id,created_by,balance_after
  ) values(
    v_wallet_id,'redeemed',-v_reward.points_cost,
    'Danışan puanıyla ödül aldı: '||v_reward.name,
    v_reward.id,auth.uid(),v_new_balance
  ) returning loyalty_transaction.id into v_transaction_id;

  loop
    v_code:=upper(substr(md5(gen_random_uuid()::text||clock_timestamp()::text),1,8));
    exit when not exists(
      select 1
      from public.reward_redemptions redemption
      where redemption.redemption_code=v_code
    );
  end loop;

  insert into public.reward_redemptions as reward_redemption(
    clinic_id,client_id,reward_id,loyalty_transaction_id,reward_name,
    points_spent,status,requested_at,note,redemption_code,code_expires_at,updated_at
  ) values(
    v_clinic,v_client.id,v_reward.id,v_transaction_id,v_reward.name,
    v_reward.points_cost,'requested',now(),'Danışan puanıyla oluşturuldu',
    v_code,now()+interval '90 days',now()
  ) returning reward_redemption.id into v_redemption_id;

  -- Notify the client.
  insert into public.notifications(
    clinic_id,recipient_user_id,title,body,category,action_view,metadata,dedupe_key
  ) values(
    v_clinic,auth.uid(),'Sadakat ödülünüz hazır',
    v_reward.name||' ödülünü '||v_reward.points_cost::text||' puan kullanarak aldınız.',
    'loyalty_reward_redeemed','loyalty',
    jsonb_build_object(
      'redemption_id',v_redemption_id,
      'reward_id',v_reward.id,
      'reward_name',v_reward.name,
      'redemption_code',v_code,
      'points_spent',v_reward.points_cost,
      'balance_after',v_new_balance
    ),
    'client-reward-redeemed-'||v_redemption_id::text
  );

  -- Notify clinic owners and the client's assigned dietitian.
  select dietitian_profile.user_id
    into v_dietitian_user_id
  from public.dietitian_profiles dietitian_profile
  where dietitian_profile.id=v_client.assigned_dietitian_id
    and dietitian_profile.clinic_id=v_clinic
  limit 1;

  for v_recipient in
    select distinct recipient.user_id
    from (
      select membership.user_id
      from public.clinic_memberships membership
      where membership.clinic_id=v_clinic
        and membership.is_active=true
        and membership.role='owner'
      union all
      select v_dietitian_user_id
      where v_dietitian_user_id is not null
    ) recipient
    where recipient.user_id is not null
      and recipient.user_id<>auth.uid()
  loop
    insert into public.notifications(
      clinic_id,recipient_user_id,title,body,category,action_view,metadata,dedupe_key
    ) values(
      v_clinic,v_recipient,'Danışan sadakat ödülü aldı',
      v_client.full_name||', '||v_reward.name||' ödülünü puanıyla aldı.',
      'loyalty_reward_redeemed_staff','loyalty',
      jsonb_build_object(
        'redemption_id',v_redemption_id,
        'client_id',v_client.id,
        'client_name',v_client.full_name,
        'member_no',v_client.member_no,
        'reward_id',v_reward.id,
        'reward_name',v_reward.name,
        'redemption_code',v_code,
        'points_spent',v_reward.points_cost,
        'balance_after',v_new_balance
      ),
      'staff-client-reward-redeemed-'||v_redemption_id::text||'-'||v_recipient::text
    );
  end loop;

  insert into public.audit_logs(
    clinic_id,actor_user_id,action,target_type,target_id,metadata
  ) values(
    v_clinic,auth.uid(),'client_reward_redeemed','reward_redemption',v_redemption_id::text,
    jsonb_build_object(
      'client_id',v_client.id,
      'client_name',v_client.full_name,
      'member_no',v_client.member_no,
      'reward_id',v_reward.id,
      'reward_name',v_reward.name,
      'points_spent',v_reward.points_cost,
      'balance_before',v_balance,
      'balance_after',v_new_balance,
      'redemption_code',v_code,
      'stock_after',case when v_reward.stock is null then null else v_reward.stock-1 end
    )
  );

  return jsonb_build_object(
    'redemption_id',v_redemption_id,
    'client_id',v_client.id,
    'reward_id',v_reward.id,
    'reward_name',v_reward.name,
    'points_spent',v_reward.points_cost,
    'balance_before',v_balance,
    'balance_after',v_new_balance,
    'redemption_code',v_code,
    'code_expires_at',now()+interval '90 days'
  );
end;
$$;

revoke all on function public.client_redeem_reward_v56(uuid) from public;
grant execute on function public.client_redeem_reward_v56(uuid) to authenticated;

commit;

-- ============================================================================
-- 017_clinic_operations_sprint.sql
-- ============================================================================

-- NutriClinic AI v6.0
-- Packages/sessions, clinic resources, intake & consent, document center,
-- private messaging, adherence/tasks, and PWA push subscription infrastructure.
-- Run once after migrations 001-016.

begin;

create extension if not exists "btree_gist";

create or replace function public.can_access_client_v6(
  p_client_id uuid,
  p_allow_secretary boolean default false
) returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists (
    select 1
    from public.client_profiles c
    join public.clinic_memberships m
      on m.clinic_id=c.clinic_id and m.user_id=auth.uid() and m.is_active=true
    left join public.dietitian_profiles d on d.id=c.assigned_dietitian_id
    where c.id=p_client_id
      and c.is_active=true
      and (
        c.user_id=auth.uid()
        or m.role='owner'
        or (p_allow_secretary and m.role='secretary')
        or (m.role='dietitian' and d.user_id=auth.uid())
      )
  );
$$;

grant execute on function public.can_access_client_v6(uuid,boolean) to authenticated;

-- SERVICE CATALOG, PACKAGES AND SESSION USAGE
create table if not exists public.service_catalog (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  name text not null,
  category text not null default 'other' check (category in ('consultation','meal_plan','measurement','bodyshape','g5','device','other')),
  description text,
  default_quantity numeric(8,2) not null default 1 check (default_quantity>0),
  default_unit_price numeric(12,2) not null default 0 check (default_unit_price>=0),
  is_active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(clinic_id,name)
);

create table if not exists public.client_packages (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  payment_id uuid references public.payments(id) on delete set null,
  name text not null,
  status text not null default 'active' check (status in ('draft','active','paused','completed','cancelled','expired')),
  starts_on date not null default current_date,
  ends_on date,
  total_price numeric(12,2) not null default 0 check (total_price>=0),
  currency text not null default 'TRY',
  notes text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_on is null or ends_on>=starts_on)
);
create index if not exists client_packages_client_idx on public.client_packages(client_id,created_at desc);

create table if not exists public.client_package_items (
  id uuid primary key default gen_random_uuid(),
  package_id uuid not null references public.client_packages(id) on delete cascade,
  service_id uuid references public.service_catalog(id) on delete set null,
  service_name text not null,
  allocated_quantity numeric(8,2) not null check (allocated_quantity>0),
  used_quantity numeric(8,2) not null default 0 check (used_quantity>=0),
  unit_price numeric(12,2) not null default 0 check (unit_price>=0),
  created_at timestamptz not null default now(),
  check (used_quantity<=allocated_quantity)
);
create index if not exists client_package_items_package_idx on public.client_package_items(package_id);

create table if not exists public.package_usage (
  id uuid primary key default gen_random_uuid(),
  package_item_id uuid not null references public.client_package_items(id) on delete cascade,
  quantity numeric(8,2) not null default 1 check (quantity>0),
  appointment_id uuid references public.appointments(id) on delete set null,
  used_at timestamptz not null default now(),
  performed_by uuid references public.profiles(id) on delete set null,
  note text
);
create index if not exists package_usage_item_idx on public.package_usage(package_item_id,used_at desc);

-- CLINIC DEVICES / ROOMS
create table if not exists public.clinic_resources (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  name text not null,
  resource_type text not null default 'device' check (resource_type in ('device','room','equipment','other')),
  description text,
  capacity integer not null default 1 check (capacity between 1 and 100),
  is_active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(clinic_id,name)
);

create table if not exists public.resource_bookings (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  resource_id uuid not null references public.clinic_resources(id) on delete cascade,
  client_id uuid references public.client_profiles(id) on delete set null,
  appointment_id uuid references public.appointments(id) on delete set null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'confirmed' check (status in ('pending','confirmed','completed','cancelled')),
  note text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at>starts_at),
  exclude using gist (
    resource_id with =,
    tstzrange(starts_at,ends_at,'[)') with &&
  ) where (status in ('pending','confirmed'))
);
create index if not exists resource_bookings_time_idx on public.resource_bookings(clinic_id,starts_at);

-- INTAKE / ANAMNESIS AND CONSENT
create table if not exists public.intake_templates (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  name text not null,
  description text,
  form_schema jsonb not null default '{}'::jsonb,
  version integer not null default 1,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(clinic_id,name,version)
);

create table if not exists public.intake_responses (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  template_id uuid not null references public.intake_templates(id) on delete restrict,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  answers jsonb not null default '{}'::jsonb,
  status text not null default 'draft' check (status in ('draft','submitted','reviewed')),
  submitted_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(template_id,client_id)
);

create table if not exists public.consent_templates (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  name text not null,
  body text not null,
  version integer not null default 1,
  is_required boolean not null default true,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(clinic_id,name,version)
);

create table if not exists public.client_consents (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  template_id uuid not null references public.consent_templates(id) on delete restrict,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  accepted boolean not null default false,
  signature_name text,
  template_version integer not null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  user_agent text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(template_id,client_id)
);

-- DOCUMENT CENTER
create table if not exists public.client_documents (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  category text not null default 'other' check (category in ('laboratory','report','prescription','measurement','meal_plan','consent','payment','administrative','photo','other')),
  title text not null,
  file_name text not null,
  storage_path text not null unique,
  mime_type text,
  size_bytes bigint,
  document_date date,
  notes text,
  visible_to_client boolean not null default true,
  uploaded_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);
create index if not exists client_documents_client_idx on public.client_documents(client_id,created_at desc);

-- PRIVATE CLIENT-DIETITIAN MESSAGING
create table if not exists public.direct_conversations (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  dietitian_id uuid not null references public.dietitian_profiles(id) on delete cascade,
  status text not null default 'active' check (status in ('active','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(client_id,dietitian_id)
);

create table if not exists public.direct_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.direct_conversations(id) on delete cascade,
  sender_user_id uuid not null references public.profiles(id) on delete cascade,
  body text,
  attachment_path text,
  attachment_name text,
  attachment_type text,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  check (nullif(trim(coalesce(body,'')),'') is not null or attachment_path is not null)
);
create index if not exists direct_messages_conversation_idx on public.direct_messages(conversation_id,created_at);

-- TASKS AND ADHERENCE
create table if not exists public.client_tasks (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  assigned_by uuid not null references public.profiles(id) on delete restrict,
  title text not null,
  description text,
  task_type text not null default 'habit' check (task_type in ('water','activity','meal_photo','weight','document','habit','other')),
  due_date date,
  status text not null default 'pending' check (status in ('pending','completed','skipped','cancelled')),
  points_reward integer not null default 0 check (points_reward>=0),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists client_tasks_client_idx on public.client_tasks(client_id,status,due_date);

-- PWA PUSH SUBSCRIPTIONS
create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth_key text not null,
  user_agent text,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index if not exists push_subscriptions_user_idx on public.push_subscriptions(user_id);

create table if not exists public.push_delivery_logs (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.notifications(id) on delete cascade,
  subscription_id uuid not null references public.push_subscriptions(id) on delete cascade,
  status text not null default 'sent' check (status in ('sent','failed','expired')),
  error_message text,
  created_at timestamptz not null default now(),
  unique(notification_id,subscription_id)
);

-- DEFAULT SERVICE, INTAKE AND CONSENT TEMPLATES
insert into public.service_catalog(clinic_id,name,category,description,default_quantity,default_unit_price)
select c.id,x.name,x.category,x.description,x.qty,x.price
from public.clinics c
cross join (values
  ('İlk Görüşme','consultation','İlk değerlendirme ve planlama',1::numeric,0::numeric),
  ('Kontrol Görüşmesi','consultation','Kontrol ve plan güncelleme',1::numeric,0::numeric),
  ('Haftalık Menü','meal_plan','Bir haftalık kişiye özel menü',1::numeric,0::numeric),
  ('Vücut Analizi','measurement','Ayrıntılı vücut kompozisyon ölçümü',1::numeric,0::numeric),
  ('BodyShape Seansı','bodyshape','BodyShape cihaz kullanımı',1::numeric,0::numeric),
  ('G5 Seansı','g5','G5 uygulama seansı',1::numeric,0::numeric)
) as x(name,category,description,qty,price)
on conflict(clinic_id,name) do nothing;

insert into public.intake_templates(clinic_id,name,description,form_schema,version)
select c.id,'İlk Görüşme Anamnez Formu','Danışanın sağlık ve yaşam öyküsünü görüşme öncesinde toplar',
  '{"sections":["health_history","medications","operations","digestion","sleep","tobacco_alcohol","activity","nutrition_history","emotional_eating","women_health","notes"]}'::jsonb,1
from public.clinics c
where not exists(select 1 from public.intake_templates t where t.clinic_id=c.id and t.name='İlk Görüşme Anamnez Formu' and t.version=1);

insert into public.consent_templates(clinic_id,name,body,version,is_required)
select c.id,x.name,x.body,1,x.required
from public.clinics c
cross join (values
  ('Aydınlatma ve Veri İşleme Onayı','Kişisel ve klinik verilerimin hizmetin yürütülmesi amacıyla işlenmesine ilişkin aydınlatma metnini okudum ve anladım.',true),
  ('Online Danışmanlık Onayı','Online görüşmenin kapsamı, sınırları ve teknik koşulları hakkında bilgilendirildim.',false),
  ('Fotoğraf ve Belge Yükleme Onayı','Öğün, ilerleme ve klinik belge görsellerinin yalnızca yetkili klinik ekibi tarafından görüntülenmesini kabul ediyorum.',false),
  ('Paket, İptal ve Randevu Koşulları','Paket kullanımı, randevu değişikliği ve iptal koşullarını okudum ve kabul ediyorum.',true)
) as x(name,body,required)
where not exists(select 1 from public.consent_templates t where t.clinic_id=c.id and t.name=x.name and t.version=1);

-- RLS
alter table public.service_catalog enable row level security;
alter table public.client_packages enable row level security;
alter table public.client_package_items enable row level security;
alter table public.package_usage enable row level security;
alter table public.clinic_resources enable row level security;
alter table public.resource_bookings enable row level security;
alter table public.intake_templates enable row level security;
alter table public.intake_responses enable row level security;
alter table public.consent_templates enable row level security;
alter table public.client_consents enable row level security;
alter table public.client_documents enable row level security;
alter table public.direct_conversations enable row level security;
alter table public.direct_messages enable row level security;
alter table public.client_tasks enable row level security;
alter table public.push_subscriptions enable row level security;
alter table public.push_delivery_logs enable row level security;

drop policy if exists service_catalog_read on public.service_catalog;
create policy service_catalog_read on public.service_catalog for select to authenticated
using (public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary'));
drop policy if exists service_catalog_manage on public.service_catalog;
create policy service_catalog_manage on public.service_catalog for all to authenticated
using (public.current_clinic_role(clinic_id)='owner')
with check (public.current_clinic_role(clinic_id)='owner');

drop policy if exists client_packages_read on public.client_packages;
create policy client_packages_read on public.client_packages for select to authenticated
using (public.can_access_client_v6(client_id,true));
drop policy if exists client_packages_manage on public.client_packages;
create policy client_packages_manage on public.client_packages for all to authenticated
using (public.current_clinic_role(clinic_id) in ('owner','secretary'))
with check (public.current_clinic_role(clinic_id) in ('owner','secretary'));

drop policy if exists package_items_read on public.client_package_items;
create policy package_items_read on public.client_package_items for select to authenticated
using (exists(select 1 from public.client_packages p where p.id=package_id and public.can_access_client_v6(p.client_id,true)));
drop policy if exists package_items_manage on public.client_package_items;
create policy package_items_manage on public.client_package_items for all to authenticated
using (exists(select 1 from public.client_packages p where p.id=package_id and public.current_clinic_role(p.clinic_id) in ('owner','secretary')))
with check (exists(select 1 from public.client_packages p where p.id=package_id and public.current_clinic_role(p.clinic_id) in ('owner','secretary')));

drop policy if exists package_usage_read on public.package_usage;
create policy package_usage_read on public.package_usage for select to authenticated
using (exists(select 1 from public.client_package_items i join public.client_packages p on p.id=i.package_id where i.id=package_item_id and public.can_access_client_v6(p.client_id,true)));

drop policy if exists resources_staff_read on public.clinic_resources;
create policy resources_staff_read on public.clinic_resources for select to authenticated
using (public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary'));
drop policy if exists resources_owner_manage on public.clinic_resources;
create policy resources_owner_manage on public.clinic_resources for all to authenticated
using (public.current_clinic_role(clinic_id)='owner')
with check (public.current_clinic_role(clinic_id)='owner');

drop policy if exists resource_bookings_staff on public.resource_bookings;
create policy resource_bookings_staff on public.resource_bookings for all to authenticated
using (public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary'))
with check (public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary'));

drop policy if exists intake_templates_read on public.intake_templates;
create policy intake_templates_read on public.intake_templates for select to authenticated
using (public.current_clinic_role(clinic_id) is not null);
drop policy if exists intake_templates_owner on public.intake_templates;
create policy intake_templates_owner on public.intake_templates for all to authenticated
using (public.current_clinic_role(clinic_id)='owner')
with check (public.current_clinic_role(clinic_id)='owner');

drop policy if exists intake_responses_read on public.intake_responses;
create policy intake_responses_read on public.intake_responses for select to authenticated
using (public.can_access_client_v6(client_id,false));
drop policy if exists intake_responses_client_insert on public.intake_responses;
create policy intake_responses_client_insert on public.intake_responses for insert to authenticated
with check (client_id=public.current_client_id(clinic_id));
drop policy if exists intake_responses_client_update on public.intake_responses;
create policy intake_responses_client_update on public.intake_responses for update to authenticated
using (client_id=public.current_client_id(clinic_id) or public.can_access_client_v6(client_id,false))
with check (client_id=public.current_client_id(clinic_id) or public.can_access_client_v6(client_id,false));

drop policy if exists consent_templates_read on public.consent_templates;
create policy consent_templates_read on public.consent_templates for select to authenticated
using (public.current_clinic_role(clinic_id) is not null);
drop policy if exists consent_templates_owner on public.consent_templates;
create policy consent_templates_owner on public.consent_templates for all to authenticated
using (public.current_clinic_role(clinic_id)='owner')
with check (public.current_clinic_role(clinic_id)='owner');

drop policy if exists client_consents_read on public.client_consents;
create policy client_consents_read on public.client_consents for select to authenticated
using (public.can_access_client_v6(client_id,false));
drop policy if exists client_consents_client_write on public.client_consents;
create policy client_consents_client_write on public.client_consents for insert to authenticated
with check (client_id=public.current_client_id(clinic_id));
drop policy if exists client_consents_client_update on public.client_consents;
create policy client_consents_client_update on public.client_consents for update to authenticated
using (client_id=public.current_client_id(clinic_id))
with check (client_id=public.current_client_id(clinic_id));

drop policy if exists client_documents_read on public.client_documents;
create policy client_documents_read on public.client_documents for select to authenticated
using (
  (client_id=public.current_client_id(clinic_id) and visible_to_client)
  or public.can_access_client_v6(client_id,false)
  or (public.current_clinic_role(clinic_id)='secretary' and category in ('payment','administrative'))
);
drop policy if exists client_documents_insert on public.client_documents;
create policy client_documents_insert on public.client_documents for insert to authenticated
with check (
  uploaded_by=auth.uid()
  and (
    client_id=public.current_client_id(clinic_id)
    or public.can_access_client_v6(client_id,false)
    or (public.current_clinic_role(clinic_id)='secretary' and category in ('payment','administrative'))
  )
);
drop policy if exists client_documents_delete on public.client_documents;
create policy client_documents_delete on public.client_documents for delete to authenticated
using (uploaded_by=auth.uid() or public.current_clinic_role(clinic_id)='owner');

drop policy if exists conversations_read on public.direct_conversations;
create policy conversations_read on public.direct_conversations for select to authenticated
using (
  exists(select 1 from public.client_profiles c where c.id=client_id and c.user_id=auth.uid())
  or exists(select 1 from public.dietitian_profiles d where d.id=dietitian_id and d.user_id=auth.uid())
  or public.current_clinic_role(clinic_id)='owner'
);

drop policy if exists messages_read on public.direct_messages;
create policy messages_read on public.direct_messages for select to authenticated
using (exists(select 1 from public.direct_conversations c where c.id=conversation_id and (
  public.current_clinic_role(c.clinic_id)='owner'
  or exists(select 1 from public.client_profiles cp where cp.id=c.client_id and cp.user_id=auth.uid())
  or exists(select 1 from public.dietitian_profiles dp where dp.id=c.dietitian_id and dp.user_id=auth.uid())
)));
drop policy if exists messages_insert on public.direct_messages;
create policy messages_insert on public.direct_messages for insert to authenticated
with check (sender_user_id=auth.uid() and exists(select 1 from public.direct_conversations c where c.id=conversation_id and (
  public.current_clinic_role(c.clinic_id)='owner'
  or exists(select 1 from public.client_profiles cp where cp.id=c.client_id and cp.user_id=auth.uid())
  or exists(select 1 from public.dietitian_profiles dp where dp.id=c.dietitian_id and dp.user_id=auth.uid())
)));
drop policy if exists messages_update on public.direct_messages;
create policy messages_update on public.direct_messages for update to authenticated
using (exists(select 1 from public.direct_conversations c where c.id=conversation_id and (
  public.current_clinic_role(c.clinic_id)='owner'
  or exists(select 1 from public.client_profiles cp where cp.id=c.client_id and cp.user_id=auth.uid())
  or exists(select 1 from public.dietitian_profiles dp where dp.id=c.dietitian_id and dp.user_id=auth.uid())
)));

drop policy if exists client_tasks_read on public.client_tasks;
create policy client_tasks_read on public.client_tasks for select to authenticated
using (public.can_access_client_v6(client_id,false));
drop policy if exists client_tasks_staff_manage on public.client_tasks;
create policy client_tasks_staff_manage on public.client_tasks for all to authenticated
using (public.can_access_client_v6(client_id,false) and public.current_clinic_role(clinic_id) in ('owner','dietitian'))
with check (public.can_access_client_v6(client_id,false) and public.current_clinic_role(clinic_id) in ('owner','dietitian'));

drop policy if exists push_subscriptions_own on public.push_subscriptions;
create policy push_subscriptions_own on public.push_subscriptions for all to authenticated
using (user_id=auth.uid()) with check (user_id=auth.uid());

drop policy if exists push_delivery_logs_own_read on public.push_delivery_logs;
create policy push_delivery_logs_own_read on public.push_delivery_logs for select to authenticated
using (exists(select 1 from public.push_subscriptions s where s.id=subscription_id and s.user_id=auth.uid()));

-- STORAGE BUCKETS
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('client-documents','client-documents',false,15728640,array['application/pdf','image/jpeg','image/png','image/webp','application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict(id) do update set public=false,file_size_limit=15728640,allowed_mime_types=excluded.allowed_mime_types;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('direct-message-media','direct-message-media',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf','audio/mpeg','audio/mp4','audio/webm'])
on conflict(id) do update set public=false,file_size_limit=10485760,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists client_documents_storage_insert on storage.objects;
create policy client_documents_storage_insert on storage.objects for insert to authenticated
with check (bucket_id='client-documents' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists client_documents_storage_read on storage.objects;
create policy client_documents_storage_read on storage.objects for select to authenticated
using (bucket_id='client-documents' and exists(select 1 from public.client_documents d where d.storage_path=name and (
  (d.client_id=public.current_client_id(d.clinic_id) and d.visible_to_client)
  or public.can_access_client_v6(d.client_id,false)
  or (public.current_clinic_role(d.clinic_id)='secretary' and d.category in ('payment','administrative'))
)));
drop policy if exists client_documents_storage_delete on storage.objects;
create policy client_documents_storage_delete on storage.objects for delete to authenticated
using (bucket_id='client-documents' and ((storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from public.client_documents d where d.storage_path=name and public.current_clinic_role(d.clinic_id)='owner')));

drop policy if exists direct_message_media_insert on storage.objects;
create policy direct_message_media_insert on storage.objects for insert to authenticated
with check (bucket_id='direct-message-media' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists direct_message_media_read on storage.objects;
create policy direct_message_media_read on storage.objects for select to authenticated
using (bucket_id='direct-message-media' and exists(select 1 from public.direct_messages m join public.direct_conversations c on c.id=m.conversation_id where m.attachment_path=name and (
  public.current_clinic_role(c.clinic_id)='owner'
  or exists(select 1 from public.client_profiles cp where cp.id=c.client_id and cp.user_id=auth.uid())
  or exists(select 1 from public.dietitian_profiles dp where dp.id=c.dietitian_id and dp.user_id=auth.uid())
)));

-- ATOMIC PACKAGE USAGE
create or replace function public.consume_package_item_v6(
  p_package_item_id uuid,
  p_quantity numeric default 1,
  p_appointment_id uuid default null,
  p_note text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_item public.client_package_items%rowtype;
  v_package public.client_packages%rowtype;
  v_role public.clinic_role;
  v_client_user uuid;
  v_remaining numeric;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_quantity<=0 then raise exception 'Quantity must be positive'; end if;

  select * into v_item from public.client_package_items where id=p_package_item_id for update;
  if v_item.id is null then raise exception 'Package item not found'; end if;
  select * into v_package from public.client_packages where id=v_item.package_id for update;
  v_role:=public.current_clinic_role(v_package.clinic_id);
  if v_role is null or v_role not in ('owner','dietitian','secretary') then raise exception 'Staff access required'; end if;
  if v_role='dietitian' and not public.can_access_client_v6(v_package.client_id,false) then raise exception 'Client access denied'; end if;
  if v_item.used_quantity+p_quantity>v_item.allocated_quantity then raise exception 'Insufficient remaining sessions'; end if;

  update public.client_package_items set used_quantity=used_quantity+p_quantity where id=v_item.id;
  insert into public.package_usage(package_item_id,quantity,appointment_id,performed_by,note)
  values(v_item.id,p_quantity,p_appointment_id,auth.uid(),nullif(trim(coalesce(p_note,'')),''));

  v_remaining:=v_item.allocated_quantity-(v_item.used_quantity+p_quantity);
  select user_id into v_client_user from public.client_profiles where id=v_package.client_id;
  if v_client_user is not null then
    insert into public.notifications(clinic_id,recipient_user_id,title,body,category,metadata)
    values(v_package.clinic_id,v_client_user,'Paket kullanımınız güncellendi',v_item.service_name||' için kalan kullanım: '||v_remaining::text,'package',jsonb_build_object('view','packages','package_id',v_package.id));
  end if;

  if not exists(select 1 from public.client_package_items i where i.package_id=v_package.id and i.used_quantity<i.allocated_quantity) then
    update public.client_packages set status='completed',updated_at=now() where id=v_package.id;
  end if;

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values(v_package.clinic_id,auth.uid(),'consume_package_item','client_package_item',v_item.id::text,jsonb_build_object('quantity',p_quantity,'remaining',v_remaining,'client_id',v_package.client_id));
  return jsonb_build_object('remaining',v_remaining,'package_id',v_package.id,'service_name',v_item.service_name);
end;
$$;
grant execute on function public.consume_package_item_v6(uuid,numeric,uuid,text) to authenticated;

create or replace function public.ensure_direct_conversation_v6(p_client_id uuid)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_client public.client_profiles%rowtype;
  v_dietitian uuid;
  v_conversation uuid;
  v_role public.clinic_role;
begin
  select * into v_client from public.client_profiles where id=p_client_id and is_active=true;
  if v_client.id is null then raise exception 'Client not found'; end if;
  v_role:=public.current_clinic_role(v_client.clinic_id);
  if not public.can_access_client_v6(p_client_id,false) then raise exception 'Access denied'; end if;
  v_dietitian:=v_client.assigned_dietitian_id;
  if v_dietitian is null then raise exception 'Assigned dietitian not found'; end if;

  insert into public.direct_conversations(clinic_id,client_id,dietitian_id,status)
  values(v_client.clinic_id,p_client_id,v_dietitian,'active')
  on conflict(client_id,dietitian_id) do update set status='active',updated_at=now()
  returning id into v_conversation;
  return v_conversation;
end;
$$;
grant execute on function public.ensure_direct_conversation_v6(uuid) to authenticated;

create or replace function public.set_client_task_status_v6(p_task_id uuid,p_status text)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_task public.client_tasks%rowtype;
  v_wallet uuid;
begin
  if p_status not in ('pending','completed','skipped') then raise exception 'Invalid task status'; end if;
  select * into v_task from public.client_tasks where id=p_task_id for update;
  if v_task.id is null then raise exception 'Task not found'; end if;
  if v_task.client_id<>public.current_client_id(v_task.clinic_id) then raise exception 'Client access required'; end if;
  if v_task.status='completed' and p_status<>'completed' then raise exception 'Completed tasks cannot be reopened by client'; end if;

  update public.client_tasks
  set status=p_status,completed_at=case when p_status='completed' then now() else null end,updated_at=now()
  where id=p_task_id;

  if p_status='completed' and v_task.status<>'completed' and v_task.points_reward>0 then
    select id into v_wallet from public.loyalty_wallets where clinic_id=v_task.clinic_id and client_id=v_task.client_id for update;
    update public.loyalty_wallets set balance=balance+v_task.points_reward,updated_at=now() where id=v_wallet;
    insert into public.loyalty_transactions(wallet_id,transaction_type,points,reason,created_by)
    values(v_wallet,'earned',v_task.points_reward,'Görev tamamlandı: '||v_task.title,auth.uid());
  end if;
end;
$$;
grant execute on function public.set_client_task_status_v6(uuid,text) to authenticated;

create or replace function public.get_client_adherence_v6(p_client_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_client uuid;
  v_clinic uuid;
  v_attendance numeric:=0;
  v_meals numeric:=0;
  v_water numeric:=0;
  v_activity numeric:=0;
  v_tasks numeric:=0;
  v_total numeric:=0;
  v_completed int:=0;
  v_outcomes int:=0;
  v_meal_days int:=0;
  v_water_days int:=0;
  v_activity_days int:=0;
  v_task_total int:=0;
  v_task_done int:=0;
begin
  if p_client_id is null then
    select c.id,c.clinic_id into v_client,v_clinic from public.client_profiles c where c.user_id=auth.uid() and c.is_active=true limit 1;
  else
    select c.id,c.clinic_id into v_client,v_clinic from public.client_profiles c where c.id=p_client_id and c.is_active=true;
  end if;
  if v_client is null then raise exception 'Client not found'; end if;
  if not public.can_access_client_v6(v_client,false) then raise exception 'Access denied'; end if;

  select count(*) filter(where status='completed'),count(*) filter(where status in ('completed','cancelled','no_show'))
  into v_completed,v_outcomes from public.appointments
  where client_id=v_client and starts_at>=now()-interval '30 days';
  v_attendance:=case when v_outcomes=0 then 100 else round(100.0*v_completed/v_outcomes,1) end;

  select count(distinct consumed_on) into v_meal_days from public.meal_completions where client_id=v_client and consumed_on>=current_date-13;
  v_meals:=least(100,round(100.0*v_meal_days/14,1));

  select count(distinct log_date) into v_water_days from public.daily_water_logs where client_id=v_client and log_date>=current_date-13 and amount_ml>0;
  v_water:=least(100,round(100.0*v_water_days/14,1));

  select count(distinct activity_date) into v_activity_days from public.activity_logs where client_id=v_client and activity_date>=current_date-13;
  v_activity:=least(100,round(100.0*v_activity_days/14,1));

  select count(*),count(*) filter(where status='completed') into v_task_total,v_task_done
  from public.client_tasks where client_id=v_client and created_at>=now()-interval '30 days' and status<>'cancelled';
  v_tasks:=case when v_task_total=0 then 100 else round(100.0*v_task_done/v_task_total,1) end;

  v_total:=round(v_attendance*0.30+v_meals*0.30+v_water*0.15+v_activity*0.15+v_tasks*0.10,1);
  return jsonb_build_object(
    'score',v_total,
    'risk',case when v_total>=80 then 'low' when v_total>=55 then 'medium' else 'high' end,
    'attendance',v_attendance,
    'meal_tracking',v_meals,
    'water_tracking',v_water,
    'activity_tracking',v_activity,
    'tasks',v_tasks,
    'period_days',30
  );
end;
$$;
grant execute on function public.get_client_adherence_v6(uuid) to authenticated;

-- Automatic in-app notifications for new operational records.
create or replace function public.notify_package_created_v6()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_user uuid;
begin
  select user_id into v_user from public.client_profiles where id=new.client_id;
  if v_user is not null then
    insert into public.notifications(clinic_id,recipient_user_id,title,body,category,action_view,metadata)
    values(new.clinic_id,v_user,'Yeni hizmet paketi tanımlandı',new.name||' paketi hesabınıza eklendi.','package','packages',jsonb_build_object('package_id',new.id));
  end if;
  return new;
end;
$$;
drop trigger if exists trg_notify_package_created_v6 on public.client_packages;
create trigger trg_notify_package_created_v6 after insert on public.client_packages
for each row execute function public.notify_package_created_v6();

create or replace function public.notify_task_created_v6()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_user uuid;
begin
  select user_id into v_user from public.client_profiles where id=new.client_id;
  if v_user is not null then
    insert into public.notifications(clinic_id,recipient_user_id,title,body,category,action_view,metadata)
    values(new.clinic_id,v_user,'Yeni takip göreviniz var',new.title,'task','followup',jsonb_build_object('task_id',new.id));
  end if;
  return new;
end;
$$;
drop trigger if exists trg_notify_task_created_v6 on public.client_tasks;
create trigger trg_notify_task_created_v6 after insert on public.client_tasks
for each row execute function public.notify_task_created_v6();

create or replace function public.notify_direct_message_v6()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_conversation public.direct_conversations%rowtype;
  v_client_user uuid;
  v_dietitian_user uuid;
  v_recipient uuid;
  v_sender_name text;
begin
  select * into v_conversation from public.direct_conversations where id=new.conversation_id;
  select user_id into v_client_user from public.client_profiles where id=v_conversation.client_id;
  select user_id into v_dietitian_user from public.dietitian_profiles where id=v_conversation.dietitian_id;
  v_recipient:=case when new.sender_user_id=v_client_user then v_dietitian_user else v_client_user end;
  select full_name into v_sender_name from public.profiles where id=new.sender_user_id;
  if v_recipient is not null then
    insert into public.notifications(clinic_id,recipient_user_id,title,body,category,action_view,metadata)
    values(v_conversation.clinic_id,v_recipient,coalesce(v_sender_name,'NutriClinic')||' yeni mesaj gönderdi',coalesce(nullif(left(new.body,120),''),'Yeni bir dosya gönderildi.'),'message','messages',jsonb_build_object('conversation_id',new.conversation_id));
  end if;
  return new;
end;
$$;
drop trigger if exists trg_notify_direct_message_v6 on public.direct_messages;
create trigger trg_notify_direct_message_v6 after insert on public.direct_messages
for each row execute function public.notify_direct_message_v6();

-- Realtime messaging and task updates.
do $$
begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='direct_messages') then
    alter publication supabase_realtime add table public.direct_messages;
  end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='client_tasks') then
    alter publication supabase_realtime add table public.client_tasks;
  end if;
exception when undefined_object then null;
end $$;

commit;

-- ============================================================================
-- 018_client_device_booking.sql
-- ============================================================================

-- NutriClinic AI v6.2
-- Client self-service device booking and clinical resource management.
-- Run once after 017_clinic_operations_sprint.sql.

begin;

alter table public.clinic_resources
  add column if not exists client_bookable boolean not null default false,
  add column if not exists slot_minutes integer not null default 45,
  add column if not exists booking_start_time time not null default '09:00',
  add column if not exists booking_end_time time not null default '18:00';

alter table public.clinic_resources
  drop constraint if exists clinic_resources_slot_minutes_check;
alter table public.clinic_resources
  add constraint clinic_resources_slot_minutes_check check (slot_minutes between 15 and 240);

alter table public.clinic_resources
  drop constraint if exists clinic_resources_booking_hours_check;
alter table public.clinic_resources
  add constraint clinic_resources_booking_hours_check check (booking_end_time > booking_start_time);

-- Existing devices/equipment become client-bookable by default.
update public.clinic_resources
set client_bookable=true
where resource_type in ('device','equipment') and client_bookable=false;

-- Clients may read the clinic's resource catalogue. Only clinical roles may manage it.
drop policy if exists resources_staff_read on public.clinic_resources;
drop policy if exists resources_owner_manage on public.clinic_resources;
drop policy if exists resources_member_read_v6_2 on public.clinic_resources;
create policy resources_member_read_v6_2 on public.clinic_resources
for select to authenticated
using (public.current_clinic_role(clinic_id) is not null);

drop policy if exists resources_clinical_manage_v6_2 on public.clinic_resources;
create policy resources_clinical_manage_v6_2 on public.clinic_resources
for all to authenticated
using (public.current_clinic_role(clinic_id) in ('owner','dietitian'))
with check (public.current_clinic_role(clinic_id) in ('owner','dietitian'));

-- Direct booking-table management remains staff-only. Clients use security-definer RPCs below.
drop policy if exists resource_bookings_staff on public.resource_bookings;
drop policy if exists resource_bookings_staff_v6_2 on public.resource_bookings;
create policy resource_bookings_staff_v6_2 on public.resource_bookings
for all to authenticated
using (public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary'))
with check (
  public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary')
  and (client_id is null or exists(
    select 1 from public.client_profiles cp where cp.id=client_id and cp.clinic_id=clinic_id and cp.is_active=true
  ))
);

create or replace function public.get_resource_schedule_v6_2(
  p_clinic_id uuid,
  p_start timestamptz,
  p_end timestamptz
) returns table(
  booking_id uuid,
  resource_id uuid,
  resource_name text,
  resource_type text,
  client_id uuid,
  client_name text,
  client_email text,
  client_phone text,
  starts_at timestamptz,
  ends_at timestamptz,
  status text,
  note text,
  is_mine boolean
)
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_role public.clinic_role;
  v_client_id uuid;
begin
  v_role:=public.current_clinic_role(p_clinic_id);
  if v_role is null then
    raise exception 'Clinic access required';
  end if;

  v_client_id:=public.current_client_id(p_clinic_id);

  return query
  select
    case when v_role in ('owner','dietitian','secretary') or rb.client_id=v_client_id then rb.id else null end,
    rb.resource_id,
    cr.name,
    cr.resource_type,
    case when v_role in ('owner','dietitian','secretary') or rb.client_id=v_client_id then rb.client_id else null end,
    case when v_role in ('owner','dietitian','secretary') or rb.client_id=v_client_id then cp.full_name else null end,
    case when v_role in ('owner','dietitian','secretary') or rb.client_id=v_client_id then p.email else null end,
    case when v_role in ('owner','dietitian','secretary') or rb.client_id=v_client_id then p.phone else null end,
    rb.starts_at,
    rb.ends_at,
    rb.status,
    case when v_role in ('owner','dietitian','secretary') or rb.client_id=v_client_id then rb.note else null end,
    rb.client_id=v_client_id
  from public.resource_bookings rb
  join public.clinic_resources cr on cr.id=rb.resource_id
  left join public.client_profiles cp on cp.id=rb.client_id
  left join public.profiles p on p.id=cp.user_id
  where rb.clinic_id=p_clinic_id
    and rb.status<>'cancelled'
    and rb.starts_at<p_end
    and rb.ends_at>p_start
  order by rb.starts_at;
end;
$$;

create or replace function public.create_client_resource_booking_v6_2(
  p_clinic_id uuid,
  p_resource_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_note text default null
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_role public.clinic_role;
  v_client_id uuid;
  v_resource public.clinic_resources%rowtype;
  v_booking_id uuid;
  v_timezone text;
begin
  v_role:=public.current_clinic_role(p_clinic_id);
  if v_role<>'client' then
    raise exception 'Client access required';
  end if;

  v_client_id:=public.current_client_id(p_clinic_id);
  if v_client_id is null then
    raise exception 'Danışan profili bulunamadı';
  end if;

  select * into v_resource
  from public.clinic_resources
  where id=p_resource_id and clinic_id=p_clinic_id and is_active=true and client_bookable=true;

  select timezone into v_timezone from public.clinics where id=p_clinic_id;

  if not found then
    raise exception 'Bu cihaz danışan rezervasyonuna açık değil';
  end if;

  if p_starts_at<=now() then
    raise exception 'Geçmiş bir saate rezervasyon yapılamaz';
  end if;
  if p_ends_at<=p_starts_at then
    raise exception 'Bitiş saati başlangıçtan sonra olmalıdır';
  end if;
  if extract(epoch from (p_ends_at-p_starts_at))/60 > 240 then
    raise exception 'Bir cihaz rezervasyonu en fazla 4 saat olabilir';
  end if;
  if (p_starts_at at time zone coalesce(v_timezone,'Europe/Istanbul'))::time < v_resource.booking_start_time
     or (p_ends_at at time zone coalesce(v_timezone,'Europe/Istanbul'))::time > v_resource.booking_end_time then
    raise exception 'Seçilen saat cihazın rezervasyon saatleri dışındadır';
  end if;

  insert into public.resource_bookings(
    clinic_id,resource_id,client_id,starts_at,ends_at,status,note,created_by
  ) values(
    p_clinic_id,p_resource_id,v_client_id,p_starts_at,p_ends_at,'pending',nullif(trim(coalesce(p_note,'')),''),auth.uid()
  ) returning id into v_booking_id;

  return v_booking_id;
exception
  when exclusion_violation then
    raise exception 'Bu cihaz seçilen saatte dolu';
end;
$$;

create or replace function public.cancel_client_resource_booking_v6_2(
  p_booking_id uuid
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_booking public.resource_bookings%rowtype;
begin
  select * into v_booking from public.resource_bookings where id=p_booking_id;
  if not found then raise exception 'Rezervasyon bulunamadı'; end if;
  if v_booking.client_id<>public.current_client_id(v_booking.clinic_id) then
    raise exception 'Bu rezervasyonu iptal etme yetkiniz yok';
  end if;
  if v_booking.starts_at<=now() then
    raise exception 'Başlamış veya geçmiş rezervasyon iptal edilemez';
  end if;
  if v_booking.status not in ('pending','confirmed') then
    raise exception 'Bu rezervasyon iptal edilemez';
  end if;

  update public.resource_bookings
  set status='cancelled',updated_at=now()
  where id=p_booking_id;
end;
$$;

create or replace function public.set_resource_booking_status_v6_2(
  p_booking_id uuid,
  p_status text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_booking public.resource_bookings%rowtype;
begin
  if p_status not in ('pending','confirmed','completed','cancelled') then
    raise exception 'Geçersiz rezervasyon durumu';
  end if;
  select * into v_booking from public.resource_bookings where id=p_booking_id;
  if not found then raise exception 'Rezervasyon bulunamadı'; end if;
  if public.current_clinic_role(v_booking.clinic_id) not in ('owner','dietitian','secretary') then
    raise exception 'Yetkiniz yok';
  end if;
  update public.resource_bookings set status=p_status,updated_at=now() where id=p_booking_id;
end;
$$;

create or replace function public.archive_clinic_resource_v6_2(
  p_resource_id uuid
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
begin
  select clinic_id into v_clinic from public.clinic_resources where id=p_resource_id;
  if v_clinic is null then raise exception 'Cihaz bulunamadı'; end if;
  if public.current_clinic_role(v_clinic) not in ('owner','dietitian') then
    raise exception 'Yetkiniz yok';
  end if;

  if exists(
    select 1 from public.resource_bookings
    where resource_id=p_resource_id and status in ('pending','confirmed') and ends_at>now()
  ) then
    raise exception 'Yaklaşan rezervasyonları bulunan cihaz silinemez. Önce rezervasyonları iptal edin';
  end if;

  update public.clinic_resources set is_active=false where id=p_resource_id;
end;
$$;

create or replace function public.notify_resource_booking_v6_2()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_resource_name text;
  v_client_user uuid;
  v_client_name text;
  v_staff record;
  v_title text;
  v_body text;
begin
  select name into v_resource_name from public.clinic_resources where id=new.resource_id;
  select cp.user_id,cp.full_name into v_client_user,v_client_name from public.client_profiles cp where cp.id=new.client_id;

  if tg_op='INSERT' and new.status='pending' and new.client_id is not null then
    for v_staff in
      select user_id from public.clinic_memberships
      where clinic_id=new.clinic_id and role in ('owner','dietitian','secretary') and is_active=true
    loop
      perform public.create_app_notification_v5(
        new.clinic_id,v_staff.user_id,'Yeni cihaz randevu talebi',
        coalesce(v_client_name,'Danışan')||' • '||coalesce(v_resource_name,'Cihaz')||' • '||to_char(new.starts_at,'DD.MM.YYYY HH24:MI'),
        'resource_booking','resources',jsonb_build_object('booking_id',new.id,'resource_id',new.resource_id),
        'resource_booking:'||new.id::text||':staff:pending:'||v_staff.user_id::text
      );
    end loop;
  end if;

  if v_client_user is not null and (tg_op='INSERT' or old.status is distinct from new.status) then
    v_title:=case new.status
      when 'pending' then 'Cihaz randevu talebiniz alındı'
      when 'confirmed' then 'Cihaz randevunuz onaylandı'
      when 'completed' then 'Cihaz randevunuz tamamlandı'
      when 'cancelled' then 'Cihaz randevunuz iptal edildi'
      else 'Cihaz randevunuz güncellendi' end;
    v_body:=coalesce(v_resource_name,'Cihaz')||' • '||to_char(new.starts_at,'DD.MM.YYYY HH24:MI');
    perform public.create_app_notification_v5(
      new.clinic_id,v_client_user,v_title,v_body,'resource_booking','resources',
      jsonb_build_object('booking_id',new.id,'resource_id',new.resource_id,'status',new.status),
      'resource_booking:'||new.id::text||':client:'||new.status
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_resource_booking_v6_2 on public.resource_bookings;
create trigger trg_notify_resource_booking_v6_2
after insert or update of status on public.resource_bookings
for each row execute function public.notify_resource_booking_v6_2();

grant execute on function public.get_resource_schedule_v6_2(uuid,timestamptz,timestamptz) to authenticated;
grant execute on function public.create_client_resource_booking_v6_2(uuid,uuid,timestamptz,timestamptz,text) to authenticated;
grant execute on function public.cancel_client_resource_booking_v6_2(uuid) to authenticated;
grant execute on function public.set_resource_booking_status_v6_2(uuid,text) to authenticated;
grant execute on function public.archive_clinic_resource_v6_2(uuid) to authenticated;

commit;

-- ============================================================================
-- 019_saas_pilot_multi_tenant.sql
-- ============================================================================

-- NutriClinic AI v7.0
-- Pilot-ready SaaS foundation: isolated clinic onboarding, invite flows,
-- subscription/plan limits, pilot feedback and platform administration data.

begin;

create extension if not exists "pgcrypto";

alter table public.clinics add column if not exists status text not null default 'active';
alter table public.clinics add column if not exists created_by uuid references public.profiles(id) on delete set null;
alter table public.clinics add column if not exists onboarding_completed_at timestamptz;
alter table public.clinics add column if not exists logo_url text;
alter table public.clinics add column if not exists accent_color text default '#155f43';
alter table public.clinics add column if not exists updated_at timestamptz not null default now();

do $$ begin
  alter table public.clinics add constraint clinics_status_v7_check
    check (status in ('active','pilot','paused','expired','cancelled'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.clinics add constraint clinics_accent_color_v7_check
    check (accent_color is null or accent_color ~ '^#[0-9A-Fa-f]{6}$');
exception when duplicate_object then null; end $$;

create table if not exists public.subscription_plans (
  slug text primary key,
  name text not null,
  description text,
  monthly_price_try numeric(12,2),
  max_dietitians int not null default 1 check (max_dietitians > 0),
  max_staff int not null default 2 check (max_staff > 0),
  max_active_clients int not null default 150 check (max_active_clients > 0),
  monthly_ai_credits int not null default 250 check (monthly_ai_credits >= 0),
  storage_gb int not null default 2 check (storage_gb >= 0),
  features jsonb not null default '{}',
  is_public boolean not null default false,
  is_active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.subscription_plans
  (slug,name,description,monthly_price_try,max_dietitians,max_staff,max_active_clients,monthly_ai_credits,storage_gb,features,is_public,sort_order)
values
  ('founder','Kurucu Klinik','NutriClinic AI kurucu kliniği için süresiz yönetim planı',0,20,50,10000,100000,200,
   '{"appointments":true,"meal_plans":true,"payments":true,"devices":true,"community":true,"ai":true,"reports":true,"white_label":true,"founder":true}'::jsonb,false,-10),
  ('pilot','Pilot Klinik','Davetli pilot klinikler için ücretsiz değerlendirme planı',0,5,10,500,3000,10,
   '{"appointments":true,"meal_plans":true,"payments":true,"devices":true,"community":true,"ai":true,"priority_feedback":true}'::jsonb,false,0),
  ('starter','Başlangıç','Bağımsız diyetisyenler için temel klinik yönetimi',1490,1,2,150,300,3,
   '{"appointments":true,"meal_plans":true,"payments":true,"ai":true}'::jsonb,true,10),
  ('professional','Profesyonel','Büyüyen diyetisyen ekipleri için gelişmiş plan',2990,3,6,500,1200,10,
   '{"appointments":true,"meal_plans":true,"payments":true,"devices":true,"community":true,"ai":true,"reports":true}'::jsonb,true,20),
  ('clinic','Klinik','Çok kullanıcılı klinikler ve şubeler için kapsamlı plan',5990,10,20,2500,5000,50,
   '{"appointments":true,"meal_plans":true,"payments":true,"devices":true,"community":true,"ai":true,"reports":true,"white_label":true}'::jsonb,true,30)
on conflict (slug) do update set
  name=excluded.name,
  description=excluded.description,
  monthly_price_try=excluded.monthly_price_try,
  max_dietitians=excluded.max_dietitians,
  max_staff=excluded.max_staff,
  max_active_clients=excluded.max_active_clients,
  monthly_ai_credits=excluded.monthly_ai_credits,
  storage_gb=excluded.storage_gb,
  features=excluded.features,
  is_public=excluded.is_public,
  is_active=true,
  sort_order=excluded.sort_order,
  updated_at=now();

create table if not exists public.clinic_subscriptions (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null unique references public.clinics(id) on delete cascade,
  plan_slug text not null references public.subscription_plans(slug),
  status text not null default 'pilot',
  pilot_started_at timestamptz,
  pilot_ends_at timestamptz,
  current_period_started_at timestamptz,
  current_period_ends_at timestamptz,
  billing_provider text,
  external_customer_id text,
  external_subscription_id text,
  cancel_at_period_end boolean not null default false,
  limits_override jsonb not null default '{}',
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$ begin
  alter table public.clinic_subscriptions add constraint clinic_subscriptions_status_v7_check
    check (status in ('pilot','trialing','active','past_due','paused','expired','cancelled'));
exception when duplicate_object then null; end $$;

alter table public.clinic_subscriptions add column if not exists last_pilot_reminder_days int;

create table if not exists public.pilot_invites (
  id uuid primary key default gen_random_uuid(),
  token text not null unique,
  label text not null,
  contact_email text,
  plan_slug text not null default 'pilot' references public.subscription_plans(slug),
  pilot_days int not null default 90 check (pilot_days between 7 and 365),
  max_uses int not null default 1 check (max_uses between 1 and 20),
  used_count int not null default 0 check (used_count >= 0),
  expires_at timestamptz not null,
  is_active boolean not null default true,
  created_by_email text,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.clinic_invites (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  token text not null unique,
  email text,
  role public.clinic_role not null default 'client',
  max_uses int not null default 1 check (max_uses between 1 and 1000),
  used_count int not null default 0 check (used_count >= 0),
  expires_at timestamptz not null,
  is_active boolean not null default true,
  invited_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.pilot_feedback (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  category text not null default 'general',
  rating smallint check (rating between 1 and 5),
  message text not null check (char_length(message) between 3 and 5000),
  page_path text,
  status text not null default 'new',
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$ begin
  alter table public.pilot_feedback add constraint pilot_feedback_category_v7_check
    check (category in ('general','bug','idea','usability','support'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.pilot_feedback add constraint pilot_feedback_status_v7_check
    check (status in ('new','reviewing','planned','resolved','closed'));
exception when duplicate_object then null; end $$;

create table if not exists public.monthly_usage_counters (
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  usage_month date not null,
  ai_requests int not null default 0,
  emails_sent int not null default 0,
  sms_sent int not null default 0,
  storage_bytes bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key (clinic_id,usage_month)
);

create index if not exists clinic_invites_clinic_created_v7_idx on public.clinic_invites(clinic_id,created_at desc);
create index if not exists clinic_invites_token_v7_idx on public.clinic_invites(token);
create index if not exists pilot_invites_token_v7_idx on public.pilot_invites(token);
create index if not exists pilot_feedback_clinic_created_v7_idx on public.pilot_feedback(clinic_id,created_at desc);
create index if not exists clinic_subscriptions_status_v7_idx on public.clinic_subscriptions(status,pilot_ends_at);

-- Existing installations receive the non-expiring founder plan so no current workflow is interrupted.
insert into public.clinic_subscriptions(clinic_id,plan_slug,status,metadata)
select c.id,'founder','active',jsonb_build_object('source','v7_existing_clinic_migration','founder_access',true)
from public.clinics c
where not exists(select 1 from public.clinic_subscriptions s where s.clinic_id=c.id);

update public.clinics c
set status='active',updated_at=now()
where exists(select 1 from public.clinic_subscriptions s where s.clinic_id=c.id and s.plan_slug='founder');

-- The legacy seed clinic is removed only in a completely fresh installation.
-- Existing installations keep it because they already have memberships.
delete from public.clinics
where id='00000000-0000-0000-0000-000000000001'
  and not exists(select 1 from public.clinic_memberships where clinic_id='00000000-0000-0000-0000-000000000001');

-- New Auth accounts are now neutral profiles. Clinic membership is created only
-- after a pilot or clinic invitation is redeemed.
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_full_name text;
  v_email text;
  v_phone text;
  v_locale text;
begin
  v_email := coalesce(nullif(new.raw_user_meta_data->>'contact_email',''),new.email);
  v_phone := coalesce(nullif(new.raw_user_meta_data->>'contact_phone',''),new.phone);
  v_full_name := coalesce(nullif(new.raw_user_meta_data->>'full_name',''),split_part(coalesce(v_email,v_phone,'Kullanıcı'),'@',1));
  v_locale := coalesce(nullif(new.raw_user_meta_data->>'preferred_locale',''),'tr');
  if v_locale not in ('tr','en','el','ru','de') then v_locale := 'tr'; end if;

  insert into public.profiles(id,full_name,email,phone,preferred_locale)
  values(new.id,v_full_name,v_email,v_phone,v_locale)
  on conflict(id) do update set
    full_name=excluded.full_name,
    email=coalesce(excluded.email,public.profiles.email),
    phone=coalesce(excluded.phone,public.profiles.phone),
    preferred_locale=excluded.preferred_locale,
    updated_at=now();

  return new;
end;
$$;

create or replace function public.get_saas_context_v7()
returns jsonb
language plpgsql stable security definer set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_result jsonb;
begin
  select m.clinic_id,m.role into v_clinic,v_role
  from public.clinic_memberships m
  where m.user_id=auth.uid() and m.is_active=true
  order by m.created_at limit 1;

  if v_clinic is null then return null; end if;

  select jsonb_build_object(
    'clinic_id',c.id,
    'clinic_name',c.name,
    'clinic_slug',c.slug,
    'clinic_status',c.status,
    'role',v_role,
    'plan_slug',p.slug,
    'plan_name',p.name,
    'subscription_status',s.status,
    'pilot_ends_at',s.pilot_ends_at,
    'days_remaining',case when s.pilot_ends_at is null then null else greatest(0,ceil(extract(epoch from (s.pilot_ends_at-now()))/86400.0)::int) end,
    'limits',jsonb_build_object(
      'dietitians',coalesce((s.limits_override->>'max_dietitians')::int,p.max_dietitians),
      'staff',coalesce((s.limits_override->>'max_staff')::int,p.max_staff),
      'active_clients',coalesce((s.limits_override->>'max_active_clients')::int,p.max_active_clients),
      'ai_credits',coalesce((s.limits_override->>'monthly_ai_credits')::int,p.monthly_ai_credits),
      'storage_gb',coalesce((s.limits_override->>'storage_gb')::int,p.storage_gb)
    ),
    'usage',jsonb_build_object(
      'dietitians',(select count(*) from public.clinic_memberships where clinic_id=v_clinic and is_active and role in ('owner','dietitian')),
      'staff',(select count(*) from public.clinic_memberships where clinic_id=v_clinic and is_active and role in ('owner','dietitian','secretary')),
      'active_clients',(select count(*) from public.client_profiles where clinic_id=v_clinic and is_active),
      'ai_requests',coalesce((select ai_requests from public.monthly_usage_counters where clinic_id=v_clinic and usage_month=date_trunc('month',current_date)::date),0)
    ),
    'features',p.features
  ) into v_result
  from public.clinics c
  join public.clinic_subscriptions s on s.clinic_id=c.id
  join public.subscription_plans p on p.slug=s.plan_slug
  where c.id=v_clinic;

  return v_result;
end;
$$;

-- Every newly-created tenant receives the operational starter data that
-- older clinics obtained when migration 017 originally ran.
create or replace function public.seed_new_clinic_v7(
  p_clinic_id uuid,
  p_creator uuid
)
returns void
language plpgsql security definer set search_path=public
as $$
begin
  if p_clinic_id is null then
    raise exception 'Klinik kimliği zorunludur';
  end if;

  insert into public.service_catalog(
    clinic_id,name,category,description,default_quantity,default_unit_price,created_by
  )
  select p_clinic_id,x.name,x.category,x.description,x.qty,x.price,p_creator
  from (values
    ('İlk Görüşme','consultation','İlk değerlendirme ve planlama',1::numeric,0::numeric),
    ('Kontrol Görüşmesi','consultation','Kontrol ve plan güncelleme',1::numeric,0::numeric),
    ('Haftalık Menü','meal_plan','Bir haftalık kişiye özel menü',1::numeric,0::numeric),
    ('Vücut Analizi','measurement','Ayrıntılı vücut kompozisyon ölçümü',1::numeric,0::numeric),
    ('BodyShape Seansı','bodyshape','BodyShape cihaz kullanımı',1::numeric,0::numeric),
    ('G5 Seansı','g5','G5 uygulama seansı',1::numeric,0::numeric)
  ) as x(name,category,description,qty,price)
  on conflict(clinic_id,name) do nothing;

  insert into public.intake_templates(
    clinic_id,name,description,form_schema,version,created_by
  )
  values(
    p_clinic_id,
    'İlk Görüşme Anamnez Formu',
    'Danışanın sağlık ve yaşam öyküsünü görüşme öncesinde toplar',
    '{"sections":["health_history","medications","operations","digestion","sleep","tobacco_alcohol","activity","nutrition_history","emotional_eating","women_health","notes"]}'::jsonb,
    1,
    p_creator
  )
  on conflict(clinic_id,name,version) do nothing;

  insert into public.consent_templates(
    clinic_id,name,body,version,is_required,created_by
  )
  select p_clinic_id,x.name,x.body,1,x.required,p_creator
  from (values
    ('Aydınlatma ve Veri İşleme Onayı','Kişisel ve klinik verilerimin hizmetin yürütülmesi amacıyla işlenmesine ilişkin aydınlatma metnini okudum ve anladım.',true),
    ('Online Danışmanlık Onayı','Online görüşmenin kapsamı, sınırları ve teknik koşulları hakkında bilgilendirildim.',false),
    ('Fotoğraf ve Belge Yükleme Onayı','Öğün, ilerleme ve klinik belge görsellerinin yalnızca yetkili klinik ekibi tarafından görüntülenmesini kabul ediyorum.',false),
    ('Paket, İptal ve Randevu Koşulları','Paket kullanımı, randevu değişikliği ve iptal koşullarını okudum ve kabul ediyorum.',true)
  ) as x(name,body,required)
  on conflict(clinic_id,name,version) do nothing;
end;
$$;

create or replace function public.redeem_pilot_invite_v7(
  p_token text,
  p_clinic_name text,
  p_slug text,
  p_timezone text default 'Europe/Istanbul',
  p_locale text default 'tr'
)
returns uuid
language plpgsql security definer set search_path=public
as $$
declare
  v_invite public.pilot_invites%rowtype;
  v_profile public.profiles%rowtype;
  v_clinic uuid;
  v_dietitian uuid;
  v_slug text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if exists(select 1 from public.clinic_memberships where user_id=auth.uid() and is_active) then
    raise exception 'Bu hesap zaten aktif bir kliniğe bağlı';
  end if;
  if trim(coalesce(p_clinic_name,''))='' then raise exception 'Klinik adı zorunludur'; end if;

  v_slug:=lower(trim(p_slug));
  if v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
    raise exception 'Klinik bağlantı adı yalnızca küçük harf, sayı ve tire içerebilir';
  end if;
  if exists(select 1 from public.clinics where slug=v_slug) then raise exception 'Bu klinik bağlantı adı kullanımda'; end if;

  select * into v_invite from public.pilot_invites
  where upper(token)=upper(trim(p_token)) for update;
  if v_invite.id is null then raise exception 'Pilot davet kodu bulunamadı'; end if;
  if not v_invite.is_active or v_invite.expires_at<=now() or v_invite.used_count>=v_invite.max_uses then
    raise exception 'Pilot davet kodunun süresi dolmuş veya kullanım hakkı kalmamış';
  end if;

  select * into v_profile from public.profiles where id=auth.uid();
  if v_profile.id is null then raise exception 'Kullanıcı profili bulunamadı'; end if;
  if v_invite.contact_email is not null and lower(coalesce(v_profile.email,''))<>lower(v_invite.contact_email) then
    raise exception 'Bu pilot kodu farklı bir e-posta adresine tanımlanmış';
  end if;

  insert into public.clinics(name,slug,default_locale,timezone,status,created_by,onboarding_completed_at)
  values(trim(p_clinic_name),v_slug,
    case when p_locale in ('tr','en','el','ru','de') then p_locale else 'tr' end,
    coalesce(nullif(trim(p_timezone),''),'Europe/Istanbul'),'pilot',auth.uid(),now())
  returning id into v_clinic;

  insert into public.clinic_memberships(clinic_id,user_id,role,is_active)
  values(v_clinic,auth.uid(),'owner',true);

  insert into public.dietitian_profiles(clinic_id,user_id,title,is_bookable)
  values(v_clinic,auth.uid(),'Danışman Diyetisyen',true)
  returning id into v_dietitian;
  perform public.ensure_default_availability(v_dietitian);
  perform public.seed_new_clinic_v7(v_clinic,auth.uid());

  insert into public.clinic_subscriptions(clinic_id,plan_slug,status,pilot_started_at,pilot_ends_at,metadata)
  values(v_clinic,v_invite.plan_slug,'pilot',now(),now()+make_interval(days=>v_invite.pilot_days),
    jsonb_build_object('pilot_invite_id',v_invite.id,'pilot_label',v_invite.label));

  update public.pilot_invites set used_count=used_count+1,updated_at=now(),
    is_active=case when used_count+1>=max_uses then false else is_active end
  where id=v_invite.id;

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values(v_clinic,auth.uid(),'pilot_clinic_created','clinic',v_clinic::text,
    jsonb_build_object('pilot_invite_id',v_invite.id,'pilot_days',v_invite.pilot_days,'plan_slug',v_invite.plan_slug));

  return v_clinic;
end;
$$;

create or replace function public.create_clinic_invite_v7(
  p_role public.clinic_role,
  p_email text default null,
  p_expires_days int default 14,
  p_max_uses int default 1
)
returns text
language plpgsql security definer set search_path=public
as $$
declare
  v_clinic uuid;
  v_actor_role public.clinic_role;
  v_token text;
begin
  select clinic_id,role into v_clinic,v_actor_role
  from public.clinic_memberships where user_id=auth.uid() and is_active limit 1;
  if v_clinic is null then raise exception 'Klinik üyeliği bulunamadı'; end if;
  if p_role='owner' then raise exception 'Klinik Sahibi rolü davetle verilemez'; end if;
  if v_actor_role='client' then raise exception 'Bu işlem için klinik yetkisi gerekli'; end if;
  if v_actor_role in ('dietitian','secretary') and p_role<>'client' then
    raise exception 'Diyetisyen ve Sekreter yalnızca Danışan daveti oluşturabilir';
  end if;
  if p_expires_days not between 1 and 90 then raise exception 'Geçerlilik süresi 1-90 gün olmalıdır'; end if;
  if p_max_uses not between 1 and 1000 then raise exception 'Kullanım sayısı geçersiz'; end if;

  v_token:=upper(substr(encode(gen_random_bytes(12),'hex'),1,16));
  insert into public.clinic_invites(clinic_id,token,email,role,max_uses,expires_at,invited_by)
  values(v_clinic,v_token,nullif(lower(trim(p_email)),''),p_role,p_max_uses,now()+make_interval(days=>p_expires_days),auth.uid());

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values(v_clinic,auth.uid(),'clinic_invite_created','clinic_invite',v_token,
    jsonb_build_object('role',p_role,'email',nullif(lower(trim(p_email)),''),'max_uses',p_max_uses));
  return v_token;
end;
$$;

create or replace function public.list_clinic_invites_v7()
returns table(
  id uuid, token text, email text, role public.clinic_role, max_uses int,
  used_count int, expires_at timestamptz, is_active boolean, created_at timestamptz
)
language plpgsql stable security definer set search_path=public
as $$
declare v_clinic uuid; v_role public.clinic_role;
begin
  select clinic_id,clinic_memberships.role into v_clinic,v_role
  from public.clinic_memberships where user_id=auth.uid() and is_active limit 1;
  if v_clinic is null or v_role='client' then raise exception 'Klinik personeli erişimi gerekli'; end if;
  return query
    select i.id,i.token,i.email,i.role,i.max_uses,i.used_count,i.expires_at,i.is_active,i.created_at
    from public.clinic_invites i where i.clinic_id=v_clinic order by i.created_at desc;
end;
$$;

create or replace function public.revoke_clinic_invite_v7(p_invite_id uuid)
returns void
language plpgsql security definer set search_path=public
as $$
declare v_clinic uuid; v_role public.clinic_role;
begin
  select clinic_id,role into v_clinic,v_role from public.clinic_memberships
  where user_id=auth.uid() and is_active limit 1;
  if v_clinic is null or v_role not in ('owner','dietitian','secretary') then raise exception 'Klinik personeli erişimi gerekli'; end if;
  update public.clinic_invites set is_active=false,updated_at=now()
  where id=p_invite_id and clinic_id=v_clinic;
end;
$$;

create or replace function public.accept_clinic_invite_v7(p_token text)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_invite public.clinic_invites%rowtype;
  v_profile public.profiles%rowtype;
  v_plan public.subscription_plans%rowtype;
  v_subscription public.clinic_subscriptions%rowtype;
  v_member_no text;
  v_client uuid;
  v_dietitian uuid;
  v_staff_count int;
  v_dietitian_count int;
  v_client_count int;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if exists(select 1 from public.clinic_memberships where user_id=auth.uid() and is_active) then
    raise exception 'Bu hesap zaten aktif bir kliniğe bağlı';
  end if;

  select * into v_invite from public.clinic_invites
  where upper(token)=upper(trim(p_token)) for update;
  if v_invite.id is null then raise exception 'Klinik davet kodu bulunamadı'; end if;
  if not v_invite.is_active or v_invite.expires_at<=now() or v_invite.used_count>=v_invite.max_uses then
    raise exception 'Klinik davet kodunun süresi dolmuş veya kullanım hakkı kalmamış';
  end if;

  select * into v_profile from public.profiles where id=auth.uid();
  if v_profile.id is null then raise exception 'Kullanıcı profili bulunamadı'; end if;
  if v_invite.email is not null and lower(coalesce(v_profile.email,''))<>lower(v_invite.email) then
    raise exception 'Bu davet farklı bir e-posta adresine tanımlanmış';
  end if;

  select * into v_subscription from public.clinic_subscriptions where clinic_id=v_invite.clinic_id;
  select * into v_plan from public.subscription_plans where slug=v_subscription.plan_slug;
  if v_subscription.status in ('paused','expired','cancelled') then raise exception 'Klinik hesabı yeni kullanıcı kabul etmiyor'; end if;

  select count(*) into v_staff_count from public.clinic_memberships
    where clinic_id=v_invite.clinic_id and is_active and role in ('owner','dietitian','secretary');
  select count(*) into v_dietitian_count from public.clinic_memberships
    where clinic_id=v_invite.clinic_id and is_active and role in ('owner','dietitian');
  select count(*) into v_client_count from public.client_profiles
    where clinic_id=v_invite.clinic_id and is_active;

  if v_invite.role in ('dietitian') and v_dietitian_count>=coalesce((v_subscription.limits_override->>'max_dietitians')::int,v_plan.max_dietitians) then
    raise exception 'Diyetisyen limiti dolmuş';
  end if;
  if v_invite.role in ('dietitian','secretary') and v_staff_count>=coalesce((v_subscription.limits_override->>'max_staff')::int,v_plan.max_staff) then
    raise exception 'Personel limiti dolmuş';
  end if;
  if v_invite.role='client' and v_client_count>=coalesce((v_subscription.limits_override->>'max_active_clients')::int,v_plan.max_active_clients) then
    raise exception 'Aktif danışan limiti dolmuş';
  end if;

  insert into public.clinic_memberships(clinic_id,user_id,role,is_active)
  values(v_invite.clinic_id,auth.uid(),v_invite.role,true)
  on conflict(clinic_id,user_id) do update set role=excluded.role,is_active=true,updated_at=now();

  if v_invite.role='client' then
    v_member_no:='NCA-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('public.client_member_sequence')::text,6,'0');
    insert into public.client_profiles(clinic_id,user_id,member_no,full_name,email,phone,is_active)
    values(v_invite.clinic_id,auth.uid(),v_member_no,v_profile.full_name,v_profile.email,v_profile.phone,true)
    on conflict(clinic_id,user_id) do update set
      full_name=excluded.full_name,
      email=coalesce(excluded.email,public.client_profiles.email),
      phone=coalesce(excluded.phone,public.client_profiles.phone),
      is_active=true,
      updated_at=now()
    returning id into v_client;
    insert into public.loyalty_wallets(clinic_id,client_id,balance) values(v_invite.clinic_id,v_client,0)
    on conflict(clinic_id,client_id) do nothing;
  elsif v_invite.role='dietitian' then
    insert into public.dietitian_profiles(clinic_id,user_id,title,is_bookable)
    values(v_invite.clinic_id,auth.uid(),'Diyetisyen',true)
    on conflict(clinic_id,user_id) do update set is_bookable=true
    returning id into v_dietitian;
    perform public.ensure_default_availability(v_dietitian);
  end if;

  update public.clinic_invites set used_count=used_count+1,updated_at=now(),
    is_active=case when used_count+1>=max_uses then false else is_active end
  where id=v_invite.id;

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values(v_invite.clinic_id,auth.uid(),'clinic_invite_accepted','user',auth.uid()::text,
    jsonb_build_object('invite_id',v_invite.id,'role',v_invite.role));

  return jsonb_build_object('clinic_id',v_invite.clinic_id,'role',v_invite.role);
end;
$$;

create or replace function public.submit_pilot_feedback_v7(
  p_category text,
  p_rating int,
  p_message text,
  p_page_path text default null
)
returns uuid
language plpgsql security definer set search_path=public
as $$
declare v_clinic uuid; v_id uuid;
begin
  select clinic_id into v_clinic from public.clinic_memberships
  where user_id=auth.uid() and is_active limit 1;
  if v_clinic is null then raise exception 'Klinik üyeliği bulunamadı'; end if;
  if p_category not in ('general','bug','idea','usability','support') then raise exception 'Geri bildirim kategorisi geçersiz'; end if;
  if p_rating is not null and p_rating not between 1 and 5 then raise exception 'Puan 1-5 arasında olmalıdır'; end if;
  if char_length(trim(coalesce(p_message,'')))<3 then raise exception 'Geri bildirim mesajı çok kısa'; end if;
  insert into public.pilot_feedback(clinic_id,user_id,category,rating,message,page_path)
  values(v_clinic,auth.uid(),p_category,p_rating,trim(p_message),nullif(trim(p_page_path),''))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.consume_ai_credit_v7(p_clinic_id uuid,p_units int default 1)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_plan public.subscription_plans%rowtype;
  v_subscription public.clinic_subscriptions%rowtype;
  v_limit int;
  v_current int;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_units not between 1 and 100 then raise exception 'AI kullanım birimi geçersiz'; end if;
  if public.current_clinic_role(p_clinic_id) is null then raise exception 'Klinik erişimi bulunamadı'; end if;
  select * into v_subscription from public.clinic_subscriptions where clinic_id=p_clinic_id;
  if v_subscription.id is null then raise exception 'Klinik aboneliği bulunamadı'; end if;
  if v_subscription.status not in ('pilot','trialing','active') then raise exception 'AI araçları için aktif klinik planı gerekli'; end if;
  select * into v_plan from public.subscription_plans where slug=v_subscription.plan_slug;
  v_limit:=coalesce((v_subscription.limits_override->>'monthly_ai_credits')::int,v_plan.monthly_ai_credits);

  insert into public.monthly_usage_counters(clinic_id,usage_month,ai_requests)
  values(p_clinic_id,date_trunc('month',current_date)::date,0)
  on conflict(clinic_id,usage_month) do nothing;

  select ai_requests into v_current from public.monthly_usage_counters
  where clinic_id=p_clinic_id and usage_month=date_trunc('month',current_date)::date
  for update;
  if v_current+p_units>v_limit then raise exception 'Aylık AI kullanım limitiniz doldu'; end if;

  update public.monthly_usage_counters set ai_requests=ai_requests+p_units,updated_at=now()
  where clinic_id=p_clinic_id and usage_month=date_trunc('month',current_date)::date
  returning ai_requests into v_current;
  return jsonb_build_object('used',v_current,'limit',v_limit,'remaining',greatest(0,v_limit-v_current));
end;
$$;

-- Plan limit enforcement for role promotion.
create or replace function public.set_member_role(p_user_id uuid,p_role public.clinic_role)
returns void
language plpgsql security definer set search_path=public
as $$
declare
  v_clinic uuid;
  v_current_role public.clinic_role;
  v_dietitian uuid;
  v_plan public.subscription_plans%rowtype;
  v_subscription public.clinic_subscriptions%rowtype;
  v_dietitian_limit int;
  v_staff_limit int;
  v_dietitian_count int;
  v_staff_count int;
  v_profile public.profiles%rowtype;
  v_client uuid;
  v_member_no text;
begin
  select clinic_id into v_clinic from public.clinic_memberships
  where user_id=auth.uid() and role='owner' and is_active=true limit 1;
  if v_clinic is null then raise exception 'Yalnızca Klinik Sahibi rol değiştirebilir'; end if;

  select role into v_current_role from public.clinic_memberships
  where clinic_id=v_clinic and user_id=p_user_id and is_active=true;
  if v_current_role is null then raise exception 'Kullanıcı bu kliniğin üyesi değil'; end if;

  if v_current_role='owner' and p_role<>'owner' and
     (select count(*) from public.clinic_memberships where clinic_id=v_clinic and role='owner' and is_active=true)<=1
  then raise exception 'Son Klinik Sahibi rolü düşürülemez'; end if;

  select * into v_subscription from public.clinic_subscriptions where clinic_id=v_clinic;
  select * into v_plan from public.subscription_plans where slug=v_subscription.plan_slug;
  v_dietitian_limit:=coalesce((v_subscription.limits_override->>'max_dietitians')::int,v_plan.max_dietitians);
  v_staff_limit:=coalesce((v_subscription.limits_override->>'max_staff')::int,v_plan.max_staff);
  select count(*) into v_dietitian_count from public.clinic_memberships where clinic_id=v_clinic and is_active and role in ('owner','dietitian') and user_id<>p_user_id;
  select count(*) into v_staff_count from public.clinic_memberships where clinic_id=v_clinic and is_active and role in ('owner','dietitian','secretary') and user_id<>p_user_id;
  if p_role in ('owner','dietitian') and v_dietitian_count>=v_dietitian_limit then raise exception 'Paketinizdeki Diyetisyen limiti dolmuş'; end if;
  if p_role in ('owner','dietitian','secretary') and v_staff_count>=v_staff_limit then raise exception 'Paketinizdeki personel limiti dolmuş'; end if;

  update public.clinic_memberships set role=p_role,updated_at=now()
  where clinic_id=v_clinic and user_id=p_user_id;

  if p_role in ('owner','dietitian') then
    insert into public.dietitian_profiles(clinic_id,user_id,title,is_bookable)
    values(v_clinic,p_user_id,'Danışman Diyetisyen',true)
    on conflict(clinic_id,user_id) do update set is_bookable=true
    returning id into v_dietitian;
    perform public.ensure_default_availability(v_dietitian);
  else
    update public.dietitian_profiles set is_bookable=false where clinic_id=v_clinic and user_id=p_user_id;
  end if;

  if p_role='client' then
    select * into v_profile from public.profiles where id=p_user_id;
    v_member_no:='NCA-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('public.client_member_sequence')::text,6,'0');
    insert into public.client_profiles(clinic_id,user_id,member_no,full_name,email,phone,is_active)
    values(v_clinic,p_user_id,v_member_no,v_profile.full_name,v_profile.email,v_profile.phone,true)
    on conflict(clinic_id,user_id) do update set is_active=true,updated_at=now()
    returning id into v_client;
    insert into public.loyalty_wallets(clinic_id,client_id,balance) values(v_clinic,v_client,0)
    on conflict(clinic_id,client_id) do nothing;
  else
    update public.client_profiles set is_active=false,updated_at=now()
    where clinic_id=v_clinic and user_id=p_user_id;
  end if;

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values(v_clinic,auth.uid(),'member_role_changed','user',p_user_id::text,
    jsonb_build_object('old_role',v_current_role,'new_role',p_role,'plan_slug',v_subscription.plan_slug));
end;
$$;

alter table public.subscription_plans enable row level security;
alter table public.clinic_subscriptions enable row level security;
alter table public.pilot_invites enable row level security;
alter table public.clinic_invites enable row level security;
alter table public.pilot_feedback enable row level security;
alter table public.monthly_usage_counters enable row level security;

drop policy if exists subscription_plans_read_v7 on public.subscription_plans;
create policy subscription_plans_read_v7 on public.subscription_plans for select to authenticated using (is_active=true);

drop policy if exists clinic_subscriptions_member_read_v7 on public.clinic_subscriptions;
create policy clinic_subscriptions_member_read_v7 on public.clinic_subscriptions for select to authenticated
using (public.current_clinic_role(clinic_id) is not null);

drop policy if exists clinic_invites_staff_read_v7 on public.clinic_invites;
create policy clinic_invites_staff_read_v7 on public.clinic_invites for select to authenticated
using (public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary'));

drop policy if exists pilot_feedback_own_read_v7 on public.pilot_feedback;
create policy pilot_feedback_own_read_v7 on public.pilot_feedback for select to authenticated
using (user_id=auth.uid() or public.current_clinic_role(clinic_id)='owner');

drop policy if exists usage_counters_member_read_v7 on public.monthly_usage_counters;
create policy usage_counters_member_read_v7 on public.monthly_usage_counters for select to authenticated
using (public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary'));

-- Pilot invites are intentionally unavailable through the public PostgREST API.
-- They are managed by the authenticated platform-admin server route with service role.

revoke all on function public.get_saas_context_v7() from public;
revoke all on function public.seed_new_clinic_v7(uuid,uuid) from public;
revoke all on function public.redeem_pilot_invite_v7(text,text,text,text,text) from public;
revoke all on function public.create_clinic_invite_v7(public.clinic_role,text,int,int) from public;
revoke all on function public.list_clinic_invites_v7() from public;
revoke all on function public.revoke_clinic_invite_v7(uuid) from public;
revoke all on function public.accept_clinic_invite_v7(text) from public;
revoke all on function public.submit_pilot_feedback_v7(text,int,text,text) from public;
revoke all on function public.consume_ai_credit_v7(uuid,int) from public;

grant execute on function public.get_saas_context_v7() to authenticated;
grant execute on function public.redeem_pilot_invite_v7(text,text,text,text,text) to authenticated;
grant execute on function public.create_clinic_invite_v7(public.clinic_role,text,int,int) to authenticated;
grant execute on function public.list_clinic_invites_v7() to authenticated;
grant execute on function public.revoke_clinic_invite_v7(uuid) to authenticated;
grant execute on function public.accept_clinic_invite_v7(text) to authenticated;
grant execute on function public.submit_pilot_feedback_v7(text,int,text,text) to authenticated;
grant execute on function public.consume_ai_credit_v7(uuid,int) to authenticated;

grant select on public.subscription_plans,public.clinic_subscriptions,public.clinic_invites,public.pilot_feedback,public.monthly_usage_counters to authenticated;

commit;



-- v7.3 public registration and pilot application extension
begin;
create table if not exists public.pilot_applications (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text not null,
  phone text,
  applicant_type text not null default 'clinic_owner'
    check (applicant_type in ('clinic_owner','dietitian','clinic_team','other')),
  clinic_name text,
  city text,
  team_size integer not null default 1 check (team_size between 1 and 1000),
  active_client_count integer not null default 0 check (active_client_count between 0 and 1000000),
  uses_devices boolean not null default false,
  message text,
  status text not null default 'new'
    check (status in ('new','contacted','approved','waitlist','rejected','closed')),
  admin_note text,
  reviewed_by_email text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists pilot_applications_status_created_idx
  on public.pilot_applications(status, created_at desc);
create index if not exists pilot_applications_email_idx
  on public.pilot_applications(lower(email));

alter table public.pilot_applications enable row level security;

-- Başvurular yalnızca sunucu tarafındaki service-role API ile yazılır ve okunur.
-- Anon/authenticated kullanıcılara doğrudan tablo yetkisi verilmez.
revoke all on table public.pilot_applications from anon, authenticated;
commit;


-- Included migration 021
-- NutriClinic AI v7.5
-- Platform Admin clinic detail, commercial approval and pilot-to-paid conversion flow.
-- Run once after 020_public_registration_and_pilot_applications.sql.

begin;

alter table public.clinic_subscriptions
  add column if not exists commercial_approved_at timestamptz,
  add column if not exists commercial_approved_by_email text,
  add column if not exists commercial_approval_note text,
  add column if not exists agreed_price_try numeric(12,2),
  add column if not exists billing_cycle text,
  add column if not exists converted_from_pilot_at timestamptz;

do $$ begin
  alter table public.clinic_subscriptions add constraint clinic_subscriptions_billing_cycle_v75_check
    check (billing_cycle is null or billing_cycle in ('monthly','annual','manual'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.clinic_subscriptions add constraint clinic_subscriptions_agreed_price_v75_check
    check (agreed_price_try is null or agreed_price_try >= 0);
exception when duplicate_object then null; end $$;

create table if not exists public.clinic_conversion_requests (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  requested_by uuid not null references public.profiles(id) on delete cascade,
  requested_plan_slug text not null references public.subscription_plans(slug),
  note text,
  status text not null default 'pending',
  reviewed_by_email text,
  reviewed_at timestamptz,
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$ begin
  alter table public.clinic_conversion_requests add constraint clinic_conversion_requests_status_v75_check
    check (status in ('pending','approved','rejected','cancelled'));
exception when duplicate_object then null; end $$;

create unique index if not exists clinic_conversion_requests_one_pending_v75_idx
  on public.clinic_conversion_requests(clinic_id)
  where status='pending';
create index if not exists clinic_conversion_requests_status_created_v75_idx
  on public.clinic_conversion_requests(status,created_at desc);

create table if not exists public.platform_clinic_notes (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  note text not null check (char_length(trim(note)) between 2 and 5000),
  created_by_email text not null,
  created_at timestamptz not null default now()
);
create index if not exists platform_clinic_notes_clinic_created_v75_idx
  on public.platform_clinic_notes(clinic_id,created_at desc);

alter table public.clinic_conversion_requests enable row level security;
alter table public.platform_clinic_notes enable row level security;

revoke all on table public.clinic_conversion_requests from anon, authenticated;
revoke all on table public.platform_clinic_notes from anon, authenticated;

create or replace function public.request_paid_conversion_v75(
  p_plan_slug text,
  p_note text default null
)
returns uuid
language plpgsql security definer set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_request_id uuid;
begin
  select clinic_id,role into v_clinic,v_role
  from public.clinic_memberships
  where user_id=auth.uid() and is_active=true
  order by created_at
  limit 1;

  if v_clinic is null or v_role<>'owner' then
    raise exception 'Ücretli devam talebini yalnızca Klinik Sahibi gönderebilir';
  end if;

  if not exists(
    select 1 from public.subscription_plans
    where slug=p_plan_slug and is_active=true and is_public=true
  ) then
    raise exception 'Seçilen ücretli plan geçersiz';
  end if;

  insert into public.clinic_conversion_requests(
    clinic_id,requested_by,requested_plan_slug,note,status
  )
  values(
    v_clinic,auth.uid(),p_plan_slug,nullif(trim(coalesce(p_note,'')),''),'pending'
  )
  on conflict (clinic_id) where status='pending'
  do update set
    requested_by=excluded.requested_by,
    requested_plan_slug=excluded.requested_plan_slug,
    note=excluded.note,
    updated_at=now()
  returning id into v_request_id;

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values(
    v_clinic,auth.uid(),'paid_conversion_requested','clinic',v_clinic::text,
    jsonb_build_object('request_id',v_request_id,'plan_slug',p_plan_slug,'note',nullif(trim(coalesce(p_note,'')),''))
  );

  return v_request_id;
end;
$$;

create or replace function public.get_saas_context_v7()
returns jsonb
language plpgsql stable security definer set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_result jsonb;
begin
  select m.clinic_id,m.role into v_clinic,v_role
  from public.clinic_memberships m
  where m.user_id=auth.uid() and m.is_active=true
  order by m.created_at limit 1;

  if v_clinic is null then return null; end if;

  select jsonb_build_object(
    'clinic_id',c.id,
    'clinic_name',c.name,
    'clinic_slug',c.slug,
    'clinic_status',c.status,
    'role',v_role,
    'plan_slug',p.slug,
    'plan_name',p.name,
    'subscription_status',s.status,
    'pilot_ends_at',s.pilot_ends_at,
    'days_remaining',case when s.pilot_ends_at is null then null else greatest(0,ceil(extract(epoch from (s.pilot_ends_at-now()))/86400.0)::int) end,
    'conversion_request',(
      select jsonb_build_object(
        'id',r.id,
        'requested_plan_slug',r.requested_plan_slug,
        'requested_plan_name',rp.name,
        'status',r.status,
        'note',r.note,
        'created_at',r.created_at,
        'reviewed_at',r.reviewed_at,
        'admin_note',r.admin_note
      )
      from public.clinic_conversion_requests r
      join public.subscription_plans rp on rp.slug=r.requested_plan_slug
      where r.clinic_id=v_clinic
      order by r.created_at desc
      limit 1
    ),
    'limits',jsonb_build_object(
      'dietitians',coalesce((s.limits_override->>'max_dietitians')::int,p.max_dietitians),
      'staff',coalesce((s.limits_override->>'max_staff')::int,p.max_staff),
      'active_clients',coalesce((s.limits_override->>'max_active_clients')::int,p.max_active_clients),
      'ai_credits',coalesce((s.limits_override->>'monthly_ai_credits')::int,p.monthly_ai_credits),
      'storage_gb',coalesce((s.limits_override->>'storage_gb')::int,p.storage_gb)
    ),
    'usage',jsonb_build_object(
      'dietitians',(select count(*) from public.clinic_memberships where clinic_id=v_clinic and is_active and role in ('owner','dietitian')),
      'staff',(select count(*) from public.clinic_memberships where clinic_id=v_clinic and is_active and role in ('owner','dietitian','secretary')),
      'active_clients',(select count(*) from public.client_profiles where clinic_id=v_clinic and is_active),
      'ai_requests',coalesce((select ai_requests from public.monthly_usage_counters where clinic_id=v_clinic and usage_month=date_trunc('month',current_date)::date),0)
    ),
    'features',p.features
  ) into v_result
  from public.clinics c
  join public.clinic_subscriptions s on s.clinic_id=c.id
  join public.subscription_plans p on p.slug=s.plan_slug
  where c.id=v_clinic;

  return v_result;
end;
$$;

revoke all on function public.request_paid_conversion_v75(text,text) from public;
grant execute on function public.request_paid_conversion_v75(text,text) to authenticated;

commit;


-- Included migration 022
-- NutriClinic AI v8.0
-- Stabilizes SaaS lifecycle state, clears stale pilot dates and extends SaaS context.
-- Run once after 021_platform_clinic_details_and_paid_conversion.sql.

begin;

-- Non-pilot subscriptions must never keep a pilot countdown.
update public.clinic_subscriptions
set pilot_ends_at = null,
    last_pilot_reminder_days = null,
    updated_at = now()
where plan_slug <> 'pilot'
  and (pilot_ends_at is not null or last_pilot_reminder_days is not null);

-- Founder access is always active and never expires as a pilot.
update public.clinic_subscriptions
set status = 'active',
    pilot_started_at = null,
    pilot_ends_at = null,
    last_pilot_reminder_days = null,
    updated_at = now()
where plan_slug = 'founder';

create or replace function public.normalize_subscription_lifecycle_v8()
returns trigger
language plpgsql
set search_path=public
as $$
begin
  if new.plan_slug = 'founder' then
    new.status := 'active';
    new.pilot_started_at := null;
    new.pilot_ends_at := null;
    new.last_pilot_reminder_days := null;
  elsif new.plan_slug <> 'pilot' or new.status not in ('pilot','trialing') then
    new.pilot_started_at := case when new.plan_slug = 'pilot' then new.pilot_started_at else null end;
    new.pilot_ends_at := null;
    new.last_pilot_reminder_days := null;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists clinic_subscriptions_lifecycle_v8 on public.clinic_subscriptions;
create trigger clinic_subscriptions_lifecycle_v8
before insert or update of plan_slug,status,pilot_started_at,pilot_ends_at,last_pilot_reminder_days
on public.clinic_subscriptions
for each row execute function public.normalize_subscription_lifecycle_v8();

create or replace function public.get_saas_context_v7()
returns jsonb
language plpgsql stable security definer set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_result jsonb;
begin
  select m.clinic_id,m.role into v_clinic,v_role
  from public.clinic_memberships m
  where m.user_id=auth.uid() and m.is_active=true
  order by m.created_at
  limit 1;

  if v_clinic is null then return null; end if;

  select jsonb_build_object(
    'clinic_id',c.id,
    'clinic_name',c.name,
    'clinic_slug',c.slug,
    'clinic_status',c.status,
    'role',v_role,
    'plan_slug',p.slug,
    'plan_name',p.name,
    'subscription_status',s.status,
    'pilot_started_at',case when s.plan_slug='pilot' then s.pilot_started_at else null end,
    'pilot_ends_at',case when s.plan_slug='pilot' and s.status in ('pilot','trialing') then s.pilot_ends_at else null end,
    'days_remaining',case
      when s.plan_slug='pilot' and s.status in ('pilot','trialing') and s.pilot_ends_at is not null
        then greatest(0,ceil(extract(epoch from (s.pilot_ends_at-now()))/86400.0)::int)
      else null
    end,
    'current_period_started_at',s.current_period_started_at,
    'current_period_ends_at',s.current_period_ends_at,
    'billing_cycle',s.billing_cycle,
    'commercial_approved_at',s.commercial_approved_at,
    'commercial_approved_by_email',s.commercial_approved_by_email,
    'agreed_price_try',s.agreed_price_try,
    'conversion_request',(
      select jsonb_build_object(
        'id',r.id,
        'requested_plan_slug',r.requested_plan_slug,
        'requested_plan_name',rp.name,
        'status',r.status,
        'note',r.note,
        'created_at',r.created_at,
        'reviewed_at',r.reviewed_at,
        'admin_note',r.admin_note
      )
      from public.clinic_conversion_requests r
      join public.subscription_plans rp on rp.slug=r.requested_plan_slug
      where r.clinic_id=v_clinic
      order by r.created_at desc
      limit 1
    ),
    'limits',jsonb_build_object(
      'dietitians',coalesce((s.limits_override->>'max_dietitians')::int,p.max_dietitians),
      'staff',coalesce((s.limits_override->>'max_staff')::int,p.max_staff),
      'active_clients',coalesce((s.limits_override->>'max_active_clients')::int,p.max_active_clients),
      'ai_credits',coalesce((s.limits_override->>'monthly_ai_credits')::int,p.monthly_ai_credits),
      'storage_gb',coalesce((s.limits_override->>'storage_gb')::int,p.storage_gb)
    ),
    'usage',jsonb_build_object(
      'dietitians',(select count(*) from public.clinic_memberships where clinic_id=v_clinic and is_active and role in ('owner','dietitian')),
      'staff',(select count(*) from public.clinic_memberships where clinic_id=v_clinic and is_active and role in ('owner','dietitian','secretary')),
      'active_clients',(select count(*) from public.client_profiles where clinic_id=v_clinic and is_active),
      'ai_requests',coalesce((select ai_requests from public.monthly_usage_counters where clinic_id=v_clinic and usage_month=date_trunc('month',current_date)::date),0)
    ),
    'features',p.features
  ) into v_result
  from public.clinics c
  join public.clinic_subscriptions s on s.clinic_id=c.id
  join public.subscription_plans p on p.slug=s.plan_slug
  where c.id=v_clinic;

  return v_result;
end;
$$;

revoke all on function public.get_saas_context_v7() from public;
grant execute on function public.get_saas_context_v7() to authenticated;

comment on function public.normalize_subscription_lifecycle_v8() is
'Prevents stale pilot countdown fields from leaking into founder or paid subscriptions.';

commit;
