# NutriClinic AI v5.6

## Sadakat akışı

Bu sürümde danışan, puanı ve stok yeterliyse ödülü kendi hesabından alır.

1. Klinik Sahibi ödül kataloğunu ve stokları oluşturur.
2. Danışan Sadakat ekranında **Puanımla kullan** düğmesine basar.
3. Puan ve stok aynı veritabanı işlemi içinde düşer.
4. Tek kullanımlık 8 karakterli kod oluşturulur.
5. Ödül danışanın **Puanımla aldığım ödüller** alanında görünür.
6. Klinik Sahibi veya atanmış Diyetisyen hizmet verildiğinde **Kullanıldı** olarak işaretler.
7. İşlem bildirim ve audit loglarına kaydedilir.

Aktif ödül bulunmuyorsa danışana, bu bölümün klinik ödülleri oluşturduktan sonra açılacağı gösterilir.

## Mevcut Supabase projesini güncelleme

Daha önce `001`–`015` migrationlarını çalıştırdıysanız yalnızca:

```text
supabase/migrations/016_client_self_service_loyalty_rewards.sql
```

dosyasını Supabase SQL Editor içinde bir kez çalıştırın.

## Yerel çalıştırma

```powershell
npm.cmd install
npm.cmd run dev
```

Production kontrolü:

```powershell
npm.cmd run build
```
