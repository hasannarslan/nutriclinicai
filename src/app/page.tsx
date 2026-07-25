import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Activity, Apple, ArrowRight, CalendarDays, CheckCircle2, CircleDollarSign, ClipboardCheck, MessagesSquare, ShieldCheck, Sparkles, UsersRound, UtensilsCrossed } from "lucide-react";
import { isPlatformAdminEmail } from "@/lib/platform-admin";

export const dynamic = "force-dynamic";

export default async function Home() {
  if (!process.env.NEXT_PUBLIC_SUPABASE_URL || !(process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY)) {
    redirect("/login?setup=missing");
  }
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (user) redirect(isPlatformAdminEmail(user.email) ? "/platform-admin" : "/dashboard");

  const salesEmail = process.env.NEXT_PUBLIC_SALES_EMAIL || "hello@nutriclinic.ai";
  return (
    <main className="marketing-page">
      <header className="marketing-nav">
        <div className="brand"><span><Apple size={21}/></span><b>NutriClinic AI</b></div>
        <nav><a href="#features">Özellikler</a><a href="#pilot">Pilot Programı</a><a href="#security">Güvenlik</a></nav>
        <a className="secondary-button compact" href="/login">Giriş yap</a>
      </header>

      <section className="marketing-hero">
        <div className="marketing-hero-copy">
          <span className="marketing-pill"><Sparkles size={15}/>Diyetisyen klinikleri için işletim sistemi</span>
          <h1>Randevudan menüye, ödemeden danışan takibine kadar kliniğiniz tek panelde.</h1>
          <p>NutriClinic AI; diyetisyen, sekreter ve danışan süreçlerini ayrı yetkilerle yöneten; yapay zekâ destekli, çok dilli klinik yönetim platformudur.</p>
          <div className="marketing-actions"><a className="primary-button" href="/login">Davet koduyla başla<ArrowRight size={17}/></a><a className="secondary-button" href={`mailto:${salesEmail}?subject=NutriClinic%20AI%20Pilot%20Başvurusu`}>Pilot başvurusu</a></div>
          <div className="marketing-proof"><span><CheckCircle2/>Kurulum gerektirmeyen klinik workspace</span><span><CheckCircle2/>Rol bazlı veri erişimi</span><span><CheckCircle2/>Web ve mobil uyumlu PWA</span></div>
        </div>
        <div className="marketing-dashboard-preview">
          <div className="preview-top"><span></span><span></span><span></span><b>NutriClinic AI</b></div>
          <div className="preview-grid">
            <article><CalendarDays/><small>Bugünkü randevu</small><strong>12</strong><em>3 onay bekliyor</em></article>
            <article><UsersRound/><small>Aktif danışan</small><strong>186</strong><em>+14 bu ay</em></article>
            <article><CircleDollarSign/><small>Günlük tahsilat</small><strong>₺24.500</strong><em>₺7.000 bekliyor</em></article>
            <article><Activity/><small>Uyum ortalaması</small><strong>%81</strong><em>12 riskli danışan</em></article>
          </div>
          <div className="preview-list"><b>Bugünkü akış</b><span><i></i>09:00 · İlk görüşme · Onaylandı</span><span><i></i>10:00 · Vücut analizi · Ödendi</span><span><i></i>11:15 · Kontrol · Bekliyor</span></div>
        </div>
      </section>

      <section id="features" className="marketing-section">
        <div className="marketing-section-head"><span className="section-kicker">TEK PLATFORM</span><h2>Klinik operasyonunun bütün parçaları birbiriyle bağlı çalışır.</h2><p>Ayrı uygulamalar, Excel dosyaları ve dağınık mesajlaşmalar yerine tek danışan kaydı üzerinden tüm süreci yönetin.</p></div>
        <div className="marketing-feature-grid">
          <article><CalendarDays/><h3>Akıllı randevu</h3><p>Diyetisyen, cihaz ve oda uygunluğunu aynı sistemde yönetin; onay, iptal ve hatırlatmaları otomatikleştirin.</p></article>
          <article><UsersRound/><h3>Detaylı danışan dosyası</h3><p>Ölçüm, alerji, anamnez, belge, ödeme, paket, katılım ve sadakat geçmişini tek profilde görün.</p></article>
          <article><UtensilsCrossed/><h3>Beslenme planı</h3><p>Öğün bazlı plan, otomatik makro tahmini, Word/PDF çıktısı, fotoğraflı tüketim ve AI alternatifleri.</p></article>
          <article><CircleDollarSign/><h3>Ödeme ve paketler</h3><p>Hizmet kalemleri, kısmi tahsilat, kalan bakiye, yaklaşan ödeme ve seans kullanımını takip edin.</p></article>
          <article><MessagesSquare/><h3>Güvenli iletişim</h3><p>Danışan–diyetisyen özel mesajlaşması, dosya paylaşımı, topluluk ve 24 saatlik hikâyeler.</p></article>
          <article><ClipboardCheck/><h3>Onam ve takip</h3><p>Anamnez, dijital onay, görevler, uyum skoru ve bildirim merkeziyle danışan devamlılığını artırın.</p></article>
        </div>
      </section>

      <section id="pilot" className="marketing-pilot">
        <div><span className="marketing-pill light"><Sparkles size={15}/>Davetli pilot programı</span><h2>İlk 3–5 klinik sistemi ücretsiz kullanacak.</h2><p>Pilot klinikler gerçek danışan süreçlerinde sistemi belirli süre ücretsiz kullanır. Karşılığında düzenli geri bildirim verir; kritik hatalar ve kullanım ihtiyaçları öncelikli geliştirilir.</p><ul><li>Ücretsiz pilot klinik workspace’i</li><li>Kurulum ve ekip davet desteği</li><li>Pilot süresi ve kullanım limitlerinin panelden yönetimi</li><li>Doğrudan geri bildirim ve öncelikli destek</li><li>Pilot sonunda ücretli plana geçiş kararı</li></ul></div>
        <div className="pilot-process"><article><span>1</span><b>Klinik seçimi</b><p>Farklı çalışma modellerinden 3–5 diyetisyen veya klinik belirlenir.</p></article><article><span>2</span><b>90 günlük pilot</b><p>Klinik davet koduyla kendi izole alanını kurar ve gerçek kullanım başlar.</p></article><article><span>3</span><b>Haftalık geri bildirim</b><p>Panel içindeki pilot geri bildirim aracıyla hata ve öneriler toplanır.</p></article><article><span>4</span><b>Ücretli dönüşüm</b><p>Pilot sonunda kullanım, değer ve ihtiyaçlara göre uygun plan sunulur.</p></article></div>
      </section>

      <section id="security" className="marketing-security"><ShieldCheck size={42}/><div><span className="section-kicker">TENANT İZOLASYONU</span><h2>Her kliniğin verisi ayrı erişim kurallarıyla korunur.</h2><p>Kullanıcılar yalnızca davet edildikleri kliniğe bağlanır. Klinik üyeliği ve rolü veritabanı seviyesinde doğrulanır; danışan, diyetisyen ve sekreter erişimleri ayrı tutulur.</p></div></section>


    </main>
  );
}
