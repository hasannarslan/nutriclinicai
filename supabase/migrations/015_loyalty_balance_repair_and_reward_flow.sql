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
