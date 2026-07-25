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
