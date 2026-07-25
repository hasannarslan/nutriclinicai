"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { AlertTriangle, CheckCircle2, FlaskConical, LogOut, MessageSquarePlus, Send, ShieldAlert, X } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import type { Role } from "@/lib/types";

type SaasContext = {
  clinic_status: string;
  plan_name: string;
  plan_slug: string;
  subscription_status: string;
  pilot_ends_at: string | null;
  days_remaining: number | null;
  limits: { dietitians: number; staff: number; active_clients: number; ai_credits: number; storage_gb: number };
  usage: { dietitians: number; staff: number; active_clients: number; ai_requests: number };
};

export function SaasPilotBanner({ role }: { role: Role }) {
  const supabase = useMemo(() => createClient(), []);
  const [context, setContext] = useState<SaasContext | null>(null);

  useEffect(() => {
    let active = true;
    (async () => {
      const { data } = await supabase.rpc("get_saas_context_v7");
      if (active && data) setContext(data as SaasContext);
    })();
    return () => { active = false; };
  }, [supabase]);

  if (!context || role === "client") return null;
  const endingSoon = context.days_remaining !== null && context.days_remaining <= 14;
  const expired = context.subscription_status === "expired" || context.clinic_status === "expired";

  return (
    <section className={`saas-pilot-banner ${endingSoon ? "warning" : ""} ${expired ? "expired" : ""}`}>
      <div className="saas-pilot-icon">{expired ? <AlertTriangle size={22}/> : <FlaskConical size={22}/>}</div>
      <div className="saas-pilot-copy">
        <b>{context.plan_name} · {context.subscription_status === "pilot" ? "Ücretsiz pilot" : context.subscription_status}</b>
        <p>{expired
          ? "Pilot erişim süresi sona erdi. Veriler korunuyor; devam etmek için platform yöneticisiyle görüşün."
          : context.days_remaining !== null
            ? `Pilot erişimin bitmesine ${context.days_remaining} gün kaldı. Pilot süresince geri bildirimleriniz ürün yol haritasına doğrudan girer.`
            : "Klinik planınız aktif."}</p>
      </div>
      <div className="saas-usage-chips">
        <span>Diyetisyen <b>{context.usage.dietitians}/{context.limits.dietitians}</b></span>
        <span>Personel <b>{context.usage.staff}/{context.limits.staff}</b></span>
        <span>Danışan <b>{context.usage.active_clients}/{context.limits.active_clients}</b></span>
        <span>AI <b>{context.usage.ai_requests}/{context.limits.ai_credits}</b></span>
      </div>
    </section>
  );
}


export function SaasAccessGate({ isPlatformAdmin = false }: { isPlatformAdmin?: boolean }) {
  const supabase = useMemo(() => createClient(), []);
  const [context, setContext] = useState<SaasContext | null>(null);

  useEffect(() => {
    let active = true;
    (async () => {
      const { data } = await supabase.rpc("get_saas_context_v7");
      if (active && data) setContext(data as SaasContext);
    })();
    return () => { active = false; };
  }, [supabase]);

  if (!context) return null;
  const pilotTimeExpired = Boolean(context.pilot_ends_at && new Date(context.pilot_ends_at).getTime() < Date.now());
  const blocked = pilotTimeExpired || ["paused", "expired", "cancelled"].includes(context.subscription_status) || ["paused", "expired", "cancelled"].includes(context.clinic_status);
  if (!blocked) return null;

  async function signOut() {
    await supabase.auth.signOut();
    window.location.assign("/login");
  }

  return <div className="saas-access-gate" role="dialog" aria-modal="true">
    <section>
      <span className="saas-access-icon"><ShieldAlert size={30}/></span>
      <span className="section-kicker">KLİNİK ERİŞİMİ</span>
      <h2>{context.subscription_status === "paused" || context.clinic_status === "paused" ? "Klinik hesabı geçici olarak duraklatıldı" : "Ücretsiz pilot süresi sona erdi"}</h2>
      <p>Klinik verileri korunmaya devam ediyor. Kullanımı yeniden açmak veya ücretli plana geçmek için NutriClinic AI platform yöneticisiyle iletişime geçin.</p>
      <div className="saas-access-actions">
        {isPlatformAdmin && <a className="primary-button" href="/platform-admin">Platform yönetimine git</a>}
        <button type="button" className="secondary-button" onClick={signOut}><LogOut size={16}/>Çıkış yap</button>
      </div>
    </section>
  </div>;
}

export function PilotFeedback({ role }: { role: Role }) {
  const supabase = useMemo(() => createClient(), []);
  const [open, setOpen] = useState(false);
  const [category, setCategory] = useState("general");
  const [rating, setRating] = useState(5);
  const [message, setMessage] = useState("");
  const [status, setStatus] = useState("");
  const [busy, setBusy] = useState(false);

  const submit = useCallback(async () => {
    if (message.trim().length < 3) return setStatus("Lütfen geri bildiriminizi biraz daha ayrıntılı yazın.");
    setBusy(true); setStatus("");
    const { error } = await supabase.rpc("submit_pilot_feedback_v7", {
      p_category: category,
      p_rating: rating,
      p_message: message.trim(),
      p_page_path: window.location.pathname + window.location.search,
    });
    setBusy(false);
    if (error) return setStatus(error.message);
    setStatus("Geri bildiriminiz kaydedildi. Teşekkür ederiz.");
    setMessage("");
    setTimeout(() => { setOpen(false); setStatus(""); }, 1200);
  }, [category, message, rating, supabase]);

  if (role === "client") return null;
  return (
    <>
      <button type="button" className="pilot-feedback-fab" onClick={() => setOpen(true)}><MessageSquarePlus size={18}/>Pilot geri bildirimi</button>
      {open && <div className="pilot-feedback-overlay" role="dialog" aria-modal="true">
        <section className="pilot-feedback-modal">
          <button type="button" className="pilot-feedback-close" onClick={() => setOpen(false)} aria-label="Kapat"><X size={18}/></button>
          <span className="section-kicker">PİLOT PROGRAMI</span>
          <h2>Deneyiminizi doğrudan ürün ekibine iletin</h2>
          <p>Hata, kullanım zorluğu veya özellik önerisini yazın. Pilot klinik geri bildirimleri öncelikli değerlendirilir.</p>
          <div className="form-grid">
            <label>Kategori<select value={category} onChange={(event) => setCategory(event.target.value)}><option value="general">Genel</option><option value="bug">Hata</option><option value="idea">Özellik fikri</option><option value="usability">Kullanılabilirlik</option><option value="support">Destek</option></select></label>
            <label>Deneyim puanı<select value={rating} onChange={(event) => setRating(Number(event.target.value))}>{[5,4,3,2,1].map((value) => <option key={value} value={value}>{value}/5</option>)}</select></label>
            <label className="wide">Mesaj<textarea rows={5} value={message} onChange={(event) => setMessage(event.target.value)} placeholder="Ne oldu, hangi ekrandaydı ve nasıl olmasını bekliyordunuz?"/></label>
          </div>
          {status && <div className="inline-message"><CheckCircle2 size={16}/>{status}</div>}
          <button type="button" className="primary-button" disabled={busy} onClick={submit}><Send size={16}/>{busy ? "Gönderiliyor…" : "Geri bildirimi gönder"}</button>
        </section>
      </div>}
    </>
  );
}
