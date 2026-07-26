"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  Activity,
  ArrowLeft,
  Banknote,
  Building2,
  CalendarClock,
  CheckCircle2,
  Clipboard,
  ClipboardList,
  CreditCard,
  Eye,
  FileText,
  FlaskConical,
  Languages,
  Link2,
  Mail,
  MessageSquareText,
  RefreshCw,
  Search,
  ShieldCheck,
  Stethoscope,
  UsersRound,
  Utensils,
  X,
} from "lucide-react";
import { detectBrowserLocale, intlLocales, localeLabels, locales, translateUiText } from "@/lib/i18n";
import { LocalizedContent } from "@/lib/i18n-runtime";
import type { Locale } from "@/lib/types";

type ConversionRequest = {
  id: string;
  clinic_id: string;
  requested_by: string;
  requested_plan_slug: string;
  note: string | null;
  status: string;
  reviewed_by_email: string | null;
  reviewed_at: string | null;
  admin_note: string | null;
  created_at: string;
  updated_at: string;
};

type ClinicRow = {
  id: string;
  name: string;
  slug: string;
  status: string;
  default_locale: string;
  timezone: string;
  created_at: string;
  subscription: {
    plan_slug: string;
    status: string;
    pilot_started_at: string | null;
    pilot_ends_at: string | null;
    current_period_started_at: string | null;
    current_period_ends_at: string | null;
    commercial_approved_at: string | null;
    commercial_approved_by_email: string | null;
    agreed_price_try: number | null;
    billing_cycle: string | null;
  } | null;
  memberships: { owners: number; dietitians: number; secretaries: number; total: number };
  active_clients: number;
  conversion_request: ConversionRequest | null;
};

type PilotInvite = {
  id: string;
  token: string;
  label: string;
  contact_email: string | null;
  pilot_days: number;
  max_uses: number;
  used_count: number;
  expires_at: string;
  is_active: boolean;
  created_at: string;
};

type PilotApplication = {
  id: string;
  full_name: string;
  email: string;
  phone: string | null;
  applicant_type: string;
  clinic_name: string | null;
  city: string | null;
  team_size: number;
  active_client_count: number;
  uses_devices: boolean;
  message: string | null;
  status: string;
  admin_note: string | null;
  created_at: string;
};

type Feedback = {
  id: string;
  clinic_id: string;
  category: string;
  rating: number | null;
  message: string;
  page_path: string | null;
  status: string;
  admin_note: string | null;
  created_at: string;
};

type Plan = {
  slug: string;
  name: string;
  monthly_price_try: number | null;
  max_dietitians: number;
  max_staff: number;
  max_active_clients: number;
  is_public?: boolean;
  is_active?: boolean;
};

type Payload = {
  clinics: ClinicRow[];
  pilotInvites: PilotInvite[];
  pilotApplications: PilotApplication[];
  feedback: Feedback[];
  plans: Plan[];
  conversionRequests: ConversionRequest[];
  warnings?: string[];
  metrics: {
    clinics: number;
    pilotClinics: number;
    activeUsers: number;
    activeClients: number;
    openFeedback: number;
    openApplications: number;
    pendingConversions: number;
  };
};

type Member = {
  id: string;
  user_id: string;
  role: string;
  is_active: boolean;
  created_at: string;
  profile: { id: string; full_name: string; email: string | null; phone: string | null } | null;
};

