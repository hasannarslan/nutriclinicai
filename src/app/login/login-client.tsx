"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Apple, ArrowRight, CheckCircle2, Languages, ShieldCheck } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { detectBrowserLocale, dictionaries, localeLabels, locales } from "@/lib/i18n";
import { LocalizedContent } from "@/lib/i18n-runtime";
import type { Locale } from "@/lib/types";

export default function LoginClient({ configured, platformSetupAllowed }: { configured: boolean; platformSetupAllowed: boolean }) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [mode, setMode] = useState<"login" | "register">(searchParams.get("mode") === "register" ? "register" : "login");
  const [locale, setLocale] = useState<Locale>("tr");
  useEffect(() => setLocale(detectBrowserLocale()), []);
  const [fullName, setFullName] = useState("");
  const [accountIntent, setAccountIntent] = useState("client");
  const [email, setEmail] = useState("");
  const [phone, setPhone] = useState("");
  const [identity, setIdentity] = useState("");
  const [password, setPassword] = useState("");
  const [otp, setOtp] = useState("");
  const [awaitingPhoneOtp, setAwaitingPhoneOtp] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState(searchParams.get("error") ? "E-posta doğrulaması tamamlanamadı." : "");
  const [loading, setLoading] = useState(false);
  const t = dictionaries[locale];
  const isEmailIdentity = useMemo(() => identity.includes("@"), [identity]);
  const pilotToken = searchParams.get("pilot") || "";
  const inviteToken = searchParams.get("invite") || "";
  const nextPath = platformSetupAllowed
    ? "/platform-admin"
    : pilotToken
      ? `/onboarding?pilot=${encodeURIComponent(pilotToken)}`
      : inviteToken
        ? `/onboarding?invite=${encodeURIComponent(inviteToken)}`
        : "/dashboard";

  async function signIn() {
    setError(""); setMessage(""); setLoading(true);
    try {
      const supabase = createClient();
      const credentials = isEmailIdentity
        ? { email: identity.trim(), password }
        : { phone: identity.trim(), password };
      const { error: authError } = await supabase.auth.signInWithPassword(credentials);
      if (authError) throw authError;
      router.replace(nextPath);
      router.refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Giriş yapılamadı.");
    } finally { setLoading(false); }
  }

  async function signUp() {
    setError(""); setMessage("");
    if (!fullName.trim()) return setError("Ad soyad zorunludur.");
    if (!email.trim() && !phone.trim()) return setError("E-posta veya telefon bilgilerinden biri zorunludur.");
    if (password.length < 8) return setError("Şifre en az 8 karakter olmalıdır.");
    setLoading(true);
    try {
      const supabase = createClient();
      const options = {
        data: {
          full_name: fullName.trim(),
          contact_email: email.trim() || null,
          contact_phone: phone.trim() || null,
          preferred_locale: locale,
          account_intent: accountIntent,
        },
        emailRedirectTo: `${window.location.origin}/auth/callback?next=${encodeURIComponent(nextPath)}`,
      };
      const credentials = email.trim()
        ? { email: email.trim(), password, options }
        : { phone: phone.trim(), password, options };
      const { data, error: authError } = await supabase.auth.signUp(credentials);
      if (authError) throw authError;
      if (!email.trim() && phone.trim() && !data.session) {
        setAwaitingPhoneOtp(true);
        setMessage("Telefonuna gelen doğrulama kodunu gir.");
      } else {
        if (data.session) await supabase.auth.signOut();
        const registeredIdentity=email.trim()||phone.trim();
        setIdentity(registeredIdentity);
        setPassword("");
        setFullName("");
        setEmail("");
        setPhone("");
        setMode("login");
        setMessage(data.session
          ? "Üyeliğin oluşturuldu. Şimdi giriş yapabilir ve klinik davet kodunu girebilirsin."
          : `${t.verificationSent} Doğruladıktan sonra giriş yapıp klinik davet kodunu kullanabilirsin.`);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "Kayıt oluşturulamadı.");
    } finally { setLoading(false); }
  }

  async function verifyPhone() {
    setError(""); setLoading(true);
    try {
      const supabase = createClient();
      const { error: verifyError } = await supabase.auth.verifyOtp({ phone: phone.trim(), token: otp.trim(), type: "sms" });
      if (verifyError) throw verifyError;
      await supabase.auth.signOut();
      setAwaitingPhoneOtp(false);
      setIdentity(phone.trim());
      setPassword("");
      setOtp("");
      setMode("login");
      setMessage("Telefon doğrulandı. Şimdi şifrenle giriş yapabilirsin.");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Kod doğrulanamadı.");
    } finally { setLoading(false); }
  }

  if (!configured) {
    return (
      <LocalizedContent locale={locale} className="localized-app-root">
      <main className="auth-page single">
        <section className="auth-card setup-card">
          <div className="brand"><span><Apple size={22}/></span><b>NutriClinic AI</b></div>
          <h1>{t.setupRequired}</h1>
          <p>{t.setupRequiredText}</p>
          <code>NEXT_PUBLIC_SUPABASE_URL<br/>NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY</code>
          <p className="hint">Ayrıntılar proje içindeki README.md dosyasında bulunuyor.</p>
        </section>
      </main>
      </LocalizedContent>
    );
  }

  return (
    <LocalizedContent locale={locale} className="localized-app-root">
    <main className="auth-page">
      <section className="auth-hero">
        <div className="brand light"><span><Apple size={23}/></span><b>NutriClinic AI</b></div>
        <div>
          <small>AKILLI KLİNİK YÖNETİMİ</small>
          <h1>Kliniğiniz, danışanlarınız ve beslenme süreçleri tek platformda.</h1>
          <p>Gerçek kullanıcı hesapları, güvenli rol yönetimi, randevular, ölçümler ve kişiye özel beslenme planları.</p>
        </div>
        <div className="trust-row"><ShieldCheck size={18}/> Herkes hesap oluşturabilir; klinik ve rol erişimi yalnızca güvenli davetle etkinleşir.</div>
      </section>
      <section className="auth-panel">
        <div className="auth-card">
          <div className="auth-top">
            <div className="brand"><span><Apple size={21}/></span><b>NutriClinic AI</b></div>
            <label className="language-picker"><Languages size={16}/><select value={locale} onChange={(e) => setLocale(e.target.value as Locale)}>{locales.map((l)=><option value={l} key={l}>{localeLabels[l]}</option>)}</select></label>
          </div>
          {(pilotToken || inviteToken || platformSetupAllowed) && <div className="auth-invite-context">
            <ShieldCheck size={17}/>
            <div><b>{platformSetupAllowed ? "Platform yöneticisi kurulumu" : pilotToken ? "Pilot klinik daveti" : "Klinik katılım daveti"}</b><small>{platformSetupAllowed ? "Yalnızca PLATFORM_ADMIN_EMAILS içinde tanımlı e-posta ile devam edin." : "Giriş veya kayıt tamamlandıktan sonra davet kodunuz otomatik olarak uygulanacak."}</small></div>
          </div>}
          <div className="auth-tabs">
            <button className={mode === "login" ? "active" : ""} onClick={() => { setMode("login"); setError(""); setMessage(""); }}>{t.signIn}</button>
            <button className={mode === "register" ? "active" : ""} onClick={() => { setMode("register"); setError(""); setMessage(""); }}>{t.signUp}</button>
          </div>
          {!pilotToken && !inviteToken && !platformSetupAllowed && <div className="auth-registration-locked public"><ShieldCheck size={16}/><span>Herkes hesap oluşturabilir. Klinik Sahibi, Diyetisyen, Sekreter ve Danışan yetkileri klinik daveti veya pilot onayıyla güvenli biçimde etkinleşir.</span></div>}

          {mode === "login" ? (
            <form className="form-stack" onSubmit={(event)=>{event.preventDefault();void signIn();}}>
              <label>{t.authIdentity}<input value={identity} onChange={(e)=>setIdentity(e.target.value)} placeholder="ornek@mail.com veya +905..." autoComplete="username"/></label>
              <label>{t.password}<input type="password" value={password} onChange={(e)=>setPassword(e.target.value)} autoComplete="current-password"/></label>
              <button type="submit" className="primary-button" disabled={loading || !identity || !password}>{loading ? "..." : t.signIn}<ArrowRight size={17}/></button>
            </form>
          ) : awaitingPhoneOtp ? (
            <form className="form-stack" onSubmit={(event)=>{event.preventDefault();void verifyPhone();}}>
              <label>SMS doğrulama kodu<input inputMode="numeric" value={otp} onChange={(e)=>setOtp(e.target.value)} maxLength={8}/></label>
              <button type="submit" className="primary-button" disabled={loading || !otp}>Kodu doğrula<ArrowRight size={17}/></button>
            </form>
          ) : (
            <form className="form-stack" onSubmit={(event)=>{event.preventDefault();void signUp();}}>
              <label>{t.fullName}<input value={fullName} onChange={(e)=>setFullName(e.target.value)} autoComplete="name"/></label>
              <label>Hesabı hangi amaçla açıyorsunuz?<select value={accountIntent} onChange={(e)=>setAccountIntent(e.target.value)}><option value="client">Danışan olarak katılacağım</option><option value="dietitian">Diyetisyen olarak bir kliniğe katılacağım</option><option value="secretary">Sekreter olarak bir kliniğe katılacağım</option><option value="clinic_owner">Klinik sahibi / bağımsız diyetisyenim</option></select><small>Bu seçim doğrudan yetki vermez; rolünüz klinik daveti veya pilot onayıyla etkinleşir.</small></label>
              <div className="two-col">
                <label>{t.email}<input type="email" value={email} onChange={(e)=>setEmail(e.target.value)} autoComplete="email" placeholder="Varsa"/></label>
                <label>{t.phone}<input value={phone} onChange={(e)=>setPhone(e.target.value)} autoComplete="tel" placeholder="Varsa"/></label>
              </div>
              <label>{t.password}<input type="password" value={password} onChange={(e)=>setPassword(e.target.value)} autoComplete="new-password"/><small>{t.passwordHint}</small></label>
              <div className="info-box"><CheckCircle2 size={17}/><span>{pilotToken || inviteToken ? "Kayıt tamamlandığında davetiniz otomatik uygulanacak." : "Kayıt sonrası klinik davet kodunuzu girebilir veya klinik sahibiyseniz pilot başvurusu yapabilirsiniz."}</span></div>
              {accountIntent === "clinic_owner" && !pilotToken && <a className="secondary-button auth-pilot-link" href="/pilot-application">Pilot klinik başvurusu yap</a>}
              <button type="submit" className="primary-button" disabled={loading}>{loading ? "..." : t.signUp}<ArrowRight size={17}/></button>
            </form>
          )}
          {error && <p className="form-message error">{error}</p>}
          {message && <p className="form-message success">{message}</p>}
        </div>
      </section>
    </main>
    </LocalizedContent>
  );
}
