# NutriClinic AI v5.5

## Sadakat düzeltmesi

Bu sürüm iki sorunu düzeltir:

1. `999.999.999` gibi yanlışlıkla girilmiş puanlar artık olağan dışı bakiye olarak işaretlenir.
2. Klinik Sahibi veya Diyetisyen danışanın puanını log kaydı oluşturarak doğru değere çekebilir.
3. Tek işlemde en fazla 1.000.000 puan eklenebilir; 100.000 ve üzerindeki girişlerde ayrıca onay istenir.
4. Danışan ödülü kendisi oluşturmaz. Klinik Sahibi veya Diyetisyen, danışanı seçip ödülü hesabına tanımlar.
5. Ödül kullanımı manuel kod yazarak değil, tanımlanmış ödül kaydındaki **Kullanıldı işaretle** düğmesiyle tamamlanır.

## Mevcut projeyi güncelleme

Supabase SQL Editor'de yalnızca şu migrationı çalıştırın:

```text
015_loyalty_balance_repair_and_reward_flow.sql
```

`001-014` dosyalarını yeniden çalıştırmayın.

Migration tamamlandıktan sonra Klinik Sahibi veya Diyetisyen hesabıyla:

1. **Sadakat** ekranını açın.
2. Danışanı seçin.
3. **Puan bakiyesini düzelt** bölümünü açın.
4. Gerçek bakiye ve düzeltme nedenini girin.
5. Sonra ödülü seçip **Ödülü danışana tanımla** düğmesine basın.
6. Ödül klinikte kullanıldığında tanımlanan ödül kaydında **Kullanıldı** düğmesine basın.

## Çalıştırma

```powershell
npm.cmd install
npm.cmd run dev
```

Production kontrolü:

```powershell
npm.cmd run build
```
