import {getToken} from "next-auth/jwt";
import {NextRequest} from "next/server";
export async function GET(req:NextRequest){
 const token=await getToken({req,secret:process.env.NEXTAUTH_SECRET});
 const respond=(d:unknown,status=200)=>Response.json(d,{status,headers:{"Cache-Control":"private, no-store"}});
 if(!token?.accessToken||typeof token.login!=="string"||!/^[a-zA-Z0-9-]+$/.test(token.login))return respond({error:"Sesi tidak valid. Silakan masuk kembali."},401);
 const repo=token.login+"/XyRDP",view=req.nextUrl.searchParams.get("view");
 const path=view==="folder"?"/contents":view==="logs"?"/actions/runs?per_page=20":"";
 try{const r=await fetch("https://api.github.com/repos/"+repo+path,{headers:{Authorization:"Bearer "+token.accessToken,"User-Agent":"RdpFree","Accept":"application/vnd.github+json"},cache:"no-store"});
 if(r.status===404&&view==="home")return respond({repo,exists:false});
 if(!r.ok)return respond({error:r.status===401?"Akses GitHub kedaluwarsa. Silakan masuk kembali.":"GitHub belum dapat memuat data ("+r.status+")."},r.status===401?401:502);
 const d=await r.json();return respond({repo,exists:true,...(view==="folder"?{items:d}:view==="logs"?{runs:d.workflow_runs}:{})});
 }catch{return respond({error:"Koneksi ke GitHub gagal. Coba lagi."},502)}
}
