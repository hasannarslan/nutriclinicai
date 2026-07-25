"use client";
/* eslint-disable @next/next/no-img-element */

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  BedDouble, BellRing, CalendarClock, Check, CheckCircle2, ClipboardCheck, ClipboardList,
  Download, FileCheck2, FileText, Gauge, HardDriveUpload, LoaderCircle, MessageCircle, Package,
  Paperclip, Plus, RefreshCw, Save, Send, ShieldCheck, Smartphone, Trash2, Upload, UserRound, X
} from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import type { Role } from "@/lib/types";

type ClientLite = { id:string; member_no:string; full_name:string; email?:string|null; phone?:string|null; assigned_dietitian_id?:string|null };
type ServiceRow = { id:string; name:string; category:string; description:string|null; default_quantity:number; default_unit_price:number; is_active:boolean };
type PackageItem = { id:string; package_id:string; service_id:string|null; service_name:string; allocated_quantity:number; used_quantity:number; unit_price:number };
type PackageRow = { id:string; client_id:string; name:string; status:string; starts_on:string; ends_on:string|null; total_price:number; currency:string; notes:string|null; created_at:string; client_package_items?:PackageItem[] };
type ResourceRow = { id:string; name:string; resource_type:string; description:string|null; capacity:number; is_active:boolean; client_bookable:boolean; slot_minutes:number; booking_start_time:string; booking_end_time:string };
type ResourceBooking = { id:string|null; resource_id:string; resource_name:string; resource_type:string; client_id:string|null; client_name:string|null; client_email:string|null; client_phone:string|null; starts_at:string; ends_at:string; status:string; note:string|null; is_mine:boolean };
type IntakeTemplate = { id:string; name:string; description:string|null; version:number };
type IntakeResponse = { id:string; answers:Record<string,unknown>; status:string; submitted_at:string|null; reviewed_at:string|null };
type ConsentTemplate = { id:string; name:string; body:string; version:number; is_required:boolean };
type ConsentRow = { id:string; template_id:string; accepted:boolean; signature_name:string|null; accepted_at:string|null; revoked_at:string|null };
type DocumentRow = { id:string; client_id:string; category:string; title:string; file_name:string; storage_path:string; mime_type:string|null; size_bytes:number|null; document_date:string|null; notes:string|null; visible_to_client:boolean; created_at:string };
type MessageRow = { id:string; conversation_id:string; sender_user_id:string; body:string|null; attachment_path:string|null; attachment_name:string|null; attachment_type:string|null; read_at:string|null; created_at:string; signed_url?:string };
type TaskRow = { id:string; client_id:string; title:string; description:string|null; task_type:string; due_date:string|null; status:string; points_reward:number; completed_at:string|null; created_at:string };
type Adherence = { score:number; risk:"low"|"medium"|"high"; attendance:number; meal_tracking:number; water_tracking:number; activity_tracking:number; tasks:number; period_days:number };

type DraftPackageItem = { key:string; service_id:string; service_name:string; quantity:string; unit_price:string };

function PageHeader({title,description,action}:{title:string;description:string;action?:React.ReactNode}){
  return <div className="page-header v3-page-header"><div><span className="section-kicker">NUTRICLINIC AI</span><h1>{title}</h1><p>{description}</p></div>{action&&<div className="page-header-actions">{action}</div>}</div>;
}
function Loading(){return <div className="empty-state"><LoaderCircle className="spin" size={24}/><p>Yükleniyor…</p></div>}
function Empty({title,text,icon}:{title:string;text:string;icon?:React.ReactNode}){return <div className="v6-empty">{icon||<ClipboardList size={30}/>}<h3>{title}</h3><p>{text}</p></div>}
function money(value:number|string|null|undefined){return new Intl.NumberFormat("tr-TR",{style:"currency",currency:"TRY",maximumFractionDigits:2}).format(Number(value)||0)}
function shortDate(value:string|null|undefined){if(!value)return "—";return new Date(value).toLocaleDateString("tr-TR",{day:"2-digit",month:"short",year:"numeric"})}
function dateTime(value:string){return new Date(value).toLocaleString("tr-TR",{day:"2-digit",month:"short",hour:"2-digit",minute:"2-digit"})}
function localDate(){return new Date().toISOString().slice(0,10)}
function uid(){return crypto.randomUUID()}
function safeName(value:string){return value.replace(/[^a-zA-Z0-9._-]+/g,"-").replace(/-+/g,"-")}
function formatBytes(value:number|null){if(!value)return "—";if(value<1024)return `${value} B`;if(value<1048576)return `${(value/1024).toFixed(1)} KB`;return `${(value/1048576).toFixed(1)} MB`}
function roleCanManagePackage(role:Role){return role==="owner"||role==="secretary"}
function roleIsClinical(role:Role){return role==="owner"||role==="dietitian"}

async function getOwnClientId(supabase:ReturnType<typeof createClient>,clinicId:string){
  const {data,error}=await supabase.rpc("current_client_id",{target_clinic:clinicId});
  if(error)throw error;return data as string|null;
}

