# NutriClinic AI v7.1 — Pilot SaaS Edition

NutriClinic AI; diyetisyen klinikleri için çok kullanıcılı ve çok klinikli bir klinik işletim sistemidir. v7.0, mevcut klinik özelliklerini davetli pilot programı ve tenant izolasyonlu SaaS temeliyle birleştirir.

## v7.0 ile gelen SaaS özellikleri

- Her klinik için ayrı `clinic_id` tabanlı workspace
- Yeni kullanıcıların hiçbir kliniğe otomatik eklenmemesi
- Pilot davet koduyla yeni klinik oluşturma
- Klinik Sahibinin ekip ve danışan daveti üretmesi
- Pilot, Başlangıç, Profesyonel ve Klinik plan kataloğu
- Diyetisyen, personel, aktif danışan ve AI kullanım limitleri
- Global Platform Admin paneli
- Pilot süresi uzatma, klinik duraklatma ve plan değiştirme
- Panel içinden pilot geri bildirimi
- Aylık AI kredi sayacı ve limit kontrolü
- Pilot bitiş bildirimleri, günlük lifecycle cron ve süre dolduğunda erişim kilidi
- Satış landing page’i
- Yeni kliniklere otomatik hizmet kataloğu, anamnez ve onam şablonları
- Tek dosyalık fresh Supabase baseline
- Vercel güvenlik başlıkları ve production yapılandırması

## Kurulum seçenekleri

### Mevcut v6.2 Supabase projesi

Yalnızca şunu çalıştırın:

`supabase/migrations/019_saas_pilot_multi_tenant.sql`

### Sıfırdan yeni Supabase projesi

Tek dosya:

`supabase/baseline/production_baseline_v7.sql`

Bu dosya 001–019 arasındaki güncel migrationları sırayla içerir.

## Ortam değişkenleri

`.env.example` dosyasını `.env.local` olarak kopyalayın. SaaS için kritik ek alanlar:

```env
SUPABASE_SERVICE_ROLE_KEY=
PLATFORM_ADMIN_EMAILS=admin@alanadiniz.com
PLATFORM_SETUP_TOKEN=uzun-rastgele-bir-deger
NEXT_PUBLIC_SALES_EMAIL=hello@alanadiniz.com
CRON_SECRET=uzun-rastgele-bir-deger
```

`SUPABASE_SERVICE_ROLE_KEY`, `XAI_API_KEY`, `CRON_SECRET` ve `PLATFORM_SETUP_TOKEN` değerlerine `NEXT_PUBLIC_` eklemeyin.

## İlk Platform Admin kurulumu

1. `PLATFORM_ADMIN_EMAILS` içine kendi e-posta adresinizi yazın.
2. Güçlü bir `PLATFORM_SETUP_TOKEN` oluşturun.
3. Uygulamayı deploy edin.
4. Tarayıcıda `/login?platform_setup=TOKEN` adresini açın.
5. `PLATFORM_ADMIN_EMAILS` içinde bulunan e-postayla kayıt olun.
6. E-postayı doğrulayıp aynı bağlantıdan giriş yapın.
7. `/platform-admin` açılır.
8. İlk kurulumdan sonra `PLATFORM_SETUP_TOKEN` değerini değiştirin veya kaldırın ve redeploy edin.

## 3–5 ücretsiz pilot klinik açma

1. `/platform-admin` → **Pilot davetleri**
2. Klinik adı/etiketi, hedef e-posta ve pilot gününü girin.
3. Davet bağlantısını kopyalayın.
4. Klinik sahibi bağlantıdan kayıt olur.
5. Klinik adını girerek bağımsız workspace’i oluşturur.
6. Klinik Sahibi → **Ekip ve Davetler** bölümünden diyetisyen, sekreter ve danışan davetleri üretir.

Önerilen ilk pilot: 90 gün. İlk 30 gün kurulum ve kullanım alışkanlığı, sonraki 30 gün yoğun kullanım, son 30 gün değer ölçümü ve ücretli dönüşüm görüşmesi.

## Platform Admin yetkileri

