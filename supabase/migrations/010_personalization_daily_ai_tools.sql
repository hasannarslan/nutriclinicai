-- NutriClinic AI v4.0
-- Personalized onboarding, daily wellness tracking, AI recipe and food label analysis.
-- Run once after migrations 001-009.

alter table public.client_profiles
  add column if not exists onboarding_completed boolean not null default false,
  add column if not exists onboarding_completed_at timestamptz,
  add column if not exists primary_goal text,
  add column if not exists motivation_reasons text[] not null default '{}',
  add column if not exists current_weight_kg numeric(6,2),
  add column if not exists target_weight_kg numeric(6,2),
  add column if not exists activity_level text,
  add column if not exists calorie_knowledge text,
  add column if not exists diet_style text,
  add column if not exists chronic_conditions text[] not null default '{}',
  add column if not exists additive_reactions text[] not null default '{}',
  add column if not exists water_goal_ml integer not null default 2000,
  add column if not exists goal_pace_kg_per_week numeric(4,2) not null default 0.50,
  add column if not exists daily_tracking_enabled boolean not null default true;

create table if not exists public.daily_water_logs (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  log_date date not null default current_date,
  amount_ml integer not null check (amount_ml between 1 and 5000),
  created_at timestamptz not null default now()
);
create index if not exists daily_water_logs_client_date_idx on public.daily_water_logs(client_id,log_date);

create table if not exists public.activity_logs (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  activity_date date not null default current_date,
  activity_type text not null,
  duration_minutes integer not null default 0 check (duration_minutes between 0 and 1440),
  calories_burned numeric(8,2) not null default 0 check (calories_burned >= 0),
  note text,
  source text not null default 'manual',
  created_at timestamptz not null default now()
);
create index if not exists activity_logs_client_date_idx on public.activity_logs(client_id,activity_date);

create table if not exists public.client_weight_logs (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  weight_date date not null default current_date,
  weight_kg numeric(6,2) not null check (weight_kg between 20 and 500),
  source text not null default 'client',
  created_at timestamptz not null default now(),
  unique(client_id,weight_date)
);
create index if not exists client_weight_logs_client_date_idx on public.client_weight_logs(client_id,weight_date desc);

