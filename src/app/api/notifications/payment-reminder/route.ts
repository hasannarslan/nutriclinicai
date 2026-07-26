import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { cleanText, isUuid, sameOriginRequest } from "@/lib/api-validation";
import { intlLocales, normalizeLocale } from "@/lib/i18n";
import type { Locale } from "@/lib/types";

export const runtime = "nodejs";
export const maxDuration = 60;

type Channel = "email" | "sms";

type ReminderCopy = {
  genericClient: string;
  genericService: string;
  subject: (clinicName: string) => string;
  greeting: (clientName: string) => string;
  body: (service: string, amount: string, timing: string) => string;
  contact: string;
  dueDate: string;
  noDate: string;
  overdue: (days: number) => string;
  dueToday: string;
  daysLeft: (days: number) => string;
};

const reminderCopy: Record<Locale, ReminderCopy> = {
  tr: {
    genericClient: "Danışan",
    genericService: "Hizmet",
    subject: (clinic) => `${clinic} ödeme hatırlatması`,
    greeting: (client) => `Merhaba ${client}`,
    body: (service, amount, timing) => `${service} hizmetine ait kalan ${amount} tutarındaki ödemeniz için ${timing}.`,
    contact: "Detaylar için kliniğinizle iletişime geçebilirsiniz.",
    dueDate: "Son ödeme tarihi",
    noDate: "ödeme tarihi belirlenmemiştir",
    overdue: (days) => `ödemeniz ${days} gün gecikmiştir`,
    dueToday: "ödeme tarihiniz bugündür",
    daysLeft: (days) => `ödeme tarihinize ${days} gün kalmıştır`,
  },
  en: {
    genericClient: "Client",
    genericService: "Service",
    subject: (clinic) => `${clinic} payment reminder`,
    greeting: (client) => `Hello ${client}`,
    body: (service, amount, timing) => `Your remaining payment of ${amount} for ${service} ${timing}.`,
    contact: "Please contact your clinic for details.",
    dueDate: "Due date",
    noDate: "does not have a due date yet",
    overdue: (days) => `is ${days} days overdue`,
    dueToday: "is due today",
    daysLeft: (days) => `is due in ${days} days`,
  },
  el: {
    genericClient: "Πελάτης",
    genericService: "Υπηρεσία",
    subject: (clinic) => `Υπενθύμιση πληρωμής από ${clinic}`,
    greeting: (client) => `Γεια σας ${client}`,
    body: (service, amount, timing) => `Η υπόλοιπη πληρωμή ${amount} για την υπηρεσία ${service} ${timing}.`,
    contact: "Επικοινωνήστε με την κλινική σας για λεπτομέρειες.",
    dueDate: "Ημερομηνία λήξης",
    noDate: "δεν έχει ακόμη ημερομηνία λήξης",
    overdue: (days) => `έχει καθυστερήσει ${days} ημέρες`,
    dueToday: "λήγει σήμερα",
    daysLeft: (days) => `λήγει σε ${days} ημέρες`,
  },
  ru: {
    genericClient: "Клиент",
    genericService: "Услуга",
    subject: (clinic) => `Напоминание об оплате от ${clinic}`,
    greeting: (client) => `Здравствуйте, ${client}`,
    body: (service, amount, timing) => `Остаток оплаты ${amount} за услугу «${service}» ${timing}.`,
    contact: "Для уточнения свяжитесь с клиникой.",
    dueDate: "Срок оплаты",
    noDate: "пока не имеет срока оплаты",
    overdue: (days) => `просрочен на ${days} дн.`,
    dueToday: "должен быть оплачен сегодня",
    daysLeft: (days) => `должен быть оплачен через ${days} дн.`,
  },
  de: {
    genericClient: "Klient",
    genericService: "Leistung",
    subject: (clinic) => `Zahlungserinnerung von ${clinic}`,
    greeting: (client) => `Guten Tag ${client}`,
    body: (service, amount, timing) => `Der offene Betrag von ${amount} für ${service} ${timing}.`,
    contact: "Für weitere Informationen wenden Sie sich bitte an Ihre Praxis.",
    dueDate: "Fälligkeitsdatum",
    noDate: "hat noch kein Fälligkeitsdatum",
    overdue: (days) => `ist seit ${days} Tagen überfällig`,
    dueToday: "ist heute fällig",
    daysLeft: (days) => `ist in ${days} Tagen fällig`,
  },
};

function json(body: Record<string, unknown>, status = 200) {
  return NextResponse.json(body, { status, headers: { "Cache-Control": "no-store, max-age=0" } });
}

