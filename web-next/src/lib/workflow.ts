import {ApiError,Context,gh} from "./api";
import {db} from "./db";
// 1.1.28: durasi_menit sengaja DIKELUARKAN dari `choices`. Workflow nyata
// mendeklarasikannya sebagai `type: string` (bukan choice), sehingga kontrak
// workflow-contract.ts dulu SELALU menolak repo asli dengan 409. Validasi
// angka dilakukan eksplisit di validate() di bawah.
export const choices:Record<string,string[]>={akses:["tailscale"],runner:["windows-2022","windows-2025","windows-latest"],microphone:["ya","tidak"],roblox:["ya","tidak"],minecraft_java:["ya","tidak"],minecraft_bedrock:["ya","tidak"],storage_boost:["ya","tidak"],debloat:["ringan","full","tidak"],runtimes:["auto","cepat","penuh"],samp:["ya","tidak"],win10:["ya","tidak"],xydesk:["ya","tidak"],ekstra:["ya","tidak"],grafis:["software","tidak"],discord:["ya","tidak"],fps_boost:["ya","tidak"],samp_antiban:["ya","tidak"],mumu:["ya","tidak"],perpanjang_otomatis:["ya","tidak"],linux_mode:["desktop","polos"]};
export const defaults:Record<string,string>={durasi_menit:"360",hostname:"rdpfree",rdp_user:"xyadmin",akses:"tailscale",runner:"windows-2022",microphone:"ya",roblox:"tidak",minecraft_java:"tidak",minecraft_bedrock:"tidak",storage_boost:"tidak",debloat:"ringan",runtimes:"auto",samp:"ya",win10:"tidak",xydesk:"ya",ekstra:"tidak",grafis:"tidak",discord:"tidak",fps_boost:"ya",samp_antiban:"tidak",mumu:"tidak",perpanjang_otomatis:"ya",linux_mode:"desktop"};
export function validate(raw:Record<string,unknown>){const inputs={...defaults};for(const [k,v] of Object.entries(raw)){if(["wallpaper","wallpaper_url","gta_sa_url","samp_extra","portmap_host","portmap_port"].includes(k))continue;if(!Object.prototype.hasOwnProperty.call(defaults,k)||typeof v!=="string")throw new ApiError(400,"Parameter tidak dikenal: "+k);inputs[k]=v;}
 for(const [k,allowed] of Object.entries(choices))if(!allowed.includes(inputs[k]))throw new ApiError(400,"Pilihan tidak valid: "+k);
 const durasi=Number(inputs.durasi_menit);if(!Number.isInteger(durasi)||durasi<10||durasi>360||!/^\d{1,3}$/.test(inputs.durasi_menit))throw new ApiError(400,"Durasi sesi harus 10–360 menit");
 if(!/^[a-zA-Z0-9][a-zA-Z0-9-]{0,29}$/.test(inputs.hostname))throw new ApiError(400,"Hostname harus 1–30 huruf, angka, atau tanda minus");
 if(!/^[a-zA-Z][a-zA-Z0-9_-]{2,19}$/.test(inputs.rdp_user)||/^(administrator|guest|defaultaccount|wdagutilityaccount|system|localservice|networkservice|con|prn|aux|nul)$/i.test(inputs.rdp_user))throw new ApiError(400,"Username RDP tidak valid");
 for(const k of ["gta_sa_url"]){if(inputs[k]){try{const u=new URL(inputs[k]);if(u.protocol!=="https:"||u.username||u.password||inputs[k].length>2000)throw Error();}catch{throw new ApiError(400,k+" harus URL HTTPS")}}}return inputs;}
export function migrateSettings(raw:Record<string,unknown>){
 const migrated={...raw};delete migrated.tunnel_provider;delete migrated.wallpaper;delete migrated.wallpaper_url;
 // 1.1.29: tunnel Tailscale only (arahan pemilik). Portmap/railway dihapus;
 //         nilai lama apa pun dinormalkan ke Tailscale.
 delete migrated.portmap_host;delete migrated.portmap_port;
 if(!choices.akses.includes(String(migrated.akses)))migrated.akses="tailscale";
 // Legacy labels are migrated to the real default image; no workflow starts on save.
 delete migrated.gta_sa_url;delete migrated.samp_extra;
 if(!("runner" in migrated)||["github","self-hosted"].includes(String(migrated.runner)))migrated.runner="windows-2022";
 return validate(migrated);
}
export async function loadSettings(repo:string){const r=await db().prepare("SELECT inputs FROM settings WHERE repo=?").bind(repo).first<{inputs:string}>();return r?migrateSettings(JSON.parse(r.inputs)):{...defaults};}
export type Run={id:number;run_attempt?:number;status:string;conclusion:string|null;created_at:string;run_started_at:string;html_url:string;name:string;workflow_id:number};
export async function runs(ctx:Context){return (await gh<{workflow_runs:Run[]}>(ctx,"/actions/workflows/rdp-6h.yml/runs?per_page=30")).workflow_runs;}
export const active=(r:Run)=>["queued","in_progress","waiting","requested","pending"].includes(r.status);
