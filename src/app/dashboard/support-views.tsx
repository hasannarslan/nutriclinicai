"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { Activity, AlertTriangle, Bell, Building2, CheckCircle2, Clock3, CreditCard, Gift, Globe2, LockKeyhole, Plus, RefreshCw, Save, ShieldCheck, Trash2, UserCog, UsersRound, WalletCards, TicketCheck, PartyPopper, Scale } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { localeLabels, locales } from "@/lib/i18n";
import type { Clinic, Locale, Profile, Role } from "@/lib/types";

type TeamRow={user_id:string;role:Role;is_active:boolean;full_name:string;email:string|null;phone:string|null};
type ClinicInviteRow={id:string;token:string;email:string|null;role:Role;max_uses:number;used_count:number;expires_at:string;is_active:boolean;created_at:string};
type ClientRow={id:string;full_name:string;member_no:string};
type MeasurementRow={id:string;client_id:string;measured_at:string;weight_kg:number|null;body_fat_percent:number|null;muscle_mass_kg:number|null;waist_cm:number|null;note:string|null;client_name?:string};
type RewardRow={id:string;name:string;description:string|null;points_cost:number;stock:number|null;is_active:boolean;created_at:string};
type RedemptionRow={id:string;client_id:string;client_name:string;member_no:string;reward_id:string|null;reward_name:string;points_spent:number;status:string;requested_at:string;fulfilled_at:string|null;note:string|null;redemption_code:string|null;code_expires_at:string|null;used_at:string|null;used_by:string|null};
type LoyaltyClientRow={client_id:string;client_name:string;member_no:string;remaining_points:number};
type ClientPaymentRow={id:string;service_type:string;description:string|null;amount:number;paid_amount:number;remaining_amount:number;currency:string;status:"pending"|"partial"|"paid"|"refunded"|"cancelled";method:"cash"|"card"|"iban"|"other"|null;paid_at:string|null;due_date:string|null;reminder_sent_at:string|null;created_at:string};

function Header({title,description,action}:{title:string;description:string;action?:React.ReactNode}){return <div className="page-header v3-page-header"><div><span className="section-kicker">NUTRICLINIC AI</span><h1>{title}</h1><p>{description}</p></div>{action}</div>}
function Loading(){return <div className="empty-state"><RefreshCw className="spin" size={24}/><p>Yükleniyor…</p></div>}
function Empty({text="Henüz kayıt yok."}:{text?:string}){return <div className="empty-state"><Activity size={27}/><p>{text}</p></div>}
function initials(name:string){return name.split(" ").filter(Boolean).slice(0,2).map(x=>x[0]).join("").toUpperCase()}
function roleText(role:Role){return({owner:"Klinik Sahibi",dietitian:"Diyetisyen",secretary:"Sekreter",client:"Danışan"} as Record<Role,string>)[role]}
function money(value:number){return new Intl.NumberFormat("tr-TR",{style:"currency",currency:"TRY"}).format(value)}
function paymentStatusText(status:ClientPaymentRow["status"]){return({pending:"Bekliyor",partial:"Kısmi",paid:"Ödendi",refunded:"İade",cancelled:"İptal"} as Record<string,string>)[status]||status}
function paymentMethodText(method:ClientPaymentRow["method"]){return({cash:"Nakit",card:"Kart",iban:"IBAN",other:"Diğer"} as Record<string,string>)[method||""]||"—"}

export function TeamV3({clinicId,currentUserId}:{clinicId:string;currentUserId:string}){
  const supabase=useMemo(()=>createClient(),[]);
  const[rows,setRows]=useState<TeamRow[]>([]);
  const[invites,setInvites]=useState<ClinicInviteRow[]>([]);
  const[loading,setLoading]=useState(true);
  const[message,setMessage]=useState("");
  const[inviteForm,setInviteForm]=useState({role:"client" as Role,email:"",expires_days:"14",max_uses:"1"});
  const[busy,setBusy]=useState(false);
  const load=useCallback(async()=>{
    setLoading(true);
    const[{data:m,error},{data:i,error:inviteError}]=await Promise.all([
      supabase.from("clinic_memberships").select("user_id,role,is_active").eq("clinic_id",clinicId).order("created_at",{ascending:false}),
      supabase.rpc("list_clinic_invites_v7")
    ]);
    if(error){setMessage(error.message);setLoading(false);return}
    if(inviteError)setMessage(inviteError.message);
    const ids=(m||[]).map((x:any)=>x.user_id);
    const{data:p}=ids.length?await supabase.from("profiles").select("id,full_name,email,phone").in("id",ids):{data:[]};
    const map=new Map((p||[]).map((x:any)=>[x.id,x]));
    setRows((m||[]).map((x:any)=>({...x,...map.get(x.user_id)})));
    setInvites((i||[]) as ClinicInviteRow[]);
    setLoading(false)
  },[clinicId,supabase]);
  useEffect(()=>{void load()},[load]);
  async function updateRole(userId:string,next:Role){const{error}=await supabase.rpc("set_member_role",{p_user_id:userId,p_role:next});if(error)setMessage(error.message);else{setMessage("Rol güncellendi.");await load()}}
  async function createInvite(){
    setBusy(true);setMessage("");
    const{data,error}=await supabase.rpc("create_clinic_invite_v7",{
      p_role:inviteForm.role,
      p_email:inviteForm.email.trim()||null,
      p_expires_days:Number(inviteForm.expires_days)||14,
      p_max_uses:Number(inviteForm.max_uses)||1
    });
    setBusy(false);
    if(error)return setMessage(error.message);
    const token=String(data||"");
    const query=inviteForm.role==="client"?"invite":"invite";
    const link=`${window.location.origin}/login?${query}=${token}`;
    await navigator.clipboard?.writeText(link);
    setInviteForm({role:"client",email:"",expires_days:"14",max_uses:"1"});
    setMessage("Davet oluşturuldu ve bağlantı panoya kopyalandı.");
    await load();
  }
  async function revokeInvite(id:string){
    const{error}=await supabase.rpc("revoke_clinic_invite_v7",{p_invite_id:id});
    if(error)setMessage(error.message);else{setMessage("Davet pasif yapıldı.");await load()}
  }
  function copyInvite(token:string){void navigator.clipboard?.writeText(`${window.location.origin}/login?invite=${token}`);setMessage("Davet bağlantısı panoya kopyalandı.")}
  return <>
    <Header title="Ekip ve Davetler" description="Kullanıcıları güvenli davet bağlantısıyla kliniğe alın; rol ve plan limitlerini tek ekrandan yönetin." action={<button className="secondary-button compact" onClick={load}><RefreshCw size={14}/>Yenile</button>}/>
    {message&&<div className="notice-bar">{message}</div>}
    <section className="surface-card team-invite-v7">
      <div className="surface-head"><div><span className="section-kicker">GÜVENLİ DAVET</span><h3>Yeni ekip veya danışan daveti</h3><p>Kullanıcılar artık herkese açık şekilde kliniğe eklenmez. Her hesap bu kodla doğru tenant ve role bağlanır.</p></div><UserCog size={28}/></div>
      <div className="form-grid">
        <label>Rol<select value={inviteForm.role} onChange={e=>setInviteForm({...inviteForm,role:e.target.value as Role})}><option value="client">Danışan</option><option value="dietitian">Diyetisyen</option><option value="secretary">Sekreter</option></select></label>
        <label>E-posta kısıtı (isteğe bağlı)<input type="email" value={inviteForm.email} onChange={e=>setInviteForm({...inviteForm,email:e.target.value})} placeholder="yalnızca bu e-posta kullanabilsin"/></label>
        <label>Geçerlilik günü<input type="number" min="1" max="90" value={inviteForm.expires_days} onChange={e=>setInviteForm({...inviteForm,expires_days:e.target.value})}/></label>
        <label>Maksimum kullanım<input type="number" min="1" max="1000" value={inviteForm.max_uses} onChange={e=>setInviteForm({...inviteForm,max_uses:e.target.value})}/></label>
      </div>
      <button className="primary-button compact" disabled={busy} onClick={createInvite}><Plus size={15}/>{busy?"Oluşturuluyor…":"Davet oluştur ve bağlantıyı kopyala"}</button>
      {invites.length>0&&<div className="clinic-invite-list-v7">{invites.map(invite=><article key={invite.id} className={!invite.is_active?"inactive":""}><div><b>{roleText(invite.role)}</b><code>{invite.token}</code><small>{invite.email||"E-posta kısıtı yok"} · {invite.used_count}/{invite.max_uses} kullanım · {new Date(invite.expires_at).toLocaleDateString("tr-TR")}</small></div><div><button onClick={()=>copyInvite(invite.token)}>Bağlantıyı kopyala</button>{invite.is_active&&<button className="danger-action" onClick={()=>revokeInvite(invite.id)}>Pasif yap</button>}</div></article>)}</div>}
    </section>
    <section className="surface-card">{loading?<Loading/>:<div className="table-wrap modern-table-wrap"><table className="modern-table"><thead><tr><th>Kullanıcı</th><th>İletişim</th><th>Mevcut rol</th><th>Rol değiştir</th></tr></thead><tbody>{rows.map(row=><tr key={row.user_id}><td><div className="person-cell"><span className="avatar">{initials(row.full_name||"K")}</span><b>{row.full_name||"İsimsiz kullanıcı"}</b></div></td><td>{row.email||row.phone||"—"}</td><td><span className={`role-badge ${row.role}`}>{roleText(row.role)}</span></td><td><select value={row.role} disabled={row.user_id===currentUserId&&row.role==="owner"} onChange={e=>updateRole(row.user_id,e.target.value as Role)}><option value="client">Danışan</option><option value="secretary">Sekreter</option><option value="dietitian">Diyetisyen</option><option value="owner">Klinik Sahibi</option></select></td></tr>)}</tbody></table></div>}</section>
  </>
}

