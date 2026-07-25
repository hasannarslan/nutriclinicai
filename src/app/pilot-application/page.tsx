import Link from "next/link";
import PilotApplicationForm from "./pilot-application-form";

export const dynamic = "force-dynamic";

export default function PilotApplicationPage() {
  return (
    <main className="pilot-application-page">
      <header className="pilot-application-nav">
        <Link href="/" className="brand"><span>🍏</span><b>NutriClinic AI</b></Link>
        <Link href="/login" className="secondary-button compact">Giriş yap</Link>
      </header>
      <section className="pilot-application-shell">
        <div className="pilot-application-copy">
          <span className="section-kicker">ÜCRETSİZ PİLOT PROGRAMI</span>
          <h1>Kliniğinizi NutriClinic AI pilot programına taşıyın.</h1>
          <p>İlk 3–5 diyetisyen ve klinik sistemi sınırlı süre ücretsiz kullanacak. Başvurunuz incelendikten sonra size özel pilot kayıt bağlantısı gönderilecek.</p>
          <div className="pilot-application-benefits">
            <article><b>90 güne kadar ücretsiz erişim</b><span>Gerçek danışanlarınızla sistemi test edin.</span></article>
            <article><b>Kurulum ve veri aktarım desteği</b><span>Ekip, hizmet ve çalışma saatlerinizi birlikte hazırlayın.</span></article>
            <article><b>Öncelikli geliştirme</b><span>Pilot geri bildirimleri ürün yol haritasında öncelik kazanır.</span></article>
          </div>
        </div>
        <PilotApplicationForm />
      </section>
    </main>
  );
}
