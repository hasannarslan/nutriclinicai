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
