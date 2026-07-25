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