function formatMoney(value: number, currency: string, locale: Locale) {
  const safeCurrency = /^[A-Z]{3}$/.test(currency) ? currency : "TRY";
  try {
    return new Intl.NumberFormat(intlLocales[locale], { style: "currency", currency: safeCurrency }).format(Number.isFinite(value) ? value : 0);
  } catch {
    return new Intl.NumberFormat(intlLocales[locale], { style: "currency", currency: "TRY" }).format(Number.isFinite(value) ? value : 0);
  }
}

function formatDate(value: string, locale: Locale) {
  const date = new Date(`${value}T12:00:00`);
  return Number.isNaN(date.getTime()) ? "" : new Intl.DateTimeFormat(intlLocales[locale], { dateStyle: "medium" }).format(date);
}

function escapeHtml(value: unknown) {
  return String(value ?? "").replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;",
  })[character] || character);
}

async function sendEmail(to: string, subject: string, text: string, html: string) {
  const apiKey = process.env.RESEND_API_KEY;
  const from = process.env.RESEND_FROM;
  if (!apiKey || !from) throw new Error("E-posta gönderimi için RESEND_API_KEY ve RESEND_FROM ayarlanmalıdır.");
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from, to, subject, text, html }),
  });
  const payload = await response.json().catch(() => ({})) as { id?: unknown; message?: unknown };
  if (!response.ok) throw new Error(typeof payload.message === "string" ? payload.message.slice(0, 500) : `E-posta gönderilemedi (${response.status}).`);
  return String(payload.id || "").slice(0, 250);
}

