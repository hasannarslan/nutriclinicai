-- NutriClinic AI v2.6
-- Loyalty earned/used/remaining summaries, visible reward redemption history,
-- and operational redemption records. Run once after migrations 001-007.

begin;

create table if not exists public.reward_redemptions (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  reward_id uuid references public.rewards(id) on delete set null,
  loyalty_transaction_id uuid unique references public.loyalty_transactions(id) on delete set null,
  reward_name text not null,
  points_spent int not null check (points_spent > 0),
  status text not null default 'requested' check (status in ('requested','approved','fulfilled','cancelled')),
  requested_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  fulfilled_at timestamptz,
  handled_by uuid references public.profiles(id) on delete set null,
  note text
);

create index if not exists reward_redemptions_client_requested_idx
  on public.reward_redemptions(client_id,requested_at desc);

alter table public.reward_redemptions enable row level security;

drop policy if exists reward_redemptions_select on public.reward_redemptions;
create policy reward_redemptions_select
on public.reward_redemptions for select
using (
  public.current_clinic_role(clinic_id) in ('owner','dietitian')
  or client_id=public.current_client_id(clinic_id)
);

drop policy if exists reward_redemptions_update_staff on public.reward_redemptions;
create policy reward_redemptions_update_staff
on public.reward_redemptions for update
using (public.current_clinic_role(clinic_id) in ('owner','dietitian'))
with check (public.current_clinic_role(clinic_id) in ('owner','dietitian'));

-- Preserve visibility for rewards redeemed before this migration.
insert into public.reward_redemptions(
  clinic_id,client_id,reward_id,loyalty_transaction_id,reward_name,
  points_spent,status,requested_at,updated_at
)
select
  wallet.clinic_id,
  wallet.client_id,
  transaction.reward_id,
  transaction.id,
  coalesce(reward.name, regexp_replace(transaction.reason,'^Ödül kullanımı:\s*','','i')),
  abs(transaction.points),
  'requested',
  transaction.created_at,
  transaction.created_at
from public.loyalty_transactions transaction
join public.loyalty_wallets wallet on wallet.id=transaction.wallet_id
left join public.rewards reward on reward.id=transaction.reward_id
where transaction.transaction_type='redeemed'
  and transaction.points<0
on conflict (loyalty_transaction_id) do nothing;

