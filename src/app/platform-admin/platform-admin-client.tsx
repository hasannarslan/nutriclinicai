"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  Activity, ArrowLeft, Banknote, Building2, CalendarClock, CheckCircle2, Clipboard, ClipboardList,
  CreditCard, ExternalLink, Eye, FileText, FlaskConical, Link2, Mail, MessageSquareText, RefreshCw,
  ShieldCheck, Stethoscope, UsersRound, Utensils, X,
} from "lucide-react";

type ConversionRequest = { id: string; clinic_id: string; requested_by: string; requested_plan_slug: string; note: string | null; status: string; reviewed_by_email: string | null; reviewed_at: string | null; admin_note: string | null; created_at: string; updated_at: string };
type ClinicRow = {
  id: string; name: string; slug: string; status: string; default_locale: string; timezone: string; created_at: string;
  subscription: { plan_slug: string; status: string; pilot_started_at: string | null; pilot_ends_at: string | null; current_period_started_at: string | null; current_period_ends_at: string | null; commercial_approved_at: string | null; commercial_approved_by_email: string | null; agreed_price_try: number | null; billing_cycle: string | null } | null;
  memberships: { owners: number; dietitians: number; secretaries: number; total: number };
  active_clients: number;
  conversion_request: ConversionRequest | null;
};
type PilotInvite = { id: string; token: string; label: string; contact_email: string | null; pilot_days: number; max_uses: number; used_count: number; expires_at: string; is_active: boolean; created_at: string };
type PilotApplication = { id: string; full_name: string; email: string; phone: string | null; applicant_type: string; clinic_name: string | null; city: string | null; team_size: number; active_client_count: number; uses_devices: boolean; message: string | null; status: string; admin_note: string | null; created_at: string };
type Feedback = { id: string; clinic_id: string; category: string; rating: number | null; message: string; page_path: string | null; status: string; admin_note: string | null; created_at: string };
type Plan = { slug: string; name: string; monthly_price_try: number | null; max_dietitians: number; max_staff: number; max_active_clients: number };
type Payload = { clinics: ClinicRow[]; pilotInvites: PilotInvite[]; pilotApplications: PilotApplication[]; feedback: Feedback[]; plans: Plan[]; conversionRequests: ConversionRequest[]; metrics: { clinics: number; pilotClinics: number; activeUsers: number; activeClients: number; openFeedback: number; openApplications: number; pendingConversions: number } };

type Member = { id: string; user_id: string; role: string; is_active: boolean; created_at: string; profile: { id: string; full_name: string; email: string | null; phone: string | null } | null };
type ClinicDetail = {
  clinic: { id: string; name: string; slug: string; status: string; default_locale: string; timezone: string; phone: string | null; email: string | null; website: string | null; address: string | null; created_at: string; onboarding_completed_at: string | null };
  subscription: ({ id: string; plan_slug: string; status: string; pilot_started_at: string | null; pilot_ends_at: string | null; current_period_started_at: string | null; current_period_ends_at: string | null; commercial_approved_at: string | null; commercial_approved_by_email: string | null; commercial_approval_note: string | null; agreed_price_try: number | null; billing_cycle: string | null; converted_from_pilot_at: string | null; plan: { slug: string; name: string; monthly_price_try: number | null } | null } | null);
  members: Member[];
  clients: Array<{ id: string; member_no: string; full_name: string; email: string | null; phone: string | null; is_active: boolean; created_at: string }>;
  resources: Array<{ id: string; name: string; resource_type: string; is_active: boolean; created_at: string }>;
  packages: Array<{ id: string; name: string; status: string; total_price: number; currency: string; created_at: string }>;
  feedback: Feedback[];
  conversionRequests: ConversionRequest[];
  notes: Array<{ id: string; note: string; created_by_email: string; created_at: string }>;
  audit: Array<{ id: number; action: string; target_type: string | null; metadata: Record<string, unknown>; created_at: string }>;
  stats: {
    members: { total: number; owners: number; dietitians: number; secretaries: number };
    clients: { active: number; total: number };
    appointments: { total: number; upcoming: number; completed: number; cancelled: number; no_show: number };
    mealPlans: { total: number; active: number };
    measurements: number;
    resources: { total: number; active: number };
    packages: { total: number; active: number };
    feedback: { total: number; open: number };
    financials: Array<{ currency: string; total: number; paid: number; remaining: number }>;
  };
};

