# NutriClinic AI v6.2

Bu sürüm v6.1 düzeltmelerini ve danışan cihaz randevu sistemini içerir.

## Yeni özellikler

- Danışanlar **Cihaz ve Odalar** ekranından kliniğin danışan rezervasyonuna açtığı cihazları görebilir.
- Cihazın çalışma aralığına ve seans süresine göre müsait saatler yatay olarak oluşturulur.
- Müsait saatler aktif, dolu saatler pasif görünür.
- Danışanın oluşturduğu cihaz randevusu `Onay bekliyor` durumunda açılır.
- Klinik Sahibi, Diyetisyen veya Sekreter talebi onaylayabilir, tamamlayabilir veya iptal edebilir.
- Danışan başlamamış kendi cihaz randevusunu iptal edebilir.
- Klinik Sahibi **ve Diyetisyen** cihaz/oda ekleyebilir.
- Cihaz adı, türü, seans süresi, rezervasyon başlangıç-bitiş saati ve danışana açık olup olmadığı belirlenebilir.
- Klinik Sahibi veya Diyetisyen cihazı silebilir/pasife alabilir; geçmiş rezervasyonlar korunur.
- Yaklaşan rezervasyonu bulunan cihaz, rezervasyonlar iptal edilmeden silinemez.
- Cihaz randevu talepleri ve durum değişiklikleri bildirim merkezine düşer.
- Danışan başka kişilerin dolu saatlerini görür, ancak ad/telefon/e-posta bilgilerini göremez.
- Klinik ekibi randevu sahibinin ad, telefon ve e-posta bilgilerini görür.

## Önceki v6.1 düzeltmeleri

- Onam kaydında boş UUID hatası düzeltildi.
- Danışan özel mesajlaşma ekranı masaüstünde tam genişliğe çıkarıldı.

## Supabase

`001-017` daha önce çalıştıysa yalnızca şunu çalıştırın:

```text
supabase/migrations/018_client_device_booking.sql
```

## Çalıştırma

```powershell
npm.cmd install
npm.cmd run dev
```

Production kontrolü:

```powershell
npm.cmd run build
```