export function PackagesV6({role,clinicId}:{role:Role;clinicId:string}){
  const supabase=useMemo(()=>createClient(),[]);
  const staff=role!=="client";
  const canManage=roleCanManagePackage(role);
  const [clients,setClients]=useState<ClientLite[]>([]);
  const [services,setServices]=useState<ServiceRow[]>([]);
  const [packages,setPackages]=useState<PackageRow[]>([]);
  const [loading,setLoading]=useState(true);
  const [message,setMessage]=useState("");
  const [selectedClient,setSelectedClient]=useState("");
  const [showForm,setShowForm]=useState(false);
  const [form,setForm]=useState({name:"Başlangıç Paketi",starts_on:localDate(),ends_on:"",notes:"",items:[{key:uid(),service_id:"",service_name:"",quantity:"1",unit_price:"0"}] as DraftPackageItem[]});

  const load=useCallback(async()=>{
    setLoading(true);setMessage("");
    try{
      let clientId:string|null=null;
      if(staff){const {data,error}=await supabase.rpc("get_client_directory_v4");if(error)throw error;const list=(data||[]) as ClientLite[];setClients(list);setSelectedClient(current=>current||list[0]?.id||"");}
      else clientId=await getOwnClientId(supabase,clinicId);
      const serviceResult=staff
        ? await supabase.from("service_catalog").select("id,name,category,description,default_quantity,default_unit_price,is_active").eq("clinic_id",clinicId).eq("is_active",true).order("name")
        : {data:[],error:null};
      let packageQuery=supabase.from("client_packages").select("id,client_id,name,status,starts_on,ends_on,total_price,currency,notes,created_at,client_package_items(id,package_id,service_id,service_name,allocated_quantity,used_quantity,unit_price)").eq("clinic_id",clinicId);
      if(clientId)packageQuery=packageQuery.eq("client_id",clientId);
      const packageResult=await packageQuery.order("created_at",{ascending:false});
      if(serviceResult.error)throw serviceResult.error;if(packageResult.error)throw packageResult.error;setServices((serviceResult.data||[]) as ServiceRow[]);setPackages((packageResult.data||[]) as PackageRow[]);
    }catch(error){setMessage(error instanceof Error?error.message:"Paketler yüklenemedi.");}
    setLoading(false);
  },[clinicId,staff,supabase]);
  useEffect(()=>{void load()},[load]);

  const total=useMemo(()=>form.items.reduce((sum,item)=>sum+(Number(item.quantity)||0)*(Number(item.unit_price)||0),0),[form.items]);
  function updateItem(key:string,patch:Partial<DraftPackageItem>){setForm(current=>({...current,items:current.items.map(item=>item.key===key?{...item,...patch}:item)}))}
  function chooseService(key:string,id:string){const service=services.find(row=>row.id===id);if(!service)return updateItem(key,{service_id:"",service_name:""});updateItem(key,{service_id:id,service_name:service.name,quantity:String(service.default_quantity),unit_price:String(service.default_unit_price)})}
  async function savePackage(){
    if(!selectedClient)return setMessage("Danışan seçin.");
    const items=form.items.filter(x=>x.service_name.trim()&&Number(x.quantity)>0);
    if(!form.name.trim()||!items.length)return setMessage("Paket adı ve en az bir hizmet girin.");
    setMessage("");
    const {data:user}=await supabase.auth.getUser();
    const {data:created,error}=await supabase.from("client_packages").insert({clinic_id:clinicId,client_id:selectedClient,name:form.name.trim(),starts_on:form.starts_on,ends_on:form.ends_on||null,total_price:total,notes:form.notes||null,created_by:user.user?.id}).select("id").single();
    if(error||!created)return setMessage(error?.message||"Paket oluşturulamadı.");
    const {error:itemError}=await supabase.from("client_package_items").insert(items.map(item=>({package_id:created.id,service_id:item.service_id||null,service_name:item.service_name.trim(),allocated_quantity:Number(item.quantity),unit_price:Number(item.unit_price)||0})));
    if(itemError){await supabase.from("client_packages").delete().eq("id",created.id);return setMessage(itemError.message)}
    setShowForm(false);setForm({name:"Başlangıç Paketi",starts_on:localDate(),ends_on:"",notes:"",items:[{key:uid(),service_id:"",service_name:"",quantity:"1",unit_price:"0"}]});setMessage("Paket oluşturuldu.");await load();
  }
  async function consume(item:PackageItem){const {error}=await supabase.rpc("consume_package_item_v6",{p_package_item_id:item.id,p_quantity:1,p_appointment_id:null,p_note:null});if(error)setMessage(error.message);else{setMessage(`${item.service_name} için 1 kullanım düşüldü.`);await load()}}
  async function removePackage(id:string){if(!confirm("Paket ve kullanım kayıtları silinsin mi?"))return;const {error}=await supabase.from("client_packages").delete().eq("id",id);if(error)setMessage(error.message);else await load()}
  const clientMap=useMemo(()=>new Map(clients.map(c=>[c.id,c])),[clients]);

  return <><PageHeader title="Paket ve Seanslar" description={staff?"Danışanın satın aldığı hizmetleri, kalan seansları ve kullanım geçmişini tek ekranda yönetin.":"Satın aldığınız paketleri, kullanılan ve kalan seanslarınızı görüntüleyin."} action={canManage?<button className="primary-button compact" onClick={()=>setShowForm(true)}><Plus size={15}/>Yeni paket</button>:undefined}/>
    {message&&<div className="notice-bar"><span>{message}</span><button onClick={()=>setMessage("")}><X size={15}/></button></div>}
    {showForm&&canManage&&<section className="surface-card v6-form-card"><div className="surface-head"><div><span className="section-kicker">YENİ PAKET</span><h3>Hizmet paketini oluştur</h3><p>Hizmet, adet ve birim fiyatlardan toplam otomatik hesaplanır.</p></div><button className="drawer-close" onClick={()=>setShowForm(false)}><X size={18}/></button></div>
      <div className="form-grid"><label>Danışan<select value={selectedClient} onChange={e=>setSelectedClient(e.target.value)}>{clients.map(c=><option key={c.id} value={c.id}>{c.full_name} • {c.member_no}</option>)}</select></label><label>Paket adı<input value={form.name} onChange={e=>setForm({...form,name:e.target.value})}/></label><label>Başlangıç<input type="date" value={form.starts_on} onChange={e=>setForm({...form,starts_on:e.target.value})}/></label><label>Bitiş<input type="date" value={form.ends_on} onChange={e=>setForm({...form,ends_on:e.target.value})}/></label><label className="wide">Not<textarea rows={2} value={form.notes} onChange={e=>setForm({...form,notes:e.target.value})}/></label></div>
      <div className="v6-service-lines">{form.items.map((item,index)=><article key={item.key}><b>{index+1}</b><label>Hazır hizmet<select value={item.service_id} onChange={e=>chooseService(item.key,e.target.value)}><option value="">Serbest hizmet</option>{services.map(service=><option key={service.id} value={service.id}>{service.name}</option>)}</select></label><label>Hizmet adı<input value={item.service_name} onChange={e=>updateItem(item.key,{service_name:e.target.value})}/></label><label>Adet<input type="number" min="0.1" step="0.1" value={item.quantity} onChange={e=>updateItem(item.key,{quantity:e.target.value})}/></label><label>Birim fiyat<input type="number" min="0" step="0.01" value={item.unit_price} onChange={e=>updateItem(item.key,{unit_price:e.target.value})}/></label><strong>{money((Number(item.quantity)||0)*(Number(item.unit_price)||0))}</strong><button className="icon-danger" onClick={()=>setForm(current=>({...current,items:current.items.filter(x=>x.key!==item.key)}))}><Trash2 size={15}/></button></article>)}</div>
      <button className="secondary-button compact" onClick={()=>setForm(current=>({...current,items:[...current.items,{key:uid(),service_id:"",service_name:"",quantity:"1",unit_price:"0"}]}))}><Plus size={14}/>Hizmet ekle</button>
      <div className="v6-total"><span>Paket toplamı</span><b>{money(total)}</b></div><div className="form-actions"><button className="secondary-button" onClick={()=>setShowForm(false)}>Vazgeç</button><button className="primary-button" onClick={savePackage}><Save size={15}/>Paketi kaydet</button></div>
    </section>}
    {loading?<Loading/>:<div className="v6-package-grid">{packages.length===0?<Empty title="Paket bulunmuyor" text={staff?"Danışana ilk hizmet paketini oluşturabilirsiniz.":"Kliniğiniz paket tanımladığında burada görünecektir."} icon={<Package size={32}/>} />:packages.map(pack=>{const items=pack.client_package_items||[];const completed=items.reduce((a,x)=>a+Number(x.used_quantity),0);const allocated=items.reduce((a,x)=>a+Number(x.allocated_quantity),0);const percent=allocated?Math.min(100,Math.round(completed/allocated*100)):0;return <article className="surface-card v6-package-card" key={pack.id}><header><div><span className={`status ${pack.status}`}>{pack.status==="active"?"Aktif":pack.status==="completed"?"Tamamlandı":pack.status}</span><h3>{pack.name}</h3><p>{staff?`${clientMap.get(pack.client_id)?.full_name||"Danışan"} • ${clientMap.get(pack.client_id)?.member_no||""}`:`${shortDate(pack.starts_on)} – ${shortDate(pack.ends_on)}`}</p></div>{canManage&&<button className="icon-danger" onClick={()=>removePackage(pack.id)}><Trash2 size={15}/></button>}</header><div className="v6-package-progress"><div><span style={{width:`${percent}%`}}/></div><small>{completed} / {allocated} kullanım tamamlandı</small></div><div className="v6-package-items">{items.map(item=>{const remaining=Number(item.allocated_quantity)-Number(item.used_quantity);return <div key={item.id}><span><b>{item.service_name}</b><small>{item.used_quantity} kullanıldı • {remaining} kaldı</small></span><strong>{remaining}/{item.allocated_quantity}</strong>{staff&&remaining>0&&<button className="secondary-button compact" onClick={()=>consume(item)}><Check size={13}/>1 kullanım düş</button>}</div>})}</div><footer><span>{money(pack.total_price)}</span><small>{pack.notes||"Paket notu bulunmuyor."}</small></footer></article>})}</div>}
  </>;
}

