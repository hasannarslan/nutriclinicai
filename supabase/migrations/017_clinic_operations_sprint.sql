-- NutriClinic AI v6.0
-- Packages/sessions, clinic resources, intake & consent, document center,
-- private messaging, adherence/tasks, and PWA push subscription infrastructure.
-- Run once after migrations 001-016.

begin;

create extension if not exists "btree_gist";

create or replace function public.can_access_client_v6(
  p_client_id uuid,
  p_allow_secretary boolean default false
) returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists (
    select 1
    from public.client_profiles c
    join public.clinic_memberships m
      on m.clinic_id=c.clinic_id and m.user_id=auth.uid() and m.is_active=true
    left join public.dietitian_profiles d on d.id=c.assigned_dietitian_id
    where c.id=p_client_id
      and c.is_active=true
      and (
        c.user_id=auth.uid()
        or m.role='owner'
        or (p_allow_secretary and m.role='secretary')
        or (m.role='dietitian' and d.user_id=auth.uid())
      )
  );
$$;

grant execute on function public.can_access_client_v6(uuid,boolean) to authenticated;

-- SERVICE CATALOG, PACKAGES AND SESSION USAGE
create table if not exists public.service_catalog (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  name text not null,
  category text not null default 'other' check (category in ('consultation','meal_plan','measurement','bodyshape','g5','device','other')),
  description text,
  default_quantity numeric(8,2) not null default 1 check (default_quantity>0),
  default_unit_price numeric(12,2) not null default 0 check (default_unit_price>=0),
  is_active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(clinic_id,name)
);

create table if not exists public.client_packages (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  payment_id uuid references public.payments(id) on delete set null,
  name text not null,
  status text not null default 'active' check (status in ('draft','active','paused','completed','cancelled','expired')),
  starts_on date not null default current_date,
  ends_on date,
  total_price numeric(12,2) not null default 0 check (total_price>=0),
  currency text not null default 'TRY',
  notes text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_on is null or ends_on>=starts_on)
);
create index if not exists client_packages_client_idx on public.client_packages(client_id,created_at desc);

create table if not exists public.client_package_items (
  id uuid primary key default gen_random_uuid(),
  package_id uuid not null references public.client_packages(id) on delete cascade,
  service_id uuid references public.service_catalog(id) on delete set null,
  service_name text not null,
  allocated_quantity numeric(8,2) not null check (allocated_quantity>0),
  used_quantity numeric(8,2) not null default 0 check (used_quantity>=0),
  unit_price numeric(12,2) not null default 0 check (unit_price>=0),
  created_at timestamptz not null default now(),
  check (used_quantity<=allocated_quantity)
);
create index if not exists client_package_items_package_idx on public.client_package_items(package_id);

create table if not exists public.package_usage (
  id uuid primary key default gen_random_uuid(),
  package_item_id uuid not null references public.client_package_items(id) on delete cascade,
  quantity numeric(8,2) not null default 1 check (quantity>0),
  appointment_id uuid references public.appointments(id) on delete set null,
  used_at timestamptz not null default now(),
  performed_by uuid references public.profiles(id) on delete set null,
  note text
);
create index if not exists package_usage_item_idx on public.package_usage(package_item_id,used_at desc);

-- CLINIC DEVICES / ROOMS
create table if not exists public.clinic_resources (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  name text not null,
  resource_type text not null default 'device' check (resource_type in ('device','room','equipment','other')),
  description text,
  capacity integer not null default 1 check (capacity between 1 and 100),
  is_active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(clinic_id,name)
);

create table if not exists public.resource_bookings (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  resource_id uuid not null references public.clinic_resources(id) on delete cascade,
  client_id uuid references public.client_profiles(id) on delete set null,
  appointment_id uuid references public.appointments(id) on delete set null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'confirmed' check (status in ('pending','confirmed','completed','cancelled')),
  note text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at>starts_at),
  exclude using gist (
    resource_id with =,
    tstzrange(starts_at,ends_at,'[)') with &&
  ) where (status in ('pending','confirmed'))
);
create index if not exists resource_bookings_time_idx on public.resource_bookings(clinic_id,starts_at);