export function MeasurementsV3({role,clinicId}:{role:Role;clinicId:string}){
  const supabase=useMemo(()=>createClient(),[]);
  const staff=role==="owner"||role==="dietitian";
  const[rows,setRows]=useState<MeasurementRow[]>([]);
  const[clients,setClients]=useState<ClientRow[]>([]);
  const[selectedClient,setSelectedClient]=useState("");
  const[loading,setLoading]=useState(true);
  const[message,setMessage]=useState("");
  const[form,setForm]=useState({client_id:"",weight:"",fat:"",muscle:"",waist:"",note:""});

  const load=useCallback(async()=>{
    setLoading(true);
    const[{data:m,error:measurementError},{data:c,error:clientError}]=await Promise.all([
      supabase.from("measurements").select("id,client_id,measured_at,weight_kg,body_fat_percent,muscle_mass_kg,waist_cm,note").order("measured_at",{ascending:false}),
      staff?supabase.rpc("get_client_directory_v4"):Promise.resolve({data:[],error:null}),
    ]);
    if(measurementError)setMessage(measurementError.message);
    if(clientError)setMessage(clientError.message);
    const cs=((c||[]) as any[]).map(x=>({id:x.id,full_name:x.full_name,member_no:x.member_no})) as ClientRow[];
    setClients(cs);
    const map=new Map(cs.map(x=>[x.id,x.full_name]));
    const next=((m||[]) as MeasurementRow[]).map(x=>({...x,client_name:staff?(map.get(x.client_id)||"Danışan"):"Ölçümünüz"}));
    setRows(next);
    const initial=selectedClient&&cs.some(x=>x.id===selectedClient)?selectedClient:(cs[0]?.id||next[0]?.client_id||"");
    setSelectedClient(initial);
    setForm(current=>({...current,client_id:initial}));
    setLoading(false);
  },[selectedClient,staff,supabase]);
  useEffect(()=>{void load()},[load]);

  async function add(){
    const clientId=form.client_id||selectedClient;
    if(!clientId)return setMessage("Danışan seçin.");
    if(!form.weight&&!form.fat&&!form.muscle&&!form.waist)return setMessage("En az bir ölçüm değeri girin.");
    const{data:user}=await supabase.auth.getUser();
    const{data:diet}=await supabase.from("dietitian_profiles").select("id").eq("user_id",user.user?.id||"").maybeSingle();
    const{error}=await supabase.from("measurements").insert({clinic_id:clinicId,client_id:clientId,recorded_by:diet?.id||null,weight_kg:form.weight?Number(form.weight):null,body_fat_percent:form.fat?Number(form.fat):null,muscle_mass_kg:form.muscle?Number(form.muscle):null,waist_cm:form.waist?Number(form.waist):null,note:form.note||null});
    if(error)setMessage(error.message);else{setMessage("Ölçüm kaydedildi.");setForm(current=>({...current,weight:"",fat:"",muscle:"",waist:"",note:""}));await load()}
  }

  const visible=staff&&selectedClient?rows.filter(x=>x.client_id===selectedClient):rows;
  const latest=visible[0];
  const previous=visible[1];
  const weightDelta=latest?.weight_kg!=null&&previous?.weight_kg!=null?Number((latest.weight_kg-previous.weight_kg).toFixed(1)):null;
  const chartRows=[...visible].filter(x=>x.weight_kg!=null).slice(0,12).reverse();
  const weights=chartRows.map(x=>Number(x.weight_kg));
  const min=weights.length?Math.min(...weights)-1:0;
  const max=weights.length?Math.max(...weights)+1:1;
  const points=chartRows.map((row,index)=>{
    const x=chartRows.length===1?50:(index/(chartRows.length-1))*100;
    const y=88-((Number(row.weight_kg)-min)/Math.max(max-min,1))*68;
    return `${x},${y}`;
  }).join(" ");

  return <>
    <Header title="Ölçümler" description="Kilo, yağ oranı, kas kütlesi ve bel çevresini gelişmiş trend görünümüyle takip edin." action={staff?<select className="measurement-client-select" value={selectedClient} onChange={e=>{setSelectedClient(e.target.value);setForm(current=>({...current,client_id:e.target.value}))}}>{clients.map(c=><option key={c.id} value={c.id}>{c.full_name} • {c.member_no}</option>)}</select>:undefined}/>
    {message&&<div className="notice-bar">{message}</div>}
    {staff&&<section className="surface-card measurement-entry-v5"><div className="settings-section-title"><Plus size={20}/><div><h3>Yeni klinik ölçümü</h3><p>Yeni değer eski kaydın üzerine yazılmaz; tarihsel gelişime eklenir.</p></div></div><div className="form-grid"><label>Kilo (kg)<input type="number" step="0.1" value={form.weight} onChange={e=>setForm({...form,weight:e.target.value})}/></label><label>Yağ oranı (%)<input type="number" step="0.1" value={form.fat} onChange={e=>setForm({...form,fat:e.target.value})}/></label><label>Kas kütlesi (kg)<input type="number" step="0.1" value={form.muscle} onChange={e=>setForm({...form,muscle:e.target.value})}/></label><label>Bel çevresi (cm)<input type="number" step="0.1" value={form.waist} onChange={e=>setForm({...form,waist:e.target.value})}/></label><label className="wide">Klinik notu<input value={form.note} onChange={e=>setForm({...form,note:e.target.value})}/></label></div><button className="primary-button compact" onClick={add}><Plus size={14}/>Ölçüm ekle</button></section>}
    {loading?<Loading/>:!latest?<Empty text="Henüz ölçüm kaydı bulunmuyor."/>:<>
      <section className="measurement-overview-v5">
        <article className="measurement-primary-card"><div><small>Güncel kilo</small><strong>{latest.weight_kg??"—"}<span> kg</span></strong>{weightDelta!=null&&<p className={weightDelta<=0?"success-text":"danger-text"}>{weightDelta>0?"+":""}{weightDelta} kg önceki ölçüme göre</p>}</div><Scale size={30}/></article>
        <article><small>Yağ oranı</small><b>{latest.body_fat_percent!=null?`%${latest.body_fat_percent}`:"—"}</b><span>{previous?.body_fat_percent!=null?`Önceki: %${previous.body_fat_percent}`:"İlk kayıt"}</span></article>
        <article><small>Kas kütlesi</small><b>{latest.muscle_mass_kg!=null?`${latest.muscle_mass_kg} kg`:"—"}</b><span>{previous?.muscle_mass_kg!=null?`Önceki: ${previous.muscle_mass_kg} kg`:"İlk kayıt"}</span></article>
        <article><small>Bel çevresi</small><b>{latest.waist_cm!=null?`${latest.waist_cm} cm`:"—"}</b><span>{previous?.waist_cm!=null?`Önceki: ${previous.waist_cm} cm`:"İlk kayıt"}</span></article>
      </section>
      <section className="surface-card measurement-trend-v5"><div className="surface-head"><div><span className="section-kicker">GELİŞİM</span><h3>Kilo trendi</h3><p>Son {chartRows.length} ölçümün tarihsel değişimi.</p></div><span className="count-pill">{visible.length} kayıt</span></div>{chartRows.length>1?<div className="measurement-chart-shell"><svg viewBox="0 0 100 100" preserveAspectRatio="none" role="img" aria-label="Kilo değişim grafiği"><line x1="0" y1="88" x2="100" y2="88"/><polyline points={points}/>{chartRows.map((row,index)=>{const [x,y]=points.split(" ")[index].split(",");return <circle key={row.id} cx={x} cy={y} r="1.8"/>})}</svg><div className="measurement-chart-labels"><span>{new Date(chartRows[0].measured_at).toLocaleDateString("tr-TR")}</span><b>{latest.weight_kg} kg</b><span>{new Date(latest.measured_at).toLocaleDateString("tr-TR")}</span></div></div>:<p className="muted-line">Trend için en az iki kilo ölçümü gerekir.</p>}</section>
      <section className="surface-card"><div className="surface-head"><div><span className="section-kicker">GEÇMİŞ</span><h3>Ölçüm kayıtları</h3></div></div><div className="table-wrap modern-table-wrap"><table className="modern-table"><thead><tr><th>Tarih</th><th>Kilo</th><th>Yağ</th><th>Kas</th><th>Bel</th><th>Not</th></tr></thead><tbody>{visible.map(row=><tr key={row.id}><td><b>{new Date(row.measured_at).toLocaleDateString("tr-TR")}</b><small>{new Date(row.measured_at).toLocaleTimeString("tr-TR",{hour:"2-digit",minute:"2-digit"})}</small></td><td>{row.weight_kg??"—"} kg</td><td>{row.body_fat_percent??"—"}%</td><td>{row.muscle_mass_kg??"—"} kg</td><td>{row.waist_cm??"—"} cm</td><td>{row.note||"—"}</td></tr>)}</tbody></table></div></section>
    </>}
  </>
}

