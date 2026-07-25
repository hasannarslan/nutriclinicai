import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export const runtime = "nodejs";
export const maxDuration = 60;

type Channel = "email" | "sms";

function formatMoney(value: number, currency = "TRY") {
  return new Intl.NumberFormat("tr-TR", { style: "currency", currency }).format(value);
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
  const payload = await response.json();
  if (!response.ok) throw new Error(payload?.message || "E-posta gönderilemedi.");
  return String(payload?.id || "");
}

async function sendSms(to: string, body: string) {
  const sid = process.env.TWILIO_ACCOUNT_SID;
  const token = process.env.TWILIO_AUTH_TOKEN;
  const from = process.env.TWILIO_FROM_NUMBER;
  const messagingServiceSid = process.env.TWILIO_MESSAGING_SERVICE_SID;
  if (!sid || !token || (!from && !messagingServiceSid)) {
    throw new Error("SMS için TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN ve gönderici numarası veya Messaging Service ayarlanmalıdır.");
  }
  const params = new URLSearchParams({ To: to, Body: body });
  if (messagingServiceSid) params.set("MessagingServiceSid", messagingServiceSid);
  else if (from) params.set("From", from);
  const response = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${Buffer.from(`${sid}:${token}`).toString("base64")}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: params.toString(),
  });
  const payload = await response.json();
  if (!response.ok) throw new Error(payload?.message || "SMS gönderilemedi.");
  return String(payload?.sid || "");
}

export async function POST(request: Request) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Oturum gerekli." }, { status: 401 });

  let paymentId = "";
  let channel: Channel = "email";
  try {
    const body = await request.json();
    paymentId = String(body.payment_id || "");
    channel = body.channel === "sms" ? "sms" : "email";
    if (!paymentId) return NextResponse.json({ error: "Ödeme kaydı zorunludur." }, { status: 400 });

    const { data: membership } = await supabase
      .from("clinic_memberships")
      .select("clinic_id,role")
      .eq("user_id", user.id)
      .eq("is_active", true)
      .single();
    if (!membership || !["owner", "dietitian", "secretary"].includes(membership.role)) {
      return NextResponse.json({ error: "Hatırlatma gönderme yetkiniz yok." }, { status: 403 });
    }

    const { data: payment, error: paymentError } = await supabase
      .from("payments")
      .select("id,clinic_id,client_id,service_type,description,amount,paid_amount,remaining_amount,currency,status,due_date")
      .eq("id", paymentId)
      .eq("clinic_id", membership.clinic_id)
      .single();
    if (paymentError || !payment) return NextResponse.json({ error: paymentError?.message || "Ödeme bulunamadı." }, { status: 404 });

    const [{ data: client }, { data: clinic }] = await Promise.all([
      supabase.from("client_profiles").select("id,user_id,full_name,email,phone,assigned_dietitian_id").eq("id", payment.client_id).single(),
      supabase.from("clinics").select("name,phone,email").eq("id", membership.clinic_id).single(),
    ]);
    if (!client) return NextResponse.json({ error: "Danışan bulunamadı." }, { status: 404 });

    if (membership.role === "dietitian") {
      const { data: dietitian } = await supabase.from("dietitian_profiles").select("id").eq("clinic_id", membership.clinic_id).eq("user_id", user.id).single();
      if (!dietitian || client.assigned_dietitian_id !== dietitian.id) {
        return NextResponse.json({ error: "Bu danışan size bağlı değil." }, { status: 403 });
      }
    }

    const dueDate = payment.due_date ? new Date(`${payment.due_date}T12:00:00`) : null;
    const today = new Date(); today.setHours(0, 0, 0, 0);
    const days = dueDate ? Math.ceil((dueDate.getTime() - today.getTime()) / 86400000) : null;
    const timing = days == null ? "ödeme tarihi belirlenmemiştir" : days < 0 ? `ödemeniz ${Math.abs(days)} gün gecikmiştir` : days === 0 ? "ödeme tarihiniz bugündür" : `ödeme tarihinize ${days} gün kalmıştır`;
    const title = `${clinic?.name || "NutriClinic AI"} ödeme hatırlatması`;
    const reminderAmount = Number(payment.remaining_amount ?? Math.max(0, Number(payment.amount) - Number(payment.paid_amount || 0)));
    const text = `Merhaba ${client.full_name}, ${payment.service_type} hizmetine ait kalan ${formatMoney(reminderAmount, payment.currency)} tutarındaki ödemeniz için ${timing}. Detaylar için kliniğinizle iletişime geçebilirsiniz.`;
    const html = `<div style="font-family:Arial,sans-serif;max-width:560px;margin:auto;padding:24px"><h2>${title}</h2><p>Merhaba <strong>${client.full_name}</strong>,</p><p><strong>${payment.service_type}</strong> hizmetine ait <strong>${formatMoney(reminderAmount, payment.currency)}</strong> kalan ödemeniz için ${timing}.</p>${payment.due_date ? `<p>Son ödeme tarihi: <strong>${new Date(payment.due_date).toLocaleDateString("tr-TR")}</strong></p>` : ""}<p>${clinic?.name || "NutriClinic AI"}</p></div>`;

    const recipient = channel === "email" ? client.email : client.phone;
    if (!recipient) return NextResponse.json({ error: channel === "email" ? "Danışanın e-posta adresi yok." : "Danışanın telefon numarası yok." }, { status: 400 });

    let providerMessageId = "";
    if (channel === "email") providerMessageId = await sendEmail(recipient, title, text, html);
    else providerMessageId = await sendSms(recipient, text);

    const { error: logError } = await supabase.rpc("record_payment_reminder_v5", {
      p_payment_id: payment.id,
      p_channel: channel,
      p_recipient: recipient,
      p_status: "sent",
      p_provider_message_id: providerMessageId,
      p_error_message: null,
    });
    if (logError) throw new Error(`Hatırlatma gönderildi ancak kayıt güncellenemedi: ${logError.message}`);

    return NextResponse.json({ ok: true, channel, recipient, provider_message_id: providerMessageId });
  } catch (error) {
    if (paymentId) {
      try {
        await supabase.rpc("record_payment_reminder_v5", {
          p_payment_id: paymentId,
          p_channel: channel,
          p_recipient: null,
          p_status: "failed",
          p_provider_message_id: null,
          p_error_message: error instanceof Error ? error.message : "Gönderim hatası",
        });
      } catch { /* ignore log failure */ }
    }
    return NextResponse.json({ error: error instanceof Error ? error.message : "Hatırlatma gönderilemedi." }, { status: 500 });
  }
}
