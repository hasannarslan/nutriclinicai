import type { Metadata, Viewport } from "next";
import "./globals.css";

const appUrl = process.env.NEXT_PUBLIC_APP_URL || "http://localhost:3000";

export const metadata: Metadata = {
  metadataBase: new URL(appUrl),
  title: { default: "NutriClinic AI", template: "%s · NutriClinic AI" },
  description: "Diyetisyen klinikleri için randevu, danışan, menü, ölçüm, ödeme ve yapay zekâ destekli klinik yönetim platformu.",
  keywords: ["diyetisyen programı", "klinik yönetimi", "beslenme planı", "randevu sistemi", "NutriClinic AI"],
  manifest: "/manifest.webmanifest",
  appleWebApp: { capable: true, statusBarStyle: "default", title: "NutriClinic AI" },
  icons: { icon: "/icon.svg", apple: "/icon.svg" },
  openGraph: {
    title: "NutriClinic AI",
    description: "Diyetisyen klinikleri için yapay zekâ destekli klinik işletim sistemi.",
    type: "website",
    url: appUrl,
  },
};

export const viewport: Viewport = { themeColor: "#0f6b4d" };

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  const year = new Date().getFullYear();
  return (
    <html lang="tr">
      <body>
        {children}
        <footer className="global-copyright">© {year} NutriClinic AI. Tüm hakları Hasan Arslan tarafından saklıdır.</footer>
      </body>
    </html>
  );
}