-- INTAKE / ANAMNESIS AND CONSENT
create table if not exists public.intake_templates (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  name text not null,
  description text,
  form_schema jsonb not null default '{}'::jsonb,
  version integer not null default 1,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(clinic_id,name,version)
);

create table if not exists public.intake_responses (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  template_id uuid not null references public.intake_templates(id) on delete restrict,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  answers jsonb not null default '{}'::jsonb,
  status text not null default 'draft' check (status in ('draft','submitted','reviewed')),
  submitted_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(template_id,client_id)
);

create table if not exists public.consent_templates (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  name text not null,
  body text not null,
  version integer not null default 1,
  is_required boolean not null default true,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(clinic_id,name,version)
);

create table if not exists public.client_consents (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  template_id uuid not null references public.consent_templates(id) on delete restrict,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  accepted boolean not null default false,
  signature_name text,
  template_version integer not null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  user_agent text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(template_id,client_id)
);

-- DOCUMENT CENTER
create table if not exists public.client_documents (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  category text not null default 'other' check (category in ('laboratory','report','prescription','measurement','meal_plan','consent','payment','administrative','photo','other')),
  title text not null,
  file_name text not null,
  storage_path text not null unique,
  mime_type text,
  size_bytes bigint,
  document_date date,
  notes text,
  visible_to_client boolean not null default true,
  uploaded_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);
create index if not exists client_documents_client_idx on public.client_documents(client_id,created_at desc);

