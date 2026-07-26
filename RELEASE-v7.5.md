# NutriClinic AI v7.5 — Klinik Detayı ve Pilot Sonrası Onay

Bu sürüm Platform Admin panelini gerçek tenant yönetim ekranına dönüştürür.

## Eklenenler

- Klinik satırından açılan ayrıntılı klinik drawer'ı
- Klinik iletişim, plan, pilot ve ticari onay bilgileri
- Klinik sahibi, diyetisyen ve sekreter listesi
- Aktif danışan, randevu, menü, ölçüm, cihaz ve paket özetleri
- Toplam/alınan/kalan ödeme özeti
- Platforma özel klinik notları ve son audit hareketleri
- Klinik Sahibinin pilot bittikten sonra ücretli devam talebi göndermesi
- Platform Admin'de ayrı Geçiş Talepleri sekmesi
- Talep edilen plan, klinik notu ve tarih görüntüleme
- Plan, aylık/yıllık/manüel dönem, anlaşılmış fiyat ve onay notu ile ticari aktivasyon
- Onay sonrası kliniğin `active` durumuna ve seçilen ücretli plana geçirilmesi
- Pilot süresini özel gün sayısıyla uzatma

## Veritabanı

Mevcut kurulumda yalnızca `021_platform_clinic_details_and_paid_conversion.sql` dosyasını bir kez çalıştırın.
