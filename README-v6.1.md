# NutriClinic AI v6.1

Bu sürüm v6.0 üzerindeki iki hatayı düzeltir.

## Düzeltmeler

- Yeni onam kaydında boş `id` değerinin UUID kolonuna gönderilmesi engellendi.
- Zorunlu onamlar kabul edilmeden kayıt yapılması engellendi.
- Danışan profili bulunamadığında anlaşılır Türkçe hata gösterilir.
- Onam kaldırıldığında iptal tarihi doğru biçimde kaydedilir.
- Danışan Özel Mesajlar ekranı masaüstünde artık tam genişlikte açılır.
- Klinik Sahibi/Diyetisyen ekranındaki danışan listeli görünüm korunur.
- İmza alanı ve Onayları kaydet düğmesi daha düzgün hizalandı.

## Supabase

Bu sürüm için yeni SQL migration gerekmez. Daha önce `017_clinic_operations_sprint.sql` başarıyla çalıştıysa yalnızca yeni ZIP'i kullanın.

## Çalıştırma

```powershell
npm.cmd install
npm.cmd run dev
```

Production kontrolü:

```powershell
npm.cmd run build
```
