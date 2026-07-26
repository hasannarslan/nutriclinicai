import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import OnboardingClient from "./onboarding-client";

export const dynamic = "force-dynamic";

export default async function OnboardingPage({
  searchParams,
}: {
  searchParams: Promise<{ pilot?: string; invite?: string }>;
}) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: membership } = await supabase
    .from("clinic_memberships")
    .select("id")
    .eq("user_id", user.id)
    .eq("is_active", true)
    .order("created_at", { ascending: true })
    .limit(1)
    .maybeSingle();
  if (membership) redirect("/dashboard");

  const params = await searchParams;
  return (
    <OnboardingClient
      initialPilotToken={params.pilot || ""}
      initialInviteToken={params.invite || ""}
      email={user.email || ""}
    />
  );
}
