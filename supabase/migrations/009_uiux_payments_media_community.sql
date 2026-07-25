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
