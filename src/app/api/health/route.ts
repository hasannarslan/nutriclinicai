import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

export function GET() {
  return NextResponse.json({
    status: "ok",
    app: "NutriClinic AI",
    version: "3.0.0",
    timestamp: new Date().toISOString(),
  });
}
