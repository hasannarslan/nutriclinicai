"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { ArrowLeft, Building2, CalendarClock, CheckCircle2, Clipboard, ClipboardList, ExternalLink, FlaskConical, Link2, Mail, MessageSquareText, RefreshCw, ShieldCheck, UsersRound } from "lucide-react";

type ClinicRow = {
  id: string; name: string; slug: string; status: string; default_locale: string; timezone: string; created_at: string;
  subscription: { plan_slug: string; status: string; pilot_started_at: string | null; pilot_ends_at: string | null } | null;
  memberships: { owners: number; dietitians: number; secretaries: number; total: number };
  active_clients: number;
};
type PilotInvite = { id: string; token: string; label: string; contact_email: string | null; pilot_days: number; max_uses: number; used_count: number; expires_at: string; is_active: boolean; created_at: string };
type PilotApplication = { id: string; full_name: string; email: string; phone: string | null; applicant_type: string; clinic_name: string | null; city: string | null; team_size: number; active_client_count: number; uses_devices: boolean; message: string | null; status: string; admin_note: string | null; created_at: string };
type Feedback = { id: string; clinic_id: string; category: string; rating: number | null; message: string; page_path: string | null; status: string; admin_note: string | null; created_at: string };
type Plan = { slug: string; name: string; monthly_price_try: number | null; max_dietitians: number; max_staff: number; max_active_clients: number };
type Payload = { clinics: ClinicRow[]; pilotInvites: PilotInvite[]; pilotApplications: PilotApplication[]; feedback: Feedback[]; plans: Plan[]; metrics: { clinics: number; pilotClinics: number; activeUsers: number; activeClients: number; openFeedback: number; openApplications: number } };

function date(value: string | null) {
  return value ? new Intl.DateTimeFormat("tr-TR", { dateStyle: "medium" }).format(new Date(value)) : "—";
}
function daysLeft(value: string | null) {
  if (!value) return null;
  return Math.ceil((new Date(value).getTime() - Date.now()) / 86400000);
}