export function ResourcesV6({role,clinicId}:{role:Role;clinicId:string}){
  const supabase=useMemo(()=>createClient(),[]);
  const clientMode=role==="client";
  const canManageResources=role==="owner"||role==="dietitian";
  const [resources,setResources]=useState<ResourceRow[]>([]);
  const [bookings,setBookings]=useState<ResourceBooking[]>([]);
  const [clients,setClients]=useState<ClientLite[]>([]);
  const [loading,setLoading]=useState(true);
  const [message,setMessage]=useState("");
  const [resourceForm,setResourceForm]=useState({name:"",resource_type:"device",description:"",capacity:"1",client_bookable:true,slot_minutes:"45",booking_start_time:"09:00",booking_end_time:"18:00"});
  const [bookingForm,setBookingForm]=useState({resource_id:"",client_id:"",date:localDate(),start:"09:00",end:"09:45",note:""});
  const [selectedSlot,setSelectedSlot]=useState("");

  const load=useCallback(async()=>{
    setLoading(true);setMessage("");
    const from=new Date(Date.now()-86400000).toISOString();
    const to=new Date(Date.now()+1000*60*60*24*120).toISOString();
    const resourceQuery=supabase.from("clinic_resources")
      .select("id,name,resource_type,description,capacity,is_active,client_bookable,slot_minutes,booking_start_time,booking_end_time")
      .eq("clinic_id",clinicId).order("is_active",{ascending:false}).order("name");
    const [resourceResult,scheduleResult,clientResult]=await Promise.all([
      resourceQuery,
      supabase.rpc("get_resource_schedule_v6_2",{p_clinic_id:clinicId,p_start:from,p_end:to}),
      clientMode?Promise.resolve({data:[],error:null}):supabase.rpc("get_client_directory_v4")
    ]);
    if(resourceResult.error)setMessage(resourceResult.error.message);
    else if(scheduleResult.error)setMessage(scheduleResult.error.message);
    else if(clientResult.error)setMessage(clientResult.error.message);
    const resourceRows=(resourceResult.data||[]) as ResourceRow[];
    const bookingRows=((scheduleResult.data||[]) as Array<Record<string,unknown>>).map(row=>({
      id:(row.booking_id as string|null)||null,
      resource_id:String(row.resource_id||""),resource_name:String(row.resource_name||"Cihaz"),resource_type:String(row.resource_type||"device"),
      client_id:(row.client_id as string|null)||null,client_name:(row.client_name as string|null)||null,client_email:(row.client_email as string|null)||null,
      client_phone:(row.client_phone as string|null)||null,starts_at:String(row.starts_at),ends_at:String(row.ends_at),status:String(row.status),
      note:(row.note as string|null)||null,is_mine:Boolean(row.is_mine)
    }));
    const clientRows=(clientResult.data||[]) as ClientLite[];
    setResources(resourceRows);setBookings(bookingRows);setClients(clientRows);
    setBookingForm(current=>{
      const first=resourceRows.find(r=>r.is_active&&(!clientMode||r.client_bookable));
      const resource=resourceRows.find(r=>r.id===current.resource_id)||first;
      return {...current,resource_id:resource?.id||"",client_id:current.client_id||(clientRows[0]?.id||""),start:current.start||resource?.booking_start_time?.slice(0,5)||"09:00"};
    });
    setLoading(false);
  },[clientMode,clinicId,supabase]);
  useEffect(()=>{void load()},[load]);

  async function addResource(){
    if(!resourceForm.name.trim())return setMessage("Cihaz veya oda adı girin.");
    const {data:user}=await supabase.auth.getUser();
    const {error}=await supabase.from("clinic_resources").insert({
      clinic_id:clinicId,name:resourceForm.name.trim(),resource_type:resourceForm.resource_type,description:resourceForm.description||null,
      capacity:Number(resourceForm.capacity)||1,client_bookable:resourceForm.client_bookable,slot_minutes:Number(resourceForm.slot_minutes)||45,
      booking_start_time:resourceForm.booking_start_time,booking_end_time:resourceForm.booking_end_time,created_by:user.user?.id
    });
    if(error)setMessage(error.message);else{
      setResourceForm({name:"",resource_type:"device",description:"",capacity:"1",client_bookable:true,slot_minutes:"45",booking_start_time:"09:00",booking_end_time:"18:00"});
      setMessage("Cihaz/oda eklendi.");await load();
    }
  }
  async function archiveResource(id:string){
    if(!confirm("Bu cihaz/oda listeden kaldırılsın mı? Geçmiş rezervasyonlar korunacaktır."))return;
    const {error}=await supabase.rpc("archive_clinic_resource_v6_2",{p_resource_id:id});
    if(error)setMessage(error.message);else{setMessage("Cihaz/oda pasife alındı.");await load()}
  }
  async function restoreResource(id:string){
    const {error}=await supabase.from("clinic_resources").update({is_active:true}).eq("id",id);
    if(error)setMessage(error.message);else await load();
  }
  async function addStaffBooking(){
    if(!bookingForm.resource_id)return setMessage("Cihaz veya oda seçin.");
    const start=new Date(`${bookingForm.date}T${bookingForm.start}:00`);const end=new Date(`${bookingForm.date}T${bookingForm.end}:00`);
    if(end<=start)return setMessage("Bitiş saati başlangıçtan sonra olmalı.");
    const {data:user}=await supabase.auth.getUser();
    const {error}=await supabase.from("resource_bookings").insert({clinic_id:clinicId,resource_id:bookingForm.resource_id,client_id:bookingForm.client_id||null,starts_at:start.toISOString(),ends_at:end.toISOString(),status:"confirmed",note:bookingForm.note||null,created_by:user.user?.id});
    if(error)setMessage(error.code==="23P01"?"Bu cihaz veya oda seçilen saatte zaten rezerve edilmiş.":error.message);else{setMessage("Rezervasyon oluşturuldu.");await load()}
  }
  async function addClientBooking(){
    if(!bookingForm.resource_id||!selectedSlot)return setMessage("Cihaz ve müsait saat seçin.");
    const resource=resources.find(r=>r.id===bookingForm.resource_id);if(!resource)return;
    const start=new Date(`${bookingForm.date}T${selectedSlot}:00`);
    const end=new Date(start.getTime()+Number(resource.slot_minutes||45)*60000);
    const {error}=await supabase.rpc("create_client_resource_booking_v6_2",{p_clinic_id:clinicId,p_resource_id:resource.id,p_starts_at:start.toISOString(),p_ends_at:end.toISOString(),p_note:bookingForm.note||null});
    if(error)setMessage(error.message);else{setMessage("Cihaz randevu talebiniz alındı. Klinik onayından sonra kesinleşecektir.");setSelectedSlot("");setBookingForm(current=>({...current,note:""}));await load()}
  }
  async function cancelClientBooking(id:string|null){
    if(!id)return;const {error}=await supabase.rpc("cancel_client_resource_booking_v6_2",{p_booking_id:id});
    if(error)setMessage(error.message);else{setMessage("Cihaz randevunuz iptal edildi.");await load()}
  }
  async function setBookingStatus(id:string|null,status:string){
    if(!id)return;const {error}=await supabase.rpc("set_resource_booking_status_v6_2",{p_booking_id:id,p_status:status});
    if(error)setMessage(error.message);else await load();
  }

  const activeResources=useMemo(()=>resources.filter(r=>r.is_active&&(!clientMode||r.client_bookable)),[clientMode,resources]);
  const selectedResource=useMemo(()=>activeResources.find(r=>r.id===bookingForm.resource_id)||activeResources[0],[activeResources,bookingForm.resource_id]);
  const slots=useMemo(()=>{
    if(!selectedResource)return [] as Array<{time:string;busy:boolean;mine:boolean}>;
    const toMinutes=(value:string)=>{const [h,m]=value.slice(0,5).split(":").map(Number);return h*60+m};
    const toTime=(value:number)=>`${String(Math.floor(value/60)).padStart(2,"0")}:${String(value%60).padStart(2,"0")}`;
    const start=toMinutes(selectedResource.booking_start_time);const end=toMinutes(selectedResource.booking_end_time);const length=Number(selectedResource.slot_minutes)||45;
    const result:Array<{time:string;busy:boolean;mine:boolean}>=[];
    for(let minute=start;minute+length<=end;minute+=length){
      const time=toTime(minute);const slotStart=new Date(`${bookingForm.date}T${time}:00`);const slotEnd=new Date(slotStart.getTime()+length*60000);
      const collision=bookings.find(b=>b.resource_id===selectedResource.id&&b.status!=="cancelled"&&new Date(b.starts_at)<slotEnd&&new Date(b.ends_at)>slotStart);
      result.push({time,busy:Boolean(collision),mine:Boolean(collision?.is_mine)});
    }
    return result;
  },[bookingForm.date,bookings,selectedResource]);
  const clientBookings=useMemo(()=>bookings.filter(b=>b.is_mine).sort((a,b)=>new Date(a.starts_at).getTime()-new Date(b.starts_at).getTime()),[bookings]);
  const staffBookings=useMemo(()=>[...bookings].sort((a,b)=>new Date(a.starts_at).getTime()-new Date(b.starts_at).getTime()),[bookings]);

  if(clientMode){
    return <><PageHeader title="Cihaz Randevuları" description="Kliniğinizin rezervasyona açtığı cihazları ve müsait saatleri seçin; talebiniz onaylandığında bildirim alın." action={<button className="secondary-button compact" onClick={()=>load()}><RefreshCw size={14}/>Yenile</button>}/>
      {message&&<div className="notice-bar"><span>{message}</span><button onClick={()=>setMessage("")}><X size={15}/></button></div>}
      {loading?<Loading/>:<><section className="surface-card v62-client-resource-booking"><div className="surface-head"><div><span className="section-kicker">YENİ TALEP</span><h3>Cihaz ve saat seçin</h3><p>Dolu saatler pasiftir. Oluşturulan talep Klinik Sahibi, Diyetisyen veya Sekreter tarafından onaylanır.</p></div><CalendarClock size={22}/></div>
        {activeResources.length===0?<Empty title="Cihaz rezervasyonu henüz açılmadı" text="Kliniğiniz cihazları danışan rezervasyonuna açtığında bu bölüm kullanıma açılacaktır." icon={<BedDouble size={31}/>}/>:<>
          <div className="form-grid compact"><label>Cihaz<select value={bookingForm.resource_id} onChange={e=>{setBookingForm({...bookingForm,resource_id:e.target.value});setSelectedSlot("")}}>{activeResources.map(r=><option key={r.id} value={r.id}>{r.name}</option>)}</select></label><label>Tarih<input type="date" min={localDate()} value={bookingForm.date} onChange={e=>{setBookingForm({...bookingForm,date:e.target.value});setSelectedSlot("")}}/></label><label className="wide">Not<input value={bookingForm.note} onChange={e=>setBookingForm({...bookingForm,note:e.target.value})} placeholder="İsteğe bağlı kısa not"/></label></div>
          <div className="v62-slot-legend"><span><i className="available"/>Müsait</span><span><i className="busy"/>Dolu</span><span><i className="selected"/>Seçilen</span></div>
          <div className="v62-resource-slots">{slots.map(slot=><button key={slot.time} type="button" disabled={slot.busy} className={`${slot.busy?"busy":"available"} ${selectedSlot===slot.time?"selected":""}`} onClick={()=>setSelectedSlot(slot.time)}><b>{slot.time}</b><small>{slot.mine?"Sizin randevunuz":slot.busy?"Dolu":selectedSlot===slot.time?"Seçildi":"Müsait"}</small></button>)}</div>
          <button className="primary-button" disabled={!selectedSlot} onClick={addClientBooking}><CalendarClock size={15}/>{selectedSlot?`${selectedSlot} için talep oluştur`:"Önce müsait saat seçin"}</button>
        </>}
      </section>
      <section className="surface-card"><div className="surface-head"><div><span className="section-kicker">RANDEVULARIM</span><h3>Yaklaşan cihaz randevuları</h3></div><span className="count-badge">{clientBookings.length} kayıt</span></div>{clientBookings.length===0?<Empty title="Cihaz randevunuz yok" text="Yeni bir cihaz ve müsait saat seçerek talep oluşturabilirsiniz."/>:<div className="v6-booking-list">{clientBookings.map(b=><article key={b.id||`${b.resource_id}-${b.starts_at}`} className={b.status==="cancelled"?"cancelled":""}><div className="v6-date-tile"><b>{new Date(b.starts_at).toLocaleDateString("tr-TR",{day:"2-digit"})}</b><span>{new Date(b.starts_at).toLocaleDateString("tr-TR",{month:"short"})}</span></div><div><b>{b.resource_name}</b><p>{dateTime(b.starts_at)} – {new Date(b.ends_at).toLocaleTimeString("tr-TR",{hour:"2-digit",minute:"2-digit"})}</p><small>{b.note||"Not bulunmuyor"}</small></div><span className={`status ${b.status}`}>{b.status==="pending"?"Onay bekliyor":b.status==="confirmed"?"Onaylandı":b.status==="completed"?"Tamamlandı":"İptal"}</span>{["pending","confirmed"].includes(b.status)&&new Date(b.starts_at)>new Date()&&<button className="icon-danger" onClick={()=>cancelClientBooking(b.id)}><X size={15}/></button>}</article>)}</div>}</section></>}
    </>;
  }

  return <><PageHeader title="Cihaz ve Oda Takvimi" description="BodyShape, G5, ölçüm odası ve diğer kaynakların takvimini yönetin; danışan taleplerini onaylayın." action={<button className="secondary-button compact" onClick={()=>load()}><RefreshCw size={14}/>Yenile</button>}/>
    {message&&<div className="notice-bar"><span>{message}</span><button onClick={()=>setMessage("")}><X size={15}/></button></div>}
    <div className="v6-two-column"><section className="surface-card"><div className="surface-head"><div><span className="section-kicker">REZERVASYON</span><h3>Cihaz veya oda ayır</h3></div><CalendarClock size={22}/></div><div className="form-grid compact"><label>Kaynak<select value={bookingForm.resource_id} onChange={e=>setBookingForm({...bookingForm,resource_id:e.target.value})}><option value="">Seçin</option>{resources.filter(x=>x.is_active).map(r=><option key={r.id} value={r.id}>{r.name}</option>)}</select></label><label>Danışan<select value={bookingForm.client_id} onChange={e=>setBookingForm({...bookingForm,client_id:e.target.value})}><option value="">Danışansız rezervasyon</option>{clients.map(c=><option key={c.id} value={c.id}>{c.full_name}</option>)}</select></label><label>Tarih<input type="date" value={bookingForm.date} onChange={e=>setBookingForm({...bookingForm,date:e.target.value})}/></label><label>Başlangıç<input type="time" value={bookingForm.start} onChange={e=>setBookingForm({...bookingForm,start:e.target.value})}/></label><label>Bitiş<input type="time" value={bookingForm.end} onChange={e=>setBookingForm({...bookingForm,end:e.target.value})}/></label><label>Not<input value={bookingForm.note} onChange={e=>setBookingForm({...bookingForm,note:e.target.value})}/></label></div><button className="primary-button" onClick={addStaffBooking}><Save size={15}/>Rezervasyonu oluştur</button></section>
      {canManageResources&&<section className="surface-card"><div className="surface-head"><div><span className="section-kicker">CİHAZ YÖNETİMİ</span><h3>Yeni cihaz veya oda</h3></div><BedDouble size={22}/></div><div className="form-grid compact"><label>Ad<input value={resourceForm.name} onChange={e=>setResourceForm({...resourceForm,name:e.target.value})} placeholder="Örn. BodyShape 1"/></label><label>Tür<select value={resourceForm.resource_type} onChange={e=>setResourceForm({...resourceForm,resource_type:e.target.value})}><option value="device">Cihaz</option><option value="room">Oda</option><option value="equipment">Ekipman</option><option value="other">Diğer</option></select></label><label>Seans süresi<input type="number" min="15" step="5" value={resourceForm.slot_minutes} onChange={e=>setResourceForm({...resourceForm,slot_minutes:e.target.value})}/></label><label>Başlangıç<input type="time" value={resourceForm.booking_start_time} onChange={e=>setResourceForm({...resourceForm,booking_start_time:e.target.value})}/></label><label>Bitiş<input type="time" value={resourceForm.booking_end_time} onChange={e=>setResourceForm({...resourceForm,booking_end_time:e.target.value})}/></label><label>Kapasite<input type="number" min="1" value={resourceForm.capacity} onChange={e=>setResourceForm({...resourceForm,capacity:e.target.value})}/></label><label className="wide">Açıklama<input value={resourceForm.description} onChange={e=>setResourceForm({...resourceForm,description:e.target.value})}/></label><label className="form-check wide"><input className="form-check-input" type="checkbox" checked={resourceForm.client_bookable} onChange={e=>setResourceForm({...resourceForm,client_bookable:e.target.checked})}/><span className="form-check-label">Danışanlar bu cihazdan randevu alabilsin</span></label></div><button className="secondary-button" onClick={addResource}><Plus size={15}/>Cihaz/oda ekle</button></section>}
    </div>
    {canManageResources&&<section className="surface-card"><div className="surface-head"><div><span className="section-kicker">KAYNAKLAR</span><h3>Cihaz ve oda listesi</h3></div><span className="count-badge">{resources.filter(r=>r.is_active).length} aktif</span></div><div className="v62-resource-manager">{resources.map(resource=><article key={resource.id} className={!resource.is_active?"inactive":""}><div><span className={`status ${resource.is_active?"confirmed":"cancelled"}`}>{resource.is_active?"Aktif":"Pasif"}</span><b>{resource.name}</b><p>{resource.resource_type==="device"?"Cihaz":resource.resource_type==="room"?"Oda":resource.resource_type==="equipment"?"Ekipman":"Diğer"} • {resource.slot_minutes} dk • {resource.booking_start_time.slice(0,5)}–{resource.booking_end_time.slice(0,5)}</p><small>{resource.client_bookable?"Danışan rezervasyonuna açık":"Yalnızca klinik ekibi kullanabilir"}</small></div>{resource.is_active?<button className="icon-danger" onClick={()=>archiveResource(resource.id)}><Trash2 size={15}/>Sil</button>:<button className="secondary-button compact" onClick={()=>restoreResource(resource.id)}><RefreshCw size={13}/>Geri aç</button>}</article>)}</div></section>}
    {loading?<Loading/>:<section className="surface-card"><div className="surface-head"><div><span className="section-kicker">YAKLAŞAN</span><h3>Cihaz ve oda rezervasyonları</h3></div><span className="count-badge">{staffBookings.length} kayıt</span></div>{staffBookings.length===0?<Empty title="Rezervasyon yok" text="Cihaz veya oda için ilk zaman aralığını ayırabilirsiniz."/>:<div className="v6-booking-list">{staffBookings.map(b=><article key={b.id||`${b.resource_id}-${b.starts_at}`}><div className="v6-date-tile"><b>{new Date(b.starts_at).toLocaleDateString("tr-TR",{day:"2-digit"})}</b><span>{new Date(b.starts_at).toLocaleDateString("tr-TR",{month:"short"})}</span></div><div><b>{b.resource_name}</b><p>{dateTime(b.starts_at)} – {new Date(b.ends_at).toLocaleTimeString("tr-TR",{hour:"2-digit",minute:"2-digit"})}</p><small>{b.client_name||"Klinik rezervasyonu"}{b.client_phone?` • ${b.client_phone}`:""}{b.client_email?` • ${b.client_email}`:""}{b.note?` • ${b.note}`:""}</small></div><span className={`status ${b.status}`}>{b.status==="pending"?"Onay bekliyor":b.status==="confirmed"?"Onaylı":b.status==="completed"?"Tamamlandı":"İptal"}</span><div className="v62-booking-actions">{b.status==="pending"&&<button className="secondary-button compact" onClick={()=>setBookingStatus(b.id,"confirmed")}><Check size={13}/>Onayla</button>}{b.status==="confirmed"&&<button className="secondary-button compact" onClick={()=>setBookingStatus(b.id,"completed")}><CheckCircle2 size={13}/>Tamamlandı</button>}{["pending","confirmed"].includes(b.status)&&<button className="icon-danger" onClick={()=>setBookingStatus(b.id,"cancelled")}><X size={15}/></button>}</div></article>)}</div>}</section>}
  </>;
}

