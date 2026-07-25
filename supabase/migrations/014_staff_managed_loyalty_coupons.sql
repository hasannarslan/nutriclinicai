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
