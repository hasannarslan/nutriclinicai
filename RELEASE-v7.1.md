# NutriClinic AI v7.1

## Pilot kliniğe özel bağlantı düzeltmesi

- Pilot daveti oluşturulduğunda yalnızca kod değil, tam ve benzersiz kayıt URL'si ekranda gösterilir.
- Oluşturulan bağlantı için Kopyala ve Aç düğmeleri bulunur.
- Aktif pilot davetleri listesinde her klinik için tam URL görünür.
- `NEXT_PUBLIC_APP_URL` tanımlıysa bağlantılar Vercel production alan adıyla oluşturulur; tanımlı değilse açık olan sitenin domaini kullanılır.
- Clipboard izni kapalıysa yedek kopyalama yöntemi devreye girer.
- Bu sürüm için Supabase migrationı gerekmez.
