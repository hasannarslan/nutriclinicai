"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Apple, ArrowRight, Building2, CheckCircle2, KeyRound, LogOut, UsersRound } from "lucide-react";
import { createClient } from "@/lib/supabase/client";

function makeSlug(value: string) {
  return value
    .toLocaleLowerCase("tr-TR")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/ı/g, "i")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 55);
}

export default function OnboardingClient({
  initialPilotToken,
  initialInviteToken,
  email,
}: {
  initialPilotToken: string;
  initialInviteToken: string;
  email: string;
}) {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);
  const initialMode = initialPilotToken ? "pilot" : "invite";
  const [mode, setMode] = useState<"pilot" | "invite">(initialMode);
  const [token, setToken] = useState(initialPilotToken || initialInviteToken);
  const [clinicName, setClinicName] = useState("");
  const [slug, setSlug] = useState("");
  const [timezone, setTimezone] = useState("Europe/Istanbul");
  const [locale, setLocale] = useState("tr");
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  async function submitPilot() {
    if (!token.trim()) return setError("Pilot davet kodunu girin.");
    if (!clinicName.trim()) return setError("Klinik adını girin.");
    const finalSlug = slug.trim() || makeSlug(clinicName);
    if (!finalSlug) return setError("Klinik bağlantı adını girin.");
    setLoading(true); setError(""); setMessage("");
    const { error: rpcError } = await supabase.rpc("redeem_pilot_invite_v7", {
      p_token: token.trim(),
      p_clinic_name: clinicName.trim(),
      p_slug: finalSlug,
      p_timezone: timezone,
      p_locale: locale,
    });
    setLoading(false);
    if (rpcError) return setError(rpcError.message);
    setMessage("Pilot kliniğiniz oluşturuldu. Panel açılıyor…");
    router.replace("/dashboard");
    router.refresh();
  }

  async function acceptInvite() {
    if (!token.trim()) return setError("Klinik davet kodunu girin.");
    setLoading(true); setError(""); setMessage("");
    const { error: rpcError } = await supabase.rpc("accept_clinic_invite_v7", {
      p_token: token.trim(),
    });
    setLoading(false);
    if (rpcError) return setError(rpcError.message);
    setMessage("Davet kabul edildi. Panel açılıyor…");
    router.replace("/dashboard");
    router.refresh();
  }

  async function logout() {
    await supabase.auth.signOut();
    router.replace("/login");
    router.refresh();
  }

  return (
    <main className="onboarding-page">
      <section className="onboarding-shell">
        <header className="onboarding-header">
          <div className="brand"><span><Apple size={22}/></span><b>NutriClinic AI</b></div>
          <button type="button" className="secondary-button compact" onClick={logout}><LogOut size={15}/>Çıkış</button>
        </header>

        <div className="onboarding-copy">
          <span className="section-kicker">KLİNİK KURULUMU</span>
          <h1>Hesabınızı doğru kliniğe bağlayın.</h1>
          <p>{email ? `${email} hesabı` : "Hesabınız"} oluşturuldu. Hesabınız hazır. Klinik verilerinin birbirinden ayrılması ve rolünüzün güvenli biçimde belirlenmesi için klinik veya pilot davet koduyla devam edin.</p>
        </div>

        <div className="onboarding-mode-grid">
          <button type="button" className={mode === "pilot" ? "active" : ""} onClick={() => { setMode("pilot"); setError(""); }}>
            <Building2 size={25}/><span><b>Pilot klinik oluştur</b><small>NutriClinic AI tarafından verilen pilot koduyla yeni klinik workspace’i açın.</small></span>
          </button>
          <button type="button" className={mode === "invite" ? "active" : ""} onClick={() => { setMode("invite"); setError(""); }}>
            <UsersRound size={25}/><span><b>Mevcut kliniğe katıl</b><small>Klinik Sahibinin gönderdiği ekip veya danışan davet kodunu kullanın.</small></span>
          </button>
        </div>

        <section className="onboarding-form-card">
          <label>Davet kodu
            <div className="token-input"><KeyRound size={18}/><input value={token} onChange={(event) => setToken(event.target.value.toUpperCase())} placeholder={mode === "pilot" ? "PILOT KODU" : "KLİNİK DAVET KODU"}/></div>
          </label>

          {mode === "pilot" ? (
            <>
              <div className="form-grid">
                <label>Klinik adı<input value={clinicName} onChange={(event) => { setClinicName(event.target.value); if (!slug) setSlug(makeSlug(event.target.value)); }} placeholder="Örn. Arslan Sağlıklı Yaşam Merkezi"/></label>
                <label>Klinik bağlantısı<input value={slug} onChange={(event) => setSlug(makeSlug(event.target.value))} placeholder="arslan-saglikli-yasam"/><small>Panel ve ilerideki özel bağlantınız için kullanılır.</small></label>
                <label>Varsayılan dil<select value={locale} onChange={(event) => setLocale(event.target.value)}><option value="tr">Türkçe</option><option value="en">English</option><option value="el">Ελληνικά</option><option value="ru">Русский</option><option value="de">Deutsch</option></select></label>
                <label>Saat dilimi<select value={timezone} onChange={(event) => setTimezone(event.target.value)}><option value="Europe/Istanbul">Türkiye / İstanbul</option><option value="Asia/Famagusta">Kıbrıs / Gazimağusa</option><option value="Europe/Athens">Yunanistan / Atina</option><option value="Europe/Berlin">Almanya / Berlin</option><option value="Europe/Moscow">Rusya / Moskova</option></select></label>
              </div>
              <div className="pilot-includes"><CheckCircle2 size={18}/><p>Pilot klinik, bağımsız veritabanı alanı, Klinik Sahibi hesabı, varsayılan Diyetisyen profili ve ücretsiz pilot planıyla otomatik hazırlanır.</p></div>
              <button type="button" className="primary-button onboarding-submit" disabled={loading} onClick={submitPilot}>{loading ? "Kuruluyor…" : "Pilot kliniği oluştur"}<ArrowRight size={18}/></button>
            </>
          ) : (
            <>
              <div className="pilot-includes"><CheckCircle2 size={18}/><p>Davet kodu; rolünüzü, kliniğinizi ve erişebileceğiniz verileri otomatik belirler. Başka kliniklerin verilerine erişemezsiniz.</p></div>
              <button type="button" className="primary-button onboarding-submit" disabled={loading} onClick={acceptInvite}>{loading ? "Katılınıyor…" : "Kliniğe katıl"}<ArrowRight size={18}/></button>
            </>
          )}

          {error && <p className="form-message error">{error}</p>}
          {message && <p className="form-message success">{message}</p>}
        </section>

        <p className="onboarding-help">Davet kodunuz yoksa kliniğinizin sahibinden davet isteyin. Klinik sahibi veya bağımsız diyetisyenseniz <a href="/pilot-application">pilot programına başvurun</a>.</p>
      </section>
    </main>
  );
}