const anamnesisFields=[
  ["health_history","Hastalık ve sağlık geçmişi","Tanılar, önceki sağlık sorunları"],
  ["medications","Kullanılan ilaç ve takviyeler","İsim, doz ve kullanım sıklığı"],
  ["operations","Ameliyat ve önemli tedaviler","Tarih ve kısa açıklama"],
  ["digestion","Sindirim şikâyetleri","Şişkinlik, kabızlık, reflü vb."],
  ["sleep","Uyku düzeni","Saat, kalite ve gece uyanmaları"],
  ["tobacco_alcohol","Sigara ve alkol","Sıklık ve miktar"],
  ["activity","Günlük aktivite","İş, yürüyüş, egzersiz alışkanlığı"],
  ["nutrition_history","Beslenme ve diyet geçmişi","Önceki diyetler, öğün düzeni"],
  ["emotional_eating","Duygusal yeme","Stres, gece yeme ve tetikleyiciler"],
  ["women_health","Kadın sağlığı bilgileri","Gerekliyse adet düzeni, gebelik/emzirme"],
  ["notes","Ek notlar","Diyetisyeninizin bilmesini istediğiniz diğer bilgiler"]
] as const;

export function FormsConsentsV6({role,clinicId}:{role:Role;clinicId:string}){
  const supabase=useMemo(()=>createClient(),[]);const clientMode=role==="client";const clinical=roleIsClinical(role);
  const [clients,setClients]=useState<ClientLite[]>([]);const [clientId,setClientId]=useState("");const [template,setTemplate]=useState<IntakeTemplate|null>(null);const [response,setResponse]=useState<IntakeResponse|null>(null);const [answers,setAnswers]=useState<Record<string,string>>({});const [consentTemplates,setConsentTemplates]=useState<ConsentTemplate[]>([]);const [consents,setConsents]=useState<ConsentRow[]>([]);const [signature,setSignature]=useState("");const [loading,setLoading]=useState(true);const [message,setMessage]=useState("");
  const loadBase=useCallback(async()=>{setLoading(true);try{let target="";if(clientMode){target=(await getOwnClientId(supabase,clinicId))||"";}else{const {data,error}=await supabase.rpc("get_client_directory_v4");if(error)throw error;const list=(data||[]) as ClientLite[];setClients(list);target=clientId||list[0]?.id||"";}setClientId(target);const [{data:t,error:te},{data:ct,error:ce}]=await Promise.all([supabase.from("intake_templates").select("id,name,description,version").eq("clinic_id",clinicId).eq("is_active",true).order("created_at").limit(1),supabase.from("consent_templates").select("id,name,body,version,is_required").eq("clinic_id",clinicId).eq("is_active",true).order("is_required",{ascending:false})]);if(te)throw te;if(ce)throw ce;setTemplate((t?.[0]||null) as IntakeTemplate|null);setConsentTemplates((ct||[]) as ConsentTemplate[]);if(target)await loadClient(target,t?.[0]?.id||null);}catch(error){setMessage(error instanceof Error?error.message:"Formlar yüklenemedi.")}setLoading(false)},[clientId,clientMode,clinicId,supabase]);
  async function loadClient(target:string,templateId?:string|null){const tid=templateId||template?.id;if(!target)return;const [r,c]=await Promise.all([tid?supabase.from("intake_responses").select("id,answers,status,submitted_at,reviewed_at").eq("client_id",target).eq("template_id",tid).maybeSingle():Promise.resolve({data:null,error:null}),supabase.from("client_consents").select("id,template_id,accepted,signature_name,accepted_at,revoked_at").eq("client_id",target)]);if(r.error)setMessage(r.error.message);const rr=(r.data||null) as IntakeResponse|null;setResponse(rr);setAnswers(Object.fromEntries(Object.entries(rr?.answers||{}).map(([k,v])=>[k,String(v??"")])));setConsents((c.data||[]) as ConsentRow[]);setSignature((c.data?.find((x:any)=>x.signature_name)?.signature_name)||"")}
  useEffect(()=>{void loadBase()},[loadBase]);
  async function switchClient(value:string){setClientId(value);setLoading(true);await loadClient(value);setLoading(false)}
  async function saveAnamnesis(submit:boolean){if(!template||!clientId)return;const payload={clinic_id:clinicId,template_id:template.id,client_id:clientId,answers,status:submit?"submitted":"draft",submitted_at:submit?new Date().toISOString():null,updated_at:new Date().toISOString()};const {error}=await supabase.from("intake_responses").upsert(payload,{onConflict:"template_id,client_id"});if(error)setMessage(error.message);else{setMessage(submit?"Anamnez formu gönderildi.":"Taslak kaydedildi.");await loadClient(clientId)}}
  async function review(){if(!response)return;const {data:user}=await supabase.auth.getUser();const {error}=await supabase.from("intake_responses").update({status:"reviewed",reviewed_at:new Date().toISOString(),reviewed_by:user.user?.id}).eq("id",response.id);if(error)setMessage(error.message);else await loadClient(clientId)}
  async function saveConsents(){
    if(!clientId)return setMessage("Danışan profili bulunamadı. Sayfayı yenileyip tekrar deneyin.");
    if(!signature.trim())return setMessage("Onay için ad soyad yazın.");
    const missingRequired=consentTemplates.filter(t=>t.is_required&&!consents.find(c=>c.template_id===t.id)?.accepted);
    if(missingRequired.length)return setMessage(`Zorunlu onamları kabul edin: ${missingRequired.map(t=>t.name).join(", ")}`);
    const rows=consentTemplates.map(t=>{
      const current=consents.find(c=>c.template_id===t.id);
      const accepted=Boolean(current?.accepted);
      return {
        ...(current?.id?{id:current.id}:{}),
        clinic_id:clinicId,
        template_id:t.id,
        client_id:clientId,
        accepted,
        signature_name:signature.trim(),
        template_version:t.version,
        accepted_at:accepted?(current?.accepted_at||new Date().toISOString()):null,
        revoked_at:accepted?null:(current?.accepted_at?new Date().toISOString():null),
        user_agent:navigator.userAgent,
        updated_at:new Date().toISOString()
      };
    });
    const {error}=await supabase.from("client_consents").upsert(rows,{onConflict:"template_id,client_id"});
    if(error)setMessage(error.message);
    else{setMessage("Onay tercihleriniz kaydedildi.");await loadClient(clientId)}
  }
  function toggleConsent(templateId:string,accepted:boolean){const current=consents.find(c=>c.template_id===templateId);setConsents(list=>current?list.map(c=>c.template_id===templateId?{...c,accepted,accepted_at:accepted?new Date().toISOString():null}:c):[...list,{id:"",template_id:templateId,accepted,signature_name:signature,accepted_at:accepted?new Date().toISOString():null,revoked_at:null}])}
  const selectedName=clientMode?"Danışan":clients.find(c=>c.id===clientId)?.full_name||"Danışan";
  return <><PageHeader title="Anamnez ve Onam" description={clientMode?"İlk görüşme öncesi sağlık öykünüzü tamamlayın ve klinik onaylarını yönetin.":"Danışanın görüşme öncesi formunu ve onam durumunu tek dosyada inceleyin."}/>{message&&<div className="notice-bar"><span>{message}</span><button onClick={()=>setMessage("")}><X size={15}/></button></div>}{!clientMode&&<section className="surface-card v6-client-select"><label>Danışan<select value={clientId} onChange={e=>switchClient(e.target.value)}>{clients.map(c=><option key={c.id} value={c.id}>{c.full_name} • {c.member_no}</option>)}</select></label><span><UserRound size={18}/>{selectedName}</span></section>}
    {loading?<Loading/>:<div className="v6-form-layout"><section className="surface-card"><div className="surface-head"><div><span className="section-kicker">ANAMNEZ</span><h3>{template?.name||"İlk görüşme formu"}</h3><p>{template?.description}</p></div><span className={`status ${response?.status||"draft"}`}>{response?.status==="submitted"?"Gönderildi":response?.status==="reviewed"?"İncelendi":"Taslak"}</span></div><div className="v6-anamnesis-grid">{anamnesisFields.map(([key,label,placeholder])=><label key={key}>{label}<textarea rows={3} value={answers[key]||""} onChange={e=>setAnswers({...answers,[key]:e.target.value})} placeholder={placeholder} readOnly={!clientMode}/></label>)}</div>{clientMode?<div className="form-actions"><button className="secondary-button" onClick={()=>saveAnamnesis(false)}><Save size={14}/>Taslak kaydet</button><button className="primary-button" onClick={()=>saveAnamnesis(true)}><Send size={14}/>Diyetisyene gönder</button></div>:clinical&&response?.status==="submitted"?<button className="primary-button" onClick={review}><ClipboardCheck size={15}/>İncelendi olarak işaretle</button>:null}</section>
      <section className="surface-card"><div className="surface-head"><div><span className="section-kicker">DİJİTAL ONAY</span><h3>Onam ve koşullar</h3><p>Her metin sürümü, kabul tarihi ve imza adıyla saklanır.</p></div><ShieldCheck size={24}/></div><div className="v6-consent-list">{consentTemplates.map(t=>{const row=consents.find(c=>c.template_id===t.id);return <article key={t.id} className={row?.accepted?"accepted":""}><div><b>{t.name}{t.is_required&&<em>Zorunlu</em>}</b><p>{t.body}</p>{row?.accepted_at&&<small>Kabul: {dateTime(row.accepted_at)}</small>}</div>{clientMode?<label className="v6-check"><input type="checkbox" checked={Boolean(row?.accepted)} onChange={e=>toggleConsent(t.id,e.target.checked)}/><span>{row?.accepted?"Kabul edildi":"Kabul et"}</span></label>:<span className={`status ${row?.accepted?"confirmed":"pending"}`}>{row?.accepted?"Kabul edildi":"Bekliyor"}</span>}</article>})}</div>{clientMode&&<div className="v6-consent-actions"><label>İmza adı soyadı<input value={signature} onChange={e=>setSignature(e.target.value)} placeholder="Ad Soyad"/></label><button className="primary-button" onClick={saveConsents}><FileCheck2 size={15}/>Onayları kaydet</button></div>}</section></div>}
  </>;
}

