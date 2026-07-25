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