type ClinicDetail = {
  clinic: {
    id: string;
    name: string;
    slug: string;
    status: string;
    default_locale: string;
    timezone: string;
    phone: string | null;
    email: string | null;
    website: string | null;
    address: string | null;
    created_at: string;
    onboarding_completed_at: string | null;
  };
  subscription: ({
    id: string;
    plan_slug: string;
    status: string;
    pilot_started_at: string | null;
    pilot_ends_at: string | null;
    current_period_started_at: string | null;
    current_period_ends_at: string | null;
    commercial_approved_at: string | null;
    commercial_approved_by_email: string | null;
    commercial_approval_note: string | null;
    agreed_price_try: number | null;
    billing_cycle: string | null;
    converted_from_pilot_at: string | null;
    plan: { slug: string; name: string; monthly_price_try: number | null } | null;
  } | null);
  members: Member[];
  clients: Array<{ id: string; member_no: string; full_name: string; email: string | null; phone: string | null; is_active: boolean; created_at: string }>;
  resources: Array<{ id: string; name: string; resource_type: string; is_active: boolean; created_at: string }>;
  packages: Array<{ id: string; name: string; status: string; total_price: number; currency: string; created_at: string }>;
  feedback: Feedback[];
  conversionRequests: ConversionRequest[];
  notes: Array<{ id: string; note: string; created_by_email: string; created_at: string }>;
  audit: Array<{ id: number; action: string; target_type: string | null; metadata: Record<string, unknown>; created_at: string }>;
  warnings?: string[];
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

type Tab = "clinics" | "conversions" | "applications" | "invites" | "feedback";

type ApiError = Error & { status?: number };

function daysLeft(value: string | null) {
  if (!value) return null;
  const timestamp = new Date(value).getTime();
  if (Number.isNaN(timestamp)) return null;
  return Math.ceil((timestamp - Date.now()) / 86_400_000);
}

function roleLabel(role: string) {
  return ({ owner: "Klinik Sahibi", dietitian: "Diyetisyen", secretary: "Sekreter", client: "Danışan" } as Record<string, string>)[role] || role;
}

function statusLabel(status: string) {
  return ({
    new: "Yeni",
    contacted: "İletişime geçildi",
    approved: "Onaylandı",
    waitlist: "Bekleme listesi",
    reviewing: "İnceleniyor",
    planned: "Planlandı",
    resolved: "Çözüldü",
    closed: "Kapalı",
    rejected: "Reddedildi",
    pilot: "Ücretsiz Pilot",
    trialing: "Deneme",
    active: "Aktif",
    past_due: "Ödeme Gecikmiş",
    paused: "Duraklatıldı",
    expired: "Süresi Doldu",
    cancelled: "İptal Edildi",
    pending: "Bekliyor",
  } as Record<string, string>)[status] || status;
}

function clinicStatusFromSubscription(planSlug: string | undefined, status: string | undefined) {
  if (planSlug === "pilot" && ["pilot", "trialing"].includes(status || "")) return "pilot";
  if (["paused", "expired", "cancelled"].includes(status || "")) return status;
  if (["active", "trialing", "past_due"].includes(status || "")) return "active";
  return status || "active";
}

async function readJson<T>(response: Response): Promise<T> {
  const payload = await response.json().catch(() => null) as T | { error?: string } | null;
  if (!response.ok) {
    const serverMessage = payload && typeof payload === "object" && "error" in payload && typeof payload.error === "string" ? payload.error : null;
    const error = new Error(serverMessage || `Sunucu hatası (${response.status})`) as ApiError;
    error.status = response.status;
    throw error;
  }
  if (!payload) throw new Error("Sunucu boş veya geçersiz yanıt döndürdü.");
  return payload as T;
}

export default function PlatformAdminClient({ email }: { email: string }) {
  const [locale, setLocale] = useState<Locale>("tr");
  const [data, setData] = useState<Payload | null>(null);
  const [loading, setLoading] = useState(true);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [busyAction, setBusyAction] = useState("");
  const [tab, setTab] = useState<Tab>("clinics");
  const [query, setQuery] = useState("");
  const [inviteForm, setInviteForm] = useState({ label: "", contact_email: "", pilot_days: "90", expires_days: "14", max_uses: "1" });
  const [lastCreatedInvite, setLastCreatedInvite] = useState<PilotInvite | null>(null);
  const [selectedClinicId, setSelectedClinicId] = useState<string | null>(null);
  const [clinicDetail, setClinicDetail] = useState<ClinicDetail | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [pilotExtensionDays, setPilotExtensionDays] = useState("30");
  const [platformNote, setPlatformNote] = useState("");
  const [activationForm, setActivationForm] = useState({ plan_slug: "professional", billing_cycle: "monthly", agreed_price_try: "", approval_note: "" });
  const [planForm, setPlanForm] = useState("professional");
  const configuredAppUrl = useMemo(() => (process.env.NEXT_PUBLIC_APP_URL || "").replace(/\/$/, ""), []);
  const [appUrl, setAppUrl] = useState(configuredAppUrl);

  useEffect(() => setLocale(detectBrowserLocale()), []);
  useEffect(() => {
    if (!configuredAppUrl && typeof window !== "undefined") setAppUrl(window.location.origin.replace(/\/$/, ""));
  }, [configuredAppUrl]);

  const formatDate = useCallback((value: string | null) => {
    if (!value) return "—";
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? "—" : new Intl.DateTimeFormat(intlLocales[locale], { dateStyle: "medium" }).format(date);
  }, [locale]);

  const formatDateTime = useCallback((value: string | null) => {
    if (!value) return "—";
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? "—" : new Intl.DateTimeFormat(intlLocales[locale], { dateStyle: "medium", timeStyle: "short" }).format(date);
  }, [locale]);

  const formatMoney = useCallback((value: number | null | undefined, currency = "TRY") => (
    new Intl.NumberFormat(intlLocales[locale], { style: "currency", currency, maximumFractionDigits: 2 }).format(Number(value || 0))
  ), [locale]);
  const tx = useCallback((value: string) => translateUiText(value, locale), [locale]);
  const availablePaidPlans = useMemo(() => (data?.plans || []).filter((plan) => plan.is_active !== false && !["pilot", "founder"].includes(plan.slug)), [data?.plans]);

  const pilotLink = useCallback((token: string) => `${appUrl}/login?pilot=${encodeURIComponent(token)}`, [appUrl]);

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const response = await fetch("/api/platform/admin", { cache: "no-store", headers: { accept: "application/json" } });
      setData(await readJson<Payload>(response));
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Veriler alınamadı");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  const loadClinicDetail = useCallback(async (clinicId: string) => {
    setSelectedClinicId(clinicId);
    setClinicDetail(null);
    setDetailLoading(true);
    setError("");
    try {
      const response = await fetch(`/api/platform/admin/clinic/${encodeURIComponent(clinicId)}`, { cache: "no-store", headers: { accept: "application/json" } });
      const detail = await readJson<ClinicDetail>(response);
      setClinicDetail(detail);
      const request = detail.conversionRequests.find((item) => item.status === "pending") || detail.conversionRequests[0];
      const requestedPlanSlug = request?.requested_plan_slug || detail.subscription?.plan_slug || "professional";
      const paidPlans = (data?.plans || []).filter((item) => item.is_active !== false && !["pilot", "founder"].includes(item.slug));
      const effectivePlanSlug = paidPlans.some((item) => item.slug === requestedPlanSlug) ? requestedPlanSlug : paidPlans[0]?.slug || "professional";
      const plan = paidPlans.find((item) => item.slug === effectivePlanSlug);
      setActivationForm({
        plan_slug: effectivePlanSlug,
        billing_cycle: detail.subscription?.billing_cycle || "monthly",
        agreed_price_try: detail.subscription?.agreed_price_try != null
          ? String(detail.subscription.agreed_price_try)
          : plan?.monthly_price_try != null ? String(plan.monthly_price_try) : "",
        approval_note: request?.admin_note || detail.subscription?.commercial_approval_note || "",
      });
      setPlanForm(detail.subscription?.plan_slug || "professional");
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Klinik detayları alınamadı");
    } finally {
      setDetailLoading(false);
    }
  }, [data?.plans]);

  async function performAction(body: Record<string, unknown>, success: string, options?: { refreshDetail?: boolean; key?: string }) {
    if (busyAction) return undefined;
    const key = options?.key || String(body.action || "action");
    setBusyAction(key);
    setError("");
    setMessage("");
    try {
      const response = await fetch("/api/platform/admin", {
        method: "POST",
        headers: { "content-type": "application/json", accept: "application/json" },
        body: JSON.stringify(body),
      });
      const payload = await readJson<Record<string, unknown>>(response);
      setMessage(success);
      await load();
      if (options?.refreshDetail && selectedClinicId) await loadClinicDetail(selectedClinicId);
      return payload;
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "İşlem başarısız");
      return undefined;
    } finally {
      setBusyAction("");
    }
  }

  async function copyPilotLink(token: string) {
    const link = pilotLink(token);
    try {
      await navigator.clipboard.writeText(link);
    } catch {
      const field = document.createElement("textarea");
      field.value = link;
      field.style.position = "fixed";
      field.style.opacity = "0";
      document.body.appendChild(field);
      field.select();
      document.execCommand("copy");
      field.remove();
    }
    setMessage("Özel pilot bağlantısı panoya kopyalandı.");
  }

  async function createInvite() {
    if (!inviteForm.label.trim()) {
      setError("Pilot etiketi zorunludur.");
      return;
    }
    const payload = await performAction({ action: "create_pilot_invite", ...inviteForm }, "Pilot daveti oluşturuldu.", { key: "create-invite" }) as { invite?: PilotInvite } | undefined;
    if (payload?.invite) {
      setLastCreatedInvite(payload.invite);
      setInviteForm({ label: "", contact_email: "", pilot_days: "90", expires_days: "14", max_uses: "1" });
      await copyPilotLink(payload.invite.token);
    }
  }

  async function approveClinic() {
    if (!selectedClinicId || !clinicDetail) return;
    const selectedClinic = data?.clinics.find((item) => item.id === selectedClinicId);
    const pending = clinicDetail.conversionRequests.find((item) => item.status === "pending");
    const selectedPlan = availablePaidPlans.find((item) => item.slug === activationForm.plan_slug);
    if (!selectedPlan) { setError("Aktif ücretli plan bulunamadı."); return; }
    if (activationForm.agreed_price_try && (!Number.isFinite(Number(activationForm.agreed_price_try)) || Number(activationForm.agreed_price_try) < 0)) { setError("Anlaşılan fiyat geçersiz."); return; }
    if (!window.confirm(tx(`${selectedClinic?.name || clinicDetail.clinic.name} kliniğini ${selectedPlan.name} planında aktif etmek istediğinize emin misiniz?`))) return;
    await performAction({ action: "approve_paid_access", clinic_id: selectedClinicId, request_id: pending?.id || null, ...activationForm }, "Klinik ücretli plana geçirildi ve erişimi onaylandı.", { refreshDetail: true, key: "approve-clinic" });
  }

  async function updateClinicStatus(clinic: ClinicRow, status: string) {
    if (status === clinic.status) return;
    if (["paused", "expired", "cancelled"].includes(status) && !window.confirm(tx(`${clinic.name} kliniğinin durumu “${tx(statusLabel(status))}” olarak değiştirilsin mi?`))) return;
    await performAction({ action: "set_clinic_status", clinic_id: clinic.id, status }, "Klinik durumu güncellendi.", { refreshDetail: selectedClinicId === clinic.id, key: `status:${clinic.id}` });
  }

  const pendingConversions = data?.conversionRequests.filter((item) => item.status === "pending") || [];
  const selectedClinic = data?.clinics.find((item) => item.id === selectedClinicId) || null;
  const normalizedQuery = query.trim().toLocaleLowerCase(intlLocales[locale]);
  const filteredClinics = (data?.clinics || []).filter((clinic) => !normalizedQuery || [clinic.name, clinic.slug, clinic.subscription?.plan_slug, clinic.status].some((value) => String(value || "").toLocaleLowerCase(intlLocales[locale]).includes(normalizedQuery)));

  return (
    <LocalizedContent locale={locale} className="localized-app-root">
      <main className="platform-admin-page">
        <header className="platform-admin-header">
          <div>
            <span className="section-kicker">NUTRICLINIC AI PLATFORM</span>
            <h1>Global Yönetim</h1>
            <p>{email} · Pilot klinikler, planlar, ticari onaylar ve geri bildirimler</p>
          </div>
          <div className="platform-admin-actions">
            <label className="language-picker"><Languages size={16}/><select value={locale} onChange={(event) => setLocale(event.target.value as Locale)}>{locales.map((item) => <option key={item} value={item}>{localeLabels[item]}</option>)}</select></label>
            <a className="secondary-button compact" href="/dashboard"><ArrowLeft size={15}/>Kliniğe dön</a>
            <button className="secondary-button compact" onClick={() => void load()} disabled={loading || Boolean(busyAction)}><RefreshCw size={15} className={loading ? "spin" : ""}/>Yenile</button>
          </div>
        </header>

        {message && <div className="notice-bar platform-notice success"><span>{message}</span><button onClick={() => setMessage("")} aria-label="Kapat"><X size={15}/></button></div>}
        {error && <div className="notice-bar platform-notice error"><span>{error}</span><button onClick={() => setError("")} aria-label="Kapat"><X size={15}/></button></div>}
        {data?.warnings?.length ? <div className="platform-warning-list"><b>Eksik veya erişilemeyen platform verileri</b>{data.warnings.map((warning) => <small key={warning}>{warning}</small>)}</div> : null}

        {loading && !data ? (
          <div className="center-state"><RefreshCw className="spin"/><p>Platform verileri yükleniyor…</p></div>
        ) : !data ? (
          <div className="center-state"><p>Platform verileri alınamadı.</p><button className="primary-button" onClick={() => void load()}>Tekrar dene</button></div>
        ) : (
          <>
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

            {tab === "clinics" && (
              <section className="surface-card platform-table-card">
                <div className="surface-head platform-list-head">
                  <div><span className="section-kicker">TENANT YÖNETİMİ</span><h3>Klinik workspace’leri</h3><p>Ekip, danışan, kullanım, finans ve abonelik durumunu yönetin.</p></div>
                  <label className="platform-search"><Search size={16}/><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Klinik, plan veya durum ara"/></label>
                </div>
                <div className="table-wrap modern-table-wrap">
                  <table className="modern-table">
                    <thead><tr><th>Klinik</th><th>Plan / pilot</th><th>Kullanım</th><th>Durum</th><th>İşlemler</th></tr></thead>
                    <tbody>
                      {filteredClinics.map((clinic) => {
                        const isPilot = clinic.subscription?.plan_slug === "pilot";
                        const remaining = isPilot ? daysLeft(clinic.subscription?.pilot_ends_at || null) : null;
                        const pending = clinic.conversion_request?.status === "pending";
                        const periodText = isPilot && clinic.subscription?.pilot_ends_at
                          ? `${formatDate(clinic.subscription.pilot_ends_at)} · ${remaining ?? "—"} gün`
                          : clinic.subscription?.commercial_approved_at
                            ? `Onay: ${formatDate(clinic.subscription.commercial_approved_at)}`
                            : clinic.subscription?.current_period_ends_at
                              ? `Dönem sonu: ${formatDate(clinic.subscription.current_period_ends_at)}`
                              : clinic.subscription?.plan_slug === "founder" ? "Süresiz kurucu erişimi" : "Dönem bilgisi yok";
                        return (
                          <tr key={clinic.id} className={pending ? "platform-pending-row" : ""}>
                            <td><b>{clinic.name}</b><small>{clinic.slug}<br/>{formatDate(clinic.created_at)}</small>{pending && <span className="conversion-request-badge">Ücretli devam talebi</span>}</td>
                            <td><span className="role-badge owner">{data.plans.find((plan) => plan.slug === clinic.subscription?.plan_slug)?.name || clinic.subscription?.plan_slug || "—"}</span><small>{periodText}</small></td>
                            <td><small>{clinic.memberships.owners + clinic.memberships.dietitians} diyetisyen/owner<br/>{clinic.memberships.secretaries} sekreter · {clinic.active_clients} danışan</small></td>
                            <td><span className={`status-badge ${clinic.status}`}>{statusLabel(clinic.status)}</span>{clinic.subscription && clinicStatusFromSubscription(clinic.subscription.plan_slug, clinic.subscription.status) !== clinic.status && <small className="platform-state-warning">Abonelik: {statusLabel(clinic.subscription.status)}</small>}</td>
                            <td><div className="platform-row-actions">
                              <button className="platform-detail-button" disabled={Boolean(busyAction)} onClick={() => void loadClinicDetail(clinic.id)}><Eye size={14}/>Detayları gör</button>
                              {isPilot && <button disabled={Boolean(busyAction)} onClick={() => void performAction({ action: "extend_pilot", clinic_id: clinic.id, days: 30 }, "Pilot 30 gün uzatıldı.", { key: `extend:${clinic.id}` })}><CalendarClock size={14}/>+30 gün</button>}
                              <select value={clinic.status} disabled={Boolean(busyAction)} onChange={(event) => void updateClinicStatus(clinic, event.target.value)}>
                                {clinic.status === "pilot" && <option value="pilot" disabled>Pilot (süre yönetimi)</option>}
                                <option value="active">Aktif</option><option value="paused">Duraklatıldı</option><option value="expired">Süresi doldu</option><option value="cancelled">İptal</option>
                              </select>
                            </div></td>
                          </tr>
                        );
                      })}
                      {filteredClinics.length === 0 && <tr><td colSpan={5}><p className="muted-line">Arama kriterine uygun klinik bulunamadı.</p></td></tr>}
                    </tbody>
                  </table>
                </div>
              </section>
            )}

            {tab === "conversions" && (
              <section className="surface-card platform-table-card">
                <div className="surface-head"><div><span className="section-kicker">ÜCRETLİ DÖNÜŞÜM</span><h3>Geçiş talepleri</h3><p>Klinik sahibinin ücretli devam isteğini inceleyip plan ve fiyatı onaylayın.</p></div></div>
                {pendingConversions.length === 0 ? <p className="muted-line">Bekleyen geçiş talebi yok.</p> : <div className="platform-card-list">{pendingConversions.map((request) => {
                  const clinic = data.clinics.find((item) => item.id === request.clinic_id);
                  return <article key={request.id}><div><b>{clinic?.name || request.clinic_id}</b><small>{data.plans.find((plan) => plan.slug === request.requested_plan_slug)?.name || request.requested_plan_slug} · {formatDateTime(request.created_at)}</small><p>{request.note || "Klinik Sahibi not bırakmadı."}</p></div><button className="primary-button compact" onClick={() => void loadClinicDetail(request.clinic_id)}><Eye size={14}/>İncele ve onayla</button></article>;
                })}</div>}
              </section>
            )}

            {tab === "applications" && (
              <section className="surface-card platform-table-card">
                <div className="surface-head"><div><span className="section-kicker">WEB BAŞVURULARI</span><h3>Pilot başvuruları</h3><p>Başvuruyu değerlendirin ve uygun kişiye özel pilot daveti oluşturun.</p></div></div>
                <div className="platform-card-list">{data.pilotApplications.map((application) => (
                  <article key={application.id}>
                    <div><b>{application.full_name}</b><small>{application.email}{application.phone ? ` · ${application.phone}` : ""} · {formatDateTime(application.created_at)}</small><p>{application.clinic_name || "Klinik adı yok"} · {application.city || "Şehir yok"} · {application.team_size} kişilik ekip · {application.active_client_count} danışan</p>{application.message && <p>{application.message}</p>}</div>
                    <div className="platform-row-actions"><select value={application.status} disabled={Boolean(busyAction)} onChange={(event) => void performAction({ action: "update_pilot_application", application_id: application.id, status: event.target.value, admin_note: application.admin_note }, "Başvuru durumu güncellendi.", { key: `application:${application.id}` })}><option value="new">Yeni</option><option value="contacted">İletişime geçildi</option><option value="approved">Onaylandı</option><option value="waitlist">Bekleme listesi</option><option value="rejected">Reddedildi</option><option value="closed">Kapalı</option></select><button onClick={() => { setInviteForm((current) => ({ ...current, label: application.clinic_name || application.full_name, contact_email: application.email })); setTab("invites"); }}><Link2 size={14}/>Davet hazırla</button></div>
                  </article>
                ))}{data.pilotApplications.length === 0 && <p className="muted-line">Henüz pilot başvurusu yok.</p>}</div>
              </section>
            )}

            {tab === "invites" && (
              <section className="platform-two-column">
                <article className="surface-card platform-form-card">
                  <div className="surface-head"><div><span className="section-kicker">ÖZEL BAĞLANTI</span><h3>Pilot daveti oluştur</h3></div></div>
                  <div className="form-grid">
                    <label className="wide">Etiket<input value={inviteForm.label} onChange={(event) => setInviteForm({ ...inviteForm, label: event.target.value })} placeholder="Klinik veya kişi adı"/></label>
                    <label className="wide">E-posta<input type="email" value={inviteForm.contact_email} onChange={(event) => setInviteForm({ ...inviteForm, contact_email: event.target.value })}/></label>
                    <label>Pilot süresi (gün)<input type="number" min="7" max="365" value={inviteForm.pilot_days} onChange={(event) => setInviteForm({ ...inviteForm, pilot_days: event.target.value })}/></label>
                    <label>Bağlantı geçerliliği (gün)<input type="number" min="1" max="90" value={inviteForm.expires_days} onChange={(event) => setInviteForm({ ...inviteForm, expires_days: event.target.value })}/></label>
                    <label>Maksimum kullanım<input type="number" min="1" max="20" value={inviteForm.max_uses} onChange={(event) => setInviteForm({ ...inviteForm, max_uses: event.target.value })}/></label>
                  </div>
                  <button className="primary-button" disabled={busyAction === "create-invite"} onClick={() => void createInvite()}>{busyAction === "create-invite" ? <RefreshCw className="spin" size={16}/> : <Link2 size={16}/>}Özel pilot bağlantısı oluştur</button>
                  {lastCreatedInvite && <div className="platform-created-link"><b>{lastCreatedInvite.label}</b><code>{pilotLink(lastCreatedInvite.token)}</code><button onClick={() => void copyPilotLink(lastCreatedInvite.token)}><Clipboard size={14}/>Bağlantıyı kopyala</button></div>}
                </article>
                <article className="surface-card platform-table-card">
                  <div className="surface-head"><div><span className="section-kicker">DAVET GEÇMİŞİ</span><h3>Pilot davetleri</h3></div></div>
                  <div className="platform-card-list compact">{data.pilotInvites.map((invite) => <article key={invite.id}><div><b>{invite.label}</b><small>{invite.contact_email || "E-posta yok"} · {invite.used_count}/{invite.max_uses} kullanım · {formatDate(invite.expires_at)}</small><code>{invite.token}</code></div><div className="platform-row-actions"><button onClick={() => void copyPilotLink(invite.token)}><Clipboard size={14}/>Kopyala</button><button disabled={Boolean(busyAction)} onClick={() => void performAction({ action: "set_invite_active", invite_id: invite.id, is_active: !invite.is_active }, invite.is_active ? "Davet pasifleştirildi." : "Davet aktifleştirildi.", { key: `invite:${invite.id}` })}>{invite.is_active ? "Pasifleştir" : "Aktifleştir"}</button></div></article>)}</div>
                </article>
              </section>
            )}

            {tab === "feedback" && (
              <section className="surface-card platform-table-card">
                <div className="surface-head"><div><span className="section-kicker">PİLOT GERİ BİLDİRİMİ</span><h3>Geri bildirimler</h3></div></div>
                <div className="platform-card-list">{data.feedback.map((item) => {
                  const clinic = data.clinics.find((clinicRow) => clinicRow.id === item.clinic_id);
                  return <article key={item.id}><div><b>{clinic?.name || "Bilinmeyen klinik"} · {item.category}</b><small>{item.rating ? `${item.rating}/5` : "Puan yok"} · {formatDateTime(item.created_at)} · {item.page_path || "Sayfa bilgisi yok"}</small><p>{item.message}</p></div><select value={item.status} disabled={Boolean(busyAction)} onChange={(event) => void performAction({ action: "update_feedback", feedback_id: item.id, status: event.target.value, admin_note: item.admin_note }, "Geri bildirim durumu güncellendi.", { key: `feedback:${item.id}` })}><option value="new">Yeni</option><option value="reviewing">İnceleniyor</option><option value="planned">Planlandı</option><option value="resolved">Çözüldü</option><option value="closed">Kapalı</option></select></article>;
                })}{data.feedback.length === 0 && <p className="muted-line">Henüz geri bildirim yok.</p>}</div>
              </section>
            )}
          </>
        )}

        {selectedClinicId && (
          <div className="platform-detail-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) setSelectedClinicId(null); }}>
            <aside className="platform-detail-drawer" role="dialog" aria-modal="true" aria-label="Klinik detayları">
              <header><div><span className="section-kicker">KLİNİK DETAYI</span><h2>{selectedClinic?.name || clinicDetail?.clinic.name || "Klinik"}</h2><p>{selectedClinic?.slug || clinicDetail?.clinic.slug}</p></div><button onClick={() => setSelectedClinicId(null)} aria-label="Kapat"><X/></button></header>
              <div className="platform-detail-body">
                {detailLoading ? <div className="center-state"><RefreshCw className="spin"/><p>Klinik detayları yükleniyor…</p></div> : !clinicDetail ? <div className="center-state"><p>Klinik detayları alınamadı.</p><button className="primary-button" onClick={() => void loadClinicDetail(selectedClinicId)}>Tekrar dene</button></div> : (
                  <>
                    {clinicDetail.warnings?.length ? <div className="platform-warning-list"><b>Bazı detaylar yüklenemedi</b>{clinicDetail.warnings.map((warning) => <small key={warning}>{warning}</small>)}</div> : null}
                    {clinicDetail.conversionRequests.some((item) => item.status === "pending") && <section className="detail-section conversion-callout"><div><span className="section-kicker">ÜCRETLİ DEVAM TALEBİ</span><h3>{data?.plans.find((plan) => plan.slug === clinicDetail.conversionRequests.find((item) => item.status === "pending")?.requested_plan_slug)?.name || clinicDetail.conversionRequests.find((item) => item.status === "pending")?.requested_plan_slug}</h3><p>{clinicDetail.conversionRequests.find((item) => item.status === "pending")?.note || "Klinik Sahibi not bırakmadı."}</p><small>{formatDateTime(clinicDetail.conversionRequests.find((item) => item.status === "pending")?.created_at || null)}</small></div></section>}

                    <section className="detail-section"><div className="detail-section-head"><h3>Klinik ve abonelik bilgileri</h3><span className={`status-badge ${clinicDetail.clinic.status}`}>{statusLabel(clinicDetail.clinic.status)}</span></div><div className="detail-info-grid platform-detail-info"><div><small>Klinik adı</small><b>{clinicDetail.clinic.name}</b></div><div><small>Plan</small><b>{clinicDetail.subscription?.plan?.name || clinicDetail.subscription?.plan_slug || "—"}</b></div><div><small>Abonelik durumu</small><b>{statusLabel(clinicDetail.subscription?.status || "—")}</b></div><div><small>Telefon</small><b>{clinicDetail.clinic.phone || "—"}</b></div><div><small>E-posta</small><b>{clinicDetail.clinic.email || "—"}</b></div><div><small>Web sitesi</small><b>{clinicDetail.clinic.website || "—"}</b></div><div><small>Saat dilimi</small><b>{clinicDetail.clinic.timezone}</b></div><div><small>Varsayılan dil</small><b>{localeLabels[(clinicDetail.clinic.default_locale as Locale)] || clinicDetail.clinic.default_locale}</b></div><div className="wide"><small>Adres</small><b>{clinicDetail.clinic.address || "—"}</b></div>{clinicDetail.subscription?.plan_slug === "pilot" && <div><small>Pilot bitişi</small><b>{formatDate(clinicDetail.subscription.pilot_ends_at)}</b></div>}<div><small>Ücretli onay</small><b>{formatDate(clinicDetail.subscription?.commercial_approved_at || null)}</b></div></div></section>

                    <section className="detail-section"><div className="detail-section-head"><h3>Operasyon özeti</h3></div><div className="platform-detail-metrics"><article><UsersRound/><small>Aktif danışan</small><b>{clinicDetail.stats.clients.active}</b></article><article><CalendarClock/><small>Yaklaşan randevu</small><b>{clinicDetail.stats.appointments.upcoming}</b></article><article><CheckCircle2/><small>Tamamlanan</small><b>{clinicDetail.stats.appointments.completed}</b></article><article><Utensils/><small>Aktif menü</small><b>{clinicDetail.stats.mealPlans.active}</b></article><article><Activity/><small>Ölçüm kaydı</small><b>{clinicDetail.stats.measurements}</b></article><article><Stethoscope/><small>Aktif cihaz/oda</small><b>{clinicDetail.stats.resources.active}</b></article></div><div className="platform-appointment-rates"><span>İptal: <b>{clinicDetail.stats.appointments.cancelled}</b></span><span>Gelmedi: <b>{clinicDetail.stats.appointments.no_show}</b></span><span>Toplam randevu: <b>{clinicDetail.stats.appointments.total}</b></span><span>Aktif paket: <b>{clinicDetail.stats.packages.active}</b></span></div></section>

                    <section className="detail-section"><div className="detail-section-head"><h3>Finans özeti</h3><Banknote size={18}/></div>{clinicDetail.stats.financials.length === 0 ? <p className="muted-line">Henüz ödeme kaydı yok.</p> : <div className="payment-totals platform-financial-grid">{clinicDetail.stats.financials.map((item) => <div key={item.currency}><small>Toplam · {item.currency}</small><b>{formatMoney(item.total, item.currency)}</b><small>Alınan</small><b className="success-text">{formatMoney(item.paid, item.currency)}</b><small>Kalan</small><b className="danger-text">{formatMoney(item.remaining, item.currency)}</b></div>)}</div>}</section>

                    <section className="detail-section"><div className="detail-section-head"><h3>Ekip üyeleri</h3><span>{clinicDetail.stats.members.total} aktif</span></div><div className="drawer-list platform-member-list">{clinicDetail.members.filter((item) => item.is_active).map((member) => <article key={member.id}><span className="drawer-list-icon"><UsersRound size={16}/></span><div><b>{member.profile?.full_name || "İsimsiz kullanıcı"}</b><small>{roleLabel(member.role)} · {member.profile?.email || member.profile?.phone || "İletişim bilgisi yok"}</small></div><span className={`role-badge ${member.role}`}>{roleLabel(member.role)}</span></article>)}{clinicDetail.members.filter((item) => item.is_active).length === 0 && <p className="muted-line">Aktif ekip üyesi yok.</p>}</div></section>

                    <section className="detail-section"><div className="detail-section-head"><h3>Son danışan kayıtları</h3><span>{clinicDetail.stats.clients.active}/{clinicDetail.stats.clients.total} aktif</span></div>{clinicDetail.clients.length === 0 ? <p className="muted-line">Henüz danışan kaydı yok.</p> : <div className="drawer-list platform-client-list">{clinicDetail.clients.slice(0, 8).map((client) => <article key={client.id}><span className="drawer-list-icon"><UsersRound size={16}/></span><div><b>{client.full_name}</b><small>{client.member_no} · {client.email || client.phone || "İletişim bilgisi yok"}</small></div><span className={`status-badge ${client.is_active ? "active" : "cancelled"}`}>{client.is_active ? "Aktif" : "Pasif"}</span></article>)}</div>}</section>

                    <section className="detail-section"><div className="detail-section-head"><h3>Pilot geri bildirimleri</h3><span>{clinicDetail.stats.feedback.open} açık</span></div>{clinicDetail.feedback.length === 0 ? <p className="muted-line">Bu klinikten henüz geri bildirim gelmedi.</p> : <div className="platform-clinic-feedback">{clinicDetail.feedback.slice(0, 6).map((item) => <article key={item.id}><div><span className="viz-badge">{item.category}</span><b>{item.rating ? `${item.rating}/5` : "Puan yok"}</b></div><p>{item.message}</p><small>{statusLabel(item.status)} · {formatDateTime(item.created_at)}</small></article>)}</div>}</section>

                    <section className="detail-section"><div className="detail-section-head"><h3>Cihazlar, odalar ve paketler</h3></div><div className="platform-mini-columns"><div><b>{clinicDetail.stats.resources.active}/{clinicDetail.stats.resources.total} kaynak aktif</b>{clinicDetail.resources.slice(0, 6).map((item) => <small key={item.id}>{item.name} · {item.resource_type} · {item.is_active ? "Aktif" : "Pasif"}</small>)}</div><div><b>{clinicDetail.stats.packages.active}/{clinicDetail.stats.packages.total} paket aktif</b>{clinicDetail.packages.slice(0, 6).map((item) => <small key={item.id}>{item.name} · {statusLabel(item.status)} · {formatMoney(item.total_price, item.currency)}</small>)}</div></div></section>

                    {(clinicDetail.subscription?.plan_slug === "pilot" || clinicDetail.conversionRequests.some((item) => item.status === "pending")) ? (
                      <section className="detail-section platform-approval-section"><div className="detail-section-head"><div><span className="section-kicker">TİCARİ ONAY</span><h3>Pilot kliniği ücretli plana geçir</h3></div><CreditCard size={20}/></div><p>Onay sonrasında klinik ve abonelik durumu Aktif olur; pilot geri sayımı temizlenir.</p><div className="inline-editor platform-approval-form"><label>Plan<select value={activationForm.plan_slug} onChange={(event) => { const plan = data?.plans.find((item) => item.slug === event.target.value); setActivationForm({ ...activationForm, plan_slug: event.target.value, agreed_price_try: plan?.monthly_price_try != null ? String(plan.monthly_price_try) : activationForm.agreed_price_try }); }}>{availablePaidPlans.map((plan) => <option key={plan.slug} value={plan.slug}>{plan.name}</option>)}</select></label><label>Faturalama<select value={activationForm.billing_cycle} onChange={(event) => setActivationForm({ ...activationForm, billing_cycle: event.target.value })}><option value="monthly">Aylık</option><option value="annual">Yıllık</option><option value="manual">Manuel / özel anlaşma</option></select></label><label>Anlaşılan tutar (₺)<input type="number" min="0" step="0.01" value={activationForm.agreed_price_try} onChange={(event) => setActivationForm({ ...activationForm, agreed_price_try: event.target.value })}/></label><label className="wide">Onay / sözleşme notu<textarea rows={3} value={activationForm.approval_note} onChange={(event) => setActivationForm({ ...activationForm, approval_note: event.target.value })} placeholder="Ödeme, deneme sonucu, özel fiyat veya sözleşme notu"/></label></div><button className="primary-button platform-approve-button" disabled={Boolean(busyAction) || availablePaidPlans.length === 0} onClick={() => void approveClinic()}>{busyAction === "approve-clinic" ? <RefreshCw className="spin" size={17}/> : <CheckCircle2 size={17}/>}Onayla ve kliniği aktif et</button>{clinicDetail.conversionRequests.find((item) => item.status === "pending") && <button className="secondary-button danger-outline" disabled={Boolean(busyAction)} onClick={() => { const request = clinicDetail.conversionRequests.find((item) => item.status === "pending"); if (request && window.confirm(tx("Ücretli devam talebi reddedilsin mi?"))) void performAction({ action: "reject_conversion_request", clinic_id: selectedClinicId, request_id: request.id, admin_note: activationForm.approval_note }, "Ücretli devam talebi reddedildi.", { refreshDetail: true, key: "reject-conversion" }); }}>Talebi reddet</button>}</section>
                    ) : (
                      <section className="detail-section"><div className="detail-section-head"><h3>Ticari durum</h3><CheckCircle2 size={18}/></div><div className="detail-info-grid platform-detail-info"><div><small>Abonelik durumu</small><b>{statusLabel(clinicDetail.subscription?.status || "active")}</b></div><div><small>Faturalama</small><b>{clinicDetail.subscription?.billing_cycle === "annual" ? "Yıllık" : clinicDetail.subscription?.billing_cycle === "monthly" ? "Aylık" : "Manuel / özel"}</b></div><div><small>Anlaşılan tutar</small><b>{clinicDetail.subscription?.agreed_price_try == null ? "—" : formatMoney(clinicDetail.subscription.agreed_price_try)}</b></div><div><small>Dönem sonu</small><b>{formatDate(clinicDetail.subscription?.current_period_ends_at || null)}</b></div></div><div className="platform-inline-action platform-plan-action"><select value={planForm} onChange={(event) => setPlanForm(event.target.value)}>{data?.plans.filter((plan) => plan.is_active !== false && plan.slug !== "pilot").map((plan) => <option key={plan.slug} value={plan.slug}>{plan.name}</option>)}</select><button disabled={Boolean(busyAction) || planForm === clinicDetail.subscription?.plan_slug} onClick={() => { if (window.confirm(tx("Klinik planı değiştirilsin mi?"))) void performAction({ action: "change_plan", clinic_id: selectedClinicId, plan_slug: planForm }, "Klinik planı güncellendi.", { refreshDetail: true, key: "change-plan" }); }}>Planı güncelle</button></div></section>
                    )}

                    {clinicDetail.subscription?.plan_slug === "pilot" && <section className="detail-section"><div className="detail-section-head"><h3>Pilot süresini yönet</h3></div><div className="platform-inline-action"><input type="number" min="1" max="365" value={pilotExtensionDays} onChange={(event) => setPilotExtensionDays(event.target.value)}/><button disabled={Boolean(busyAction)} onClick={() => { const days = Number(pilotExtensionDays); if (!Number.isInteger(days) || days < 1 || days > 365) { setError("Pilot uzatma günü 1 ile 365 arasında olmalıdır."); return; } void performAction({ action: "extend_pilot", clinic_id: selectedClinicId, days }, `Pilot ${days} gün uzatıldı.`, { refreshDetail: true, key: "extend-detail" }); }}><CalendarClock size={15}/>Süreyi uzat</button></div></section>}

                    <section className="detail-section"><div className="detail-section-head"><h3>Platform notları</h3><FileText size={18}/></div><div className="platform-note-composer"><textarea rows={3} value={platformNote} onChange={(event) => setPlatformNote(event.target.value)} placeholder="Klinikle yapılan görüşme, özel şart veya takip notu"/><button className="secondary-button" disabled={Boolean(busyAction) || platformNote.trim().length < 2} onClick={async () => { const saved = await performAction({ action: "save_clinic_note", clinic_id: selectedClinicId, note: platformNote }, "Klinik notu kaydedildi.", { refreshDetail: true, key: "save-note" }); if (saved) setPlatformNote(""); }}>Notu kaydet</button></div><div className="platform-note-list">{clinicDetail.notes.map((item) => <article key={item.id}><p>{item.note}</p><small>{item.created_by_email} · {formatDateTime(item.created_at)}</small></article>)}{clinicDetail.notes.length === 0 && <p className="muted-line">Henüz platform notu yok.</p>}</div></section>

                    <section className="detail-section"><div className="detail-section-head"><h3>Son platform hareketleri</h3></div><div className="platform-audit-list">{clinicDetail.audit.slice(0, 12).map((item) => <article key={item.id}><b>{item.action}</b><small>{formatDateTime(item.created_at)} · {item.target_type || "sistem"}</small></article>)}{clinicDetail.audit.length === 0 && <p className="muted-line">Henüz hareket kaydı yok.</p>}</div></section>
                  </>
                )}
              </div>
            </aside>
          </div>
        )}
      </main>
    </LocalizedContent>
  );
}