export function LoyaltyV3({role,clinicId}:{role:Role;clinicId:string}){
  const supabase=useMemo(()=>createClient(),[]);
  const owner=role==="owner";
  const clinical=role==="owner"||role==="dietitian";
  const[balance,setBalance]=useState(0);
  const[rewards,setRewards]=useState<RewardRow[]>([]);
  const[redemptions,setRedemptions]=useState<RedemptionRow[]>([]);
  const[clients,setClients]=useState<LoyaltyClientRow[]>([]);
  const[message,setMessage]=useState("");
  const[showForm,setShowForm]=useState(false);
  const[stockInputs,setStockInputs]=useState<Record<string,string>>({});
  const[form,setForm]=useState({name:"",description:"",points_cost:"",stock_mode:"limited",stock:"1"});
  const[selectedClientId,setSelectedClientId]=useState("");
  const[balanceCorrection,setBalanceCorrection]=useState({value:"",reason:""});
  const[busy,setBusy]=useState(false);
  const[celebration,setCelebration]=useState<{title:string;detail:string;code?:string}|null>(null);

  const load=useCallback(async()=>{
    const rewardQuery=supabase
      .from("rewards")
      .select("id,name,description,points_cost,stock,is_active,created_at")
      .eq("clinic_id",clinicId)
      .order("points_cost");

    const [rewardResult,walletResult,redemptionResult,clientResult]=await Promise.all([
      owner?rewardQuery:rewardQuery.eq("is_active",true),
      role==="client"
        ?supabase.from("loyalty_wallets").select("balance").eq("clinic_id",clinicId).maybeSingle()
        :Promise.resolve({data:null,error:null}),
      role==="client"||clinical
        ?supabase.rpc("get_reward_redemptions",{p_client_id:null})
        :Promise.resolve({data:[],error:null}),
      clinical
        ?supabase.rpc("get_reward_issuance_clients_v54")
        :Promise.resolve({data:[],error:null})
    ]);

    setRewards((rewardResult.data||[]) as RewardRow[]);
    setBalance((walletResult.data as {balance?:number}|null)?.balance||0);
    setRedemptions((redemptionResult.data||[]) as RedemptionRow[]);
    setClients((clientResult.data||[]) as LoyaltyClientRow[]);

    const error=rewardResult.error||walletResult.error||redemptionResult.error||clientResult.error;
    if(error)setMessage(error.message);
  },[clinicId,clinical,owner,role,supabase]);

  useEffect(()=>{void load()},[load]);

  const selectedClient=clients.find(row=>row.client_id===selectedClientId);
  const suspiciousClientBalance=role==="client"&&balance>10000000;
  const suspiciousSelectedBalance=Boolean(selectedClient&&selectedClient.remaining_points>10000000);

  async function addReward(){
    if(!form.name.trim()||Number(form.points_cost)<=0){
      setMessage("Ödül adı ve puan bedeli zorunludur.");
      return;
    }
    const{error}=await supabase.from("rewards").insert({
      clinic_id:clinicId,
      name:form.name.trim(),
      description:form.description||null,
      points_cost:Number(form.points_cost),
      stock:form.stock_mode==="unlimited"?null:Math.max(0,Number(form.stock)||0),
      is_active:true
    });
    if(error)setMessage(error.message);
    else{
      setShowForm(false);
      setForm({name:"",description:"",points_cost:"",stock_mode:"limited",stock:"1"});
      setMessage("Yeni sadakat ödülü oluşturuldu.");
      await load();
    }
  }

  async function adjust(row:RewardRow,dir:1|-1){
    const qty=Math.max(1,Number(stockInputs[row.id]||1));
    const{error}=await supabase.rpc("adjust_reward_stock",{
      p_reward_id:row.id,
      p_delta:qty*dir,
      p_reason:dir>0?"Panelden stok eklendi":"Panelden stok çıkarıldı"
    });
    if(error)setMessage(error.message);
    else await load();
  }

  async function redeemReward(row:RewardRow){
    if(role!=="client")return;
    if(!row.is_active){setMessage("Bu ödül şu anda kullanıma açık değil.");return;}
    if(row.stock!==null&&row.stock<=0){setMessage("Bu ödülün stoğu tükenmiş.");return;}
    if(balance<row.points_cost){setMessage(`Bu ödül için ${(row.points_cost-balance).toLocaleString("tr-TR")} puan daha gerekiyor.`);return;}
    if(!window.confirm(`${row.name} ödülü için ${row.points_cost.toLocaleString("tr-TR")} puan kullanılsın mı?`))return;
    setBusy(true);
    const{data,error}=await supabase.rpc("client_redeem_reward_v56",{p_reward_id:row.id});
    setBusy(false);
    if(error){setMessage(error.message);return;}
    const result=data as {reward_name:string;redemption_code:string;balance_after:number};
    setCelebration({
      title:`${result.reward_name} ödülünü kazandınız`,
      detail:`Puanınız başarıyla kullanıldı. Kalan bakiyeniz ${result.balance_after.toLocaleString("tr-TR")} puan. Ödülü kliniğinizde kullanabilirsiniz.`,
      code:result.redemption_code
    });
    await load();
  }

  async function correctBalance(){
    if(!selectedClientId){setMessage("Önce danışan seçin.");return;}
    const next=Number(balanceCorrection.value);
    if(!Number.isInteger(next)||next<0){setMessage("Yeni puan bakiyesi 0 veya daha büyük tam sayı olmalıdır.");return;}
    if(!balanceCorrection.reason.trim()){setMessage("Puan düzeltme nedeni zorunludur.");return;}
    if(!window.confirm(`${selectedClient?.client_name||"Danışan"} sadakat bakiyesi ${next.toLocaleString("tr-TR")} puan olarak düzeltilecek. Onaylıyor musunuz?`))return;
    setBusy(true);
    const{data,error}=await supabase.rpc("set_client_loyalty_balance_v55",{
      p_client_id:selectedClientId,
      p_new_balance:next,
      p_reason:balanceCorrection.reason.trim()
    });
    setBusy(false);
    if(error){setMessage(error.message);return;}
    const result=data as {old_balance:number;new_balance:number;delta:number};
    setMessage(`Puan bakiyesi ${result.old_balance.toLocaleString("tr-TR")} puandan ${result.new_balance.toLocaleString("tr-TR")} puana düzeltildi.`);
    setBalanceCorrection({value:"",reason:""});
    await load();
  }

  async function fulfill(redemption:RedemptionRow){
    if(!window.confirm(`${redemption.client_name} için ${redemption.reward_name} ödülü kullanıldı olarak işaretlensin mi?`))return;
    setBusy(true);
    const{data,error}=await supabase.rpc("fulfill_reward_redemption_v54",{
      p_redemption_id:redemption.id
    });
    setBusy(false);
    if(error){
      setMessage(error.message);
      return;
    }
    const result=data as {reward_name:string;client_name:string};
    setCelebration({
      title:`${result.reward_name} kullanıldı`,
      detail:`${result.client_name} adlı danışanın sadakat ödülü başarıyla kullanıldı olarak kaydedildi.`
    });
    await load();
  }

  return <>
    <Header
      title="Sadakat"
      description={role==="client"
        ?"Puanınız yettiğinde ödülü doğrudan seçin, puanınızı kullanın ve kuponunuzu oluşturun."
        :owner
          ?"Ödül kataloğunu, stokları ve danışanların kullandığı ödülleri yönetin."
          :"Size bağlı danışanların puan bakiyelerini ve kullandığı ödülleri takip edin."}
      action={owner?<button className="primary-button compact" onClick={()=>setShowForm(value=>!value)}><Plus size={14}/>Yeni ödül</button>:undefined}
    />

    {message&&<div className="notice-bar">{message}</div>}

    {celebration&&<div className="reward-celebration-overlay">
      <section className="reward-celebration">
        <PartyPopper size={42}/>
        <span>SADAKAT ÖDÜLÜ</span>
        <h2>{celebration.title}</h2>
        <p>{celebration.detail}</p>
        {celebration.code&&<><small>Kupon kodu</small><strong>{celebration.code}</strong></>}
        <button className="primary-button" onClick={()=>setCelebration(null)}>Tamam</button>
      </section>
    </div>}

    {clinical&&<section className="surface-card loyalty-issue-panel">
      <div className="surface-head">
        <div>
          <span className="section-kicker">DANIŞAN PUANLARI</span>
          <h3>Puan bakiyesi kontrolü</h3>
          <p>Danışan ödülünü kendi hesabından puanıyla alır. Buradan yalnızca bakiyeyi kontrol edebilir ve hatalı puanları loglu şekilde düzeltebilirsiniz.</p>
        </div>
        <Scale size={28}/>
      </div>
      <div className="form-grid loyalty-issue-grid">
        <label>Danışan
          <select value={selectedClientId} onChange={event=>setSelectedClientId(event.target.value)}>
            <option value="">Danışan seçin</option>
            {clients.map(client=><option key={client.client_id} value={client.client_id}>{client.client_name} · {client.member_no} · {client.remaining_points.toLocaleString("tr-TR")} puan</option>)}
          </select>
        </label>
        <label>Mevcut kullanılabilir puan
          <input value={selectedClient?selectedClient.remaining_points.toLocaleString("tr-TR"):"—"} readOnly/>
        </label>
      </div>
      {selectedClient&&<details className={`loyalty-balance-correction ${suspiciousSelectedBalance?"warning":""}`} open={suspiciousSelectedBalance}>
        <summary><Scale size={15}/>Puan bakiyesini düzelt{suspiciousSelectedBalance&&<span>Olağan dışı bakiye</span>}</summary>
        <p>Yanlış puan eklenmişse bakiyeyi silmeden, log kaydı oluşturarak doğru değere çekin.</p>
        <div className="loyalty-correction-grid">
          <label>Doğru bakiye<input type="number" min="0" step="1" value={balanceCorrection.value} onChange={event=>setBalanceCorrection({...balanceCorrection,value:event.target.value})} placeholder="Örn. 5000"/></label>
          <label>Düzeltme nedeni<input value={balanceCorrection.reason} onChange={event=>setBalanceCorrection({...balanceCorrection,reason:event.target.value})} placeholder="Örn. yanlışlıkla fazla puan girildi"/></label>
          <button className="secondary-button compact" disabled={busy||!balanceCorrection.value||!balanceCorrection.reason.trim()} onClick={correctBalance}>Bakiyeyi düzelt</button>
        </div>
      </details>}
    </section>}

    {showForm&&owner&&<section className="surface-card">
      <div className="form-grid">
        <label>Ödül adı<input value={form.name} onChange={event=>setForm({...form,name:event.target.value})}/></label>
        <label>Puan bedeli<input type="number" value={form.points_cost} onChange={event=>setForm({...form,points_cost:event.target.value})}/></label>
        <label>Stok türü<select value={form.stock_mode} onChange={event=>setForm({...form,stock_mode:event.target.value})}><option value="limited">Sınırlı</option><option value="unlimited">Sınırsız</option></select></label>
        {form.stock_mode==="limited"&&<label>Stok<input type="number" min="0" value={form.stock} onChange={event=>setForm({...form,stock:event.target.value})}/></label>}
        <label className="wide">Açıklama<textarea rows={3} value={form.description} onChange={event=>setForm({...form,description:event.target.value})}/></label>
      </div>
      <button className="primary-button compact" onClick={addReward}><Save size={14}/>Kaydet</button>
    </section>}

    <div className="loyalty-banner v3-loyalty-banner">
      <Gift size={34}/>
      <div>
        <span>{role==="client"?"Kullanılabilir puan":"Aktif ödül"}</span>
        <strong>{role==="client"?balance.toLocaleString("tr-TR"):rewards.filter(reward=>reward.is_active).length}</strong>
      </div>
    </div>

    {suspiciousClientBalance&&<div className="loyalty-balance-alert"><AlertTriangle size={19}/><div><b>Puan bakiyeniz olağan dışı görünüyor</b><p>Bu değer görüntüleme hatası değil, hesabınıza kaydedilmiş mevcut bakiyedir. Klinik Sahibi veya Diyetisyen loglu düzeltme yapmalıdır.</p></div></div>}

    {role==="client"&&rewards.length>0&&<div className="loyalty-client-note">
      <ShieldCheck size={18}/>
      <p>Puanınız ve ödül stoğu yeterliyse <b>Puanımla kullan</b> düğmesine basabilirsiniz. Puanınız anında düşer ve tek kullanımlık ödül kodunuz oluşturulur.</p>
    </div>}

    {rewards.length===0
      ?<section className="surface-card loyalty-empty-catalog"><Gift size={32}/><h3>Sadakat ödülleri henüz oluşturulmadı</h3><p>{role==="client"?"Kliniğiniz ödülleri tanımladıktan sonra bu bölüm kullanıma açılacaktır.":owner?"Yeni ödül düğmesiyle ilk sadakat ödülünü oluşturduğunuzda katalog kullanıma açılacaktır.":"Klinik Sahibi ödül oluşturduktan sonra danışanlar puanlarını kullanabilecektir."}</p></section>
      :<div className="reward-grid">
      {rewards.map(row=>{
        const eligible=role==="client"&&row.is_active&&balance>=row.points_cost&&(row.stock===null||row.stock>0);
        const missing=Math.max(0,row.points_cost-balance);
        return <article key={row.id} className={role==="client"&&!eligible?"reward-locked":"reward-available"}>
          <Gift size={22}/>
          <h3>{row.name}</h3>
          <p>{row.description||"Klinik ödülü"}</p>
          <b>{row.points_cost.toLocaleString("tr-TR")} puan</b>
          <small>Stok: {row.stock===null?"Sınırsız":row.stock}</small>
          {role==="client"&&<>
            <span className={`reward-eligibility ${eligible?"eligible":"locked"}`}>
              {eligible?"Bu ödülü puanınızla hemen alabilirsiniz":row.stock===0?"Stokta yok":`${missing.toLocaleString("tr-TR")} puan eksik`}
            </span>
            <button className="reward-redeem-button" disabled={busy||!eligible} onClick={()=>redeemReward(row)}><Gift size={14}/>{busy?"İşleniyor…":eligible?"Puanımla kullan":row.stock===0?"Stokta yok":"Puan yetersiz"}</button>
          </>}
          {owner&&<div className="reward-owner-controls">
            <div className="stock-adjust">
              <input type="number" min="1" value={stockInputs[row.id]||"1"} disabled={row.stock===null} onChange={event=>setStockInputs({...stockInputs,[row.id]:event.target.value})}/>
              <button disabled={row.stock===null} onClick={()=>adjust(row,1)}>Stok ekle</button>
              <button disabled={row.stock===null||row.stock===0} onClick={()=>adjust(row,-1)}>Stok çıkar</button>
            </div>
            <div className="reward-card-actions">
              <button onClick={()=>supabase.from("rewards").update({is_active:!row.is_active}).eq("id",row.id).then(load)}>{row.is_active?"Pasif yap":"Aktif yap"}</button>
              <button className="danger-action" onClick={async()=>{if(window.confirm("Ödül silinsin mi?")){await supabase.from("rewards").delete().eq("id",row.id);await load()}}}><Trash2 size={13}/>Sil</button>
            </div>
          </div>}
        </article>
      })}
    </div>}

    {(role==="client"||clinical)&&<section className="surface-card redemption-history-section">
      <div className="redemption-history-head">
        <TicketCheck size={21}/>
        <div>
          <h3>{role==="client"?"Puanımla aldığım ödüller":"Danışanların aldığı ödüller"}</h3>
          <p>{role==="client"?"Puanınızla oluşturduğunuz kullanılabilir ve geçmiş ödüller.":"Danışanların puanlarıyla aldığı kuponları ve kullanım durumlarını buradan yönetin."}</p>
        </div>
      </div>
      {redemptions.length===0?<Empty text="Henüz tanımlanmış ödül yok."/>:<div className="redemption-list">
        {redemptions.map(row=><article key={row.id}>
          <div className="redemption-icon"><Gift size={17}/></div>
          <div className="grow">
            <b>{row.reward_name}</b>
            {clinical&&<p>{row.client_name} · {row.member_no}</p>}
            <small>{new Date(row.requested_at).toLocaleString("tr-TR")} · {row.points_spent.toLocaleString("tr-TR")} puan</small>
            {row.note&&<small>Not: {row.note}</small>}
          </div>
          {row.redemption_code&&<code className="reward-code-inline">{row.redemption_code}</code>}
          <span className={`redemption-status ${row.status}`}>{row.status==="fulfilled"?"Kullanıldı":row.status==="requested"?"Kullanılabilir":row.status==="cancelled"?"İptal":row.status}</span>
          {clinical&&row.status==="requested"&&<button className="primary-button compact" disabled={busy} onClick={()=>fulfill(row)}><CheckCircle2 size={14}/>Kullanıldı</button>}
        </article>)}
      </div>}
    </section>}
  </>
}

