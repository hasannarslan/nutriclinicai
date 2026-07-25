import { Suspense } from "react";
import LoginClient from "./login-client";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ platform_setup?: string }>;
}) {
  const configured = Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL && (process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY));
  const params = await searchParams;
  const platformSetupAllowed = Boolean(
    process.env.PLATFORM_SETUP_TOKEN &&
    params.platform_setup &&
    params.platform_setup === process.env.PLATFORM_SETUP_TOKEN
  );
  return (
    <Suspense fallback={<main className="center-state"><p>Yükleniyor…</p></main>}>
      <LoginClient configured={configured} platformSetupAllowed={platformSetupAllowed} />
    </Suspense>
  );
}
