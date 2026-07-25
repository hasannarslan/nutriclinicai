"use client";

import { useState, type FormEvent } from "react";
import { ArrowRight, CheckCircle2 } from "lucide-react";

const initialForm = {
  full_name: "",
  email: "",
  phone: "",
  applicant_type: "clinic_owner",
  clinic_name: "",
  city: "",
  team_size: "1",
  active_client_count: "0",
  uses_devices: false,
  message: "",
  website: "",
};

export default function PilotApplicationForm() {
  const [form, setForm] = useState(initialForm);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setLoading(true); setError("");
    try {
      const response = await fetch("/api/pilot-applications", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(form),
      });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "Başvuru gönderilemedi.");
      setSuccess(true);
      setForm(initialForm);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Başvuru gönderilemedi.");
    } finally {
      setLoading(false);
    }
  }

  if (success) {
    return <section className="pilot-application-card pilot-success-card"><CheckCircle2 size={42}/><h2>Başvurunuz alındı</h2><p>Başvurunuzu inceleyip uygun bulunması hâlinde size özel pilot bağlantısını e-posta yoluyla göndereceğiz.</p><button className="secondary-button" onClick={() => setSuccess(false)}>Yeni başvuru gönder</button></section>;
  }

  return (
    <form className="pilot-application-card" onSubmit={submit}>
      <div><span className="section-kicker">BAŞVURU FORMU</span><h2>Pilot erişim talebi</h2><p>Bilgiler yalnızca pilot değerlendirmesi ve iletişim amacıyla kullanılır.</p></div>
      <div className="form-grid">
        <label>Ad soyad<input required value={form.full_name} onChange={(e)=>setForm({...form,full_name:e.target.value})}/></label>
        <label>E-posta<input required type="email" value={form.email} onChange={(e)=>setForm({...form,email:e.target.value})}/></label>
        <label>Telefon<input value={form.phone} onChange={(e)=>setForm({...form,phone:e.target.value})}/></label>
        <label>Başvuru türü<select value={form.applicant_type} onChange={(e)=>setForm({...form,applicant_type:e.target.value})}><option value="clinic_owner">Klinik sahibi</option><option value="dietitian">Bağımsız diyetisyen</option><option value="clinic_team">Klinik ekibi</option><option value="other">Diğer</option></select></label>
        <label>Klinik / marka adı<input value={form.clinic_name} onChange={(e)=>setForm({...form,clinic_name:e.target.value})}/></label>
        <label>Şehir / ülke<input value={form.city} onChange={(e)=>setForm({...form,city:e.target.value})}/></label>
        <label>Ekip büyüklüğü<input type="number" min="1" max="1000" value={form.team_size} onChange={(e)=>setForm({...form,team_size:e.target.value})}/></label>
        <label>Aktif danışan sayısı<input type="number" min="0" max="1000000" value={form.active_client_count} onChange={(e)=>setForm({...form,active_client_count:e.target.value})}/></label>
      </div>
      <label className="pilot-checkbox"><input type="checkbox" checked={form.uses_devices} onChange={(e)=>setForm({...form,uses_devices:e.target.checked})}/><span>BodyShape, G5 veya benzeri cihaz/oda rezervasyonu kullanıyorum.</span></label>
      <label>Notunuz<textarea rows={4} value={form.message} onChange={(e)=>setForm({...form,message:e.target.value})} placeholder="Klinik çalışma şeklinizi ve pilotta özellikle test etmek istediğiniz alanları yazabilirsiniz."/></label>
      <label className="pilot-honeypot" aria-hidden="true">Website<input tabIndex={-1} autoComplete="off" value={form.website} onChange={(e)=>setForm({...form,website:e.target.value})}/></label>
      {error && <p className="form-message error">{error}</p>}
      <button className="primary-button" disabled={loading}>{loading ? "Gönderiliyor…" : "Pilot başvurusu gönder"}<ArrowRight size={17}/></button>
    </form>
  );
}
