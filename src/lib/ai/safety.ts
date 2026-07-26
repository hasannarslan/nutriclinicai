export function parseAIJson(text: string): Record<string, unknown> {
  const cleaned = String(text || "")
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/```\s*$/i, "")
    .trim();
  if (!cleaned) throw new Error("AI boş yanıt döndürdü.");

  try {
    const value = JSON.parse(cleaned);
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error();
    return value as Record<string, unknown>;
  } catch {
    const objectStart = cleaned.indexOf("{");
    const objectEnd = cleaned.lastIndexOf("}");
    if (objectStart >= 0 && objectEnd > objectStart) {
      const value = JSON.parse(cleaned.slice(objectStart, objectEnd + 1));
      if (value && typeof value === "object" && !Array.isArray(value)) return value as Record<string, unknown>;
    }
    throw new Error("AI yanıtı geçerli JSON formatında değildi.");
  }
}

export function cleanText(value: unknown, maxLength: number, fallback = "") {
  const text = typeof value === "string" || typeof value === "number" ? String(value).trim() : "";
  return (text || fallback).slice(0, maxLength);
}

export function cleanStringArray(value: unknown, maxItems = 30, maxLength = 120) {
  if (!Array.isArray(value)) return [] as string[];
  return value
    .map((item) => cleanText(item, maxLength))
    .filter(Boolean)
    .slice(0, maxItems);
}

export function finiteNumber(value: unknown, options: { min: number; max: number; fallback: number }) {
  const number = Number(value);
  if (!Number.isFinite(number)) return options.fallback;
  return Math.min(options.max, Math.max(options.min, number));
}

export function safeJsonValue(value: unknown, maxLength = 4000) {
  try {
    return JSON.stringify(value ?? null).slice(0, maxLength);
  } catch {
    return "null";
  }
}