export default function PlatformAdminClient({ email }: { email: string }) {
  const [data, setData] = useState<Payload | null>(null);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState("");
  const [tab, setTab] = useState<"clinics" | "applications" | "invites" | "feedback">("clinics");
  const [inviteForm, setInviteForm] = useState({ label: "", contact_email: "", pilot_days: "90", expires_days: "14", max_uses: "1" });
  const [lastCreatedInvite, setLastCreatedInvite] = useState<PilotInvite | null>(null);
  const configuredAppUrl = useMemo(() => (process.env.NEXT_PUBLIC_APP_URL || "").replace(/\/$/, ""), []);
  const [appUrl, setAppUrl] = useState(configuredAppUrl);
  useEffect(() => {
    if (!configuredAppUrl && typeof window !== "undefined") setAppUrl(window.location.origin.replace(/\/$/, ""));
  }, [configuredAppUrl]);
  const pilotLink = useCallback((token: string) => `${appUrl}/login?pilot=${encodeURIComponent(token)}`, [appUrl]);

  const load = useCallback(async () => {
    setLoading(true); setMessage("");
    const response = await fetch("/api/platform/admin", { cache: "no-store" });
    const payload = await response.json();
    setLoading(false);
    if (!response.ok) return setMessage(payload.error || "Veriler alınamadı");
    setData(payload as Payload);
  }, []);
  useEffect(() => { void load(); }, [load]);

  async function action(body: Record<string, unknown>, success: string) {
    setMessage("");
    const response = await fetch("/api/platform/admin", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
    const payload = await response.json();
    if (!response.ok) return setMessage(payload.error || "İşlem başarısız");
    setMessage(success);
    await load();
    return payload;
  }

  async function copyPilotLink(token: string) {
    const link = pilotLink(token);
    try {
      await navigator.clipboard.writeText(link);
      setMessage("Özel pilot bağlantısı panoya kopyalandı.");
    } catch {
      const field = document.createElement("textarea");
      field.value = link;
      field.style.position = "fixed";
      field.style.opacity = "0";
      document.body.appendChild(field);
      field.select();
      document.execCommand("copy");
      field.remove();
      setMessage("Özel pilot bağlantısı panoya kopyalandı.");
    }
  }

  async function createInvite() {
    const payload = await action({ action: "create_pilot_invite", ...inviteForm }, "Pilot daveti oluşturuldu.") as { invite?: PilotInvite } | undefined;
    if (payload?.invite) {
      setLastCreatedInvite(payload.invite);
      setInviteForm({ label: "", contact_email: "", pilot_days: "90", expires_days: "14", max_uses: "1" });
      await copyPilotLink(payload.invite.token);
      setMessage("Pilot kliniğe özel bağlantı oluşturuldu ve panoya kopyalandı.");
    }
  }

  return (
    <main className="platform-admin-page">
      <header className="platform-admin-header">
        <div><span className="section-kicker">NUTRICLINIC AI PLATFORM</span><h1>Global Yönetim</h1><p>{email} · Pilot klinikler, planlar ve geri bildirimler</p></div>
        <div className="platform-admin-actions"><a className="secondary-button compact" href="/dashboard"><ArrowLeft size={15}/>Kliniğe dön</a><button className="secondary-button compact" onClick={load}><RefreshCw size={15}/>Yenile</button></div>
      </header>

      {message && <div className="notice-bar"><span>{message}</span></div>}
      {loading || !data ? <div className="center-state"><RefreshCw className="spin"/><p>Platform verileri yükleniyor…</p></div> : <>
        <section className="platform-metrics">
          <article><Building2/><span>Toplam klinik<strong>{data.metrics.clinics}</strong></span></article>
          <article><FlaskConical/><span>Pilot klinik<strong>{data.metrics.pilotClinics}</strong></span></article>
          <article><UsersRound/><span>Aktif kullanıcı<strong>{data.metrics.activeUsers}</strong></span></article>
          <article><ShieldCheck/><span>Aktif danışan<strong>{data.metrics.activeClients}</strong></span></article>
          <article><ClipboardList/><span>Yeni başvuru<strong>{data.metrics.openApplications}</strong></span></article><article><MessageSquareText/><span>Açık geri bildirim<strong>{data.metrics.openFeedback}</strong></span></article>
        </section>

        <nav className="platform-tabs">
          <button className={tab === "clinics" ? "active" : ""} onClick={() => setTab("clinics")}>Klinikler</button>
          <button className={tab === "applications" ? "active" : ""} onClick={() => setTab("applications")}>Pilot başvuruları</button>
          <button className={tab === "invites" ? "active" : ""} onClick={() => setTab("invites")}>Pilot davetleri</button>
          <button className={tab === "feedback" ? "active" : ""} onClick={() => setTab("feedback")}>Geri bildirimler</button>
        </nav>

        {tab === "clinics" && <section className="surface-card platform-table-card">
          <div className="surface-head"><div><span className="section-kicker">TENANT YÖNETİMİ</span><h3>Klinik workspace’leri</h3><p>Her klinik ayrı tenant olarak izlenir. Pilot süresini uzatabilir, planını veya erişim durumunu değiştirebilirsiniz.</p></div></div>
          <div className="table-wrap modern-table-wrap"><table className="modern-table"><thead><tr><th>Klinik</th><th>Plan / pilot</th><th>Kullanım</th><th>Durum</th><th>İşlemler</th></tr></thead><tbody>{data.clinics.map((clinic) => {
            const remaining = daysLeft(clinic.subscription?.pilot_ends_at || null);
            return <tr key={clinic.id}><td><b>{clinic.name}</b><small>{clinic.slug}<br/>{date(clinic.created_at)}</small></td><td><span className="role-badge owner">{clinic.subscription?.plan_slug || "—"}</span><small>{clinic.subscription?.pilot_ends_at ? `${date(clinic.subscription.pilot_ends_at)} · ${remaining !== null ? `${remaining} gün` : ""}` : "Süre yok"}</small></td><td><small>{clinic.memberships.owners + clinic.memberships.dietitians} diyetisyen/owner<br/>{clinic.memberships.secretaries} sekreter · {clinic.active_clients} danışan</small></td><td><span className={`status-badge ${clinic.status}`}>{clinic.status}</span></td><td><div className="platform-row-actions"><button onClick={() => action({ action: "extend_pilot", clinic_id: clinic.id, days: 30 }, "Pilot 30 gün uzatıldı.")}><CalendarClock size={14}/>+30 gün</button><select value={clinic.subscription?.plan_slug || "pilot"} onChange={(event) => action({ action: "change_plan", clinic_id: clinic.id, plan_slug: event.target.value }, "Plan güncellendi.")}>{data.plans.map((plan) => <option value={plan.slug} key={plan.slug}>{plan.name}</option>)}</select><select value={clinic.status} onChange={(event) => action({ action: "set_clinic_status", clinic_id: clinic.id, status: event.target.value }, "Klinik durumu güncellendi.")}><option value="pilot">Pilot</option><option value="active">Aktif</option><option value="paused">Duraklatıldı</option><option value="expired">Süresi doldu</option><option value="cancelled">İptal</option></select></div></td></tr>;
          })}</tbody></table></div>
        </section>}


        {tab === "applications" && <section className="surface-card platform-table-card">
          <div className="surface-head"><div><span className="section-kicker">PİLOT TALEPLERİ</span><h3>Web sitesinden gelen başvurular</h3><p>Başvuruyu inceleyin; uygun gördüğünüz kişiye özel pilot daveti oluşturun.</p></div></div>
          {data.pilotApplications.length === 0 ? <p className="muted-line">Henüz pilot başvurusu yok.</p> : <div className="table-wrap modern-table-wrap"><table className="modern-table"><thead><tr><th>Başvuran</th><th>Klinik / kullanım</th><th>Mesaj</th><th>Durum</th><th>İşlemler</th></tr></thead><tbody>{data.pilotApplications.map((item) => <tr key={item.id}><td><b>{item.full_name}</b><small><a href={`mailto:${item.email}`}>{item.email}</a><br/>{item.phone || "Telefon yok"}<br/>{date(item.created_at)}</small></td><td><b>{item.clinic_name || "Klinik adı yok"}</b><small>{item.city || "Konum yok"}<br/>{item.team_size} kişilik ekip · {item.active_client_count} danışan<br/>{item.uses_devices ? "Cihaz kullanıyor" : "Cihaz kullanmıyor"}</small></td><td><small>{item.message || "Not bırakılmadı."}</small></td><td><span className={`status-badge ${item.status}`}>{item.status}</span></td><td><div className="platform-row-actions"><select value={item.status} onChange={(event) => action({ action: "update_pilot_application", application_id: item.id, status: event.target.value, admin_note: item.admin_note }, "Başvuru durumu güncellendi.")}><option value="new">Yeni</option><option value="contacted">İletişime geçildi</option><option value="approved">Onaylandı</option><option value="waitlist">Bekleme listesi</option><option value="rejected">Reddedildi</option><option value="closed">Kapandı</option></select><button onClick={() => { setInviteForm({ label: item.clinic_name || item.full_name, contact_email: item.email, pilot_days: "90", expires_days: "14", max_uses: "1" }); setTab("invites"); }}><Link2 size={14}/>Davet hazırla</button><a href={`mailto:${item.email}?subject=NutriClinic AI Pilot Programı`}><Mail size={14}/>E-posta</a></div></td></tr>)}</tbody></table></div>}
        </section>}

        {tab === "invites" && <div className="platform-two-column">
          <section className="surface-card"><div className="surface-head"><div><span className="section-kicker">DAVETLİ PİLOT</span><h3>Pilot kliniğe özel bağlantı oluştur</h3><p>Her klinik için benzersiz ve paylaşılabilir bir kayıt bağlantısı üretin. Bağlantı yalnızca belirlediğiniz kullanım ve tarih sınırlarında çalışır.</p></div></div><div className="form-grid"><label>Pilot etiketi<input value={inviteForm.label} onChange={(event) => setInviteForm({ ...inviteForm, label: event.target.value })} placeholder="Örn. Dr. Ayşe Beslenme Kliniği"/></label><label>Kısıtlı e-posta (isteğe bağlı)<input type="email" value={inviteForm.contact_email} onChange={(event) => setInviteForm({ ...inviteForm, contact_email: event.target.value })}/></label><label>Pilot süresi (gün)<input type="number" min="7" max="365" value={inviteForm.pilot_days} onChange={(event) => setInviteForm({ ...inviteForm, pilot_days: event.target.value })}/></label><label>Bağlantı geçerliliği (gün)<input type="number" min="1" max="90" value={inviteForm.expires_days} onChange={(event) => setInviteForm({ ...inviteForm, expires_days: event.target.value })}/></label><label>Maksimum kullanım<input type="number" min="1" max="20" value={inviteForm.max_uses} onChange={(event) => setInviteForm({ ...inviteForm, max_uses: event.target.value })}/></label></div><button className="primary-button" onClick={createInvite}><Link2 size={16}/>Özel pilot bağlantısı oluştur</button>{lastCreatedInvite && <div className="pilot-link-result"><div className="pilot-link-result-head"><CheckCircle2 size={21}/><div><b>{lastCreatedInvite.label} için bağlantı hazır</b><small>Bu bağlantıyı doğrudan pilot kliniğin sahibine gönderin.</small></div></div><div className="pilot-link-field"><input readOnly value={pilotLink(lastCreatedInvite.token)} aria-label="Oluşturulan özel pilot bağlantısı"/><button type="button" onClick={() => copyPilotLink(lastCreatedInvite.token)}><Clipboard size={15}/>Kopyala</button><a href={pilotLink(lastCreatedInvite.token)} target="_blank" rel="noreferrer"><ExternalLink size={15}/>Aç</a></div></div>}</section>
          <section className="surface-card"><div className="surface-head"><div><span className="section-kicker">ÖZEL BAĞLANTILAR</span><h3>Pilot klinik bağlantıları</h3></div></div><div className="platform-invite-list">{data.pilotInvites.map((invite) => <article key={invite.id} className={!invite.is_active ? "inactive" : ""}><div className="platform-invite-main"><b>{invite.label}</b><a className="platform-pilot-url" href={pilotLink(invite.token)} target="_blank" rel="noreferrer">{pilotLink(invite.token)}</a><small>{invite.contact_email || "E-posta kısıtı yok"} · {invite.used_count}/{invite.max_uses} kullanım · Son tarih: {date(invite.expires_at)}</small></div><div className="platform-invite-actions"><button title="Özel bağlantıyı kopyala" onClick={() => copyPilotLink(invite.token)}><Clipboard size={15}/>Kopyala</button><a title="Bağlantıyı aç" href={pilotLink(invite.token)} target="_blank" rel="noreferrer"><ExternalLink size={15}/>Aç</a><button onClick={() => action({ action: "set_invite_active", invite_id: invite.id, is_active: !invite.is_active }, invite.is_active ? "Davet pasif yapıldı." : "Davet aktifleştirildi.")}>{invite.is_active ? "Pasif yap" : "Aktifleştir"}</button></div></article>)}</div></section>
        </div>}

        {tab === "feedback" && <section className="surface-card platform-feedback-list"><div className="surface-head"><div><span className="section-kicker">PİLOT GERİ BİLDİRİMİ</span><h3>Kliniklerden gelen kayıtlar</h3></div></div>{data.feedback.length === 0 ? <p className="muted-line">Henüz geri bildirim yok.</p> : data.feedback.map((item) => <article key={item.id}><div className="platform-feedback-meta"><span className="viz-badge">{item.category}</span><b>{item.rating ? `${item.rating}/5` : "Puan yok"}</b><small>{date(item.created_at)}</small></div><p>{item.message}</p><small>{item.page_path || "Sayfa bilgisi yok"}</small><div className="platform-feedback-actions"><select value={item.status} onChange={(event) => action({ action: "update_feedback", feedback_id: item.id, status: event.target.value, admin_note: item.admin_note }, "Geri bildirim durumu güncellendi.")}><option value="new">Yeni</option><option value="reviewing">İnceleniyor</option><option value="planned">Planlandı</option><option value="resolved">Çözüldü</option><option value="closed">Kapandı</option></select></div></article>)}</section>}
      </>}
    </main>
  );
}
