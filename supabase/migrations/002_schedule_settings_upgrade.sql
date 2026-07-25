-- NutriClinic AI v2 upgrade
-- Adds richer settings, weekly/daily schedule management, and positive daily availability.
-- Safe to run once after 001_production_schema.sql on an existing project.

alter table public.clinics add column if not exists address text;
alter table public.clinics add column if not exists website text;
alter table public.clinics add column if not exists booking_horizon_days int not null default 60;
alter table public.clinics add column if not exists minimum_booking_notice_hours int not null default 2;
alter table public.clinics add column if not exists cancellation_notice_hours int not null default 12;
alter table public.clinics add column if not exists allow_client_cancellation boolean not null default true;
alter table public.clinics add column if not exists allow_online_booking boolean not null default true;
alter table public.profiles add column if not exists notification_preferences jsonb not null default '{"email_notifications":true,"appointment_reminders":true,"meal_reminders":true,"weekly_summary":true}'::jsonb;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='clinics_booking_horizon_days_check') then
    alter table public.clinics add constraint clinics_booking_horizon_days_check check (booking_horizon_days between 1 and 365);
  end if;
  if not exists (select 1 from pg_constraint where conname='clinics_minimum_booking_notice_check') then
    alter table public.clinics add constraint clinics_minimum_booking_notice_check check (minimum_booking_notice_hours between 0 and 168);
  end if;
  if not exists (select 1 from pg_constraint where conname='clinics_cancellation_notice_check') then
    alter table public.clinics add constraint clinics_cancellation_notice_check check (cancellation_notice_hours between 0 and 168);
  end if;
end $$;

drop policy if exists clinics_update_owner on public.clinics;
create policy clinics_update_owner on public.clinics
for update using (public.current_clinic_role(id)='owner')
with check (public.current_clinic_role(id)='owner');

create or replace function public.validate_appointment_slot(p_dietitian_id uuid,p_starts_at timestamptz,p_ends_at timestamptz)
returns void
language plpgsql stable security definer set search_path=public
as $$
declare
  v_timezone text;
  v_weekday int;
  v_start_time time;
  v_end_time time;
  v_horizon int;
  v_min_notice int;
  v_local_date date;
  v_in_weekly boolean;
  v_in_daily_extra boolean;
begin
  select c.timezone,c.booking_horizon_days,c.minimum_booking_notice_hours
  into v_timezone,v_horizon,v_min_notice
  from public.dietitian_profiles d
  join public.clinics c on c.id=d.clinic_id
  where d.id=p_dietitian_id and d.is_bookable=true;

  if v_timezone is null then raise exception 'Dietitian is not available for booking'; end if;
  if p_starts_at < now()+make_interval(hours=>v_min_notice) then raise exception 'Selected time is too close to the current time'; end if;

  v_local_date := (p_starts_at at time zone v_timezone)::date;
  if v_local_date > ((now() at time zone v_timezone)::date + v_horizon) then
    raise exception 'Selected date is outside the booking horizon';
  end if;

  v_weekday := extract(dow from p_starts_at at time zone v_timezone)::int;
  v_start_time := (p_starts_at at time zone v_timezone)::time;
  v_end_time := (p_ends_at at time zone v_timezone)::time;

  select exists(
    select 1 from public.availability_rules
    where dietitian_id=p_dietitian_id and weekday=v_weekday and is_active=true
      and start_time<=v_start_time and end_time>=v_end_time
  ) into v_in_weekly;

  select exists(
    select 1 from public.availability_exceptions
    where dietitian_id=p_dietitian_id and is_available=true
      and starts_at<=p_starts_at and ends_at>=p_ends_at
  ) into v_in_daily_extra;

  if not v_in_weekly and not v_in_daily_extra then
    raise exception 'Selected time is outside the dietitian working hours';
  end if;

  if exists(
    select 1 from public.availability_exceptions
    where dietitian_id=p_dietitian_id and is_available=false
      and tstzrange(starts_at,ends_at,'[)') && tstzrange(p_starts_at,p_ends_at,'[)')
  ) then
    raise exception 'Selected time is unavailable';
  end if;
end;
$$;

create or replace function public.get_dietitian_day_slots(p_dietitian_id uuid,p_day date)
returns table(starts_at timestamptz,ends_at timestamptz,is_available boolean)
language plpgsql stable security definer set search_path=public
as $$
declare
  v_clinic uuid;
  v_timezone text;
  v_duration int;
  v_buffer int;
  v_horizon int;
  v_min_notice int;
begin
  select d.clinic_id,c.timezone,d.appointment_duration_minutes,d.buffer_minutes,
         c.booking_horizon_days,c.minimum_booking_notice_hours
  into v_clinic,v_timezone,v_duration,v_buffer,v_horizon,v_min_notice
  from public.dietitian_profiles d join public.clinics c on c.id=d.clinic_id
  where d.id=p_dietitian_id and d.is_bookable=true;

  if v_clinic is null or public.current_clinic_role(v_clinic) is null then raise exception 'Access denied'; end if;
  if p_day > ((now() at time zone v_timezone)::date + v_horizon) then return; end if;

  return query
  with ranges as (
    select
      (p_day::timestamp + r.start_time) at time zone v_timezone as range_start,
      (p_day::timestamp + r.end_time) at time zone v_timezone as range_end
    from public.availability_rules r
    where r.dietitian_id=p_dietitian_id
      and r.weekday=extract(dow from p_day)::int
      and r.is_active=true

    union all

    select e.starts_at,e.ends_at
    from public.availability_exceptions e
    where e.dietitian_id=p_dietitian_id
      and e.is_available=true
      and (e.starts_at at time zone v_timezone)::date=p_day
  ), generated as (
    select generate_series(
      range_start,
      range_end-make_interval(mins=>v_duration),
      make_interval(mins=>v_duration+v_buffer)
    ) as slot_start
    from ranges
    where range_end-range_start>=make_interval(mins=>v_duration)
  ), unique_slots as (
    select distinct slot_start from generated
  )
  select
    u.slot_start,
    u.slot_start+make_interval(mins=>v_duration) as slot_end,
    not exists(
      select 1 from public.appointments a
      where a.dietitian_id=p_dietitian_id and a.status in ('pending','confirmed')
        and tstzrange(a.starts_at,a.ends_at,'[)') && tstzrange(u.slot_start,u.slot_start+make_interval(mins=>v_duration),'[)')
    )
    and not exists(
      select 1 from public.availability_exceptions e
      where e.dietitian_id=p_dietitian_id and e.is_available=false
        and tstzrange(e.starts_at,e.ends_at,'[)') && tstzrange(u.slot_start,u.slot_start+make_interval(mins=>v_duration),'[)')
    )
    and u.slot_start>=now()+make_interval(hours=>v_min_notice) as available
  from unique_slots u
  order by u.slot_start;
end;
$$;

-- API table privileges required by the new screens. RLS remains authoritative.
grant update on public.clinics to authenticated;
grant insert,update,delete on public.availability_rules,public.availability_exceptions to authenticated;
