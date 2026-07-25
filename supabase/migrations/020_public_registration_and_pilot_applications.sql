begin;

create table if not exists public.pilot_applications (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  email text not null,
  phone text,
  applicant_type text not null default 'clinic_owner'
    check (applicant_type in ('clinic_owner','dietitian','clinic_team','other')),
  clinic_name text,
  city text,
  team_size integer not null default 1 check (team_size between 1 and 1000),
  active_client_count integer not null default 0 check (active_client_count between 0 and 1000000),
  uses_devices boolean not null default false,
  message text,
  status text not null default 'new'
    check (status in ('new','contacted','approved','waitlist','rejected','closed')),
  admin_note text,
  reviewed_by_email text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists pilot_applications_status_created_idx
  on public.pilot_applications(status, created_at desc);
create index if not exists pilot_applications_email_idx
  on public.pilot_applications(lower(email));

alter table public.pilot_applications enable row level security;

-- Başvurular yalnızca sunucu tarafındaki service-role API ile yazılır ve okunur.
-- Anon/authenticated kullanıcılara doğrudan tablo yetkisi verilmez.
revoke all on table public.pilot_applications from anon, authenticated;

commit;
