# NutriClinic AI v7.3 — Açık Kayıt ve Pilot Başvuru Akışı

## Yeni kullanıcı akışı

- Giriş ekranında **Üye ol** sekmesi artık herkese açıktır.
- Kullanıcı kayıt sırasında kullanım amacını seçer: Danışan, Diyetisyen, Sekreter veya Klinik Sahibi.
- Bu seçim doğrudan rol vermez. Klinik erişimi ve gerçek rol yalnızca klinik daveti veya pilot onayı ile etkinleşir.
- Davetsiz kayıt olan kullanıcı `/onboarding` ekranında klinik davet kodunu girebilir.
- Klinik sahibi veya bağımsız diyetisyen, genel pilot başvuru formuna yönlendirilir.

## Pilot başvuru sistemi

- Landing page üzerindeki **Pilot başvurusu** artık uygulama içindeki `/pilot-application` formunu açar.
- Başvurular Platform Admin → **Pilot başvuruları** sekmesinde listelenir.
- Platform Admin başvuruyu durumlandırabilir, e-posta gönderebilir ve tek tıkla pilot davet formunu hazırlayabilir.

## Veritabanı

Mevcut v7.2 kurulumunda yalnızca:

`supabase/migrations/020_public_registration_and_pilot_applications.sql`

çalıştırılmalıdır.
