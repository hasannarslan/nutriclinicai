"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import {
  Activity,
  Apple,
  CalendarDays,
  Boxes,
  ClipboardCheck,
  FileArchive,
  Gauge,
  MessagesSquare,
  PackageOpen,
  ChevronRight,
  CircleDollarSign,
  Gift,
  LayoutDashboard,
  LogOut,
  Menu,
  MessageCircle,
  Settings,
  Sparkles,
  Quote,
  Shield,
  UserCog,
  UsersRound,
  UtensilsCrossed,
  X,
} from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { dictionaries } from "@/lib/i18n";
import type { Clinic, Membership, Profile, Role } from "@/lib/types";
import {
  AppointmentsV3,
  ClientsV3,
  CommunityV3,
  MealPlansV3,
  OverviewV3,
  PaymentsV3,
} from "./v3-views";
import {
  LoyaltyV3,
  MeasurementsV3,
  ProfileSettingsV3,
  TeamV3,
} from "./support-views";
import { ClientExperienceV4 } from "./client-experience-v4";
import { NotificationCenter } from "./notification-center";
import {
  DirectMessagesV6,
  DocumentsV6,
  FollowupV6,
  FormsConsentsV6,
  PackagesV6,
  PwaInstallCard,
  ResourcesV6,
} from "./ops-v6";
import { PwaRegister } from "./pwa-register";
import { PilotFeedback, SaasAccessGate, SaasPilotBanner } from "./saas-pilot";

type View =
  | "dashboard"
  | "appointments"
  | "clients"
  | "payments"
  | "mealPlans"
  | "measurements"
  | "loyalty"
  | "community"
  | "packages"
  | "resources"
  | "forms"
  | "documents"
  | "messages"
  | "followup"
  | "team"
  | "settings";

const permissions: Record<Role, View[]> = {
  owner: [
    "dashboard",
    "appointments",
    "clients",
    "payments",
    "mealPlans",
    "measurements",
    "loyalty",
    "community",
    "packages",
    "resources",
    "forms",
    "documents",
    "messages",
    "followup",
    "team",
    "settings",
  ],
  dietitian: [
    "dashboard",
    "appointments",
    "clients",
    "payments",
    "mealPlans",
    "measurements",
    "loyalty",
    "community",
    "packages",
    "resources",
    "forms",
    "documents",
    "messages",
    "followup",
    "settings",
  ],
  secretary: ["dashboard", "appointments", "clients", "payments", "packages", "resources", "documents", "settings"],
  client: [
    "dashboard",
    "appointments",
    "mealPlans",
    "measurements",
    "loyalty",
    "community",
    "packages",
    "resources",
    "forms",
    "documents",
    "messages",
    "followup",
    "settings",
  ],
};

function initials(name: string) {
  return name
    .split(" ")
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0])
    .join("")
    .toUpperCase();
}

