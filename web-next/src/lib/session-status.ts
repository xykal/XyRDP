// Workflow status is authoritative; a leftover status branch must never revive a stopped run.
export type SessionStats={ram_total_gb?:number;ram_used_gb?:number;ram_free_gb?:number;disk_total_gb?:number;disk_free_gb?:number;cpu_percent?:number;uptime_menit?:number;updated_at?:string};
export type SessionFile={run_id?:string|number;run_attempt?:string|number;active?:boolean;started_at?:string;expires_at?:string;heartbeat_at?:string;rdp_user?:string;hostname?:string;hardware?:{cpu_threads?:number;ram_gb?:number;disk_free_gb?:number};statistik?:SessionStats;games?:Record<string,unknown>;media?:Record<string,unknown>;game_environment?:Record<string,unknown>;akses?:{mode?:string;tailscale?:{ip?:string;status?:string;note?:string}}};
export type StatusRun={id:number;status:string;conclusion:string|null;run_attempt?:number};
export type JobStep={name:string;status:string;conclusion:string|null;number:number};
export type StatusJob={id:number;name:string;status:string;conclusion:string|null;steps?:JobStep[]};
const pending=["queued","waiting","requested","pending"];
const optionalStepRe=/^(Pulihkan sesi sebelumnya|Verifikasi dependensi|Toolkit grafis opsional|Setup grafis|Setup tampilan|Storage boost|Simpan sesi|Upload simpanan sesi|Finalize)/i;
export function sessionState(run:StatusRun|null,session:SessionFile|null,jobs:StatusJob[]=[],now=Date.now()){
 const running=run?.status==="in_progress",active=!!run&&(running||pending.includes(run.status));
 const matching=!!run&&String(session?.run_id)===String(run.id)&&(Number(session?.run_attempt||1)===Number(run.run_attempt||1));
 const steps=jobs.flatMap(j=>j.steps||[]).map(s=>({name:s.name,status:s.status,conclusion:s.conclusion,number:s.number}));
 const fatalFailure=steps.find((s,idx)=>{
  if(s.conclusion!=="failure"&&s.conclusion!=="timed_out")return false;
  if(optionalStepRe.test(s.name))return false;
  // If a later non-cleanup step is running or completed, this step had continue-on-error: true
  const laterActive=steps.slice(idx+1).some(nxt=>(nxt.status==="in_progress"||nxt.conclusion==="success")&&!/^(Simpan sesi|Upload simpanan|Finalize|Post )/i.test(nxt.name));
  return !laterActive;
 })||null;
 const current=!!(running&&matching&&session?.active&&Date.parse(session.expires_at||"")>now&&!fatalFailure);
 const ts=current?session?.akses?.tailscale:null;
 // Restrict the advertised RDP endpoint to a valid Tailscale IPv4 address.
 const parts=ts?.ip?.split(".").map(Number)||[];
 const validIP=parts.length===4&&parts.every(n=>Number.isInteger(n)&&n>=0&&n<=255)&&parts[0]===100&&parts[1]>=64&&parts[1]<=127;
 // 1.1.29: tunnel Tailscale only.
 const host=ts?.status==="ok"&&validIP?ts.ip:null;
 const phase=run?.status==="completed"?(run.conclusion==="success"?"stopped":run.conclusion==="cancelled"?"cancelled":"failed"):fatalFailure?"failed":pending.includes(run?.status||"")?"queued":current&&host?"ready":active?"preparing":"stopped";
 return {active,current,phase,connection:host?{host,port:3389,username:session?.rdp_user||"xyadmin",password_required:true,transport:"tailscale"}:null,progress:{current_step:steps.find(s=>s.status==="in_progress")?.name||null,failed_step:fatalFailure?.name||null,completed:steps.filter(s=>s.status==="completed").length,total:steps.length,steps}};
}