export function DocumentsV6({role,clinicId}:{role:Role;clinicId:string}){
  const supabase=useMemo(()=>createClient(),[]);const clientMode=role==="client";const [clients,setClients]=useState<ClientLite[]>([]);const [clientId,setClientId]=useState("");const [rows,setRows]=useState<DocumentRow[]>([]);const [loading,setLoading]=useState(true);const [uploading,setUploading]=useState(false);const [message,setMessage]=useState("");const fileRef=useRef<HTMLInputElement|null>(null);const [form,setForm]=useState({category:"laboratory",title:"",document_date:localDate(),notes:"",visible_to_client:true});
  const load=useCallback(async()=>{setLoading(true);try{let target="";if(clientMode)target=(await getOwnClientId(supabase,clinicId))||"";else{const {data,error}=await supabase.rpc("get_client_directory_v4");if(error)throw error;const list=(data||[]) as ClientLite[];setClients(list);target=clientId||list[0]?.id||"";}setClientId(target);if(target){const {data,error}=await supabase.from("client_documents").select("id,client_id,category,title,file_name,storage_path,mime_type,size_bytes,document_date,notes,visible_to_client,created_at").eq("client_id",target).order("created_at",{ascending:false});if(error)throw error;setRows((data||[]) as DocumentRow[])}}catch(error){setMessage(error instanceof Error?error.message:"Belgeler yüklenemedi.")}setLoading(false)},[clientId,clientMode,clinicId,supabase]);useEffect(()=>{void load()},[load]);
  async function switchClient(value:string){setClientId(value);setLoading(true);const {data,error}=await supabase.from("client_documents").select("id,client_id,category,title,file_name,storage_path,mime_type,size_bytes,document_date,notes,visible_to_client,created_at").eq("client_id",value).order("created_at",{ascending:false});if(error)setMessage(error.message);setRows((data||[]) as DocumentRow[]);setLoading(false)}
  async function upload(){const file=fileRef.current?.files?.[0];if(!file||!clientId)return setMessage("Dosya ve danışan seçin.");if(!form.title.trim())return setMessage("Belge başlığı girin.");setUploading(true);const {data:user}=await supabase.auth.getUser();if(!user.user){setUploading(false);return}const path=`${user.user.id}/${clientId}/${Date.now()}-${safeName(file.name)}`;const {error:storageError}=await supabase.storage.from("client-documents").upload(path,file,{contentType:file.type,upsert:false});if(storageError){setUploading(false);return setMessage(storageError.message)}const {error}=await supabase.from("client_documents").insert({clinic_id:clinicId,client_id:clientId,category:form.category,title:form.title.trim(),file_name:file.name,storage_path:path,mime_type:file.type||null,size_bytes:file.size,document_date:form.document_date||null,notes:form.notes||null,visible_to_client:clientMode?true:form.visible_to_client,uploaded_by:user.user.id});if(error){await supabase.storage.from("client-documents").remove([path]);setMessage(error.message)}else{setForm({category:"laboratory",title:"",document_date:localDate(),notes:"",visible_to_client:true});if(fileRef.current)fileRef.current.value="";setMessage("Belge güvenli dosyaya eklendi.");await load()}setUploading(false)}
  async function openDoc(row:DocumentRow){const {data,error}=await supabase.storage.from("client-documents").createSignedUrl(row.storage_path,120);if(error)return setMessage(error.message);window.open(data.signedUrl,"_blank","noopener,noreferrer")}
  async function remove(row:DocumentRow){if(!confirm("Belge silinsin mi?"))return;const {error}=await supabase.from("client_documents").delete().eq("id",row.id);if(error)return setMessage(error.message);await supabase.storage.from("client-documents").remove([row.storage_path]);await load()}
  const categories=[['laboratory','Laboratuvar'],['report','Rapor'],['prescription','Reçete'],['measurement','Ölçüm'],['meal_plan','Menü'],['consent','Onam'],['payment','Ödeme'],['administrative','İdari'],['photo','Fotoğraf'],['other','Diğer']];
  return <><PageHeader title="Belge Merkezi" description="Kan tahlili, reçete, rapor, ölçüm ve klinik evraklarını güvenli danışan dosyasında saklayın."/>{message&&<div className="notice-bar"><span>{message}</span><button onClick={()=>setMessage("")}><X size={15}/></button></div>}{!clientMode&&<section className="surface-card v6-client-select"><label>Danışan<select value={clientId} onChange={e=>switchClient(e.target.value)}>{clients.map(c=><option key={c.id} value={c.id}>{c.full_name} • {c.member_no}</option>)}</select></label></section>}
    <section className="surface-card v6-upload-card"><div><HardDriveUpload size={30}/><h3>Yeni belge yükle</h3><p>PDF, Word veya görsel dosyaları en fazla 15 MB.</p></div><div className="form-grid compact"><label>Başlık<input value={form.title} onChange={e=>setForm({...form,title:e.target.value})} placeholder="Örn. Temmuz kan tahlili"/></label><label>Kategori<select value={form.category} onChange={e=>setForm({...form,category:e.target.value})}>{categories.filter(([value])=>role!=="secretary"||['payment','administrative'].includes(value)).map(([value,label])=><option key={value} value={value}>{label}</option>)}</select></label><label>Belge tarihi<input type="date" value={form.document_date} onChange={e=>setForm({...form,document_date:e.target.value})}/></label><label>Dosya<input ref={fileRef} type="file" accept=".pdf,.docx,image/jpeg,image/png,image/webp"/></label><label className="wide">Not<input value={form.notes} onChange={e=>setForm({...form,notes:e.target.value})}/></label>{!clientMode&&<label className="v6-check"><input type="checkbox" checked={form.visible_to_client} onChange={e=>setForm({...form,visible_to_client:e.target.checked})}/><span>Danışan görebilsin</span></label>}</div><button className="primary-button" disabled={uploading} onClick={upload}>{uploading?<LoaderCircle className="spin" size={15}/>:<Upload size={15}/>}Yükle</button></section>
    {loading?<Loading/>:<div className="v6-document-grid">{rows.length===0?<Empty title="Belge yok" text="İlk belgeyi yükleyerek danışan dosyasını oluşturun." icon={<FileText size={32}/>} />:rows.map(row=><article className="surface-card" key={row.id}><div className="v6-doc-icon"><FileText size={23}/></div><div><span className="section-kicker">{categories.find(x=>x[0]===row.category)?.[1]||row.category}</span><h3>{row.title}</h3><p>{row.file_name}</p><small>{shortDate(row.document_date||row.created_at)} • {formatBytes(row.size_bytes)}{!row.visible_to_client&&" • Danışana kapalı"}</small></div><div className="v6-doc-actions"><button onClick={()=>openDoc(row)}><Download size={15}/>Aç</button><button className="icon-danger" onClick={()=>remove(row)}><Trash2 size={15}/></button></div></article>)}</div>}
  </>;
}

