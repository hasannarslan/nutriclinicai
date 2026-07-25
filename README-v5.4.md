# NutriClinic AI v5.4

Bu sürüm sadakat ödüllerindeki rol akışını düzeltir.

## Yeni sadakat akışı

- Danışan artık kendi puanını harcayıp kupon oluşturamaz.
- Klinik Sahibi veya Diyetisyen, Sadakat ekranından danışanı ve ödülü seçer.
- Sistem danışanın puanını, ödül bedelini ve stoğu kontrol eder.
- Ödül danışanın hesabına tanımlandığında puan ve stok tek işlemde düşer.
- Danışan kendisine tanımlanan ödülü ve 8 karakterli kupon kodunu görür.
- Klinik Sahibi veya Diyetisyen ödülü listeden **Kullanıldı** olarak işaretler.
- Bütün tanımlama ve kullanım işlemleri audit loguna kaydedilir.

## Düzeltilen hatalar

- `column reference "id" is ambiguous`
- Manuel ve sistemde bulunmayan kodlarda görülen kafa karıştırıcı `Reward code not found` akışı
- Danışanın kendi kuponunu üretmesi

## Mevcut Supabase projesini güncelleme

Daha önce `001-013` migrationlarını çalıştırdıysanız yalnızca şu dosyayı çalıştırın:

```text
supabase/migrations/014_staff_managed_loyalty_coupons.sql
```

Supabase Dashboard:

```text
SQL Editor → New query → Dosyanın tamamını yapıştır → Run
```

`001-013` dosyalarını yeniden çalıştırmayın.

## Çalıştırma

Eski `.env.local` dosyanızı yeni klasöre kopyalayın.

```powershell
npm.cmd install
npm.cmd run dev
```

Production kontrolü:

```powershell
npm.cmd run build
```