create table if not exists public.ai_generated_recipes (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid references public.client_profiles(id) on delete cascade,
  created_by uuid not null references public.profiles(id) on delete cascade,
  ingredients text not null,
  meal_type text,
  max_minutes integer,
  max_calories integer,
  recipe jsonb not null,
  is_saved boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists ai_generated_recipes_user_idx on public.ai_generated_recipes(created_by,created_at desc);

create table if not exists public.food_label_scans (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid references public.client_profiles(id) on delete cascade,
  created_by uuid not null references public.profiles(id) on delete cascade,
  filename text,
  result jsonb not null,
  created_at timestamptz not null default now()
);
create index if not exists food_label_scans_user_idx on public.food_label_scans(created_by,created_at desc);

alter table public.daily_water_logs enable row level security;
alter table public.activity_logs enable row level security;
alter table public.client_weight_logs enable row level security;
alter table public.ai_generated_recipes enable row level security;
alter table public.food_label_scans enable row level security;

drop policy if exists water_select_v4 on public.daily_water_logs;
create policy water_select_v4 on public.daily_water_logs for select using (
  client_id=public.current_client_id(clinic_id)
  or public.current_clinic_role(clinic_id) in ('owner','dietitian')
);
drop policy if exists water_insert_v4 on public.daily_water_logs;
create policy water_insert_v4 on public.daily_water_logs for insert with check (
  client_id=public.current_client_id(clinic_id)
);
drop policy if exists water_delete_v4 on public.daily_water_logs;
create policy water_delete_v4 on public.daily_water_logs for delete using (
  client_id=public.current_client_id(clinic_id)
);

drop policy if exists activity_select_v4 on public.activity_logs;
create policy activity_select_v4 on public.activity_logs for select using (
  client_id=public.current_client_id(clinic_id)
  or public.current_clinic_role(clinic_id) in ('owner','dietitian')
);
drop policy if exists activity_insert_v4 on public.activity_logs;
create policy activity_insert_v4 on public.activity_logs for insert with check (
  client_id=public.current_client_id(clinic_id)
);
drop policy if exists activity_delete_v4 on public.activity_logs;
create policy activity_delete_v4 on public.activity_logs for delete using (
  client_id=public.current_client_id(clinic_id)
);

drop policy if exists weight_select_v4 on public.client_weight_logs;
create policy weight_select_v4 on public.client_weight_logs for select using (
  client_id=public.current_client_id(clinic_id)
  or public.current_clinic_role(clinic_id) in ('owner','dietitian')
);
drop policy if exists weight_insert_v4 on public.client_weight_logs;
create policy weight_insert_v4 on public.client_weight_logs for insert with check (
  client_id=public.current_client_id(clinic_id)
  or public.current_clinic_role(clinic_id) in ('owner','dietitian')
);
drop policy if exists weight_update_v4 on public.client_weight_logs;
create policy weight_update_v4 on public.client_weight_logs for update using (
  client_id=public.current_client_id(clinic_id)
  or public.current_clinic_role(clinic_id) in ('owner','dietitian')
) with check (
  client_id=public.current_client_id(clinic_id)
  or public.current_clinic_role(clinic_id) in ('owner','dietitian')
);

drop policy if exists recipes_select_v4 on public.ai_generated_recipes;
create policy recipes_select_v4 on public.ai_generated_recipes for select using (
  created_by=auth.uid()
  or (client_id is not null and public.current_clinic_role(clinic_id) in ('owner','dietitian'))
);
drop policy if exists recipes_insert_v4 on public.ai_generated_recipes;
create policy recipes_insert_v4 on public.ai_generated_recipes for insert with check (created_by=auth.uid());
drop policy if exists recipes_update_v4 on public.ai_generated_recipes;
create policy recipes_update_v4 on public.ai_generated_recipes for update using (created_by=auth.uid()) with check (created_by=auth.uid());

drop policy if exists scans_select_v4 on public.food_label_scans;
create policy scans_select_v4 on public.food_label_scans for select using (
  created_by=auth.uid()
  or (client_id is not null and public.current_clinic_role(clinic_id) in ('owner','dietitian'))
);
drop policy if exists scans_insert_v4 on public.food_label_scans;
create policy scans_insert_v4 on public.food_label_scans for insert with check (created_by=auth.uid());

grant select,insert,delete on public.daily_water_logs,public.activity_logs to authenticated;
grant select,insert,update on public.client_weight_logs to authenticated;
grant select,insert,update on public.ai_generated_recipes to authenticated;
grant select,insert on public.food_label_scans to authenticated;

create or replace function public.get_my_onboarding_v4()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_client public.client_profiles%rowtype;
  v_weight numeric;
begin
  select c.* into v_client
  from public.client_profiles c
  join public.clinic_memberships m on m.clinic_id=c.clinic_id and m.user_id=auth.uid() and m.is_active=true
  where c.user_id=auth.uid() and c.is_active=true
  limit 1;

  if v_client.id is null then raise exception 'Client profile not found'; end if;

  select coalesce(
    (select w.weight_kg from public.client_weight_logs w where w.client_id=v_client.id order by w.weight_date desc,w.created_at desc limit 1),
    (select m.weight_kg from public.measurements m where m.client_id=v_client.id and m.weight_kg is not null order by m.measured_at desc limit 1),
    v_client.current_weight_kg
  ) into v_weight;

  return jsonb_build_object(
    'id',v_client.id,
    'completed',v_client.onboarding_completed,
    'primary_goal',v_client.primary_goal,
    'motivation_reasons',v_client.motivation_reasons,
    'gender',v_client.gender,
    'birth_date',v_client.birth_date,
    'height_cm',v_client.height_cm,
    'current_weight_kg',v_weight,
    'target_weight_kg',v_client.target_weight_kg,
    'activity_level',v_client.activity_level,
    'calorie_knowledge',v_client.calorie_knowledge,
    'diet_style',v_client.diet_style,
    'chronic_conditions',v_client.chronic_conditions,
    'allergies',v_client.allergies,
    'additive_reactions',v_client.additive_reactions,
    'water_goal_ml',v_client.water_goal_ml,
    'goal_pace_kg_per_week',v_client.goal_pace_kg_per_week
  );
end;
$$;

create or replace function public.complete_client_onboarding_v4(
  p_primary_goal text,
  p_motivation_reasons text[],
  p_gender text,
  p_birth_date date,
  p_height_cm numeric,
  p_current_weight_kg numeric,
  p_target_weight_kg numeric,
  p_activity_level text,
  p_calorie_knowledge text,
  p_diet_style text,
  p_chronic_conditions text[],
  p_allergies text[],
  p_additive_reactions text[],
  p_water_goal_ml integer,
  p_goal_pace_kg_per_week numeric
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_client_id uuid;
  v_clinic uuid;
begin
  select c.id,c.clinic_id into v_client_id,v_clinic
  from public.client_profiles c
  where c.user_id=auth.uid() and c.is_active=true
  limit 1;
  if v_client_id is null then raise exception 'Client profile not found'; end if;
  if p_height_cm is null or p_height_cm<100 or p_height_cm>250 then raise exception 'Height is invalid'; end if;
  if p_current_weight_kg is null or p_current_weight_kg<20 or p_current_weight_kg>500 then raise exception 'Weight is invalid'; end if;
  if p_target_weight_kg is null or p_target_weight_kg<20 or p_target_weight_kg>500 then raise exception 'Target weight is invalid'; end if;

  update public.client_profiles set
    primary_goal=nullif(trim(p_primary_goal),''),
    motivation_reasons=coalesce(p_motivation_reasons,'{}'),
    gender=nullif(trim(p_gender),''),
    birth_date=p_birth_date,
    height_cm=p_height_cm,
    current_weight_kg=p_current_weight_kg,
    target_weight_kg=p_target_weight_kg,
    target_text=case when p_target_weight_kg is null then target_text else concat(p_target_weight_kg,' kg') end,
    activity_level=nullif(trim(p_activity_level),''),
    calorie_knowledge=nullif(trim(p_calorie_knowledge),''),
    diet_style=nullif(trim(p_diet_style),''),
    chronic_conditions=coalesce(p_chronic_conditions,'{}'),
    allergies=coalesce(p_allergies,'{}'),
    additive_reactions=coalesce(p_additive_reactions,'{}'),
    water_goal_ml=greatest(500,least(coalesce(p_water_goal_ml,2000),8000)),
    goal_pace_kg_per_week=greatest(0.10,least(coalesce(p_goal_pace_kg_per_week,0.50),1.50)),
    onboarding_completed=true,
    onboarding_completed_at=now(),
    updated_at=now()
  where id=v_client_id;

  insert into public.client_weight_logs(clinic_id,client_id,weight_date,weight_kg,source)
  values(v_clinic,v_client_id,current_date,p_current_weight_kg,'onboarding')
  on conflict(client_id,weight_date) do update set weight_kg=excluded.weight_kg,source='onboarding',created_at=now();

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values(v_clinic,auth.uid(),'client_onboarding_completed','client',v_client_id::text,
    jsonb_build_object('goal',p_primary_goal,'current_weight_kg',p_current_weight_kg,'target_weight_kg',p_target_weight_kg));

  return public.get_my_onboarding_v4();
end;
$$;

create or replace function public.add_water_v4(p_amount_ml integer,p_log_date date default current_date)
returns integer
language plpgsql
security definer
set search_path=public
as $$
declare v_client uuid;v_clinic uuid;v_total integer;
begin
  if p_amount_ml<1 or p_amount_ml>5000 then raise exception 'Invalid water amount'; end if;
  select c.id,c.clinic_id into v_client,v_clinic from public.client_profiles c where c.user_id=auth.uid() and c.is_active=true limit 1;
  if v_client is null then raise exception 'Client profile not found'; end if;
  insert into public.daily_water_logs(clinic_id,client_id,log_date,amount_ml) values(v_clinic,v_client,coalesce(p_log_date,current_date),p_amount_ml);
  select coalesce(sum(amount_ml),0)::integer into v_total from public.daily_water_logs where client_id=v_client and log_date=coalesce(p_log_date,current_date);
  return v_total;
end;
$$;

create or replace function public.add_activity_v4(
  p_activity_type text,
  p_duration_minutes integer,
  p_calories_burned numeric,
  p_note text default null,
  p_activity_date date default current_date
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare v_client uuid;v_clinic uuid;v_id uuid;
begin
  select c.id,c.clinic_id into v_client,v_clinic from public.client_profiles c where c.user_id=auth.uid() and c.is_active=true limit 1;
  if v_client is null then raise exception 'Client profile not found'; end if;
  insert into public.activity_logs(clinic_id,client_id,activity_date,activity_type,duration_minutes,calories_burned,note)
  values(v_clinic,v_client,coalesce(p_activity_date,current_date),nullif(trim(p_activity_type),''),greatest(coalesce(p_duration_minutes,0),0),greatest(coalesce(p_calories_burned,0),0),nullif(trim(coalesce(p_note,'')),''))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.add_client_weight_v4(p_weight_kg numeric,p_weight_date date default current_date)
returns numeric
language plpgsql
security definer
set search_path=public
as $$
declare v_client uuid;v_clinic uuid;
begin
  if p_weight_kg<20 or p_weight_kg>500 then raise exception 'Invalid weight'; end if;
  select c.id,c.clinic_id into v_client,v_clinic from public.client_profiles c where c.user_id=auth.uid() and c.is_active=true limit 1;
  if v_client is null then raise exception 'Client profile not found'; end if;
  insert into public.client_weight_logs(clinic_id,client_id,weight_date,weight_kg,source)
  values(v_clinic,v_client,coalesce(p_weight_date,current_date),p_weight_kg,'client')
  on conflict(client_id,weight_date) do update set weight_kg=excluded.weight_kg,source='client',created_at=now();
  update public.client_profiles set current_weight_kg=p_weight_kg,updated_at=now() where id=v_client;
  return p_weight_kg;
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
  v_client public.client_profiles%rowtype;
  v_plan public.meal_plans%rowtype;
  v_water integer;
  v_burned numeric;
  v_weight numeric;
  v_meals jsonb;
  v_consumed jsonb;
  v_weight_history jsonb;
begin
  select c.* into v_client from public.client_profiles c where c.user_id=auth.uid() and c.is_active=true limit 1;
  if v_client.id is null then raise exception 'Client profile not found'; end if;

  select p.* into v_plan
  from public.meal_plans p
  where p.client_id=v_client.id and p.status='active' and coalesce(p_date,current_date) between p.starts_on and p.ends_on
  order by p.created_at desc limit 1;

  select coalesce(sum(w.amount_ml),0)::integer into v_water
  from public.daily_water_logs w where w.client_id=v_client.id and w.log_date=coalesce(p_date,current_date);

  select coalesce(sum(a.calories_burned),0) into v_burned
  from public.activity_logs a where a.client_id=v_client.id and a.activity_date=coalesce(p_date,current_date);

  select coalesce(
    (select w.weight_kg from public.client_weight_logs w where w.client_id=v_client.id and w.weight_date<=coalesce(p_date,current_date) order by w.weight_date desc,w.created_at desc limit 1),
    (select m.weight_kg from public.measurements m where m.client_id=v_client.id and m.weight_kg is not null order by m.measured_at desc limit 1),
    v_client.current_weight_kg
  ) into v_weight;

  if v_plan.id is null then
    v_meals='[]'::jsonb;
    v_consumed=jsonb_build_object('calories',0,'protein_g',0,'carbs_g',0,'fat_g',0);
  else
    select coalesce(jsonb_agg(row_data order by meal_sort,item_sort),'[]'::jsonb) into v_meals
    from (
      select jsonb_build_object(
        'id',i.id,'meal_name',i.meal_name,'food_name',i.food_name,'portion_text',i.portion_text,
        'calories',i.calories,'protein_g',i.protein_g,'carbs_g',i.carbs_g,'fat_g',i.fat_g,
        'completed',exists(select 1 from public.meal_completions mc where mc.item_id=i.id and mc.client_id=v_client.id and mc.consumed_on=coalesce(p_date,current_date))
      ) row_data,
      case i.meal_name when 'Kahvaltı' then 1 when 'Ara Öğün' then 2 when 'Öğle Yemeği' then 3 when 'İkindi Ara Öğünü' then 4 when 'Akşam Yemeği' then 5 when 'Gece Ara Öğünü' then 6 else 9 end meal_sort,
      i.sort_order item_sort
      from public.meal_plan_items i where i.meal_plan_id=v_plan.id
    ) s;

    select jsonb_build_object(
      'calories',coalesce(sum(i.calories),0),
      'protein_g',coalesce(sum(i.protein_g),0),
      'carbs_g',coalesce(sum(i.carbs_g),0),
      'fat_g',coalesce(sum(i.fat_g),0)
    ) into v_consumed
    from public.meal_plan_items i
    where i.meal_plan_id=v_plan.id
      and exists(select 1 from public.meal_completions mc where mc.item_id=i.id and mc.client_id=v_client.id and mc.consumed_on=coalesce(p_date,current_date));
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('date',q.weight_date,'weight_kg',q.weight_kg) order by q.weight_date),'[]'::jsonb)
  into v_weight_history
  from (
    select w.weight_date,w.weight_kg from public.client_weight_logs w where w.client_id=v_client.id order by w.weight_date desc limit 14
  ) q;

  return jsonb_build_object(
    'date',coalesce(p_date,current_date),
    'client',jsonb_build_object(
      'id',v_client.id,'name',v_client.full_name,'goal',v_client.primary_goal,'height_cm',v_client.height_cm,
      'current_weight_kg',v_weight,'target_weight_kg',v_client.target_weight_kg,'water_goal_ml',v_client.water_goal_ml,
      'allergies',v_client.allergies,'disliked_foods',v_client.disliked_foods,'diet_style',v_client.diet_style
    ),
    'plan',case when v_plan.id is null then null else jsonb_build_object(
      'id',v_plan.id,'title',v_plan.title,'target_calories',coalesce(v_plan.target_calories,0),
      'target_protein_g',coalesce(v_plan.target_protein_g,0),'target_carbs_g',coalesce(v_plan.target_carbs_g,0),
      'target_fat_g',coalesce(v_plan.target_fat_g,0),'dietitian_note',v_plan.dietitian_note
    ) end,
    'consumed',v_consumed,
    'meals',v_meals,
    'water_ml',v_water,
    'burned_calories',coalesce(v_burned,0),
    'weight_history',v_weight_history
  );
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
  left join lateral (select coalesce(sum(case when p.status not in ('cancelled','refunded') then p.amount else 0 end),0)::numeric total,coalesce(sum(case when p.status='paid' then p.amount else 0 end),0)::numeric paid from public.payments p where p.client_id=c.id) pay on true
  left join lateral (select p.status,p.method,p.service_type,p.paid_at from public.payments p where p.client_id=c.id order by p.created_at desc limit 1) last_pay on true
  where c.clinic_id=v_clinic and c.is_active=true
  order by c.created_at desc;
end;
$$;

grant execute on function public.get_my_onboarding_v4() to authenticated;
grant execute on function public.complete_client_onboarding_v4(text,text[],text,date,numeric,numeric,numeric,text,text,text,text[],text[],text[],integer,numeric) to authenticated;
grant execute on function public.add_water_v4(integer,date) to authenticated;
grant execute on function public.add_activity_v4(text,integer,numeric,text,date) to authenticated;
grant execute on function public.add_client_weight_v4(numeric,date) to authenticated;
grant execute on function public.get_client_daily_hub_v4(date) to authenticated;
grant execute on function public.get_client_directory_v4() to authenticated;
