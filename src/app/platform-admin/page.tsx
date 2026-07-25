import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { isPlatformAdminEmail } from "@/lib/platform-admin";
import PlatformAdminClient from "./platform-admin-client";

export const dynamic = "force-dynamic";

export default async function PlatformAdminPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");
  if (!isPlatformAdminEmail(user.email)) redirect("/dashboard");
  return <PlatformAdminClient email={user.email || "Platform Admin"}/>;
}