export function ProfileSettingsV3({profile,role,clinic,onUpdated,onClinicUpdated}:{profile:Profile;role:Role;clinic:Clinic;onUpdated:(p:Profile)=>void;onClinicUpdated:(c:Clinic)=>void}){
  const [todayMs]=useState(()=>{const d=new Date();d.setHours(0,0,0,0);return d.getTime()});
  const supabase=useMemo(()=>createClient(),[]);const[message,setMessage]=useState("");const[profileForm,setProfileForm]=useState({full_name:profile.full_name,email:profile.email||"",phone:profile.phone||"",preferred_locale:profile.preferred_locale,email_notifications:true,appointment_reminders:true,meal_reminders:true,weekly_summary:true,sms_notifications:false,appointment_changes:true,loyalty_notifications:true,progress_insights:true,default_appointment_mode:"in_clinic"});const[clientForm,setClientForm]=useState({birth_date:"",gender:"",height_cm:"",target_text:"",allergies:"",disliked_foods:"",medical_notes:"",medications:"",community_opt_in:true});const[clientPayments,setClientPayments]=useState<ClientPaymentRow[]>([]);const[clinicForm,setClinicForm]=useState({name:clinic.name,phone:clinic.phone||"",email:clinic.email||"",address:clinic.address||"",website:clinic.website||"",timezone:clinic.timezone||"Europe/Istanbul",default_locale:clinic.default_locale,booking_horizon_days:String(clinic.booking_horizon_days??60),minimum_booking_notice_hours:String(clinic.minimum_booking_notice_hours??2),cancellation_notice_hours:String(clinic.cancellation_notice_hours??12),allow_client_cancellation:clinic.allow_client_cancellation??true,allow_online_booking:clinic.allow_online_booking??true});const[dietForm,setDietForm]=useState({title:"Danışman Diyetisyen",license_no:"",bio:"",appointment_duration_minutes:"45",buffer_minutes:"10",is_bookable:true});const[password,setPassword]=useState({password:"",confirm:""});
  useEffect(()=>{(async()=>{const{data:p}=await supabase.from("profiles").select("notification_preferences").eq("id",profile.id).maybeSingle();const prefs=(p?.notification_preferences||{}) as Record<string,boolean|string>;setProfileForm(f=>({...f,email_notifications:Boolean(prefs.email_notifications??true),appointment_reminders:Boolean(prefs.appointment_reminders??true),meal_reminders:Boolean(prefs.meal_reminders??true),weekly_summary:Boolean(prefs.weekly_summary??true),sms_notifications:Boolean(prefs.sms_notifications??false),appointment_changes:Boolean(prefs.appointment_changes??true),loyalty_notifications:Boolean(prefs.loyalty_notifications??true),progress_insights:Boolean(prefs.progress_insights??true),default_appointment_mode:String(prefs.default_appointment_mode||"in_clinic")}));if(role==="client"){const{data:c}=await supabase.from("client_profiles").select("id,birth_date,gender,height_cm,target_text,allergies,disliked_foods,medical_notes,medications,community_opt_in").eq("clinic_id",clinic.id).eq("user_id",profile.id).eq("is_active",true).maybeSingle();if(c){setClientForm({birth_date:c.birth_date||"",gender:c.gender||"",height_cm:c.height_cm==null?"":String(c.height_cm),target_text:c.target_text||"",allergies:(c.allergies||[]).join(", "),disliked_foods:(c.disliked_foods||[]).join(", "),medical_notes:c.medical_notes||"",medications:c.medications||"",community_opt_in:c.community_opt_in??true});const{data:paymentRows,error:paymentError}=await supabase.from("payments").select("id,service_type,description,amount,paid_amount,remaining_amount,currency,status,method,paid_at,due_date,reminder_sent_at,created_at").eq("client_id",c.id).order("created_at",{ascending:false});if(paymentError)setMessage(paymentError.message);else setClientPayments((paymentRows||[]) as ClientPaymentRow[])}}if(role==="owner"||role==="dietitian"){const{data:d}=await supabase.from("dietitian_profiles").select("title,license_no,bio,appointment_duration_minutes,buffer_minutes,is_bookable").eq("clinic_id",clinic.id).eq("user_id",profile.id).maybeSingle();if(d)setDietForm({title:d.title||"Diyetisyen",license_no:d.license_no||"",bio:d.bio||"",appointment_duration_minutes:String(d.appointment_duration_minutes),buffer_minutes:String(d.buffer_minutes),is_bookable:d.is_bookable})}})()},[clinic.id,profile.id,role,supabase]);
  async function saveProfile(){const prefs={email_notifications:profileForm.email_notifications,appointment_reminders:profileForm.appointment_reminders,meal_reminders:profileForm.meal_reminders,weekly_summary:profileForm.weekly_summary,sms_notifications:profileForm.sms_notifications,appointment_changes:profileForm.appointment_changes,loyalty_notifications:profileForm.loyalty_notifications,progress_insights:profileForm.progress_insights,default_appointment_mode:profileForm.default_appointment_mode};const{data,error}=await supabase.from("profiles").update({full_name:profileForm.full_name.trim(),email:profileForm.email||null,phone:profileForm.phone||null,preferred_locale:profileForm.preferred_locale,notification_preferences:prefs}).eq("id",profile.id).select("id,full_name,email,phone,preferred_locale").single();if(error)setMessage(error.message);else{onUpdated(data as Profile);setMessage("Hesap ayarları kaydedildi.")}}
  async function saveClient(){const list=(v:string)=>v.split(",").map(x=>x.trim()).filter(Boolean);const{error}=await supabase.from("client_profiles").update({birth_date:clientForm.birth_date||null,gender:clientForm.gender||null,height_cm:clientForm.height_cm?Number(clientForm.height_cm):null,target_text:clientForm.target_text||null,allergies:list(clientForm.allergies),disliked_foods:list(clientForm.disliked_foods),medical_notes:clientForm.medical_notes||null,medications:clientForm.medications||null,community_opt_in:clientForm.community_opt_in,updated_at:new Date().toISOString()}).eq("clinic_id",clinic.id).eq("user_id",profile.id).eq("is_active",true);if(error)setMessage(error.message);else setMessage("Danışan profiliniz güncellendi.")}
  async function saveClinic(){const payload={name:clinicForm.name,phone:clinicForm.phone||null,email:clinicForm.email||null,address:clinicForm.address||null,website:clinicForm.website||null,timezone:clinicForm.timezone,default_locale:clinicForm.default_locale,booking_horizon_days:Number(clinicForm.booking_horizon_days),minimum_booking_notice_hours:Number(clinicForm.minimum_booking_notice_hours),cancellation_notice_hours:Number(clinicForm.cancellation_notice_hours),allow_client_cancellation:clinicForm.allow_client_cancellation,allow_online_booking:clinicForm.allow_online_booking};const{data,error}=await supabase.from("clinics").update(payload).eq("id",clinic.id).select("id,name,slug,default_locale,timezone,phone,email,address,website,booking_horizon_days,minimum_booking_notice_hours,cancellation_notice_hours,allow_client_cancellation,allow_online_booking").single();if(error)setMessage(error.message);else{onClinicUpdated(data as Clinic);setMessage("Klinik ayarları kaydedildi.")}}
  async function saveDiet(){const{error}=await supabase.from("dietitian_profiles").update({title:dietForm.title,license_no:dietForm.license_no||null,bio:dietForm.bio||null,appointment_duration_minutes:Number(dietForm.appointment_duration_minutes),buffer_minutes:Number(dietForm.buffer_minutes),is_bookable:dietForm.is_bookable}).eq("clinic_id",clinic.id).eq("user_id",profile.id);if(error)setMessage(error.message);else setMessage("Diyetisyen ayarları kaydedildi.")}
  async function changePassword(){if(password.password.length<8)return setMessage("Şifre en az 8 karakter olmalı.");if(password.password!==password.confirm)return setMessage("Şifreler eşleşmiyor.");const{error}=await supabase.auth.updateUser({password:password.password});if(error)setMessage(error.message);else{setPassword({password:"",confirm:""});setMessage("Şifre değiştirildi.")}}
  return <><Header title="Ayarlar" description="Hesap, bildirim, beslenme tercihleri, klinik, randevu ve güvenlik ayarlarını yönetin."/>{message&&<div className="notice-bar">{message}</div>}<div className="settings-layout v3-settings-layout"><section className="settings-section"><div className="settings-section-title"><UserCog size={20}/><div><h3>Hesap</h3><p>Kişisel bilgiler ve panel dili.</p></div></div><div className="form-grid"><label>Ad soyad<input value={profileForm.full_name} onChange={e=>setProfileForm({...profileForm,full_name:e.target.value})}/></label><label>E-posta<input value={profileForm.email} onChange={e=>setProfileForm({...profileForm,email:e.target.value})}/></label><label>Telefon<input value={profileForm.phone} onChange={e=>setProfileForm({...profileForm,phone:e.target.value})}/></label><label>Panel dili<select value={profileForm.preferred_locale} onChange={e=>setProfileForm({...profileForm,preferred_locale:e.target.value as Locale})}>{locales.map(l=><option key={l} value={l}>{localeLabels[l]}</option>)}</select></label></div><button className="primary-button compact" onClick={saveProfile}><Save size={14}/>Kaydet</button></section><section className="settings-section"><div className="settings-section-title"><Bell size={20}/><div><h3>Bildirimler</h3><p>Randevu, öğün ve sadakat bildirimleri.</p></div></div><div className="switch-grid">{[["email_notifications","E-posta bildirimleri"],["appointment_reminders","Randevu hatırlatmaları"],["meal_reminders","Öğün hatırlatmaları"],["weekly_summary","Haftalık özet"],["sms_notifications","SMS bildirimleri"],["appointment_changes","Randevu değişiklikleri"],["loyalty_notifications","Sadakat bildirimleri"],["progress_insights","İlerleme analizleri"]].map(([key,label])=><label key={key}><input type="checkbox" checked={Boolean((profileForm as any)[key])} onChange={e=>setProfileForm({...profileForm,[key]:e.target.checked})}/><span><b>{label}</b></span></label>)}</div><button className="primary-button compact" onClick={saveProfile}><Save size={14}/>Bildirimleri kaydet</button></section>{role==="client"&&<section className="settings-section full-width"><div className="settings-section-title"><Activity size={20}/><div><h3>Danışan profili</h3><p>Diyetisyeninizin menü ve takip sürecinde kullanacağı bilgiler.</p></div></div><div className="form-grid"><label>Doğum tarihi<input type="date" value={clientForm.birth_date} onChange={e=>setClientForm({...clientForm,birth_date:e.target.value})}/></label><label>Cinsiyet<select value={clientForm.gender} onChange={e=>setClientForm({...clientForm,gender:e.target.value})}><option value="">Belirtmek istemiyorum</option><option value="female">Kadın</option><option value="male">Erkek</option><option value="other">Diğer</option></select></label><label>Boy (cm)<input type="number" value={clientForm.height_cm} onChange={e=>setClientForm({...clientForm,height_cm:e.target.value})}/></label><label>Hedef<input value={clientForm.target_text} onChange={e=>setClientForm({...clientForm,target_text:e.target.value})}/></label><label className="wide">Alerjiler<input value={clientForm.allergies} onChange={e=>setClientForm({...clientForm,allergies:e.target.value})} placeholder="Virgülle ayırın"/></label><label className="wide">Sevmediğim / kullanmadığım besinler<input value={clientForm.disliked_foods} onChange={e=>setClientForm({...clientForm,disliked_foods:e.target.value})}/></label><label className="wide">Sağlık notları<textarea rows={3} value={clientForm.medical_notes} onChange={e=>setClientForm({...clientForm,medical_notes:e.target.value})}/></label><label className="wide">Kullanılan ilaçlar<textarea rows={3} value={clientForm.medications} onChange={e=>setClientForm({...clientForm,medications:e.target.value})}/></label></div><div className="switch-grid compact-switches"><label><input type="checkbox" checked={clientForm.community_opt_in} onChange={e=>setClientForm({...clientForm,community_opt_in:e.target.checked})}/><span><b>Diyetisyen grubuna katıl</b><small>Aynı diyetisyene bağlı danışanların topluluk paylaşımlarını gör.</small></span></label></div><button className="primary-button compact" onClick={saveClient}><Save size={14}/>Danışan profilini kaydet</button></section>}{role==="client"&&<section className="settings-section full-width client-payment-history"><div className="settings-section-title"><CreditCard size={20}/><div><h3>Ödemelerim</h3><p>Kliniğe ait ödeme durumunuzu ve geçmiş kayıtlarınızı görüntüleyin.</p></div></div><div className="client-payment-summary"><article><CheckCircle2/><span><small>Ödenen toplam</small><b>{money(clientPayments.reduce((sum,p)=>sum+Number(p.paid_amount||0),0))}</b></span></article><article><Clock3/><span><small>Bekleyen toplam</small><b>{money(clientPayments.filter(p=>p.status==="pending"||p.status==="partial").reduce((sum,p)=>sum+Number(p.remaining_amount??Math.max(0,Number(p.amount)-Number(p.paid_amount||0))),0))}</b></span></article><article><WalletCards/><span><small>Toplam kayıt</small><b>{clientPayments.length}</b></span></article></div>{clientPayments.length===0?<Empty text="Henüz ödeme kaydınız bulunmuyor."/>:<div className="client-payment-list">{clientPayments.map(payment=><article key={payment.id}><div className="client-payment-list-icon"><CreditCard size={17}/></div><div><b>{payment.service_type}</b><p>{payment.description||"Açıklama yok"}</p><small>{new Date(payment.paid_at||payment.created_at).toLocaleDateString("tr-TR")} • {paymentMethodText(payment.method)}</small>{payment.due_date&&<small className={new Date(`${payment.due_date}T23:59:59`).getTime()<todayMs?"due-overdue":""}>Son ödeme: {new Date(`${payment.due_date}T12:00:00`).toLocaleDateString("tr-TR")} • {Math.ceil((new Date(`${payment.due_date}T12:00:00`).getTime()-todayMs)/86400000)<0?`${Math.abs(Math.ceil((new Date(`${payment.due_date}T12:00:00`).getTime()-todayMs)/86400000))} gün gecikti`:`${Math.ceil((new Date(`${payment.due_date}T12:00:00`).getTime()-todayMs)/86400000)} gün kaldı`}</small>}</div><div className="client-payment-amounts"><strong>{money(payment.amount)}</strong><small>Alınan {money(payment.paid_amount||0)} • Kalan {money(payment.remaining_amount??Math.max(0,Number(payment.amount)-Number(payment.paid_amount||0)))}</small></div><span className={`payment-badge ${payment.status}`}>{paymentStatusText(payment.status)}</span></article>)}</div>}</section>}{role==="owner"&&<section className="settings-section full-width"><div className="settings-section-title"><Building2 size={20}/><div><h3>Klinik ve rezervasyon</h3><p>Klinik iletişim bilgileri ve rezervasyon kuralları.</p></div></div><div className="form-grid"><label>Klinik adı<input value={clinicForm.name} onChange={e=>setClinicForm({...clinicForm,name:e.target.value})}/></label><label>Varsayılan dil<select value={clinicForm.default_locale} onChange={e=>setClinicForm({...clinicForm,default_locale:e.target.value as Locale})}>{locales.map(l=><option key={l} value={l}>{localeLabels[l]}</option>)}</select></label><label>Telefon<input value={clinicForm.phone} onChange={e=>setClinicForm({...clinicForm,phone:e.target.value})}/></label><label>E-posta<input value={clinicForm.email} onChange={e=>setClinicForm({...clinicForm,email:e.target.value})}/></label><label>Web sitesi<input value={clinicForm.website} onChange={e=>setClinicForm({...clinicForm,website:e.target.value})}/></label><label>Saat dilimi<input value={clinicForm.timezone} onChange={e=>setClinicForm({...clinicForm,timezone:e.target.value})}/></label><label className="wide">Adres<textarea rows={3} value={clinicForm.address} onChange={e=>setClinicForm({...clinicForm,address:e.target.value})}/></label><label>Randevu ufku (gün)<input type="number" value={clinicForm.booking_horizon_days} onChange={e=>setClinicForm({...clinicForm,booking_horizon_days:e.target.value})}/></label><label>Minimum rezervasyon süresi (saat)<input type="number" value={clinicForm.minimum_booking_notice_hours} onChange={e=>setClinicForm({...clinicForm,minimum_booking_notice_hours:e.target.value})}/></label><label>İptal süresi (saat)<input type="number" value={clinicForm.cancellation_notice_hours} onChange={e=>setClinicForm({...clinicForm,cancellation_notice_hours:e.target.value})}/></label></div><div className="switch-grid compact-switches"><label><input type="checkbox" checked={clinicForm.allow_client_cancellation} onChange={e=>setClinicForm({...clinicForm,allow_client_cancellation:e.target.checked})}/><span><b>Danışan iptali</b></span></label><label><input type="checkbox" checked={clinicForm.allow_online_booking} onChange={e=>setClinicForm({...clinicForm,allow_online_booking:e.target.checked})}/><span><b>Online görüşme</b></span></label></div><button className="primary-button compact" onClick={saveClinic}><Save size={14}/>Klinik ayarlarını kaydet</button></section>}{(role==="owner"||role==="dietitian")&&<section className="settings-section"><div className="settings-section-title"><Globe2 size={20}/><div><h3>Diyetisyen profili</h3><p>Unvan, süre ve rezervasyon bilgileri.</p></div></div><div className="form-grid"><label>Unvan<input value={dietForm.title} onChange={e=>setDietForm({...dietForm,title:e.target.value})}/></label><label>Kayıt numarası<input value={dietForm.license_no} onChange={e=>setDietForm({...dietForm,license_no:e.target.value})}/></label><label>Randevu süresi<input type="number" value={dietForm.appointment_duration_minutes} onChange={e=>setDietForm({...dietForm,appointment_duration_minutes:e.target.value})}/></label><label>Mola süresi<input type="number" value={dietForm.buffer_minutes} onChange={e=>setDietForm({...dietForm,buffer_minutes:e.target.value})}/></label><label className="wide">Biyografi<textarea rows={3} value={dietForm.bio} onChange={e=>setDietForm({...dietForm,bio:e.target.value})}/></label></div><div className="switch-grid compact-switches"><label><input type="checkbox" checked={dietForm.is_bookable} onChange={e=>setDietForm({...dietForm,is_bookable:e.target.checked})}/><span><b>Rezervasyona açık</b></span></label></div><button className="primary-button compact" onClick={saveDiet}><Save size={14}/>Diyetisyen ayarlarını kaydet</button></section>}<section className="settings-section"><div className="settings-section-title"><LockKeyhole size={20}/><div><h3>Güvenlik</h3><p>Yeni şifre belirleyin.</p></div></div><div className="form-grid"><label>Yeni şifre<input type="password" value={password.password} onChange={e=>setPassword({...password,password:e.target.value})}/></label><label>Şifre tekrar<input type="password" value={password.confirm} onChange={e=>setPassword({...password,confirm:e.target.value})}/></label></div><button className="secondary-button compact" onClick={changePassword}><LockKeyhole size={14}/>Şifreyi değiştir</button></section></div></>
}
