-- NutriClinic AI v2.3
-- Adds a clinic-editable food nutrition catalogue used for automatic macro calculations.
-- Run once after migrations 001 through 004.

begin;

create table if not exists public.food_catalog (
  id uuid primary key default gen_random_uuid(),
  clinic_id uuid references public.clinics(id) on delete cascade,
  name text not null,
  name_key text not null,
  calories_per_100g numeric(8,2) not null default 0 check (calories_per_100g >= 0),
  protein_per_100g numeric(8,2) not null default 0 check (protein_per_100g >= 0),
  carbs_per_100g numeric(8,2) not null default 0 check (carbs_per_100g >= 0),
  fat_per_100g numeric(8,2) not null default 0 check (fat_per_100g >= 0),
  default_portion_g numeric(8,2) not null default 100 check (default_portion_g > 0),
  source_label text,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (clinic_id,name_key)
);

create unique index if not exists food_catalog_global_name_key_uidx
  on public.food_catalog(name_key)
  where clinic_id is null;

create index if not exists food_catalog_clinic_active_name_idx
  on public.food_catalog(clinic_id,is_active,name);

alter table public.food_catalog enable row level security;

drop policy if exists food_catalog_select_members on public.food_catalog;
create policy food_catalog_select_members
on public.food_catalog
for select
using (
  is_active=true
  and (clinic_id is null or public.current_clinic_role(clinic_id) is not null)
);

drop policy if exists food_catalog_insert_clinical on public.food_catalog;
create policy food_catalog_insert_clinical
on public.food_catalog
for insert
with check (
  clinic_id is not null
  and public.current_clinic_role(clinic_id) in ('owner','dietitian')
  and created_by=auth.uid()
);

drop policy if exists food_catalog_update_clinical on public.food_catalog;
create policy food_catalog_update_clinical
on public.food_catalog
for update
using (
  clinic_id is not null
  and public.current_clinic_role(clinic_id) in ('owner','dietitian')
)
with check (
  clinic_id is not null
  and public.current_clinic_role(clinic_id) in ('owner','dietitian')
);

drop policy if exists food_catalog_delete_clinical on public.food_catalog;
create policy food_catalog_delete_clinical
on public.food_catalog
for delete
using (
  clinic_id is not null
  and public.current_clinic_role(clinic_id) in ('owner','dietitian')
);

grant select,insert,update,delete on public.food_catalog to authenticated;

-- Starter values are per 100 g and deliberately remain editable through a
-- clinic-specific override. Clinical teams should validate values against the
-- database and preparation method they use in practice.
insert into public.food_catalog(
  clinic_id,name,name_key,calories_per_100g,protein_per_100g,
  carbs_per_100g,fat_per_100g,default_portion_g,source_label
) values
  (null,'Yumurta','yumurta',143,12.6,0.7,9.5,50,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Süt, tam yağlı','sut tam yagli',61,3.2,4.8,3.3,200,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Yoğurt, tam yağlı','yogurt tam yagli',61,3.5,4.7,3.3,200,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Beyaz peynir','beyaz peynir',264,14.2,4.1,21.3,30,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Kaşar peyniri','kasar peyniri',404,25,1.3,33,30,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Tavuk göğsü, pişmiş','tavuk gogsu pismis',165,31,0,3.6,120,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Dana kıyma, pişmiş','dana kiyma pismis',250,26,0,15,120,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Somon, pişmiş','somon pismis',206,22,0,12,120,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Ton balığı, suda','ton baligi suda',116,26,0,1,100,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Kuru fasulye, pişmiş','kuru fasulye pismis',127,8.7,22.8,0.5,150,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Nohut, pişmiş','nohut pismis',164,8.9,27.4,2.6,150,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Yeşil mercimek, pişmiş','yesil mercimek pismis',116,9,20.1,0.4,150,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Pirinç, pişmiş','pirinc pismis',130,2.7,28.2,0.3,150,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Bulgur, pişmiş','bulgur pismis',83,3.1,18.6,0.2,150,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Yulaf ezmesi, kuru','yulaf ezmesi kuru',389,16.9,66.3,6.9,40,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Tam buğday ekmeği','tam bugday ekmegi',247,13,41,4.2,50,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Muz','muz',89,1.1,22.8,0.3,120,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Elma','elma',52,0.3,13.8,0.2,150,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Avokado','avokado',160,2,8.5,14.7,100,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Badem','badem',579,21.2,21.6,49.9,20,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Zeytinyağı','zeytinyagi',884,0,0,100,10,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Patates, haşlanmış','patates haslanmis',87,1.9,20.1,0.1,150,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Brokoli, pişmiş','brokoli pismis',35,2.4,7.2,0.4,150,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Ispanak, pişmiş','ispanak pismis',23,3,3.8,0.3,150,'Başlangıç kataloğu — klinik doğrulaması önerilir'),
  (null,'Ayran','ayran',37,2,3,1.8,200,'Başlangıç kataloğu — klinik doğrulaması önerilir')
on conflict do nothing;

commit;
