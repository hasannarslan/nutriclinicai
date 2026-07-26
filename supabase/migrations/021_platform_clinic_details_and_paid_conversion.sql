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
