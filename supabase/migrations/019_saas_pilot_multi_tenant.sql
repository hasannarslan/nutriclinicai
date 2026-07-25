-- NutriClinic AI v7.0
-- Pilot-ready SaaS foundation: isolated clinic onboarding, invite flows,
-- subscription/plan limits, pilot feedback and platform administration data.

begin;

create extension if not exists "pgcrypto";

alter table public.clinics add column if not exists status text not null default 'active';
alter table public.clinics add column if not exists created_by uuid references public.profiles(id) on delete set null;
alter table public.clinics add column if not exists onboarding_completed_at timestamptz;
alter table public.clinics add column if not exists logo_url text;
alter table public.clinics add column if not exists accent_color text default '#155f43';
alter table public.clinics add column if not exists updated_at timestamptz not null default now();

do $$ begin
  alter table public.clinics add constraint clinics_status_v7_check
    check (status in ('active','pilot','paused','expired','cancelled'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.clinics add constraint clinics_accent_color_v7_check
    check (accent_color is null or accent_color ~ '^#[0-9A-Fa-f]{6}$');
exception when duplicate_object then null; end $$;

create table if not exists public.subscription_plans (
  slug text primary key,
  name text not null,
  description text,
  monthly_price_try numeric(12,2),
  max_dietitians int not null default 1 check (max_dietitians > 0),
  max_staff int not null default 2 check (max_staff > 0),
  max_active_clients int not null default 150 check (max_active_clients > 0),
  monthly_ai_credits int not null default 250 check (monthly_ai_credits >= 0),
  storage_gb int not null default 2 check (storage_gb >= 0),
  features jsonb not null default '{}',
  is_public boolean not null default false,
  is_active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.subscription_plans
  (slug,name,description,monthly_price_try,max_dietitians,max_staff,max_active_clients,monthly_ai_credits,storage_gb,features,is_public,sort_order)
values
  ('founder','Kurucu Klinik','NutriClinic AI kurucu kliniği için süresiz yönetim planı',0,20,50,10000,100000,200,
   '{"appointments":true,"meal_plans":true,"payments":true,"devices":true,"community":true,"ai":true,"reports":true,"white_label":true,"founder":true}'::jsonb,false,-10),
  ('pilot','Pilot Klinik','Davetli pilot klinikler için ücretsiz değerlendirme planı',0,5,10,500,3000,10,
   '{"appointments":true,"meal_plans":true,"payments":true,"devices":true,"community":true,"ai":true,"priority_feedback":true}'::jsonb,false,0),
  ('starter','Başlangıç','Bağımsız diyetisyenler için temel klinik yönetimi',1490,1,2,150,300,3,
   '{"appointments":true,"meal_plans":true,"payments":true,"ai":true}'::jsonb,true,10),
  ('professional','Profesyonel','Büyüyen diyetisyen ekipleri için gelişmiş plan',2990,3,6,500,1200,10,
   '{"appointments":true,"meal_plans":true,"payments":true,"devices":true,"community":true,"ai":true,"reports":true}'::jsonb,true,20),
  ('clinic','Klinik','Çok kullanıcılı klinikler ve şubeler için kapsamlı plan',5990,10,20,2500,5000,50,
   '{"appointments":true,"meal_plans":true,"payments":true,"devices":true,"community":true,"ai":true,"reports":true,"white_label":true}'::jsonb,true,30)
on conflict (slug) do update set
  name=excluded.name,
  description=excluded.description,
  monthly_price_try=excluded.monthly_price_try,
  max_dietitians=excluded.max_dietitians,
  max_staff=excluded.max_staff,
  max_active_clients=excluded.max_active_clients,
  monthly_ai_credits=excluded.monthly_ai_credits,
  storage_gb=excluded.storage_gb,
  features=excluded.features,
  is_public=excluded.is_public,
  is_active=true,
  sort_order=excluded.sort_order,
  updated_at=now();

create table if not exists public.clinic_subscriptions (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null unique references public.clinics(id) on delete cascade,
  plan_slug text not null references public.subscription_plans(slug),
  status text not null default 'pilot',
  pilot_started_at timestamptz,
  pilot_ends_at timestamptz,
  current_period_started_at timestamptz,
  current_period_ends_at timestamptz,
  billing_provider text,
  external_customer_id text,
  external_subscription_id text,
  cancel_at_period_end boolean not null default false,
  limits_override jsonb not null default '{}',
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$ begin
  alter table public.clinic_subscriptions add constraint clinic_subscriptions_status_v7_check
    check (status in ('pilot','trialing','active','past_due','paused','expired','cancelled'));
exception when duplicate_object then null; end $$;

alter table public.clinic_subscriptions add column if not exists last_pilot_reminder_days int;

create table if not exists public.pilot_invites (
  id uuid primary key default gen_random_uuid(),
  token text not null unique,
  label text not null,
  contact_email text,
  plan_slug text not null default 'pilot' references public.subscription_plans(slug),
  pilot_days int not null default 90 check (pilot_days between 7 and 365),
  max_uses int not null default 1 check (max_uses between 1 and 20),
  used_count int not null default 0 check (used_count >= 0),
  expires_at timestamptz not null,
  is_active boolean not null default true,
  created_by_email text,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.clinic_invites (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  token text not null unique,
  email text,
  role public.clinic_role not null default 'client',
  max_uses int not null default 1 check (max_uses between 1 and 1000),
  used_count int not null default 0 check (used_count >= 0),
  expires_at timestamptz not null,
  is_active boolean not null default true,
  invited_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.pilot_feedback (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  category text not null default 'general',
  rating smallint check (rating between 1 and 5),
  message text not null check (char_length(message) between 3 and 5000),
  page_path text,
  status text not null default 'new',
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

do $$ begin
  alter table public.pilot_feedback add constraint pilot_feedback_category_v7_check
    check (category in ('general','bug','idea','usability','support'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.pilot_feedback add constraint pilot_feedback_status_v7_check
    check (status in ('new','reviewing','planned','resolved','closed'));
exception when duplicate_object then null; end $$;

create table if not exists public.monthly_usage_counters (
  clinic_id uuid not null references public.clinics(id) on delete cascade,
  usage_month date not null,
  ai_requests int not null default 0,
  emails_sent int not null default 0,
  sms_sent int not null default 0,
  storage_bytes bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key (clinic_id,usage_month)
);

create index if not exists clinic_invites_clinic_created_v7_idx on public.clinic_invites(clinic_id,created_at desc);
create index if not exists clinic_invites_token_v7_idx on public.clinic_invites(token);
create index if not exists pilot_invites_token_v7_idx on public.pilot_invites(token);
create index if not exists pilot_feedback_clinic_created_v7_idx on public.pilot_feedback(clinic_id,created_at desc);
create index if not exists clinic_subscriptions_status_v7_idx on public.clinic_subscriptions(status,pilot_ends_at);

-- Existing installations receive the non-expiring founder plan so no current workflow is interrupted.
insert into public.clinic_subscriptions(clinic_id,plan_slug,status,metadata)
select c.id,'founder','active',jsonb_build_object('source','v7_existing_clinic_migration','founder_access',true)
from public.clinics c
where not exists(select 1 from public.clinic_subscriptions s where s.clinic_id=c.id);

update public.clinics c
set status='active',updated_at=now()
where exists(select 1 from public.clinic_subscriptions s where s.clinic_id=c.id and s.plan_slug='founder');

-- The legacy seed clinic is removed only in a completely fresh installation.
-- Existing installations keep it because they already have memberships.
delete from public.clinics
where id='00000000-0000-0000-0000-000000000001'
  and not exists(select 1 from public.clinic_memberships where clinic_id='00000000-0000-0000-0000-000000000001');

-- New Auth accounts are now neutral profiles. Clinic membership is created only
-- after a pilot or clinic invitation is redeemed.
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  v_full_name text;
  v_email text;
  v_phone text;
  v_locale text;
begin
  v_email := coalesce(nullif(new.raw_user_meta_data->>'contact_email',''),new.email);
  v_phone := coalesce(nullif(new.raw_user_meta_data->>'contact_phone',''),new.phone);
  v_full_name := coalesce(nullif(new.raw_user_meta_data->>'full_name',''),split_part(coalesce(v_email,v_phone,'Kullanıcı'),'@',1));
  v_locale := coalesce(nullif(new.raw_user_meta_data->>'preferred_locale',''),'tr');
  if v_locale not in ('tr','en','el','ru','de') then v_locale := 'tr'; end if;

  insert into public.profiles(id,full_name,email,phone,preferred_locale)
  values(new.id,v_full_name,v_email,v_phone,v_locale)
  on conflict(id) do update set
    full_name=excluded.full_name,
    email=coalesce(excluded.email,public.profiles.email),
    phone=coalesce(excluded.phone,public.profiles.phone),
    preferred_locale=excluded.preferred_locale,
    updated_at=now();

  return new;
end;
$$;

create or replace function public.get_saas_context_v7()
returns jsonb
language plpgsql stable security definer set search_path=public
as $$
declare
  v_clinic uuid;
  v_role public.clinic_role;
  v_result jsonb;
begin
  select m.clinic_id,m.role into v_clinic,v_role
  from public.clinic_memberships m
  where m.user_id=auth.uid() and m.is_active=true
  order by m.created_at limit 1;

  if v_clinic is null then return null; end if;

  select jsonb_build_object(
    'clinic_id',c.id,
    'clinic_name',c.name,
    'clinic_slug',c.slug,
    'clinic_status',c.status,
    'role',v_role,
    'plan_slug',p.slug,
    'plan_name',p.name,
    'subscription_status',s.status,
    'pilot_ends_at',s.pilot_ends_at,
    'days_remaining',case when s.pilot_ends_at is null then null else greatest(0,ceil(extract(epoch from (s.pilot_ends_at-now()))/86400.0)::int) end,
    'limits',jsonb_build_object(
      'dietitians',coalesce((s.limits_override->>'max_dietitians')::int,p.max_dietitians),
      'staff',coalesce((s.limits_override->>'max_staff')::int,p.max_staff),
      'active_clients',coalesce((s.limits_override->>'max_active_clients')::int,p.max_active_clients),
      'ai_credits',coalesce((s.limits_override->>'monthly_ai_credits')::int,p.monthly_ai_credits),
      'storage_gb',coalesce((s.limits_override->>'storage_gb')::int,p.storage_gb)
    ),
    'usage',jsonb_build_object(
      'dietitians',(select count(*) from public.clinic_memberships where clinic_id=v_clinic and is_active and role in ('owner','dietitian')),
      'staff',(select count(*) from public.clinic_memberships where clinic_id=v_clinic and is_active and role in ('owner','dietitian','secretary')),
      'active_clients',(select count(*) from public.client_profiles where clinic_id=v_clinic and is_active),
      'ai_requests',coalesce((select ai_requests from public.monthly_usage_counters where clinic_id=v_clinic and usage_month=date_trunc('month',current_date)::date),0)
    ),
    'features',p.features
  ) into v_result
  from public.clinics c
  join public.clinic_subscriptions s on s.clinic_id=c.id
  join public.subscription_plans p on p.slug=s.plan_slug
  where c.id=v_clinic;

  return v_result;
end;
$$;

-- Every newly-created tenant receives the operational starter data that
-- older clinics obtained when migration 017 originally ran.
create or replace function public.seed_new_clinic_v7(
  p_clinic_id uuid,
  p_creator uuid
)
returns void
language plpgsql security definer set search_path=public
as $$
begin
  if p_clinic_id is null then
    raise exception 'Klinik kimliği zorunludur';
  end if;

  insert into public.service_catalog(
    clinic_id,name,category,description,default_quantity,default_unit_price,created_by
  )
  select p_clinic_id,x.name,x.category,x.description,x.qty,x.price,p_creator
  from (values
    ('İlk Görüşme','consultation','İlk değerlendirme ve planlama',1::numeric,0::numeric),
    ('Kontrol Görüşmesi','consultation','Kontrol ve plan güncelleme',1::numeric,0::numeric),
    ('Haftalık Menü','meal_plan','Bir haftalık kişiye özel menü',1::numeric,0::numeric),
    ('Vücut Analizi','measurement','Ayrıntılı vücut kompozisyon ölçümü',1::numeric,0::numeric),
    ('BodyShape Seansı','bodyshape','BodyShape cihaz kullanımı',1::numeric,0::numeric),
    ('G5 Seansı','g5','G5 uygulama seansı',1::numeric,0::numeric)
  ) as x(name,category,description,qty,price)
  on conflict(clinic_id,name) do nothing;

  insert into public.intake_templates(
    clinic_id,name,description,form_schema,version,created_by
  )
  values(
    p_clinic_id,
    'İlk Görüşme Anamnez Formu',
    'Danışanın sağlık ve yaşam öyküsünü görüşme öncesinde toplar',
    '{"sections":["health_history","medications","operations","digestion","sleep","tobacco_alcohol","activity","nutrition_history","emotional_eating","women_health","notes"]}'::jsonb,
    1,
    p_creator
  )
  on conflict(clinic_id,name,version) do nothing;

  insert into public.consent_templates(
    clinic_id,name,body,version,is_required,created_by
  )
  select p_clinic_id,x.name,x.body,1,x.required,p_creator
  from (values
    ('Aydınlatma ve Veri İşleme Onayı','Kişisel ve klinik verilerimin hizmetin yürütülmesi amacıyla işlenmesine ilişkin aydınlatma metnini okudum ve anladım.',true),
    ('Online Danışmanlık Onayı','Online görüşmenin kapsamı, sınırları ve teknik koşulları hakkında bilgilendirildim.',false),
    ('Fotoğraf ve Belge Yükleme Onayı','Öğün, ilerleme ve klinik belge görsellerinin yalnızca yetkili klinik ekibi tarafından görüntülenmesini kabul ediyorum.',false),
    ('Paket, İptal ve Randevu Koşulları','Paket kullanımı, randevu değişikliği ve iptal koşullarını okudum ve kabul ediyorum.',true)
  ) as x(name,body,required)
  on conflict(clinic_id,name,version) do nothing;
end;
$$;

create or replace function public.redeem_pilot_invite_v7(
  p_token text,
  p_clinic_name text,
  p_slug text,
  p_timezone text default 'Europe/Istanbul',
  p_locale text default 'tr'
)
returns uuid
language plpgsql security definer set search_path=public
as $$
declare
  v_invite public.pilot_invites%rowtype;
  v_profile public.profiles%rowtype;
  v_clinic uuid;
  v_dietitian uuid;
  v_slug text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if exists(select 1 from public.clinic_memberships where user_id=auth.uid() and is_active) then
    raise exception 'Bu hesap zaten aktif bir kliniğe bağlı';
  end if;
  if trim(coalesce(p_clinic_name,''))='' then raise exception 'Klinik adı zorunludur'; end if;

  v_slug:=lower(trim(p_slug));
  if v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
    raise exception 'Klinik bağlantı adı yalnızca küçük harf, sayı ve tire içerebilir';
  end if;
  if exists(select 1 from public.clinics where slug=v_slug) then raise exception 'Bu klinik bağlantı adı kullanımda'; end if;

  select * into v_invite from public.pilot_invites
  where upper(token)=upper(trim(p_token)) for update;
  if v_invite.id is null then raise exception 'Pilot davet kodu bulunamadı'; end if;
  if not v_invite.is_active or v_invite.expires_at<=now() or v_invite.used_count>=v_invite.max_uses then
    raise exception 'Pilot davet kodunun süresi dolmuş veya kullanım hakkı kalmamış';
  end if;

  select * into v_profile from public.profiles where id=auth.uid();
  if v_profile.id is null then raise exception 'Kullanıcı profili bulunamadı'; end if;
  if v_invite.contact_email is not null and lower(coalesce(v_profile.email,''))<>lower(v_invite.contact_email) then
    raise exception 'Bu pilot kodu farklı bir e-posta adresine tanımlanmış';
  end if;

  insert into public.clinics(name,slug,default_locale,timezone,status,created_by,onboarding_completed_at)
  values(trim(p_clinic_name),v_slug,
    case when p_locale in ('tr','en','el','ru','de') then p_locale else 'tr' end,
    coalesce(nullif(trim(p_timezone),''),'Europe/Istanbul'),'pilot',auth.uid(),now())
  returning id into v_clinic;

  insert into public.clinic_memberships(clinic_id,user_id,role,is_active)
  values(v_clinic,auth.uid(),'owner',true);

  insert into public.dietitian_profiles(clinic_id,user_id,title,is_bookable)
  values(v_clinic,auth.uid(),'Danışman Diyetisyen',true)
  returning id into v_dietitian;
  perform public.ensure_default_availability(v_dietitian);
  perform public.seed_new_clinic_v7(v_clinic,auth.uid());

  insert into public.clinic_subscriptions(clinic_id,plan_slug,status,pilot_started_at,pilot_ends_at,metadata)
  values(v_clinic,v_invite.plan_slug,'pilot',now(),now()+make_interval(days=>v_invite.pilot_days),
    jsonb_build_object('pilot_invite_id',v_invite.id,'pilot_label',v_invite.label));

  update public.pilot_invites set used_count=used_count+1,updated_at=now(),
    is_active=case when used_count+1>=max_uses then false else is_active end
  where id=v_invite.id;

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values(v_clinic,auth.uid(),'pilot_clinic_created','clinic',v_clinic::text,
    jsonb_build_object('pilot_invite_id',v_invite.id,'pilot_days',v_invite.pilot_days,'plan_slug',v_invite.plan_slug));

  return v_clinic;
end;
$$;

create or replace function public.create_clinic_invite_v7(
  p_role public.clinic_role,
  p_email text default null,
  p_expires_days int default 14,
  p_max_uses int default 1
)
returns text
language plpgsql security definer set search_path=public
as $$
declare
  v_clinic uuid;
  v_actor_role public.clinic_role;
  v_token text;
begin
  select clinic_id,role into v_clinic,v_actor_role
  from public.clinic_memberships where user_id=auth.uid() and is_active limit 1;
  if v_clinic is null then raise exception 'Klinik üyeliği bulunamadı'; end if;
  if p_role='owner' then raise exception 'Klinik Sahibi rolü davetle verilemez'; end if;
  if v_actor_role='client' then raise exception 'Bu işlem için klinik yetkisi gerekli'; end if;
  if v_actor_role in ('dietitian','secretary') and p_role<>'client' then
    raise exception 'Diyetisyen ve Sekreter yalnızca Danışan daveti oluşturabilir';
  end if;
  if p_expires_days not between 1 and 90 then raise exception 'Geçerlilik süresi 1-90 gün olmalıdır'; end if;
  if p_max_uses not between 1 and 1000 then raise exception 'Kullanım sayısı geçersiz'; end if;

  v_token:=upper(substr(encode(gen_random_bytes(12),'hex'),1,16));
  insert into public.clinic_invites(clinic_id,token,email,role,max_uses,expires_at,invited_by)
  values(v_clinic,v_token,nullif(lower(trim(p_email)),''),p_role,p_max_uses,now()+make_interval(days=>p_expires_days),auth.uid());

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values(v_clinic,auth.uid(),'clinic_invite_created','clinic_invite',v_token,
    jsonb_build_object('role',p_role,'email',nullif(lower(trim(p_email)),''),'max_uses',p_max_uses));
  return v_token;
end;
$$;

create or replace function public.list_clinic_invites_v7()
returns table(
  id uuid, token text, email text, role public.clinic_role, max_uses int,
  used_count int, expires_at timestamptz, is_active boolean, created_at timestamptz
)
language plpgsql stable security definer set search_path=public
as $$
declare v_clinic uuid; v_role public.clinic_role;
begin
  select clinic_id,clinic_memberships.role into v_clinic,v_role
  from public.clinic_memberships where user_id=auth.uid() and is_active limit 1;
  if v_clinic is null or v_role='client' then raise exception 'Klinik personeli erişimi gerekli'; end if;
  return query
    select i.id,i.token,i.email,i.role,i.max_uses,i.used_count,i.expires_at,i.is_active,i.created_at
    from public.clinic_invites i where i.clinic_id=v_clinic order by i.created_at desc;
end;
$$;

create or replace function public.revoke_clinic_invite_v7(p_invite_id uuid)
returns void
language plpgsql security definer set search_path=public
as $$
declare v_clinic uuid; v_role public.clinic_role;
begin
  select clinic_id,role into v_clinic,v_role from public.clinic_memberships
  where user_id=auth.uid() and is_active limit 1;
  if v_clinic is null or v_role not in ('owner','dietitian','secretary') then raise exception 'Klinik personeli erişimi gerekli'; end if;
  update public.clinic_invites set is_active=false,updated_at=now()
  where id=p_invite_id and clinic_id=v_clinic;
end;
$$;

create or replace function public.accept_clinic_invite_v7(p_token text)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_invite public.clinic_invites%rowtype;
  v_profile public.profiles%rowtype;
  v_plan public.subscription_plans%rowtype;
  v_subscription public.clinic_subscriptions%rowtype;
  v_member_no text;
  v_client uuid;
  v_dietitian uuid;
  v_staff_count int;
  v_dietitian_count int;
  v_client_count int;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if exists(select 1 from public.clinic_memberships where user_id=auth.uid() and is_active) then
    raise exception 'Bu hesap zaten aktif bir kliniğe bağlı';
  end if;

  select * into v_invite from public.clinic_invites
  where upper(token)=upper(trim(p_token)) for update;
  if v_invite.id is null then raise exception 'Klinik davet kodu bulunamadı'; end if;
  if not v_invite.is_active or v_invite.expires_at<=now() or v_invite.used_count>=v_invite.max_uses then
    raise exception 'Klinik davet kodunun süresi dolmuş veya kullanım hakkı kalmamış';
  end if;

  select * into v_profile from public.profiles where id=auth.uid();
  if v_profile.id is null then raise exception 'Kullanıcı profili bulunamadı'; end if;
  if v_invite.email is not null and lower(coalesce(v_profile.email,''))<>lower(v_invite.email) then
    raise exception 'Bu davet farklı bir e-posta adresine tanımlanmış';
  end if;

  select * into v_subscription from public.clinic_subscriptions where clinic_id=v_invite.clinic_id;
  select * into v_plan from public.subscription_plans where slug=v_subscription.plan_slug;
  if v_subscription.status in ('paused','expired','cancelled') then raise exception 'Klinik hesabı yeni kullanıcı kabul etmiyor'; end if;

  select count(*) into v_staff_count from public.clinic_memberships
    where clinic_id=v_invite.clinic_id and is_active and role in ('owner','dietitian','secretary');
  select count(*) into v_dietitian_count from public.clinic_memberships
    where clinic_id=v_invite.clinic_id and is_active and role in ('owner','dietitian');
  select count(*) into v_client_count from public.client_profiles
    where clinic_id=v_invite.clinic_id and is_active;

  if v_invite.role in ('dietitian') and v_dietitian_count>=coalesce((v_subscription.limits_override->>'max_dietitians')::int,v_plan.max_dietitians) then
    raise exception 'Diyetisyen limiti dolmuş';
  end if;
  if v_invite.role in ('dietitian','secretary') and v_staff_count>=coalesce((v_subscription.limits_override->>'max_staff')::int,v_plan.max_staff) then
    raise exception 'Personel limiti dolmuş';
  end if;
  if v_invite.role='client' and v_client_count>=coalesce((v_subscription.limits_override->>'max_active_clients')::int,v_plan.max_active_clients) then
    raise exception 'Aktif danışan limiti dolmuş';
  end if;

  insert into public.clinic_memberships(clinic_id,user_id,role,is_active)
  values(v_invite.clinic_id,auth.uid(),v_invite.role,true)
  on conflict(clinic_id,user_id) do update set role=excluded.role,is_active=true,updated_at=now();

  if v_invite.role='client' then
    v_member_no:='NCA-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('public.client_member_sequence')::text,6,'0');
    insert into public.client_profiles(clinic_id,user_id,member_no,full_name,email,phone,is_active)
    values(v_invite.clinic_id,auth.uid(),v_member_no,v_profile.full_name,v_profile.email,v_profile.phone,true)
    on conflict(clinic_id,user_id) do update set
      full_name=excluded.full_name,
      email=coalesce(excluded.email,public.client_profiles.email),
      phone=coalesce(excluded.phone,public.client_profiles.phone),
      is_active=true,
      updated_at=now()
    returning id into v_client;
    insert into public.loyalty_wallets(clinic_id,client_id,balance) values(v_invite.clinic_id,v_client,0)
    on conflict(clinic_id,client_id) do nothing;
  elsif v_invite.role='dietitian' then
    insert into public.dietitian_profiles(clinic_id,user_id,title,is_bookable)
    values(v_invite.clinic_id,auth.uid(),'Diyetisyen',true)
    on conflict(clinic_id,user_id) do update set is_bookable=true
    returning id into v_dietitian;
    perform public.ensure_default_availability(v_dietitian);
  end if;

  update public.clinic_invites set used_count=used_count+1,updated_at=now(),
    is_active=case when used_count+1>=max_uses then false else is_active end
  where id=v_invite.id;

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values(v_invite.clinic_id,auth.uid(),'clinic_invite_accepted','user',auth.uid()::text,
    jsonb_build_object('invite_id',v_invite.id,'role',v_invite.role));

  return jsonb_build_object('clinic_id',v_invite.clinic_id,'role',v_invite.role);
end;
$$;

create or replace function public.submit_pilot_feedback_v7(
  p_category text,
  p_rating int,
  p_message text,
  p_page_path text default null
)
returns uuid
language plpgsql security definer set search_path=public
as $$
declare v_clinic uuid; v_id uuid;
begin
  select clinic_id into v_clinic from public.clinic_memberships
  where user_id=auth.uid() and is_active limit 1;
  if v_clinic is null then raise exception 'Klinik üyeliği bulunamadı'; end if;
  if p_category not in ('general','bug','idea','usability','support') then raise exception 'Geri bildirim kategorisi geçersiz'; end if;
  if p_rating is not null and p_rating not between 1 and 5 then raise exception 'Puan 1-5 arasında olmalıdır'; end if;
  if char_length(trim(coalesce(p_message,'')))<3 then raise exception 'Geri bildirim mesajı çok kısa'; end if;
  insert into public.pilot_feedback(clinic_id,user_id,category,rating,message,page_path)
  values(v_clinic,auth.uid(),p_category,p_rating,trim(p_message),nullif(trim(p_page_path),''))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.consume_ai_credit_v7(p_clinic_id uuid,p_units int default 1)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_plan public.subscription_plans%rowtype;
  v_subscription public.clinic_subscriptions%rowtype;
  v_limit int;
  v_current int;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_units not between 1 and 100 then raise exception 'AI kullanım birimi geçersiz'; end if;
  if public.current_clinic_role(p_clinic_id) is null then raise exception 'Klinik erişimi bulunamadı'; end if;
  select * into v_subscription from public.clinic_subscriptions where clinic_id=p_clinic_id;
  if v_subscription.id is null then raise exception 'Klinik aboneliği bulunamadı'; end if;
  if v_subscription.status not in ('pilot','trialing','active') then raise exception 'AI araçları için aktif klinik planı gerekli'; end if;
  select * into v_plan from public.subscription_plans where slug=v_subscription.plan_slug;
  v_limit:=coalesce((v_subscription.limits_override->>'monthly_ai_credits')::int,v_plan.monthly_ai_credits);

  insert into public.monthly_usage_counters(clinic_id,usage_month,ai_requests)
  values(p_clinic_id,date_trunc('month',current_date)::date,0)
  on conflict(clinic_id,usage_month) do nothing;

  select ai_requests into v_current from public.monthly_usage_counters
  where clinic_id=p_clinic_id and usage_month=date_trunc('month',current_date)::date
  for update;
  if v_current+p_units>v_limit then raise exception 'Aylık AI kullanım limitiniz doldu'; end if;

  update public.monthly_usage_counters set ai_requests=ai_requests+p_units,updated_at=now()
  where clinic_id=p_clinic_id and usage_month=date_trunc('month',current_date)::date
  returning ai_requests into v_current;
  return jsonb_build_object('used',v_current,'limit',v_limit,'remaining',greatest(0,v_limit-v_current));
end;
$$;

-- Plan limit enforcement for role promotion.
create or replace function public.set_member_role(p_user_id uuid,p_role public.clinic_role)
returns void
language plpgsql security definer set search_path=public
as $$
declare
  v_clinic uuid;
  v_current_role public.clinic_role;
  v_dietitian uuid;
  v_plan public.subscription_plans%rowtype;
  v_subscription public.clinic_subscriptions%rowtype;
  v_dietitian_limit int;
  v_staff_limit int;
  v_dietitian_count int;
  v_staff_count int;
  v_profile public.profiles%rowtype;
  v_client uuid;
  v_member_no text;
begin
  select clinic_id into v_clinic from public.clinic_memberships
  where user_id=auth.uid() and role='owner' and is_active=true limit 1;
  if v_clinic is null then raise exception 'Yalnızca Klinik Sahibi rol değiştirebilir'; end if;

  select role into v_current_role from public.clinic_memberships
  where clinic_id=v_clinic and user_id=p_user_id and is_active=true;
  if v_current_role is null then raise exception 'Kullanıcı bu kliniğin üyesi değil'; end if;

  if v_current_role='owner' and p_role<>'owner' and
     (select count(*) from public.clinic_memberships where clinic_id=v_clinic and role='owner' and is_active=true)<=1
  then raise exception 'Son Klinik Sahibi rolü düşürülemez'; end if;

  select * into v_subscription from public.clinic_subscriptions where clinic_id=v_clinic;
  select * into v_plan from public.subscription_plans where slug=v_subscription.plan_slug;
  v_dietitian_limit:=coalesce((v_subscription.limits_override->>'max_dietitians')::int,v_plan.max_dietitians);
  v_staff_limit:=coalesce((v_subscription.limits_override->>'max_staff')::int,v_plan.max_staff);
  select count(*) into v_dietitian_count from public.clinic_memberships where clinic_id=v_clinic and is_active and role in ('owner','dietitian') and user_id<>p_user_id;
  select count(*) into v_staff_count from public.clinic_memberships where clinic_id=v_clinic and is_active and role in ('owner','dietitian','secretary') and user_id<>p_user_id;
  if p_role in ('owner','dietitian') and v_dietitian_count>=v_dietitian_limit then raise exception 'Paketinizdeki Diyetisyen limiti dolmuş'; end if;
  if p_role in ('owner','dietitian','secretary') and v_staff_count>=v_staff_limit then raise exception 'Paketinizdeki personel limiti dolmuş'; end if;

  update public.clinic_memberships set role=p_role,updated_at=now()
  where clinic_id=v_clinic and user_id=p_user_id;

  if p_role in ('owner','dietitian') then
    insert into public.dietitian_profiles(clinic_id,user_id,title,is_bookable)
    values(v_clinic,p_user_id,'Danışman Diyetisyen',true)
    on conflict(clinic_id,user_id) do update set is_bookable=true
    returning id into v_dietitian;
    perform public.ensure_default_availability(v_dietitian);
  else
    update public.dietitian_profiles set is_bookable=false where clinic_id=v_clinic and user_id=p_user_id;
  end if;

  if p_role='client' then
    select * into v_profile from public.profiles where id=p_user_id;
    v_member_no:='NCA-'||to_char(current_date,'YYYY')||'-'||lpad(nextval('public.client_member_sequence')::text,6,'0');
    insert into public.client_profiles(clinic_id,user_id,member_no,full_name,email,phone,is_active)
    values(v_clinic,p_user_id,v_member_no,v_profile.full_name,v_profile.email,v_profile.phone,true)
    on conflict(clinic_id,user_id) do update set is_active=true,updated_at=now()
    returning id into v_client;
    insert into public.loyalty_wallets(clinic_id,client_id,balance) values(v_clinic,v_client,0)
    on conflict(clinic_id,client_id) do nothing;
  else
    update public.client_profiles set is_active=false,updated_at=now()
    where clinic_id=v_clinic and user_id=p_user_id;
  end if;

  insert into public.audit_logs(clinic_id,actor_user_id,action,target_type,target_id,metadata)
  values(v_clinic,auth.uid(),'member_role_changed','user',p_user_id::text,
    jsonb_build_object('old_role',v_current_role,'new_role',p_role,'plan_slug',v_subscription.plan_slug));
end;
$$;

alter table public.subscription_plans enable row level security;
alter table public.clinic_subscriptions enable row level security;
alter table public.pilot_invites enable row level security;
alter table public.clinic_invites enable row level security;
alter table public.pilot_feedback enable row level security;
alter table public.monthly_usage_counters enable row level security;

drop policy if exists subscription_plans_read_v7 on public.subscription_plans;
create policy subscription_plans_read_v7 on public.subscription_plans for select to authenticated using (is_active=true);

drop policy if exists clinic_subscriptions_member_read_v7 on public.clinic_subscriptions;
create policy clinic_subscriptions_member_read_v7 on public.clinic_subscriptions for select to authenticated
using (public.current_clinic_role(clinic_id) is not null);

drop policy if exists clinic_invites_staff_read_v7 on public.clinic_invites;
create policy clinic_invites_staff_read_v7 on public.clinic_invites for select to authenticated
using (public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary'));

drop policy if exists pilot_feedback_own_read_v7 on public.pilot_feedback;
create policy pilot_feedback_own_read_v7 on public.pilot_feedback for select to authenticated
using (user_id=auth.uid() or public.current_clinic_role(clinic_id)='owner');

drop policy if exists usage_counters_member_read_v7 on public.monthly_usage_counters;
create policy usage_counters_member_read_v7 on public.monthly_usage_counters for select to authenticated
using (public.current_clinic_role(clinic_id) in ('owner','dietitian','secretary'));

-- Pilot invites are intentionally unavailable through the public PostgREST API.
-- They are managed by the authenticated platform-admin server route with service role.

revoke all on function public.get_saas_context_v7() from public;
revoke all on function public.seed_new_clinic_v7(uuid,uuid) from public;
revoke all on function public.redeem_pilot_invite_v7(text,text,text,text,text) from public;
revoke all on function public.create_clinic_invite_v7(public.clinic_role,text,int,int) from public;
revoke all on function public.list_clinic_invites_v7() from public;
revoke all on function public.revoke_clinic_invite_v7(uuid) from public;
revoke all on function public.accept_clinic_invite_v7(text) from public;
revoke all on function public.submit_pilot_feedback_v7(text,int,text,text) from public;
revoke all on function public.consume_ai_credit_v7(uuid,int) from public;

grant execute on function public.get_saas_context_v7() to authenticated;
grant execute on function public.redeem_pilot_invite_v7(text,text,text,text,text) to authenticated;
grant execute on function public.create_clinic_invite_v7(public.clinic_role,text,int,int) to authenticated;
grant execute on function public.list_clinic_invites_v7() to authenticated;
grant execute on function public.revoke_clinic_invite_v7(uuid) to authenticated;
grant execute on function public.accept_clinic_invite_v7(text) to authenticated;
grant execute on function public.submit_pilot_feedback_v7(text,int,text,text) to authenticated;
grant execute on function public.consume_ai_credit_v7(uuid,int) to authenticated;

grant select on public.subscription_plans,public.clinic_subscriptions,public.clinic_invites,public.pilot_feedback,public.monthly_usage_counters to authenticated;

commit;