function date(value: string | null) { return value ? new Intl.DateTimeFormat("tr-TR", { dateStyle: "medium" }).format(new Date(value)) : "—"; }
function dateTime(value: string | null) { return value ? new Intl.DateTimeFormat("tr-TR", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value)) : "—"; }
function daysLeft(value: string | null) { if (!value) return null; return Math.ceil((new Date(value).getTime() - Date.now()) / 86400000); }
function money(value: number | null | undefined, currency = "TRY") { return new Intl.NumberFormat("tr-TR", { style: "currency", currency, maximumFractionDigits: 2 }).format(Number(value || 0)); }
function roleLabel(role: string) { return ({ owner: "Klinik Sahibi", dietitian: "Diyetisyen", secretary: "Sekreter", client: "Danışan" } as Record<string, string>)[role] || role; }
function statusLabel(status: string) { return ({ pilot: "Ücretsiz Pilot", trialing: "Deneme", active: "Aktif", past_due: "Ödeme Gecikmiş", paused: "Duraklatıldı", expired: "Süresi Doldu", cancelled: "İptal Edildi" } as Record<string, string>)[status] || status; }

export default function PlatformAdminClient({ email }: { email: string }) {
  const [data, setData] = useState<Payload | null>(null);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState("");
  const [tab, setTab] = useState<"clinics" | "conversions" | "applications" | "invites" | "feedback">("clinics");
  const [inviteForm, setInviteForm] = useState({ label: "", contact_email: "", pilot_days: "90", expires_days: "14", max_uses: "1" });
  const [lastCreatedInvite, setLastCreatedInvite] = useState<PilotInvite | null>(null);
  const [selectedClinic, setSelectedClinic] = useState<ClinicRow | null>(null);
  const [clinicDetail, setClinicDetail] = useState<ClinicDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [pilotExtensionDays, setPilotExtensionDays] = useState("30");
  const [platformNote, setPlatformNote] = useState("");
  const [activationForm, setActivationForm] = useState({ plan_slug: "professional", billing_cycle: "monthly", agreed_price_try: "", approval_note: "" });
  const configuredAppUrl = useMemo(() => (process.env.NEXT_PUBLIC_APP_URL || "").replace(/\/$/, ""), []);
  const [appUrl, setAppUrl] = useState(configuredAppUrl);
  useEffect(() => { if (!configuredAppUrl && typeof window !== "undefined") setAppUrl(window.location.origin.replace(/\/$/, "")); }, [configuredAppUrl]);
  const pilotLink = useCallback((token: string) => `${appUrl}/login?pilot=${encodeURIComponent(token)}`, [appUrl]);

  const load = useCallback(async () => {
    setLoading(true); setMessage("");
    const response = await fetch("/api/platform/admin", { cache: "no-store" });
    const payload = await response.json().catch(() => ({ error: "Sunucu yanıtı okunamadı." }));
    setLoading(false);
    if (!response.ok) return setMessage(payload.error || "Veriler alınamadı");
    setData(payload as Payload);
  }, []);
  useEffect(() => { void load(); }, [load]);

  const loadClinicDetail = useCallback(async (clinic: ClinicRow) => {
    setSelectedClinic(clinic); setClinicDetail(null); setDetailLoading(true); setMessage("");
    const response = await fetch(`/api/platform/admin/clinic/${clinic.id}`, { cache: "no-store" });
    const payload = await response.json();
    setDetailLoading(false);
    if (!response.ok) return setMessage(payload.error || "Klinik detayları alınamadı");
    const detail = payload as ClinicDetail;
    setClinicDetail(detail);
    const request = detail.conversionRequests.find((item) => item.status === "pending") || detail.conversionRequests[0];
    const requestedPlanSlug = request?.requested_plan_slug || detail.subscription?.plan_slug || "professional";
    const effectivePlanSlug = ["pilot", "founder"].includes(requestedPlanSlug) ? "professional" : requestedPlanSlug;
    const plan = data?.plans.find((item) => item.slug === effectivePlanSlug);
    setActivationForm({
      plan_slug: effectivePlanSlug,
      billing_cycle: detail.subscription?.billing_cycle || "monthly",
      agreed_price_try: detail.subscription?.agreed_price_try !== null && detail.subscription?.agreed_price_try !== undefined ? String(detail.subscription.agreed_price_try) : plan?.monthly_price_try !== null && plan?.monthly_price_try !== undefined ? String(plan.monthly_price_try) : "",
      approval_note: request?.admin_note || detail.subscription?.commercial_approval_note || "",
    });
  }, [data?.plans]);

  async function action(body: Record<string, unknown>, success: string, refreshDetail = false) {
    setMessage("");
    const response = await fetch("/api/platform/admin", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
    const payload = await response.json();
    if (!response.ok) return setMessage(payload.error || "İşlem başarısız");
    setMessage(success);
    await load();
    if (refreshDetail && selectedClinic) await loadClinicDetail(selectedClinic);
    return payload;
  }

  async function copyPilotLink(token: string) {
    const link = pilotLink(token);
    try { await navigator.clipboard.writeText(link); setMessage("Özel pilot bağlantısı panoya kopyalandı."); }
    catch {
      const field = document.createElement("textarea"); field.value = link; field.style.position = "fixed"; field.style.opacity = "0"; document.body.appendChild(field); field.select(); document.execCommand("copy"); field.remove(); setMessage("Özel pilot bağlantısı panoya kopyalandı.");
    }
  }

  async function createInvite() {
    const payload = await action({ action: "create_pilot_invite", ...inviteForm }, "Pilot daveti oluşturuldu.") as { invite?: PilotInvite } | undefined;
    if (payload?.invite) { setLastCreatedInvite(payload.invite); setInviteForm({ label: "", contact_email: "", pilot_days: "90", expires_days: "14", max_uses: "1" }); await copyPilotLink(payload.invite.token); setMessage("Pilot kliniğe özel bağlantı oluşturuldu ve panoya kopyalandı."); }
  }

  async function approveClinic() {
    if (!selectedClinic || !clinicDetail) return;
    const pending = clinicDetail.conversionRequests.find((item) => item.status === "pending");
    if (!window.confirm(`${selectedClinic.name} kliniğini ${data?.plans.find((item) => item.slug === activationForm.plan_slug)?.name || activationForm.plan_slug} planında aktif etmek istediğinize emin misiniz?`)) return;
    await action({ action: "approve_paid_access", clinic_id: selectedClinic.id, request_id: pending?.id || null, ...activationForm }, "Klinik ücretli plana geçirildi ve erişimi onaylandı.", true);
  }

  const pendingConversions = data?.conversionRequests.filter((item) => item.status === "pending") || [];

  return <main className="platform-admin-page">
    <header className="platform-admin-header">
      <div><span className="section-kicker">NUTRICLINIC AI PLATFORM</span><h1>Global Yönetim</h1><p>{email} · Pilot klinikler, planlar, ticari onaylar ve geri bildirimler</p></div>
      <div className="platform-admin-actions"><a className="secondary-button compact" href="/dashboard"><ArrowLeft size={15}/>Kliniğe dön</a><button className="secondary-button compact" onClick={load}><RefreshCw size={15}/>Yenile</button></div>
    </header>

    {message && <div className="notice-bar platform-notice"><span>{message}</span></div>}
    {loading || !data ? <div className="center-state"><RefreshCw className="spin"/><p>Platform verileri yükleniyor…</p></div> : <>
      <section className="platform-metrics platform-metrics-v75">
        <article><Building2/><span>Toplam klinik<strong>{data.metrics.clinics}</strong></span></article>
        <article><FlaskConical/><span>Pilot klinik<strong>{data.metrics.pilotClinics}</strong></span></article>
        <article className={data.metrics.pendingConversions ? "attention" : ""}><CreditCard/><span>Geçiş talebi<strong>{data.metrics.pendingConversions}</strong></span></article>
        <article><UsersRound/><span>Aktif kullanıcı<strong>{data.metrics.activeUsers}</strong></span></article>
        <article><ShieldCheck/><span>Aktif danışan<strong>{data.metrics.activeClients}</strong></span></article>
        <article><ClipboardList/><span>Yeni başvuru<strong>{data.metrics.openApplications}</strong></span></article>
        <article><MessageSquareText/><span>Açık geri bildirim<strong>{data.metrics.openFeedback}</strong></span></article>
      </section>

      <nav className="platform-tabs">
        <button className={tab === "clinics" ? "active" : ""} onClick={() => setTab("clinics")}>Klinikler</button>
        <button className={tab === "conversions" ? "active" : ""} onClick={() => setTab("conversions")}>Geçiş talepleri {data.metrics.pendingConversions > 0 && <b>{data.metrics.pendingConversions}</b>}</button>
        <button className={tab === "applications" ? "active" : ""} onClick={() => setTab("applications")}>Pilot başvuruları</button>
        <button className={tab === "invites" ? "active" : ""} onClick={() => setTab("invites")}>Pilot davetleri</button>
        <button className={tab === "feedback" ? "active" : ""} onClick={() => setTab("feedback")}>Geri bildirimler</button>
      </nav>

      {tab === "clinics" && <section className="surface-card platform-table-card">
        <div className="surface-head"><div><span className="section-kicker">TENANT YÖNETİMİ</span><h3>Klinik workspace’leri</h3><p>Detay ekranından ekip, danışan, kullanım, finans, pilot geçmişi ve ücretli plan onayını yönetin.</p></div></div>
        <div className="table-wrap modern-table-wrap"><table className="modern-table"><thead><tr><th>Klinik</th><th>Plan / pilot</th><th>Kullanım</th><th>Durum</th><th>İşlemler</th></tr></thead><tbody>{data.clinics.map((clinic) => {
          const isPilot = clinic.subscription?.plan_slug === "pilot";
          const remaining = isPilot ? daysLeft(clinic.subscription?.pilot_ends_at || null) : null;
          const pending = clinic.conversion_request?.status === "pending";
          const periodText = isPilot && clinic.subscription?.pilot_ends_at
            ? `${date(clinic.subscription.pilot_ends_at)} · ${remaining !== null ? `${remaining} gün` : ""}`
            : clinic.subscription?.commercial_approved_at
              ? `Onay: ${date(clinic.subscription.commercial_approved_at)}`
              : clinic.subscription?.current_period_ends_at
                ? `Dönem sonu: ${date(clinic.subscription.current_period_ends_at)}`
                : clinic.subscription?.plan_slug === "founder" ? "Süresiz kurucu erişimi" : "Dönem bilgisi yok";
          return <tr key={clinic.id} className={pending ? "platform-pending-row" : ""}><td><b>{clinic.name}</b><small>{clinic.slug}<br/>{date(clinic.created_at)}</small>{pending && <span className="conversion-request-badge">Ücretli devam talebi</span>}</td><td><span className="role-badge owner">{clinic.subscription?.plan_slug || "—"}</span><small>{periodText}</small></td><td><small>{clinic.memberships.owners + clinic.memberships.dietitians} diyetisyen/owner<br/>{clinic.memberships.secretaries} sekreter · {clinic.active_clients} danışan</small></td><td><span className={`status-badge ${clinic.status}`}>{statusLabel(clinic.status)}</span></td><td><div className="platform-row-actions"><button className="platform-detail-button" onClick={() => void loadClinicDetail(clinic)}><Eye size={14}/>Detayları gör</button>{isPilot && <button onClick={() => action({ action: "extend_pilot", clinic_id: clinic.id, days: 30 }, "Pilot 30 gün uzatıldı.")}><CalendarClock size={14}/>+30 gün</button>}<select value={clinic.status} onChange={(event) => action({ action: "set_clinic_status", clinic_id: clinic.id, status: event.target.value }, "Klinik durumu güncellendi.")}>{clinic.status === "pilot" && <option value="pilot" disabled>Pilot (süre yönetimi)</option>}<option value="active">Aktif</option><option value="paused">Duraklatıldı</option><option value="expired">Süresi doldu</option><option value="cancelled">İptal</option></select></div></td></tr>;
        })}</tbody></table></div>
      </section>}

      {tab === "conversions" && <section className="surface-card platform-table-card">
        <div className="surface-head"><div><span className="section-kicker">PİLOT → ÜCRETLİ</span><h3>Platform Admin onayı bekleyen klinikler</h3><p>Klinik Sahibinin plan tercihini ve notunu inceleyip kliniği ücretli plana geçirin.</p></div></div>
        {pendingConversions.length === 0 ? <div className="platform-empty-state"><CheckCircle2 size={28}/><b>Bekleyen geçiş talebi yok</b><p>Yeni bir klinik ücretli devam talebi gönderdiğinde burada görünecek.</p></div> : <div className="table-wrap modern-table-wrap"><table className="modern-table"><thead><tr><th>Klinik</th><th>Talep edilen plan</th><th>Not</th><th>Tarih</th><th>İşlem</th></tr></thead><tbody>{pendingConversions.map((request) => {
          const clinic = data.clinics.find((item) => item.id === request.clinic_id);
          return <tr key={request.id}><td><b>{clinic?.name || request.clinic_id}</b><small>{clinic?.slug || ""}</small></td><td><span className="role-badge owner">{data.plans.find((item) => item.slug === request.requested_plan_slug)?.name || request.requested_plan_slug}</span></td><td><small>{request.note || "Not bırakılmadı."}</small></td><td>{dateTime(request.created_at)}</td><td><button className="primary-button compact" onClick={() => clinic && void loadClinicDetail(clinic)}><Eye size={14}/>İncele ve onayla</button></td></tr>;
        })}</tbody></table></div>}
      </section>}

      {tab === "applications" && <section className="surface-card platform-table-card">
        <div className="surface-head"><div><span className="section-kicker">PİLOT TALEPLERİ</span><h3>Web sitesinden gelen başvurular</h3><p>Başvuruyu inceleyin; uygun gördüğünüz kişiye özel pilot daveti oluşturun.</p></div></div>
        {data.pilotApplications.length === 0 ? <p className="muted-line">Henüz pilot başvurusu yok.</p> : <div className="table-wrap modern-table-wrap"><table className="modern-table"><thead><tr><th>Başvuran</th><th>Klinik / kullanım</th><th>Mesaj</th><th>Durum</th><th>İşlemler</th></tr></thead><tbody>{data.pilotApplications.map((item) => <tr key={item.id}><td><b>{item.full_name}</b><small><a href={`mailto:${item.email}`}>{item.email}</a><br/>{item.phone || "Telefon yok"}<br/>{date(item.created_at)}</small></td><td><b>{item.clinic_name || "Klinik adı yok"}</b><small>{item.city || "Konum yok"}<br/>{item.team_size} kişilik ekip · {item.active_client_count} danışan<br/>{item.uses_devices ? "Cihaz kullanıyor" : "Cihaz kullanmıyor"}</small></td><td><small>{item.message || "Not bırakılmadı."}</small></td><td><span className={`status-badge ${item.status}`}>{item.status}</span></td><td><div className="platform-row-actions"><select value={item.status} onChange={(event) => action({ action: "update_pilot_application", application_id: item.id, status: event.target.value, admin_note: item.admin_note }, "Başvuru durumu güncellendi.")}><option value="new">Yeni</option><option value="contacted">İletişime geçildi</option><option value="approved">Onaylandı</option><option value="waitlist">Bekleme listesi</option><option value="rejected">Reddedildi</option><option value="closed">Kapandı</option></select><button onClick={() => { setInviteForm({ label: item.clinic_name || item.full_name, contact_email: item.email, pilot_days: "90", expires_days: "14", max_uses: "1" }); setTab("invites"); }}><Link2 size={14}/>Davet hazırla</button><a href={`mailto:${item.email}?subject=NutriClinic AI Pilot Programı`}><Mail size={14}/>E-posta</a></div></td></tr>)}</tbody></table></div>}
      </section>}

      {tab === "invites" && <div className="platform-two-column">
        <section className="surface-card"><div className="surface-head"><div><span className="section-kicker">DAVETLİ PİLOT</span><h3>Pilot kliniğe özel bağlantı oluştur</h3><p>Her klinik için benzersiz ve paylaşılabilir bir kayıt bağlantısı üretin.</p></div></div><div className="form-grid"><label>Pilot etiketi<input value={inviteForm.label} onChange={(event) => setInviteForm({ ...inviteForm, label: event.target.value })} placeholder="Örn. Dr. Ayşe Beslenme Kliniği"/></label><label>Kısıtlı e-posta (isteğe bağlı)<input type="email" value={inviteForm.contact_email} onChange={(event) => setInviteForm({ ...inviteForm, contact_email: event.target.value })}/></label><label>Pilot süresi (gün)<input type="number" min="7" max="365" value={inviteForm.pilot_days} onChange={(event) => setInviteForm({ ...inviteForm, pilot_days: event.target.value })}/></label><label>Bağlantı geçerliliği (gün)<input type="number" min="1" max="90" value={inviteForm.expires_days} onChange={(event) => setInviteForm({ ...inviteForm, expires_days: event.target.value })}/></label><label>Maksimum kullanım<input type="number" min="1" max="20" value={inviteForm.max_uses} onChange={(event) => setInviteForm({ ...inviteForm, max_uses: event.target.value })}/></label></div><button className="primary-button" onClick={createInvite}><Link2 size={16}/>Özel pilot bağlantısı oluştur</button>{lastCreatedInvite && <div className="pilot-link-result"><div className="pilot-link-result-head"><CheckCircle2 size={21}/><div><b>{lastCreatedInvite.label} için bağlantı hazır</b><small>Bu bağlantıyı doğrudan pilot kliniğin sahibine gönderin.</small></div></div><div className="pilot-link-field"><input readOnly value={pilotLink(lastCreatedInvite.token)} aria-label="Oluşturulan özel pilot bağlantısı"/><button type="button" onClick={() => copyPilotLink(lastCreatedInvite.token)}><Clipboard size={15}/>Kopyala</button><a href={pilotLink(lastCreatedInvite.token)} target="_blank" rel="noreferrer"><ExternalLink size={15}/>Aç</a></div></div>}</section>
        <section className="surface-card"><div className="surface-head"><div><span className="section-kicker">ÖZEL BAĞLANTILAR</span><h3>Pilot klinik bağlantıları</h3></div></div><div className="platform-invite-list">{data.pilotInvites.map((invite) => <article key={invite.id} className={!invite.is_active ? "inactive" : ""}><div className="platform-invite-main"><b>{invite.label}</b><a className="platform-pilot-url" href={pilotLink(invite.token)} target="_blank" rel="noreferrer">{pilotLink(invite.token)}</a><small>{invite.contact_email || "E-posta kısıtı yok"} · {invite.used_count}/{invite.max_uses} kullanım · Son tarih: {date(invite.expires_at)}</small></div><div className="platform-invite-actions"><button title="Özel bağlantıyı kopyala" onClick={() => copyPilotLink(invite.token)}><Clipboard size={15}/>Kopyala</button><a title="Bağlantıyı aç" href={pilotLink(invite.token)} target="_blank" rel="noreferrer"><ExternalLink size={15}/>Aç</a><button onClick={() => action({ action: "set_invite_active", invite_id: invite.id, is_active: !invite.is_active }, invite.is_active ? "Davet pasif yapıldı." : "Davet aktifleştirildi.")}>{invite.is_active ? "Pasif yap" : "Aktifleştir"}</button></div></article>)}</div></section>
      </div>}

      {tab === "feedback" && <section className="surface-card platform-feedback-list"><div className="surface-head"><div><span className="section-kicker">PİLOT GERİ BİLDİRİMİ</span><h3>Kliniklerden gelen kayıtlar</h3></div></div>{data.feedback.length === 0 ? <p className="muted-line">Henüz geri bildirim yok.</p> : data.feedback.map((item) => <article key={item.id}><div className="platform-feedback-meta"><span className="viz-badge">{item.category}</span><b>{item.rating ? `${item.rating}/5` : "Puan yok"}</b><small>{date(item.created_at)}</small></div><p>{item.message}</p><small>{item.page_path || "Sayfa bilgisi yok"}</small><div className="platform-feedback-actions"><select value={item.status} onChange={(event) => action({ action: "update_feedback", feedback_id: item.id, status: event.target.value, admin_note: item.admin_note }, "Geri bildirim durumu güncellendi.")}><option value="new">Yeni</option><option value="reviewing">İnceleniyor</option><option value="planned">Planlandı</option><option value="resolved">Çözüldü</option><option value="closed">Kapandı</option></select></div></article>)}</section>}
    </>}

    {selectedClinic && <>
      <button className="drawer-backdrop platform-drawer-backdrop" onClick={() => { setSelectedClinic(null); setClinicDetail(null); }} aria-label="Klinik detaylarını kapat"/>
      <aside className="detail-drawer platform-clinic-drawer" role="dialog" aria-modal="true">
        <header className="detail-drawer-head"><div><Building2 size={22}/><span><h2>{selectedClinic.name}</h2><p>{selectedClinic.slug} · Platform klinik detayı</p></span></div><button className="drawer-close" onClick={() => { setSelectedClinic(null); setClinicDetail(null); }}><X size={18}/></button></header>
        <div className="drawer-content">
          {detailLoading || !clinicDetail ? <div className="center-state"><RefreshCw className="spin"/><p>Klinik detayları yükleniyor…</p></div> : <>
            {clinicDetail.conversionRequests.find((item) => item.status === "pending") && <section className="platform-conversion-alert">
              <CreditCard size={22}/><div><span className="section-kicker">ÜCRETLİ DEVAM TALEBİ</span><h3>{data?.plans.find((plan) => plan.slug === clinicDetail.conversionRequests.find((item) => item.status === "pending")?.requested_plan_slug)?.name || clinicDetail.conversionRequests.find((item) => item.status === "pending")?.requested_plan_slug}</h3><p>{clinicDetail.conversionRequests.find((item) => item.status === "pending")?.note || "Klinik Sahibi not bırakmadı."}</p><small>{dateTime(clinicDetail.conversionRequests.find((item) => item.status === "pending")?.created_at || null)}</small></div>
            </section>}

            <section className="detail-section"><div className="detail-section-head"><h3>Klinik ve abonelik bilgileri</h3><span className={`status-badge ${clinicDetail.clinic.status}`}>{statusLabel(clinicDetail.clinic.status)}</span></div><div className="detail-info-grid platform-detail-info"><div><small>Klinik adı</small><b>{clinicDetail.clinic.name}</b></div><div><small>Plan</small><b>{clinicDetail.subscription?.plan?.name || clinicDetail.subscription?.plan_slug || "—"}</b></div><div><small>Telefon</small><b>{clinicDetail.clinic.phone || "—"}</b></div><div><small>E-posta</small><b>{clinicDetail.clinic.email || "—"}</b></div><div><small>Web sitesi</small><b>{clinicDetail.clinic.website || "—"}</b></div><div><small>Saat dilimi</small><b>{clinicDetail.clinic.timezone}</b></div><div className="wide"><small>Adres</small><b>{clinicDetail.clinic.address || "—"}</b></div><div><small>Pilot bitişi</small><b>{date(clinicDetail.subscription?.pilot_ends_at || null)}</b></div><div><small>Ücretli onay</small><b>{date(clinicDetail.subscription?.commercial_approved_at || null)}</b></div></div></section>

            <section className="detail-section"><div className="detail-section-head"><h3>Operasyon özeti</h3></div><div className="platform-detail-metrics"><article><UsersRound/><small>Aktif danışan</small><b>{clinicDetail.stats.clients.active}</b></article><article><CalendarClock/><small>Yaklaşan randevu</small><b>{clinicDetail.stats.appointments.upcoming}</b></article><article><CheckCircle2/><small>Tamamlanan</small><b>{clinicDetail.stats.appointments.completed}</b></article><article><Utensils/><small>Aktif menü</small><b>{clinicDetail.stats.mealPlans.active}</b></article><article><Activity/><small>Ölçüm kaydı</small><b>{clinicDetail.stats.measurements}</b></article><article><Stethoscope/><small>Aktif cihaz/oda</small><b>{clinicDetail.stats.resources.active}</b></article></div><div className="platform-appointment-rates"><span>İptal: <b>{clinicDetail.stats.appointments.cancelled}</b></span><span>Gelmedi: <b>{clinicDetail.stats.appointments.no_show}</b></span><span>Toplam randevu: <b>{clinicDetail.stats.appointments.total}</b></span><span>Aktif paket: <b>{clinicDetail.stats.packages.active}</b></span></div></section>

            <section className="detail-section"><div className="detail-section-head"><h3>Finans özeti</h3><Banknote size={18}/></div>{clinicDetail.stats.financials.length === 0 ? <p className="muted-line">Henüz ödeme kaydı yok.</p> : <div className="payment-totals platform-financial-grid">{clinicDetail.stats.financials.map((item) => <div key={item.currency}><small>Toplam · {item.currency}</small><b>{money(item.total, item.currency)}</b><small>Alınan</small><b className="success-text">{money(item.paid, item.currency)}</b><small>Kalan</small><b className="danger-text">{money(item.remaining, item.currency)}</b></div>)}</div>}</section>

            <section className="detail-section"><div className="detail-section-head"><h3>Ekip üyeleri</h3><span>{clinicDetail.stats.members.total} aktif</span></div><div className="drawer-list platform-member-list">{clinicDetail.members.filter((item) => item.is_active).map((member) => <article key={member.id}><span className="drawer-list-icon"><UsersRound size={16}/></span><div><b>{member.profile?.full_name || "İsimsiz kullanıcı"}</b><small>{roleLabel(member.role)} · {member.profile?.email || member.profile?.phone || "İletişim bilgisi yok"}</small></div><span className={`role-badge ${member.role}`}>{roleLabel(member.role)}</span></article>)}</div></section>

            <section className="detail-section"><div className="detail-section-head"><h3>Son danışan kayıtları</h3><span>{clinicDetail.stats.clients.active}/{clinicDetail.stats.clients.total} aktif</span></div>{clinicDetail.clients.length === 0 ? <p className="muted-line">Henüz danışan kaydı yok.</p> : <div className="drawer-list platform-client-list">{clinicDetail.clients.slice(0, 8).map((client) => <article key={client.id}><span className="drawer-list-icon"><UsersRound size={16}/></span><div><b>{client.full_name}</b><small>{client.member_no} · {client.email || client.phone || "İletişim bilgisi yok"}</small></div><span className={`status-badge ${client.is_active ? "active" : "cancelled"}`}>{client.is_active ? "Aktif" : "Pasif"}</span></article>)}</div>}</section>

            <section className="detail-section"><div className="detail-section-head"><h3>Pilot geri bildirimleri</h3><span>{clinicDetail.stats.feedback.open} açık</span></div>{clinicDetail.feedback.length === 0 ? <p className="muted-line">Bu klinikten henüz geri bildirim gelmedi.</p> : <div className="platform-clinic-feedback">{clinicDetail.feedback.slice(0, 6).map((item) => <article key={item.id}><div><span className="viz-badge">{item.category}</span><b>{item.rating ? `${item.rating}/5` : "Puan yok"}</b></div><p>{item.message}</p><small>{item.status} · {dateTime(item.created_at)}</small></article>)}</div>}</section>

            <section className="detail-section"><div className="detail-section-head"><h3>Cihazlar, odalar ve paketler</h3></div><div className="platform-mini-columns"><div><b>{clinicDetail.stats.resources.active}/{clinicDetail.stats.resources.total} kaynak aktif</b>{clinicDetail.resources.slice(0, 6).map((item) => <small key={item.id}>{item.name} · {item.resource_type} · {item.is_active ? "Aktif" : "Pasif"}</small>)}</div><div><b>{clinicDetail.stats.packages.active}/{clinicDetail.stats.packages.total} paket aktif</b>{clinicDetail.packages.slice(0, 6).map((item) => <small key={item.id}>{item.name} · {item.status} · {money(item.total_price, item.currency)}</small>)}</div></div></section>

            {(clinicDetail.subscription?.plan_slug === "pilot" || clinicDetail.conversionRequests.some((item) => item.status === "pending")) ? <section className="detail-section platform-approval-section"><div className="detail-section-head"><div><span className="section-kicker">TİCARİ ONAY</span><h3>Pilot kliniği ücretli plana geçir</h3></div><CreditCard size={20}/></div><p>Onay sonrasında klinik ve abonelik durumu <b>Aktif</b> olur; eski pilot geri sayımı temizlenir.</p><div className="inline-editor platform-approval-form"><label>Plan<select value={activationForm.plan_slug} onChange={(event) => { const plan = data?.plans.find((item) => item.slug === event.target.value); setActivationForm({ ...activationForm, plan_slug: event.target.value, agreed_price_try: plan?.monthly_price_try !== null && plan?.monthly_price_try !== undefined ? String(plan.monthly_price_try) : activationForm.agreed_price_try }); }}>{data?.plans.filter((plan) => !["pilot", "founder"].includes(plan.slug)).map((plan) => <option key={plan.slug} value={plan.slug}>{plan.name}</option>)}</select></label><label>Faturalama<select value={activationForm.billing_cycle} onChange={(event) => setActivationForm({ ...activationForm, billing_cycle: event.target.value })}><option value="monthly">Aylık</option><option value="annual">Yıllık</option><option value="manual">Manuel / özel anlaşma</option></select></label><label>Anlaşılan tutar (₺)<input type="number" min="0" step="0.01" value={activationForm.agreed_price_try} onChange={(event) => setActivationForm({ ...activationForm, agreed_price_try: event.target.value })}/></label><label className="wide">Onay / sözleşme notu<textarea rows={3} value={activationForm.approval_note} onChange={(event) => setActivationForm({ ...activationForm, approval_note: event.target.value })} placeholder="Ödeme, deneme sonucu, özel fiyat veya sözleşme notu"/></label></div><button className="primary-button platform-approve-button" onClick={approveClinic}><CheckCircle2 size={17}/>Onayla ve kliniği aktif et</button>{clinicDetail.conversionRequests.find((item) => item.status === "pending") && <button className="secondary-button danger-outline" onClick={() => { const request = clinicDetail.conversionRequests.find((item) => item.status === "pending"); if (request) void action({ action: "reject_conversion_request", clinic_id: selectedClinic.id, request_id: request.id, admin_note: activationForm.approval_note }, "Ücretli devam talebi reddedildi.", true); }}>Talebi reddet</button>}</section> : <section className="detail-section"><div className="detail-section-head"><h3>Ticari durum</h3><CheckCircle2 size={18}/></div><p>Bu klinik <b>{clinicDetail.subscription?.plan?.name || clinicDetail.subscription?.plan_slug || "aktif"}</b> planında çalışıyor. Pilot onay formu yalnızca pilot kliniklerde gösterilir.</p><div className="detail-info-grid platform-detail-info"><div><small>Abonelik durumu</small><b>{statusLabel(clinicDetail.subscription?.status || "active")}</b></div><div><small>Faturalama</small><b>{clinicDetail.subscription?.billing_cycle === "annual" ? "Yıllık" : clinicDetail.subscription?.billing_cycle === "monthly" ? "Aylık" : "Manuel / özel"}</b></div><div><small>Anlaşılan tutar</small><b>{clinicDetail.subscription?.agreed_price_try === null || clinicDetail.subscription?.agreed_price_try === undefined ? "—" : money(clinicDetail.subscription.agreed_price_try)}</b></div><div><small>Dönem sonu</small><b>{date(clinicDetail.subscription?.current_period_ends_at || null)}</b></div></div></section>}

            {clinicDetail.subscription?.plan_slug === "pilot" && <section className="detail-section"><div className="detail-section-head"><h3>Pilot süresini yönet</h3></div><div className="platform-inline-action"><input type="number" min="1" max="365" value={pilotExtensionDays} onChange={(event) => setPilotExtensionDays(event.target.value)}/><button onClick={() => action({ action: "extend_pilot", clinic_id: selectedClinic.id, days: Number(pilotExtensionDays) }, `Pilot ${pilotExtensionDays} gün uzatıldı.`, true)}><CalendarClock size={15}/>Süreyi uzat</button></div></section>}

            <section className="detail-section"><div className="detail-section-head"><h3>Platform notları</h3><FileText size={18}/></div><div className="platform-note-composer"><textarea rows={3} value={platformNote} onChange={(event) => setPlatformNote(event.target.value)} placeholder="Klinikle yapılan görüşme, özel şart veya takip notu"/><button className="secondary-button" onClick={async () => { await action({ action: "save_clinic_note", clinic_id: selectedClinic.id, note: platformNote }, "Klinik notu kaydedildi.", true); setPlatformNote(""); }}>Notu kaydet</button></div><div className="platform-note-list">{clinicDetail.notes.map((item) => <article key={item.id}><p>{item.note}</p><small>{item.created_by_email} · {dateTime(item.created_at)}</small></article>)}</div></section>

            <section className="detail-section"><div className="detail-section-head"><h3>Son platform hareketleri</h3></div><div className="platform-audit-list">{clinicDetail.audit.slice(0, 12).map((item) => <article key={item.id}><b>{item.action}</b><small>{dateTime(item.created_at)} · {item.target_type || "sistem"}</small></article>)}</div></section>
          </>}
        </div>
      </aside>
    </>}
  </main>;
}