-- PRIVATE CLIENT-DIETITIAN MESSAGING
create table if not exists public.direct_conversations (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  dietitian_id uuid not null references public.dietitian_profiles(id) on delete cascade,
  status text not null default 'active' check (status in ('active','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(client_id,dietitian_id)
);

create table if not exists public.direct_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.direct_conversations(id) on delete cascade,
  sender_user_id uuid not null references public.profiles(id) on delete cascade,
  body text,
  attachment_path text,
  attachment_name text,
  attachment_type text,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  check (nullif(trim(coalesce(body,'')),'') is not null or attachment_path is not null)
);
create index if not exists direct_messages_conversation_idx on public.direct_messages(conversation_id,created_at);

-- TASKS AND ADHERENCE
create table if not exists public.client_tasks (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  client_id uuid not null references public.client_profiles(id) on delete cascade,
  assigned_by uuid not null references public.profiles(id) on delete restrict,
  title text not null,
  description text,
  task_type text not null default 'habit' check (task_type in ('water','activity','meal_photo','weight','document','habit','other')),
  due_date date,
  status text not null default 'pending' check (status in ('pending','completed','skipped','cancelled')),
  points_reward integer not null default 0 check (points_reward>=0),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists client_tasks_client_idx on public.client_tasks(client_id,status,due_date);

-- PWA PUSH SUBSCRIPTIONS
create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth_key text not null,
  user_agent text,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);
create index if not exists push_subscriptions_user_idx on public.push_subscriptions(user_id);

create table if not exists public.push_delivery_logs (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.notifications(id) on delete cascade,
  subscription_id uuid not null references public.push_subscriptions(id) on delete cascade,
  status text not null default 'sent' check (status in ('sent','failed','expired')),
  error_message text,
  created_at timestamptz not null default now(),
  unique(notification_id,subscription_id)
);

-- DEFAULT SERVICE, INTAKE AND CONSENT TEMPLATES
insert into public.service_catalog(clinic_id,name,category,description,default_quantity,default_unit_price)
select c.id,x.name,x.category,x.description,x.qty,x.price
from public.clinics c
cross join (values
  ('İlk Görüşme','consultation','İlk değerlendirme ve planlama',1::numeric,0::numeric),
  ('Kontrol Görüşmesi','consultation','Kontrol ve plan güncelleme',1::numeric,0::numeric),
  ('Haftalık Menü','meal_plan','Bir haftalık kişiye özel menü',1::numeric,0::numeric),
  ('Vücut Analizi','measurement','Ayrıntılı vücut kompozisyon ölçümü',1::numeric,0::numeric),
  ('BodyShape Seansı','bodyshape','BodyShape cihaz kullanımı',1::numeric,0::numeric),
  ('G5 Seansı','g5','G5 uygulama seansı',1::numeric,0::numeric)
) as x(name,category,description,qty,price)
on conflict(clinic_id,name) do nothing;

insert into public.intake_templates(clinic_id,name,description,form_schema,version)
select c.id,'İlk Görüşme Anamnez Formu','Danışanın sağlık ve yaşam öyküsünü görüşme öncesinde toplar',
  '{"sections":["health_history","medications","operations","digestion","sleep","tobacco_alcohol","activity","nutrition_history","emotional_eating","women_health","notes"]}'::jsonb,1
from public.clinics c
where not exists(select 1 from public.intake_templates t where t.clinic_id=c.id and t.name='İlk Görüşme Anamnez Formu' and t.version=1);

insert into public.consent_templates(clinic_id,name,body,version,is_required)
select c.id,x.name,x.body,1,x.required
from public.clinics c
cross join (values
  ('Aydınlatma ve Veri İşleme Onayı','Kişisel ve klinik verilerimin hizmetin yürütülmesi amacıyla işlenmesine ilişkin aydınlatma metnini okudum ve anladım.',true),
  ('Online Danışmanlık Onayı','Online görüşmenin kapsamı, sınırları ve teknik koşulları hakkında bilgilendirildim.',false),
  ('Fotoğraf ve Belge Yükleme Onayı','Öğün, ilerleme ve klinik belge görsellerinin yalnızca yetkili klinik ekibi tarafından görüntülenmesini kabul ediyorum.',false),
  ('Paket, İptal ve Randevu Koşulları','Paket kullanımı, randevu değişikliği ve iptal koşullarını okudum ve kabul ediyorum.',true)
) as x(name,body,required)
where not exists(select 1 from public.consent_templates t where t.clinic_id=c.id and t.name=x.name and t.version=1);

-- RLS
alter table public.service_catalog enable row level security;
alter table public.client_packages enable row level security;
alter table public.client_package_items enable row level security;
alter table public.package_usage enable row level security;
alter table public.clinic_resources enable row level security;
alter table public.resource_bookings enable row level security;
alter table public.intake_templates enable row level security;
alter table public.intake_responses enable row level security;
alter table public.consent_templates enable row level security;
alter table public.client_consents enable row level security;
alter table public.client_documents enable row level security;
alter table public.direct_conversations enable row level security;
alter table public.direct_messages enable row level security;
alter table public.client_tasks enable row level security;
alter table public.push_subscriptions enable row level security;
alter table public.push_delivery_logs enable row level security;

drop policy if exists service_catalog_read on public.service_catalog;
create policy service_catalog_read on public.service_catalog for select to authenticated
using (public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary'));
drop policy if exists service_catalog_manage on public.service_catalog;
create policy service_catalog_manage on public.service_catalog for all to authenticated
using (public.current_clinic_role(clinic_id)='owner')
with check (public.current_clinic_role(clinic_id)='owner');

drop policy if exists client_packages_read on public.client_packages;
create policy client_packages_read on public.client_packages for select to authenticated
using (public.can_access_client_v6(client_id,true));
drop policy if exists client_packages_manage on public.client_packages;
create policy client_packages_manage on public.client_packages for all to authenticated
using (public.current_clinic_role(clinic_id) in ('owner','secretary'))
with check (public.current_clinic_role(clinic_id) in ('owner','secretary'));

drop policy if exists package_items_read on public.client_package_items;
create policy package_items_read on public.client_package_items for select to authenticated
using (exists(select 1 from public.client_packages p where p.id=package_id and public.can_access_client_v6(p.client_id,true)));
drop policy if exists package_items_manage on public.client_package_items;
create policy package_items_manage on public.client_package_items for all to authenticated
using (exists(select 1 from public.client_packages p where p.id=package_id and public.current_clinic_role(p.clinic_id) in ('owner','secretary')))
with check (exists(select 1 from public.client_packages p where p.id=package_id and public.current_clinic_role(p.clinic_id) in ('owner','secretary')));

drop policy if exists package_usage_read on public.package_usage;
create policy package_usage_read on public.package_usage for select to authenticated
using (exists(select 1 from public.client_package_items i join public.client_packages p on p.id=i.package_id where i.id=package_item_id and public.can_access_client_v6(p.client_id,true)));

drop policy if exists resources_staff_read on public.clinic_resources;
create policy resources_staff_read on public.clinic_resources for select to authenticated
using (public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary'));
drop policy if exists resources_owner_manage on public.clinic_resources;
create policy resources_owner_manage on public.clinic_resources for all to authenticated
using (public.current_clinic_role(clinic_id)='owner')
with check (public.current_clinic_role(clinic_id)='owner');

drop policy if exists resource_bookings_staff on public.resource_bookings;
create policy resource_bookings_staff on public.resource_bookings for all to authenticated
using (public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary'))
with check (public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary'));

drop policy if exists intake_templates_read on public.intake_templates;
create policy intake_templates_read on public.intake_templates for select to authenticated
using (public.current_clinic_role(clinic_id) is not null);
drop policy if exists intake_templates_owner on public.intake_templates;
create policy intake_templates_owner on public.intake_templates for all to authenticated
using (public.current_clinic_role(clinic_id)='owner')
with check (public.current_clinic_role(clinic_id)='owner');

drop policy if exists intake_responses_read on public.intake_responses;
create policy intake_responses_read on public.intake_responses for select to authenticated
using (public.can_access_client_v6(client_id,false));
drop policy if exists intake_responses_client_insert on public.intake_responses;
create policy intake_responses_client_insert on public.intake_responses for insert to authenticated
with check (client_id=public.current_client_id(clinic_id));
drop policy if exists intake_responses_client_update on public.intake_responses;
create policy intake_responses_client_update on public.intake_responses for update to authenticated
using (client_id=public.current_client_id(clinic_id) or public.can_access_client_v6(client_id,false))
with check (client_id=public.current_client_id(clinic_id) or public.can_access_client_v6(client_id,false));

drop policy if exists consent_templates_read on public.consent_templates;
create policy consent_templates_read on public.consent_templates for select to authenticated
using (public.current_clinic_role(clinic_id) is not null);
drop policy if exists consent_templates_owner on public.consent_templates;
create policy consent_templates_owner on public.consent_templates for all to authenticated
using (public.current_clinic_role(clinic_id)='owner')
with check (public.current_clinic_role(clinic_id)='owner');

drop policy if exists client_consents_read on public.client_consents;
create policy client_consents_read on public.client_consents for select to authenticated
using (public.can_access_client_v6(client_id,false));
drop policy if exists client_consents_client_write on public.client_consents;
create policy client_consents_client_write on public.client_consents for insert to authenticated
with check (client_id=public.current_client_id(clinic_id));
drop policy if exists client_consents_client_update on public.client_consents;
create policy client_consents_client_update on public.client_consents for update to authenticated
using (client_id=public.current_client_id(clinic_id))
with check (client_id=public.current_client_id(clinic_id));

drop policy if exists client_documents_read on public.client_documents;
create policy client_documents_read on public.client_documents for select to authenticated
using (
  (client_id=public.current_client_id(clinic_id) and visible_to_client)
  or public.can_access_client_v6(client_id,false)
  or (public.current_clinic_role(clinic_id)='secretary' and category in ('payment','administrative'))
);
drop policy if exists client_documents_insert on public.client_documents;
create policy client_documents_insert on public.client_documents for insert to authenticated
with check (
  uploaded_by=auth.uid()
  and (
    client_id=public.current_client_id(clinic_id)
    or public.can_access_client_v6(client_id,false)
    or (public.current_clinic_role(clinic_id)='secretary' and category in ('payment','administrative'))
  )
);
drop policy if exists client_documents_delete on public.client_documents;
create policy client_documents_delete on public.client_documents for delete to authenticated
using (uploaded_by=auth.uid() or public.current_clinic_role(clinic_id)='owner');

drop policy if exists conversations_read on public.direct_conversations;
create policy conversations_read on public.direct_conversations for select to authenticated
using (
  exists(select 1 from public.client_profiles c where c.id=client_id and c.user_id=auth.uid())
  or exists(select 1 from public.dietitian_profiles d where d.id=dietitian_id and d.user_id=auth.uid())
  or public.current_clinic_role(clinic_id)='owner'
);

drop policy if exists messages_read on public.direct_messages;
create policy messages_read on public.direct_messages for select to authenticated
using (exists(select 1 from public.direct_conversations c where c.id=conversation_id and (
  public.current_clinic_role(c.clinic_id)='owner'
  or exists(select 1 from public.client_profiles cp where cp.id=c.client_id and cp.user_id=auth.uid())
  or exists(select 1 from public.dietitian_profiles dp where dp.id=c.dietitian_id and dp.user_id=auth.uid())
)));
drop policy if exists messages_insert on public.direct_messages;
create policy messages_insert on public.direct_messages for insert to authenticated
with check (sender_user_id=auth.uid() and exists(select 1 from public.direct_conversations c where c.id=conversation_id and (
  public.current_clinic_role(c.clinic_id)='owner'
  or exists(select 1 from public.client_profiles cp where cp.id=c.client_id and cp.user_id=auth.uid())
  or exists(select 1 from public.dietitian_profiles dp where dp.id=c.dietitian_id and dp.user_id=auth.uid())
)));
drop policy if exists messages_update on public.direct_messages;
create policy messages_update on public.direct_messages for update to authenticated
using (exists(select 1 from public.direct_conversations c where c.id=conversation_id and (
  public.current_clinic_role(c.clinic_id)='owner'
  or exists(select 1 from public.client_profiles cp where cp.id=c.client_id and cp.user_id=auth.uid())
  or exists(select 1 from public.dietitian_profiles dp where dp.id=c.dietitian_id and dp.user_id=auth.uid())
)));

drop policy if exists client_tasks_read on public.client_tasks;
create policy client_tasks_read on public.client_tasks for select to authenticated
using (public.can_access_client_v6(client_id,false));
drop policy if exists client_tasks_staff_manage on public.client_tasks;
create policy client_tasks_staff_manage on public.client_tasks for all to authenticated
using (public.can_access_client_v6(client_id,false) and public.current_clinic_role(clinic_id) in ('owner','dietitian'))
with check (public.can_access_client_v6(client_id,false) and public.current_clinic_role(clinic_id) in ('owner','dietitian'));

drop policy if exists push_subscriptions_own on public.push_subscriptions;
create policy push_subscriptions_own on public.push_subscriptions for all to authenticated
using (user_id=auth.uid()) with check (user_id=auth.uid());

drop policy if exists push_delivery_logs_own_read on public.push_delivery_logs;
create policy push_delivery_logs_own_read on public.push_delivery_logs for select to authenticated
using (exists(select 1 from public.push_subscriptions s where s.id=subscription_id and s.user_id=auth.uid()));

-- STORAGE BUCKETS
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('client-documents','client-documents',false,15728640,array['application/pdf','image/jpeg','image/png','image/webp','application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict(id) do update set public=false,file_size_limit=15728640,allowed_mime_types=excluded.allowed_mime_types;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('direct-message-media','direct-message-media',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf','audio/mpeg','audio/mp4','audio/webm'])
on conflict(id) do update set public=false,file_size_limit=10485760,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists client_documents_storage_insert on storage.objects;
create policy client_documents_storage_insert on storage.objects for insert to authenticated
with check (bucket_id='client-documents' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists client_documents_storage_read on storage.objects;
create policy client_documents_storage_read on storage.objects for select to authenticated
using (bucket_id='client-documents' and exists(select 1 from public.client_documents d where d.storage_path=name and (
  (d.client_id=public.current_client_id(d.clinic_id) and d.visible_to_client)
  or public.can_access_client_v6(d.client_id,false)
  or (public.current_clinic_role(d.clinic_id)='secretary' and d.category in ('payment','administrative'))
)));
drop policy if exists client_documents_storage_delete on storage.objects;
create policy client_documents_storage_delete on storage.objects for delete to authenticated
using (bucket_id='client-documents' and ((storage.foldername(name))[1]=auth.uid()::text or exists(select 1 from public.client_documents d where d.storage_path=name and public.current_clinic_role(d.clinic_id)='owner')));

drop policy if exists direct_message_media_insert on storage.objects;
create policy direct_message_media_insert on storage.objects for insert to authenticated
with check (bucket_id='direct-message-media' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists direct_message_media_read on storage.objects;
create policy direct_message_media_read on storage.objects for select to authenticated
using (bucket_id='direct-message-media' and exists(select 1 from public.direct_messages m join public.direct_conversations c on c.id=m.conversation_id where m.attachment_path=name and (
  public.current_clinic_role(c.clinic_id)='owner'
  or exists(select 1 from public.client_profiles cp where cp.id=c.client_id and cp.user_id=auth.uid())
  or exists(select 1 from public.dietitian_profiles dp where dp.id=c.dietitian_id and dp.user_id=auth.uid())
)));

-- ATOMIC PACKAGE USAGE
create or replace function public.consume_package_item_v6(
  p_package_item_id uuid,
  p_quantity numeric default 1,
  p_appointment_id uuid default null,
  p_note text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_item public.client_package_items%rowtype;
  v_package public.client_packages%rowtype;
  v_role public.clinic_role;
  v_client_user uuid;
  v_remaining numeric;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_quantity<=0 then raise exception 'Quantity must be positive'; end if;

  select * into v_item from public.client_package_items where id=p_package_item_id for update;
  if v_item.id is null then raise exception 'Package item not found'; end if;
  select * into v_package from public.client_packages where id=v_item.package_id for update;
  v_role:=public.current_clinic_role(v_package.clinic_id);
  if v_role is null or v_role not in ('owner','dietitian','secretary') then raise exception 'Staff access required'; end if;
  if v_role='dietitian' and not public.can_access_client_v6(v_package.client_id,false) then raise exception 'Client access denied'; end if;
  if v_item.used_quantity+p_quantity>v_item.allocated_quantity then raise exception 'Insufficient remaining sessions'; end if;

  update public.client_package_items set used_quantity=used_quantity+p_quantity where id=v_item.id;
  insert into public.package_usage(package_item_id,quantity,appointment_id,performed_by,note)
  values(v_item.id,p_quantity,p_appointment_id,auth.uid(),nullif(trim(coalesce(p_note,'')),''));

  v_remaining:=v_item.allocated_quantity-(v_item.used_quantity+p_quantity);
  select user_id into v_client_user from public.client_profiles where id=v_package.client_id;
  if v_client_user is not null then
    insert into public.notifications(clinic_id,recipient_user_id,title,body,category,metadata)
    values(v_package.clinic_id,v_client_user,'Paket kullanımınız güncellendi',v_item.service_name||' için kalan kullanım: '||v_remaining::text,'package',jsonb_build_object('view','packages','package_id',v_package.id));
  end if;

  if not exists(select 1 from public.client_package_items i where i.package_id=v_package.id and i.used_quantity<i.allocated_quantity) then
    update public.client_packages set status='completed',updated_at=now() where id=v_package.id;
  end if;

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values(v_package.clinic_id,auth.uid(),'consume_package_item','client_package_item',v_item.id::text,jsonb_build_object('quantity',p_quantity,'remaining',v_remaining,'client_id',v_package.client_id));
  return jsonb_build_object('remaining',v_remaining,'package_id',v_package.id,'service_name',v_item.service_name);
end;
$$;
grant execute on function public.consume_package_item_v6(uuid,numeric,uuid,text) to authenticated;

create or replace function public.ensure_direct_conversation_v6(p_client_id uuid)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_client public.client_profiles%rowtype;
  v_dietitian uuid;
  v_conversation uuid;
  v_role public.clinic_role;
begin
  select * into v_client from public.client_profiles where id=p_client_id and is_active=true;
  if v_client.id is null then raise exception 'Client not found'; end if;
  v_role:=public.current_clinic_role(v_client.clinic_id);
  if not public.can_access_client_v6(p_client_id,false) then raise exception 'Access denied'; end if;
  v_dietitian:=v_client.assigned_dietitian_id;
  if v_dietitian is null then raise exception 'Assigned dietitian not found'; end if;

  insert into public.direct_conversations(clinic_id,client_id,dietitian_id,status)
  values(v_client.clinic_id,p_client_id,v_dietitian,'active')
  on conflict(client_id,dietitian_id) do update set status='active',updated_at=now()
  returning id into v_conversation;
  return v_conversation;
end;
$$;
grant execute on function public.ensure_direct_conversation_v6(uuid) to authenticated;

create or replace function public.set_client_task_status_v6(p_task_id uuid,p_status text)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_task public.client_tasks%rowtype;
  v_wallet uuid;
begin
  if p_status not in ('pending','completed','skipped') then raise exception 'Invalid task status'; end if;
  select * into v_task from public.client_tasks where id=p_task_id for update;
  if v_task.id is null then raise exception 'Task not found'; end if;
  if v_task.client_id<>public.current_client_id(v_task.clinic_id) then raise exception 'Client access required'; end if;
  if v_task.status='completed' and p_status<>'completed' then raise exception 'Completed tasks cannot be reopened by client'; end if;

  update public.client_tasks
  set status=p_status,completed_at=case when p_status='completed' then now() else null end,updated_at=now()
  where id=p_task_id;

  if p_status='completed' and v_task.status<>'completed' and v_task.points_reward>0 then
    select id into v_wallet from public.loyalty_wallets where clinic_id=v_task.clinic_id and client_id=v_task.client_id for update;
    update public.loyalty_wallets set balance=balance+v_task.points_reward,updated_at=now() where id=v_wallet;
    insert into public.loyalty_transactions(wallet_id,transaction_type,points,reason,created_by)
    values(v_wallet,'earned',v_task.points_reward,'Görev tamamlandı: '||v_task.title,auth.uid());
  end if;
end;
$$;
grant execute on function public.set_client_task_status_v6(uuid,text) to authenticated;

create or replace function public.get_client_adherence_v6(p_client_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_client uuid;
  v_clinic uuid;
  v_attendance numeric:=0;
  v_meals numeric:=0;
  v_water numeric:=0;
  v_activity numeric:=0;
  v_tasks numeric:=0;
  v_total numeric:=0;
  v_completed int:=0;
  v_outcomes int:=0;
  v_meal_days int:=0;
  v_water_days int:=0;
  v_activity_days int:=0;
  v_task_total int:=0;
  v_task_done int:=0;
begin
  if p_client_id is null then
    select c.id,c.clinic_id into v_client,v_clinic from public.client_profiles c where c.user_id=auth.uid() and c.is_active=true limit 1;
  else
    select c.id,c.clinic_id into v_client,v_clinic from public.client_profiles c where c.id=p_client_id and c.is_active=true;
  end if;
  if v_client is null then raise exception 'Client not found'; end if;
  if not public.can_access_client_v6(v_client,false) then raise exception 'Access denied'; end if;

  select count(*) filter(where status='completed'),count(*) filter(where status in ('completed','cancelled','no_show'))
  into v_completed,v_outcomes from public.appointments
  where client_id=v_client and starts_at>=now()-interval '30 days';
  v_attendance:=case when v_outcomes=0 then 100 else round(100.0*v_completed/v_outcomes,1) end;

  select count(distinct consumed_on) into v_meal_days from public.meal_completions where client_id=v_client and consumed_on>=current_date-13;
  v_meals:=least(100,round(100.0*v_meal_days/14,1));

  select count(distinct log_date) into v_water_days from public.daily_water_logs where client_id=v_client and log_date>=current_date-13 and amount_ml>0;
  v_water:=least(100,round(100.0*v_water_days/14,1));

  select count(distinct activity_date) into v_activity_days from public.activity_logs where client_id=v_client and activity_date>=current_date-13;
  v_activity:=least(100,round(100.0*v_activity_days/14,1));

  select count(*),count(*) filter(where status='completed') into v_task_total,v_task_done
  from public.client_tasks where client_id=v_client and created_at>=now()-interval '30 days' and status<>'cancelled';
  v_tasks:=case when v_task_total=0 then 100 else round(100.0*v_task_done/v_task_total,1) end;

  v_total:=round(v_attendance*0.30+v_meals*0.30+v_water*0.15+v_activity*0.15+v_tasks*0.10,1);
  return jsonb_build_object(
    'score',v_total,
    'risk',case when v_total>=80 then 'low' when v_total>=55 then 'medium' else 'high' end,
    'attendance',v_attendance,
    'meal_tracking',v_meals,
    'water_tracking',v_water,
    'activity_tracking',v_activity,
    'tasks',v_tasks,
    'period_days',30
  );
end;
$$;
grant execute on function public.get_client_adherence_v6(uuid) to authenticated;

-- Automatic in-app notifications for new operational records.
create or replace function public.notify_package_created_v6()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_user uuid;
begin
  select user_id into v_user from public.client_profiles where id=new.client_id;
  if v_user is not null then
    insert into public.notifications(clinic_id,recipient_user_id,title,body,category,action_view,metadata)
    values(new.clinic_id,v_user,'Yeni hizmet paketi tanımlandı',new.name||' paketi hesabınıza eklendi.','package','packages',jsonb_build_object('package_id',new.id));
  end if;
  return new;
end;
$$;
drop trigger if exists trg_notify_package_created_v6 on public.client_packages;
create trigger trg_notify_package_created_v6 after insert on public.client_packages
for each row execute function public.notify_package_created_v6();

create or replace function public.notify_task_created_v6()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_user uuid;
begin
  select user_id into v_user from public.client_profiles where id=new.client_id;
  if v_user is not null then
    insert into public.notifications(clinic_id,recipient_user_id,title,body,category,action_view,metadata)
    values(new.clinic_id,v_user,'Yeni takip göreviniz var',new.title,'task','followup',jsonb_build_object('task_id',new.id));
  end if;
  return new;
end;
$$;
drop trigger if exists trg_notify_task_created_v6 on public.client_tasks;
create trigger trg_notify_task_created_v6 after insert on public.client_tasks
for each row execute function public.notify_task_created_v6();

create or replace function public.notify_direct_message_v6()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_conversation public.direct_conversations%rowtype;
  v_client_user uuid;
  v_dietitian_user uuid;
  v_recipient uuid;
  v_sender_name text;
begin
  select * into v_conversation from public.direct_conversations where id=new.conversation_id;
  select user_id into v_client_user from public.client_profiles where id=v_conversation.client_id;
  select user_id into v_dietitian_user from public.dietitian_profiles where id=v_conversation.dietitian_id;
  v_recipient:=case when new.sender_user_id=v_client_user then v_dietitian_user else v_client_user end;
  select full_name into v_sender_name from public.profiles where id=new.sender_user_id;
  if v_recipient is not null then
    insert into public.notifications(clinic_id,recipient_user_id,title,body,category,action_view,metadata)
    values(v_conversation.clinic_id,v_recipient,coalesce(v_sender_name,'NutriClinic')||' yeni mesaj gönderdi',coalesce(nullif(left(new.body,120),''),'Yeni bir dosya gönderildi.'),'message','messages',jsonb_build_object('conversation_id',new.conversation_id));
  end if;
  return new;
end;
$$;
drop trigger if exists trg_notify_direct_message_v6 on public.direct_messages;
create trigger trg_notify_direct_message_v6 after insert on public.direct_messages
for each row execute function public.notify_direct_message_v6();

-- Realtime messaging and task updates.
do $$
begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='direct_messages') then
    alter publication supabase_realtime add table public.direct_messages;
  end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='client_tasks') then
    alter publication supabase_realtime add table public.client_tasks;
  end if;
exception when undefined_object then null;
end $$;

commit;
