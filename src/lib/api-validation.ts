export function isUuid(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

export function parseBoundedInteger(value: unknown, fallback: number, min: number, max: number): number {
  const number = typeof value === "number" ? value : Number(String(value ?? "").trim());
  if (!Number.isFinite(number)) return fallback;
  return Math.min(max, Math.max(min, Math.trunc(number)));
}

export function parseBoundedNumber(value: unknown, fallback: number | null, min: number, max: number): number | null {
  if (value === "" || value === null || value === undefined) return fallback;
  const number = typeof value === "number" ? value : Number(String(value).trim().replace(",", "."));
  if (!Number.isFinite(number) || number < min || number > max) return fallback;
  return number;
}

export function parseBoolean(value: unknown, fallback = false): boolean {
  if (typeof value === "boolean") return value;
  if (value === "true" || value === 1 || value === "1") return true;
  if (value === "false" || value === 0 || value === "0") return false;
  return fallback;
}


export function parseStrictBoolean(value: unknown): boolean | null {
  if (typeof value === "boolean") return value;
  if (value === "true" || value === 1 || value === "1") return true;
  if (value === "false" || value === 0 || value === "0") return false;
  return null;
}

export function cleanText(value: unknown, maxLength: number): string {
  return String(value ?? "").replace(/\0/g, "").trim().slice(0, maxLength);
}

export function cleanEmail(value: unknown): string | null {
  const email = cleanText(value, 254).toLowerCase();
  if (!email) return null;
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : null;
}

export function sameOriginRequest(request: Request): boolean {
  const origin = request.headers.get("origin");
  if (!origin) return true;
  try {
    return new URL(origin).origin === new URL(request.url).origin;
  } catch {
    return false;
  }
}

export function publicErrorMessage(error: unknown, fallback: string): string {
  if (!(error instanceof Error)) return fallback;
  const message = error.message || fallback;
  const known = [
    "Yetkisiz",
    "zorunlu",
    "bulunamadı",
    "geçersiz",
    "plan",
    "pilot",
    "davet",
    "talep",
    "durum",
    "fiyat",
    "abonelik",
  ];
  return known.some((token) => message.toLocaleLowerCase("tr-TR").includes(token.toLocaleLowerCase("tr-TR")))
    ? message.slice(0, 500)
    : fallback;
}
