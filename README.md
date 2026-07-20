# NutriClinic AI v4.1

NutriClinic AI; Klinik Sahibi, Diyetisyen, Sekreter ve Danışan rolleri için hazırlanmış Next.js + Supabase tabanlı klinik yönetim ve kişiselleştirilmiş danışan takip platformudur.

## v4.1 değişiklikleri

### Danışan Genel Bakış → ödeme durumu

Danışan günlük panelinde artık ödeme özeti bulunur:

- Son ödeme kaydının durumu
- Ödeme alınan veya bekleyen hizmet
- Ödeme yöntemi: Nakit, Kart, IBAN veya Diğer
- Son işlem tarihi
- Toplam alınan tutar
- Toplam bekleyen tutar
- Tek tıkla Ayarlar → Ödemelerim alanına geçiş

Danışan yalnızca kendisine ait ödeme kayıtlarını görebilir. Bu erişim `payments` tablosundaki mevcut RLS politikasıyla korunur.

### Ayarlar → Ödemelerim

Danışan ayarlarında geçmiş ödeme kayıtları listelenir:

- Hizmet adı ve açıklaması
- Tutar
- Durum: Bekliyor, Kısmi, Ödendi, İade veya İptal
- Ödeme yöntemi
- Ödeme tarihi
- Ödenen toplam, bekleyen toplam ve kayıt sayısı

Bu güncelleme yeni tablo veya migration gerektirmez; v3.0 ile gelen `payments` altyapısını kullanır.

### Groq ve xAI Grok desteği

AI tarif ve yiyecek etiketi tarayıcı artık sağlayıcı seçilebilir şekilde çalışır.

Desteklenen değerler:

```env
AI_PROVIDER=groq
AI_PROVIDER=xai
AI_PROVIDER=grok
```

`grok`, xAI Grok için takma addır. `groq`, GroqCloud platformudur.

#### GroqCloud yapılandırması

```env
AI_PROVIDER=groq
GROQ_API_KEY=gsk_xxx
GROQ_MODEL=llama-3.3-70b-versatile
GROQ_VISION_MODEL=qwen/qwen3.6-27b
```

#### xAI Grok yapılandırması

```env
AI_PROVIDER=xai
XAI_API_KEY=xai-xxx
XAI_MODEL=grok-4.5
XAI_VISION_MODEL=grok-4.5
```

API anahtarlarına `NEXT_PUBLIC_` öneki eklemeyin. Anahtarlar yalnızca sunucu tarafındaki API route'larında kullanılır.

## v4.0 kişiselleştirme özellikleri

- Danışan ilk kurulum akışı
- Hedef, boy, kilo, hedef kilo ve aktivite bilgileri
- Kronik durum, alerji ve beslenme tarzı kaydı
- Günlük kalori ve makro takibi
- Su, kilo ve egzersiz kaydı
- Öğün fotoğrafı gönderme
- AI tarif üretici
- Paketli gıda etiketi ve alerjen tarayıcı
- Diyetisyen ve Klinik Sahibi için genişletilmiş danışan detayları

## Mevcut v4.0 sistemini yükseltme

Bu sürüm için **yeni Supabase SQL migration çalıştırılmaz**.

Yapılacaklar:

1. Eski `.env.local` dosyanızı yeni klasöre kopyalayın.
2. OpenAI değişkenleri varsa kaldırın veya pasif bırakın.
3. Groq ya da xAI değişkenlerinden birini ekleyin.
4. Yeni projeyi çalıştırın.

## Yeni Supabase projesi

Migration dosyalarını sırayla çalıştırın:

```text
001_production_schema.sql
002_schedule_settings_upgrade.sql
003_role_client_visibility_fix.sql
004_booking_menu_loyalty_upgrade.sql
005_meal_nutrition_auth_upgrade.sql
006_manual_loyalty_points.sql
007_edit_calendar_redemption_settings.sql
008_loyalty_redemptions_food_warnings.sql
009_uiux_payments_media_community.sql
010_personalization_daily_ai_tools.sql
```

## Ortam değişkenleri

`.env.example` dosyasını `.env.local` olarak kopyalayın:

```env
NEXT_PUBLIC_SUPABASE_URL=https://YOUR-PROJECT.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_xxx

AI_PROVIDER=groq
GROQ_API_KEY=gsk_xxx
GROQ_MODEL=llama-3.3-70b-versatile
GROQ_VISION_MODEL=qwen/qwen3.6-27b
```

Legacy Supabase projelerinde `NEXT_PUBLIC_SUPABASE_ANON_KEY` kullanılabilir.

## Yerel çalıştırma

```powershell
npm.cmd install
npm.cmd run dev
```

```text
http://localhost:3000
```

## Vercel

Vercel Project Settings → Environment Variables alanına aynı Supabase ve AI değişkenlerini ekleyin.

Supabase Authentication URL Configuration:

```text
Site URL: https://YOUR-PROJECT.vercel.app
Redirect URL: https://YOUR-PROJECT.vercel.app/auth/callback
Local Redirect URL: http://localhost:3000/auth/callback
```

## Kontroller

```powershell
npm.cmd run lint
npm.cmd run build
```
