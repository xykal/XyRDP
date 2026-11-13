const sections=new Set(['','connection','setup','folder','settings','logs','devices']);
export function dashboardRoute(path:string,login:string|null,admin=false):{kind:'redirect'|'rewrite';path:string}|{kind:'next'|'reject'|'login'}{
 if(path!=='/dashboard'&&!path.startsWith('/dashboard/'))return {kind:'next'};
 const parts=path.slice('/dashboard'.length).split('/').filter(Boolean).map(v=>{try{return decodeURIComponent(v)}catch{return '!invalid'}});
 if(!login&&!admin)return {kind:'login'};
 if(parts[0]?.startsWith('@')){
  if(!login||!/^\@[A-Za-z0-9-]{1,39}$/.test(parts[0])||parts[0].slice(1).toLowerCase()!==login.toLowerCase()||parts.length>2||!sections.has(parts[1]||''))return {kind:'reject'};
  return {kind:'rewrite',path:'/dashboard'+(parts[1]?'/'+parts[1]:'')};
 }
 if(admin)return {kind:'next'};
 if(!login||! /^[A-Za-z0-9-]{1,39}$/.test(login)||parts.length>1||!sections.has(parts[0]||''))return {kind:'reject'};
 return {kind:'redirect',path:'/dashboard/@'+login+(parts[0]?'/'+parts[0]:'')};
}
export function plainDashboardPath(path:string){return path.replace(/^\/dashboard\/@[^/]+(?=\/|$)/,'/dashboard')}
