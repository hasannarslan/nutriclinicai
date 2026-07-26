import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import DashboardClient from "./dashboard-client";
import type { Clinic, Membership, Profile } from "@/lib/types";
import { isPlatformAdminEmail } from "@/lib/platform-admin";

export const dynamic = "force-dynamic";
export default async function DashboardPage() {
  if (!process.env.NEXT_PUBLIC_SUPABASE_URL || !(process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY)) redirect("/login?setup=missing");

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const [{ data: profile }, { data: membership }] = await Promise.all([
    supabase.from("profiles").select("id,full_name,email,phone,preferred_locale").eq("id", user.id).single(),
    supabase.from("clinic_memberships").select("id,clinic_id,user_id,role,is_active,created_at").eq("user_id", user.id).eq("is_active", true).order("created_at", { ascending: true }).limit(1).maybeSingle(),
  ]);

  if (!profile) {
    return (
      <main className="center-state">
        <h1>Hesap hazırlanıyor</h1>
        <p>Kayıt profili henüz oluşmadı. Sayfayı birkaç saniye sonra yenileyin.</p>
      </main>
    );
  }
  if (!membership) redirect("/onboarding");

  const { data: clinic } = await supabase.from("clinics").select("id,name,slug,default_locale,timezone,phone,email,address,website,booking_horizon_days,minimum_booking_notice_hours,cancellation_notice_hours,allow_client_cancellation,allow_online_booking").eq("id", membership.clinic_id).single();
  if (!clinic) redirect("/login");

  return <DashboardClient initialProfile={profile as Profile} initialMembership={membership as Membership} clinic={clinic as Clinic} isPlatformAdmin={isPlatformAdminEmail(user.email)} />;
}
