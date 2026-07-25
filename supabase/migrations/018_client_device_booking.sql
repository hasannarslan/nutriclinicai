-- NutriClinic AI v6.2
-- Client self-service device booking and clinical resource management.
-- Run once after 017_clinic_operations_sprint.sql.

begin;

alter table public.clinic_resources
  add column if not exists client_bookable boolean not null default false,
  add column if not exists slot_minutes integer not null default 45,
  add column if not exists booking_start_time time not null default '09:00',
  add column if not exists booking_end_time time not null default '18:00';

alter table public.clinic_resources
  drop constraint if exists clinic_resources_slot_minutes_check;
alter table public.clinic_resources
  add constraint clinic_resources_slot_minutes_check check (slot_minutes between 15 and 240);

alter table public.clinic_resources
  drop constraint if exists clinic_resources_booking_hours_check;
alter table public.clinic_resources
  add constraint clinic_resources_booking_hours_check check (booking_end_time > booking_start_time);

-- Existing devices/equipment become client-bookable by default.
update public.clinic_resources
set client_bookable=true
where resource_type in ('device','equipment') and client_bookable=false;

-- Clients may read the clinic's resource catalogue. Only clinical roles may manage it.
drop policy if exists resources_staff_read on public.clinic_resources;
drop policy if exists resources_owner_manage on public.clinic_resources;
drop policy if exists resources_member_read_v6_2 on public.clinic_resources;
create policy resources_member_read_v6_2 on public.clinic_resources
for select to authenticated
using (public.current_clinic_role(clinic_id) is not null);

drop policy if exists resources_clinical_manage_v6_2 on public.clinic_resources;
create policy resources_clinical_manage_v6_2 on public.clinic_resources
for all to authenticated
using (public.current_clinic_role(clinic_id) in ('owner','dietitian'))
with check (public.current_clinic_role(clinic_id) in ('owner','dietitian'));

