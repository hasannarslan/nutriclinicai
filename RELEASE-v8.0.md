# NutriClinic AI v8.0 Release

## Güncelleme sırası

1. Projeyi yedekleyin.
2. Supabase’de `022_stabilization_and_lifecycle_fix.sql` çalıştırın.
3. Bu paketin içeriğini mevcut Git repo köküne kopyalayın.
4. `npm install && npm run audit && npm run build` çalıştırın.
5. GitHub `main` branch’e push edin.
6. Vercel Preview deployment’ında login, Platform Admin, pilot ve ücretli klinik akışlarını test edin.
7. Preview başarılıysa Production’a promote edin.

## Veritabanı geri dönüş notu

022 migration veri silmez. Non-pilot aboneliklerde yalnızca anlamsız eski pilot tarihlerini temizler ve yaşam döngüsü trigger’ı ekler.
