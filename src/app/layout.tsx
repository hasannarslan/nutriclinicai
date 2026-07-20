import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "NutriClinic AI",
  description: "Diyetisyen klinikleri için akıllı yönetim ve danışan takip platformu.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="tr">
      <body>{children}</body>
    </html>
  );
}