export function DirectMessagesV6({role,clinicId}:{role:Role;clinicId:string}){
  const supabase=useMemo(()=>createClient(),[]);const clientMode=role==="client";const [clients,setClients]=useState<ClientLite[]>([]);const [clientId,setClientId]=useState("");const [conversationId,setConversationId]=useState("");const [messages,setMessages]=useState<MessageRow[]>([]);const [profiles,setProfiles]=useState<Record<string,string>>({});const [body,setBody]=useState("");const [loading,setLoading]=useState(true);const [sending,setSending]=useState(false);const [message,setMessage]=useState("");const attachmentRef=useRef<HTMLInputElement|null>(null);const bottomRef=useRef<HTMLDivElement|null>(null);const [currentUserId,setCurrentUserId]=useState("");
  const openConversation=useCallback(async(target:string,viewerId=currentUserId)=>{if(!target)return;setLoading(true);setClientId(target);const {data:conversation,error}=await supabase.rpc("ensure_direct_conversation_v6",{p_client_id:target});if(error){setMessage(error.message);setLoading(false);return}const cid=conversation as string;setConversationId(cid);const {data,error:me}=await supabase.from("direct_messages").select("id,conversation_id,sender_user_id,body,attachment_path,attachment_name,attachment_type,read_at,created_at").eq("conversation_id",cid).order("created_at");if(me)setMessage(me.message);const rows=(data||[]) as MessageRow[];const ids=[...new Set(rows.map(x=>x.sender_user_id))];const {data:p}=ids.length?await supabase.from("profiles").select("id,full_name").in("id",ids):{data:[]};setProfiles(Object.fromEntries((p||[]).map((x:any)=>[x.id,x.full_name])));for(const row of rows){if(row.attachment_path){const {data:url}=await supabase.storage.from("direct-message-media").createSignedUrl(row.attachment_path,600);row.signed_url=url?.signedUrl}}setMessages(rows);if(viewerId)await supabase.from("direct_messages").update({read_at:new Date().toISOString()}).eq("conversation_id",cid).neq("sender_user_id",viewerId).is("read_at",null);setLoading(false);setTimeout(()=>bottomRef.current?.scrollIntoView({behavior:"smooth"}),50)},[currentUserId,supabase]);
  useEffect(()=>{(async()=>{const {data:user}=await supabase.auth.getUser();setCurrentUserId(user.user?.id||"");let target="";if(clientMode)target=(await getOwnClientId(supabase,clinicId))||"";else{const {data,error}=await supabase.rpc("get_client_directory_v4");if(error){setMessage(error.message);setLoading(false);return}const list=(data||[]) as ClientLite[];setClients(list);target=list[0]?.id||"";}if(target)await openConversation(target,user.user?.id||"");else setLoading(false)})()},[clientMode,clinicId,openConversation,supabase]);
  useEffect(()=>{if(!conversationId)return;const channel=supabase.channel(`direct-${conversationId}`).on("postgres_changes",{event:"INSERT",schema:"public",table:"direct_messages",filter:`conversation_id=eq.${conversationId}`},()=>void openConversation(clientId)).subscribe();return()=>{void supabase.removeChannel(channel)}},[clientId,conversationId,openConversation,supabase]);
  async function send(){if(!conversationId||(!body.trim()&&!attachmentRef.current?.files?.[0]))return;setSending(true);const file=attachmentRef.current?.files?.[0];let path:string|null=null;const {data:user}=await supabase.auth.getUser();if(!user.user){setSending(false);return}if(file){path=`${user.user.id}/${conversationId}/${Date.now()}-${safeName(file.name)}`;const {error}=await supabase.storage.from("direct-message-media").upload(path,file,{contentType:file.type});if(error){setMessage(error.message);setSending(false);return}}const {error}=await supabase.from("direct_messages").insert({conversation_id:conversationId,sender_user_id:user.user.id,body:body.trim()||null,attachment_path:path,attachment_name:file?.name||null,attachment_type:file?.type||null});if(error){if(path)await supabase.storage.from("direct-message-media").remove([path]);setMessage(error.message)}else{setBody("");if(attachmentRef.current)attachmentRef.current.value="";await openConversation(clientId)}setSending(false)}
  return <><PageHeader title="Özel Mesajlar" description="Danışan ve sorumlu diyetisyen arasında güvenli metin, fotoğraf ve belge iletişimi."/>{message&&<div className="notice-bar"><span>{message}</span><button onClick={()=>setMessage("")}><X size={15}/></button></div>}<section className={`surface-card v6-chat-shell ${clientMode?"client-mode":"staff-mode"}`}>{!clientMode&&<aside><span className="section-kicker">DANIŞANLAR</span>{clients.map(c=><button key={c.id} className={clientId===c.id?"active":""} onClick={()=>openConversation(c.id)}><span>{c.full_name.split(" ").map(x=>x[0]).slice(0,2).join("")}</span><div><b>{c.full_name}</b><small>{c.member_no}</small></div></button>)}</aside>}<div className="v6-chat-main"><header><MessageCircle size={20}/><div><b>{clientMode?"Diyetisyeninizle özel görüşme":clients.find(c=>c.id===clientId)?.full_name||"Danışan"}</b><small>Mesajlar yalnızca yetkili taraflarca görülür.</small></div></header><div className="v6-chat-messages">{loading?<Loading/>:messages.length===0?<Empty title="Henüz mesaj yok" text="İlk mesajı yazarak özel görüşmeyi başlatın." icon={<MessageCircle size={31}/>} />:messages.map(row=><article key={row.id} className={row.sender_user_id===currentUserId?"mine":"theirs"}><small>{profiles[row.sender_user_id]||"Kullanıcı"}</small>{row.body&&<p>{row.body}</p>}{row.signed_url&&<a href={row.signed_url} target="_blank" rel="noreferrer">{row.attachment_type?.startsWith("image/")?<img src={row.signed_url} alt={row.attachment_name||"Mesaj görseli"}/>:<><Paperclip size={15}/>{row.attachment_name||"Dosyayı aç"}</>}</a>}<time>{dateTime(row.created_at)}</time></article>)}<div ref={bottomRef}/></div><footer><label className="v6-attachment"><Paperclip size={18}/><input ref={attachmentRef} type="file" accept="image/*,.pdf,audio/*"/><span>Dosya</span></label><textarea rows={2} value={body} onChange={e=>setBody(e.target.value)} onKeyDown={e=>{if(e.key==="Enter"&&!e.shiftKey){e.preventDefault();void send()}}} placeholder="Mesajınızı yazın…"/><button className="primary-button" disabled={sending} onClick={send}>{sending?<LoaderCircle className="spin" size={17}/>:<Send size={17}/>}</button></footer></div></section></>;
}

