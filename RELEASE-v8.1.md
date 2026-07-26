# NutriClinic AI v8.1 Release Notes

## Ana düzeltmeler

- Dashboard, Platform Admin, login, onboarding ve pilot başvurusunda çok dilli çalışma zamanı.
- Kalıcı dashboard dil seçimi ve locale uyumlu tarih/para biçimleri.
- Danışan diline göre ödeme hatırlatma e-posta/SMS içerikleri.
- Platform Admin klinik detay ekranı, kısmi hata uyarıları ve exact sayaçlar.
- Transactional pilot uzatma, ücretli plana geçiş, durum ve plan yönetimi.
- Klinik/abonelik durum senkronizasyonu ve hatalı pilot banner düzeltmesi.
- API gövde, UUID, boolean, sayı, metin ve same-origin doğrulamaları.
- Geçersiz JSON yanıtlarına karşı güvenli istemci davranışı.
- PWA cache v8.1 yenilemesi.
- Genişletilmiş statik proje denetimi.

## Migration

Mevcut v8.0 kurulumunda yalnızca:

```text
supabase/migrations/023_platform_integrity_and_locale_v81.sql
```

## Sürüm

```text
0.8.1
```
