import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

export function GET() {
  const checks = {
    supabase: Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL && (process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY)),
    serviceRole: Boolean(process.env.SUPABASE_SERVICE_ROLE_KEY),
    platformAdmin: Boolean(process.env.PLATFORM_ADMIN_EMAILS),
    ai: Boolean(process.env.XAI_API_KEY || process.env.GROQ_API_KEY),
    cron: Boolean(process.env.CRON_SECRET),
  };
  const ready = checks.supabase && checks.serviceRole && checks.platformAdmin;
  return NextResponse.json({
    status: ready ? "ok" : "degraded",
    app: "NutriClinic AI",
    version: "0.8.1",
    edition: "Stabilized SaaS v8.1",
    checks,
    timestamp: new Date().toISOString(),
  }, { status: ready ? 200 : 503 });
}
