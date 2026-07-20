"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import {
  Activity,
  Apple,
  CalendarDays,
  ChevronRight,
  CircleDollarSign,
  Gift,
  LayoutDashboard,
  LogOut,
  Menu,
  MessageCircle,
  Settings,
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

type View =
  | "dashboard"
  | "appointments"
  | "clients"
  | "payments"
  | "mealPlans"
  | "measurements"
  | "loyalty"
  | "community"
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
    "team",
    "settings",
  ],
  dietitian: [
    "dashboard",
    "appointments",
    "clients",
    "mealPlans",
    "measurements",
    "loyalty",
    "community",
    "settings",
  ],
  secretary: ["dashboard", "appointments", "clients", "payments", "settings"],
  client: [
    "dashboard",
    "appointments",
    "mealPlans",
    "measurements",
    "loyalty",
    "community",
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
}: {
  initialProfile: Profile;
  initialMembership: Membership;
  clinic: Clinic;
}) {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);
  const [profile, setProfile] = useState(initialProfile);
  const [membership, setMembership] = useState(initialMembership);
  const [clinicInfo, setClinicInfo] = useState(clinic);
  const [view, setView] = useState<View>("dashboard");
  const [menuOpen, setMenuOpen] = useState(false);
  const [notice, setNotice] = useState("");
  const locale = profile.preferred_locale || clinicInfo.default_locale;
  const t = dictionaries[locale];

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
    { id: "team", label: t.team, icon: <UserCog size={19} /> },
    { id: "settings", label: t.settings, icon: <Settings size={19} /> },
  ];

  return (
    <main className="app-shell v3-shell">
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
          <div className="profile-chip v3-profile-chip">
            <span>{initials(profile.full_name)}</span>
            <div>
              <b>{profile.full_name}</b>
              <small>{profile.email || profile.phone || "Hesap"}</small>
            </div>
          </div>
        </header>

        <div className="page-content v3-page-content">
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
          {view === "team" && membership.role === "owner" && (
            <TeamV3 clinicId={clinicInfo.id} currentUserId={profile.id} />
          )}
          {view === "settings" && (
            <ProfileSettingsV3
              profile={profile}
              role={membership.role}
              clinic={clinicInfo}
              onUpdated={setProfile}
              onClinicUpdated={setClinicInfo}
            />
          )}
        </div>
      </section>
    </main>
  );
}
