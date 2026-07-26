-- NutriClinic AI v8.1
-- Platform Admin transactional actions, clinic/subscription state synchronization,
-- and locale integrity repair. Run once after 022_stabilization_and_lifecycle_fix.sql.

begin;

-- Keep supported locale values canonical. Existing constraints already reject new invalid values;
-- these statements repair legacy imports that may predate the constraints.
update public.profiles
set preferred_locale = 'tr', updated_at = now()
where preferred_locale is null or preferred_locale not in ('tr','en','el','ru','de');

update public.clinics
set default_locale = 'tr', updated_at = now()
where default_locale is null or default_locale not in ('tr','en','el','ru','de');

create or replace function public.clinic_status_from_subscription_v81(
  p_plan_slug text,
  p_subscription_status text
)
returns text
language sql
immutable
set search_path=public
as $$
  select case
    when p_plan_slug = 'pilot' and p_subscription_status in ('pilot','trialing') then 'pilot'
    when p_subscription_status in ('paused','expired','cancelled') then p_subscription_status
    when p_subscription_status in ('active','trialing','past_due') then 'active'
    else 'active'
  end;
$$;

-- Repair current drift before installing the synchronization trigger.
update public.clinics c
set status = public.clinic_status_from_subscription_v81(s.plan_slug, s.status),
    updated_at = now()
from public.clinic_subscriptions s
where s.clinic_id = c.id
  and c.status is distinct from public.clinic_status_from_subscription_v81(s.plan_slug, s.status);

create or replace function public.sync_clinic_status_from_subscription_v81()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_status text;
begin
  v_status := public.clinic_status_from_subscription_v81(new.plan_slug, new.status);
  update public.clinics
  set status = v_status,
      updated_at = now()
  where id = new.clinic_id
    and status is distinct from v_status;
  return new;
end;
$$;

drop trigger if exists clinic_subscription_status_sync_v81 on public.clinic_subscriptions;
create trigger clinic_subscription_status_sync_v81
after insert or update of plan_slug,status
on public.clinic_subscriptions
for each row execute function public.sync_clinic_status_from_subscription_v81();

create or replace function public.platform_extend_pilot_v81(
  p_clinic_id uuid,
  p_days integer,
  p_admin_email text,
  p_actor_user_id uuid default null
)
returns timestamptz
language plpgsql
security definer
set search_path=public
as $$
declare
  v_subscription public.clinic_subscriptions%rowtype;
  v_base timestamptz;
  v_end timestamptz;
begin
  if p_days is null or p_days < 1 or p_days > 365 then
    raise exception 'Pilot uzatma günü 1 ile 365 arasında olmalıdır';
  end if;

  select * into v_subscription
  from public.clinic_subscriptions
  where clinic_id = p_clinic_id
  for update;

  if not found then raise exception 'Klinik aboneliği bulunamadı'; end if;
  if v_subscription.plan_slug <> 'pilot' then
    raise exception 'Yalnızca pilot planındaki kliniklerin süresi uzatılabilir';
  end if;

  v_base := greatest(coalesce(v_subscription.pilot_ends_at, now()), now());
  v_end := v_base + make_interval(days => p_days);

  update public.clinic_subscriptions
  set status = 'pilot',
      pilot_started_at = coalesce(pilot_started_at, now()),
      pilot_ends_at = v_end,
      last_pilot_reminder_days = null,
      updated_at = now()
  where clinic_id = p_clinic_id;

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values (
    p_clinic_id,p_actor_user_id,'pilot_extended_by_platform','clinic',p_clinic_id::text,
    jsonb_build_object('days',p_days,'pilot_ends_at',v_end,'by_email',nullif(trim(coalesce(p_admin_email,'')),''))
  );

  return v_end;
end;
$$;