export default function DashboardClient({
  initialProfile,
  initialMembership,
  clinic,
  isPlatformAdmin,
}: {
  initialProfile: Profile;
  initialMembership: Membership;
  clinic: Clinic;
  isPlatformAdmin: boolean;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const supabase = useMemo(() => createClient(), []);
  const [profile, setProfile] = useState(initialProfile);
  const [membership, setMembership] = useState(initialMembership);
  const [clinicInfo, setClinicInfo] = useState(clinic);
  const [view, setView] = useState<View>("dashboard");
  const [menuOpen, setMenuOpen] = useState(false);
  const [notice, setNotice] = useState("");
  const [motivation, setMotivation] = useState<string | null>(null);
  const locale = profile.preferred_locale || clinicInfo.default_locale;
  const t = dictionaries[locale];

  useEffect(() => {
    if (membership.role !== "client") return;
    let active = true;
    (async () => {
      const { data } = await supabase.rpc("claim_daily_motivation_v5");
      const message = (data as { message?: string } | null)?.message;
      if (active && message) setMotivation(message);
    })();
    return () => { active = false; };
  }, [membership.role, supabase]);

  useEffect(() => {
    const requested = searchParams.get("view") as View | null;
    if (requested && permissions[membership.role].includes(requested)) setView(requested);
  }, [membership.role, searchParams]);

  useEffect(() => {
    const navigate = (event: Event) => {
      const nextView = (event as CustomEvent<View>).detail;
      if (permissions[membership.role].includes(nextView)) {
        setView(nextView);
        setMenuOpen(false);
      }
    };
    window.addEventListener("nutriclinic:navigate", navigate);
    return () => window.removeEventListener("nutriclinic:navigate", navigate);
  }, [membership.role]);

  async function logout() {
    await supabase.auth.signOut();
    router.replace("/login");
    router.refresh();
  }

  async function claimFirstOwner() {
    setNotice("");
    const { data, error } = await supabase.rpc("claim_first_owner");
    if (error) {
      setNotice(error.message);
      return;
    }
    if (!data) {
      setNotice("Sistemde zaten bir klinik sahibi bulunuyor.");
      return;
    }

    const { data: fresh, error: membershipError } = await supabase
      .from("clinic_memberships")
      .select("id,clinic_id,user_id,role,is_active")
      .eq("id", membership.id)
      .single();

    if (membershipError) {
      setNotice(membershipError.message);
      return;
    }
    if (fresh) setMembership(fresh as Membership);
    setNotice("Klinik sahibi hesabı etkinleştirildi.");
    router.refresh();
  }

  const navItems: Array<{
    id: View;
    label: string;
    icon: React.ReactNode;
  }> = [
    { id: "dashboard", label: t.dashboard, icon: <LayoutDashboard size={19} /> },
    { id: "appointments", label: t.appointments, icon: <CalendarDays size={19} /> },
    { id: "clients", label: t.clients, icon: <UsersRound size={19} /> },
    { id: "payments", label: t.payments, icon: <CircleDollarSign size={19} /> },
    { id: "mealPlans", label: t.mealPlans, icon: <UtensilsCrossed size={19} /> },
    { id: "measurements", label: t.measurements, icon: <Activity size={19} /> },
    { id: "loyalty", label: t.loyalty, icon: <Gift size={19} /> },
    { id: "community", label: t.community, icon: <MessageCircle size={19} /> },
    { id: "packages", label: t.packages, icon: <PackageOpen size={19} /> },
    { id: "resources", label: t.resources, icon: <Boxes size={19} /> },
    { id: "forms", label: t.forms, icon: <ClipboardCheck size={19} /> },
    { id: "documents", label: t.documents, icon: <FileArchive size={19} /> },
    { id: "messages", label: t.messages, icon: <MessagesSquare size={19} /> },
    { id: "followup", label: t.followup, icon: <Gauge size={19} /> },
    { id: "team", label: t.team, icon: <UserCog size={19} /> },
    { id: "settings", label: t.settings, icon: <Settings size={19} /> },
  ];

  return (
    <main className="app-shell v3-shell">
      <PwaRegister />
      {motivation && (
        <div className="daily-motivation-overlay" role="dialog" aria-modal="true" aria-label="Günün motivasyonu">
          <section className="daily-motivation-modal">
            <button type="button" onClick={() => setMotivation(null)} aria-label="Kapat"><X size={20} /></button>
            <div className="motivation-symbol"><Sparkles size={28} /><Quote size={34} /></div>
            <span>BUGÜNÜN MESAJI</span>
            <h2>{motivation}</h2>
            <p>Bugün yalnızca bir sonraki doğru adıma odaklan.</p>
            <button type="button" className="primary-button" onClick={() => setMotivation(null)}>Günüme başla</button>
          </section>
        </div>
      )}
      {menuOpen && (
        <button
          type="button"
          className="mobile-overlay"
          onClick={() => setMenuOpen(false)}
          aria-label="Menüyü kapat"
        />
      )}

      <aside className={`sidebar v3-sidebar ${menuOpen ? "open" : ""}`}>
        <div className="sidebar-brand">
          <span>
            <Apple size={21} />
          </span>
          <b>
            NutriClinic <em>AI</em>
          </b>
          <button type="button" onClick={() => setMenuOpen(false)} aria-label="Menüyü kapat">
            <X size={18} />
          </button>
        </div>

        <div className="clinic-card v3-clinic-card">
          <div>{initials(clinicInfo.name)}</div>
          <span>
            <b>{clinicInfo.name}</b>
            <small>{t[membership.role]}</small>
          </span>
        </div>

        <nav>
          {navItems
            .filter((item) => permissions[membership.role].includes(item.id))
            .map((item) => (
              <button
                type="button"
                key={item.id}
                className={view === item.id ? "active" : ""}
                onClick={() => {
                  setView(item.id);
                  setMenuOpen(false);
                }}
              >
                {item.icon}
                <span>{item.label}</span>
                <ChevronRight size={15} />
              </button>
            ))}
        </nav>

        <button type="button" className="logout-button" onClick={logout}>
          <LogOut size={18} />
          {t.signOut}
        </button>
      </aside>

      <section className="app-main">
        <header className="topbar v3-topbar">
          <button type="button" className="menu-button" onClick={() => setMenuOpen(true)}>
            <Menu size={21} />
          </button>
          <div className="topbar-copy">
            <h2>
              {t.welcome}, {profile.full_name.split(" ")[0]}
            </h2>
            <p>
              {clinicInfo.name} • {t[membership.role]}
            </p>
          </div>
          <div className="topbar-account-actions">
            {isPlatformAdmin && <a className="platform-admin-link" href="/platform-admin"><Shield size={16}/><span>Platform Admin</span></a>}
            <NotificationCenter
              userId={profile.id}
              role={membership.role}
              locale={locale}
              onNavigate={(nextView) => {
                if (permissions[membership.role].includes(nextView)) setView(nextView);
                else setView("dashboard");
              }}
            />
            <button type="button" className="profile-chip v3-profile-chip" onClick={() => setView("settings")} aria-label="Profil ve ayarları aç">
              <span>{initials(profile.full_name)}</span>
              <div>
                <b>{profile.full_name}</b>
                <small>{profile.email || profile.phone || "Hesap"}</small>
              </div>
            </button>
          </div>
        </header>

        <div className="page-content v3-page-content">
          <SaasPilotBanner role={membership.role} />
          {notice && (
            <div className="notice-bar">
              <span>{notice}</span>
              <button type="button" onClick={() => setNotice("")} aria-label="Bildirimi kapat">
                <X size={15} />
              </button>
            </div>
          )}

          {view === "dashboard" && (membership.role === "client" ? (
            <ClientExperienceV4 clinicId={clinicInfo.id} />
          ) : (
            <OverviewV3
              role={membership.role}
              clinicId={clinicInfo.id}
              fullName={profile.full_name}
              onClaimOwner={claimFirstOwner}
            />
          ))}
          {view === "appointments" && (
            <AppointmentsV3 role={membership.role} clinicId={clinicInfo.id} />
          )}
          {view === "clients" && (
            <ClientsV3 role={membership.role} clinicId={clinicInfo.id} />
          )}
          {view === "payments" && (
            <PaymentsV3 role={membership.role} clinicId={clinicInfo.id} />
          )}
          {view === "mealPlans" && (
            <MealPlansV3 role={membership.role} clinicId={clinicInfo.id} />
          )}
          {view === "measurements" && (
            <MeasurementsV3 role={membership.role} clinicId={clinicInfo.id} />
          )}
          {view === "loyalty" && (
            <LoyaltyV3 role={membership.role} clinicId={clinicInfo.id} />
          )}
          {view === "community" && (
            <CommunityV3 role={membership.role} clinicId={clinicInfo.id} />
          )}
          {view === "packages" && (
            <PackagesV6 role={membership.role} clinicId={clinicInfo.id} />
          )}
          {view === "resources" && (
            <ResourcesV6 role={membership.role} clinicId={clinicInfo.id} />
          )}
          {view === "forms" && membership.role !== "secretary" && (
            <FormsConsentsV6 role={membership.role} clinicId={clinicInfo.id} />
          )}
          {view === "documents" && (
            <DocumentsV6 role={membership.role} clinicId={clinicInfo.id} />
          )}
          {view === "messages" && membership.role !== "secretary" && (
            <DirectMessagesV6 role={membership.role} clinicId={clinicInfo.id} />
          )}
          {view === "followup" && membership.role !== "secretary" && (
            <FollowupV6 role={membership.role} clinicId={clinicInfo.id} />
          )}
          {view === "team" && membership.role === "owner" && (
            <TeamV3 clinicId={clinicInfo.id} currentUserId={profile.id} />
          )}
          {view === "settings" && (
            <>
              <ProfileSettingsV3
                profile={profile}
                role={membership.role}
                clinic={clinicInfo}
                onUpdated={setProfile}
                onClinicUpdated={setClinicInfo}
              />
              <PwaInstallCard />
            </>
          )}
        </div>
        <PilotFeedback role={membership.role} />
        <SaasAccessGate isPlatformAdmin={isPlatformAdmin} />
      </section>
    </main>
  );
}
