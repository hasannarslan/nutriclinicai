-- NutriClinic AI v2.4
-- Owner/dietitian manual loyalty point awards with transaction and audit logs.

alter table public.loyalty_transactions
  add column if not exists balance_after int;

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
  v_wallet_id uuid;
  v_old_balance int;
  v_new_balance int;
  v_transaction_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_points is null or p_points <= 0 then
    raise exception 'Points must be a positive integer';
  end if;

  if nullif(btrim(coalesce(p_reason,'')),'') is null then
    raise exception 'A reason is required for the loyalty log';
  end if;

  select c.clinic_id
    into v_clinic
  from public.client_profiles c
  where c.id=p_client_id
    and c.is_active=true;

  if v_clinic is null then
    raise exception 'Active client profile not found';
  end if;

  select m.role
    into v_role
  from public.clinic_memberships m
  where m.clinic_id=v_clinic
    and m.user_id=auth.uid()
    and m.is_active=true
  limit 1;

  if v_role is null or v_role not in ('owner','dietitian') then
    raise exception 'Only a clinic owner or dietitian can add loyalty points';
  end if;

  insert into public.loyalty_wallets(clinic_id,client_id,balance)
  values(v_clinic,p_client_id,0)
  on conflict(clinic_id,client_id) do nothing;

  select w.id,w.balance
    into v_wallet_id,v_old_balance
  from public.loyalty_wallets w
  where w.clinic_id=v_clinic
    and w.client_id=p_client_id
  for update;

  if v_old_balance > 2147483647 - p_points then
    raise exception 'Loyalty balance limit would be exceeded';
  end if;

  v_new_balance := v_old_balance + p_points;

  update public.loyalty_wallets
  set balance=v_new_balance,
      updated_at=now()
  where id=v_wallet_id;

  insert into public.loyalty_transactions(
    wallet_id,transaction_type,points,reason,created_by,balance_after
  ) values(
    v_wallet_id,'adjusted',p_points,btrim(p_reason),auth.uid(),v_new_balance
  ) returning id into v_transaction_id;

  insert into public.audit_logs(
    clinic_id,actor_user_id,action,target_type,target_id,metadata
  ) values(
    v_clinic,
    auth.uid(),
    'client_loyalty_points_added',
    'client',
    p_client_id::text,
    jsonb_build_object(
      'transaction_id',v_transaction_id,
      'points_added',p_points,
      'reason',btrim(p_reason),
      'balance_before',v_old_balance,
      'balance_after',v_new_balance,
      'actor_role',v_role
    )
  );

  return v_new_balance;
end;
$$;

create or replace function public.get_client_loyalty_history(
  p_client_id uuid
) returns table(
  id uuid,
  transaction_type public.reward_transaction_type,
  points int,
  reason text,
  actor_user_id uuid,
  actor_name text,
  actor_role public.clinic_role,
  balance_after int,
  created_at timestamptz
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

  select c.clinic_id
    into v_clinic
  from public.client_profiles c
  where c.id=p_client_id;

  select m.role
    into v_role
  from public.clinic_memberships m
  where m.clinic_id=v_clinic
    and m.user_id=auth.uid()
    and m.is_active=true
  limit 1;

  if v_role is null or v_role not in ('owner','dietitian') then
    raise exception 'Only a clinic owner or dietitian can view this loyalty history';
  end if;

  return query
  select
    t.id,
    t.transaction_type,
    t.points,
    t.reason,
    t.created_by as actor_user_id,
    p.full_name as actor_name,
    membership.role as actor_role,
    t.balance_after,
    t.created_at
  from public.loyalty_transactions t
  join public.loyalty_wallets w on w.id=t.wallet_id
  left join public.profiles p on p.id=t.created_by
  left join public.clinic_memberships membership
    on membership.clinic_id=w.clinic_id
   and membership.user_id=t.created_by
  where w.client_id=p_client_id
    and w.clinic_id=v_clinic
  order by t.created_at desc
  limit 100;
end;
$$;

revoke all on function public.add_client_loyalty_points(uuid,int,text) from public;
revoke all on function public.get_client_loyalty_history(uuid) from public;
grant execute on function public.add_client_loyalty_points(uuid,int,text) to authenticated;
grant execute on function public.get_client_loyalty_history(uuid) to authenticated;

grant select on public.loyalty_wallets,public.loyalty_transactions,public.audit_logs to authenticated;
