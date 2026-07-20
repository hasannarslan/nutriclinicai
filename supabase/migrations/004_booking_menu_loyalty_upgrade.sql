-- NutriClinic AI v2.2
-- Fixes staff appointment creation after role promotion and adds owner-managed
-- reward catalogue / auditable stock adjustments.
-- Run once after migrations 001, 002 and 003.

begin;

-- One appointment endpoint decides authorization from the current database role.
-- This prevents a promoted owner/dietitian account from accidentally being treated
-- as a client by stale browser state.
create or replace function public.create_appointment_v2(
  p_dietitian_id uuid,
  p_client_id uuid,
  p_starts_at timestamptz,
  p_appointment_type text,
  p_mode public.appointment_mode,
  p_note text default null
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_client uuid;
  v_duration int;
  v_end timestamptz;
  v_id uuid;
  v_status public.appointment_status;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select m.clinic_id,m.role
  into v_clinic,v_role
  from public.clinic_memberships m
  where m.user_id=auth.uid() and m.is_active=true
  limit 1;

  if v_clinic is null then
    raise exception 'Active clinic membership not found';
  end if;

  select d.appointment_duration_minutes
  into v_duration
  from public.dietitian_profiles d
  where d.id=p_dietitian_id
    and d.clinic_id=v_clinic
    and d.is_bookable=true;

  if v_duration is null then
    raise exception 'Invalid or unavailable dietitian';
  end if;

  if v_role in ('owner','dietitian','secretary') then
    if p_client_id is null then
      raise exception 'Randevu oluşturmak için aktif bir danışan seçin';
    end if;

    select c.id into v_client
    from public.client_profiles c
    left join public.clinic_memberships cm
      on cm.clinic_id=c.clinic_id and cm.user_id=c.user_id
    where c.id=p_client_id
      and c.clinic_id=v_clinic
      and c.is_active=true
      and (c.user_id is null or (cm.role='client' and cm.is_active=true))
    limit 1;

    if v_client is null then
      raise exception 'Seçilen danışan aktif değil veya danışan rolünde değil';
    end if;
    v_status := 'confirmed';
  elsif v_role='client' then
    select c.id into v_client
    from public.client_profiles c
    where c.clinic_id=v_clinic
      and c.user_id=auth.uid()
      and c.is_active=true
    limit 1;

    if v_client is null then
      raise exception 'Aktif danışan profiliniz bulunamadı';
    end if;
    v_status := 'pending';
  else
    raise exception 'Randevu oluşturma yetkiniz bulunmuyor';
  end if;

  v_end := p_starts_at + make_interval(mins=>v_duration);
  perform public.validate_appointment_slot(p_dietitian_id,p_starts_at,v_end);

  begin
    insert into public.appointments(
      clinic_id,dietitian_id,client_id,starts_at,ends_at,mode,
      appointment_type,status,public_note,created_by
    ) values(
      v_clinic,p_dietitian_id,v_client,p_starts_at,v_end,p_mode,
      p_appointment_type,v_status,p_note,auth.uid()
    ) returning id into v_id;
  exception when exclusion_violation then
    raise exception 'Bu randevu saati başka bir kullanıcı tarafından alındı';
  end;

  return v_id;
end;
$$;

revoke all on function public.create_appointment_v2(uuid,uuid,timestamptz,text,public.appointment_mode,text) from public;
grant execute on function public.create_appointment_v2(uuid,uuid,timestamptz,text,public.appointment_mode,text) to authenticated;

-- Auditable reward stock inventory.
do $$
begin
  if not exists (select 1 from pg_constraint where conname='rewards_stock_nonnegative') then
    alter table public.rewards add constraint rewards_stock_nonnegative check (stock is null or stock >= 0);
  end if;
end $$;

create table if not exists public.reward_stock_movements (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  reward_id uuid not null references public.rewards(id) on delete cascade,
  quantity_change int not null check (quantity_change <> 0),
  stock_after int not null check (stock_after >= 0),
  reason text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists reward_stock_movements_reward_created_idx
  on public.reward_stock_movements(reward_id,created_at desc);

alter table public.reward_stock_movements enable row level security;

drop policy if exists reward_stock_movements_owner_select on public.reward_stock_movements;
create policy reward_stock_movements_owner_select
on public.reward_stock_movements
for select
using (public.current_clinic_role(clinic_id)='owner');

drop policy if exists reward_stock_movements_owner_insert on public.reward_stock_movements;
create policy reward_stock_movements_owner_insert
on public.reward_stock_movements
for insert
with check (public.current_clinic_role(clinic_id)='owner');

create or replace function public.adjust_reward_stock(
  p_reward_id uuid,
  p_delta int,
  p_reason text default null
) returns int
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
  v_current int;
  v_next int;
begin
  if p_delta=0 then
    raise exception 'Stok değişimi sıfır olamaz';
  end if;

  select r.clinic_id,r.stock
  into v_clinic,v_current
  from public.rewards r
  where r.id=p_reward_id
  for update;

  if v_clinic is null then
    raise exception 'Ödül bulunamadı';
  end if;
  if public.current_clinic_role(v_clinic)<>'owner' then
    raise exception 'Yalnızca Klinik Sahibi stok değiştirebilir';
  end if;
  if v_current is null then
    raise exception 'Sınırsız stoklu ödülde stok hareketi yapılamaz';
  end if;

  v_next := v_current+p_delta;
  if v_next<0 then
    raise exception 'Stok sıfırın altına düşemez';
  end if;

  update public.rewards
  set stock=v_next
  where id=p_reward_id;

  insert into public.reward_stock_movements(
    clinic_id,reward_id,quantity_change,stock_after,reason,created_by
  ) values(
    v_clinic,p_reward_id,p_delta,v_next,nullif(p_reason,''),auth.uid()
  );

  return v_next;
end;
$$;

revoke all on function public.adjust_reward_stock(uuid,int,text) from public;
grant execute on function public.adjust_reward_stock(uuid,int,text) to authenticated;

-- Existing owner RLS policy is authoritative; these privileges allow the owner UI
-- to create, edit, activate/deactivate and delete catalogue items.
grant insert,update,delete on public.rewards to authenticated;
grant select,insert on public.reward_stock_movements to authenticated;

commit;