export function FollowupV6({role,clinicId}:{role:Role;clinicId:string}){
  const supabase=useMemo(()=>createClient(),[]);const clientMode=role==="client";const clinical=roleIsClinical(role);const [clients,setClients]=useState<ClientLite[]>([]);const [clientId,setClientId]=useState("");const [score,setScore]=useState<Adherence|null>(null);const [tasks,setTasks]=useState<TaskRow[]>([]);const [loading,setLoading]=useState(true);const [message,setMessage]=useState("");const [taskForm,setTaskForm]=useState({title:"",description:"",task_type:"habit",due_date:"",points_reward:"0"});
  const loadClient=useCallback(async(target:string)=>{if(!target)return;setLoading(true);const [{data:a,error:ae},{data:t,error:te}]=await Promise.all([supabase.rpc("get_client_adherence_v6",{p_client_id:clientMode?null:target}),supabase.from("client_tasks").select("id,client_id,title,description,task_type,due_date,status,points_reward,completed_at,created_at").eq("client_id",target).order("created_at",{ascending:false})]);if(ae)setMessage(ae.message);else if(te)setMessage(te.message);setScore((a||null) as Adherence|null);setTasks((t||[]) as TaskRow[]);setLoading(false)},[clientMode,supabase]);
  useEffect(()=>{(async()=>{let target="";if(clientMode)target=(await getOwnClientId(supabase,clinicId))||"";else{const {data,error}=await supabase.rpc("get_client_directory_v4");if(error){setMessage(error.message);setLoading(false);return}const list=(data||[]) as ClientLite[];setClients(list);target=list[0]?.id||"";}setClientId(target);if(target)await loadClient(target);else setLoading(false)})()},[clientMode,clinicId,loadClient,supabase]);
  async function switchClient(value:string){setClientId(value);await loadClient(value)}
  async function addTask(){if(!clientId||!taskForm.title.trim())return setMessage("Görev başlığı girin.");const {data:user}=await supabase.auth.getUser();const {error}=await supabase.from("client_tasks").insert({clinic_id:clinicId,client_id:clientId,assigned_by:user.user?.id,title:taskForm.title.trim(),description:taskForm.description||null,task_type:taskForm.task_type,due_date:taskForm.due_date||null,points_reward:Number(taskForm.points_reward)||0});if(error)setMessage(error.message);else{setTaskForm({title:"",description:"",task_type:"habit",due_date:"",points_reward:"0"});setMessage("Görev danışana atandı.");await loadClient(clientId)}}
  async function setTaskStatus(id:string,status:string){const {error}=clientMode?await supabase.rpc("set_client_task_status_v6",{p_task_id:id,p_status:status}):await supabase.from("client_tasks").update({status,completed_at:status==="completed"?new Date().toISOString():null,updated_at:new Date().toISOString()}).eq("id",id);if(error)setMessage(error.message);else await loadClient(clientId)}
  const metrics=score?[['Randevu katılımı',score.attendance],['Menü takibi',score.meal_tracking],['Su takibi',score.water_tracking],['Aktivite',score.activity_tracking],['Görevler',score.tasks]]:[];
  return <><PageHeader title="Uyum ve Takip" description={clientMode?"Son 30 günlük alışkanlık, görev ve takip skorunuzu görün.":"Randevu, menü, su, aktivite ve görev verilerinden danışan uyumunu izleyin."}/>{message&&<div className="notice-bar"><span>{message}</span><button onClick={()=>setMessage("")}><X size={15}/></button></div>}{!clientMode&&<section className="surface-card v6-client-select"><label>Danışan<select value={clientId} onChange={e=>switchClient(e.target.value)}>{clients.map(c=><option key={c.id} value={c.id}>{c.full_name} • {c.member_no}</option>)}</select></label></section>}{loading?<Loading/>:<><div className="v6-adherence-layout"><section className={`surface-card v6-score-card ${score?.risk||"medium"}`}><div className="v6-score-ring" style={{"--score":`${score?.score||0}%`} as React.CSSProperties}><span><b>%{score?.score||0}</b><small>Uyum skoru</small></span></div><div><span className="section-kicker">SON {score?.period_days||30} GÜN</span><h3>{score?.risk==="low"?"Yüksek uyum":score?.risk==="medium"?"Takip gerekli":"Öncelikli takip"}</h3><p>{score?.risk==="low"?"Danışan plan ve takip adımlarında istikrarlı ilerliyor.":score?.risk==="medium"?"Bazı alışkanlıklarda düzenli destek faydalı olabilir.":"Düşük uyum alanları için erken iletişim önerilir."}</p></div></section><section className="surface-card v6-metric-bars"><div className="surface-head"><div><span className="section-kicker">BİLEŞENLER</span><h3>Skor kırılımı</h3></div><Gauge size={22}/></div>{metrics.map(([label,value])=><div key={label as string}><span><b>{label}</b><strong>%{value}</strong></span><div><i style={{width:`${value}%`}}/></div></div>)}</section></div>
      <div className="v6-two-column"><section className="surface-card"><div className="surface-head"><div><span className="section-kicker">GÖREVLER</span><h3>{clientMode?"Görevlerim":"Danışan görevleri"}</h3></div><ClipboardCheck size={22}/></div>{tasks.length===0?<Empty title="Görev yok" text={clientMode?"Diyetisyeniniz görev verdiğinde burada görünür.":"Danışana ilk takip görevini atayın."}/>:<div className="v6-task-list">{tasks.map(task=><article key={task.id} className={task.status}><button className="v6-task-check" disabled={!clientMode||task.status==="completed"} onClick={()=>setTaskStatus(task.id,"completed")}>{task.status==="completed"?<Check size={17}/>:null}</button><div><b>{task.title}</b><p>{task.description||"Açıklama yok"}</p><small>{task.due_date?`Son tarih: ${shortDate(task.due_date)}`:"Süresiz"}{task.points_reward?` • ${task.points_reward} puan`:""}</small></div><span className={`status ${task.status}`}>{task.status==="completed"?"Tamamlandı":task.status==="pending"?"Bekliyor":task.status}</span>{clinical&&task.status!=="cancelled"&&<button className="icon-danger" onClick={()=>setTaskStatus(task.id,"cancelled")}><X size={14}/></button>}</article>)}</div>}</section>{clinical&&<section className="surface-card"><div className="surface-head"><div><span className="section-kicker">YENİ GÖREV</span><h3>Takip adımı ata</h3></div><Plus size={22}/></div><div className="form-grid compact"><label>Başlık<input value={taskForm.title} onChange={e=>setTaskForm({...taskForm,title:e.target.value})} placeholder="Örn. 3 gün kahvaltı fotoğrafı"/></label><label>Tür<select value={taskForm.task_type} onChange={e=>setTaskForm({...taskForm,task_type:e.target.value})}><option value="water">Su</option><option value="activity">Aktivite</option><option value="meal_photo">Öğün fotoğrafı</option><option value="weight">Kilo ölçümü</option><option value="document">Belge yükleme</option><option value="habit">Alışkanlık</option><option value="other">Diğer</option></select></label><label>Son tarih<input type="date" value={taskForm.due_date} onChange={e=>setTaskForm({...taskForm,due_date:e.target.value})}/></label><label>Ödül puanı<input type="number" min="0" value={taskForm.points_reward} onChange={e=>setTaskForm({...taskForm,points_reward:e.target.value})}/></label><label className="wide">Açıklama<textarea rows={3} value={taskForm.description} onChange={e=>setTaskForm({...taskForm,description:e.target.value})}/></label></div><button className="primary-button" onClick={addTask}><Save size={15}/>Görevi ata</button></section>}</div></>}
  </>;
}

