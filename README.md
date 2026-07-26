# NutriClinic AI v8.1 — Localization & Platform Repair

NutriClinic AI; Klinik Sahibi, Diyetisyen, Sekreter, Danışan ve Platform Admin rollerini çok kiracılı bir SaaS yapısında birleştiren klinik yönetim uygulamasıdır.

## v8.1 düzeltme kapsamı

- Dashboard ve Platform Admin için TR, EN, EL, RU ve DE çalışma zamanı yerelleştirmesi güçlendirildi.
- Dashboard üst çubuğuna anında çalışan dil seçici eklendi; seçim `profiles.preferred_locale` alanına kaydediliyor.
- Login, onboarding ve pilot başvuru ekranları aynı locale çalışma zamanına bağlandı.
- Para ve tarih biçimleri seçilen dile göre `Intl` ile gösteriliyor.
- Ödeme hatırlatma e-posta/SMS metinleri danışanın tercih ettiği dilde hazırlanıyor.
- Platform Admin klinik listesi, detay çekmecesi, geçiş talepleri ve hata/yükleme durumları yeniden düzenlendi.
- Pilot uzatma, klinik durumu değiştirme, plan değiştirme ve ücretli onay işlemleri veritabanında transaction kullanan service-role RPC'lerine taşındı.
- Pilot kliniklerin yanlışlıkla doğrudan aktif yapılması engellendi; aktif ücretli/founder kliniklerde pilot tarihleri temizleniyor.
- Klinik ve abonelik durumlarının birbirinden kopmasını engelleyen senkronizasyon trigger'ı eklendi.
- Platform Admin işlemlerinde UUID, gün, fiyat, plan, durum, metin uzunluğu ve aynı anda çift tıklama doğrulamaları eklendi.
- Klinik detay API'si kısmi tablo hatalarında tüm paneli düşürmek yerine uyarı döndürüyor ve sayıları exact count ile hesaplıyor.
- İstemci `fetch` işlemleri boş veya geçersiz JSON yanıtına karşı korundu.
- Profil ve klinik ayarlarında sayı, e-posta, locale ve metin sınırları eklendi.
- PWA cache anahtarı v8.1 olarak yenilendi; dashboard/admin/API yanıtları cache dışı tutuluyor.
- Statik denetime import, rota, RPC, RLS, environment variable ve Supabase select/şema eşleştirmesi eklendi.

## Mevcut v8.0 veritabanını güncelleme

Önce Supabase yedeği alın. Supabase SQL Editor içinde yalnızca şu dosyayı çalıştırın:

```text
supabase/migrations/023_platform_integrity_and_locale_v81.sql
```

`001–022` migrationlarını yeniden çalıştırmayın.

## Sıfırdan Supabase kurulumu

Yeni bir Supabase projesinde tek dosya kullanın:

```text
supabase/baseline/production_baseline_v8_1.sql
```

## Ortam değişkenleri

`.env.example` dosyasını `.env.local` olarak kopyalayın. Production için temel değişkenler:

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

Push, e-posta ve SMS kullanılacaksa VAPID, Resend ve Twilio değişkenlerini de `.env.example` içinden ekleyin. Gizli anahtarlara `NEXT_PUBLIC_` öneki eklemeyin.

## Kurulum ve doğrulama

```bash
npm install
npm run audit
npm run typecheck
npm run lint
npm run build
npm run dev
```

## Platform Admin doğrulama akışı

1. `/platform-admin` sayfasını açın.
2. Dil seçicisinde TR/EN/EL/RU/DE arasında geçiş yapın ve sayfayı yenileyerek seçimin korunduğunu kontrol edin.
3. Bir kliniğin `Detayları gör` düğmesini açın.
4. Pilot klinikte süre uzatma ve ücretli plan onayını test edin.
5. Ücretli/founder klinikte pilot geri sayımının görünmediğini doğrulayın.
6. Geçiş talebi onaylandığında abonelik durumunun `active`, pilot tarihlerinin `null` olduğunu doğrulayın.

## Sağlık kontrolü

```text
/api/health
```

Beklenen sürüm:

```json
{"version":"0.8.1","edition":"Stabilized SaaS v8.1"}
```

Teknik kapsam ve doğrulama sınırları için `AUDIT-v8.1.md` dosyasına bakın.