create or replace function public.platform_approve_paid_access_v81(
  p_clinic_id uuid,
  p_request_id uuid,
  p_plan_slug text,
  p_billing_cycle text,
  p_agreed_price_try numeric,
  p_approval_note text,
  p_admin_email text,
  p_actor_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_plan public.subscription_plans%rowtype;
  v_now timestamptz := now();
  v_period_end timestamptz;
  v_price numeric(12,2);
  v_count integer;
begin
  if p_billing_cycle not in ('monthly','annual','manual') then
    raise exception 'Faturalama dönemi geçersiz';
  end if;

  select * into v_plan
  from public.subscription_plans
  where slug = p_plan_slug and is_active = true;

  if not found or p_plan_slug in ('pilot','founder') then
    raise exception 'Ücretli plan bulunamadı veya pasif';
  end if;

  if p_agreed_price_try is not null and p_agreed_price_try < 0 then
    raise exception 'Anlaşılan fiyat geçersiz';
  end if;

  v_price := coalesce(
    p_agreed_price_try,
    case when p_billing_cycle = 'annual' then coalesce(v_plan.monthly_price_try,0) * 12 else coalesce(v_plan.monthly_price_try,0) end
  );
  v_period_end := case
    when p_billing_cycle = 'annual' then v_now + interval '1 year'
    when p_billing_cycle = 'monthly' then v_now + interval '1 month'
    else null
  end;

  update public.clinic_subscriptions
  set plan_slug = p_plan_slug,
      status = 'active',
      current_period_started_at = v_now,
      current_period_ends_at = v_period_end,
      billing_cycle = p_billing_cycle,
      agreed_price_try = v_price,
      commercial_approved_at = v_now,
      commercial_approved_by_email = nullif(trim(coalesce(p_admin_email,'')),''),
      commercial_approval_note = nullif(trim(coalesce(p_approval_note,'')),''),
      converted_from_pilot_at = coalesce(converted_from_pilot_at,v_now),
      pilot_started_at = null,
      pilot_ends_at = null,
      last_pilot_reminder_days = null,
      cancel_at_period_end = false,
      updated_at = v_now
  where clinic_id = p_clinic_id;
  get diagnostics v_count = row_count;
  if v_count = 0 then raise exception 'Klinik aboneliği bulunamadı'; end if;

  if p_request_id is not null then
    update public.clinic_conversion_requests
    set status = 'approved',
        reviewed_by_email = nullif(trim(coalesce(p_admin_email,'')),''),
        reviewed_at = v_now,
        admin_note = nullif(trim(coalesce(p_approval_note,'')),''),
        updated_at = v_now
    where id = p_request_id and clinic_id = p_clinic_id and status = 'pending';
    get diagnostics v_count = row_count;
    if v_count = 0 then raise exception 'Bekleyen geçiş talebi bulunamadı'; end if;
  else
    update public.clinic_conversion_requests
    set status = 'approved',
        reviewed_by_email = nullif(trim(coalesce(p_admin_email,'')),''),
        reviewed_at = v_now,
        admin_note = nullif(trim(coalesce(p_approval_note,'')),''),
        updated_at = v_now
    where clinic_id = p_clinic_id and status = 'pending';
  end if;

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values (
    p_clinic_id,p_actor_user_id,'clinic_paid_access_approved','clinic',p_clinic_id::text,
    jsonb_build_object(
      'plan_slug',p_plan_slug,'billing_cycle',p_billing_cycle,'agreed_price_try',v_price,
      'request_id',p_request_id,'approved_by_email',nullif(trim(coalesce(p_admin_email,'')),''),
      'note',nullif(trim(coalesce(p_approval_note,'')),'')
    )
  );

  return jsonb_build_object(
    'ok',true,
    'plan_slug',p_plan_slug,
    'billing_cycle',p_billing_cycle,
    'agreed_price_try',v_price,
    'current_period_ends_at',v_period_end
  );
end;
$$;

create or replace function public.platform_set_clinic_status_v81(
  p_clinic_id uuid,
  p_status text,
  p_admin_email text,
  p_actor_user_id uuid default null
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_plan_slug text;
  v_count integer;
begin
  if p_status not in ('active','paused','expired','cancelled') then
    raise exception 'Durum geçersiz';
  end if;

  select plan_slug into v_plan_slug
  from public.clinic_subscriptions
  where clinic_id = p_clinic_id
  for update;
  if not found then raise exception 'Klinik aboneliği bulunamadı'; end if;
  if p_status = 'active' and v_plan_slug = 'pilot' then
    raise exception 'Pilot klinik doğrudan Aktif yapılamaz. Pilot süresini uzatın veya ücretli planı onaylayın';
  end if;

  update public.clinic_subscriptions
  set status = p_status,
      pilot_started_at = case when p_status='active' then null else pilot_started_at end,
      pilot_ends_at = case when p_status='active' then null else pilot_ends_at end,
      last_pilot_reminder_days = case when p_status='active' then null else last_pilot_reminder_days end,
      updated_at = now()
  where clinic_id = p_clinic_id;
  get diagnostics v_count = row_count;
  if v_count = 0 then raise exception 'Klinik aboneliği güncellenemedi'; end if;

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values (
    p_clinic_id,p_actor_user_id,'clinic_status_changed_by_platform','clinic',p_clinic_id::text,
    jsonb_build_object('status',p_status,'by_email',nullif(trim(coalesce(p_admin_email,'')),''))
  );
end;
$$;

create or replace function public.platform_change_plan_v81(
  p_clinic_id uuid,
  p_plan_slug text,
  p_admin_email text,
  p_actor_user_id uuid default null
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_plan public.subscription_plans%rowtype;
  v_count integer;
begin
  if p_plan_slug = 'pilot' then
    raise exception 'Bir klinik genel plan değişikliğiyle pilot plana alınamaz';
  end if;

  select * into v_plan
  from public.subscription_plans
  where slug = p_plan_slug and is_active = true;
  if not found then raise exception 'Plan bulunamadı veya pasif'; end if;

  update public.clinic_subscriptions
  set plan_slug = p_plan_slug,
      status = 'active',
      pilot_started_at = null,
      pilot_ends_at = null,
      last_pilot_reminder_days = null,
      agreed_price_try = case when p_plan_slug='founder' then 0 else agreed_price_try end,
      billing_cycle = case when p_plan_slug='founder' then 'manual' else billing_cycle end,
      current_period_ends_at = case when p_plan_slug='founder' then null else current_period_ends_at end,
      updated_at = now()
  where clinic_id = p_clinic_id;
  get diagnostics v_count = row_count;
  if v_count = 0 then raise exception 'Klinik aboneliği bulunamadı'; end if;

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values (
    p_clinic_id,p_actor_user_id,'clinic_plan_changed_by_platform','clinic',p_clinic_id::text,
    jsonb_build_object('plan_slug',p_plan_slug,'by_email',nullif(trim(coalesce(p_admin_email,'')),''))
  );
end;
$$;

revoke all on function public.clinic_status_from_subscription_v81(text,text) from public, anon, authenticated;
revoke all on function public.sync_clinic_status_from_subscription_v81() from public, anon, authenticated;
revoke all on function public.platform_extend_pilot_v81(uuid,integer,text,uuid) from public, anon, authenticated;
revoke all on function public.platform_approve_paid_access_v81(uuid,uuid,text,text,numeric,text,text,uuid) from public, anon, authenticated;
revoke all on function public.platform_set_clinic_status_v81(uuid,text,text,uuid) from public, anon, authenticated;
revoke all on function public.platform_change_plan_v81(uuid,text,text,uuid) from public, anon, authenticated;

grant execute on function public.platform_extend_pilot_v81(uuid,integer,text,uuid) to service_role;
grant execute on function public.platform_approve_paid_access_v81(uuid,uuid,text,text,numeric,text,text,uuid) to service_role;
grant execute on function public.platform_set_clinic_status_v81(uuid,text,text,uuid) to service_role;
grant execute on function public.platform_change_plan_v81(uuid,text,text,uuid) to service_role;

comment on function public.sync_clinic_status_from_subscription_v81() is
'Keeps clinics.status synchronized with clinic_subscriptions and prevents conflicting Platform Admin banners.';

commit;