-- Direct booking-table management remains staff-only. Clients use security-definer RPCs below.
drop policy if exists resource_bookings_staff on public.resource_bookings;
drop policy if exists resource_bookings_staff_v6_2 on public.resource_bookings;
create policy resource_bookings_staff_v6_2 on public.resource_bookings
for all to authenticated
using (public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary'))
with check (
  public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary')
  and (client_id is null or exists(
    select 1 from public.client_profiles cp where cp.id=client_id and cp.clinic_id=clinic_id and cp.is_active=true
  ))
);

create or replace function public.get_resource_schedule_v6_2(
  p_clinic_id uuid,
  p_start timestamptz,
  p_end timestamptz
) returns table(
  booking_id uuid,
  resource_id uuid,
  resource_name text,
  resource_type text,
  client_id uuid,
  client_name text,
  client_email text,
  client_phone text,
  starts_at timestamptz,
  ends_at timestamptz,
  status text,
  note text,
  is_mine boolean
)
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_role public.clinic_role;
  v_client_id uuid;
begin
  v_role:=public.current_clinic_role(p_clinic_id);
  if v_role is null then
    raise exception 'Clinic access required';
  end if;

  v_client_id:=public.current_client_id(p_clinic_id);

  return query
  select
    case when v_role in ('owner','dietitian','secretary') or rb.client_id=v_client_id then rb.id else null end,
    rb.resource_id,
    cr.name,
    cr.resource_type,
    case when v_role in ('owner','dietitian','secretary') or rb.client_id=v_client_id then rb.client_id else null end,
    case when v_role in ('owner','dietitian','secretary') or rb.client_id=v_client_id then cp.full_name else null end,
    case when v_role in ('owner','dietitian','secretary') or rb.client_id=v_client_id then p.email else null end,
    case when v_role in ('owner','dietitian','secretary') or rb.client_id=v_client_id then p.phone else null end,
    rb.starts_at,
    rb.ends_at,
    rb.status,
    case when v_role in ('owner','dietitian','secretary') or rb.client_id=v_client_id then rb.note else null end,
    rb.client_id=v_client_id
  from public.resource_bookings rb
  join public.clinic_resources cr on cr.id=rb.resource_id
  left join public.client_profiles cp on cp.id=rb.client_id
  left join public.profiles p on p.id=cp.user_id
  where rb.clinic_id=p_clinic_id
    and rb.status<>'cancelled'
    and rb.starts_at<p_end
    and rb.ends_at>p_start
  order by rb.starts_at;
end;
$$;

create or replace function public.create_client_resource_booking_v6_2(
  p_clinic_id uuid,
  p_resource_id uuid,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_note text default null
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_role public.clinic_role;
  v_client_id uuid;
  v_resource public.clinic_resources%rowtype;
  v_booking_id uuid;
  v_timezone text;
begin
  v_role:=public.current_clinic_role(p_clinic_id);
  if v_role<>'client' then
    raise exception 'Client access required';
  end if;

  v_client_id:=public.current_client_id(p_clinic_id);
  if v_client_id is null then
    raise exception 'Danışan profili bulunamadı';
  end if;

  select * into v_resource
  from public.clinic_resources
  where id=p_resource_id and clinic_id=p_clinic_id and is_active=true and client_bookable=true;

  select timezone into v_timezone from public.clinics where id=p_clinic_id;

  if not found then
    raise exception 'Bu cihaz danışan rezervasyonuna açık değil';
  end if;

  if p_starts_at<=now() then
    raise exception 'Geçmiş bir saate rezervasyon yapılamaz';
  end if;
  if p_ends_at<=p_starts_at then
    raise exception 'Bitiş saati başlangıçtan sonra olmalıdır';
  end if;
  if extract(epoch from (p_ends_at-p_starts_at))/60 > 240 then
    raise exception 'Bir cihaz rezervasyonu en fazla 4 saat olabilir';
  end if;
  if (p_starts_at at time zone coalesce(v_timezone,'Europe/Istanbul'))::time < v_resource.booking_start_time
     or (p_ends_at at time zone coalesce(v_timezone,'Europe/Istanbul'))::time > v_resource.booking_end_time then
    raise exception 'Seçilen saat cihazın rezervasyon saatleri dışındadır';
  end if;

  insert into public.resource_bookings(
    clinic_id,resource_id,client_id,starts_at,ends_at,status,note,created_by
  ) values(
    p_clinic_id,p_resource_id,v_client_id,p_starts_at,p_ends_at,'pending',nullif(trim(coalesce(p_note,'')),''),auth.uid()
  ) returning id into v_booking_id;

  return v_booking_id;
exception
  when exclusion_violation then
    raise exception 'Bu cihaz seçilen saatte dolu';
end;
$$;

create or replace function public.cancel_client_resource_booking_v6_2(
  p_booking_id uuid
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_booking public.resource_bookings%rowtype;
begin
  select * into v_booking from public.resource_bookings where id=p_booking_id;
  if not found then raise exception 'Rezervasyon bulunamadı'; end if;
  if v_booking.client_id<>public.current_client_id(v_booking.clinic_id) then
    raise exception 'Bu rezervasyonu iptal etme yetkiniz yok';
  end if;
  if v_booking.starts_at<=now() then
    raise exception 'Başlamış veya geçmiş rezervasyon iptal edilemez';
  end if;
  if v_booking.status not in ('pending','confirmed') then
    raise exception 'Bu rezervasyon iptal edilemez';
  end if;

  update public.resource_bookings
  set status='cancelled',updated_at=now()
  where id=p_booking_id;
end;
$$;

create or replace function public.set_resource_booking_status_v6_2(
  p_booking_id uuid,
  p_status text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_booking public.resource_bookings%rowtype;
begin
  if p_status not in ('pending','confirmed','completed','cancelled') then
    raise exception 'Geçersiz rezervasyon durumu';
  end if;
  select * into v_booking from public.resource_bookings where id=p_booking_id;
  if not found then raise exception 'Rezervasyon bulunamadı'; end if;
  if public.current_clinic_role(v_booking.clinic_id) not in ('owner','dietitian','secretary') then
    raise exception 'Yetkiniz yok';
  end if;
  update public.resource_bookings set status=p_status,updated_at=now() where id=p_booking_id;
end;
$$;

create or replace function public.archive_clinic_resource_v6_2(
  p_resource_id uuid
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_clinic uuid;
begin
  select clinic_id into v_clinic from public.clinic_resources where id=p_resource_id;
  if v_clinic is null then raise exception 'Cihaz bulunamadı'; end if;
  if public.current_clinic_role(v_clinic) not in ('owner','dietitian') then
    raise exception 'Yetkiniz yok';
  end if;

  if exists(
    select 1 from public.resource_bookings
    where resource_id=p_resource_id and status in ('pending','confirmed') and ends_at>now()
  ) then
    raise exception 'Yaklaşan rezervasyonları bulunan cihaz silinemez. Önce rezervasyonları iptal edin';
  end if;

  update public.clinic_resources set is_active=false where id=p_resource_id;
end;
$$;

create or replace function public.notify_resource_booking_v6_2()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_resource_name text;
  v_client_user uuid;
  v_client_name text;
  v_staff record;
  v_title text;
  v_body text;
begin
  select name into v_resource_name from public.clinic_resources where id=new.resource_id;
  select cp.user_id,cp.full_name into v_client_user,v_client_name from public.client_profiles cp where cp.id=new.client_id;

  if tg_op='INSERT' and new.status='pending' and new.client_id is not null then
    for v_staff in
      select user_id from public.clinic_memberships
      where clinic_id=new.clinic_id and role in ('owner','dietitian','secretary') and is_active=true
    loop
      perform public.create_app_notification_v5(
        new.clinic_id,v_staff.user_id,'Yeni cihaz randevu talebi',
        coalesce(v_client_name,'Danışan')||' • '||coalesce(v_resource_name,'Cihaz')||' • '||to_char(new.starts_at,'DD.MM.YYYY HH24:MI'),
        'resource_booking','resources',jsonb_build_object('booking_id',new.id,'resource_id',new.resource_id),
        'resource_booking:'||new.id::text||':staff:pending:'||v_staff.user_id::text
      );
    end loop;
  end if;

  if v_client_user is not null and (tg_op='INSERT' or old.status is distinct from new.status) then
    v_title:=case new.status
      when 'pending' then 'Cihaz randevu talebiniz alındı'
      when 'confirmed' then 'Cihaz randevunuz onaylandı'
      when 'completed' then 'Cihaz randevunuz tamamlandı'
      when 'cancelled' then 'Cihaz randevunuz iptal edildi'
      else 'Cihaz randevunuz güncellendi' end;
    v_body:=coalesce(v_resource_name,'Cihaz')||' • '||to_char(new.starts_at,'DD.MM.YYYY HH24:MI');
    perform public.create_app_notification_v5(
      new.clinic_id,v_client_user,v_title,v_body,'resource_booking','resources',
      jsonb_build_object('booking_id',new.id,'resource_id',new.resource_id,'status',new.status),
      'resource_booking:'||new.id::text||':client:'||new.status
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_resource_booking_v6_2 on public.resource_bookings;
create trigger trg_notify_resource_booking_v6_2
after insert or update of status on public.resource_bookings
for each row execute function public.notify_resource_booking_v6_2();

grant execute on function public.get_resource_schedule_v6_2(uuid,timestamptz,timestamptz) to authenticated;
grant execute on function public.create_client_resource_booking_v6_2(uuid,uuid,timestamptz,timestamptz,text) to authenticated;
grant execute on function public.cancel_client_resource_booking_v6_2(uuid) to authenticated;
grant execute on function public.set_resource_booking_status_v6_2(uuid,text) to authenticated;
grant execute on function public.archive_clinic_resource_v6_2(uuid) to authenticated;

commit;