create or replace function public.get_client_loyalty_summaries()
returns table(
  client_id uuid,
  earned_points bigint,
  used_points bigint,
  remaining_points int
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
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select membership.clinic_id,membership.role
    into v_clinic,v_role
  from public.clinic_memberships membership
  where membership.user_id=auth.uid()
    and membership.is_active=true
  limit 1;

  if v_clinic is null or v_role not in ('owner','dietitian') then
    raise exception 'Only a clinic owner or dietitian can view loyalty summaries';
  end if;

  return query
  select
    client.id,
    coalesce(sum(case when transaction.points>0 then transaction.points else 0 end),0)::bigint as earned_points,
    coalesce(sum(case when transaction.transaction_type='redeemed' and transaction.points<0 then abs(transaction.points) else 0 end),0)::bigint as used_points,
    coalesce(wallet.balance,0)::int as remaining_points
  from public.client_profiles client
  left join public.loyalty_wallets wallet
    on wallet.clinic_id=client.clinic_id and wallet.client_id=client.id
  left join public.loyalty_transactions transaction
    on transaction.wallet_id=wallet.id
  where client.clinic_id=v_clinic
    and client.is_active=true
  group by client.id,wallet.balance
  order by client.created_at desc;
end;
$$;

create or replace function public.get_reward_redemptions(
  p_client_id uuid default null
) returns table(
  id uuid,
  client_id uuid,
  reward_name text,
  points_spent int,
  status text,
  requested_at timestamptz,
  fulfilled_at timestamptz,
  note text
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
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select membership.clinic_id,membership.role
    into v_clinic,v_role
  from public.clinic_memberships membership
  where membership.user_id=auth.uid()
    and membership.is_active=true
  limit 1;

  if v_clinic is null then
    raise exception 'Active clinic membership not found';
  end if;

  if v_role='client' then
    select client.id into v_own_client
    from public.client_profiles client
    where client.clinic_id=v_clinic
      and client.user_id=auth.uid()
      and client.is_active=true
    limit 1;

    if v_own_client is null then
      raise exception 'Active client profile not found';
    end if;

    return query
    select redemption.id,redemption.client_id,redemption.reward_name,
           redemption.points_spent,redemption.status,redemption.requested_at,
           redemption.fulfilled_at,redemption.note
    from public.reward_redemptions redemption
    where redemption.clinic_id=v_clinic
      and redemption.client_id=v_own_client
    order by redemption.requested_at desc;
  elsif v_role in ('owner','dietitian') then
    return query
    select redemption.id,redemption.client_id,redemption.reward_name,
           redemption.points_spent,redemption.status,redemption.requested_at,
           redemption.fulfilled_at,redemption.note
    from public.reward_redemptions redemption
    where redemption.clinic_id=v_clinic
      and (p_client_id is null or redemption.client_id=p_client_id)
    order by redemption.requested_at desc;
  else
    raise exception 'Access denied';
  end if;
end;
$$;

create or replace function public.redeem_reward(
  p_reward_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_client_id uuid;
  v_wallet_id uuid;
  v_balance int;
  v_new_balance int;
  v_reward_name text;
  v_points_cost int;
  v_stock int;
  v_transaction_id uuid;
  v_redemption_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select client.clinic_id,client.id
    into v_clinic,v_client_id
  from public.client_profiles client
  join public.clinic_memberships membership
    on membership.clinic_id=client.clinic_id
   and membership.user_id=client.user_id
   and membership.role='client'
   and membership.is_active=true
  where client.user_id=auth.uid()
    and client.is_active=true
  limit 1;

  if v_client_id is null then
    raise exception 'Active client profile not found';
  end if;

  select reward.name,reward.points_cost,reward.stock
    into v_reward_name,v_points_cost,v_stock
  from public.rewards reward
  where reward.id=p_reward_id
    and reward.clinic_id=v_clinic
    and reward.is_active=true
  for update;

  if v_reward_name is null then
    raise exception 'Reward is unavailable';
  end if;

  if v_stock is not null and v_stock<=0 then
    raise exception 'Reward is out of stock';
  end if;

  insert into public.loyalty_wallets(clinic_id,client_id,balance)
  values(v_clinic,v_client_id,0)
  on conflict(clinic_id,client_id) do nothing;

  select wallet.id,wallet.balance
    into v_wallet_id,v_balance
  from public.loyalty_wallets wallet
  where wallet.clinic_id=v_clinic
    and wallet.client_id=v_client_id
  for update;

  if v_balance<v_points_cost then
    raise exception 'Insufficient loyalty points';
  end if;

  v_new_balance := v_balance-v_points_cost;

  update public.loyalty_wallets
  set balance=v_new_balance,updated_at=now()
  where id=v_wallet_id;

  if v_stock is not null then
    update public.rewards set stock=v_stock-1 where id=p_reward_id;
    insert into public.reward_stock_movements(
      clinic_id,reward_id,quantity_change,stock_after,reason,created_by
    ) values(
      v_clinic,p_reward_id,-1,v_stock-1,'Danışan ödül kullanımı',auth.uid()
    );
  end if;

  insert into public.loyalty_transactions(
    wallet_id,transaction_type,points,reason,reward_id,created_by,balance_after
  ) values(
    v_wallet_id,'redeemed',-v_points_cost,'Ödül kullanımı: '||v_reward_name,p_reward_id,auth.uid(),v_new_balance
  ) returning id into v_transaction_id;

  insert into public.reward_redemptions(
    clinic_id,client_id,reward_id,loyalty_transaction_id,reward_name,
    points_spent,status,requested_at,updated_at
  ) values(
    v_clinic,v_client_id,p_reward_id,v_transaction_id,v_reward_name,
    v_points_cost,'requested',now(),now()
  ) returning id into v_redemption_id;

  insert into public.audit_logs(
    clinic_id,actor_user_id,action,target_type,target_id,metadata
  ) values(
    v_clinic,auth.uid(),'loyalty_reward_redeemed','reward',p_reward_id::text,
    jsonb_build_object(
      'transaction_id',v_transaction_id,
      'redemption_id',v_redemption_id,
      'client_id',v_client_id,
      'reward_name',v_reward_name,
      'points_spent',v_points_cost,
      'balance_before',v_balance,
      'balance_after',v_new_balance,
      'stock_after',case when v_stock is null then null else v_stock-1 end
    )
  );

  return jsonb_build_object(
    'balance',v_new_balance,
    'reward_name',v_reward_name,
    'transaction_id',v_transaction_id,
    'redemption_id',v_redemption_id
  );
end;
$$;

revoke all on function public.get_client_loyalty_summaries() from public;
revoke all on function public.get_reward_redemptions(uuid) from public;
revoke all on function public.redeem_reward(uuid) from public;

grant execute on function public.get_client_loyalty_summaries() to authenticated;
grant execute on function public.get_reward_redemptions(uuid) to authenticated;
grant execute on function public.redeem_reward(uuid) to authenticated;
grant select,update on public.reward_redemptions to authenticated;

commit;
