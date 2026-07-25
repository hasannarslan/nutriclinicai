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
