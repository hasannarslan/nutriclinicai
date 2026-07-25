-- NutriClinic AI v2.5
-- Hides the first-owner card when an owner already exists, adds a month calendar
-- availability endpoint, atomic meal-plan create/edit and client reward redemption.
-- Run once after migrations 001 through 006.

begin;

create or replace function public.can_claim_first_owner()
returns boolean
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
begin
  if auth.uid() is null then
    return false;
  end if;

  select m.clinic_id
    into v_clinic
  from public.clinic_memberships m
  where m.user_id=auth.uid()
    and m.is_active=true
  limit 1;

  if v_clinic is null then
    return false;
  end if;

  return not exists(
    select 1
    from public.clinic_memberships owner_membership
    where owner_membership.clinic_id=v_clinic
      and owner_membership.role='owner'
      and owner_membership.is_active=true
  );
end;
$$;

create or replace function public.get_dietitian_calendar(
  p_dietitian_id uuid,
  p_start date,
  p_end date
) returns table(
  day date,
  available_count int,
  total_count int
)
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_day date;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_start is null or p_end is null or p_end < p_start then
    raise exception 'Invalid calendar date range';
  end if;

  if p_end-p_start > 42 then
    raise exception 'Calendar range cannot exceed 43 days';
  end if;

  select d.clinic_id
    into v_clinic
  from public.dietitian_profiles d
  where d.id=p_dietitian_id
    and d.is_bookable=true;

  if v_clinic is null or public.current_clinic_role(v_clinic) is null then
    raise exception 'Access denied';
  end if;

  for v_day in
    select generate_series(p_start,p_end,interval '1 day')::date
  loop
    return query
    select
      v_day,
      (count(*) filter (where slot.is_available))::int,
      count(*)::int
    from public.get_dietitian_day_slots(p_dietitian_id,v_day) slot;
  end loop;
end;
$$;

create or replace function public.save_meal_plan_v2(
  p_plan_id uuid,
  p_client_id uuid,
  p_title text,
  p_starts_on date,
  p_ends_on date,
  p_target_calories numeric,
  p_target_protein_g numeric,
  p_target_carbs_g numeric,
  p_target_fat_g numeric,
  p_note text,
  p_items jsonb
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_dietitian_id uuid;
  v_plan_id uuid;
  v_action text;
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
    raise exception 'Only a clinic owner or dietitian can save meal plans';
  end if;

  if p_starts_on is null or p_ends_on is null or p_ends_on<p_starts_on then
    raise exception 'Invalid plan date range';
  end if;

  if nullif(btrim(coalesce(p_title,'')),'') is null then
    raise exception 'Plan title is required';
  end if;

  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then
    raise exception 'At least one meal item is required';
  end if;

  if not exists(
    select 1 from public.client_profiles client
    where client.id=p_client_id
      and client.clinic_id=v_clinic
      and client.is_active=true
  ) then
    raise exception 'Active client not found';
  end if;

  select dietitian.id
    into v_dietitian_id
  from public.dietitian_profiles dietitian
  where dietitian.clinic_id=v_clinic
    and dietitian.user_id=auth.uid()
  limit 1;

  if p_plan_id is null then
    if v_dietitian_id is null then
      raise exception 'Dietitian profile not found';
    end if;

    insert into public.meal_plans(
      clinic_id,client_id,dietitian_id,title,starts_on,ends_on,
      target_calories,target_protein_g,target_carbs_g,target_fat_g,
      status,dietitian_note
    ) values(
      v_clinic,p_client_id,v_dietitian_id,btrim(p_title),p_starts_on,p_ends_on,
      p_target_calories,p_target_protein_g,p_target_carbs_g,p_target_fat_g,
      'active',nullif(btrim(coalesce(p_note,'')),'')
    ) returning id into v_plan_id;
    v_action := 'meal_plan_created';
  else
    select plan.id
      into v_plan_id
    from public.meal_plans plan
    where plan.id=p_plan_id
      and plan.clinic_id=v_clinic
    for update;

    if v_plan_id is null then
      raise exception 'Meal plan not found';
    end if;

    update public.meal_plans
    set client_id=p_client_id,
        title=btrim(p_title),
        starts_on=p_starts_on,
        ends_on=p_ends_on,
        target_calories=p_target_calories,
        target_protein_g=p_target_protein_g,
        target_carbs_g=p_target_carbs_g,
        target_fat_g=p_target_fat_g,
        dietitian_note=nullif(btrim(coalesce(p_note,'')),''),
        updated_at=now()
    where id=v_plan_id;

    delete from public.meal_plan_items where meal_plan_id=v_plan_id;
    v_action := 'meal_plan_updated';
  end if;

  insert into public.meal_plan_items(
    meal_plan_id,meal_name,food_name,portion_text,
    calories,protein_g,carbs_g,fat_g,sort_order
  )
  select
    v_plan_id,
    coalesce(nullif(btrim(item.value->>'meal_name'),''),'Diğer'),
    btrim(item.value->>'food_name'),
    nullif(btrim(coalesce(item.value->>'portion_text','')),''),
    coalesce(nullif(item.value->>'calories','')::numeric,0),
    coalesce(nullif(item.value->>'protein_g','')::numeric,0),
    coalesce(nullif(item.value->>'carbs_g','')::numeric,0),
    coalesce(nullif(item.value->>'fat_g','')::numeric,0),
    coalesce(nullif(item.value->>'sort_order','')::smallint,(item.ordinality-1)::smallint)
  from jsonb_array_elements(p_items) with ordinality as item(value,ordinality)
  where nullif(btrim(item.value->>'food_name'),'') is not null;

  if not exists(select 1 from public.meal_plan_items where meal_plan_id=v_plan_id) then
    raise exception 'At least one valid food item is required';
  end if;

  insert into public.audit_logs(
    clinic_id,actor_user_id,action,target_type,target_id,metadata
  ) values(
    v_clinic,auth.uid(),v_action,'meal_plan',v_plan_id::text,
    jsonb_build_object('client_id',p_client_id,'item_count',jsonb_array_length(p_items),'actor_role',v_role)
  );

  return v_plan_id;
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
  set balance=v_new_balance,
      updated_at=now()
  where id=v_wallet_id;

  if v_stock is not null then
    update public.rewards
    set stock=v_stock-1
    where id=p_reward_id;

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

  insert into public.audit_logs(
    clinic_id,actor_user_id,action,target_type,target_id,metadata
  ) values(
    v_clinic,auth.uid(),'loyalty_reward_redeemed','reward',p_reward_id::text,
    jsonb_build_object(
      'transaction_id',v_transaction_id,
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
    'transaction_id',v_transaction_id
  );
end;
$$;

revoke all on function public.can_claim_first_owner() from public;
revoke all on function public.get_dietitian_calendar(uuid,date,date) from public;
revoke all on function public.save_meal_plan_v2(uuid,uuid,text,date,date,numeric,numeric,numeric,numeric,text,jsonb) from public;
revoke all on function public.redeem_reward(uuid) from public;

grant execute on function public.can_claim_first_owner() to authenticated;
grant execute on function public.get_dietitian_calendar(uuid,date,date) to authenticated;
grant execute on function public.save_meal_plan_v2(uuid,uuid,text,date,date,numeric,numeric,numeric,numeric,text,jsonb) to authenticated;
grant execute on function public.redeem_reward(uuid) to authenticated;

commit;
