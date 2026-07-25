-- NutriClinic AI v2.1
-- Registered users have one active clinic role. Only users whose active role is
-- "client" may appear as active danışan records. Historical clinical data is
-- preserved by deactivating, rather than deleting, the linked client profile.

begin;

create or replace function public.sync_client_profile_with_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.client_profiles
  set
    is_active = (new.is_active = true and new.role = 'client'),
    updated_at = now()
  where clinic_id = new.clinic_id
    and user_id = new.user_id;

  return new;
end;
$$;

drop trigger if exists sync_client_profile_role_state on public.clinic_memberships;
create trigger sync_client_profile_role_state
after insert or update of role, is_active on public.clinic_memberships
for each row
execute function public.sync_client_profile_with_membership();

-- Correct existing records, including the first account that claimed ownership.
-- Clients created manually by staff can have user_id = null and remain active.
update public.client_profiles c
set
  is_active = exists (
    select 1
    from public.clinic_memberships m
    where m.clinic_id = c.clinic_id
      and m.user_id = c.user_id
      and m.role = 'client'
      and m.is_active = true
  ),
  updated_at = now()
where c.user_id is not null;

create or replace function public.current_client_id(target_clinic uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select c.id
  from public.client_profiles c
  join public.clinic_memberships m
    on m.clinic_id = c.clinic_id
   and m.user_id = c.user_id
  where c.clinic_id = target_clinic
    and c.user_id = auth.uid()
    and c.is_active = true
    and m.role = 'client'
    and m.is_active = true
  limit 1;
$$;

create or replace function public.get_client_directory()
returns table(
  id uuid,
  user_id uuid,
  member_no text,
  full_name text,
  email text,
  phone text,
  height_cm numeric,
  target_text text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_clinic uuid;
begin
  select clinic_id into v_clinic
  from public.clinic_memberships
  where user_id = auth.uid()
    and is_active = true
    and role in ('owner','dietitian','secretary')
  limit 1;

  if v_clinic is null then
    raise exception 'Staff access required';
  end if;

  return query
  select
    c.id,
    c.user_id,
    c.member_no,
    c.full_name,
    c.email,
    c.phone,
    null::numeric,
    null::text,
    c.created_at
  from public.client_profiles c
  left join public.clinic_memberships m
    on m.clinic_id = c.clinic_id
   and m.user_id = c.user_id
  where c.clinic_id = v_clinic
    and c.is_active = true
    and (
      c.user_id is null
      or (m.role = 'client' and m.is_active = true)
    )
  order by c.full_name;
end;
$$;

-- A staff member's dormant historical client profile must not grant self-service
-- danışan access through the public API.
drop policy if exists clients_select_clinical_or_self on public.client_profiles;
create policy clients_select_clinical_or_self
on public.client_profiles
for select
using (
  public.current_clinic_role(clinic_id) in ('owner','dietitian')
  or (
    user_id = auth.uid()
    and is_active = true
    and public.current_clinic_role(clinic_id) = 'client'
  )
);

drop policy if exists clients_update_self_basic on public.client_profiles;
create policy clients_update_self_basic
on public.client_profiles
for update
using (
  user_id = auth.uid()
  and is_active = true
  and public.current_clinic_role(clinic_id) = 'client'
)
with check (
  user_id = auth.uid()
  and is_active = true
  and public.current_clinic_role(clinic_id) = 'client'
);

grant execute on function public.current_client_id(uuid) to authenticated;
grant execute on function public.get_client_directory() to authenticated;

commit;