- Tüm klinikleri ve planlarını görüntüleme
- Pilot süresini 30 gün uzatma
- Klinik durumunu pilot/aktif/duraklatılmış/süresi dolmuş/iptal olarak değiştirme
- Plan değiştirme
- Pilot davet kodu oluşturma/pasifleştirme
- Kliniklerden gelen geri bildirimleri yönetme

Platform Admin normal klinik RLS yetkisiyle değil, yalnızca sunucu tarafındaki service-role route üzerinden çalışır.

## Pilot ve ücretli satış sınırı

v7.0, davetli ücretsiz pilot satış sürecine hazırdır. Abonelik planları ve harici ödeme alanları veritabanında hazırdır; ancak gerçek otomatik checkout/webhook bağlantısı şirketinizin kayıtlı ülkesi ve seçeceğiniz ödeme sağlayıcısı netleşmeden bağlanmamıştır. Pilot sonunda planı Platform Admin panelinden manuel olarak aktif plana çevirebilirsiniz.


## Pilot sonunda ücretli devam ettirme

Otomatik kartlı abonelik bağlanana kadar ilk satışları manuel tahsilatla yönetebilirsiniz:

1. Klinikle ücretli plan üzerinde anlaşın.
2. Tahsilatı/faturayı kendi şirket sürecinizden tamamlayın.
3. `/platform-admin` ekranında klinik planını değiştirin.
4. Klinik durumunu **Aktif** yapın.
5. Pilot bitiş erişim kilidi kalkar ve plan limitleri uygulanır.

Bu yöntem ilk 3–5 pilot kliniğin ücretli dönüşümünü yapmaya yeterlidir. `billing_provider`, harici müşteri ve abonelik alanları ileride otomatik checkout/webhook bağlantısı için hazır tutulmuştur.

## Komutlar

```bash
npm install
npm run dev
npm run build
npm run lint
```

## Dokümanlar

- `docs/PILOT-LAUNCH-PLAYBOOK.md`
- `docs/PILOT-CLINIC-SELECTION.md`
- `docs/SECURITY-PRODUCTION-CHECKLIST.md`
- `legal/PILOT-AGREEMENT-DRAFT.md`

## Sürüm

`0.7.0` — Pilot SaaS Edition


## v7.1 — Pilot kliniğe özel bağlantı

Platform Admin → Pilot davetleri ekranında her klinik için tam ve benzersiz kayıt bağlantısı görünür şekilde üretilir. Oluşturulan bağlantı ekranda kalır; Kopyala ve Aç düğmeleri bulunur. Aktif pilot davetleri listesinde de yalnızca token değil tam URL gösterilir. `NEXT_PUBLIC_APP_URL` Vercel alan adınız olarak tanımlanırsa bağlantılar otomatik olarak production domainiyle oluşur. Bu sürüm için yeni Supabase migrationı gerekmez.

## v7.3 — Açık kayıt ve pilot başvuru

v7.3 ile kullanıcı hesabı oluşturma herkese açılmıştır. Güvenlik nedeniyle hesap oluştururken seçilen kullanım amacı doğrudan Klinik Sahibi, Diyetisyen veya Sekreter yetkisi vermez. Gerçek klinik rolü, Klinik Sahibinin oluşturduğu davet kodu veya Platform Admin tarafından onaylanan pilot bağlantısı ile etkinleşir.

Mevcut v7.2 veritabanında yalnızca şu migration çalıştırılmalıdır:

```text
supabase/migrations/020_public_registration_and_pilot_applications.sql
```

Akış:

1. Danışan, diyetisyen veya sekreter `/login?mode=register` üzerinden hesabını oluşturur.
2. Hesap doğrulandıktan sonra giriş yapar.
3. Klinik davet kodunu `/onboarding` ekranında girer.
4. Klinik sahibi veya bağımsız diyetisyen `/pilot-application` formuyla pilot başvurusu yapar.
5. Platform Admin başvuruyu `/platform-admin` içindeki **Pilot başvuruları** sekmesinde görür ve özel pilot bağlantısı oluşturur.
