-- NutriClinic AI v5.6
-- Client self-service loyalty redemption and empty-catalog experience.
-- Run once after migrations 001-015.

begin;

-- The previous staff-issued workflow is no longer exposed as the operative flow.
-- Keep the function for historical compatibility, but prevent direct calls.
revoke execute on function public.issue_reward_coupon_v54(uuid,uuid,text) from authenticated;

create or replace function public.client_redeem_reward_v56(
  p_reward_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_client public.client_profiles%rowtype;
  v_reward public.rewards%rowtype;
  v_wallet_id uuid;
  v_balance integer;
  v_new_balance integer;
  v_transaction_id uuid;
  v_redemption_id uuid;
  v_code text;
  v_dietitian_user_id uuid;
  v_recipient uuid;
begin
  if auth.uid() is null then
    raise exception 'Oturum açmanız gerekir';
  end if;

  select membership.clinic_id,membership.role
    into v_clinic,v_role
  from public.clinic_memberships membership
  where membership.user_id=auth.uid()
    and membership.is_active=true
  limit 1;

  if v_clinic is null or v_role<>'client' then
    raise exception 'Bu işlem yalnızca danışan hesabından yapılabilir';
  end if;

  select client_profile.*
    into v_client
  from public.client_profiles client_profile
  where client_profile.clinic_id=v_clinic
    and client_profile.user_id=auth.uid()
    and client_profile.is_active=true
  limit 1;

  if v_client.id is null then
    raise exception 'Aktif danışan profili bulunamadı';
  end if;

  select reward.*
    into v_reward
  from public.rewards reward
  where reward.id=p_reward_id
    and reward.clinic_id=v_clinic
    and reward.is_active=true
  for update;

  if v_reward.id is null then
    raise exception 'Ödül şu anda kullanıma açık değil';
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
    raise exception 'Puanınız yetersiz. Gerekli: %, Mevcut: %',v_reward.points_cost,coalesce(v_balance,0);
  end if;

  v_new_balance:=v_balance-v_reward.points_cost;

  update public.loyalty_wallets wallet
  set balance=v_new_balance,
      updated_at=now()
  where wallet.id=v_wallet_id;

  if v_reward.stock is not null then
    update public.rewards reward
    set stock=v_reward.stock-1
    where reward.id=v_reward.id;

    insert into public.reward_stock_movements(
      clinic_id,reward_id,quantity_change,stock_after,reason,created_by
    ) values(
      v_clinic,v_reward.id,-1,v_reward.stock-1,
      'Danışan puanıyla ödül aldı',auth.uid()
    );
  end if;

  insert into public.loyalty_transactions as loyalty_transaction(
    wallet_id,transaction_type,points,reason,reward_id,created_by,balance_after
  ) values(
    v_wallet_id,'redeemed',-v_reward.points_cost,
    'Danışan puanıyla ödül aldı: '||v_reward.name,
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
    points_spent,status,requested_at,note,redemption_code,code_expires_at,updated_at
  ) values(
    v_clinic,v_client.id,v_reward.id,v_transaction_id,v_reward.name,
    v_reward.points_cost,'requested',now(),'Danışan puanıyla oluşturuldu',
    v_code,now()+interval '90 days',now()
  ) returning reward_redemption.id into v_redemption_id;

  -- Notify the client.
  insert into public.notifications(
    clinic_id,recipient_user_id,title,body,category,action_view,metadata,dedupe_key
  ) values(
    v_clinic,auth.uid(),'Sadakat ödülünüz hazır',
    v_reward.name||' ödülünü '||v_reward.points_cost::text||' puan kullanarak aldınız.',
    'loyalty_reward_redeemed','loyalty',
    jsonb_build_object(
      'redemption_id',v_redemption_id,
      'reward_id',v_reward.id,
      'reward_name',v_reward.name,
      'redemption_code',v_code,
      'points_spent',v_reward.points_cost,
      'balance_after',v_new_balance
    ),
    'client-reward-redeemed-'||v_redemption_id::text
  );

  -- Notify clinic owners and the client's assigned dietitian.
  select dietitian_profile.user_id
    into v_dietitian_user_id
  from public.dietitian_profiles dietitian_profile
  where dietitian_profile.id=v_client.assigned_dietitian_id
    and dietitian_profile.clinic_id=v_clinic
  limit 1;

  for v_recipient in
    select distinct recipient.user_id
    from (
      select membership.user_id
      from public.clinic_memberships membership
      where membership.clinic_id=v_clinic
        and membership.is_active=true
        and membership.role='owner'
      union all
      select v_dietitian_user_id
      where v_dietitian_user_id is not null
    ) recipient
    where recipient.user_id is not null
      and recipient.user_id<>auth.uid()
  loop
    insert into public.notifications(
      clinic_id,recipient_user_id,title,body,category,action_view,metadata,dedupe_key
    ) values(
      v_clinic,v_recipient,'Danışan sadakat ödülü aldı',
      v_client.full_name||', '||v_reward.name||' ödülünü puanıyla aldı.',
      'loyalty_reward_redeemed_staff','loyalty',
      jsonb_build_object(
        'redemption_id',v_redemption_id,
        'client_id',v_client.id,
        'client_name',v_client.full_name,
        'member_no',v_client.member_no,
        'reward_id',v_reward.id,
        'reward_name',v_reward.name,
        'redemption_code',v_code,
        'points_spent',v_reward.points_cost,
        'balance_after',v_new_balance
      ),
      'staff-client-reward-redeemed-'||v_redemption_id::text||'-'||v_recipient::text
    );
  end loop;

  insert into public.audit_logs(
    clinic_id,actor_user_id,action,target_type,target_id,metadata
  ) values(
    v_clinic,auth.uid(),'client_reward_redeemed','reward_redemption',v_redemption_id::text,
    jsonb_build_object(
      'client_id',v_client.id,
      'client_name',v_client.full_name,
      'member_no',v_client.member_no,
      'reward_id',v_reward.id,
      'reward_name',v_reward.name,
      'points_spent',v_reward.points_cost,
      'balance_before',v_balance,
      'balance_after',v_new_balance,
      'redemption_code',v_code,
      'stock_after',case when v_reward.stock is null then null else v_reward.stock-1 end
    )
  );

  return jsonb_build_object(
    'redemption_id',v_redemption_id,
    'client_id',v_client.id,
    'reward_id',v_reward.id,
    'reward_name',v_reward.name,
    'points_spent',v_reward.points_cost,
    'balance_before',v_balance,
    'balance_after',v_new_balance,
    'redemption_code',v_code,
    'code_expires_at',now()+interval '90 days'
  );
end;
$$;

revoke all on function public.client_redeem_reward_v56(uuid) from public;
grant execute on function public.client_redeem_reward_v56(uuid) to authenticated;

commit;
