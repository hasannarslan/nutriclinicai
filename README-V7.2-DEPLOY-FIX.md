# NutriClinic AI v7.2 Deploy Fix

Bu paket Vercel/npm kurulum sorununu düzeltir.

- Eski `package-lock.json` kaldırıldı.
- Bağımlılıklar tam sürümlere sabitlendi.
- npm kayıt adresi `https://registry.npmjs.org/` olarak zorlandı.
- Node.js sürümü `20.x` olarak sabitlendi.
- Vercel install komutu public npm registry kullanır.

## GitHub'a yükleme

Bu klasörde:

```cmd
git add -A
git commit -m "Fix Vercel dependency installation v7.2"
git push origin main
```

Vercel'de Node.js Version: `20.x`; Install Command alanı boş/default bırakılabilir çünkü `vercel.json` içinde tanımlıdır.
