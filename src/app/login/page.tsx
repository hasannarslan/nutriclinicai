import { Suspense } from "react";
import LoginClient from "./login-client";

export default function LoginPage() {
  const configured = Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL && (process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY));
  return (
    <Suspense fallback={<main className="center-state"><p>Yükleniyor…</p></main>}>
      <LoginClient configured={configured} />
    </Suspense>
  );
}
