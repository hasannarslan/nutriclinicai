# v7.0 Pilot SaaS Edition

## Ürün değişikliği

NutriClinic AI artık tek kliniğe bağlı bir panel değil; davetle oluşturulan bağımsız klinik workspace’leri olan pilot SaaS sürümüdür.

## Kritik değişiklik

Yeni kayıt olan kullanıcılar otomatik olarak mevcut kliniğe Danışan eklenmez. Kullanıcı:

- Platform pilot koduyla yeni klinik oluşturur veya
- Klinik davet koduyla mevcut kliniğe katılır.

## Mevcut kurulum

`019_saas_pilot_multi_tenant.sql` bir kez çalıştırılmalıdır.

## Fresh kurulum

`supabase/baseline/production_baseline_v7.sql`

## Otomatik ücretlendirme

Bu sürüm ücretsiz/davetli pilot operasyonuna hazırdır. Gerçek kartla abonelik checkout’u henüz sağlayıcıya bağlanmamıştır; plan ve subscription modeli hazırdır.

## Stabil SaaS davranışı

- Süresi dolan veya duraklatılan klinik paneli yazma kullanımına kapatılır; veriler korunur.
- Yeni pilot klinik oluşturulurken temel hizmetler, anamnez formu ve onam şablonları otomatik hazırlanır.
- Pilot sonunda Platform Admin üzerinden manuel ücretli plan aktivasyonu yapılabilir.