export function PwaInstallCard(){
  const [installEvent,setInstallEvent]=useState<Event|null>(null);const [installed,setInstalled]=useState(false);const [permission,setPermission]=useState<NotificationPermission|"unsupported">("unsupported");const [message,setMessage]=useState("");
  useEffect(()=>{setInstalled(window.matchMedia("(display-mode: standalone)").matches);setPermission("Notification" in window?Notification.permission:"unsupported");const handler=(event:Event)=>{event.preventDefault();setInstallEvent(event)};window.addEventListener("beforeinstallprompt",handler);return()=>window.removeEventListener("beforeinstallprompt",handler)},[]);
  async function install(){if(!installEvent)return setMessage("Tarayıcı uygulama yükleme seçeneğini henüz sunmuyor. Menüden ‘Ana ekrana ekle’yi kullanabilirsiniz.");const promptEvent=installEvent as Event&{prompt:()=>Promise<void>;userChoice:Promise<{outcome:string}>};await promptEvent.prompt();const choice=await promptEvent.userChoice;if(choice.outcome==="accepted")setInstalled(true);setInstallEvent(null)}
  async function enableNotifications(){if(!("Notification" in window))return;const result=await Notification.requestPermission();setPermission(result);if(result==="granted"){const registration=await navigator.serviceWorker.ready;const publicKey=process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY; if(publicKey&&registration.pushManager){const padding="=".repeat((4-publicKey.length%4)%4);const base64=(publicKey+padding).replace(/-/g,"+").replace(/_/g,"/");const raw=atob(base64);const key=new Uint8Array([...raw].map(char=>char.charCodeAt(0)));const subscription=await registration.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:key});const json=subscription.toJSON();const response=await fetch("/api/push/subscribe",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({endpoint:subscription.endpoint,keys:json.keys,userAgent:navigator.userAgent})});if(!response.ok){const payload=await response.json().catch(()=>({}));setMessage(payload.error||"Push aboneliği kaydedilemedi.");return;}}await registration.showNotification("NutriClinic AI bildirimleri açık",{body:"Randevu, ödeme ve menü güncellemelerini cihazınızda görebilirsiniz.",icon:"/icon.svg",badge:"/icon.svg"});}}
  return <section className="surface-card v6-pwa-card"><div><span className="v6-pwa-icon"><Smartphone size={25}/></span><div><span className="section-kicker">MOBİL UYGULAMA</span><h3>NutriClinic AI’yi cihazınıza kurun</h3><p>Ana ekrandan tam ekran açın; izin verdiğinizde menü, randevu ve ödeme bildirimlerini cihazınızda görün.</p></div></div><div>{installed?<span className="status confirmed"><CheckCircle2 size={14}/>Uygulama kurulu</span>:<button className="primary-button compact" onClick={install}><Download size={14}/>Uygulamayı kur</button>}{permission==="granted"?<span className="status confirmed"><BellRing size={14}/>Bildirimler açık</span>:permission!=="unsupported"?<button className="secondary-button compact" onClick={enableNotifications}><BellRing size={14}/>Bildirimleri aç</button>:null}</div>{message&&<small>{message}</small>}</section>;
}