async function sendSms(to: string, body: string) {
  const sid = process.env.TWILIO_ACCOUNT_SID;
  const token = process.env.TWILIO_AUTH_TOKEN;
  const from = process.env.TWILIO_FROM_NUMBER;
  const messagingServiceSid = process.env.TWILIO_MESSAGING_SERVICE_SID;
  if (!sid || !token || (!from && !messagingServiceSid)) {
    throw new Error("SMS için TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN ve gönderici numarası veya Messaging Service ayarlanmalıdır.");
  }
  const params = new URLSearchParams({ To: to, Body: body.slice(0, 1500) });
  if (messagingServiceSid) params.set("MessagingServiceSid", messagingServiceSid);
  else if (from) params.set("From", from);
  const response = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${encodeURIComponent(sid)}/Messages.json`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${Buffer.from(`${sid}:${token}`).toString("base64")}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: params.toString(),
  });
  const payload = await response.json().catch(() => ({})) as { sid?: unknown; message?: unknown };
  if (!response.ok) throw new Error(typeof payload.message === "string" ? payload.message.slice(0, 500) : `SMS gönderilemedi (${response.status}).`);
  return String(payload.sid || "").slice(0, 250);
}

export async function POST(request: Request) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return json({ error: "Oturum gerekli." }, 401);
  if (!sameOriginRequest(request)) return json({ error: "Geçersiz istek kaynağı." }, 403);

  let paymentId = "";
  let channel: Channel = "email";
  try {
    const contentLength = Number(request.headers.get("content-length") || 0);
    if (contentLength > 16_000) return json({ error: "İstek verisi çok büyük." }, 413);
    const body = await request.json().catch(() => null) as { payment_id?: unknown; channel?: unknown } | null;
    if (!body) return json({ error: "Geçersiz istek." }, 400);
    paymentId = cleanText(body.payment_id, 50);
    channel = body.channel === "sms" ? "sms" : "email";
    if (!isUuid(paymentId)) return json({ error: "Ödeme kaydı geçersiz." }, 400);

    const { data: membership, error: membershipError } = await supabase
      .from("clinic_memberships")
      .select("clinic_id,role")
      .eq("user_id", user.id)
      .eq("is_active", true)
      .order("created_at", { ascending: true })
      .limit(1)
      .maybeSingle();
    if (membershipError) throw new Error("Klinik üyeliği doğrulanamadı.");
    if (!membership || !["owner", "dietitian", "secretary"].includes(membership.role)) {
      return json({ error: "Hatırlatma gönderme yetkiniz yok." }, 403);
    }

    const { data: payment, error: paymentError } = await supabase
      .from("payments")
      .select("id,clinic_id,client_id,service_type,description,amount,paid_amount,remaining_amount,currency,status,due_date")
      .eq("id", paymentId)
      .eq("clinic_id", membership.clinic_id)
      .maybeSingle();
    if (paymentError) throw new Error("Ödeme kaydı okunamadı.");
    if (!payment) return json({ error: "Ödeme bulunamadı." }, 404);

    const [{ data: client, error: clientError }, { data: clinic, error: clinicError }] = await Promise.all([
      supabase.from("client_profiles").select("id,user_id,full_name,email,phone,assigned_dietitian_id").eq("id", payment.client_id).eq("clinic_id", membership.clinic_id).maybeSingle(),
      supabase.from("clinics").select("name,phone,email,default_locale").eq("id", membership.clinic_id).maybeSingle(),
    ]);
    if (clientError || clinicError) throw new Error("Danışan veya klinik bilgileri okunamadı.");
    if (!client || !clinic) return json({ error: "Danışan veya klinik bulunamadı." }, 404);

    if (membership.role === "dietitian") {
      const { data: dietitian, error: dietitianError } = await supabase.from("dietitian_profiles").select("id").eq("clinic_id", membership.clinic_id).eq("user_id", user.id).maybeSingle();
      if (dietitianError) throw new Error("Diyetisyen yetkisi doğrulanamadı.");
      if (!dietitian || client.assigned_dietitian_id !== dietitian.id) {
        return json({ error: "Bu danışan size bağlı değil." }, 403);
      }
    }

    let locale = normalizeLocale(clinic.default_locale);
    if (client.user_id) {
      const { data: clientProfile } = await supabase.from("profiles").select("preferred_locale").eq("id", client.user_id).maybeSingle();
      locale = normalizeLocale(clientProfile?.preferred_locale, locale);
    }
    const copy = reminderCopy[locale];
    const dueDate = payment.due_date ? new Date(`${payment.due_date}T12:00:00`) : null;
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const days = dueDate && !Number.isNaN(dueDate.getTime()) ? Math.ceil((dueDate.getTime() - today.getTime()) / 86_400_000) : null;
    const timing = days == null ? copy.noDate : days < 0 ? copy.overdue(Math.abs(days)) : days === 0 ? copy.dueToday : copy.daysLeft(days);
    const clinicName = cleanText(clinic.name || "NutriClinic AI", 180) || "NutriClinic AI";
    const clientName = cleanText(client.full_name, 180) || copy.genericClient;
    const serviceType = cleanText(payment.service_type, 180) || copy.genericService;
    const title = copy.subject(clinicName);
    const reminderAmount = Number(payment.remaining_amount ?? Math.max(0, Number(payment.amount) - Number(payment.paid_amount || 0)));
    const amountText = formatMoney(Number.isFinite(reminderAmount) ? Math.max(0, reminderAmount) : 0, String(payment.currency || "TRY"), locale);
    const greeting = copy.greeting(clientName);
    const bodyLine = copy.body(serviceType, amountText, timing);
    const text = `${greeting}, ${bodyLine} ${copy.contact}`;
    const dueDateText = payment.due_date ? formatDate(payment.due_date, locale) : "";
    const html = `<div style="font-family:Arial,sans-serif;max-width:560px;margin:auto;padding:24px"><h2>${escapeHtml(title)}</h2><p>${escapeHtml(greeting)},</p><p>${escapeHtml(bodyLine)}</p>${dueDateText ? `<p>${escapeHtml(copy.dueDate)}: <strong>${escapeHtml(dueDateText)}</strong></p>` : ""}<p>${escapeHtml(copy.contact)}</p><p>${escapeHtml(clinicName)}</p></div>`;

    const recipient = channel === "email" ? cleanText(client.email, 254) : cleanText(client.phone, 50);
    if (!recipient) return json({ error: channel === "email" ? "Danışanın e-posta adresi yok." : "Danışanın telefon numarası yok." }, 400);

    const providerMessageId = channel === "email"
      ? await sendEmail(recipient, title, text, html)
      : await sendSms(recipient, text);

    const { error: logError } = await supabase.rpc("record_payment_reminder_v5", {
      p_payment_id: payment.id,
      p_channel: channel,
      p_recipient: recipient,
      p_status: "sent",
      p_provider_message_id: providerMessageId,
      p_error_message: null,
    });
    if (logError) throw new Error("Hatırlatma gönderildi ancak kayıt güncellenemedi.");

    return json({ ok: true, channel, recipient, provider_message_id: providerMessageId, locale });
  } catch (error) {
    const publicMessage = error instanceof Error ? error.message.slice(0, 500) : "Hatırlatma gönderilemedi.";
    if (paymentId && isUuid(paymentId)) {
      try {
        await supabase.rpc("record_payment_reminder_v5", {
          p_payment_id: paymentId,
          p_channel: channel,
          p_recipient: null,
          p_status: "failed",
          p_provider_message_id: null,
          p_error_message: publicMessage,
        });
      } catch { /* logging failure must not hide the primary error */ }
    }
    return json({ error: publicMessage || "Hatırlatma gönderilemedi." }, 500);
  }
}
