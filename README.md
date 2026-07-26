# NutriClinic AI v8.0 — Stabilized SaaS Edition

NutriClinic AI; diyetisyen, sekreter, danışan ve Platform Admin rollerini aynı çok-klinikli SaaS yapısında birleştiren klinik işletim sistemidir.

## v8.0 ile düzeltilen kritik alanlar

- Kurucu veya ücretli kliniklerde yanlış görünen pilot geri sayımı kaldırıldı.
- Abonelik yaşam döngüsü veritabanı trigger’ı ile tutarlı hale getirildi.
- Platform Admin’de pilot uzatma, ücretli onay ve durum değiştirme işlemleri güvenli kurallara bağlandı.
- Klinik detay ekranı yalnızca pilot kliniklerde ticari onay ve pilot uzatma alanlarını gösteriyor.
- Klinik durumları kullanıcıya Türkçe etiketlerle gösteriliyor.
- PWA service worker artık klinik, dashboard, admin ve API yanıtlarını önbelleğe almıyor; eski ekran gösterme riski azaltıldı.
- AI tarif, besin tahmini ve etiket tarama endpoint’lerine giriş sınırları, tenant filtresi ve yanıt doğrulama eklendi.
- E-posta HTML içeriği kaçışlanarak enjeksiyon riski azaltıldı.
- Push abonelik endpoint’i HTTPS, anahtar ve uzunluk doğrulaması yapıyor.
- Bir kullanıcının birden fazla aktif üyeliği bulunduğunda sayfaların `.single()` hatası vermesi engellendi.
- Next.js ve `eslint-config-next` aynı güvenli sürüme yükseltildi.
- Fresh kurulum için `production_baseline_v8.sql` oluşturuldu.
- `npm run audit` komutu ile kaynak, RPC, migration, baseline ve gizli anahtar kontrolleri eklendi.

## Mevcut v7.5 veritabanını güncelleme

Supabase SQL Editor içinde yalnızca şunu çalıştırın:

```text
supabase/migrations/022_stabilization_and_lifecycle_fix.sql
```

`001–021` migrationlarını yeniden çalıştırmayın.

## Sıfırdan Supabase kurulumu

Yeni bir Supabase projesinde tek dosya kullanın:

```text
supabase/baseline/production_baseline_v8.sql
```

## Ortam değişkenleri

`.env.example` dosyasını `.env.local` olarak kopyalayın. Production için en az:

```env
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=
SUPABASE_SERVICE_ROLE_KEY=
NEXT_PUBLIC_APP_URL=
PLATFORM_ADMIN_EMAILS=
CRON_SECRET=
AI_PROVIDER=xai
XAI_API_KEY=
```

Push, e-posta ve SMS kullanılıyorsa VAPID, Resend ve Twilio değişkenlerini de `.env.example` içinden ekleyin. Gizli anahtarlara `NEXT_PUBLIC_` öneki eklemeyin.

## Kurulum ve doğrulama

```bash
npm install
npm run audit
npm run lint
npm run build
npm run dev
```

## Platform Admin kurulumu

1. `PLATFORM_ADMIN_EMAILS` içine yönetici e-postasını yazın.
2. Geçici bir `PLATFORM_SETUP_TOKEN` oluşturun.
3. Deploy sonrasında `/login?platform_setup=TOKEN` adresinden yetkili e-postayla giriş yapın.
4. `/platform-admin` erişimini doğrulayın.
5. İlk kurulumdan sonra `PLATFORM_SETUP_TOKEN` değerini kaldırıp yeniden deploy edin.

## Pilot → ücretli geçiş

- Pilot klinik, panelden ücretli devam talebi oluşturur.
- Platform Admin klinik detayını, operasyon ve finans özetini inceler.
- Plan, faturalama dönemi, fiyat ve sözleşme notu girilerek onay verilir.
- Onayda klinik ve abonelik `active` olur; pilot tarihi temizlenir.
- Founder ve aktif ücretli kliniklerde pilot uzatma/onay ekranı gösterilmez.

## Sağlık kontrolü

```text
/api/health
```

Beklenen sürüm:

```json
{"version":"0.8.0","edition":"Stabilized SaaS"}
```

Detaylı denetim sonucu için `AUDIT-v8.md` dosyasına bakın.
