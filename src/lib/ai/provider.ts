type AIProvider = "xai" | "groq";

type AIContentPart =
  | { type: "input_text"; text: string }
  | { type: "input_image"; image_url: string; detail?: "low" | "high" | "auto" };

type AIResponsePayload = {
  output?: Array<{
    type?: string;
    content?: Array<{ type?: string; text?: string }>;
  }>;
  error?: { message?: string };
};

export type AIRequest = {
  content: AIContentPart[];
  vision?: boolean;
  maxOutputTokens?: number;
};

function resolveProvider(): AIProvider {
  const configured = (process.env.AI_PROVIDER || "").trim().toLowerCase();
  if (configured === "grok" || configured === "xai") return "xai";
  if (configured === "groq") return "groq";
  if (process.env.GROQ_API_KEY) return "groq";
  return "xai";
}

function providerConfig(provider: AIProvider, vision: boolean) {
  if (provider === "groq") {
    return {
      apiKey: process.env.GROQ_API_KEY,
      endpoint: "https://api.groq.com/openai/v1/responses",
      model: vision
        ? process.env.GROQ_VISION_MODEL || "qwen/qwen3.6-27b"
        : process.env.GROQ_MODEL || "llama-3.3-70b-versatile",
      label: "Groq",
    };
  }

  return {
    apiKey: process.env.XAI_API_KEY,
    endpoint: "https://api.x.ai/v1/responses",
    model: vision
      ? process.env.XAI_VISION_MODEL || process.env.XAI_MODEL || "grok-4.5"
      : process.env.XAI_MODEL || "grok-4.5",
    label: "xAI Grok",
  };
}

export function configuredAIProviderLabel() {
  return providerConfig(resolveProvider(), false).label;
}

export async function generateAIText({ content, vision = false, maxOutputTokens = 1800 }: AIRequest) {
  const provider = resolveProvider();
  const config = providerConfig(provider, vision);

  if (!config.apiKey) {
    const keyName = provider === "groq" ? "GROQ_API_KEY" : "XAI_API_KEY";
    throw new Error(`${config.label} bağlantısı için ${keyName} ortam değişkeni eklenmelidir.`);
  }

  const requestBody: Record<string, unknown> = {
    model: config.model,
    input: [{ role: "user", content }],
    max_output_tokens: maxOutputTokens,
  };

  // xAI image understanding documentation recommends disabling server-side storage.
  if (provider === "xai") requestBody.store = false;

  const response = await fetch(config.endpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${config.apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(requestBody),
    signal: AbortSignal.timeout(90_000),
  });

  const payload = (await response.json()) as AIResponsePayload;
  if (!response.ok) {
    throw new Error(payload.error?.message || `${config.label} servisi yanıt vermedi.`);
  }

  const text = (payload.output || [])
    .flatMap((item) => item.content || [])
    .filter((item) => item.type === "output_text")
    .map((item) => item.text || "")
    .join("\n")
    .trim();

  if (!text) throw new Error(`${config.label} boş yanıt döndürdü.`);
  return { text, provider: config.label, model: config.model };
}
