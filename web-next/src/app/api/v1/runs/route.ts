import {NextRequest} from "next/server";
import {context,guarded,reply,origin,body,gh,ApiError} from "@/lib/api";
import {workflowCompatible} from "@/lib/workflow-contract";
import {inspect} from "@/lib/setup";
import {runs,active,validate,loadSettings} from "@/lib/workflow";
import {db,rateLimit} from "@/lib/db";
export async function GET(req:NextRequest){return guarded(async()=>{const c=await context(req);return reply({repo:c.repo,runs:await runs(c)})})}
export async function POST(req:NextRequest){return guarded(async()=>{const c=await context(req);if(c.kind!=="device")origin(req);
 const data=await body(req);if(data.confirm!==true)throw new ApiError(400,"Konfirmasi memulai workflow diperlukan");
 if(!await rateLimit("dispatch:"+c.repo,2,300))throw new ApiError(429,"Maksimum 2 percobaan run per 5 menit");
 const now=Date.now();const lock=await db().prepare("INSERT INTO locks(key,expires) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET expires=excluded.expires WHERE locks.expires<=? RETURNING key").bind("run:"+c.repo,now+90000,now).first();if(!lock)throw new ApiError(409,"Permintaan run lain sedang diproses");
 // Lock expires after 90 seconds even if the dispatch response is lost, to prevent double starts.
 if((await runs(c)).some(active))throw new ApiError(409,"Masih ada run aktif atau antre");
 const setup=await inspect(c);if(setup.workflow_exists&&!setup.workflow_compatible)throw new ApiError(409,"Workflow repository belum sesuai dashboard. Sinkronkan workflow, scripts, dan assets dari xykal/XyRDP.");if(!setup.ready)throw new ApiError(400,"Selesaikan Setup repository, Actions, dan secrets terlebih dahulu");
 const inputs=await loadSettings(c.repo);const valid=validate(inputs);
 const repo=await gh<{default_branch:string;permissions?:{push?:boolean}}>(c,"");if(!c.installationId&&!repo.permissions?.push)throw new ApiError(403,"Akses write ke repository diperlukan");
 const workflow=await gh<{content:string}>(c,"/contents/.github/workflows/rdp-6h.yml?ref="+encodeURIComponent(repo.default_branch));
 if(!workflowCompatible(Buffer.from(workflow.content,"base64").toString("utf8")))throw new ApiError(409,"Repository masih memakai workflow lama. Sinkronkan workflow, scripts, dan assets dari xykal/XyRDP sebelum memulai; App tidak punya izin menulis source.");
 // 1.1.29: tunnel Tailscale only — tidak ada lagi validasi endpoint publik.
 const secrets=await gh<{secrets:{name:string}[]}>(c,"/actions/secrets?per_page=100");const names=secrets.secrets.map(s=>s.name);
 const required=["RDP_PASSWORD","TAILSCALE_AUTH_KEY"];
 const missing=required.filter(k=>!names.includes(k));if(missing.length)throw new ApiError(400,"Secret belum lengkap: "+missing.join(", "));
 await gh(c,"/actions/workflows/rdp-6h.yml/dispatches","POST",{ref:repo.default_branch,inputs:valid});return reply({ok:true,repo:c.repo,inputs:valid,message:"Workflow diterima GitHub. Status akan muncul setelah antre."},202);
 })}
